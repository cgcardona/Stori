//
//  PluginGreylist.swift
//  Stori
//
//  Tracks plugins that have crashed and automatically loads them sandboxed.
//  Part of architecture refactor to improve crash isolation for AU plugins.
//

import Foundation

// MARK: - Plugin Crash Record

/// Record of a plugin crash event
struct PluginCrashRecord: Codable, Equatable {
    let pluginIdentifier: String  // "name:manufacturer" format
    let crashDate: Date
    let crashCount: Int
    let lastCrashReason: String?
    
    init(pluginIdentifier: String, crashDate: Date = Date(), crashCount: Int = 1, lastCrashReason: String? = nil) {
        self.pluginIdentifier = pluginIdentifier
        self.crashDate = crashDate
        self.crashCount = crashCount
        self.lastCrashReason = lastCrashReason
    }
}

// MARK: - Plugin Greylist

/// Service that tracks plugins that have crashed and recommends sandboxing them.
/// Plugins that crash repeatedly are "greylisted" and loaded out-of-process for safety.
///
/// Usage:
/// ```
/// // Check if a plugin should be sandboxed
/// let shouldSandbox = PluginGreylist.shared.shouldSandbox(descriptor)
///
/// // Report a crash
/// PluginGreylist.shared.recordCrash(for: descriptor, reason: "AU callback timeout")
///
/// // Manually whitelist a plugin (remove from greylist)
/// PluginGreylist.shared.whitelist(descriptor)
/// ```
@MainActor
class PluginGreylist {
    
    // MARK: - Singleton
    
    static let shared = PluginGreylist()
    
    // MARK: - Configuration
    
    /// Number of crashes before a plugin is automatically greylisted
    private let crashThreshold: Int = 2
    
    /// How long to keep crash records (30 days)
    private let crashRecordRetentionDays: Int = 30
    
    /// UserDefaults key for crash records
    private let crashRecordsKey = "com.tellurstori.pluginCrashRecords"
    
    /// UserDefaults key for manually whitelisted plugins
    private let whitelistKey = "com.tellurstori.pluginWhitelist"
    
    // MARK: - Storage
    
    /// Cached crash records
    private var crashRecords: [String: PluginCrashRecord] = [:]
    
    /// Manually whitelisted plugins (user override)
    private var whitelist: Set<String> = []
    
    // MARK: - Initialization
    
    private init() {
        loadCrashRecords()
        loadWhitelist()
        pruneOldRecords()
    }
    
    // MARK: - Public API
    
    /// Check if a plugin should be loaded sandboxed (out-of-process)
    /// Returns true if the plugin has crashed enough times to warrant sandboxing
    func shouldSandbox(_ descriptor: PluginDescriptor) -> Bool {
        let identifier = pluginIdentifier(for: descriptor)
        
        // User has explicitly whitelisted this plugin
        if whitelist.contains(identifier) {
            return false
        }
        
        // Check crash count
        if let record = crashRecords[identifier] {
            return record.crashCount >= crashThreshold
        }
        
        return false
    }
    
    /// Check if a plugin is greylisted (has crash history)
    func isGreylisted(_ descriptor: PluginDescriptor) -> Bool {
        let identifier = pluginIdentifier(for: descriptor)
        return crashRecords[identifier] != nil
    }
    
    /// Get crash record for a plugin
    func getCrashRecord(for descriptor: PluginDescriptor) -> PluginCrashRecord? {
        let identifier = pluginIdentifier(for: descriptor)
        return crashRecords[identifier]
    }
    
