//
//  AudioFormatCoordinator.swift
//  Stori
//
//  Single source of truth for audio format across all subsystems.
//  Ensures consistent sample rate and channel count throughout the audio graph.
//

//  NOTE: @preconcurrency import must be the first import of that module in this file (Swift compiler limitation).
@preconcurrency import AVFoundation
import Foundation
import Observation

// MARK: - Format Subscriber Protocol

/// Protocol for components that need to be notified of format changes
@MainActor
protocol AudioFormatSubscriber: AnyObject {
    /// Called when the canonical audio format changes (e.g., device change)
    func formatDidChange(_ newFormat: AVAudioFormat)
}

// Weak reference wrapper for subscriber array
private class WeakFormatSubscriber {
    weak var value: (any AudioFormatSubscriber)?
    init(value: any AudioFormatSubscriber) {
        self.value = value
    }
}

// MARK: - Audio Format Coordinator

/// Coordinates audio format changes across all subsystems.
/// Single source of truth for the canonical audio format used throughout the engine.
@Observable
@MainActor
final class AudioFormatCoordinator {
    
    // MARK: - State
    
    /// The canonical audio format for all connections
    /// CRITICAL: All audio graph connections MUST use this format
    private(set) var canonicalFormat: AVAudioFormat
    
    /// Generation counter for format changes (detect stale references)
    private(set) var formatGeneration: Int = 0
    
    /// Subscribers that need format change notifications
    @ObservationIgnored
    private var subscribers: [WeakFormatSubscriber] = []
    
    /// Last format change timestamp
    private(set) var lastFormatChange: Date
    
    // MARK: - Initialization
    
    init(initialFormat: AVAudioFormat) {
        self.canonicalFormat = initialFormat
        self.lastFormatChange = Date()
    }
    
    /// Convenience initializer with sample rate and channel count
    convenience init(sampleRate: Double, channels: AVAudioChannelCount = 2) {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels) else {
            fatalError("AudioFormatCoordinator: Could not create format with rate=\(sampleRate), channels=\(channels)")
        }
        self.init(initialFormat: format)
    }
    
    
    // MARK: - Format Updates
    
    /// Update the canonical format (e.g., when audio device changes).
    /// Broadcasts change to all subscribers atomically.
    /// Returns the new format generation number.
    @discardableResult
    func updateFormat(_ newFormat: AVAudioFormat, reason: String = "") -> Int {
        // Validate format is reasonable
        guard newFormat.sampleRate > 0, newFormat.channelCount > 0 else {
            AppLogger.shared.error("AudioFormatCoordinator: Invalid format (rate=\(newFormat.sampleRate), channels=\(newFormat.channelCount))", category: .audio)
            return formatGeneration
        }
        
        // Check if format actually changed
        if abs(canonicalFormat.sampleRate - newFormat.sampleRate) < 1.0 &&
           canonicalFormat.channelCount == newFormat.channelCount {
            AppLogger.shared.debug("AudioFormatCoordinator: Format unchanged, skipping broadcast", category: .audio)
            return formatGeneration
        }
        
        let oldRate = canonicalFormat.sampleRate
        let oldChannels = canonicalFormat.channelCount
        
        canonicalFormat = newFormat
        formatGeneration += 1
        lastFormatChange = Date()
        
        let reasonStr = reason.isEmpty ? "" : " (reason: \(reason))"
        AppLogger.shared.info(
            "AudioFormatCoordinator: Format changed from \(Int(oldRate))Hz/\(oldChannels)ch to \(Int(newFormat.sampleRate))Hz/\(newFormat.channelCount)ch\(reasonStr)",
            category: .audio
        )
        
        // Broadcast to all subscribers
        // Clean up dead weak references
        subscribers.removeAll { $0.value == nil }
        
        let subscriberCount = subscribers.compactMap({ $0.value }).count
        AppLogger.shared.debug("AudioFormatCoordinator: Broadcasting to \(subscriberCount) subscribers", category: .audio)
        
        for subscriber in subscribers.compactMap({ $0.value }) {
            subscriber.formatDidChange(newFormat)
        }
        
        return formatGeneration
    }
    
    // MARK: - Subscription Management
    
    /// Subscribe to format change notifications
    func subscribe(_ subscriber: any AudioFormatSubscriber) {
        // Check if already subscribed
        if subscribers.contains(where: { $0.value === subscriber }) {
            return
        }
        
        subscribers.append(WeakFormatSubscriber(value: subscriber))
        AppLogger.shared.debug("AudioFormatCoordinator: Added subscriber (total: \(subscribers.count))", category: .audio)
    }
    
    /// Unsubscribe from format change notifications
    func unsubscribe(_ subscriber: any AudioFormatSubscriber) {
        subscribers.removeAll { $0.value === subscriber }
    }
    
    // MARK: - Validation
    
    /// Validate that a format is compatible with the canonical format.
    /// Returns true if conversion would be transparent (same rate/channels).
    func isCompatible(_ format: AVAudioFormat) -> Bool {
        return abs(format.sampleRate - canonicalFormat.sampleRate) < 1.0 &&
               format.channelCount == canonicalFormat.channelCount
    }
    
    /// Check if a format requires conversion to match canonical format
    func requiresConversion(_ format: AVAudioFormat) -> Bool {
        return !isCompatible(format)
    }
    
    /// Get format information for debugging
    func getFormatInfo() -> String {
        return "\(Int(canonicalFormat.sampleRate))Hz, \(canonicalFormat.channelCount)ch, generation=\(formatGeneration)"
    }
    
    // MARK: - Cleanup
}
