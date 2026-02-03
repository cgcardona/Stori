//
//  PluginLatencyManager.swift
//  Stori
//
//  Manages plugin delay compensation (PDC) to keep all tracks phase-aligned.
//  Professional DAWs compensate for plugin processing latency automatically.
//

import Foundation
import AVFoundation
import Observation
import os.lock

// MARK: - Plugin Latency Manager

/// Manages plugin delay compensation (PDC) for the entire project
@Observable
@MainActor
class PluginLatencyManager {
    
    // MARK: - Singleton
    
    static let shared = PluginLatencyManager()
    
    // MARK: - Observable Properties
    
    /// Whether PDC is enabled (can be disabled for low-latency monitoring)
    var isEnabled: Bool = true
    
    /// Maximum latency across all tracks (in samples)
    private(set) var maxLatencySamples: UInt32 = 0
    
    /// Maximum latency in milliseconds (for display)
    private(set) var maxLatencyMs: Double = 0.0
    
    // MARK: - Private Properties
    
    /// Current sample rate for latency calculations
    @ObservationIgnored
    private var sampleRate: Double = 48000.0
    
    /// Track latency info cache
    @ObservationIgnored
    private var trackLatencies: [UUID: TrackLatencyInfo] = [:]
    
    /// Compensation delays applied to each track (protected by compensationLock)
    @ObservationIgnored
    private nonisolated(unsafe) var compensationDelays: [UUID: UInt32] = [:]
    
    /// Lock for thread-safe access to compensation delays from audio thread
    @ObservationIgnored
    private nonisolated(unsafe) var compensationLock = os_unfair_lock_s()
    
    // MARK: - Types
    
    /// Information about a single track's latency
    struct TrackLatencyInfo {
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
    struct PluginLatencyEntry {
        let pluginId: UUID
        let pluginName: String
        let latencySamples: UInt32
        
        var latencyMs: Double {
            Double(latencySamples) / 44.1  // Approximate for display
        }
    }
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Configuration
    
    /// Update the sample rate used for latency calculations
    func setSampleRate(_ sampleRate: Double) {
        self.sampleRate = sampleRate
    }
    
    // MARK: - Latency Calculation
    
    /// Calculate the total latency for a single plugin
    func getPluginLatency(_ plugin: PluginInstance) -> UInt32 {
        guard let au = plugin.auAudioUnit else { return 0 }
        
        // AU latency is in seconds, convert to samples
        let latencySeconds = au.latency
        return UInt32(latencySeconds * sampleRate)
    }
    
    /// Calculate total latency for a track with the given plugins
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
        
        let info = TrackLatencyInfo(
            trackId: trackId,
            totalLatencySamples: totalLatency,
            pluginLatencies: pluginLatencies,
            sampleRate: sampleRate
        )
        
        trackLatencies[trackId] = info
        return info
    }
    
    /// Calculate latencies for all tracks and determine compensation delays
    func calculateCompensation(trackPlugins: [UUID: [PluginInstance]]) -> [UUID: UInt32] {
        // Calculate latency for each track
        var allLatencies: [TrackLatencyInfo] = []
        
        for (trackId, plugins) in trackPlugins {
            let info = calculateTrackLatency(trackId: trackId, plugins: plugins)
            allLatencies.append(info)
        }
        
        // Find maximum latency
        let maxLatency = allLatencies.map(\.totalLatencySamples).max() ?? 0
        self.maxLatencySamples = maxLatency
        self.maxLatencyMs = Double(maxLatency) / sampleRate * 1000.0
        
        // Calculate compensation for each track
        var compensation: [UUID: UInt32] = [:]
        
        for info in allLatencies {
            // Tracks with less latency need more compensation delay
            let needed = maxLatency - info.totalLatencySamples
            compensation[info.trackId] = needed
        }
        
        // Thread-safe write
        os_unfair_lock_lock(&compensationLock)
        self.compensationDelays = compensation
        os_unfair_lock_unlock(&compensationLock)
        
        return compensation
    }
    
    /// Get the compensation delay for a specific track
    /// Thread-safe: Can be called from audio thread (MIDI dispatch)
    nonisolated func getCompensationDelay(for trackId: UUID) -> UInt32 {
        os_unfair_lock_lock(&compensationLock)
        defer { os_unfair_lock_unlock(&compensationLock) }
        return compensationDelays[trackId] ?? 0
    }
    
    /// Get latency info for a specific track
    func getTrackLatency(for trackId: UUID) -> TrackLatencyInfo? {
        return trackLatencies[trackId]
    }
    
    // MARK: - Track Management
    
    /// Remove latency tracking for a track (when track is deleted)
    func removeTrack(_ trackId: UUID) {
        trackLatencies.removeValue(forKey: trackId)
        
        os_unfair_lock_lock(&compensationLock)
        compensationDelays.removeValue(forKey: trackId)
        os_unfair_lock_unlock(&compensationLock)
    }
    
    /// Clear all latency data
    func reset() {
        trackLatencies.removeAll()
        
        os_unfair_lock_lock(&compensationLock)
        compensationDelays.removeAll()
        os_unfair_lock_unlock(&compensationLock)
        
        maxLatencySamples = 0
        maxLatencyMs = 0.0
    }
}

// MARK: - TrackAudioNode Extension for PDC

extension TrackAudioNode {
    
    /// Apply delay compensation to this track
    /// Note: This creates a simple sample delay by adjusting scheduling offsets
    /// For a more sophisticated implementation, an actual delay node would be inserted
    func applyCompensationDelay(samples: UInt32) {
        // Store the compensation value for use during scheduling
        // This is applied during scheduleFromPosition by adding to the delay
        compensationDelaySamples = samples
    }
    
    /// Compensation delay in samples (stored in a private extension property)
    private static var compensationDelayKey: UInt8 = 0
    
    var compensationDelaySamples: UInt32 {
        get {
            objc_getAssociatedObject(self, &Self.compensationDelayKey) as? UInt32 ?? 0
        }
        set {
            objc_setAssociatedObject(self, &Self.compensationDelayKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
}

// MARK: - AudioEngine PDC Integration
// Note: The updateDelayCompensation() method is implemented directly in AudioEngine.swift
// because it needs access to the private trackNodes dictionary.
