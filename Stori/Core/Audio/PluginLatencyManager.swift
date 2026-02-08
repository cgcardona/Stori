//
//  PluginLatencyManager.swift
//  Stori
//
//  Manages plugin delay compensation (PDC) to keep all tracks phase-aligned.
//  Professional DAWs compensate for plugin processing latency automatically.
//
//  NOTE: @preconcurrency import must be the first import of that module in this file (Swift compiler limitation).
@preconcurrency import AVFoundation
import Foundation
import os.lock

// MARK: - Plugin Latency Manager

/// Manages plugin delay compensation (PDC) for the entire project
///
/// # Architecture: Nonisolated, Thread-Safe Singleton
///
/// This class is intentionally NOT `@MainActor` because `getCompensationDelay`
/// is called from the audio render thread (via MIDIPlaybackEngine). Making the
/// entire class `@MainActor` would require an actor hop from the RT thread,
/// which is unacceptable for audio performance.
///
/// Thread safety is ensured via `os_unfair_lock` for all mutable state.
/// Methods that access `@MainActor`-isolated types (like `PluginInstance`)
/// are individually marked `@MainActor`.
///
/// # Plugin Delay Compensation (PDC)
///
/// PDC ensures all tracks stay phase-aligned when using latency-inducing plugins.
/// Without PDC, plugins with processing latency (like linear-phase EQs, lookahead compressors,
/// or convolution reverbs) cause timing misalignment between tracks.
///
/// ## How PDC Works
///
/// 1. **Measure Plugin Latency**: Each AU plugin reports its processing latency via `AVAudioUnit.latency`
/// 2. **Calculate Compensation**: Find the track with maximum latency, then delay all other tracks to match
/// 3. **Apply Delays**: Add sample-accurate delays to tracks during audio scheduling
///
/// ## WYHIWYG (What You Hear Is What You Get)
///
/// PDC is critical for WYHIWYG because:
/// - Playback uses PDC to align tracks in real-time
/// - Export uses the SAME PDC values to ensure the bounce matches playback exactly
/// - Without PDC, mixed audio suffers from phase smear, flamming, and loss of clarity
///
/// ## Thread Safety
///
/// - All mutable state is protected by `os_unfair_lock`
/// - `getCompensationDelay` can be called from the audio thread (lock-based, no allocation)
/// - `calculateCompensation` is `@MainActor` because it accesses `PluginInstance` properties
///
final class PluginLatencyManager: @unchecked Sendable {
    
    // MARK: - Singleton
    
    static let shared = PluginLatencyManager()
    
    // MARK: - Thread-Safe State
    
    /// Lock protecting all mutable state
    private var lock = os_unfair_lock_s()
    
    /// Whether PDC is enabled (can be disabled for low-latency monitoring)
    var isEnabled: Bool {
        get {
            os_unfair_lock_lock(&lock)
            defer { os_unfair_lock_unlock(&lock) }
            return _isEnabled
        }
        set {
            os_unfair_lock_lock(&lock)
            _isEnabled = newValue
            os_unfair_lock_unlock(&lock)
        }
    }
    
    /// Maximum latency across all tracks (in samples)
    var maxLatencySamples: UInt32 {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _maxLatencySamples
    }
    
    /// Maximum latency in milliseconds (for display)
    var maxLatencyMs: Double {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _maxLatencyMs
    }
    
    // MARK: - Private Backing Storage (lock-protected)
    
    private var _isEnabled: Bool = true
    private var _maxLatencySamples: UInt32 = 0
    private var _maxLatencyMs: Double = 0.0
    private var _sampleRate: Double = 48000.0
    private var _trackLatencies: [UUID: TrackLatencyInfo] = [:]
    private var _compensationDelays: [UUID: UInt32] = [:]
    
    // MARK: - Types
    
    /// Information about a single track's latency
    struct TrackLatencyInfo: Sendable {
        let trackId: UUID
        let totalLatencySamples: UInt32
        let pluginLatencies: [PluginLatencyEntry]
        let sampleRate: Double
        
        /// Total latency in seconds (uses actual sample rate)
        var latencySeconds: Double {
            Double(totalLatencySamples) / sampleRate
        }
        
        /// Total latency in milliseconds
        var latencyMs: Double {
            latencySeconds * 1000.0
        }
    }
    
    /// Latency entry for a single plugin
    struct PluginLatencyEntry: Sendable {
        let pluginId: UUID
        let pluginName: String
        let latencySamples: UInt32
        