    /// Record a crash for a plugin
    /// - Parameters:
    ///   - descriptor: The plugin that crashed
    ///   - reason: Optional reason/description of the crash
    func recordCrash(for descriptor: PluginDescriptor, reason: String? = nil) {
        let identifier = pluginIdentifier(for: descriptor)
        
        let newRecord: PluginCrashRecord
        if let existingRecord = crashRecords[identifier] {
            // Increment crash count
            newRecord = PluginCrashRecord(
                pluginIdentifier: identifier,
                crashDate: Date(),
                crashCount: existingRecord.crashCount + 1,
                lastCrashReason: reason ?? existingRecord.lastCrashReason
            )
        } else {
            // First crash
            newRecord = PluginCrashRecord(
                pluginIdentifier: identifier,
                crashDate: Date(),
                crashCount: 1,
                lastCrashReason: reason
            )
        }
        
        crashRecords[identifier] = newRecord
        saveCrashRecords()
        
        
        if newRecord.crashCount >= crashThreshold {
        }
    }
    
    /// Manually whitelist a plugin (remove from greylist, don't sandbox)
    func whitelist(_ descriptor: PluginDescriptor) {
        let identifier = pluginIdentifier(for: descriptor)
        whitelist.insert(identifier)
        saveWhitelist()
        
    }
    
    /// Remove a plugin from the whitelist
    func removeFromWhitelist(_ descriptor: PluginDescriptor) {
        let identifier = pluginIdentifier(for: descriptor)
        whitelist.remove(identifier)
        saveWhitelist()
    }
    
    /// Clear crash history for a plugin
    func clearCrashHistory(for descriptor: PluginDescriptor) {
        let identifier = pluginIdentifier(for: descriptor)
        crashRecords.removeValue(forKey: identifier)
        saveCrashRecords()
        
    }
    
    /// Clear all crash records
    func clearAllCrashRecords() {
        crashRecords.removeAll()
        saveCrashRecords()
        
    }
    
    /// Get all greylisted plugins
    func getAllGreylistedPlugins() -> [PluginCrashRecord] {
        return Array(crashRecords.values).sorted { $0.crashCount > $1.crashCount }
    }
    
    /// Get count of greylisted plugins
    var greylistCount: Int {
        return crashRecords.count
    }
    
    // MARK: - Private Helpers
    
    /// Create a unique identifier for a plugin
    private func pluginIdentifier(for descriptor: PluginDescriptor) -> String {
        return "\(descriptor.name):\(descriptor.manufacturer)"
    }
    
    /// Load crash records from UserDefaults
    private func loadCrashRecords() {
        guard let data = UserDefaults.standard.data(forKey: crashRecordsKey) else {
            return
        }
        
        do {
            let records = try JSONDecoder().decode([String: PluginCrashRecord].self, from: data)
            crashRecords = records
        } catch {
        }
    }
    
    /// Save crash records to UserDefaults
    private func saveCrashRecords() {
        do {
            let data = try JSONEncoder().encode(crashRecords)
            UserDefaults.standard.set(data, forKey: crashRecordsKey)
        } catch {
        }
    }
    
    /// Load whitelist from UserDefaults
    private func loadWhitelist() {
        if let array = UserDefaults.standard.stringArray(forKey: whitelistKey) {
            whitelist = Set(array)
        }
    }
    
    /// Save whitelist to UserDefaults
    private func saveWhitelist() {
        UserDefaults.standard.set(Array(whitelist), forKey: whitelistKey)
    }
    
    /// Remove crash records older than retention period
    private func pruneOldRecords() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -crashRecordRetentionDays, to: Date())!
        
        var prunedCount = 0
        for (identifier, record) in crashRecords {
            if record.crashDate < cutoffDate {
                crashRecords.removeValue(forKey: identifier)
                prunedCount += 1
            }
        }
        
        if prunedCount > 0 {
            saveCrashRecords()
        }
    }
    
    // Root cause: @MainActor creates implicit actor isolation task-local storage
}

// MARK: - PluginDescriptor Extension

extension PluginDescriptor {
    
    /// Whether this plugin is greylisted (has crash history)
    @MainActor
    var isGreylisted: Bool {
        PluginGreylist.shared.isGreylisted(self)
    }
    
    /// Whether this plugin should be loaded sandboxed
    @MainActor
    var shouldLoadSandboxed: Bool {
        PluginGreylist.shared.shouldSandbox(self)
    }
}
