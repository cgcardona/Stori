//
//  RecordingBufferPoolExhaustionTests.swift
//  StoriTests
//
//  Tests for recording buffer pool exhaustion handling (BUG FIX Issue #55)
//  Ensures no dropped samples under heavy load via dynamic pooling
//
//  BUG REPORT (GitHub Issue #55):
//  =================================
//  RecordingBufferPool uses fixed-size pool of pre-allocated buffers.
//  Under heavy load (many tracks recording, slow disk I/O), the pool
//  may exhaust, causing the real-time audio callback to either block
//  or drop audio samples - both result in permanent data loss.
//
//  ROOT CAUSE:
//  -----------
//  - Fixed pool size (16 buffers) determined at initialization
//  - Buffer acquisition returns nil when pool exhausted
//  - Audio callback must handle nil - either drops samples or blocks
//  - No emergency allocation or overflow handling
//  - Disk write priority not elevated for recording operations
//
//  SOLUTION:
//  ---------
//  1. Emergency buffer allocation when pool exhausts (prevents sample drops)
//  2. Dynamic overflow buffers (grow under pressure, shrink when idle)
//  3. Pool usage monitoring with proactive warnings
//  4. Elevated disk I/O priority (.userInitiated QoS)
//  5. Statistics tracking for debugging heavy load scenarios
//
//  PROFESSIONAL STANDARD:
//  ----------------------
//  Logic Pro, Pro Tools, and Cubase NEVER drop recording samples.
//  They use dynamic buffer allocation and priority I/O to guarantee
//  zero data loss regardless of system load.
//

import XCTest
@testable import Stori
import AVFoundation

final class RecordingBufferPoolExhaustionTests: XCTestCase {
    
    // MARK: - Test Configuration
    
    /// Sample rate for testing
    private let sampleRate: Double = 48000.0
    
    /// Buffer frame capacity
    private let frameCapacity: AVAudioFrameCount = 1024
    
    /// Initial pool size for tests
    private let testPoolSize: Int = 8
    
    // MARK: - Helper Methods
    
    /// Create a test buffer pool
    private func createTestPool() -> RecordingBufferPool {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        return RecordingBufferPool(format: format, frameCapacity: frameCapacity, poolSize: testPoolSize)
    }
    
    // MARK: - Core Pool Behavior
    
    /// Test basic acquire/release cycle
    func testBasicAcquireRelease() {
        let pool = createTestPool()
        
        // Initial state
        XCTAssertEqual(pool.availableCount, testPoolSize)
        XCTAssertEqual(pool.totalAcquired, 0)
        XCTAssertEqual(pool.totalReleased, 0)
        
        // Acquire buffer
        guard let buffer = pool.acquire() else {
            XCTFail("Should acquire buffer from full pool")
            return
        }
        
        XCTAssertEqual(pool.availableCount, testPoolSize - 1)
        XCTAssertEqual(pool.totalAcquired, 1)
        XCTAssertEqual(pool.currentBuffersInUse, 1)
        
        // Release buffer
        pool.release(buffer)
        
        XCTAssertEqual(pool.availableCount, testPoolSize)
        XCTAssertEqual(pool.totalReleased, 1)
        XCTAssertEqual(pool.currentBuffersInUse, 0)
    }
    
    /// Test pool exhaustion with emergency allocation (BUG FIX Issue #55)
    func testPoolExhaustionWithEmergencyAllocation() {
        let pool = createTestPool()
        var buffers: [AVAudioPCMBuffer] = []
        
        // Acquire all pre-allocated buffers
        for i in 0..<testPoolSize {
            guard let buffer = pool.acquire() else {
                XCTFail("Should acquire buffer \(i) from pool")
                return
            }
            buffers.append(buffer)
        }
        
        // Pool should be exhausted
        XCTAssertEqual(pool.availableCount, 0)
        XCTAssertTrue(pool.isExhausted)
        XCTAssertEqual(pool.emergencyAllocations, 0, "No emergency yet")
        
        // Next acquire should trigger emergency allocation (BUG FIX)
        guard let emergencyBuffer = pool.acquire() else {
            XCTFail("Emergency allocation should succeed")
            return
        }
        
        buffers.append(emergencyBuffer)
        
        // Verify emergency allocation statistics
        XCTAssertEqual(pool.emergencyAllocations, 1, "Should track emergency allocation")
        XCTAssertEqual(pool.overflowCount, 1, "Should have 1 overflow buffer")
        XCTAssertEqual(pool.totalPoolSize, testPoolSize + 1, "Total pool grew")
        
        // Release all buffers
        for buffer in buffers {
            pool.release(buffer)
        }
        
        // Pool should return to initial size (auto-shrink)
        XCTAssertEqual(pool.availableCount, testPoolSize, "Should return to initial size")
        XCTAssertEqual(pool.overflowCount, 0, "Overflow should be deallocated")
    }
    
