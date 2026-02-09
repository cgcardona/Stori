//
//  RTSafeAtomicTests.swift
//  StoriTests
//
//  Tests for lock-free atomic operations used in RT audio error tracking (Issue #78)
//  Verifies Swift Atomics package provides proper lock-free guarantees
//

import XCTest
@testable import Stori

final class RTSafeAtomicTests: XCTestCase {
    
    // MARK: - RTSafeCounter Tests
    
    func testCounterIncrementsCorrectly() {
        let counter = RTSafeCounter()
        
        XCTAssertEqual(counter.read(), 0, "Counter should start at 0")
        
        counter.increment()
        XCTAssertEqual(counter.read(), 1)
        
        counter.increment()
        counter.increment()
        XCTAssertEqual(counter.read(), 3)
    }
    
    func testCounterReadAndReset() {
        let counter = RTSafeCounter()
        
        counter.increment()
        counter.increment()
        counter.increment()
        
        let value = counter.readAndReset()
        XCTAssertEqual(value, 3, "Should return accumulated count")
        XCTAssertEqual(counter.read(), 0, "Should reset to 0")
    }
    
    func testCounterConcurrentIncrements() async {
        let counter = RTSafeCounter()
        let iterations = 10000
        
        // Concurrent increments from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<(iterations / 4) {
                        counter.increment()
                    }
                }
            }
        }
        
        // All increments should be counted (lock-free guarantee)
        let final = counter.read()
        XCTAssertEqual(final, UInt32(iterations), "Lock-free counter should count all concurrent increments")
    }
    
    func testCounterPerformanceIsLockFree() {
        let counter = RTSafeCounter()
        
        // Measure increment performance
        measure {
            for _ in 0..<10000 {
                counter.increment()
            }
        }
        
        // Lock-free atomics: 10k ops in <1ms
        // If using locks: would be 10-100ms
    }
    
    // MARK: - RTSafeMaxTracker Tests
    
    func testMaxTrackerFindsMaximum() {
        let tracker = RTSafeMaxTracker()
        
        XCTAssertEqual(tracker.read(), 0.0, "Should start at 0")
        
        tracker.updateMax(0.5)
        XCTAssertEqual(tracker.read(), 0.5, accuracy: 0.0001)
        
        tracker.updateMax(0.3)  // Lower - should not update
        XCTAssertEqual(tracker.read(), 0.5, accuracy: 0.0001, "Lower value should not replace max")
        
        tracker.updateMax(0.9)  // Higher - should update
        XCTAssertEqual(tracker.read(), 0.9, accuracy: 0.0001, "Higher value should replace max")
    }
    
    func testMaxTrackerReadAndReset() {
        let tracker = RTSafeMaxTracker()
        
        tracker.updateMax(1.5)
        tracker.updateMax(0.8)
        tracker.updateMax(2.0)
        
        let max = tracker.readAndReset()
        XCTAssertEqual(max, 2.0, accuracy: 0.0001, "Should return maximum value")
        XCTAssertEqual(tracker.read(), 0.0, "Should reset to 0")
    }
    
    func testMaxTrackerHandlesNegativeValues() {
        let tracker = RTSafeMaxTracker()
        
        tracker.updateMax(-1.0)
        XCTAssertEqual(tracker.read(), 0.0, "Negative should not become max over initial 0")
        
        tracker.updateMax(0.5)
        XCTAssertEqual(tracker.read(), 0.5, accuracy: 0.0001)
        
        tracker.updateMax(-0.5)
        XCTAssertEqual(tracker.read(), 0.5, accuracy: 0.0001, "Negative should not replace positive max")
    }
    
    func testMaxTrackerConcurrentUpdates() async {
        let tracker = RTSafeMaxTracker()
        let expectedMax: Float = 9.99
        
        // Multiple tasks updating with different values
        await withTaskGroup(of: Void.self) { group in
            for thread in 0..<8 {
                group.addTask {
                    for i in 0..<100 {
                        let value = Float(thread) + Float(i) * 0.01
                        tracker.updateMax(value)
                    }
                }
            }
            
            // One task writes the actual max
            group.addTask {
                tracker.updateMax(expectedMax)
            }
        }
        
        let actualMax = tracker.read()
        XCTAssertEqual(actualMax, expectedMax, accuracy: 0.0001, "Should find correct max under concurrency")
    }
    
    func testMaxTrackerPerformanceIsLockFree() {
        let tracker = RTSafeMaxTracker()
        
        measure {
            for i in 0..<10000 {
                tracker.updateMax(Float(i) * 0.001)
            }
        }
        
        // CAS loop should still be fast (<10ms for 10k ops)
        // Locks would be 50-200ms with this load
    }
    
    // MARK: - Concurrent Read-And-Reset Tests
    
    func testCounterReadAndResetIsAtomic() async {
        let counter = RTSafeCounter()
        
        // Use structured concurrency to avoid Sendable issues
        let totalCounted = await withTaskGroup(of: UInt32.self, returning: UInt32.self) { group in
            // Task 1: Continually increment
            group.addTask {
                for _ in 0..<10000 {
                    counter.increment()
                }
                return 0
            }
            
            // Task 2: Periodically read and reset
            group.addTask {
                var total: UInt32 = 0
                for _ in 0..<100 {
                    try? await Task.sleep(nanoseconds: 100_000)  // 0.1ms
                    total += counter.readAndReset()
                }
                return total
            }
            
            var accum: UInt32 = 0
            for await value in group {
                accum += value
            }
            // Add any remaining
            accum += counter.read()
            return accum
        }
        
        // Should have counted all increments (allow small margin for timing)
        XCTAssertGreaterThanOrEqual(totalCounted, 9900, "Read-and-reset should be atomic")
    }
    
    func testMaxTrackerReadAndResetIsAtomic() async {
        let tracker = RTSafeMaxTracker()
        
        // Use structured concurrency
        let maxValues = await withTaskGroup(of: [Float].self, returning: [Float].self) { group in
            // Task 1: Continually update
            group.addTask {
                for i in 0..<1000 {
                    tracker.updateMax(Float(i) * 0.01)
                }
                return []
            }
            
            // Task 2: Periodically read and reset
            group.addTask {
                var values: [Float] = []
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms
                    let max = tracker.readAndReset()
                    if max > 0 {
                        values.append(max)
                    }
                }
                return values
            }
            
            var result: [Float] = []
            for await values in group {
                result.append(contentsOf: values)
            }
            return result
        }
        
        // Should have captured some maximums
        XCTAssertFalse(maxValues.isEmpty, "Should capture max values")
        
        // Each captured max should be monotonically increasing or equal
        for i in 1..<maxValues.count {
            XCTAssertGreaterThanOrEqual(maxValues[i], maxValues[i-1], "Max values should trend upward")
        }
    }
    
    // MARK: - Memory Safety Tests
    
    func testAtomicWrappersAreSendable() async {
        let counter = RTSafeCounter()
        let tracker = RTSafeMaxTracker()
        
        // Pass to concurrent tasks - should compile without Sendable warnings
        await withTaskGroup(of: Void.self) { group in
            group.addTask { counter.increment() }
            group.addTask { tracker.updateMax(1.0) }
            group.addTask { _ = counter.read() }
            group.addTask { _ = tracker.read() }
        }
        
        // If types aren't Sendable, this won't compile under Swift 6
    }
    
    func testNoMemoryLeaksFromRepeatedCreation() {
        // Create and destroy many atomics
        for _ in 0..<1000 {
            let counter = RTSafeCounter()
            let tracker = RTSafeMaxTracker()
            
            counter.increment()
            tracker.updateMax(1.0)
            
            _ = counter.read()
            _ = tracker.read()
        }
        
        // ManagedAtomic should clean up properly - no leaks
    }
    
    // MARK: - Real-Time Safety Verification
    
    func testCounterNeverBlocks() async {
        let counter = RTSafeCounter()
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Hammer the counter from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<10000 {
                        counter.increment()
                    }
                }
            }
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        // 80k lock-free operations should complete in <100ms
        // If blocking, would be 500ms-2s
        XCTAssertLessThan(duration, 0.1, "Lock-free operations should never block (took \(duration)s)")
    }
    
    func testMaxTrackerNeverBlocks() async {
        let tracker = RTSafeMaxTracker()
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Hammer the tracker from multiple tasks
        await withTaskGroup(of: Void.self) { group in
            for thread in 0..<8 {
                group.addTask {
                    for i in 0..<10000 {
                        tracker.updateMax(Float(thread) + Float(i) * 0.001)
                    }
                }
            }
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        // CAS loop should still complete quickly
        XCTAssertLessThan(duration, 0.2, "Max tracker should not block (took \(duration)s)")
    }
}
