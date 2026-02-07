//
//  UpdateStore.swift
//  Stori
//
//  Persistent storage for update state: last check time, first-seen dates,
//  snooze deadlines, ignored versions, ETag cache, and beta opt-in.
//  Backed by UserDefaults with a dedicated suite.
//

import Foundation

// MARK: - UpdateStore

/// Persistent storage for update-related state.
/// Thread-safe: all access is on @MainActor via the owning UpdateService.
@MainActor
final class UpdateStore {
    
    // MARK: - Keys
    
    private enum Key {
        static let lastCheckDate        = "com.stori.update.lastCheckDate"
        static let lastKnownVersion     = "com.stori.update.lastKnownVersion"
        static let cachedETag           = "com.stori.update.cachedETag"
        static let cachedReleaseJSON    = "com.stori.update.cachedReleaseJSON"
        static let firstSeenDates       = "com.stori.update.firstSeenDates"  // [String: Date]
        static let ignoredVersions      = "com.stori.update.ignoredVersions" // [String]
        static let snoozedUntil         = "com.stori.update.snoozedUntil"    // Date?
        static let snoozedVersion       = "com.stori.update.snoozedVersion"  // String?
        static let betaOptIn            = "com.stori.update.betaOptIn"
        static let consecutiveFailures  = "com.stori.update.consecutiveFailures"
        static let bannerShownVersions  = "com.stori.update.bannerShownVersions" // [String]
    }
    
    // MARK: - Storage
    
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    // MARK: - Last Check
    
    var lastCheckDate: Date? {
        get { defaults.object(forKey: Key.lastCheckDate) as? Date }
        set { defaults.set(newValue, forKey: Key.lastCheckDate) }
    }
    
    var lastKnownVersion: String? {
        get { defaults.string(forKey: Key.lastKnownVersion) }
        set { defaults.set(newValue, forKey: Key.lastKnownVersion) }
    }
    
    // MARK: - ETag Cache
    
    var cachedETag: String? {
        get { defaults.string(forKey: Key.cachedETag) }
        set { defaults.set(newValue, forKey: Key.cachedETag) }
    }
    
    var cachedReleaseJSON: Data? {
        get { defaults.data(forKey: Key.cachedReleaseJSON) }
        set { defaults.set(newValue, forKey: Key.cachedReleaseJSON) }
    }
    
    // MARK: - First Seen Dates (for escalation)
    
    /// Returns the date a version was first detected, or nil if never seen.
    func firstSeenDate(for version: String) -> Date? {
        guard let dict = defaults.dictionary(forKey: Key.firstSeenDates) as? [String: Date] else {
            return nil
        }
        return dict[version]
    }
    
    /// Records when a version was first seen. No-op if already recorded.
    func recordFirstSeen(_ version: String, date: Date = Date()) {
        var dict = (defaults.dictionary(forKey: Key.firstSeenDates) as? [String: Date]) ?? [:]
        if dict[version] == nil {
            dict[version] = date
            defaults.set(dict, forKey: Key.firstSeenDates)
        }
    }
    
    /// Days since a version was first seen. Returns 0 if never seen.
    func daysSinceFirstSeen(_ version: String) -> Int {
        guard let firstSeen = firstSeenDate(for: version) else { return 0 }
        return Calendar.current.dateComponents([.day], from: firstSeen, to: Date()).day ?? 0
    }
    
    // MARK: - Ignored (Skipped) Versions
    
    var ignoredVersions: Set<String> {
        get {
            Set(defaults.stringArray(forKey: Key.ignoredVersions) ?? [])
        }
        set {
            defaults.set(Array(newValue), forKey: Key.ignoredVersions)
        }
    }
    
    func ignoreVersion(_ version: String) {
        var versions = ignoredVersions
        versions.insert(version)
        ignoredVersions = versions
    }
    
    func isVersionIgnored(_ version: String) -> Bool {
        ignoredVersions.contains(version)
    }
    
    /// Clears ignore for a specific version (used when a newer version supersedes)
    func clearIgnore(for version: String) {
        var versions = ignoredVersions
        versions.remove(version)
        ignoredVersions = versions
    }
    
    // MARK: - Snooze
    
    var snoozedUntil: Date? {
        get { defaults.object(forKey: Key.snoozedUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.snoozedUntil) }
    }
    
    var snoozedVersion: String? {
        get { defaults.string(forKey: Key.snoozedVersion) }
        set { defaults.set(newValue, forKey: Key.snoozedVersion) }
    }
    
    /// Snooze notifications for a specific version for N days
    func snooze(version: String, days: Int = 3) {
        snoozedVersion = version
        snoozedUntil = Calendar.current.date(byAdding: .day, value: days, to: Date())
    }
    
    /// Whether notifications are currently snoozed for this version
    func isSnoozed(for version: String) -> Bool {
        guard snoozedVersion == version,
              let until = snoozedUntil else {
            return false
        }
        return Date() < until
    }
    
    /// Clear snooze (called when snooze expires or user manually checks)
    func clearSnooze() {
        snoozedUntil = nil
        snoozedVersion = nil
    }
    
    // MARK: - Beta Opt-In
    
    var betaOptIn: Bool {
        get { defaults.bool(forKey: Key.betaOptIn) }
        set { defaults.set(newValue, forKey: Key.betaOptIn) }
    }
    
    // MARK: - Failure Tracking (for backoff)
    
    var consecutiveFailures: Int {
        get { defaults.integer(forKey: Key.consecutiveFailures) }
        set { defaults.set(newValue, forKey: Key.consecutiveFailures) }
    }
    
    func recordFailure() {
        consecutiveFailures += 1
    }
    
    func clearFailures() {
        consecutiveFailures = 0
    }
    
    /// Backoff interval based on consecutive failures: 1h, 2h, 4h, 8h, max 24h
    var backoffInterval: TimeInterval {
        let hours = min(pow(2.0, Double(consecutiveFailures)), 24.0)
        return hours * 3600
    }
    
    // MARK: - Banner Shown Tracking
    
    /// Versions for which we've already shown the initial banner
    var bannerShownVersions: Set<String> {
        get {
            Set(defaults.stringArray(forKey: Key.bannerShownVersions) ?? [])
        }
        set {
            defaults.set(Array(newValue), forKey: Key.bannerShownVersions)
        }
    }
    
    func markBannerShown(for version: String) {
        var versions = bannerShownVersions
        versions.insert(version)
        bannerShownVersions = versions
    }
    
    func hasBannerBeenShown(for version: String) -> Bool {
        bannerShownVersions.contains(version)
    }
    
    // MARK: - Reset
    
    /// Clear all update-related persistence (for testing or troubleshooting)
    func resetAll() {
        let keys = [
            Key.lastCheckDate, Key.lastKnownVersion,
            Key.cachedETag, Key.cachedReleaseJSON,
            Key.firstSeenDates, Key.ignoredVersions,
            Key.snoozedUntil, Key.snoozedVersion,
            Key.betaOptIn, Key.consecutiveFailures,
            Key.bannerShownVersions
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
    }
    
    // Root cause: @MainActor creates implicit actor isolation task-local storage
}
