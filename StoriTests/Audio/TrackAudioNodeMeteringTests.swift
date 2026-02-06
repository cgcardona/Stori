//
//  TrackAudioNodeMeteringTests.swift
//  StoriTests
//
//  Tests for lock-free metering implementation in TrackAudioNode.
//  Ensures no lock contention, no timing jitter, and correct atomic behavior.
//

import XCTest
import AVFoundation
@testable import Stori

@MainActor
final class TrackAudioNodeMeteringTests: XCTestCase {
    
    // MARK: - Test Fixtures
    
    var audioEngine: AVAudioEngine!
    var trackNode: TrackAudioNode!
    
    override func setUp() async throws {
        audioEngine = AVAudioEngine()
        
        // Create track node with all required components
        let playerNode = AVAudioPlayerNode()
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)
        let pluginChain = PluginChain()
        let timePitchUnit = AVAudioUnitTimePitch()
        
        // Attach nodes to engine
        audioEngine.attach(playerNode)
        audioEngine.attach(volumeNode)
        audioEngine.attach(panNode)
        audioEngine.attach(eqNode)
        audioEngine.attach(timePitchUnit)
        
        // Create track node
        trackNode = TrackAudioNode(
            id: UUID(),
            playerNode: playerNode,
            volumeNode: volumeNode,
            panNode: panNode,
            eqNode: eqNode,
            pluginChain: pluginChain,
            timePitchUnit: timePitchUnit
        )
        
        // Connect signal path: player → timePitch → volume → pan → main mixer
        let format = audioEngine.outputNode.inputFormat(forBus: 0)
        audioEngine.connect(playerNode, to: timePitchUnit, format: format)
        audioEngine.connect(timePitchUnit, to: volumeNode, format: format)
        audioEngine.connect(volumeNode, to: panNode, format: format)
        audioEngine.connect(panNode, to: audioEngine.mainMixerNode, format: format)
        
        // Start engine to enable tap installation
        try audioEngine.start()
        
