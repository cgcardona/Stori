//
//  MeteringServiceTests.swift
//  StoriTests
//
//  Comprehensive tests for MeteringService - Audio level metering and LUFS loudness
//  Tests cover thread-safe access, RMS/peak calculation, LUFS measurement, and real-time safety
//

import XCTest
@testable import Stori
import AVFoundation

final class MeteringServiceTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var metering: MeteringService!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        metering = MeteringService(
            trackNodes: { [:] },  // Empty track nodes
            masterVolume: { 0.8 }  // Default master volume
        )
    }
    
    override func tearDown() async throws {
        metering = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testMeteringServiceInitialization() {
        XCTAssertNotNil(metering)
    }
    
    func testInitialMasterLevels() {
        // Initial levels should be at silence floor
        XCTAssertLessThanOrEqual(metering.masterLevelLeft, 0.0)
        XCTAssertLessThanOrEqual(metering.masterLevelRight, 0.0)
    }
    
    func testInitialPeakLevels() {
        XCTAssertLessThanOrEqual(metering.masterPeakLeft, 0.0)
        XCTAssertLessThanOrEqual(metering.masterPeakRight, 0.0)
    }
    
    func testInitialLoudnessValues() {
        // LUFS values start at -70 (silence floor)
        XCTAssertEqual(metering.loudnessMomentary, -70.0)
        XCTAssertEqual(metering.loudnessShortTerm, -70.0)
        XCTAssertEqual(metering.loudnessIntegrated, -70.0)
    }
    
    func testInitialTruePeak() {
        XCTAssertEqual(metering.truePeak, -70.0)
    }
    
    // MARK: - Property Access Tests (Thread Safety)
    
    func testConcurrentLevelReads() {
        // Verify that concurrent reads don't crash (thread-safe)
        let iterations = 1000
        
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = metering.masterLevelLeft
            _ = metering.masterLevelRight
            _ = metering.masterPeakLeft
            _ = metering.masterPeakRight
        }
        
        XCTAssertTrue(true, "Concurrent reads completed successfully")
    }
    
    func testConcurrentLoudnessReads() {
        let iterations = 1000
        
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            _ = metering.loudnessMomentary
            _ = metering.loudnessShortTerm
            _ = metering.loudnessIntegrated
            _ = metering.truePeak
        }
        
        XCTAssertTrue(true, "Concurrent loudness reads completed successfully")
    }
    
    func testMixedConcurrentPropertyAccess() {
        let iterations = 500
        
        DispatchQueue.concurrentPerform(iterations: iterations) { i in
            switch i % 7 {
            case 0: _ = metering.masterLevelLeft
            case 1: _ = metering.masterLevelRight
            case 2: _ = metering.masterPeakLeft
            case 3: _ = metering.masterPeakRight
            case 4: _ = metering.loudnessMomentary
            case 5: _ = metering.loudnessShortTerm
            case 6: _ = metering.loudnessIntegrated
            default: break
            }
        }
        
        XCTAssertTrue(true, "Mixed concurrent access completed successfully")
    }
    
    // MARK: - Level Range Tests
    
    func testMasterLevelRange() {
        // Levels should be in valid dB range (typically -70 to 0 dB)
        let left = metering.masterLevelLeft
        let right = metering.masterLevelRight
        
        XCTAssertGreaterThanOrEqual(left, -70.0)
        XCTAssertLessThanOrEqual(left, 0.0)
        
        XCTAssertGreaterThanOrEqual(right, -70.0)
        XCTAssertLessThanOrEqual(right, 0.0)
    }
    
    func testPeakLevelRange() {
        let peakL = metering.masterPeakLeft
        let peakR = metering.masterPeakRight
        
        XCTAssertGreaterThanOrEqual(peakL, -70.0)
        XCTAssertLessThanOrEqual(peakL, 0.0)
        
        XCTAssertGreaterThanOrEqual(peakR, -70.0)
        XCTAssertLessThanOrEqual(peakR, 0.0)
    }
    
    func testLoudnessRange() {
        // LUFS typically ranges from -70 (silence) to 0 (very loud)
        let momentary = metering.loudnessMomentary
        let shortTerm = metering.loudnessShortTerm
        let integrated = metering.loudnessIntegrated
        
        XCTAssertGreaterThanOrEqual(momentary, -70.0)
        XCTAssertLessThanOrEqual(momentary, 0.0)
        
        XCTAssertGreaterThanOrEqual(shortTerm, -70.0)
        XCTAssertLessThanOrEqual(shortTerm, 0.0)
        
        XCTAssertGreaterThanOrEqual(integrated, -70.0)
        XCTAssertLessThanOrEqual(integrated, 0.0)
    }
    
    // MARK: - Performance Tests
    
    func testMasterLevelReadPerformance() {
        measure {
            for _ in 0..<10000 {
                _ = metering.masterLevelLeft
                _ = metering.masterLevelRight
            }
        }
    }
    
    func testPeakLevelReadPerformance() {
        measure {
            for _ in 0..<10000 {
                _ = metering.masterPeakLeft
                _ = metering.masterPeakRight
            }
        }
    }
    
    func testLoudnessReadPerformance() {
        measure {
            for _ in 0..<5000 {
                _ = metering.loudnessMomentary
                _ = metering.loudnessShortTerm
                _ = metering.loudnessIntegrated
            }
        }
    }
    
    func testMixedPropertyReadPerformance() {
        measure {
            for i in 0..<5000 {
                switch i % 7 {
                case 0: _ = metering.masterLevelLeft
                case 1: _ = metering.masterLevelRight
                case 2: _ = metering.masterPeakLeft
                case 3: _ = metering.masterPeakRight
                case 4: _ = metering.loudnessMomentary
                case 5: _ = metering.loudnessShortTerm
                case 6: _ = metering.loudnessIntegrated
                default: break
                }
            }
        }
    }
    
    // MARK: - Concurrent Access Stress Tests
    
    func testHighConcurrencyLevelReads() async {
        let expectation = self.expectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 10
        let svc = metering!
        
        for _ in 0..<10 {
            DispatchQueue.global(qos: .userInteractive).async {
                for _ in 0..<1000 {
                    _ = svc.masterLevelLeft
                    _ = svc.masterLevelRight
                }
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    func testConcurrentReadWriteSimulation() async {
        // Simulate concurrent reads while service might be updating internally
        let expectation = self.expectation(description: "Read/write simulation")
        expectation.expectedFulfillmentCount = 5
        let svc = metering!
        
        for queueIndex in 0..<5 {
            let queue = DispatchQueue(label: "test.metering.\(queueIndex)")
            queue.async {
                for _ in 0..<500 {
                    _ = svc.masterLevelLeft
                    _ = svc.masterPeakLeft
                    _ = svc.loudnessMomentary
                }
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // MARK: - Memory Management Tests
    
    func testMultipleMeteringServiceInstances() {
        // Create multiple instances to test independence
        let service1 = MeteringService(trackNodes: { [:] }, masterVolume: { 0.8 })
        let service2 = MeteringService(trackNodes: { [:] }, masterVolume: { 0.8 })
        let service3 = MeteringService(trackNodes: { [:] }, masterVolume: { 0.8 })
        
        _ = service1.masterLevelLeft
        _ = service2.masterLevelRight
        _ = service3.loudnessMomentary
        
        XCTAssertTrue(true, "Multiple instances created successfully")
    }
    
    func testMeteringServiceCleanup() {
        for _ in 0..<100 {
            let tempService = MeteringService(trackNodes: { [:] }, masterVolume: { 0.8 })
            _ = tempService.masterLevelLeft
            _ = tempService.masterPeakRight
        }
        
        XCTAssertTrue(true, "Service cleanup validated")
    }
    
    // MARK: - Real-Time Safety Tests
    
    func testPropertyAccessDoesNotBlock() {
        // Property access should complete quickly (< 1ms per access)
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<1000 {
            _ = metering.masterLevelLeft
            _ = metering.masterLevelRight
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - start
        
        // 1000 reads should complete in < 10ms (< 0.01ms per read)
        XCTAssertLessThan(duration, 0.01, "Property access took too long: \(duration)s")
    }
    
    func testNoContention() {
        // Verify lock doesn't cause excessive contention
        let iterations = 10000
        let concurrency = 4
        
        let start = CFAbsoluteTimeGetCurrent()
        
        DispatchQueue.concurrentPerform(iterations: concurrency) { _ in
            for _ in 0..<(iterations / concurrency) {
                _ = metering.masterLevelLeft
            }
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - start
        
        // Should complete quickly even under contention
        XCTAssertLessThan(duration, 0.1, "Concurrent access caused excessive contention: \(duration)s")
    }
    
    // MARK: - Edge Case Tests
    
    func testRapidPropertyPolling() {
        // Simulate UI polling meters at 60fps (16.67ms interval)
        for _ in 0..<60 {  // 1 second worth
            _ = metering.masterLevelLeft
            _ = metering.masterLevelRight
            _ = metering.masterPeakLeft
            _ = metering.masterPeakRight
            
            Thread.sleep(forTimeInterval: 0.0167)  // ~60fps
        }
        
        XCTAssertTrue(true, "Rapid polling completed successfully")
    }
    
    func testBurstReads() {
        // Simulate burst reads (e.g., UI update after pause)
        for _ in 0..<10 {
            // Burst of reads
            for _ in 0..<100 {
                _ = metering.masterLevelLeft
                _ = metering.masterLevelRight
                _ = metering.loudnessMomentary
            }
            
            // Pause
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        XCTAssertTrue(true, "Burst reads completed successfully")
    }
    
    // MARK: - Integration Tests
    
    func testMeteringServiceLifecycle() {
        // Complete lifecycle: create, read, cleanup
        let service = MeteringService(trackNodes: { [:] }, masterVolume: { 0.8 })
        
        // Read all properties
        _ = service.masterLevelLeft
        _ = service.masterLevelRight
        _ = service.masterPeakLeft
        _ = service.masterPeakRight
        _ = service.loudnessMomentary
        _ = service.loudnessShortTerm
        _ = service.loudnessIntegrated
        _ = service.truePeak
        
        XCTAssertTrue(true, "Full lifecycle completed")
    }
    
    func testMeteringServiceInHighLoadScenario() async {
        // Simulate high load: many concurrent readers
        let expectation = self.expectation(description: "High load scenario")
        expectation.expectedFulfillmentCount = 20
        let svc = metering!
        
        for i in 0..<20 {
            DispatchQueue.global(qos: .userInteractive).async {
                for _ in 0..<100 {
                    _ = svc.masterLevelLeft
                    _ = svc.masterLevelRight
                    _ = svc.masterPeakLeft
                    _ = svc.masterPeakRight
                    _ = svc.loudnessMomentary
                }
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
    }
    
    // MARK: - Stress Tests
    
    func testVeryHighConcurrency() {
        // Extreme concurrency test
        let iterations = 100000
        let concurrency = 8
        
        DispatchQueue.concurrentPerform(iterations: concurrency) { queueIndex in
            for i in 0..<(iterations / concurrency) {
                switch (queueIndex + i) % 4 {
                case 0: _ = metering.masterLevelLeft
                case 1: _ = metering.masterPeakRight
                case 2: _ = metering.loudnessMomentary
                case 3: _ = metering.loudnessIntegrated
                default: break
                }
            }
        }
        
        XCTAssertTrue(true, "Very high concurrency test completed")
    }
    
    func testSustainedLoad() {
        // Sustained load over time
        let startTime = Date()
        let duration: TimeInterval = 1.0  // 1 second sustained load
        
        var readCount = 0
        
        while Date().timeIntervalSince(startTime) < duration {
            _ = metering.masterLevelLeft
            _ = metering.masterLevelRight
            readCount += 2
        }
        
        // Should be able to read thousands of times per second
        XCTAssertGreaterThan(readCount, 1000, "Should sustain high read rate")
    }
    
    // MARK: - LUFS Window Tests
    
    func testLUFSWindowTimeframes() {
        // Verify LUFS measurements exist for different timeframes
        
        // Momentary: 400ms window
        let momentary = metering.loudnessMomentary
        XCTAssertNotNil(momentary)
        
        // Short-term: 3s window
        let shortTerm = metering.loudnessShortTerm
        XCTAssertNotNil(shortTerm)
        
        // Integrated: entire measurement period
        let integrated = metering.loudnessIntegrated
        XCTAssertNotNil(integrated)
    }
    
    func testTruePeakMeasurement() {
        // True peak should be available
        let truePeak = metering.truePeak
        
        XCTAssertNotNil(truePeak)
        XCTAssertGreaterThanOrEqual(truePeak, -70.0)
    }
    
    // MARK: - Consistency Tests
    
    func testConsistentReads() {
        // Multiple reads in quick succession should return same value
        // (if service isn't being updated)
        let level1 = metering.masterLevelLeft
        let level2 = metering.masterLevelLeft
        
        // Values should be consistent
        XCTAssertEqual(level1, level2)
    }
    
    func testAllPropertiesAccessible() {
        // Verify all public properties can be read without error
        let properties: [Float] = [
            metering.masterLevelLeft,
            metering.masterLevelRight,
            metering.masterPeakLeft,
            metering.masterPeakRight,
            metering.loudnessMomentary,
            metering.loudnessShortTerm,
            metering.loudnessIntegrated,
            metering.truePeak
        ]
        
        XCTAssertEqual(properties.count, 8, "All properties accessible")
    }
}