    /// Test multiple emergency allocations under sustained load
    func testMultipleEmergencyAllocations() {
        let pool = createTestPool()
        var buffers: [AVAudioPCMBuffer] = []
        
        // Acquire more buffers than initial pool size
        for i in 0..<(testPoolSize + 10) {
            guard let buffer = pool.acquire() else {
                XCTFail("Should acquire buffer \(i) via emergency allocation")
                return
            }
            buffers.append(buffer)
        }
        
        // Verify emergency allocations occurred
        XCTAssertEqual(pool.emergencyAllocations, 10, "Should have 10 emergency allocations")
        XCTAssertEqual(pool.overflowCount, 10, "Should have 10 overflow buffers")
        XCTAssertEqual(pool.peakBuffersInUse, testPoolSize + 10, "Peak should track maximum")
        
        // Release half the buffers
        for i in 0..<10 {
            pool.release(buffers[i])
        }
        
        // Some overflow buffers should be deallocated (auto-shrink)
        XCTAssertLessThan(pool.overflowCount, 10, "Should shrink overflow")
    }
    
    // MARK: - Pool Usage Monitoring (BUG FIX Issue #55)
    
    /// Test pool usage ratio calculation
    func testPoolUsageRatio() {
        let pool = createTestPool()
        var buffers: [AVAudioPCMBuffer] = []
        
        // Empty pool: 0% usage
        XCTAssertEqual(pool.usageRatio, 0.0, accuracy: 0.01)
        XCTAssertFalse(pool.isLow)
        XCTAssertFalse(pool.isCritical)
        
        // Acquire 50% of pool
        for _ in 0..<(testPoolSize / 2) {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        XCTAssertEqual(pool.usageRatio, 0.5, accuracy: 0.1)
        XCTAssertFalse(pool.isLow, "Should not be low at 50%")
        
        // Acquire to 80% (low threshold)
        while pool.usageRatio < 0.8 {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        XCTAssertTrue(pool.isLow, "Should be low above 75%")
        XCTAssertFalse(pool.isCritical, "Should not be critical yet")
        
        // Acquire to 95% (critical threshold)
        while pool.usageRatio < 0.95 {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        XCTAssertTrue(pool.isCritical, "Should be critical above 90%")
        
        // Cleanup
        for buffer in buffers {
            pool.release(buffer)
        }
    }
    
    /// Test statistics snapshot
    func testStatisticsSnapshot() {
        let pool = createTestPool()
        var buffers: [AVAudioPCMBuffer] = []
        
        // Acquire some buffers
        for _ in 0..<5 {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        let stats = pool.getStatistics()
        
        XCTAssertEqual(stats.acquired, 5)
        XCTAssertEqual(stats.released, 0)
        XCTAssertEqual(stats.emergency, 0)
        XCTAssertEqual(stats.peak, 5)
        XCTAssertEqual(stats.available, testPoolSize - 5)
        
        // Cleanup
        for buffer in buffers {
            pool.release(buffer)
        }
    }
    
    // MARK: - Edge Cases
    
    /// Test buffer reuse after release
    func testBufferReuseAfterRelease() {
        let pool = createTestPool()
        
        // Acquire and release
        let buffer1 = pool.acquire()
        XCTAssertNotNil(buffer1)
        pool.release(buffer1!)
        
        // Acquire again - should reuse
        let buffer2 = pool.acquire()
        XCTAssertNotNil(buffer2)
        
        // Should be the same buffer instance (reused)
        XCTAssertTrue(buffer1 === buffer2, "Should reuse released buffer")
        
        pool.release(buffer2!)
    }
    
    /// Test concurrent acquire/release (simulates multi-threaded recording)
    func testConcurrentAcquireRelease() {
        let pool = createTestPool()
        let iterations = 100
        let expectation = self.expectation(description: "Concurrent operations")
        expectation.expectedFulfillmentCount = 2
        
        // Thread 1: Rapid acquire
        DispatchQueue.global().async {
            for _ in 0..<iterations {
                if let buffer = pool.acquire() {
                    usleep(10) // Simulate brief hold
                    pool.release(buffer)
                }
            }
            expectation.fulfill()
        }
        
        // Thread 2: Rapid acquire
        DispatchQueue.global().async {
            for _ in 0..<iterations {
                if let buffer = pool.acquire() {
                    usleep(10)
                    pool.release(buffer)
                }
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
        
        // Pool should be stable after concurrent operations
        XCTAssertEqual(pool.currentBuffersInUse, 0, "All buffers should be released")
    }
    
    /// Test maximum overflow limit
    func testMaximumOverflowLimit() {
        let pool = createTestPool()
        var buffers: [AVAudioPCMBuffer] = []
        
        // Max overflow is 32 (defined in RecordingBufferPool)
        let maxTotal = testPoolSize + 32
        
        // Acquire up to max
        for _ in 0..<maxTotal {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        XCTAssertEqual(buffers.count, maxTotal, "Should allocate up to max")
        
        // Next acquire should fail (absolute exhaustion)
        let overLimitBuffer = pool.acquire()
        XCTAssertNil(overLimitBuffer, "Should fail beyond max overflow")
        
        // Cleanup
        for buffer in buffers {
            pool.release(buffer)
        }
    }
    
    // MARK: - Regression: Heavy Load Scenarios (Issue #55)
    
    /// Test sustained load (simulates 16 tracks recording)
    func testSustainedHeavyLoad() {
        let pool = createTestPool()
        var activeBuffers: [AVAudioPCMBuffer] = []
        
        // Simulate 100 acquire/release cycles (16 tracks × ~6 buffers each)
        for cycle in 0..<100 {
            // Acquire burst (simulates 16 tracks recording simultaneously)
            for _ in 0..<16 {
                if let buffer = pool.acquire() {
                    activeBuffers.append(buffer)
                }
            }
            
            // Simulate disk write delay (release some buffers)
            if activeBuffers.count >= 10 {
                for _ in 0..<10 {
                    let buffer = activeBuffers.removeFirst()
                    pool.release(buffer)
                }
            }
            
            // Every 10 cycles, verify pool health
            if cycle % 10 == 0 {
                let stats = pool.getStatistics()
                XCTAssertGreaterThan(stats.available, 0, "Pool should not be fully exhausted at cycle \(cycle)")
            }
        }
        
        // Cleanup remaining buffers
        for buffer in activeBuffers {
            pool.release(buffer)
        }
        
        // Verify no permanent exhaustion
        XCTAssertGreaterThan(pool.availableCount, 0, "Pool should recover after load")
        
        // Verify emergency allocations occurred (proves overflow system worked)
        XCTAssertGreaterThan(pool.emergencyAllocations, 0, "Should have used emergency allocation under load")
    }
    
    /// Test slow disk I/O scenario (exact Issue #55 bug scenario)
    func testSlowDiskIOScenario() {
        let pool = createTestPool()
        var writeQueue: [AVAudioPCMBuffer] = []
        
        // Simulate 20 rapid acquires (slow disk can't keep up)
        for _ in 0..<20 {
            if let buffer = pool.acquire() {
                writeQueue.append(buffer)
            }
        }
        
        // All 20 should succeed (emergency allocation prevents drops)
        XCTAssertEqual(writeQueue.count, 20, "Should acquire all buffers via emergency allocation")
        XCTAssertGreaterThan(pool.emergencyAllocations, 0, "Should have triggered emergency allocation")
        
        // Gradually release as disk writes complete
        for buffer in writeQueue {
            pool.release(buffer)
            usleep(1000) // Simulate slow disk write (1ms each)
        }
        
        // Pool should return to initial size
        XCTAssertEqual(pool.availableCount, testPoolSize, "Should shrink back to initial size")
    }
    
    // MARK: - Performance Benchmarks
    
    /// Benchmark acquire/release performance
    func testAcquireReleasePerformance() {
        let pool = createTestPool()
        
        measure {
            for _ in 0..<1000 {
                if let buffer = pool.acquire() {
                    pool.release(buffer)
                }
            }
        }
    }
    
    /// Benchmark pool under pressure (emergency allocations)
    func testEmergencyAllocationPerformance() {
        let pool = createTestPool()
        var buffers: [AVAudioPCMBuffer] = []
        
        // Pre-exhaust pool
        for _ in 0..<testPoolSize {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        measure {
            // Measure emergency allocation performance
            for _ in 0..<100 {
                if let buffer = pool.acquire() {
                    buffers.append(buffer)
                }
            }
            
            // Release all
            for buffer in buffers.suffix(100) {
                pool.release(buffer)
            }
        }
        
        // Cleanup
        for buffer in buffers.prefix(testPoolSize) {
            pool.release(buffer)
        }
    }
    
    // MARK: - Regression Protection
    
    /// Test backward compatibility (ensure existing code still works)
    func testBackwardCompatibility() {
        let pool = createTestPool()
        
        // Old code expected nil on exhaustion - now gets emergency buffer
        var buffers: [AVAudioPCMBuffer] = []
        for _ in 0..<(testPoolSize + 5) {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        // All should succeed (no nil returns)
        XCTAssertEqual(buffers.count, testPoolSize + 5, "Should never return nil with emergency allocation")
        
        // Cleanup
        for buffer in buffers {
            pool.release(buffer)
        }
    }
    
    /// Test statistics reset
    func testStatisticsReset() {
        let pool = createTestPool()
        
        // Generate some activity
        var buffers: [AVAudioPCMBuffer] = []
        for _ in 0..<10 {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        XCTAssertGreaterThan(pool.totalAcquired, 0)
        
        // Reset statistics
        pool.resetStatistics()
        
        XCTAssertEqual(pool.totalAcquired, 0)
        XCTAssertEqual(pool.totalReleased, 0)
        XCTAssertEqual(pool.emergencyAllocations, 0)
        XCTAssertEqual(pool.peakBuffersInUse, 0)
        
        // Cleanup
        for buffer in buffers {
            pool.release(buffer)
        }
    }
}
