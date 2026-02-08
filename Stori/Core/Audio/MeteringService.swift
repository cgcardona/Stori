//
//  MeteringService.swift
//  Stori
//
//  Extracted from AudioEngine - handles level metering and LUFS loudness analysis
//
//  REAL-TIME SAFETY: Level metering uses `os_unfair_lock` protected storage.
//  The audio tap callback writes levels with lock (never blocks), and the main thread
//  reads via public properties with lock. This avoids `DispatchQueue.main.async` which
//  can cause priority inversion and audio dropouts when the main thread is busy.
//
//  This pattern matches `AutomationProcessor`, `RecordingBufferPool`, and `TrackAudioNode`.
//

import Foundation
@preconcurrency import AVFoundation
import Accelerate
import os.lock

// MARK: - Metering Service

/// Service responsible for audio level metering and LUFS loudness measurement.
/// Extracted from AudioEngine to reduce complexity and isolate read-only metering logic.
///
/// Responsibilities:
/// - Master output level metering (RMS and peak)
/// - LUFS loudness calculation (momentary, short-term, integrated)
/// - True peak detection
/// - Track-level queries (via TrackAudioNode)
///
/// REAL-TIME SAFETY: Uses `os_unfair_lock` for thread-safe access to meter values.
/// Audio tap writes with lock, main thread reads with lock - no dispatch required.
final class MeteringService: @unchecked Sendable {
    
    // MARK: - Thread Safety
    
    /// Lock for thread-safe access to meter values between audio and main threads.
    /// Using os_unfair_lock for minimal overhead - same pattern as AutomationProcessor.
    private var meterLock = os_unfair_lock_s()
    
    // MARK: - Internal Level Storage (Protected by meterLock)
    
    private var _masterLevelLeft: Float = 0.0
    private var _masterLevelRight: Float = 0.0
    private var _masterPeakLeft: Float = 0.0
    private var _masterPeakRight: Float = 0.0
    private var _loudnessMomentary: Float = -70.0
    private var _loudnessShortTerm: Float = -70.0
    private var _loudnessIntegrated: Float = -70.0
    private var _truePeak: Float = -70.0
    
    // MARK: - Clip Detection State (Issue #73)
    
    /// Number of samples that exceeded 0dBFS since last reset
    private var _clipCount: Int = 0
    
    /// Whether clipping has occurred (latching indicator)
    private var _isClipping: Bool = false
    
    // MARK: - Public Metering Properties (Thread-Safe Reads)
    
    /// Master output RMS level (left channel)
    var masterLevelLeft: Float {
        os_unfair_lock_lock(&meterLock)
        defer { os_unfair_lock_unlock(&meterLock) }
        return _masterLevelLeft
    }
    
    /// Master output RMS level (right channel)
    var masterLevelRight: Float {
        os_unfair_lock_lock(&meterLock)
        defer { os_unfair_lock_unlock(&meterLock) }
        return _masterLevelRight
    }
    
    /// Master output peak level (left channel) - decays over time
    var masterPeakLeft: Float {
        os_unfair_lock_lock(&meterLock)
        defer { os_unfair_lock_unlock(&meterLock) }
        return _masterPeakLeft
    }
    
    /// Master output peak level (right channel) - decays over time
    var masterPeakRight: Float {
        os_unfair_lock_lock(&meterLock)
        defer { os_unfair_lock_unlock(&meterLock) }
        return _masterPeakRight
    }
    
    // MARK: - LUFS Loudness Metering (Thread-Safe Reads)
    
    /// Momentary loudness (400ms window) in LUFS
    var loudnessMomentary: Float {
        os_unfair_lock_lock(&meterLock)
        defer { os_unfair_lock_unlock(&meterLock) }
        return _loudnessMomentary
    }
    
    /// Short-term loudness (3s window) in LUFS
    var loudnessShortTerm: Float {
        os_unfair_lock_lock(&meterLock)
        defer { os_unfair_lock_unlock(&meterLock) }
        return _loudnessShortTerm
    }
    
    /// Integrated loudness (entire measurement period) in LUFS
    var loudnessIntegrated: Float {
        os_unfair_lock_lock(&meterLock)
        defer { os_unfair_lock_unlock(&meterLock) }
        return _loudnessIntegrated
    }
    
