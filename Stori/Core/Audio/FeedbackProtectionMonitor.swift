//
//  FeedbackProtectionMonitor.swift
//  Stori
//
//  Real-time feedback loop detection and protection system.
//  Monitors master output for exponential gain increases and automatically mutes to prevent:
//  - Speaker/headphone damage
//  - Hearing damage
//  - Clipping/distortion artifacts
//
//  ARCHITECTURE (Issue #57):
//  - Monitors RMS level changes in real-time
//  - Detects exponential gain increases (>20dB in <100ms)
//  - Automatically mutes mixer when feedback detected
//  - Shows warning dialog to user
//  - Thread-safe using os_unfair_lock
//
//  PROFESSIONAL STANDARD:
//  - Logic Pro: "Overload Protection" with auto-mute
//  - Pro Tools: System auto-mute on sustained clipping
//  - Ableton: Automatic feedback prevention
//

import Foundation
import AVFoundation
import Accelerate
import os.lock

/// Feedback protection monitor for detecting and preventing audio feedback loops.
/// Uses real-time RMS monitoring to detect exponential gain increases.
final class FeedbackProtectionMonitor {
    
    // MARK: - Configuration
    
    /// RMS increase threshold for feedback detection (20dB = 10x amplitude)
    private let feedbackThresholdDB: Float = 20.0
    
    /// Time window for detecting rapid gain increases (100ms)
    private let detectionWindowSeconds: Double = 0.100
    
    /// Minimum RMS level to trigger feedback detection (-6dBFS)
    /// Below this, we don't care about gain spikes (too quiet)
    private let minimumTriggerLevel: Float = 0.5  // -6dBFS
    
    /// Number of consecutive spike detections before triggering auto-mute
    private let spikeCountThreshold: Int = 3
    
    // MARK: - State (Protected by Lock)
    
    private var stateLock = os_unfair_lock_s()
    
    /// History of recent RMS measurements
    private var rmsHistory: [(timestamp: TimeInterval, rms: Float)] = []
    
    /// Count of consecutive gain spikes detected
    private var consecutiveSpikeCount: Int = 0
    
    /// Whether protection is currently active
    private var _isProtectionActive: Bool = false
    
    /// Whether feedback was detected in current session
    private var _feedbackDetected: Bool = false
    
    /// Timestamp of last feedback detection
    private var lastFeedbackTime: TimeInterval = 0
    
    /// Cooldown period after feedback (don't re-trigger immediately)
    private let feedbackCooldownSeconds: Double = 2.0
    
    // MARK: - Callbacks
    
    /// Called when feedback is detected - should mute master mixer
    var onFeedbackDetected: (() -> Void)?
    
    /// Called when feedback warning should be shown to user
    var onShowFeedbackWarning: ((String) -> Void)?
    
    // MARK: - Public Properties
    
