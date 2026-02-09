//
//  UpdateStoreTests.swift
//  StoriTests
//
//  Tests for UpdateStore persistence: ignored versions, snooze,
//  first-seen dates, ETag cache, and backoff logic.
//

import XCTest
@testable import Stori

@MainActor
final class UpdateStoreTests: XCTestCase {
    
    private var store: UpdateStore!
    private var testDefaults: UserDefaults!
    private var suiteName: String!
    
    override func setUp() async throws {
        try await super.setUp()
        suiteName = "com.stori.tests.updateStore.\(UUID().uuidString)"
        testDefaults = UserDefaults(suiteName: suiteName)!
        store = UpdateStore(defaults: testDefaults)
    }
    
    override func tearDown() async throws {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        testDefaults = nil
        store = nil
        suiteName = nil
        try await super.tearDown()
    }
    
    // MARK: - Last Check Date
    
    func testLastCheckDateInitiallyNil() {
        XCTAssertNil(store.lastCheckDate)
    }
    
    func testLastCheckDatePersists() {
        let date = Date()
        store.lastCheckDate = date
        XCTAssertEqual(store.lastCheckDate?.timeIntervalSince1970 ?? 0,
                       date.timeIntervalSince1970,
                       accuracy: 1.0)
    }
    
    // MARK: - ETag Cache
    
    func testETagCacheInitiallyNil() {
        XCTAssertNil(store.cachedETag)
        XCTAssertNil(store.cachedReleaseJSON)
    }
    
    func testETagCachePersists() {
        store.cachedETag = "W/\"abc123\""
        XCTAssertEqual(store.cachedETag, "W/\"abc123\"")
        
        let testData = "{\"tag_name\":\"v0.2.3\"}".data(using: .utf8)
        store.cachedReleaseJSON = testData
        XCTAssertEqual(store.cachedReleaseJSON, testData)
    }
    
    // MARK: - First Seen Dates
    
    func testFirstSeenDateInitiallyNil() {
        XCTAssertNil(store.firstSeenDate(for: "0.2.3"))
    }
    
    func testRecordFirstSeen() {
        let now = Date()
        store.recordFirstSeen("0.2.3", date: now)
        
        XCTAssertNotNil(store.firstSeenDate(for: "0.2.3"))
        XCTAssertEqual(store.firstSeenDate(for: "0.2.3")?.timeIntervalSince1970 ?? 0,
                       now.timeIntervalSince1970,
                       accuracy: 1.0)
    }
    
    func testRecordFirstSeenDoesNotOverwrite() {
        let early = Date(timeIntervalSince1970: 1000)
        let late = Date(timeIntervalSince1970: 2000)
        
        store.recordFirstSeen("0.2.3", date: early)
        store.recordFirstSeen("0.2.3", date: late)
        
        // Should keep the earlier date
        XCTAssertEqual(store.firstSeenDate(for: "0.2.3")?.timeIntervalSince1970 ?? 0,
                       early.timeIntervalSince1970,
                       accuracy: 1.0)
    }
    
    func testDaysSinceFirstSeen() {
        // Version never seen = 0 days
        XCTAssertEqual(store.daysSinceFirstSeen("0.2.3"), 0)
        
        // Version seen 5 days ago
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        store.recordFirstSeen("0.2.3", date: fiveDaysAgo)
        XCTAssertEqual(store.daysSinceFirstSeen("0.2.3"), 5)
    }
    
    // MARK: - Ignored Versions
    
    func testIgnoredVersionsInitiallyEmpty() {
        XCTAssertTrue(store.ignoredVersions.isEmpty)
    }
    
    func testIgnoreVersion() {
        store.ignoreVersion("0.2.3")
        XCTAssertTrue(store.isVersionIgnored("0.2.3"))
        XCTAssertFalse(store.isVersionIgnored("0.2.4"))
    }
    
    func testIgnoreMultipleVersions() {
        store.ignoreVersion("0.2.3")
        store.ignoreVersion("0.2.4")
        XCTAssertTrue(store.isVersionIgnored("0.2.3"))
        XCTAssertTrue(store.isVersionIgnored("0.2.4"))
        XCTAssertEqual(store.ignoredVersions.count, 2)
    }
    
    func testClearIgnore() {
        store.ignoreVersion("0.2.3")
        store.clearIgnore(for: "0.2.3")
        XCTAssertFalse(store.isVersionIgnored("0.2.3"))
    }
    
    // MARK: - Snooze
    