    /// True peak level in dB (simplified - actual true peak requires oversampling)
    var truePeak: Float {
        os_unfair_lock_lock(&meterLock)
        defer { os_unfair_lock_unlock(&meterLock) }
        return _truePeak
    }
    
    // MARK: - Clip Detection (Issue #73)
    
    /// Number of samples that exceeded 0dBFS
    /// This counter increments when master output clips
    var clipCount: Int {
        os_unfair_lock_lock(&meterLock)
        defer { os_unfair_lock_unlock(&meterLock) }
        return _clipCount
    }
    
    /// Whether clipping has occurred (latching indicator - stays true until reset)
    /// Use this for UI clip indicator (red light)
    var isClipping: Bool {
        os_unfair_lock_lock(&meterLock)
        defer { os_unfair_lock_unlock(&meterLock) }
        return _isClipping
    }
    
    /// Reset clip detection state (call when user acknowledges clip indicator)
    func resetClipIndicator() {
        os_unfair_lock_lock(&meterLock)
        _clipCount = 0
        _isClipping = false
        os_unfair_lock_unlock(&meterLock)
    }
    
    // MARK: - Private Metering State
    
    /// Flag to prevent duplicate tap installation
    private var masterMeterTapInstalled: Bool = false
    
    /// Peak decay rate per update cycle (see AudioConstants.masterPeakDecayRate)
    /// At masterMeteringBufferSize / 48kHz = ~85ms per callback
    /// 0.9 gives ~300ms release time
    private var masterPeakDecayRate: Float { AudioConstants.masterPeakDecayRate }
    
    // MARK: - LUFS Calculation Buffers (Protected by meterLock)
    
    /// O(1) circular buffer for real-time safe LUFS calculation
    private struct CircularBuffer {
        private var buffer: [Float]
        private var writeIndex: Int = 0
        let capacity: Int
        
        init(capacity: Int, initialValue: Float = -70.0) {
            self.capacity = max(1, capacity)
            self.buffer = Array(repeating: initialValue, count: self.capacity)
        }
        
        /// O(1) append - overwrites oldest value
        mutating func append(_ value: Float) {
            buffer[writeIndex] = value
            writeIndex = (writeIndex + 1) % capacity
        }
        
        /// Calculate power average for LUFS (in linear power domain)
        func powerAverage() -> Float {
            var sum: Float = 0.0
            for value in buffer {
                sum += pow(10, value / 10.0)
            }
            let avg = sum / Float(capacity)
            return avg > 0 ? 10.0 * log10(avg) : -70.0
        }
    }
    
    /// Circular buffer for momentary loudness calculation (400ms)
    private var momentaryBuffer: CircularBuffer?
    
    /// Circular buffer for short-term loudness calculation (3s)
    private var shortTermBuffer: CircularBuffer?
    
    /// Cumulative sum for integrated loudness
    private var integratedSum: Double = 0.0
    
    /// Count of samples included in integrated loudness
    private var integratedCount: Int = 0
    
    /// Gate threshold for integrated loudness (blocks below this are excluded)
    private let loudnessGateThreshold: Float = -70.0
    
    // MARK: - Dependencies
    
    /// Accessor for track nodes (provided by AudioEngine)
    private let trackNodesAccessor: () -> [UUID: TrackAudioNode]
    
    /// Accessor for master volume (for post-fader metering)
    private let masterVolumeAccessor: () -> Float
    
    // MARK: - Initialization
    
    /// Initialize the metering service
    /// - Parameters:
    ///   - trackNodes: Closure that returns the current track nodes dictionary
    ///   - masterVolume: Closure that returns the current master volume
    init(
        trackNodes: @escaping () -> [UUID: TrackAudioNode],
        masterVolume: @escaping () -> Float
    ) {
        self.trackNodesAccessor = trackNodes
        self.masterVolumeAccessor = masterVolume
    }
    
    /// Run deinit off the executor to avoid Swift Concurrency task-local bad-free (ASan) when
    /// the runtime deinits this object on MainActor/task-local context.
    nonisolated deinit {}
    
    // MARK: - Master Meter Tap Installation
    
