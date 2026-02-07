//
//  RecordingController.swift
//  Stori
//
//  Manages audio/MIDI recording, input monitoring, and microphone permissions.
//  Extracted from AudioEngine for better separation of concerns.
//
//  ARCHITECTURE: Beats-First
//  - Recording start position is stored in beats (musical time)
//  - Audio duration from file is converted to beats when creating regions
//
//  REAL-TIME SAFETY: Input level metering uses `os_unfair_lock` protected storage.
//  The audio tap callback writes levels with lock (never blocks), and the main thread
//  reads via public property with lock. This avoids `DispatchQueue.main.async` which
//  can cause priority inversion and audio dropouts when the main thread is busy.
//
//  This pattern matches `AutomationProcessor`, `RecordingBufferPool`, `TrackAudioNode`, and `MeteringService`.
//

import Foundation
import AVFoundation
import AVKit
import os.lock

/// Recording controller manages audio input capture, file writing, and input monitoring.
/// It coordinates with AudioEngine via callbacks for graph modifications and project updates.
///
/// REAL-TIME SAFETY: Uses `os_unfair_lock` for thread-safe access to input level.
/// Audio tap writes with lock, main thread reads with lock - no dispatch required.
@Observable
@MainActor
final class RecordingController: @unchecked Sendable {
    
    // MARK: - Thread Safety
    
    /// Lock for thread-safe access to input level between audio and main threads.
    @ObservationIgnored
    private var inputLevelLock = os_unfair_lock_s()
    
    /// Internal storage for input level (protected by inputLevelLock)
    @ObservationIgnored
    private var _inputLevel: Float = 0.0
    
    // MARK: - Observable State
    var isRecording: Bool = false
    
    /// Real-time input level for UI metering (thread-safe read)
    var inputLevel: Float {
        get {
            os_unfair_lock_lock(&inputLevelLock)
            defer { os_unfair_lock_unlock(&inputLevelLock) }
            return _inputLevel
        }
        set {
            os_unfair_lock_lock(&inputLevelLock)
            _inputLevel = newValue
            os_unfair_lock_unlock(&inputLevelLock)
        }
    }
    
    // MARK: - Recording Properties
    @ObservationIgnored
    private var recordingFile: AVAudioFile?
    @ObservationIgnored
    private var recordingStartBeat: Double = 0
    @ObservationIgnored
    private var recordingTrackId: UUID?
    @ObservationIgnored
    private var inputMonitoringEnabled: Bool = true
    @ObservationIgnored
    private var recordingWriterQueue: DispatchQueue?
    @ObservationIgnored
    private var mixerPullTapInstalled: Bool = false
    @ObservationIgnored
    private var recordingSilentPlayer: AVAudioPlayerNode?
    @ObservationIgnored
    private var recordingFirstBufferReceived: Bool = false
    
    /// Pre-allocated buffer pool for real-time safe recording
    @ObservationIgnored
    private var recordingBufferPool: RecordingBufferPool?
    
    // MARK: - Count-In Recording State
    @ObservationIgnored
    private var countInRecordingPrepared: Bool = false
    @ObservationIgnored
    private var countInRecordingFile: AVAudioFile?
    @ObservationIgnored
    private var countInRecordingURL: URL?
    @ObservationIgnored
    private var countInRecordTrack: AudioTrack?
    
    // MARK: - Dependencies
    @ObservationIgnored
    private var engine: AVAudioEngine
    @ObservationIgnored
    private var mixer: AVAudioMixerNode
    @ObservationIgnored
    private weak var transportController: TransportController?  // NEW: For thread-safe position
    @ObservationIgnored
    private var getProject: () -> AudioProject?
    @ObservationIgnored
    private var getCurrentPosition: () -> PlaybackPosition
    @ObservationIgnored
    private var getSelectedTrackId: () -> UUID?
    @ObservationIgnored
    private var onStartRecordingMode: () -> Void
    @ObservationIgnored
    private var onStopRecordingMode: () -> Void
    @ObservationIgnored
    private var onStopPlayback: () -> Void
    @ObservationIgnored
    private var onProjectUpdated: (AudioProject) -> Void
    @ObservationIgnored
    private var onReconnectMetronome: () -> Void
    @ObservationIgnored
    private var loadProject: (AudioProject) -> Void
    
    // MARK: - Initialization
    