    func testSnoozedUntilInitiallyNil() {
        XCTAssertNil(store.snoozedUntil)
        XCTAssertNil(store.snoozedVersion)
    }
    
    func testSnooze() {
        store.snooze(version: "0.2.3", days: 3)
        
        XCTAssertTrue(store.isSnoozed(for: "0.2.3"))
        XCTAssertFalse(store.isSnoozed(for: "0.2.4"), "Different version should not be snoozed")
        
        XCTAssertNotNil(store.snoozedUntil)
        XCTAssertNotNil(store.snoozedVersion)
    }
    
    func testSnoozeExpires() {
        // Set snooze to expire in the past
        store.snoozedVersion = "0.2.3"
        store.snoozedUntil = Date(timeIntervalSinceNow: -1)
        
        XCTAssertFalse(store.isSnoozed(for: "0.2.3"), "Expired snooze should return false")
    }
    
    func testClearSnooze() {
        store.snooze(version: "0.2.3", days: 3)
        store.clearSnooze()
        
        XCTAssertNil(store.snoozedUntil)
        XCTAssertNil(store.snoozedVersion)
        XCTAssertFalse(store.isSnoozed(for: "0.2.3"))
    }
    
    // MARK: - Beta Opt-In
    
    func testBetaOptInDefaultsFalse() {
        XCTAssertFalse(store.betaOptIn)
    }
    
    func testBetaOptInPersists() {
        store.betaOptIn = true
        XCTAssertTrue(store.betaOptIn)
        
        store.betaOptIn = false
        XCTAssertFalse(store.betaOptIn)
    }
    
    // MARK: - Failure Tracking / Backoff
    
    func testConsecutiveFailuresInitiallyZero() {
        XCTAssertEqual(store.consecutiveFailures, 0)
    }
    
    func testRecordFailure() {
        store.recordFailure()
        XCTAssertEqual(store.consecutiveFailures, 1)
        
        store.recordFailure()
        XCTAssertEqual(store.consecutiveFailures, 2)
    }
    
    func testClearFailures() {
        store.recordFailure()
        store.recordFailure()
        store.clearFailures()
        XCTAssertEqual(store.consecutiveFailures, 0)
    }
    
    func testBackoffInterval() {
        // 0 failures = 1 hour (2^0)
        XCTAssertEqual(store.backoffInterval, 3600, accuracy: 1)
        
        // 1 failure = 2 hours
        store.recordFailure()
        XCTAssertEqual(store.backoffInterval, 7200, accuracy: 1)
        
        // 2 failures = 4 hours
        store.recordFailure()
        XCTAssertEqual(store.backoffInterval, 14400, accuracy: 1)
        
        // 3 failures = 8 hours
        store.recordFailure()
        XCTAssertEqual(store.backoffInterval, 28800, accuracy: 1)
    }
    
    func testBackoffMaxes24Hours() {
        // Many failures should max at 24 hours
        for _ in 0..<20 {
            store.recordFailure()
        }
        XCTAssertEqual(store.backoffInterval, 86400, accuracy: 1)
    }
    
    // MARK: - Banner Shown
    
    func testBannerShownInitiallyEmpty() {
        XCTAssertFalse(store.hasBannerBeenShown(for: "0.2.3"))
    }
    
    func testMarkBannerShown() {
        store.markBannerShown(for: "0.2.3")
        XCTAssertTrue(store.hasBannerBeenShown(for: "0.2.3"))
        XCTAssertFalse(store.hasBannerBeenShown(for: "0.2.4"))
    }
    
    // MARK: - Reset
    
    func testResetAll() {
        // Set various state
        store.lastCheckDate = Date()
        store.cachedETag = "test"
        store.ignoreVersion("0.2.3")
        store.snooze(version: "0.2.3", days: 3)
        store.betaOptIn = true
        store.recordFailure()
        store.markBannerShown(for: "0.2.3")
        store.recordFirstSeen("0.2.3")
        
        // Reset
        store.resetAll()
        
        // Verify everything is cleared
        XCTAssertNil(store.lastCheckDate)
        XCTAssertNil(store.cachedETag)
        XCTAssertNil(store.cachedReleaseJSON)
        XCTAssertTrue(store.ignoredVersions.isEmpty)
        XCTAssertNil(store.snoozedUntil)
        XCTAssertNil(store.snoozedVersion)
        XCTAssertFalse(store.betaOptIn)
        XCTAssertEqual(store.consecutiveFailures, 0)
        XCTAssertFalse(store.hasBannerBeenShown(for: "0.2.3"))
    }
}