    /// Install the master metering tap on the specified EQ node
    /// - Parameter masterEQ: The master EQ node to tap for metering
    func installMasterMeterTap(on masterEQ: AVAudioUnitEQ) {
        guard !masterMeterTapInstalled else { return }
        
        let format = masterEQ.outputFormat(forBus: 0)
        let channelCount = Int(format.channelCount)
        let sampleRate = format.sampleRate
        
        // Buffer sizes for LUFS calculation (based on sample rate)
        // Momentary: 400ms, Short-term: 3s
        let bufferSize = Double(AudioConstants.masterMeteringBufferSize)
        let buffersPerSecond = sampleRate / bufferSize
        let momentaryBufferCount = Int(buffersPerSecond * 0.4)  // 400ms
        let shortTermBufferCount = Int(buffersPerSecond * 3.0)  // 3s
        
        // Initialize circular buffers (synchronous - called from main thread during setup)
        os_unfair_lock_lock(&meterLock)
        momentaryBuffer = CircularBuffer(capacity: momentaryBufferCount)
        shortTermBuffer = CircularBuffer(capacity: shortTermBufferCount)
        os_unfair_lock_unlock(&meterLock)
        
        // Install tap on master EQ output to get post-EQ levels
        // Use masterMeteringBufferSize for LUFS time window calculations (~85ms at 48kHz)
        // No throttling - every callback updates meters for proper transient response
        masterEQ.installTap(onBus: 0, bufferSize: AudioConstants.masterMeteringBufferSize, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let channelData = buffer.floatChannelData else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            
            let leftData = channelData[0]
            
            // PERFORMANCE: Use Accelerate framework for SIMD-optimized calculations
            // These vDSP functions are real-time safe (no allocations, SIMD optimized)
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
            
            // Combined mean square for stereo (simplified LUFS - no K-weighting)
            let combinedMeanSquare = (rmsLeft * rmsLeft + rmsRight * rmsRight) / 2.0
            
            // Convert to dB (LUFS reference: -0.691 dB offset for K-weighting, simplified here)
            let loudnessDB: Float = combinedMeanSquare > 0 ? 10.0 * log10(combinedMeanSquare) : -70.0
            
            // True peak calculation (simplified - actual true peak requires oversampling)
            let currentTruePeak = max(peakLeft, peakRight)
            let truePeakDB: Float = currentTruePeak > 0 ? 20.0 * log10(currentTruePeak) : -70.0
            
            // CLIP DETECTION (Issue #73): Count samples exceeding 0dBFS
            // Threshold: 0.999 to account for floating-point imprecision near digital maximum
            // Real-time safe: Simple counter increment, no allocations
            var clipsInBuffer = 0
            for frame in 0..<frameCount {
                let leftSample = abs(leftData[frame])
                if leftSample >= 0.999 {
                    clipsInBuffer += 1
                }
                
                if channelCount >= 2 {
                    let rightSample = abs(channelData[1][frame])
                    if rightSample >= 0.999 {
                        clipsInBuffer += 1
                    }
                }
            }
            
            // REAL-TIME SAFE: Write all meter values with lock - no dispatch to main thread.
            // os_unfair_lock is designed for this exact use case (minimal overhead, no priority inversion).
            // The main thread reads these values via the public properties which also use the lock.
            os_unfair_lock_lock(&self.meterLock)
            
            // Update standard meters
            self._masterLevelLeft = rmsLeft
            self._masterLevelRight = rmsRight
            self._masterPeakLeft = max(self._masterPeakLeft * self.masterPeakDecayRate, peakLeft)
            self._masterPeakRight = max(self._masterPeakRight * self.masterPeakDecayRate, peakRight)
            
            // Update true peak (hold highest value, slow decay)
            self._truePeak = max(self._truePeak - 0.1, truePeakDB)
            
            // Update loudness circular buffers - O(1) operations, real-time safe
            self.momentaryBuffer?.append(loudnessDB)
            self.shortTermBuffer?.append(loudnessDB)
            
            // Calculate momentary loudness (400ms average) using O(n) but small fixed-size buffer
            self._loudnessMomentary = self.momentaryBuffer?.powerAverage() ?? -70.0
            
            // Calculate short-term loudness (3s average)
            self._loudnessShortTerm = self.shortTermBuffer?.powerAverage() ?? -70.0
            
            // Update integrated loudness (gated - only count blocks above threshold)
            // Simplified gating: only include blocks above -70 LUFS
            if loudnessDB > self.loudnessGateThreshold {
                self.integratedSum += Double(pow(10, loudnessDB / 10.0))
                self.integratedCount += 1
                
                let integratedAvg = self.integratedSum / Double(max(1, self.integratedCount))
                self._loudnessIntegrated = integratedAvg > 0 ? Float(10.0 * log10(integratedAvg)) : -70.0
            }
            
            // Update clip detection state (Issue #73)
            if clipsInBuffer > 0 {
                self._clipCount += clipsInBuffer
                self._isClipping = true  // Latching indicator
            }
            
            os_unfair_lock_unlock(&self.meterLock)
        }
        
        masterMeterTapInstalled = true
    }
    