    init(
        engine: AVAudioEngine,
        mixer: AVAudioMixerNode,
        transportController: TransportController,  // NEW: For thread-safe position
        getProject: @escaping () -> AudioProject?,
        getCurrentPosition: @escaping () -> PlaybackPosition,
        getSelectedTrackId: @escaping () -> UUID?,
        onStartRecordingMode: @escaping () -> Void,
        onStopRecordingMode: @escaping () -> Void,
        onStopPlayback: @escaping () -> Void,
        onProjectUpdated: @escaping (AudioProject) -> Void,
        onReconnectMetronome: @escaping () -> Void,
        loadProject: @escaping (AudioProject) -> Void
    ) {
        self.engine = engine
        self.mixer = mixer
        self.transportController = transportController  // NEW
        self.getProject = getProject
        self.getCurrentPosition = getCurrentPosition
        self.getSelectedTrackId = getSelectedTrackId
        self.onStartRecordingMode = onStartRecordingMode
        self.onStopRecordingMode = onStopRecordingMode
        self.onStopPlayback = onStopPlayback
        self.onProjectUpdated = onProjectUpdated
        self.onReconnectMetronome = onReconnectMetronome
        self.loadProject = loadProject
    }
    
    nonisolated deinit {}
    
    // MARK: - Helpers
    
    /// Sanitize a track name for safe use in filenames
    /// Removes path traversal characters and invalid filename characters
    private func sanitizeTrackNameForFilename(_ name: String) -> String {
        // Remove path separators and parent directory references
        var sanitized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "..", with: "")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        
        // Remove any remaining characters that are problematic for filenames
        let invalidChars = CharacterSet(charactersIn: "<>:\"|?*\0")
        sanitized = sanitized.components(separatedBy: invalidChars).joined()
        
