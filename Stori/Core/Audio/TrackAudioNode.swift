//
//  TrackAudioNode.swift
//  Stori
//
//  Audio node representation for individual tracks
//

import Foundation
import AVFoundation
import Accelerate
import os.lock

// MARK: - Track Audio Node

/// Audio node representation for individual tracks with real-time safe level metering.
///
/// REAL-TIME SAFETY: Level metering uses `os_unfair_lock` protected storage.
/// The audio tap callback writes levels with lock (never blocks), and the main thread
/// reads via public properties with lock. This avoids `DispatchQueue.main.async` which
/// can cause priority inversion and audio dropouts when the main thread is busy.
///
/// This pattern matches `AutomationProcessor` and `RecordingBufferPool` in the codebase.
final class TrackAudioNode: @unchecked Sendable {
    
    // MARK: - Properties
    let id: UUID
    let playerNode: AVAudioPlayerNode
    let volumeNode: AVAudioMixerNode
    let panNode: AVAudioMixerNode
    let eqNode: AVAudioUnitEQ
    
    // MARK: - Plugin Chain (AU/VST Insert Effects)
    /// The plugin chain for this track's insert effects
    /// Signal flow: timePitch → pluginChain.input → [plugins] → pluginChain.output → volume
    let pluginChain: PluginChain
    
    // MARK: [V2-PITCH/TEMPO] Unit (passed from AudioEngine - MUST be the connected unit!)
    let timePitchUnit: AVAudioUnitTimePitch
    
    // MARK: - Audio State
    private(set) var volume: Float
    private(set) var pan: Float
    private(set) var isMuted: Bool
    private(set) var isSolo: Bool
    
    // MARK: - Level Monitoring (Real-Time Safe)
    
    /// Lock for thread-safe access to level values between audio and main threads.
    /// Using os_unfair_lock for minimal overhead - same pattern as AutomationProcessor.
    private var levelLock = os_unfair_lock_s()
    
    /// Internal storage for level values (protected by levelLock)
    private var _currentLevelLeft: Float = 0.0
    private var _currentLevelRight: Float = 0.0
    private var _peakLevelLeft: Float = 0.0
    private var _peakLevelRight: Float = 0.0
    
    private var levelTapInstalled: Bool = false
    
    /// Current RMS level for left channel (thread-safe read)
    var currentLevelLeft: Float {
        os_unfair_lock_lock(&levelLock)
        defer { os_unfair_lock_unlock(&levelLock) }
        return _currentLevelLeft
    }
    
    /// Current RMS level for right channel (thread-safe read)
    var currentLevelRight: Float {
        os_unfair_lock_lock(&levelLock)
        defer { os_unfair_lock_unlock(&levelLock) }
        return _currentLevelRight
    }
    
    /// Peak level for left channel with decay (thread-safe read)
    var peakLevelLeft: Float {
        os_unfair_lock_lock(&levelLock)
        defer { os_unfair_lock_unlock(&levelLock) }
        return _peakLevelLeft
    }
    
    /// Peak level for right channel with decay (thread-safe read)
    var peakLevelRight: Float {
        os_unfair_lock_lock(&levelLock)
        defer { os_unfair_lock_unlock(&levelLock) }
        return _peakLevelRight
    }
    
    // Peak decay rate per callback (see AudioConstants.trackPeakDecayRate)
    // At trackMeteringBufferSize / 48kHz = ~21ms per callback
    // 0.95 gives ~300ms release time (professional standard)
    private var peakDecayRate: Float { AudioConstants.trackPeakDecayRate }
    
    // PERFORMANCE FIX: Cache loaded audio files to prevent beach ball during playback
    private var cachedAudioFiles: [URL: AVAudioFile] = [:]
    
    /// Clear audio file cache (called during memory pressure)
    func clearAudioFileCache() {
        let cacheSize = cachedAudioFiles.count
        cachedAudioFiles.removeAll()
        if cacheSize > 0 {
            AppLogger.shared.debug("TrackAudioNode[\(id)]: Cleared \(cacheSize) cached audio files", category: .audio)
        }
    }
    
    // MARK: - Initialization
    init(
        id: UUID,
        playerNode: AVAudioPlayerNode,
        volumeNode: AVAudioMixerNode,
        panNode: AVAudioMixerNode,
        eqNode: AVAudioUnitEQ,
        pluginChain: PluginChain,
        timePitchUnit: AVAudioUnitTimePitch,  // ✅ FIX: Accept the connected unit from AudioEngine
        volume: Float = 0.8,
        pan: Float = 0.0,
        isMuted: Bool = false,
        isSolo: Bool = false
    ) {
        self.id = id
        self.playerNode = playerNode
        self.volumeNode = volumeNode
        self.panNode = panNode
        self.eqNode = eqNode
        self.pluginChain = pluginChain
        self.timePitchUnit = timePitchUnit  // ✅ FIX: Use the SAME unit that's in the signal chain
        self.volume = volume
        self.pan = pan
        self.isMuted = isMuted
        self.isSolo = isSolo
        
        setupEQ()
        setupLevelMonitoring()
    }
    
    deinit {
        removeLevelMonitoring()
    }
    
    // MARK: - Parameter Smoothing (Thread-Safe)
    
