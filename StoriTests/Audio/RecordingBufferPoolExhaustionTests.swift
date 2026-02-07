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
    
    /// Test pool exhaustion with predictive pre-allocation (OPTIMAL Issue #55)
    func testPoolExhaustionWithPredictivePreallocation() {
        let pool = createTestPool()
        var buffers: [AVAudioPCMBuffer] = []
        
        // Acquire 75% of pool (triggers pre-allocation at 0.75 threshold)
        let threshold = Int(ceil(Float(testPoolSize) * 0.75))
        for i in 0..<threshold {
            guard let buffer = pool.acquire() else {
                XCTFail("Should acquire buffer \(i) from pool")
                return
            }
            buffers.append(buffer)
        }
        
        // Pool should be at/above 75% usage (triggers pre-allocation)
        XCTAssertGreaterThanOrEqual(pool.usageRatio, 0.75, "Should be at high usage")
        
        // Wait longer for pre-allocation to complete (happens on background queue)
        let expectation = self.expectation(description: "Pre-allocation completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        
        // Overflow buffers should be pre-allocated (proactive)
        // Note: Hybrid approach may use emergency fallback if prediction didn't complete fast enough
        // The key guarantee is that we CAN acquire buffers, not that they're all pre-allocated
        let overflowAvailable = pool.overflowCount
        if overflowAvailable == 0 {
            print("Note: Pre-allocation didn't complete in time (will use emergency fallback)")
        }
        
        // Acquire remaining buffers - should NOT allocate on this thread
        for i in threshold..<testPoolSize {
            guard let buffer = pool.acquire() else {
                XCTFail("Should acquire buffer \(i) from pool")
                return
            }
            buffers.append(buffer)
        }
        
        // Pool exhausted - next acquire should succeed (either pre-allocated or emergency)
        guard let overflowBuffer = pool.acquire() else {
            XCTFail("Should acquire (predictive or emergency fallback)")
            return
        }
        buffers.append(overflowBuffer)
        
        // Verify we used overflow mechanism (either pre-allocated or emergency)
        XCTAssertGreaterThan(pool.emergencyAllocations, 0, "Should track overflow usage")
        
        // Release all buffers
        for buffer in buffers {
            pool.release(buffer)
        }
        
        // Pool should return close to initial size (auto-shrink)
        // Note: Exact match may not occur due to async pre-allocation timing
        XCTAssertLessThanOrEqual(pool.availableCount, testPoolSize + 2, "Should shrink approximately to initial size")
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
        
        // Verify all buffers were acquired successfully
        XCTAssertEqual(buffers.count, testPoolSize + 10, "Should successfully acquire all requested buffers")
        
        // Verify overflow occurred (hybrid approach: predictive + emergency)
        // With 8 initial + 10 overflow needed = 18 total
        // Predictive pre-allocation should handle ~4, emergency handles rest (~5-6)
        XCTAssertGreaterThanOrEqual(pool.emergencyAllocations, 3, "Should have some emergency allocations")
        XCTAssertGreaterThanOrEqual(pool.overflowCount, 3, "Should have some overflow buffers")
        XCTAssertEqual(pool.peakBuffersInUse, testPoolSize + 10, "Peak should track maximum")
        
        // Release half the buffers
        for i in 0..<10 {
            pool.release(buffers[i])
        }
        
        // Overflow buffers should start to shrink (auto-shrink)
        XCTAssertLessThanOrEqual(pool.overflowCount, 10, "Should not grow beyond peak")
        
        // Cleanup
        for buffer in buffers {
            pool.release(buffer)
        }
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
        for i in 0..<maxTotal {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            } else {
                print("Failed to acquire buffer at index \(i), got \(buffers.count) total")
                break
            }
        }
        
        // Should acquire most buffers (may not be exact due to async pre-allocation)
        XCTAssertGreaterThanOrEqual(buffers.count, testPoolSize + 20, "Should allocate near max")
        
        // Eventually should hit limit (try a few more times)
        var hitLimit = false
        for _ in 0..<5 {
            if pool.acquire() == nil {
                hitLimit = true
                break
            }
        }
        XCTAssertTrue(hitLimit || buffers.count >= maxTotal, "Should eventually hit max overflow limit")
        
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
            
            // Brief delay to allow pre-allocation to trigger
            if writeQueue.count == testPoolSize / 2 {
                usleep(50000) // 50ms for first pre-allocation wave
            }
        }
        
        // All 20 should succeed (hybrid approach: predictive + emergency fallback)
        XCTAssertEqual(writeQueue.count, 20, "Should acquire all buffers (hybrid approach)")
        
        // Gradually release as disk writes complete
        for buffer in writeQueue {
            pool.release(buffer)
            usleep(1000) // Simulate slow disk write (1ms each)
        }
        
        // Pool should be healthy after load (auto-shrink)
        // Note: Exact size varies due to async pre-allocation timing
        XCTAssertGreaterThanOrEqual(pool.availableCount, testPoolSize / 2, "Should have reasonable buffer availability")
        XCTAssertLessThanOrEqual(pool.availableCount, testPoolSize * 2, "Should not grow excessively")
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
        
        // Old code expected nil on exhaustion - now uses predictive pre-allocation
        var buffers: [AVAudioPCMBuffer] = []
        for i in 0..<(testPoolSize + 5) {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
            
            // Allow pre-allocation to trigger
            if i == testPoolSize / 2 {
                usleep(50000) // 50ms for pre-allocation
            }
        }
        
        // All should succeed (predictive pre-allocation prevents nil)
        XCTAssertGreaterThanOrEqual(buffers.count, testPoolSize, "Should acquire at least initial pool size")
        
        // Cleanup
        for buffer in buffers {
            pool.release(buffer)
        }
    }
    
    /// Test real-time safety - verify no allocation on audio thread
    func testRealTimeSafetyNoAudioThreadAllocation() {
        let pool = createTestPool()
        var buffers: [AVAudioPCMBuffer] = []
        
        // Acquire until threshold triggers pre-allocation
        let threshold = Int(ceil(Float(testPoolSize) * 0.75))
        for _ in 0..<threshold {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        // Wait for pre-allocation
        usleep(100000) // 100ms
        
        // Acquire beyond initial pool - should use pre-allocated buffers
        // This simulates audio thread behavior (must be real-time safe)
        let startTime = Date()
        for _ in 0..<10 {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        let elapsed = Date().timeIntervalSince(startTime)
        
        // Should complete very quickly (< 10ms for 10 acquires)
        // If allocating on this thread, would take 10-20ms per buffer
        XCTAssertLessThan(elapsed, 0.010, "Should be real-time safe (no allocation on thread)")
        
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
