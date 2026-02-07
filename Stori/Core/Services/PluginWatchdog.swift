//
//  PluginWatchdog.swift
//  Stori
//
//  Monitors plugins for crashes and hangs, providing graceful recovery.
//  When a plugin crashes, it's removed from the audio graph and the user
//  is notified with options to disable or retry.
//

import Foundation
import Observation

// MARK: - Plugin Watchdog

/// Monitors plugins for crashes and provides recovery mechanisms
@MainActor
@Observable
class PluginWatchdog {
    
    // MARK: - Singleton
    
    static let shared = PluginWatchdog()
    
    // MARK: - Types
    
    /// Information about a plugin crash
    struct CrashReport: Identifiable {
        let id = UUID()
        let pluginId: UUID
        let pluginName: String
        let pluginManufacturer: String
        let timestamp: Date
        let errorDescription: String
        let recoveryAttempted: Bool
        let recoverySucceeded: Bool
        
        var formattedTime: String {
            let formatter = DateFormatter()
            formatter.timeStyle = .medium
            return formatter.string(from: timestamp)
        }
    }
    
    /// Plugin health status
    enum PluginHealth {
        case healthy
        case warning      // Slow response
        case crashed
        case disabled
    }
    
    // MARK: - Observable Properties
    
    /// Recent crash reports
    var crashReports: [CrashReport] = []
    
    /// Plugins currently disabled due to crashes
    var disabledPlugins: Set<UUID> = []
    
    /// Plugins with recent issues (for UI warning indicators)
    var pluginHealth: [UUID: PluginHealth] = [:]
    
    /// Number of unread crash notifications
    var unreadCrashCount: Int = 0
    
    // MARK: - Private Properties
    
    /// Crash count per plugin (for repeat offender detection)
    @ObservationIgnored
    private var crashCounts: [String: Int] = [:]
    
    /// Maximum crashes before auto-disable
    @ObservationIgnored
    private let maxCrashesBeforeDisable = 3
    
    // MARK: - Initialization
    
    private init() {
        loadDisabledPlugins()
    }
    
    // MARK: - Crash Handling
    
    /// Report a plugin crash
    func reportCrash(plugin: PluginInstance, error: Error) {
        let descriptor = plugin.descriptor
        
        // Increment crash count
        let identifier = descriptor.identifier
        crashCounts[identifier] = (crashCounts[identifier] ?? 0) + 1
        
        // Create crash report
        let report = CrashReport(
            pluginId: descriptor.id,
            pluginName: descriptor.name,
            pluginManufacturer: descriptor.manufacturer,
            timestamp: Date(),
            errorDescription: error.localizedDescription,
            recoveryAttempted: false,
            recoverySucceeded: false
        )
        
        crashReports.insert(report, at: 0)
        unreadCrashCount += 1
        pluginHealth[descriptor.id] = .crashed
        
        // Mark for sandboxing (future loads will use out-of-process)
        SandboxedPluginHost.shared.markForSandboxing(descriptor)
        
        // Auto-disable repeat offenders
        if (crashCounts[identifier] ?? 0) >= maxCrashesBeforeDisable {
            disablePlugin(descriptor)
        }
        
        // Keep only last 50 crash reports
        if crashReports.count > 50 {
            crashReports = Array(crashReports.prefix(50))
        }
        
    }
    
    /// Attempt to recover a crashed plugin
    func attemptRecovery(_ plugin: PluginInstance) async -> Bool {
        let descriptor = plugin.descriptor
        
        // Remember the sample rate from the previous load (before unload clears state)
        let sampleRate = plugin.loadedSampleRate
        
        do {
            // Unload and reload the plugin
            plugin.unload()
            try await plugin.loadSandboxed(sampleRate: sampleRate) // Always use sandboxed mode after crash
            
            pluginHealth[descriptor.id] = .healthy
            return true
            
        } catch {
            pluginHealth[descriptor.id] = .disabled
            disabledPlugins.insert(descriptor.id)
            return false
        }
    }
    
    // MARK: - Plugin Management
    
    /// Disable a plugin (prevent loading)
    func disablePlugin(_ descriptor: PluginDescriptor) {
        disabledPlugins.insert(descriptor.id)
        pluginHealth[descriptor.id] = .disabled
        saveDisabledPlugins()
    }
    
    /// Re-enable a disabled plugin
    func enablePlugin(_ descriptor: PluginDescriptor) {
        disabledPlugins.remove(descriptor.id)
        pluginHealth.removeValue(forKey: descriptor.id)
        crashCounts.removeValue(forKey: descriptor.identifier)
        saveDisabledPlugins()
    }
    
    /// Check if a plugin is disabled
    func isDisabled(_ descriptor: PluginDescriptor) -> Bool {
        return disabledPlugins.contains(descriptor.id)
    }
    
    /// Get the health status of a plugin
    func getHealth(_ pluginId: UUID) -> PluginHealth {
        return pluginHealth[pluginId] ?? .healthy
    }
    
    // MARK: - Notifications
    
    /// Mark all crash notifications as read
    func markAllRead() {
        unreadCrashCount = 0
    }
    
    /// Clear crash history for a plugin
    func clearCrashHistory(for descriptor: PluginDescriptor) {
        crashReports.removeAll { $0.pluginId == descriptor.id }
        crashCounts.removeValue(forKey: descriptor.identifier)
    }
    
    /// Clear all crash history
    func clearAllCrashHistory() {
        crashReports.removeAll()
        crashCounts.removeAll()
        unreadCrashCount = 0
    }
    
    // MARK: - Persistence
    
    private func loadDisabledPlugins() {
        if let data = UserDefaults.standard.data(forKey: "plugin.disabled"),
           let ids = try? JSONDecoder().decode([UUID].self, from: data) {
            disabledPlugins = Set(ids)
            for id in ids {
                pluginHealth[id] = .disabled
            }
        }
    }
    
    private func saveDisabledPlugins() {
        if let data = try? JSONEncoder().encode(Array(disabledPlugins)) {
            UserDefaults.standard.set(data, forKey: "plugin.disabled")
        }
    }
    
    // MARK: - Cleanup
}

// MARK: - PluginInstance Extension for Watchdog Integration

extension PluginInstance {
    
    /// Load with crash monitoring
    /// - Parameter sampleRate: The sample rate to configure the AU buses with (should match engine's hardware rate)
    func loadWithWatchdog(sampleRate: Double) async throws {
        let watchdog = PluginWatchdog.shared
        
        // Check if plugin is disabled
        guard !watchdog.isDisabled(descriptor) else {
            throw PluginError.pluginDisabled
        }
        
        do {
            try await load(sampleRate: sampleRate)
            watchdog.pluginHealth[descriptor.id] = .healthy
        } catch {
            watchdog.reportCrash(plugin: self, error: error)
            throw error
        }
    }
}

// MARK: - Plugin Error Extension

extension PluginError {
    static let pluginDisabled = PluginError.instantiationFailed
}