    /// Lock for thread-safe access to automation state
    /// The automation engine runs on a high-priority queue and needs safe access
    private var automationLock = os_unfair_lock_s()
    
    /// Previous volume value for smoothing (protected by automationLock)
    private var _smoothedVolume: Float = 1.0
    
    /// Previous pan value for smoothing (protected by automationLock)
    private var _smoothedPan: Float = 0.0
    
    /// Cached EQ values for smoothing (protected by automationLock)
    private var _smoothedEqLow: Float = 0.0
    private var _smoothedEqMid: Float = 0.0
    private var _smoothedEqHigh: Float = 0.0
    
    // MARK: - Volume Control
    func setVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
        let actualVolume = isMuted ? 0.0 : volume
        volumeNode.outputVolume = actualVolume
    }
    
    /// Set volume with smoothing to prevent zippering during automation playback
    /// Thread-safe - can be called from automation queue
    /// Smoothing is adaptive: large changes use less smoothing (for step curves),
    /// small changes use more smoothing (for smooth curves)
    func setVolumeSmoothed(_ newVolume: Float) {
        let targetVolume = max(0.0, min(1.0, newVolume))
        
        os_unfair_lock_lock(&automationLock)
        
        // Adaptive smoothing based on rate of change
        // Large jumps (> 0.2) use minimal smoothing (step-like behavior)
        // Small changes use more smoothing (zipper prevention)
        let delta = abs(targetVolume - _smoothedVolume)
        let smoothingFactor: Float
        if delta > 0.2 {
            smoothingFactor = 0.1  // Minimal smoothing for step curves (90% new value)
        } else if delta > 0.05 {
            smoothingFactor = 0.5  // Light smoothing for linear curves
        } else {
            smoothingFactor = 0.7  // Heavy smoothing for smooth curves
        }
        
        _smoothedVolume = _smoothedVolume * smoothingFactor + targetVolume * (1.0 - smoothingFactor)
        let smoothedValue = _smoothedVolume
        os_unfair_lock_unlock(&automationLock)
        
        volume = smoothedValue
        let actualVolume = isMuted ? 0.0 : smoothedValue
        volumeNode.outputVolume = actualVolume
    }
    
    // MARK: - Pan Control
    func setPan(_ newPan: Float) {
        pan = max(-1.0, min(1.0, newPan))
        panNode.pan = pan
    }
    
    /// Set pan with smoothing to prevent zippering during automation playback
    /// Thread-safe - can be called from automation queue
    /// Smoothing is adaptive: large changes use less smoothing (for step curves),
    /// small changes use more smoothing (for smooth curves)
    func setPanSmoothed(_ newPan: Float) {
        let targetPan = max(-1.0, min(1.0, newPan))
        
        os_unfair_lock_lock(&automationLock)
        
        // Adaptive smoothing based on rate of change
        let delta = abs(targetPan - _smoothedPan)
        let smoothingFactor: Float
        if delta > 0.4 {  // Pan range is -1 to 1, so threshold is 2x volume
            smoothingFactor = 0.1  // Minimal smoothing for step curves
        } else if delta > 0.1 {
            smoothingFactor = 0.5  // Light smoothing for linear curves
        } else {
            smoothingFactor = 0.7  // Heavy smoothing for smooth curves
        }
        
        _smoothedPan = _smoothedPan * smoothingFactor + targetPan * (1.0 - smoothingFactor)
        let smoothedValue = _smoothedPan
        os_unfair_lock_unlock(&automationLock)
        
        pan = smoothedValue
        panNode.pan = smoothedValue
    }
    
    /// Reset smoothed values (call when transport stops/starts)
    func resetSmoothing() {
        os_unfair_lock_lock(&automationLock)
        _smoothedVolume = volume
        _smoothedPan = pan
        _smoothedEqLow = 0.0
        _smoothedEqMid = 0.0
        _smoothedEqHigh = 0.0
        os_unfair_lock_unlock(&automationLock)
    }
    
    // MARK: - Thread-Safe Automation Application
    
    /// Apply all automation values at once with smoothing
    /// Thread-safe - designed to be called from the automation engine queue
    /// - Parameters:
    ///   - volume: Volume value 0-1 (nil = no change)
    ///   - pan: Pan value 0-1 (will be converted to -1 to +1)
    ///   - eqLow: Low EQ value 0-1 (0.5 = 0dB)
    ///   - eqMid: Mid EQ value 0-1 (0.5 = 0dB)
    ///   - eqHigh: High EQ value 0-1 (0.5 = 0dB)
    func applyAutomationValues(
        volume: Float?,
        pan: Float?,
        eqLow: Float?,
        eqMid: Float?,
        eqHigh: Float?
    ) {
        if let vol = volume {
            setVolumeSmoothed(vol)
        }
        
        if let p = pan {
            // Convert 0-1 to -1..+1
            setPanSmoothed(p * 2 - 1)
        }
        
        // Apply EQ with smoothing
        if eqLow != nil || eqMid != nil || eqHigh != nil {
            setEQSmoothed(
                low: eqLow.map { ($0 - 0.5) * 24 },
                mid: eqMid.map { ($0 - 0.5) * 24 },
                high: eqHigh.map { ($0 - 0.5) * 24 }
            )
        }
    }
    
    /// Set EQ with smoothing (thread-safe)
    /// Smoothing is adaptive: large changes use less smoothing (for step curves),
    /// small changes use more smoothing (for smooth curves)
    private func setEQSmoothed(low: Float?, mid: Float?, high: Float?) {
        os_unfair_lock_lock(&automationLock)
        
        // Helper to calculate adaptive smoothing factor based on delta
        func adaptiveSmoothingFactor(for delta: Float) -> Float {
            if delta > 6.0 {  // Large EQ change (> 6dB)
                return 0.1  // Minimal smoothing
            } else if delta > 2.0 {  // Medium EQ change (> 2dB)
                return 0.5  // Light smoothing
            } else {
                return 0.7  // Heavy smoothing
            }
        }
        
        if let lowVal = low {
            let delta = abs(lowVal - _smoothedEqLow)
            let factor = adaptiveSmoothingFactor(for: delta)
            _smoothedEqLow = _smoothedEqLow * factor + lowVal * (1.0 - factor)
        }
        if let midVal = mid {
            let delta = abs(midVal - _smoothedEqMid)
            let factor = adaptiveSmoothingFactor(for: delta)
            _smoothedEqMid = _smoothedEqMid * factor + midVal * (1.0 - factor)
        }
        if let highVal = high {
            let delta = abs(highVal - _smoothedEqHigh)
            let factor = adaptiveSmoothingFactor(for: delta)
            _smoothedEqHigh = _smoothedEqHigh * factor + highVal * (1.0 - factor)
        }
        
        let finalLow = _smoothedEqLow
        let finalMid = _smoothedEqMid
        let finalHigh = _smoothedEqHigh
        
        os_unfair_lock_unlock(&automationLock)
        
        // Apply to EQ node (AVAudioUnitEQ band gain is thread-safe)
        let clampedHigh = max(-12.0, min(12.0, finalHigh))
        let clampedMid = max(-12.0, min(12.0, finalMid))
        let clampedLow = max(-12.0, min(12.0, finalLow))
        
        eqNode.bands[0].gain = clampedHigh
        eqNode.bands[1].gain = clampedMid
        eqNode.bands[2].gain = clampedLow
    }
    
    // MARK: - Mute Control
    func setMuted(_ muted: Bool) {
        isMuted = muted
        let actualVolume = muted ? 0.0 : volume
        volumeNode.outputVolume = actualVolume
    }
    
    // MARK: - Solo Control
    func setSolo(_ solo: Bool) {
        isSolo = solo
        // Solo logic will be handled at the engine level
    }
    
    // MARK: - EQ Control
    private func setupEQ() {
        // Configure 3-band EQ with standard frequencies
        eqNode.bands[0].filterType = .highShelf
        eqNode.bands[0].frequency = 10000 // High: 10kHz
        eqNode.bands[0].gain = 0
        eqNode.bands[0].bypass = false
        
        eqNode.bands[1].filterType = .parametric
        eqNode.bands[1].frequency = 1000 // Mid: 1kHz
        eqNode.bands[1].bandwidth = 1.0
        eqNode.bands[1].gain = 0
        eqNode.bands[1].bypass = false
        
        eqNode.bands[2].filterType = .lowShelf
        eqNode.bands[2].frequency = 100 // Low: 100Hz
        eqNode.bands[2].gain = 0
        eqNode.bands[2].bypass = false
        
    }
    
    func setEQ(highGain: Float, midGain: Float, lowGain: Float) {
        // Clamp values to reasonable EQ range
        let clampedHigh = max(-12.0, min(12.0, highGain))
        let clampedMid = max(-12.0, min(12.0, midGain))
        let clampedLow = max(-12.0, min(12.0, lowGain))
        
        eqNode.bands[0].gain = clampedHigh // High
        eqNode.bands[1].gain = clampedMid  // Mid
        eqNode.bands[2].gain = clampedLow  // Low
        
    }
    
    // MARK: [V2-PITCH/TEMPO] Controls
    func setPitchShift(_ cents: Float) { // -2400...+2400
        timePitchUnit.pitch = cents / 100.0 // AU uses semitones
    }

    func setPlaybackRate(_ rate: Float) {  // 0.5...2.0
        timePitchUnit.rate = rate
    }

    func setOverlap(_ overlap: Float) {    // 3...32 (Apple docs)
        timePitchUnit.overlap = overlap
    }
    
    // MARK: - Level Monitoring
    
    /// Request level monitoring setup.
    /// The actual tap installation is deferred until the node is connected to an engine.
    private func setupLevelMonitoring() {
        // Try to install immediately - if engine isn't ready, tryInstallLevelTap handles it
        tryInstallLevelTap()
    }
    
    /// Attempt to install level tap if conditions are met.
    /// Can be called multiple times safely - idempotent.
    /// Called from setupLevelMonitoring and can be called when track is added to graph.
    func tryInstallLevelTap() {
        installLevelTap()
    }
    
    private func installLevelTap() {
        guard !levelTapInstalled else { return }
        
        // Don't install tap until volumeNode is attached to an engine
        guard volumeNode.engine != nil else { return }
        
        let format = volumeNode.outputFormat(forBus: 0)
        let channelCount = Int(format.channelCount)
        let sampleRate = format.sampleRate
        
        // Calculate buffer size dynamically for consistent ~20ms update interval across sample rates
        // This ensures meters respond identically at 44.1kHz, 48kHz, 96kHz, etc.
        let targetUpdateIntervalMs: Double = 20.0
        let dynamicBufferSize = AVAudioFrameCount((targetUpdateIntervalMs / 1000.0) * sampleRate)
        // Clamp to reasonable range (512 - 4096 frames)
        let bufferSize = max(512, min(4096, dynamicBufferSize))
        
        volumeNode.installTap(onBus: 0, bufferSize: bufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            
            let leftData = channelData[0]
            
            // SIMD-optimized calculations via Accelerate (real-time safe)
            var rmsLeft: Float = 0.0
            var peakLeft: Float = 0.0
            vDSP_rmsqv(leftData, 1, &rmsLeft, vDSP_Length(frameCount))
            vDSP_maxmgv(leftData, 1, &peakLeft, vDSP_Length(frameCount))
            
            var rmsRight: Float = 0.0
            var peakRight: Float = 0.0
            
            if channelCount >= 2 {
                let rightData = channelData[1]
                vDSP_rmsqv(rightData, 1, &rmsRight, vDSP_Length(frameCount))
                vDSP_maxmgv(rightData, 1, &peakRight, vDSP_Length(frameCount))
            } else {
                rmsRight = rmsLeft
                peakRight = peakLeft
            }
            
            // REAL-TIME SAFE: Write levels with lock (no dispatch to main thread)
            os_unfair_lock_lock(&self.levelLock)
            
            self._currentLevelLeft = rmsLeft
            self._currentLevelRight = rmsRight
            
            // Peak with decay (~300ms release at ~21ms callback interval)
            self._peakLevelLeft = max(self._peakLevelLeft * self.peakDecayRate, peakLeft)
            self._peakLevelRight = max(self._peakLevelRight * self.peakDecayRate, peakRight)
            
            os_unfair_lock_unlock(&self.levelLock)
        }
        
        levelTapInstalled = true
    }
    
    private func removeLevelMonitoring() {
        guard levelTapInstalled else { return }
        
        // Safety check: only remove tap if the node is still attached to an engine
        if volumeNode.engine != nil {
            do {
                volumeNode.removeTap(onBus: 0)
            } catch {
            }
        } else {
        }
        
        levelTapInstalled = false
    }
    
    // MARK: - Audio File Loading
    func loadAudioFile(_ audioFile: AudioFile) throws {
        let url = audioFile.url
        
        // SECURITY (H-1): Validate header before passing to AVAudioFile
        guard AudioFileHeaderValidator.validateHeader(at: url) else {
            let error = NSError(domain: "TrackAudioNode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid or unsupported audio file format"])
            
            // Track the error so users know why audio isn't playing
            AudioEngineErrorTracker.shared.recordError(
                severity: .error,
                component: "TrackAudioNode[\(id)]",
                message: "Invalid audio file: \(url.lastPathComponent)",
                context: ["path": url.path]
            )
            
            throw error
        }
        
        // PERFORMANCE FIX: Cache the audio file for later use in scheduleFromPosition
        let audioFileRef: AVAudioFile
        if let cachedFile = cachedAudioFiles[url] {
            audioFileRef = cachedFile
        } else {
            do {
                audioFileRef = try AVAudioFile(forReading: url)
                cachedAudioFiles[url] = audioFileRef
            } catch {
                // Track file load failures
                AudioEngineErrorTracker.shared.recordError(
                    severity: .error,
                    component: "TrackAudioNode[\(id)]",
                    message: "Failed to load audio file: \(url.lastPathComponent)",
                    error: error
                )
                throw error
            }
        }
        
        // Note: We don't schedule here anymore since scheduleFromPosition handles it
        // playerNode.scheduleFile(audioFileRef, at: nil)
    }
    
    /// Schedule audio regions from a beat position.
    /// ARCHITECTURE: Beats-First - this is the preferred API.
    /// Conversion to seconds happens internally at the AVAudioEngine boundary.
    func scheduleFromBeat(_ startBeat: Double, audioRegions: [AudioRegion], tempo: Double, skipReset: Bool = false) throws {
        // Validate format chain before scheduling
        guard validateFormatChain() else {
            let error = AudioEngineError.invalidTrackState(
                trackId: id,
                reason: "Format validation failed"
            )
            error.record()
            throw error
        }
        
        // Convert beats to seconds at AVAudioEngine boundary
        let startTimeSeconds = startBeat * (60.0 / tempo)
        try scheduleFromPosition(startTimeSeconds, audioRegions: audioRegions, tempo: tempo, skipReset: skipReset)
    }
    
    // MARK: - Format Validation
    
    /// Validates that the format chain is consistent and sample rate conversion is working.
    /// Returns true if formats are valid for scheduling, false if there's a problem.
    private func validateFormatChain() -> Bool {
        // Check if player node has an engine
        guard let engine = playerNode.engine else {
            AudioEngineError.nodeNotAttached(nodeName: "playerNode").record()
            return false
        }
        
        // Get sample rates at each point in the chain
        let hardwareRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let playerRate = playerNode.outputFormat(forBus: 0).sampleRate
        
        // Validate rates are positive
        guard playerRate > 0, hardwareRate > 0 else {
            AudioEngineError.invalidFormat(
                reason: "Invalid sample rates (player=\(playerRate), hardware=\(hardwareRate))"
            ).record()
            return false
        }
        
        // Check for extreme rate mismatches (might indicate broken converter)
        let rateRatio = playerRate / hardwareRate
        if rateRatio < 0.5 || rateRatio > 2.0 {
            AudioEngineError.formatMismatch(
                expected: hardwareRate,
                actual: playerRate
            ).record()
            return false
        }
        
        // Warn if rates don't match (indicates converter is in use)
        if abs(playerRate - hardwareRate) > 1.0 {
            AppLogger.shared.debug("TrackAudioNode: Sample rate conversion active (player=\(Int(playerRate))Hz, hardware=\(Int(hardwareRate))Hz)", category: .audio)
        }
        
        // Verify player node has output connections
        let outputConnections = engine.outputConnectionPoints(for: playerNode, outputBus: 0)
        if outputConnections.isEmpty {
            AudioEngineError.invalidNodeConnection(
                from: "playerNode",
                to: "downstream",
                reason: "No output connections"
            ).record()
            return false
        }
        
        return true
    }
    
    /// Schedule audio regions from a seconds position.
    /// NOTE: Prefer scheduleFromBeat() - this method exists for AVAudioEngine boundary operations.
    func scheduleFromPosition(_ startTime: TimeInterval, audioRegions: [AudioRegion], tempo: Double, skipReset: Bool = false) throws {
        
        // Clean slate - skip if caller already did this (e.g., cycle loops)
        if !skipReset {
            playerNode.stop()
            playerNode.reset()
        }

        // We'll express all 'when' times in player-time samples.
        // Player-time sample 0 == the instant we call playerNode.play()
        // So a region that should start 1.0s later uses sampleTime = 1.0 * sampleRate.
        var scheduledSomething = false

        for region in audioRegions {
            // 📊 COMPREHENSIVE LOGGING: Audio scheduling
            
            // PERFORMANCE FIX: Use cached audio file or load and cache it
            let audioFile: AVAudioFile
            if let cachedFile = cachedAudioFiles[region.audioFile.url] {
                audioFile = cachedFile
            } else {
                // SECURITY (H-1): Validate header before passing to AVAudioFile
                guard AudioFileHeaderValidator.validateHeader(at: region.audioFile.url) else {
                    // Track validation failures so user knows why region isn't playing
                    AudioEngineErrorTracker.shared.recordError(
                        severity: .error,
                        component: "TrackAudioNode[\(id)]",
                        message: "Skipping region: Invalid audio file header",
                        context: [
                            "file": region.audioFile.url.lastPathComponent,
                            "regionId": region.id.uuidString
                        ]
                    )
                    continue
                }
                
                do {
                    let newFile = try AVAudioFile(forReading: region.audioFile.url)
                    cachedAudioFiles[region.audioFile.url] = newFile
                    audioFile = newFile
                } catch {
                    // Track file load failures
                    AudioEngineErrorTracker.shared.recordError(
                        severity: .error,
                        component: "TrackAudioNode[\(id)]",
                        message: "Failed to load audio file during scheduling",
                        error: error,
                        additionalContext: ["file": region.audioFile.url.lastPathComponent]
                    )
                    continue
                }
            }
            let sr = audioFile.processingFormat.sampleRate
            let fileDuration = Double(audioFile.length) / sr
            
            // CRITICAL: Protect against empty audio files (0 duration)
            guard fileDuration > 0 else {
                AudioEngineErrorTracker.shared.recordError(
                    severity: .warning,
                    component: "TrackAudioNode[\(id)]",
                    message: "Skipping region: Audio file has zero duration",
                    context: [
                        "file": region.audioFile.url.lastPathComponent,
                        "fileLength": String(audioFile.length)
                    ]
                )
                continue
            }

            // Convert region's beat position to seconds for audio scheduling
            let regionStart = region.startTimeSeconds(tempo: tempo)
            let regionEnd   = regionStart + region.durationSeconds(tempo: tempo)

            // Skip regions that already ended before startTime
            if regionEnd <= startTime { continue }

            // Check if this is a looped region - ONLY loop if explicitly marked as looped
            // Duration > fileDuration with isLooped=false means "resize with empty space"
            if region.isLooped {
                // LOOPED REGION: Schedule multiple iterations
                // Use contentLength as the loop unit (may include empty space after audio)
                let contentLen = region.contentLength > 0 ? region.contentLength : fileDuration
                let loopCount = Int(ceil(region.durationSeconds(tempo: tempo) / contentLen))
                
                // TODO: DUAL SAMPLE RATE SYSTEM (See detailed explanation in non-looped section below)
                // Use playerSampleRate for timing, fileSampleRate (sr) for frame positions
                let playerSampleRate = playerNode.outputFormat(forBus: 0).sampleRate
                
                var currentLoopStart = regionStart
                for loopIndex in 0..<loopCount {
                    // Each content unit: audio plays for fileDuration, then silence for (contentLen - fileDuration)
                    let audioEndInThisLoop = currentLoopStart + fileDuration
                    let contentUnitEnd = currentLoopStart + contentLen
                    let loopEnd = min(audioEndInThisLoop, regionEnd) // Only schedule audio portion
                    
                    // Skip if this loop iteration's audio is before playback start
                    if audioEndInThisLoop <= startTime {
                        currentLoopStart += contentLen
                        continue
                    }
                    
                    // Calculate delay and frame info for this loop iteration
                    let delaySeconds = max(0.0, currentLoopStart - startTime)
                    
                    // PDC: Add compensation delay for tracks with less plugin latency
                    let compensationSeconds = Double(compensationDelaySamples) / playerSampleRate
                    let totalDelaySeconds = delaySeconds + compensationSeconds
                    let delaySamples = AVAudioFramePosition(totalDelaySeconds * playerSampleRate)
                    
                    // If starting mid-loop, calculate offset into the file (clamp to [0, fileDuration]; skip if past audio)
                    let offsetIntoLoop = max(0.0, startTime - currentLoopStart)
                    if offsetIntoLoop >= fileDuration {
                        // This iteration is in the silence portion of the content unit (contentLen > fileDuration)
                        currentLoopStart += contentLen
                        continue
                    }
                    let clampedOffset = min(offsetIntoLoop, fileDuration)
                    let startFrameInFile = AVAudioFramePosition(clampedOffset * sr)
                    
                    // Frames to play from this loop iteration (only audio, not empty space)
                    let loopDuration = loopEnd - max(currentLoopStart, startTime)
                    let frameCount = AVAudioFrameCount(max(0, loopDuration) * sr)
                    
                    if frameCount > 0 {
                        let when = AVAudioTime(sampleTime: delaySamples, atRate: playerSampleRate)
                        playerNode.scheduleSegment(
                            audioFile,
                            startingFrame: startFrameInFile,
                            frameCount: frameCount,
                            at: when
                        )
                        scheduledSomething = true
                    }
                    
                    currentLoopStart += contentLen // Advance by content length (includes empty space)
                }
            } else {
                // NON-LOOPED REGION: Schedule once (original logic)
                let delaySeconds = max(0.0, regionStart - startTime)
                
                // TODO: DUAL SAMPLE RATE SYSTEM - CRITICAL FOR ACCURATE TIMING
                // ============================================================
                // We use TWO different sample rates in audio scheduling:
                //
                // 1. playerSampleRate (from playerNode.outputFormat) - Used for TIMING
                //    - This is the engine's runtime sample rate (typically 44.1kHz or 48kHz)
                //    - Used to calculate when audio should START playing (AVAudioTime)
                //    - Determines the delay before playback begins
                //    - MUST match the audio engine's sample rate for accurate timing
                //
                // 2. fileSampleRate (sr, from audioFile.processingFormat) - Used for FRAME POSITIONS
                //    - This is the audio file's native sample rate (e.g., 32kHz from MusicGen)
                //    - Used to calculate WHERE in the file to start reading (startingFrame)
                //    - Used to calculate HOW MANY frames to read (frameCount)
                //    - MUST match the file's sample rate to read correct positions
                //
                // WHY THIS MATTERS:
                // - MusicGen generates audio at 32kHz, but the engine runs at 48kHz (or 44.1kHz)
                // - Using the wrong sample rate for timing causes playback offset bugs
                // - Example: 5 second delay at 32kHz = 160,000 samples
                //            But on 48kHz engine, that's only 3.33 seconds! (160k / 48k)
                // - This caused the bug where regions played ~1 second early
                //
                // FUTURE PLANS:
                // - KEEP THIS APPROACH - This is the correct way to handle mixed sample rates
                // - AVAudioEngine handles sample rate conversion automatically for playback
                // - DO NOT attempt to "simplify" by using a single sample rate
                // - DO NOT remove the playerSampleRate - timing MUST use engine's rate
                // - The debug logs show both rates for troubleshooting future issues
                //
                // CRITICAL: Never mix these up or use file sample rate for timing calculations!
                // ============================================================
                
                let playerSampleRate = playerNode.outputFormat(forBus: 0).sampleRate
                
                // PDC: Add compensation delay for tracks with less plugin latency
                // This keeps all tracks phase-aligned regardless of plugin latency
                let compensationSeconds = Double(compensationDelaySamples) / playerSampleRate
                let totalDelaySeconds = delaySeconds + compensationSeconds
                let delaySamples = AVAudioFramePosition(totalDelaySeconds * playerSampleRate)
                
                let offsetSecondsInFile = max(0.0, startTime - regionStart) + region.offset
                let startFrameInFile = AVAudioFramePosition(offsetSecondsInFile * sr)
                
                let framesRemainingInRegion = AVAudioFrameCount(max(0.0, (region.durationSeconds(tempo: tempo) - max(0.0, startTime - regionStart)) * sr))
                
                // 🐛 DEBUG: Log scheduling calculation
                
                guard framesRemainingInRegion > 0 else { continue }
                
                let when = AVAudioTime(sampleTime: delaySamples, atRate: playerSampleRate)
                playerNode.scheduleSegment(
                    audioFile,
                    startingFrame: startFrameInFile,
                    frameCount: framesRemainingInRegion,
                    at: when
                )
                scheduledSomething = true
            }
        }

        if scheduledSomething {
            // Start the player's timeline now; future items will fire at their 'when' offsets
            // Use immediate play() for player-time scheduling consistency
            fflush(stdout)
            
            // Verify player node is attached to engine
            let isAttached = playerNode.engine != nil
            let engineRunning = playerNode.engine?.isRunning ?? false
            
            // Check output format BEFORE play
            let outputFormat = playerNode.outputFormat(forBus: 0)
            
            // Check volume
            fflush(stdout)
            
            fflush(stdout)
            
            playerNode.play()
            
            fflush(stdout)
        } else {
        }
    }
    
    // MARK: - Playback Control
    func play() {
        if !playerNode.isPlaying {
            // CRITICAL DIAGNOSTIC: Check connection state before playing
            
            // Check OUTPUT connections (not inputs) - players are sources
            guard let engine = playerNode.engine else {
                return
            }
            
            
            // ChatGPT Fix: Check output connection points before play()
            let outputConnections = engine.outputConnectionPoints(for: playerNode, outputBus: 0)
            
            guard !outputConnections.isEmpty else {
                return
            }
            
            // Safe to play - we have verified output connections exist
            playerNode.play()
        }
    }
    
    func pause() {
        if playerNode.isPlaying {
            playerNode.pause()
        }
    }
    
    func stop() {
        playerNode.stop()
    }
    
    // MARK: - Seamless Cycle Loop Scheduling
    
    /// Pre-schedules multiple cycle iterations for seamless looping.
    /// This is the key to gap-free cycle loops - audio for subsequent iterations
    /// is already queued before the current iteration ends.
    ///
    /// ARCHITECTURE: Beats-First
    /// All parameters are in beats (musical time). Conversion to seconds happens
    /// internally at the AVAudioEngine boundary.
    ///
    /// - Parameters:
    ///   - startBeat: Current playback position in beats
    ///   - audioRegions: Regions to schedule
    ///   - tempo: Project tempo for beat-to-seconds conversion
    ///   - cycleStartBeat: Cycle region start in beats
    ///   - cycleEndBeat: Cycle region end in beats
    ///   - iterationsAhead: Number of cycle iterations to pre-schedule (default: 2)
    /// Schedule audio for cycle-aware playback (pre-schedules multiple iterations)
    ///
    /// BUG FIX (Issue #47): Added `preservePlayback` parameter to support seamless
    /// cycle loop jumps without clearing already-scheduled audio buffers.
    ///
    /// SEAMLESS CYCLE LOOP ARCHITECTURE:
    /// When cycle mode is enabled, we pre-schedule multiple iterations ahead.
    /// This means audio for beats 5-8 might already be scheduled while playing beats 1-4.
    ///
    /// PARAMETERS:
    /// - fromBeat: Starting beat position
    /// - audioRegions: Regions to schedule
    /// - tempo: Project tempo for beat→time conversion
    /// - cycleStartBeat: Cycle region start
    /// - cycleEndBeat: Cycle region end
    /// - iterationsAhead: How many future iterations to pre-schedule (default 2)
    /// - preservePlayback: If true, don't stop/reset player node (for seamless jumps)
    ///
    /// WHEN TO USE preservePlayback=true:
    /// - Cycle loop jumps where audio is already pre-scheduled
    /// - Player node is already playing and has future iterations queued
    /// - We want to avoid any gap or discontinuity
    ///
    /// WHEN TO USE preservePlayback=false (default):
    /// - Starting fresh playback
    /// - Seeking to a new position (not a cycle jump)
    /// - Need to clear old buffers and schedule new audio
    func scheduleCycleAware(
        fromBeat startBeat: Double,
        audioRegions: [AudioRegion],
        tempo: Double,
        cycleStartBeat: Double,
        cycleEndBeat: Double,
        iterationsAhead: Int = 2,
        preservePlayback: Bool = false
    ) throws {
        // BUG FIX (Issue #47): Only stop/reset if NOT preserving playback
        // This allows seamless cycle jumps without clearing pre-scheduled audio
        if !preservePlayback {
            playerNode.stop()
            playerNode.reset()
        }
        
        let playerSampleRate = playerNode.outputFormat(forBus: 0).sampleRate
        guard playerSampleRate > 0 else { return }
        
        // Convert beats to seconds at AVAudioEngine boundary
        let beatsToSeconds = 60.0 / tempo
        let startTimeSeconds = startBeat * beatsToSeconds
        let cycleStartSeconds = cycleStartBeat * beatsToSeconds
        let cycleEndSeconds = cycleEndBeat * beatsToSeconds
        
        let cycleDurationSeconds = cycleEndSeconds - cycleStartSeconds
        guard cycleDurationSeconds > 0 else {
            // Invalid cycle - fall back to normal scheduling
            try scheduleFromPosition(startTimeSeconds, audioRegions: audioRegions, tempo: tempo)
            return
        }
        
        var scheduledSomething = false
        
        // Schedule current iteration + N iterations ahead
        for iterationIndex in 0...iterationsAhead {
            // Calculate the timeline offset for this iteration
            // Iteration 0: starts immediately (or mid-cycle if startTime > cycleStart)
            // Iteration 1: starts at (cycleEnd - startTime) seconds from now
            // Iteration 2: starts at (cycleEnd - startTime) + cycleDuration seconds from now
            
            let iterationStartSeconds: TimeInterval
            let playbackOffsetSeconds: TimeInterval
            
            if iterationIndex == 0 {
                // First iteration: start from current position
                iterationStartSeconds = startTimeSeconds
                playbackOffsetSeconds = 0
            } else {
                // Subsequent iterations: start from cycle start
                iterationStartSeconds = cycleStartSeconds
                // Time until this iteration plays (from player-time 0)
                playbackOffsetSeconds = (cycleEndSeconds - startTimeSeconds) + (Double(iterationIndex - 1) * cycleDurationSeconds)
            }
            
            // Schedule all regions that intersect with this cycle iteration
            for region in audioRegions {
                do {
                    let didSchedule = try scheduleRegionForCycleIteration(
                        region: region,
                        tempo: tempo,
                        iterationStartSeconds: iterationStartSeconds,
                        cycleStartSeconds: cycleStartSeconds,
                        cycleEndSeconds: cycleEndSeconds,
                        playbackOffsetSeconds: playbackOffsetSeconds,
                        playerSampleRate: playerSampleRate
                    )
                    if didSchedule {
                        scheduledSomething = true
                    }
                } catch {
                    // Skip problematic regions, continue with others
                }
            }
        }
        
        // BUG FIX (Issue #47): Only start playback if we actually scheduled something
        // AND we're not preserving existing playback
        if scheduledSomething && !preservePlayback {
            playerNode.play()
        }
    }
    
    /// Schedules a single region's audio for one cycle iteration.
    /// Returns true if audio was scheduled.
    private func scheduleRegionForCycleIteration(
        region: AudioRegion,
        tempo: Double,
        iterationStartSeconds: TimeInterval,
        cycleStartSeconds: TimeInterval,
        cycleEndSeconds: TimeInterval,
        playbackOffsetSeconds: TimeInterval,
        playerSampleRate: Double
    ) throws -> Bool {
        // Load audio file
        let audioFile: AVAudioFile
        if let cachedFile = cachedAudioFiles[region.audioFile.url] {
            audioFile = cachedFile
        } else {
            guard AudioFileHeaderValidator.validateHeader(at: region.audioFile.url) else { return false }
            let newFile = try AVAudioFile(forReading: region.audioFile.url)
            cachedAudioFiles[region.audioFile.url] = newFile
            audioFile = newFile
        }
        
        let fileSampleRate = audioFile.processingFormat.sampleRate
        let fileDuration = Double(audioFile.length) / fileSampleRate
        guard fileDuration > 0 else { return false }
        
        // Region timing in seconds
        let regionStart = region.startTimeSeconds(tempo: tempo)
        let regionEnd = regionStart + region.durationSeconds(tempo: tempo)
        
        // Clamp region to cycle boundaries
        let effectiveStart = max(regionStart, cycleStartSeconds)
        let effectiveEnd = min(regionEnd, cycleEndSeconds)
        
        // Skip if region doesn't intersect this cycle
        guard effectiveEnd > effectiveStart else { return false }
        guard effectiveEnd > iterationStartSeconds else { return false }
        
        // Calculate what portion of the region to play
        let actualStart = max(effectiveStart, iterationStartSeconds)
        let offsetIntoRegion = actualStart - regionStart + region.offset
        
        // Clamp offset to file duration
        guard offsetIntoRegion < fileDuration else { return false }
        
        let startFrameInFile = AVAudioFramePosition(offsetIntoRegion * fileSampleRate)
        
        // Duration to play (clamped to file and cycle)
        let durationToPlay = min(effectiveEnd - actualStart, fileDuration - offsetIntoRegion)
        guard durationToPlay > 0 else { return false }
        
        let frameCount = AVAudioFrameCount(durationToPlay * fileSampleRate)
        guard frameCount > 0 else { return false }
        
        // Calculate delay from player-time 0
        let delayFromIterationStart = actualStart - iterationStartSeconds
        let totalDelaySeconds = playbackOffsetSeconds + delayFromIterationStart
        
        // Add PDC compensation
        let compensationSeconds = Double(compensationDelaySamples) / playerSampleRate
        let finalDelaySeconds = totalDelaySeconds + compensationSeconds
        
        let delaySamples = AVAudioFramePosition(finalDelaySeconds * playerSampleRate)
        let when = AVAudioTime(sampleTime: delaySamples, atRate: playerSampleRate)
        
        playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrameInFile,
            frameCount: frameCount,
            at: when
        )
        
        return true
    }
    
    // MARK: - Recording Properties
    private var isRecordEnabled: Bool = false
    private var hasInputMonitoring: Bool = false
    
    // MARK: - Additional Methods
    func setRecordEnabled(_ enabled: Bool) {
        isRecordEnabled = enabled
        
        // Visual indication could be added here
        if enabled {
        }
    }
    
    func setInputMonitoring(_ enabled: Bool) {
        hasInputMonitoring = enabled
        
        // Note: Actual zero-latency monitoring is handled at the AudioEngine level
        // by connecting the input node directly to the output
        // This flag is primarily for UI state management
        if enabled {
        } else {
        }
    }
    
    func setFrozen(_ frozen: Bool) {
        // Implementation for track freezing functionality
        // This would typically involve bouncing the track to audio and disabling real-time processing
    }
}
