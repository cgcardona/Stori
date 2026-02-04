//
//  AudioEngineErrorTrackerTests.swift
//  StoriTests
//
//  Tests for audio engine error tracking and health analysis.
//

import XCTest
@testable import Stori

@MainActor
final class AudioEngineErrorTrackerTests: XCTestCase {
    
    var tracker: AudioEngineErrorTracker!
    
    override func setUp() async throws {
        tracker = AudioEngineErrorTracker.shared
        tracker.clearErrors()
    }
    
    override func tearDown() async throws {
        tracker.clearErrors()
    }
    
    // MARK: - Error Recording Tests
    
    func testRecordsErrorWithContext() {
        tracker.recordError(
            severity: .error,
            component: "TestComponent",
            message: "Test error message",
            context: ["key": "value"]
        )
        
        XCTAssertEqual(tracker.recentErrors.count, 1, "Should record one error")
        
        let error = tracker.recentErrors[0]
        XCTAssertEqual(error.severity, .error)
        XCTAssertEqual(error.component, "TestComponent")
        XCTAssertEqual(error.message, "Test error message")
        XCTAssertEqual(error.context["key"], "value")
    }
    
    func testMaintainsMaximumErrorHistory() {
        // Record more than max errors
        for i in 0..<250 {
            tracker.recordError(
                severity: .warning,
                component: "Test",
                message: "Error \(i)"
            )
        }
        
        XCTAssertLessThanOrEqual(tracker.recentErrors.count, 200, "Should not exceed max error history")
    }
    
    func testNewestErrorsFirst() {
        tracker.recordError(severity: .error, component: "Test", message: "First")
        tracker.recordError(severity: .error, component: "Test", message: "Second")
        
        XCTAssertEqual(tracker.recentErrors[0].message, "Second", "Newest error should be first")
        XCTAssertEqual(tracker.recentErrors[1].message, "First", "Oldest error should be last")
    }
    
    // MARK: - Health Analysis Tests
    
    func testHealthyWhenNoErrors() {
        XCTAssertEqual(tracker.engineHealth, .healthy, "Should be healthy with no errors")
    }
    
    func testUnhealthyAfterMultipleCriticalErrors() {
        // Record 3 critical errors quickly
        for i in 0..<3 {
            tracker.recordError(
                severity: .critical,
                component: "Test",
                message: "Critical error \(i)"
            )
        }
        
        // Force recalculation
        tracker.clearOldErrors(olderThan: 999999)
        
        // Health should be critical or unhealthy
        switch tracker.engineHealth {
        case .critical, .unhealthy:
            // Expected
            break
        default:
            XCTFail("Should be unhealthy after multiple critical errors, got: \(tracker.engineHealth)")
        }
    }
    
    func testHealthRecoveryAfterErrorsAge() async throws {
        // Record old errors
        for i in 0..<3 {
            tracker.recordError(
                severity: .critical,
                component: "Test",
                message: "Old error \(i)"
            )
        }
        
        // Wait a bit
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        
        // Clear old errors (simulate time passing)
        tracker.clearOldErrors(olderThan: 0.05)  // 50ms threshold
        
        // Health should improve
        XCTAssertEqual(tracker.engineHealth, .healthy, "Should recover after old errors are cleared")
    }
    
    // MARK: - Query Tests
    
    func testGetErrorsBySeverity() {
        tracker.recordError(severity: .critical, component: "Test", message: "Critical1")
        tracker.recordError(severity: .error, component: "Test", message: "Error1")
        tracker.recordError(severity: .warning, component: "Test", message: "Warning1")
        tracker.recordError(severity: .critical, component: "Test", message: "Critical2")
        
        let criticalErrors = tracker.getErrors(severity: .critical)
        XCTAssertEqual(criticalErrors.count, 2, "Should find 2 critical errors")
        
        let warnings = tracker.getErrors(severity: .warning)
        XCTAssertEqual(warnings.count, 1, "Should find 1 warning")
    }
    
    func testGetErrorsByComponent() {
        tracker.recordError(severity: .error, component: "AudioEngine", message: "Error1")
        tracker.recordError(severity: .error, component: "MIDIEngine", message: "Error2")
        tracker.recordError(severity: .error, component: "AudioEngine", message: "Error3")
        
        let audioEngineErrors = tracker.getErrors(component: "AudioEngine")
        XCTAssertEqual(audioEngineErrors.count, 2, "Should find 2 AudioEngine errors")
        
        let midiEngineErrors = tracker.getErrors(component: "MIDIEngine")
        XCTAssertEqual(midiEngineErrors.count, 1, "Should find 1 MIDIEngine error")
    }
    
    func testGetRecentErrors() async throws {
        // Record old error
        tracker.recordError(severity: .error, component: "Test", message: "Old")
        
        // Wait
        try await Task.sleep(nanoseconds: 150_000_000)  // 150ms
        
        // Record recent error
        tracker.recordError(severity: .error, component: "Test", message: "Recent")
        
        let recent = tracker.getRecentErrors(within: 0.1)  // Last 100ms
        
        XCTAssertEqual(recent.count, 1, "Should only return recent error")
        XCTAssertEqual(recent[0].message, "Recent")
    }
    
    // MARK: - Error Summary Tests
    
    func testErrorSummaryFormatsCorrectly() {
        tracker.recordError(severity: .critical, component: "Test", message: "C1")
        tracker.recordError(severity: .error, component: "Test", message: "E1")
        tracker.recordError(severity: .error, component: "Test", message: "E2")
        tracker.recordError(severity: .warning, component: "Test", message: "W1")
        
        let summary = tracker.getErrorSummary()
        
        XCTAssertTrue(summary.contains("1 critical"), "Summary should mention critical count")
        XCTAssertTrue(summary.contains("2 errors"), "Summary should mention error count")
        XCTAssertTrue(summary.contains("1 warnings"), "Summary should mention warning count")
    }
    
    func testClearErrorsWorks() {
        tracker.recordError(severity: .error, component: "Test", message: "Error1")
        tracker.recordError(severity: .warning, component: "Test", message: "Warning1")
        
        XCTAssertEqual(tracker.recentErrors.count, 2, "Should have 2 errors before clear")
        
        tracker.clearErrors()
        
        XCTAssertEqual(tracker.recentErrors.count, 0, "Should have 0 errors after clear")
        XCTAssertEqual(tracker.engineHealth, .healthy, "Health should be healthy after clear")
    }
}
