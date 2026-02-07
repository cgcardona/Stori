//
//  PluginDeferredDeallocationManager.swift
//  Stori
//
//  Manages deferred deallocation of plugins during hot-swap to prevent
//  use-after-free crashes when plugins are removed while render callback is active.
//
//  ARCHITECTURE (Issue #62):
//  When a plugin is hot-swapped during playback, the old plugin must not be
//  immediately deallocated because its render callback may still be executing.
//  This manager holds references to "zombie" plugins until it's safe to release them.
//
//  SAFETY MECHANISM:
//  1. Old plugin is disconnected from audio graph (stops new render calls)
//  2. Reference is moved to pendingDeallocations with timestamp
//  3. After safetyDelaySeconds (default 0.5s = ~24,000 render cycles @ 48kHz),
//     the plugin is released and deallocated
//
//  MEMORY IMPACT:
//  Typical plugin: 1-5 MB. With 0.5s delay, max overhead is ~5 MB per swap.
//  For 10 rapid swaps: ~50 MB temporary overhead, released after delay.
//

import Foundation
@preconcurrency import AVFoundation
import Observation

/// Manages deferred deallocation of plugins to prevent use-after-free during hot-swap
@Observable
@MainActor
final class PluginDeferredDeallocationManager {
    
    // MARK: - Types
    
    /// Represents a plugin pending deallocation
    private struct PendingDeallocation {
        let plugin: PluginInstance
        let scheduledTime: Date
        let trackId: UUID?
        let slotIndex: Int?
    }
    
    // MARK: - State
    
    /// Plugins waiting to be deallocated
    @ObservationIgnored
    private var pendingDeallocations: [PendingDeallocation] = []
    
    /// Task that periodically sweeps for plugins ready to deallocate
    @ObservationIgnored
    private var sweepTask: Task<Void, Never>?
    
    /// Safety delay in seconds before plugin can be deallocated
    /// 0.5 seconds = ~24,000 render cycles at 48kHz = extremely safe
    private let safetyDelaySeconds: TimeInterval = 0.5
    
    /// How often to check for plugins ready to deallocate
    private let sweepIntervalSeconds: TimeInterval = 0.1
    
    // MARK: - Singleton
    
    static let shared = PluginDeferredDeallocationManager()
    
    private init() {
        startSweepTask()
    }
    
    // MARK: - Public API
    
    /// Schedules a plugin for deferred deallocation
    /// Call this AFTER disconnecting the plugin from the audio graph
    /// - Parameters:
    ///   - plugin: The plugin instance to deallocate
    ///   - trackId: Optional track ID for logging
    ///   - slotIndex: Optional slot index for logging
    func schedulePluginForDeallocation(
        _ plugin: PluginInstance,
        trackId: UUID? = nil,
        slotIndex: Int? = nil
    ) {
        let pending = PendingDeallocation(
            plugin: plugin,
            scheduledTime: Date(),
            trackId: trackId,
            slotIndex: slotIndex
        )
        
        pendingDeallocations.append(pending)
        
        AppLogger.shared.info(
            "🗑️ Scheduled plugin '\(plugin.descriptor.name)' for deferred deallocation (safety delay: \(safetyDelaySeconds)s)",
            category: .audio
        )
    }
    
    /// Returns the number of plugins currently pending deallocation
    /// Useful for monitoring and testing
    var pendingCount: Int {
        pendingDeallocations.count
    }
    
    /// Force immediate cleanup of all pending plugins
    /// WARNING: Only use when engine is stopped (e.g., app shutdown, project close)
    func forceImmediateCleanup() {
        let count = pendingDeallocations.count
        if count > 0 {
            AppLogger.shared.info(
                "🗑️ Force cleanup: Deallocating \(count) pending plugins immediately",
                category: .audio
            )
            pendingDeallocations.removeAll()
        }
    }
    
    // MARK: - Private Implementation
    
    /// Starts the background task that periodically sweeps for plugins ready to deallocate
    private func startSweepTask() {
        sweepTask?.cancel()
        
        sweepTask = Task { @MainActor in
            while !Task.isCancelled {
                // Sleep first to avoid immediate sweep on startup
                try? await Task.sleep(nanoseconds: UInt64(sweepIntervalSeconds * 1_000_000_000))
                
                guard !Task.isCancelled else { break }
                
                sweepPendingDeallocations()
            }
        }
    }
    
    /// Checks pending deallocations and removes plugins that have waited long enough
    private func sweepPendingDeallocations() {
        guard !pendingDeallocations.isEmpty else { return }
        
        let now = Date()
        var deallocatedCount = 0
        
        // Remove plugins that have been pending longer than safety delay
        pendingDeallocations.removeAll { pending in
            let elapsed = now.timeIntervalSince(pending.scheduledTime)
            
            if elapsed >= safetyDelaySeconds {
                // Safe to deallocate now
                AppLogger.shared.info(
                    "✅ Deallocating plugin '\(pending.plugin.descriptor.name)' after \(String(format: "%.1f", elapsed))s safety delay",
                    category: .audio
                )
                
                // Unload the plugin (deallocates resources)
                pending.plugin.unload()
                
                deallocatedCount += 1
                return true  // Remove from array
            }
            
            return false  // Keep in array
        }
        
        if deallocatedCount > 0 {
            AppLogger.shared.info(
                "🗑️ Sweep completed: Deallocated \(deallocatedCount) plugins, \(pendingDeallocations.count) still pending",
                category: .audio
            )
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        sweepTask?.cancel()
        
        // Final cleanup on deinit
        if !pendingDeallocations.isEmpty {
            AppLogger.shared.warning(
                "PluginDeferredDeallocationManager deinit with \(pendingDeallocations.count) pending plugins",
                category: .audio
            )
        }
    }
}