        // Ensure non-empty name
        return sanitized.isEmpty ? "Track" : sanitized
    }
    
    // MARK: - Public Recording API
    
    /// Prepare everything for recording during count-in
    func prepareRecordingDuringCountIn() async {
        guard let project = getProject() else {
            AppLogger.shared.debug("[REC] prepareRecordingDuringCountIn: no project", category: .audio)
            return
        }
        
        let recordTrack = findOrCreateRecordTrack(in: project)
        countInRecordTrack = recordTrack
        AppLogger.shared.debug("[REC] prepareRecordingDuringCountIn: track=\(recordTrack.name) isMIDI=\(recordTrack.isMIDITrack)", category: .audio)
        
        // MIDI tracks don't need mic permission or audio file setup
        if recordTrack.isMIDITrack {
            AppLogger.shared.debug("[REC] prepareRecordingDuringCountIn: MIDI track, marking prepared", category: .audio)
            countInRecordingPrepared = true
            return
        }
        
        // Audio recording: request microphone permission
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            requestMicPermission { _ in
                continuation.resume()
            }
        }
        
        // 3. Create recording file (this is the slow part - 170ms!)
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        let trackName = sanitizeTrackNameForFilename(recordTrack.name)
        let recordingURL = documentsPath.appendingPathComponent("Recording_\(trackName)_\(timestamp).wav")
        countInRecordingURL = recordingURL
        
        do {
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            countInRecordingFile = try AVAudioFile(forWriting: recordingURL, settings: inputFormat.settings)
        } catch {
            // Recording file creation failed
        }
        
        // 4. Pre-attach silent player
        startSilentPlayerForRecording()
        
        countInRecordingPrepared = true
    }
    
    /// Start recording after count-in — everything is already prepared
    /// Records from the current playhead position (Logic Pro behavior)
    func startRecordingAfterCountIn() {
        AppLogger.shared.debug("[REC] startRecordingAfterCountIn: countInRecordingPrepared=\(countInRecordingPrepared) hasProject=\(getProject() != nil)", category: .audio)
        guard countInRecordingPrepared, let project = getProject() else {
            AppLogger.shared.debug("[REC] startRecordingAfterCountIn: guard failed, falling back to record()", category: .audio)
            record()
            return
        }
        guard let transport = transportController else {
            AppLogger.shared.debug("[REC] startRecordingAfterCountIn: no transport, falling back to record()", category: .audio)
            record()
            return
        }
        
        // Record from current playhead position (Logic Pro behavior)
        let startBeat = getCurrentPosition().beats
        AppLogger.shared.debug("[REC] startRecordingAfterCountIn: startBeat=\(startBeat) transportState=\(transport.transportState)", category: .audio)
        
        isRecording = true
        recordingStartBeat = startBeat
        recordingTrackId = countInRecordTrack?.id
        
        // Start MIDI recording for armed MIDI tracks
        let recordEnabledTracks = project.tracks.filter { $0.mixerSettings.isRecordEnabled }
        if let firstMIDITrack = recordEnabledTracks.first(where: { $0.isMIDITrack }) {
            AppLogger.shared.debug("[REC] startRecordingAfterCountIn: starting MIDI recording for track \(firstMIDITrack.id) at beat \(startBeat)", category: .audio)
            InstrumentManager.shared.startRecording(trackId: firstMIDITrack.id, atBeats: startBeat)
        }
        
        // Install audio input tap before starting transport
        if let recordTrack = countInRecordTrack, !recordTrack.isMIDITrack {
            installInputTapForCountIn()
        }
        
        // Start transport from current position
        AppLogger.shared.debug("[REC] startRecordingAfterCountIn: calling transport.play() (transportState=\(transport.transportState))", category: .audio)
        transport.play()
        AppLogger.shared.debug("[REC] startRecordingAfterCountIn: transport.play() returned, currentBeat=\(getCurrentPosition().beats) transportState=\(transport.transportState)", category: .audio)
        onStartRecordingMode()
        
        countInRecordingPrepared = false
    }
    
    /// Start recording (standard entry point)
    func record() {
        guard !isRecording else { return }
        guard let project = getProject() else { return }
        guard let transport = transportController else { return }
        
        let recordTrack = findOrCreateRecordTrack(in: project)
        
        isRecording = true
        recordingTrackId = recordTrack.id
        recordingStartBeat = getCurrentPosition().beats
        
        if recordTrack.isMIDITrack {
            // MIDI recording: no microphone needed — start transport directly
            InstrumentManager.shared.startRecording(trackId: recordTrack.id, atBeats: recordingStartBeat)
            transport.play()
            onStartRecordingMode()
        } else {
            // Audio recording: request microphone permission, then set up input taps
            requestMicPermission { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.setupAudioRecording()
                    } else {
                        self?.stopRecording()
                    }
                }
            }
        }
    }
    
    /// Stop recording
    func stopRecording() {
        AppLogger.shared.debug("[REC] stopRecording: isRecording=\(isRecording) currentBeat=\(getCurrentPosition().beats)", category: .audio)
        guard isRecording else { return }
        
        // Stop MIDI recording and capture the region (already on MainActor)
        let instrumentManager = InstrumentManager.shared
        let recordingId = instrumentManager.recordingTrackId
        if let midiRegion = instrumentManager.stopRecording(),
           let trackId = recordingId {
            instrumentManager.projectManager?.addMIDIRegion(midiRegion, to: trackId)
        }
        
        stopRecordingInternal()
        AppLogger.shared.debug("[REC] stopRecording: calling onStopRecordingMode → transport.stopRecordingMode()", category: .audio)
        onStopRecordingMode()
        isRecording = false
        inputLevel = 0.0
        AppLogger.shared.debug("[REC] stopRecording: calling onStopPlayback", category: .audio)
        onStopPlayback()
    }
    
    // MARK: - Private Recording Implementation
    
    private func requestMicPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { result in
            completion(result)
        }
    }
    
    /// Set up audio input recording (called after mic permission is granted)
    private func setupAudioRecording() {
        guard let project = getProject() else { return }
        guard let transport = transportController else { return }
        
        do {
            let recordTrack = findOrCreateRecordTrack(in: project)
            recordingTrackId = recordTrack.id
            
            // Create recording file URL
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let timestamp = dateFormatter.string(from: Date())
            let trackName = sanitizeTrackNameForFilename(recordTrack.name)
            let recordingURL = documentsPath.appendingPathComponent("Recording_\(trackName)_\(timestamp).wav")
            
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            
            recordingFile = try AVAudioFile(forWriting: recordingURL, settings: inputFormat.settings)
            
            // High-priority writer queue — recording I/O must complete quickly
            // to prevent buffer pool exhaustion
            let writerQueue = DispatchQueue(label: "com.stori.recording.writer", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
            recordingWriterQueue = writerQueue
            
            // Pre-allocate buffer pool (system may deliver buffers larger than tap size)
            let bufferPool = RecordingBufferPool(
                format: inputFormat,
                frameCapacity: AudioConstants.recordingMaxFrameCapacity,
                poolSize: AudioConstants.recordingPoolSize
            )
            recordingBufferPool = bufferPool
            
            startSilentPlayerForRecording()
            
            // Reset first buffer flag for accurate start beat capture
            recordingFirstBufferReceived = false
            
            // Install input tap
            inputNode.installTap(onBus: 0, bufferSize: AudioConstants.recordingTapBufferSize, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self else { return }
                
                // Capture exact recording start beat on FIRST buffer arrival
                // for sample-accurate alignment with timeline
                if !self.recordingFirstBufferReceived {
                    self.recordingFirstBufferReceived = true
                    if let transport = self.transportController {
                        self.recordingStartBeat = transport.atomicBeatPosition
                    } else {
                        self.recordingStartBeat = 0.0
                        DispatchQueue.global(qos: .utility).async {
                            AppLogger.shared.error("TransportController unavailable during recording", category: .audio)
                        }
                    }
                }
                
                guard let bufferCopy = bufferPool.acquireAndCopy(from: buffer) else { return }
                
                // Calculate RMS for metering
                var rms: Float = 0.0
                if let ch0 = buffer.floatChannelData?[0] {
                    let frameCount = Int(buffer.frameLength)
                    var sum: Float = 0.0
                    for i in 0..<frameCount {
                        let sample = ch0[i]
                        sum += sample * sample
                    }
                    rms = sqrt(sum / Float(max(1, frameCount)))
                }
                
                guard let file = recordingFile else {
                    bufferPool.release(bufferCopy)
                    return
                }
                
                // Write to file on background queue
                writerQueue.async { [weak self] in
                    guard let self = self else {
                        bufferPool.release(bufferCopy)
                        return
                    }
                    defer { bufferPool.release(bufferCopy) }
                    
                    do {
                        try file.write(from: bufferCopy)
                        if bufferPool.incrementWriteCount() {
                            if let fileHandle = FileHandle(forWritingAtPath: file.url.path) {
                                try? fileHandle.synchronize()
                            }
                        }
                    } catch {
                        AppLogger.shared.error("Failed to write recording buffer: \(error)", category: .audio)
                    }
                }
                
                // Write input level with lock — real-time safe, no dispatch to main thread
                let amplifiedLevel = rms * 8.0
                os_unfair_lock_lock(&self.inputLevelLock)
                self._inputLevel = amplifiedLevel
                os_unfair_lock_unlock(&self.inputLevelLock)
            }
            
            if inputMonitoringEnabled {
                setupInputMonitoring()
            }
            
            if !engine.isRunning {
                try engine.start()
            }
            
            // Start transport — tap is already installed so we capture from beat 0
            transport.stop()
            transport.play()
            onStartRecordingMode()
            
        } catch {
            stopRecording()
        }
    }
    
    private func installInputTapForCountIn() {
        guard let recordFile = countInRecordingFile,
              let recordTrack = countInRecordTrack else { return }
        
        recordingTrackId = recordTrack.id
        recordingFile = recordFile
        
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Create dedicated writer queue with HIGH priority (BUG FIX Issue #55)
        let writerQueue = DispatchQueue(label: "com.stori.recording.writer", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
        recordingWriterQueue = writerQueue
        
        // Pre-allocate buffer pool with recording max frame capacity
        // System may deliver buffers larger than requested tap size (e.g., 4800 frames at 48kHz)
        let bufferPool = RecordingBufferPool(
            format: inputFormat,
            frameCapacity: AudioConstants.recordingMaxFrameCapacity,
            poolSize: AudioConstants.recordingPoolSize
        )
        recordingBufferPool = bufferPool
        
        // Reset first buffer flag for accurate start beat capture
        recordingFirstBufferReceived = false
        
        inputNode.installTap(onBus: 0, bufferSize: AudioConstants.recordingTapBufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // CRITICAL: Capture exact recording start beat on FIRST buffer arrival
            // This ensures sample-accurate alignment with timeline
            // REAL-TIME SAFE: Use atomic position accessor from TransportController
            if !self.recordingFirstBufferReceived {
                self.recordingFirstBufferReceived = true
                // REAL-TIME SAFETY: Thread-safe read from atomic position
                // No fallback - transportController must always be available for recording
                if let transport = self.transportController {
                    self.recordingStartBeat = transport.atomicBeatPosition
                } else {
                    // CRITICAL: TransportController missing - use safe default (0.0)
                    // This should never happen in production - log error off-thread
                    self.recordingStartBeat = 0.0
                    DispatchQueue.global(qos: .utility).async {
                        AppLogger.shared.error("TransportController unavailable during count-in recording", category: .audio)
                    }
                }
            }
            
            guard let bufferCopy = bufferPool.acquireAndCopy(from: buffer) else { return }
            
            var rms: Float = 0.0
            if let ch0 = buffer.floatChannelData?[0] {
                let frameCount = Int(buffer.frameLength)
                var sum: Float = 0.0
                for i in 0..<frameCount {
                    let sample = ch0[i]
                    sum += sample * sample
                }
                rms = sqrt(sum / Float(max(1, frameCount)))
            }
            
            // Capture file reference before async to avoid Sendable crossing actor boundaries
            guard let file = recordingFile else {
                bufferPool.release(bufferCopy)
                return
            }
            
            writerQueue.async { [weak self] in
                guard let self = self else {
                    bufferPool.release(bufferCopy)
                    return
                }
                // CRITICAL FIX: Release buffer in defer to prevent memory leak on write errors
                defer {
                    bufferPool.release(bufferCopy)
                }
                
                do {
                    try file.write(from: bufferCopy)
                    if bufferPool.incrementWriteCount() {
                        if let fileHandle = FileHandle(forWritingAtPath: file.url.path) {
                            try? fileHandle.synchronize()
                        }
                    }
                } catch {
                    // Log error but continue - buffer is released by defer
                    AppLogger.shared.error("Failed to write recording buffer: \(error)", category: .audio)
                }
            }
            
            // REAL-TIME SAFE: Write input level directly with lock - no dispatch to main thread.
            // os_unfair_lock is designed for this exact use case (minimal overhead, no priority inversion).
            let amplifiedLevel = rms * 8.0
            os_unfair_lock_lock(&self.inputLevelLock)
            self._inputLevel = amplifiedLevel
            os_unfair_lock_unlock(&self.inputLevelLock)
        }
        
        if inputMonitoringEnabled {
            setupInputMonitoring()
        }
    }
    
    // MARK: - Silent Player (for graph rendering during recording)
    
    private func startSilentPlayerForRecording() {
        let silentPlayer = AVAudioPlayerNode()
        recordingSilentPlayer = silentPlayer
        
        let wasRunning = engine.isRunning
        if wasRunning {
            engine.pause()
        }
        
        engine.attach(silentPlayer)
        let format = mixer.outputFormat(forBus: 0)
        engine.connect(silentPlayer, to: mixer, format: format)
        
        onReconnectMetronome()
        
        if wasRunning {
            do {
                try engine.start()
            } catch {}
        }
        
        guard let silentBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else {
            return
        }
        silentBuffer.frameLength = silentBuffer.frameCapacity
        
        if let channelData = silentBuffer.floatChannelData {
            for ch in 0..<Int(format.channelCount) {
                memset(channelData[ch], 0, Int(silentBuffer.frameLength) * MemoryLayout<Float>.size)
            }
        }
        
        silentPlayer.scheduleBuffer(silentBuffer, at: nil, options: .loops)
        silentPlayer.play()
    }
    
    private func stopSilentPlayerForRecording() {
        guard let silentPlayer = recordingSilentPlayer else { return }
        
        silentPlayer.stop()
        engine.disconnectNodeOutput(silentPlayer)
        engine.detach(silentPlayer)
        recordingSilentPlayer = nil
    }
    
    // MARK: - Input Monitoring
    
    private func setupInputMonitoring() {
        let inputNode = engine.inputNode
        engine.connect(inputNode, to: mixer, format: nil)
    }
    
    private func teardownInputMonitoring() {
        let connections = engine.outputConnectionPoints(for: engine.inputNode, outputBus: 0)
        if connections.count > 0 {
            engine.disconnectNodeOutput(engine.inputNode)
        }
    }
    
    // MARK: - Track Finding
    
    private func findOrCreateRecordTrack(in project: AudioProject) -> AudioTrack {
        // 1. Find explicitly record-enabled track
        if let recordTrack = project.tracks.first(where: { $0.mixerSettings.isRecordEnabled }) {
            return recordTrack
        }
        
        // 2. Record to currently selected track
        if let selectedId = getSelectedTrackId(),
           let selectedTrack = project.tracks.first(where: { $0.id == selectedId }),
           selectedTrack.trackType == .audio {
            return selectedTrack
        }
        
        // 3. Find first audio track
        if let audioTrack = project.tracks.first(where: { $0.trackType == .audio }) {
            return audioTrack
        }
        
        // 4. Return first track or create new one
        return project.tracks.first ?? AudioTrack(name: "Audio 1", trackType: .audio)
    }
    
    // MARK: - Stop Recording Internal
    
    private func stopRecordingInternal() {
        guard let recordingFile = recordingFile,
              let recordingTrackId = recordingTrackId else { return }
        
        stopSilentPlayerForRecording()
        engine.inputNode.removeTap(onBus: 0)
        
        let recordingURL = recordingFile.url
        let recordingFormat = recordingFile.processingFormat
        let startBeat = self.recordingStartBeat
        
        // Wait for pending writes
        if let writerQueue = recordingWriterQueue {
            writerQueue.sync {}
        }
        recordingWriterQueue = nil
        
        if inputMonitoringEnabled {
            teardownInputMonitoring()
        }
        
        // Clear all references
        self.recordingFile = nil
        self.countInRecordingFile = nil
        self.countInRecordTrack = nil
        self.countInRecordingURL = nil
        self.recordingStartBeat = 0
        self.recordingTrackId = nil
        
        // Finalize file and create region on background queue
        let getProjectCopy = getProject
        let onProjectUpdatedCopy = onProjectUpdated
        let loadProjectCopy = loadProject
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard self != nil else { return }
            
            // Ensure file data is fully flushed to disk
            // This is more reliable than polling for file readiness
            do {
                if let fileHandle = FileHandle(forWritingAtPath: recordingURL.path) {
                    try fileHandle.synchronize()
                    try fileHandle.close()
                }
            } catch {
                AppLogger.shared.warning("Recording: File sync warning - \(error.localizedDescription)", category: .audio)
            }
            
            // Quick verification with minimal polling (file should already be ready)
            var attempts = 0
            let maxAttempts = 5
            var fileReady = false
            
            while attempts < maxAttempts && !fileReady {
                if attempts > 0 {
                    Thread.sleep(forTimeInterval: 0.05)  // 50ms between attempts
                }
                attempts += 1
                
                guard FileManager.default.fileExists(atPath: recordingURL.path) else { continue }
                
                do {
                    let _ = try AVAudioFile(forReading: recordingURL)
                    fileReady = true
                } catch {
                    continue
                }
            }
            
            guard fileReady else {
                AppLogger.shared.error("Recording: File not ready after sync - \(recordingURL.lastPathComponent)", category: .audio)
                return
            }
            
            var fileSize: Int64 = 0
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: recordingURL.path)
                fileSize = attributes[.size] as? Int64 ?? 0
            } catch { return }
            
            // Calculate duration
            let estimatedHeaderSize: Int64 = 78
            let dataBytes = max(0, fileSize - estimatedHeaderSize)
            let bytesPerFrame = recordingFormat.streamDescription.pointee.mBytesPerFrame
            let frameCount = Int64(dataBytes) / Int64(bytesPerFrame)
            let actualDuration = Double(frameCount) / recordingFormat.sampleRate
            
            guard actualDuration > 0 else { return }
            
            do {
                let audioFile = AudioFile(
                    name: recordingURL.deletingPathExtension().lastPathComponent,
                    url: recordingURL,
                    duration: actualDuration,
                    sampleRate: recordingFormat.sampleRate,
                    channels: Int(recordingFormat.channelCount),
                    bitDepth: 16,
                    fileSize: Int64(try recordingURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0),
                    format: .wav
                )
                
                // Get tempo for duration conversion (audio duration is in seconds)
                let tempo = getProjectCopy()?.tempo ?? 120.0
                // startBeat is already in beats from recordingStartBeat
                // Convert recorded audio duration from seconds to beats
                let durationBeats = actualDuration * (tempo / 60.0)
                
                let audioRegion = AudioRegion(
                    audioFile: audioFile,
                    startBeat: startBeat,
                    durationBeats: durationBeats,
                    tempo: tempo,
                    fadeIn: 0,
                    fadeOut: 0,
                    gain: 1.0,
                    isLooped: false,
                    offset: 0
                )
                
                DispatchQueue.main.async {
                    guard var project = getProjectCopy() else { return }
                    
                    if let trackIndex = project.tracks.firstIndex(where: { $0.id == recordingTrackId }) {
                        project.tracks[trackIndex].regions.append(audioRegion)
                        project.modifiedAt = Date()
                        onProjectUpdatedCopy(project)
                        
                        NotificationCenter.default.post(name: .projectUpdated, object: project)
                        NotificationCenter.default.post(name: .saveProject, object: nil)
                        
                    loadProjectCopy(project)
                }
            }
            } catch {}
        }
    }
    
    // MARK: - Cleanup
}