    // MARK: - Integrated Loudness Reset
    
    /// Reset integrated loudness measurement (call at start of new measurement period)
    func resetIntegratedLoudness() {
        os_unfair_lock_lock(&meterLock)
        integratedSum = 0.0
        integratedCount = 0
        _loudnessIntegrated = -70.0
        os_unfair_lock_unlock(&meterLock)
    }
    
    // MARK: - Test Support (Issue #73)
    
    #if DEBUG
    /// Process a buffer through clip detection logic for testing.
    /// This allows unit tests to validate clip detection without requiring the full audio engine.
    /// - Parameter buffer: The audio buffer to analyze for clipping
    func processBufferForTesting(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 0 else { return }
        
        // Detect clips in buffer (same logic as meter tap callback)
        var clipsInBuffer = 0
        for frame in 0..<frameCount {
            let leftSample = abs(channelData[0][frame])
            if leftSample >= 0.999 {
                clipsInBuffer += 1
            }
            
            if channelCount >= 2 {
                let rightSample = abs(channelData[1][frame])
                if rightSample >= 0.999 {
                    clipsInBuffer += 1
                }
            }
        }
        
        // Update clip detection state (thread-safe)
        if clipsInBuffer > 0 {
            os_unfair_lock_lock(&meterLock)
            _clipCount += clipsInBuffer
            _isClipping = true  // Latching indicator
            os_unfair_lock_unlock(&meterLock)
        }
    }
    #endif
    
    // MARK: - Level Queries
    
    /// Get current and peak levels for all tracks
    /// - Returns: Dictionary mapping track IDs to (current, peak) level tuples
    func getTrackLevels() -> [UUID: (current: Float, peak: Float)] {
        var levels: [UUID: (current: Float, peak: Float)] = [:]
        
        for (trackId, trackNode) in trackNodesAccessor() {
            // Use left channel as primary meter (stereo meters handled separately in UI)
            levels[trackId] = (current: trackNode.currentLevelLeft, peak: trackNode.peakLevelLeft)
        }
        
        return levels
    }
    
    /// Get the current level for a specific track
    /// - Parameter trackId: The UUID of the track
    /// - Returns: The current audio level (0.0 if track not found)
    func getTrackLevel(_ trackId: UUID) -> Float {
        guard let trackNode = trackNodesAccessor()[trackId] else { return 0.0 }
        return trackNode.currentLevelLeft
    }
    
    /// Get the combined master output level (post-fader)
    /// - Returns: Tuple of (current RMS, peak) levels
    func getMasterLevel() -> (current: Float, peak: Float) {
        let masterVolume = masterVolumeAccessor()
        
        // If master volume is 0, return silent levels
        guard masterVolume > 0.0 else {
            return (current: 0.0, peak: 0.0)
        }
        
        // Calculate RMS of all active (non-muted) tracks
        let trackLevels = getTrackLevels()
        let activeTracks = trackLevels.values.filter { $0.current > 0.0 }
        
        guard !activeTracks.isEmpty else {
            return (current: 0.0, peak: 0.0)
        }
        
        // Calculate RMS (Root Mean Square) for more accurate master level
        let sumOfSquares = activeTracks.map { $0.current * $0.current }.reduce(0, +)
        let rms = sqrt(sumOfSquares / Float(activeTracks.count))
        
        let maxPeak = activeTracks.map { $0.peak }.max() ?? 0.0
        
        // Apply master volume to the calculated levels (post-fader metering)
        let postFaderRMS = rms * masterVolume
        let postFaderPeak = maxPeak * masterVolume
        
        return (current: postFaderRMS, peak: postFaderPeak)
    }
    
    // MARK: - Cleanup
    
    /// Explicit deinit to prevent Swift Concurrency task leak
    /// Even @unchecked Sendable classes can have implicit tasks that cause
    /// memory corruption during deallocation if not properly cleaned up
}
