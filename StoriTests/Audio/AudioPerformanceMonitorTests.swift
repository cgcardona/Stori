//
//  AudioPerformanceMonitorTests.swift
//  StoriTests
//
//  Tests for audio performance monitoring and telemetry.
//

import XCTest
@testable import Stori

@MainActor
final class AudioPerformanceMonitorTests: XCTestCase {
    
    var monitor: AudioPerformanceMonitor!
    
    override func setUp() async throws {
        monitor = AudioPerformanceMonitor.shared
        monitor.reset()
        monitor.isEnabled = true
    }
    
    override func tearDown() async throws {
        monitor.reset()
    }
    
    // MARK: - Basic Timing Tests
    
    func testMeasuresSyncOperation() {
        let result = monitor.measure(operation: "TestOperation") {
            return 42
        }
        
        XCTAssertEqual(result, 42, "Should return operation result")
        XCTAssertEqual(monitor.recentEvents.count, 1, "Should record one event")
        
        let event = monitor.recentEvents[0]
        XCTAssertEqual(event.operation, "TestOperation")
        XCTAssertGreaterThan(event.durationMs, 0, "Should record positive duration")
    }
    
    func testMeasuresAsyncOperation() async {
        let result = await monitor.measureAsync(operation: "AsyncTest") {
            try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            return "done"
        }
        
        XCTAssertEqual(result, "done")
        XCTAssertEqual(monitor.recentEvents.count, 1)
        
        let event = monitor.recentEvents[0]
        XCTAssertGreaterThanOrEqual(event.durationMs, 10, accuracy: 5, "Should measure ~10ms")
    }
    
    func testTracksOperationStatistics() {
        // Measure same operation multiple times
        for _ in 0..<5 {
            monitor.measure(operation: "RepeatedOp") {
                // Simulate work
                _ = (0..<1000).reduce(0, +)
            }
        }
        
        let stats = monitor.getStatistics(for: "RepeatedOp")
        XCTAssertNotNil(stats)
        XCTAssertEqual(stats?.callCount, 5)
        XCTAssertGreaterThan(stats?.averageDurationMs ?? 0, 0)
        XCTAssertLessThanOrEqual(stats?.minDurationMs ?? 0, stats?.maxDurationMs ?? 0)
    }
    
    func testDetectsSlowOperations() async {
        // Simulate slow operation
        await monitor.measureAsync(operation: "SlowOp") {
            try? await Task.sleep(nanoseconds: 150_000_000)  // 150ms
        }
        
        let stats = monitor.getStatistics(for: "SlowOp")
        XCTAssertEqual(stats?.slowCount, 1, "Should detect slow operation")
        
        let event = monitor.recentEvents[0]
        XCTAssertTrue(event.isSlow, "Event should be marked as slow")
    }
    
    func testDetectsVerySlowOperations() async {
        // Simulate very slow operation
        await monitor.measureAsync(operation: "VerySlowOp") {
            try? await Task.sleep(nanoseconds: 600_000_000)  // 600ms
        }
        
        let stats = monitor.getStatistics(for: "VerySlowOp")
        XCTAssertEqual(stats?.verySlowCount, 1, "Should detect very slow operation")
        
        let event = monitor.recentEvents[0]
        XCTAssertTrue(event.isVerySlow, "Event should be marked as very slow")
    }
    
    // MARK: - Query Tests
    
    func testGetSlowestOperations() {
        // Record operations with different speeds
        monitor.measure(operation: "Fast") { _ = 1 + 1 }
        
        monitor.measure(operation: "Medium") {
            Thread.sleep(forTimeInterval: 0.01)  // 10ms
        }
        
        monitor.measure(operation: "Slow") {
            Thread.sleep(forTimeInterval: 0.05)  // 50ms
        }
        
        let slowest = monitor.getSlowestOperations(limit: 3)
        
        XCTAssertEqual(slowest.count, 3)
        XCTAssertEqual(slowest[0].operation, "Slow", "Slowest should be first")
        XCTAssertEqual(slowest[2].operation, "Fast", "Fastest should be last")
    }
    
    func testManualTimingWorks() {
        let start = monitor.startTiming()
        Thread.sleep(forTimeInterval: 0.02)  // 20ms
        monitor.recordTiming(operation: "ManualOp", startTime: start)
        
        XCTAssertEqual(monitor.recentEvents.count, 1)
        
        let event = monitor.recentEvents[0]
        XCTAssertGreaterThanOrEqual(event.durationMs, 20, "Should measure at least 20ms")
    }
    
    func testRespectsEnabledFlag() {
        monitor.isEnabled = false
        
        let result = monitor.measure(operation: "DisabledTest") {
            return 123
        }
        
        XCTAssertEqual(result, 123, "Should still return result")
        XCTAssertEqual(monitor.recentEvents.count, 0, "Should not record when disabled")
    }
}