        var latencyMs: Double {
            Double(latencySamples) / 44.1  // Approximate for display
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // Lock-based state is trivially cleaned up by ARC — no manual deinit needed.
    
    // MARK: - Configuration (Thread-Safe)
    
    /// Update the sample rate used for latency calculations
    func setSampleRate(_ sampleRate: Double) {
        os_unfair_lock_lock(&lock)
        _sampleRate = sampleRate
        os_unfair_lock_unlock(&lock)
    }
    
    /// Current sample rate (thread-safe read)
    var sampleRate: Double {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _sampleRate
    }
    
    // MARK: - Latency Calculation (@MainActor — accesses PluginInstance)
    
    /// Calculate the total latency for a single plugin
    /// - Note: `@MainActor` because `PluginInstance` is `@MainActor`-isolated
    @MainActor
    func getPluginLatency(_ plugin: PluginInstance) -> UInt32 {
        guard let au = plugin.auAudioUnit else { return 0 }
        
        // AU latency is in seconds, convert to samples
        let latencySeconds = au.latency
        let sr = sampleRate  // thread-safe read
        return UInt32(latencySeconds * sr)
    }
    
    /// Calculate total latency for a track with the given plugins
    /// - Note: `@MainActor` because `PluginInstance` is `@MainActor`-isolated
    @MainActor
    func calculateTrackLatency(trackId: UUID, plugins: [PluginInstance]) -> TrackLatencyInfo {
        var pluginLatencies: [PluginLatencyEntry] = []
        var totalLatency: UInt32 = 0
        
        for plugin in plugins {
            let latency = getPluginLatency(plugin)
            if latency > 0 {
                let entry = PluginLatencyEntry(
                    pluginId: plugin.id,
                    pluginName: plugin.descriptor.name,
                    latencySamples: latency
                )
                pluginLatencies.append(entry)
                totalLatency += latency
            }
        }
        
        let sr = sampleRate  // thread-safe read
        let info = TrackLatencyInfo(
            trackId: trackId,
            totalLatencySamples: totalLatency,
            pluginLatencies: pluginLatencies,
            sampleRate: sr
        )
        
        os_unfair_lock_lock(&lock)
        _trackLatencies[trackId] = info
        os_unfair_lock_unlock(&lock)
        
        return info
    }
    
    // MARK: - Testing Support
    
    /// TEST ONLY: Calculate compensation with explicit latency values
    /// Allows testing PDC logic without loading real Audio Unit plugins
    /// - Parameter trackLatencies: Map of track ID to total latency in samples
    /// - Returns: Map of track ID to compensation delay in samples
    func calculateCompensationWithExplicitLatencies(_ trackLatencies: [UUID: UInt32]) -> [UUID: UInt32] {
        os_unfair_lock_lock(&lock)
        
        guard _isEnabled else {
            os_unfair_lock_unlock(&lock)
            return trackLatencies.mapValues { _ in 0 }
        }
        
        // Find maximum latency
        let maxLatency = trackLatencies.values.max() ?? 0
        _maxLatencySamples = maxLatency
        _maxLatencyMs = Double(maxLatency) / _sampleRate * 1000.0
        
        // Calculate compensation for each track
        var compensation: [UUID: UInt32] = [:]
        
        for (trackId, latency) in trackLatencies {
            // Tracks with less latency need more compensation delay
            let needed = maxLatency - latency
            compensation[trackId] = needed
        }
        
        _compensationDelays = compensation
        os_unfair_lock_unlock(&lock)
        
        return compensation
    }
    
    /// Calculate latencies for all tracks and determine compensation delays
    /// - Note: `@MainActor` because `PluginInstance` is `@MainActor`-isolated
    @MainActor
    func calculateCompensation(trackPlugins: [UUID: [PluginInstance]]) -> [UUID: UInt32] {
        // Calculate latency for each track (MainActor: accesses PluginInstance)
        var allLatencies: [TrackLatencyInfo] = []
        
        for (trackId, plugins) in trackPlugins {
            let info = calculateTrackLatency(trackId: trackId, plugins: plugins)
            allLatencies.append(info)
        }
        
        // Lock for state mutation
        os_unfair_lock_lock(&lock)
        
        // Find maximum latency
        let maxLatency = allLatencies.map(\.totalLatencySamples).max() ?? 0
        _maxLatencySamples = maxLatency
        _maxLatencyMs = Double(maxLatency) / _sampleRate * 1000.0
        
        // Calculate compensation for each track
        var compensation: [UUID: UInt32] = [:]
        
        for info in allLatencies {
            // Tracks with less latency need more compensation delay
            let needed = maxLatency - info.totalLatencySamples
            compensation[info.trackId] = needed
        }
        
        _compensationDelays = compensation
        os_unfair_lock_unlock(&lock)
        
        return compensation
    }
    
    /// Get the compensation delay for a specific track
    /// Thread-safe: Can be called from audio thread (MIDI dispatch)
    func getCompensationDelay(for trackId: UUID) -> UInt32 {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _compensationDelays[trackId] ?? 0
    }
    
    /// Get latency info for a specific track
    func getTrackLatency(for trackId: UUID) -> TrackLatencyInfo? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return _trackLatencies[trackId]
    }
    
    // MARK: - Track Management (Thread-Safe)
    
    /// Remove latency tracking for a track (when track is deleted)
    func removeTrack(_ trackId: UUID) {
        os_unfair_lock_lock(&lock)
        _trackLatencies.removeValue(forKey: trackId)
        _compensationDelays.removeValue(forKey: trackId)
        os_unfair_lock_unlock(&lock)
    }
    
    /// Clear all latency data
    func reset() {
        os_unfair_lock_lock(&lock)
        _trackLatencies.removeAll()
        _compensationDelays.removeAll()
        _maxLatencySamples = 0
        _maxLatencyMs = 0.0
        os_unfair_lock_unlock(&lock)
    }
    
    // MARK: - Cleanup
}

// MARK: - AudioEngine PDC Integration
// Note: The updateDelayCompensation() method is implemented directly in AudioEngine.swift
// because it needs access to the private trackNodes dictionary.
