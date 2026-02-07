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
@preconcurrency import AVFoundation
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
    private var onStartPlayback: () -> Void
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
        onStartPlayback: @escaping () -> Void,
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
        self.onStartPlayback = onStartPlayback
        self.onStopPlayback = onStopPlayback
        self.onProjectUpdated = onProjectUpdated
        self.onReconnectMetronome = onReconnectMetronome
        self.loadProject = loadProject
    }
    
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
        guard let project = getProject() else { return }
        
        // 1. Request microphone permission
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            requestMicPermission { _ in
                continuation.resume()
            }
        }
        
        // 2. Find record track
        let recordTrack = findOrCreateRecordTrack(in: project)
        countInRecordTrack = recordTrack
        
        // Skip audio file creation for MIDI tracks
        if recordTrack.isMIDITrack {
            countInRecordingPrepared = true
            return
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
    
    /// Start recording after count-in - everything is already prepared
    func startRecordingAfterCountIn() {
        guard countInRecordingPrepared, let project = getProject() else {
            record()
            return
        }
        
        // CRITICAL FIX (Issue #120): Start transport properly BEFORE starting recording
        // The transport controller's play() method sets up timing state, starts position
        // timer, and triggers audio/MIDI playback. Without this, the playhead doesn't move
        // and the UI becomes unresponsive.
        //
        // Previous bug: Called onStartRecordingMode() and onStartPlayback() directly,
        // which set transport state to .recording but never called transport.play().
        // This left the position timer stopped and timing state uninitialized.
        //
        // Correct flow:
        // 1. Call transport.play() to start from beat 0 with proper timing setup
        // 2. Switch transport state from .playing to .recording
        // 3. Set recording flag and install taps
        
        guard let transport = transportController else {
            record()
            return
        }
        
        // Ensure we're at beat 0 for recording
        transport.stop()
        
        // Set recording flag (before installing tap)
        isRecording = true
        
        // Start MIDI recording for record-enabled MIDI tracks
        let recordEnabledTracks = project.tracks.filter { $0.mixerSettings.isRecordEnabled }
        let midiRecordTracks = recordEnabledTracks.filter { $0.isMIDITrack }
        if let firstMIDITrack = midiRecordTracks.first {
            Task { @MainActor in
                InstrumentManager.shared.startRecording(trackId: firstMIDITrack.id, atBeats: 0)
            }
        }
        
        // Install input tap BEFORE starting transport (ensures we capture from beat 0)
        if let recordTrack = countInRecordTrack, !recordTrack.isMIDITrack {
            installInputTapForCountIn()
        }
        
        // Start transport - this triggers audio/MIDI playback AND sets up position tracking
        // CRITICAL: This must come AFTER tap installation to capture first beat
        transport.play()
        
        // Switch transport state to recording (transport is now playing with proper timing)
        onStartRecordingMode()
        
        // Clear prepared state
        countInRecordingPrepared = false
    }
    
    /// Start recording (standard entry point)
    func record() {
        guard let project = getProject() else { return }
        
        // Capture recording start beat immediately so we have it even if first buffer is delayed
        recordingStartBeat = getCurrentPosition().beats
        
        // Check for record-enabled tracks
        let recordEnabledTracks = project.tracks.filter { $0.mixerSettings.isRecordEnabled }
        
        // Set recording state
        onStartRecordingMode()
        isRecording = true
        
        // Start MIDI recording for record-enabled MIDI tracks
        let midiRecordTracks = recordEnabledTracks.filter { $0.isMIDITrack }
        if let firstMIDITrack = midiRecordTracks.first {
            let startBeats = getCurrentPosition().beats
            Task { @MainActor in
                InstrumentManager.shared.startRecording(trackId: firstMIDITrack.id, atBeats: startBeats)
            }
        }
        
        // Install tap (and start playback) inside startRecording/setupRecording so we don't miss first buffers
        startRecording()
    }
    
    /// Stop recording
    func stopRecording() {
        guard isRecording else { return }
        
        // Stop MIDI recording and capture the region
        Task { @MainActor in
            let instrumentManager = InstrumentManager.shared
            let recordingTrackId = instrumentManager.recordingTrackId
            if let midiRegion = instrumentManager.stopRecording(),
               let trackId = recordingTrackId {
                instrumentManager.projectManager?.addMIDIRegion(midiRegion, to: trackId)
            }
        }
        
        stopRecordingInternal()
        onStopRecordingMode()
        isRecording = false
        inputLevel = 0.0
        onStopPlayback()
    }
    
    // MARK: - Private Recording Implementation
    
    private func startRecording() {
        guard getProject() != nil else { return }
        
        requestMicPermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    self?.setupRecording()
                } else {
                    self?.stopRecording()
                }
            }
        }
    }
    
    private func requestMicPermission(completion: @escaping (Bool) -> Void) {
        let usageDescription = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        
        if usageDescription == nil {
            // Missing NSMicrophoneUsageDescription
        }
        
        AVCaptureDevice.requestAccess(for: .audio) { result in
            completion(result)
        }
    }
    
    private func setupRecording() {
        guard let project = getProject() else { return }
        
        do {
            let recordTrack = findOrCreateRecordTrack(in: project)
            recordingTrackId = recordTrack.id
            
            // Skip audio recording for MIDI tracks (start transport so MIDI has timeline)
            if recordTrack.isMIDITrack {
                // CRITICAL FIX (Issue #120): Start transport properly for MIDI recording
                // Must call transport.play() to set up timing state and position tracking
                if let transport = transportController {
                    transport.stop()  // Ensure we're at beat 0
                    transport.play()  // Start transport with proper timing
                    onStartRecordingMode()  // Switch to recording mode
                } else {
                    onStartPlayback()  // Fallback (shouldn't happen)
                }
                return
            }
            
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
            
            // Create dedicated writer queue with HIGH priority (BUG FIX Issue #55)
            // Recording I/O must complete quickly to prevent buffer pool exhaustion
            // .utility QoS is too low for real-time recording - use .userInitiated
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
            
            startSilentPlayerForRecording()
            
            // Reset first buffer flag for accurate start beat capture
            recordingFirstBufferReceived = false
            
            // Install input tap
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
                
                // Capture file reference before async to avoid Sendable crossing actor boundaries
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
            
            if !engine.isRunning {
                try engine.start()
            }
            
            // CRITICAL FIX (Issue #120): Start transport properly for audio recording
            // Must call transport.play() to set up timing state and position tracking
            // Tap is already installed above, so we'll capture from beat 0
            if let transport = transportController {
                transport.stop()  // Ensure we're at beat 0
                transport.play()  // Start transport with proper timing
                onStartRecordingMode()  // Switch to recording mode
            } else {
                // Fallback (shouldn't happen) - use old broken path
                onStartPlayback()
            }
            
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
    
    deinit {
        // CRITICAL: Protective deinit for @Observable @MainActor class (ASan Issue #84742+)
        // Prevents double-free from implicit Swift Concurrency property change notification tasks
    }
}