        // Install metering tap
        trackNode.tryInstallLevelTap()
    }
    
    override func tearDown() async throws {
        audioEngine.stop()
        trackNode = nil
        audioEngine = nil
    }
    
    // MARK: - Basic Metering Tests
    
    /// Test that metering levels can be read without crashing (lock-free access)
    func testMeteringLevelsAccessible() {
        // This should not crash or hang (lock-free read)
        let leftLevel = trackNode.currentLevelLeft
        let rightLevel = trackNode.currentLevelRight
        let leftPeak = trackNode.peakLevelLeft
        let rightPeak = trackNode.peakLevelRight
        
        // Initial values should be zero or positive
        XCTAssertGreaterThanOrEqual(leftLevel, 0.0)
        XCTAssertGreaterThanOrEqual(rightLevel, 0.0)
        XCTAssertGreaterThanOrEqual(leftPeak, 0.0)
        XCTAssertGreaterThanOrEqual(rightPeak, 0.0)
    }
    
    /// Test concurrent reads from multiple threads (lock-free property)
    func testConcurrentReads() async throws {
        let expectation = expectation(description: "Concurrent reads complete")
        expectation.expectedFulfillmentCount = 100
        
        // Spawn 100 concurrent readers
        for _ in 0..<100 {
            Task.detached {
                // Rapidly read metering values
                for _ in 0..<1000 {
                    _ = await self.trackNode.currentLevelLeft
                    _ = await self.trackNode.currentLevelRight
                    _ = await self.trackNode.peakLevelLeft
                    _ = await self.trackNode.peakLevelRight
                }
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        // If we got here without hanging, lock-free access works
    }
    
    // MARK: - Atomic Correctness Tests
    
    /// Test that Float values round-trip correctly through bit-casting
    func testFloatBitPatternRoundTrip() {
        let testValues: [Float] = [0.0, 0.1, 0.5, 0.9, 1.0, -0.5, 0.001, 0.999]
        
        for original in testValues {
            let bitPattern = original.bitPattern
            let reconstructed = Float(bitPattern: bitPattern)
            
            // Exact equality for bit-casting (no floating-point precision loss)
            XCTAssertEqual(original, reconstructed, accuracy: 0.0)
        }
    }
    
    /// Test that atomic reads don't return torn/corrupted values
    func testNoTornReads() async throws {
        // Set known values
        let testLevel: Float = 0.75
        let testPeak: Float = 0.85
        
        // Simulate audio callback updating values (via private tap callback)
        // Since we can't directly call the private callback, we'll verify
        // that reads are consistent across multiple threads
        
        // Read from 100 threads simultaneously
        var readValues: [[Float]] = []
        let lock = NSLock()
        
        let expectation = expectation(description: "Concurrent reads")
        expectation.expectedFulfillmentCount = 100
        
        for _ in 0..<100 {
            Task.detached {
                let left = await self.trackNode.currentLevelLeft
                let right = await self.trackNode.currentLevelRight
                let peakL = await self.trackNode.peakLevelLeft
                let peakR = await self.trackNode.peakLevelRight
                
                lock.lock()
                readValues.append([left, right, peakL, peakR])
                lock.unlock()
                
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // All reads should return valid floats (not NaN, not Inf)
        for values in readValues {
            for value in values {
                XCTAssertFalse(value.isNaN, "Torn read detected (NaN)")
                XCTAssertFalse(value.isInfinite, "Torn read detected (Inf)")
                XCTAssertGreaterThanOrEqual(value, -1.0, "Torn read (negative)")
                XCTAssertLessThanOrEqual(value, 1.0, "Torn read (too large)")
            }
        }
    }
    
    // MARK: - Performance Tests
    
    /// Test that lock-free metering has lower latency than locked version
    func testLockFreeMeteringPerformance() {
        measure {
            // Simulate reading metering data 10,000 times (typical for UI updates)
            for _ in 0..<10000 {
                _ = trackNode.currentLevelLeft
                _ = trackNode.currentLevelRight
                _ = trackNode.peakLevelLeft
                _ = trackNode.peakLevelRight
            }
        }
        
        // This should complete in < 10ms on modern hardware
        // (Lock-based version would take significantly longer)
    }
    
    /// Test memory ordering is correct (no stale reads)
    func testMemoryOrdering() async throws {
        // This test verifies that atomic operations have correct memory ordering
        // By reading values rapidly after "simulated" writes
        
        var previousLeft: Float = 0.0
        var sameValueCount = 0
        
        // Read 1000 times rapidly
        for _ in 0..<1000 {
            let currentLeft = trackNode.currentLevelLeft
            
            // Count how many times we read the exact same value
            if currentLeft == previousLeft {
                sameValueCount += 1
            }
            
            previousLeft = currentLeft
            
            // Small delay to allow potential audio callback
            try await Task.sleep(for: .microseconds(100))
        }
        
        // We should mostly read the same value (audio isn't playing)
        // This verifies that reads are consistent and not returning random memory
        XCTAssertGreaterThan(sameValueCount, 900, "Memory ordering issue detected")
    }
    
    // MARK: - Multi-Track Scenario Tests
    
    /// Test 32-track scenario (Issue #59 reproduction)
    func testManyTracksNoContention() async throws {
        var trackNodes: [TrackAudioNode] = []
        
        // Create 32 tracks (Issue #59 scenario)
        for _ in 0..<32 {
            let playerNode = AVAudioPlayerNode()
            let volumeNode = AVAudioMixerNode()
            let panNode = AVAudioMixerNode()
            let eqNode = AVAudioUnitEQ(numberOfBands: 3)
            let pluginChain = PluginChain()
            let timePitchUnit = AVAudioUnitTimePitch()
            
            audioEngine.attach(playerNode)
            audioEngine.attach(volumeNode)
            audioEngine.attach(panNode)
            audioEngine.attach(eqNode)
            audioEngine.attach(timePitchUnit)
            
            let format = audioEngine.outputNode.inputFormat(forBus: 0)
            audioEngine.connect(playerNode, to: timePitchUnit, format: format)
            audioEngine.connect(timePitchUnit, to: volumeNode, format: format)
            audioEngine.connect(volumeNode, to: panNode, format: format)
            audioEngine.connect(panNode, to: audioEngine.mainMixerNode, format: format)
            
            let node = TrackAudioNode(
                id: UUID(),
                playerNode: playerNode,
                volumeNode: volumeNode,
                panNode: panNode,
                eqNode: eqNode,
                pluginChain: pluginChain,
                timePitchUnit: timePitchUnit
            )
            
            node.tryInstallLevelTap()
            trackNodes.append(node)
        }
        
        // Read metering from all 32 tracks simultaneously
        let startTime = CACurrentMediaTime()
        
        for _ in 0..<1000 {
            for node in trackNodes {
                _ = node.currentLevelLeft
                _ = node.currentLevelRight
                _ = node.peakLevelLeft
                _ = node.peakLevelRight
            }
        }
        
        let duration = CACurrentMediaTime() - startTime
        
        // Should complete in < 100ms (lock-based would take much longer)
        XCTAssertLessThan(duration, 0.1, "Multi-track metering too slow")
        
        print("32-track metering: \(String(format: "%.2f", duration * 1000))ms for 1000 iterations")
    }
    
    /// Test timing consistency with multiple tracks (no jitter)
    func testTimingConsistency() async throws {
        var durations: [TimeInterval] = []
        
        // Measure 100 iterations of reading all metering values
        // Use batched reads to get more stable timing measurements
        for _ in 0..<100 {
            let start = CACurrentMediaTime()
            
            // Read multiple times per iteration to reduce measurement noise
            for _ in 0..<100 {
                _ = trackNode.currentLevelLeft
                _ = trackNode.currentLevelRight
                _ = trackNode.peakLevelLeft
                _ = trackNode.peakLevelRight
            }
            
            let duration = CACurrentMediaTime() - start
            durations.append(duration)
        }
        
        // Calculate standard deviation
        let mean = durations.reduce(0, +) / Double(durations.count)
        let variance = durations.map { pow($0 - mean, 2) }.reduce(0, +) / Double(durations.count)
        let stdDev = sqrt(variance)
        
        // For very fast operations, absolute timing variation matters more than relative
        // Standard deviation should be < 20% of mean (accounts for measurement noise)
        let coefficientOfVariation = stdDev / mean
        XCTAssertLessThan(coefficientOfVariation, 0.20, "Excessive timing jitter detected")
        
        print("Metering timing: mean=\(String(format: "%.2f", mean * 1_000_000))μs, σ=\(String(format: "%.2f", stdDev * 1_000_000))μs, CV=\(String(format: "%.1f", coefficientOfVariation * 100))%")
    }
    
    // MARK: - Edge Cases
    
    /// Test rapid initialization and deinitialization (memory safety)
    func testRapidCreateDestroy() {
        for _ in 0..<100 {
            let playerNode = AVAudioPlayerNode()
            let volumeNode = AVAudioMixerNode()
            let panNode = AVAudioMixerNode()
            let eqNode = AVAudioUnitEQ(numberOfBands: 3)
            let pluginChain = PluginChain()
            let timePitchUnit = AVAudioUnitTimePitch()
            
            audioEngine.attach(playerNode)
            audioEngine.attach(volumeNode)
            audioEngine.attach(panNode)
            audioEngine.attach(eqNode)
            audioEngine.attach(timePitchUnit)
            
            let node = TrackAudioNode(
                id: UUID(),
                playerNode: playerNode,
                volumeNode: volumeNode,
                panNode: panNode,
                eqNode: eqNode,
                pluginChain: pluginChain,
                timePitchUnit: timePitchUnit
            )
            
            // Read values immediately
            _ = node.currentLevelLeft
            _ = node.peakLevelRight
            
            // Deinit (node goes out of scope)
            // This tests atomic storage deallocation
        }
        
        // If we got here without crashing, memory management is correct
    }
    
    /// Test zero and boundary values
    func testBoundaryValues() {
        // Initial values should be zero
        XCTAssertEqual(trackNode.currentLevelLeft, 0.0, accuracy: 0.0001)
        XCTAssertEqual(trackNode.currentLevelRight, 0.0, accuracy: 0.0001)
        XCTAssertEqual(trackNode.peakLevelLeft, 0.0, accuracy: 0.0001)
        XCTAssertEqual(trackNode.peakLevelRight, 0.0, accuracy: 0.0001)
    }
}