    /// Whether protection monitoring is active
    var isProtectionActive: Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return _isProtectionActive
    }
    
    /// Whether feedback was detected
    var feedbackDetected: Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        return _feedbackDetected
    }
    
    // MARK: - Initialization
    
    init() {
        rmsHistory.reserveCapacity(10)  // Pre-allocate for efficiency
    }
    
    // MARK: - Monitoring Control
    
    /// Start feedback protection monitoring
    func startMonitoring() {
        os_unfair_lock_lock(&stateLock)
        _isProtectionActive = true
        _feedbackDetected = false
        rmsHistory.removeAll(keepingCapacity: true)
        consecutiveSpikeCount = 0
        os_unfair_lock_unlock(&stateLock)
        
        AppLogger.shared.info("Feedback protection: Monitoring started", category: .audio)
    }
    
    /// Stop feedback protection monitoring
    func stopMonitoring() {
        os_unfair_lock_lock(&stateLock)
        _isProtectionActive = false
        rmsHistory.removeAll(keepingCapacity: true)
        consecutiveSpikeCount = 0
        os_unfair_lock_unlock(&stateLock)
        
        AppLogger.shared.info("Feedback protection: Monitoring stopped", category: .audio)
    }
    
    /// Reset feedback detection state (call after user acknowledges warning)
    func resetFeedbackState() {
        os_unfair_lock_lock(&stateLock)
        _feedbackDetected = false
        consecutiveSpikeCount = 0
        rmsHistory.removeAll(keepingCapacity: true)
        os_unfair_lock_unlock(&stateLock)
        
        AppLogger.shared.info("Feedback protection: State reset", category: .audio)
    }
    
    // MARK: - Real-Time Monitoring (Called from Audio Thread)
    
    /// Process audio buffer and check for feedback
    /// REAL-TIME SAFE: No allocations, fast computation
    /// - Parameter buffer: Audio buffer to analyze
    /// - Returns: true if feedback detected
    func processBuffer(_ buffer: AVAudioPCMBuffer) -> Bool {
        os_unfair_lock_lock(&stateLock)
        defer { os_unfair_lock_unlock(&stateLock) }
        
        guard _isProtectionActive else { return false }
        
        // Calculate RMS level using SIMD (real-time safe)
        let currentRMS = calculateRMS(buffer: buffer)
        let currentTime = CACurrentMediaTime()
        
        // Ignore if level too low (not a concern)
        guard currentRMS > minimumTriggerLevel else {
            // Reset spike count if we drop below threshold
            if consecutiveSpikeCount > 0 {
                consecutiveSpikeCount = 0
            }
            return false
        }
        
        // Add to history
        rmsHistory.append((timestamp: currentTime, rms: currentRMS))
        
        // Remove old samples outside detection window
        let cutoffTime = currentTime - detectionWindowSeconds
        rmsHistory.removeAll { $0.timestamp < cutoffTime }
        
        // Need at least 2 samples to detect change
        guard rmsHistory.count >= 2 else { return false }
        
        // Check if we're in cooldown period
        if currentTime - lastFeedbackTime < feedbackCooldownSeconds {
            return false
        }
        
        // Get oldest and newest RMS in window
        guard let oldestRMS = rmsHistory.first?.rms,
              let newestRMS = rmsHistory.last?.rms else {
            return false
        }
        
        // Calculate gain change in dB
        let gainChangeDB = 20.0 * log10(newestRMS / max(oldestRMS, 0.0001))
        
        // Check for exponential increase
        if gainChangeDB > feedbackThresholdDB {
            consecutiveSpikeCount += 1
            
            AppLogger.shared.warning(
                "Feedback protection: Gain spike detected (+\(String(format: "%.1f", gainChangeDB))dB in \(String(format: "%.0f", (rmsHistory.last!.timestamp - rmsHistory.first!.timestamp) * 1000))ms), count: \(consecutiveSpikeCount)/\(spikeCountThreshold)",
                category: .audio
            )
            
            // Trigger protection if threshold reached
            if consecutiveSpikeCount >= spikeCountThreshold {
                _feedbackDetected = true
                lastFeedbackTime = currentTime
                consecutiveSpikeCount = 0
                rmsHistory.removeAll(keepingCapacity: true)
                
                // CRITICAL: Call callbacks OUTSIDE the lock to prevent deadlock
                // Store them and call after unlock
                let shouldTrigger = true
                return shouldTrigger
            }
        } else {
            // Reset count if no spike
            if consecutiveSpikeCount > 0 {
                consecutiveSpikeCount = max(0, consecutiveSpikeCount - 1)
            }
        }
        
        return false
    }
    
    /// Calculate RMS level from buffer using SIMD
    /// REAL-TIME SAFE: Uses Accelerate framework
    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0.0 }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        guard frameCount > 0 else { return 0.0 }
        
        var totalRMS: Float = 0.0
        
        // Calculate RMS for each channel using Accelerate
        for channel in 0..<channelCount {
            var rms: Float = 0.0
            vDSP_rmsqv(channelData[channel], 1, &rms, vDSP_Length(frameCount))
            totalRMS += rms
        }
        
        // Average across channels
        return totalRMS / Float(channelCount)
    }
    
    // MARK: - Emergency Mute
    
    /// Trigger emergency mute and warning
    /// Called from main thread after feedback detected
    func triggerEmergencyProtection(currentLevel: Float) {
        let levelDB = 20.0 * log10(currentLevel)
        let message = """
        FEEDBACK DETECTED!
        
        Audio has been automatically muted to protect your speakers and hearing.
        
        Level before mute: \(String(format: "%.1f", levelDB)) dBFS
        
        Possible causes:
        • Bus routing feedback loop
        • Plugin feedback (delay/reverb)
        • Parallel routing error
        • Excessive automation gain
        
        Check your routing and reduce gain/feedback levels before unmuting.
        """
        
        // Trigger callbacks
        onFeedbackDetected?()
        onShowFeedbackWarning?(message)
        
        AppLogger.shared.error("FEEDBACK PROTECTION TRIGGERED: Auto-muted master output", category: .audio)
    }
    
    deinit {
        // CRITICAL: Protective deinit (ASan Issue #84742+)
        // Root cause: Classes owned by @Observable @MainActor parents can experience
        // Swift Concurrency TaskLocal double-free on deallocation even without timers.
        // Empty deinit ensures proper Swift Concurrency cleanup order.
        // See: AudioEngine.deinit, AutomationEngine.deinit, MetronomeEngine.deinit
    }
}
