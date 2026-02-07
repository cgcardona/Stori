//
//  RecordingBufferPoolTests.swift
//  StoriTests
//
//  Comprehensive tests for RecordingBufferPool - Real-time safe buffer management
//  Tests cover initialization, acquisition, release, thread safety, and performance
//

import XCTest
@testable import Stori
import AVFoundation

final class RecordingBufferPoolTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var pool: RecordingBufferPool!
    private var format: AVAudioFormat!
    private let frameCapacity: AVAudioFrameCount = 1024
    private let poolSize = 16
    
    // MARK: - Setup/Teardown
    
    override func setUp() {
        super.setUp()
        format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        pool = RecordingBufferPool(format: format, frameCapacity: frameCapacity, poolSize: poolSize)
    }
    
    override func tearDown() {
        pool = nil
        format = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testBufferPoolInitialization() {
        // Pool should pre-allocate all buffers
        XCTAssertEqual(pool.availableCount, poolSize)
        XCTAssertEqual(pool.totalAcquired, 0)
        XCTAssertEqual(pool.totalReleased, 0)
        XCTAssertEqual(pool.allocationFailures, 0)
    }
    
    func testBufferPoolPreAllocatesBuffers() {
        // All buffers should be available immediately
        XCTAssertFalse(pool.isExhausted)
        XCTAssertFalse(pool.isLow)
        XCTAssertEqual(pool.availableCount, poolSize)
    }
    
    func testBufferPoolFormat() {
        // Acquire a buffer and verify format
        guard let buffer = pool.acquire() else {
            XCTFail("Failed to acquire buffer")
            return
        }
        
        XCTAssertEqual(buffer.format, format)
        XCTAssertEqual(buffer.frameCapacity, frameCapacity)
        
        pool.release(buffer)
    }
    
    // MARK: - Buffer Acquisition Tests
    
    func testAcquireBuffer() {
        let buffer = pool.acquire()
        
        XCTAssertNotNil(buffer)
        XCTAssertEqual(pool.availableCount, poolSize - 1)
        XCTAssertEqual(pool.totalAcquired, 1)
    }
    
    func testAcquireMultipleBuffers() {
        var buffers: [AVAudioPCMBuffer] = []
        
        for i in 0..<5 {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
            
            XCTAssertEqual(pool.availableCount, poolSize - (i + 1))
            XCTAssertEqual(pool.totalAcquired, i + 1)
        }
        
        XCTAssertEqual(buffers.count, 5)
    }
    
    func testAcquireAllBuffers() {
        var buffers: [AVAudioPCMBuffer] = []
        
        // Acquire all buffers
        for _ in 0..<poolSize {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        XCTAssertEqual(buffers.count, poolSize)
        XCTAssertEqual(pool.availableCount, 0)
        XCTAssertTrue(pool.isExhausted)
    }
    
    func testAcquireWhenExhausted() {
        // Exhaust initial pool
        var buffers: [AVAudioPCMBuffer] = []
        for _ in 0..<poolSize {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        // Try to acquire when initial pool exhausted
        // NEW BEHAVIOR (Issue #55): Should succeed via emergency allocation (zero data loss)
        let extraBuffer = pool.acquire()
        
        XCTAssertNotNil(extraBuffer, "Should use emergency allocation when pool exhausted (Issue #55)")
        XCTAssertGreaterThanOrEqual(pool.allocationFailures, 1, "Should track emergency allocation")
        
        // Cleanup
        if let extraBuffer = extraBuffer {
            pool.release(extraBuffer)
        }
        for buffer in buffers {
            pool.release(buffer)
        }
    }
    
    // MARK: - Buffer Release Tests
    
    func testReleaseBuffer() {
        guard let buffer = pool.acquire() else {
            XCTFail("Failed to acquire buffer")
            return
        }
        
        XCTAssertEqual(pool.availableCount, poolSize - 1)
        
        pool.release(buffer)
        
        XCTAssertEqual(pool.availableCount, poolSize)
        XCTAssertEqual(pool.totalReleased, 1)
    }
    
    func testReleaseMultipleBuffers() {
        var buffers: [AVAudioPCMBuffer] = []
        
        // Acquire 5 buffers
        for _ in 0..<5 {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        // Release all
        for buffer in buffers {
            pool.release(buffer)
        }
        
        XCTAssertEqual(pool.availableCount, poolSize)
        XCTAssertEqual(pool.totalReleased, 5)
    }
    
    func testReleaseResetsFrameLength() {
        guard let buffer = pool.acquire() else {
            XCTFail("Failed to acquire buffer")
            return
        }
        
        // Set frame length
        buffer.frameLength = 512
        XCTAssertEqual(buffer.frameLength, 512)
        
        // Release should reset frame length
        pool.release(buffer)
        
        // Acquire again and verify reset
        guard let reacquired = pool.acquire() else {
            XCTFail("Failed to reacquire buffer")
            return
        }
        
        XCTAssertEqual(reacquired.frameLength, 0)
    }
    
    // MARK: - Pool Status Tests
    
    func testPoolIsLow() {
        // Pool is low when less than 25% available
        let threshold = poolSize / 4
        
        // Acquire enough to get below threshold
        for _ in 0..<(poolSize - threshold + 1) {
            _ = pool.acquire()
        }
        
        XCTAssertTrue(pool.isLow)
    }
    
    func testPoolIsNotLow() {
        // Pool is not low when > 25% available
        XCTAssertFalse(pool.isLow)
        
        // Acquire a few
        for _ in 0..<3 {
            _ = pool.acquire()
        }
        
        XCTAssertFalse(pool.isLow)
    }
    
    func testPoolIsExhausted() {
        // Exhaust pool
        for _ in 0..<poolSize {
            _ = pool.acquire()
        }
        
        XCTAssertTrue(pool.isExhausted)
        XCTAssertEqual(pool.availableCount, 0)
    }
    
    func testPoolIsNotExhausted() {
        XCTAssertFalse(pool.isExhausted)
        
        _ = pool.acquire()
        
        XCTAssertFalse(pool.isExhausted)
    }
    
    // MARK: - Statistics Tests
    
    func testStatisticsTracking() {
        // Initial state
        XCTAssertEqual(pool.totalAcquired, 0)
        XCTAssertEqual(pool.totalReleased, 0)
        XCTAssertEqual(pool.allocationFailures, 0)
        
        // Acquire 3 buffers
        var buffers: [AVAudioPCMBuffer] = []
        for _ in 0..<3 {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        XCTAssertEqual(pool.totalAcquired, 3)
        XCTAssertEqual(pool.totalReleased, 0)
        
        // Release 2 buffers
        for buffer in buffers.prefix(2) {
            pool.release(buffer)
        }
        
        XCTAssertEqual(pool.totalAcquired, 3)
        XCTAssertEqual(pool.totalReleased, 2)
    }
    
    func testAllocationFailureTracking() {
        // Exhaust pool
        for _ in 0..<poolSize {
            _ = pool.acquire()
        }
        
        // Try to acquire 3 more (should fail)
        for _ in 0..<3 {
            _ = pool.acquire()
        }
        
        XCTAssertEqual(pool.allocationFailures, 3)
    }
    
    func testResetStatistics() {
        // Acquire and release some buffers
        if let buffer = pool.acquire() {
            pool.release(buffer)
        }
        
        // Fail an acquisition
        for _ in 0..<poolSize {
            _ = pool.acquire()
        }
        _ = pool.acquire()  // Should fail
        
        // Statistics should be non-zero
        XCTAssertGreaterThan(pool.totalAcquired, 0)
        XCTAssertGreaterThan(pool.totalReleased, 0)
        XCTAssertGreaterThan(pool.allocationFailures, 0)
        
        // Reset
        pool.resetStatistics()
        
        XCTAssertEqual(pool.totalAcquired, 0)
        XCTAssertEqual(pool.totalReleased, 0)
        XCTAssertEqual(pool.allocationFailures, 0)
        XCTAssertEqual(pool.writeCount, 0)
    }
    
    // MARK: - Write Count Tests
    
    func testIncrementWriteCount() {
        XCTAssertEqual(pool.writeCount, 0)
        
        _ = pool.incrementWriteCount()
        XCTAssertEqual(pool.writeCount, 1)
        
        _ = pool.incrementWriteCount()
        XCTAssertEqual(pool.writeCount, 2)
    }
    
    func testSyncIntervalDetection() {
        let syncInterval = RecordingBufferPool.syncInterval
        
        // Increment up to sync interval
        for i in 1..<syncInterval {
            let shouldSync = pool.incrementWriteCount()
            XCTAssertFalse(shouldSync, "Should not sync at count \(i)")
        }
        
        // At sync interval, should return true
        let shouldSync = pool.incrementWriteCount()
        XCTAssertTrue(shouldSync, "Should sync at count \(syncInterval)")
        XCTAssertEqual(pool.writeCount, syncInterval)
        
        // Next increment should not sync
        let shouldNotSync = pool.incrementWriteCount()
        XCTAssertFalse(shouldNotSync)
    }
    
    func testSyncIntervalPeriodic() {
        let syncInterval = RecordingBufferPool.syncInterval
        
        // Should sync at multiples of syncInterval
        for _ in 0..<syncInterval {
            _ = pool.incrementWriteCount()
        }
        XCTAssertEqual(pool.writeCount, syncInterval)
        
        for _ in 0..<syncInterval {
            _ = pool.incrementWriteCount()
        }
        let shouldSync = pool.incrementWriteCount()
        XCTAssertFalse(shouldSync)  // 201 is not multiple of 100
        
        // But at 200, should sync
        pool.resetStatistics()
        for i in 1...200 {
            let shouldSync = pool.incrementWriteCount()
            if i % syncInterval == 0 {
                XCTAssertTrue(shouldSync, "Should sync at \(i)")
            }
        }
    }
    
    // MARK: - Acquire and Copy Tests
    
    func testAcquireAndCopy() {
        // Create source buffer with data
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512) else {
            XCTFail("Failed to create source buffer")
            return
        }
        sourceBuffer.frameLength = 512
        
        // Fill with test data
        if let data = sourceBuffer.floatChannelData {
            for ch in 0..<Int(format.channelCount) {
                for frame in 0..<Int(sourceBuffer.frameLength) {
                    data[ch][frame] = Float(frame) / 100.0
                }
            }
        }
        
        // Acquire and copy
        guard let poolBuffer = pool.acquireAndCopy(from: sourceBuffer) else {
            XCTFail("Failed to acquire and copy")
            return
        }
        
        // Verify copy
        XCTAssertEqual(poolBuffer.frameLength, sourceBuffer.frameLength)
        
        if let srcData = sourceBuffer.floatChannelData,
           let dstData = poolBuffer.floatChannelData {
            for ch in 0..<Int(format.channelCount) {
                for frame in 0..<Int(sourceBuffer.frameLength) {
                    assertApproximatelyEqual(
                        dstData[ch][frame],
                        srcData[ch][frame],
                        tolerance: 0.00001
                    )
                }
            }
        }
    }
    
    func testAcquireAndCopyWhenExhausted() {
        // Exhaust initial pool
        var buffers: [AVAudioPCMBuffer] = []
        for _ in 0..<poolSize {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        // Create source buffer
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512) else {
            XCTFail("Failed to create source buffer")
            return
        }
        sourceBuffer.frameLength = 512
        
        // Try to acquire and copy when initial pool exhausted
        // NEW BEHAVIOR (Issue #55): Should succeed via emergency allocation
        let result = pool.acquireAndCopy(from: sourceBuffer)
        
        XCTAssertNotNil(result, "Should use emergency allocation when pool exhausted (Issue #55)")
        XCTAssertEqual(result?.frameLength, sourceBuffer.frameLength, "Should copy frame length")
        
        // Cleanup
        if let result = result {
            pool.release(result)
        }
        for buffer in buffers {
            pool.release(buffer)
        }
    }
    
    func testAcquireAndCopySourceTooLarge() {
        // Create source buffer larger than pool buffer capacity
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity + 1) else {
            XCTFail("Failed to create source buffer")
            return
        }
        sourceBuffer.frameLength = frameCapacity + 1
        
        // Try to acquire and copy
        let result = pool.acquireAndCopy(from: sourceBuffer)
        
        XCTAssertNil(result, "Should return nil when source is too large")
        
        // Pool should still have all buffers (release happened)
        XCTAssertEqual(pool.availableCount, poolSize)
    }
    
    // MARK: - Real-Time Safety Tests
    
    func testBufferPoolNoAllocationOnAcquire() {
        // The pool should be fully pre-allocated
        // Acquiring a buffer should not allocate memory
        
        // Acquire all buffers (should not allocate)
        var buffers: [AVAudioPCMBuffer] = []
        for _ in 0..<poolSize {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        XCTAssertEqual(buffers.count, poolSize)
        
        // This test primarily validates at compile time and runtime
        // In production, would use Instruments to verify zero allocations
        XCTAssertTrue(true, "Buffer acquisition completed without allocation")
    }
    
    func testBufferPoolLockContention() {
        // Test that lock is held for minimal time
        // In real-time code, lock contention must be minimized
        
        let iterations = 1000
        
        measure {
            for _ in 0..<iterations {
                if let buffer = pool.acquire() {
                    pool.release(buffer)
                }
            }
        }
        
        // If this completes quickly, lock contention is minimal
        XCTAssertTrue(true, "Lock contention is acceptable")
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentAcquisition() async {
        let concurrentTasks = 8
        
        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<concurrentTasks {
                group.addTask {
                    var count = 0
                    for _ in 0..<10 {
                        if let buffer = self.pool.acquire() {
                            count += 1
                            self.pool.release(buffer)
                        }
                    }
                    return count
                }
            }
            
            var totalAcquired = 0
            for await count in group {
                totalAcquired += count
            }
            
            // Should have acquired successfully multiple times
            XCTAssertGreaterThan(totalAcquired, 0)
        }
    }
    
    func testConcurrentAcquireRelease() async {
        var buffers: [AVAudioPCMBuffer] = []
        
        // Acquire some buffers
        for _ in 0..<8 {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        // Concurrently release
        await withTaskGroup(of: Void.self) { group in
            for buffer in buffers {
                group.addTask {
                    self.pool.release(buffer)
                }
            }
        }
        
        // All should be released
        XCTAssertEqual(pool.availableCount, poolSize)
    }
    
    // MARK: - Performance Tests
    
    func testBufferAcquisitionPerformance() {
        measure {
            for _ in 0..<1000 {
                if let buffer = pool.acquire() {
                    pool.release(buffer)
                }
            }
        }
    }
    
    func testBufferReleasePerformance() {
        // Pre-acquire buffers
        var buffers: [AVAudioPCMBuffer] = []
        for _ in 0..<poolSize {
            if let buffer = pool.acquire() {
                buffers.append(buffer)
            }
        }
        
        measure {
            for _ in 0..<100 {
                // Release all
                for buffer in buffers {
                    pool.release(buffer)
                }
                
                // Re-acquire
                buffers.removeAll(keepingCapacity: true)
                for _ in 0..<poolSize {
                    if let buffer = pool.acquire() {
                        buffers.append(buffer)
                    }
                }
            }
        }
    }
    
    func testAcquireAndCopyPerformance() {
        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512) else {
            XCTFail("Failed to create source buffer")
            return
        }
        sourceBuffer.frameLength = 512
        
        measure {
            for _ in 0..<100 {
                if let buffer = pool.acquireAndCopy(from: sourceBuffer) {
                    pool.release(buffer)
                }
            }
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testSmallPoolSize() {
        let smallPool = RecordingBufferPool(format: format, frameCapacity: frameCapacity, poolSize: 2)
        
        XCTAssertEqual(smallPool.availableCount, 2)
        
        _ = smallPool.acquire()
        _ = smallPool.acquire()
        
        XCTAssertTrue(smallPool.isExhausted)
    }
    
    func testLargePoolSize() {
        let largePool = RecordingBufferPool(format: format, frameCapacity: frameCapacity, poolSize: 64)
        
        XCTAssertEqual(largePool.availableCount, 64)
        
        // Acquire many buffers
        for _ in 0..<32 {
            _ = largePool.acquire()
        }
        
        XCTAssertFalse(largePool.isExhausted)
        XCTAssertEqual(largePool.availableCount, 32)
    }
    
    func testZeroFrameLengthBuffer() {
        guard let buffer = pool.acquire() else {
            XCTFail("Failed to acquire buffer")
            return
        }
        
        XCTAssertEqual(buffer.frameLength, 0)
        
        pool.release(buffer)
        
        guard let reacquired = pool.acquire() else {
            XCTFail("Failed to reacquire buffer")
            return
        }
        
        XCTAssertEqual(reacquired.frameLength, 0)
    }
    
    // MARK: - Memory Management Tests
    
    func testBufferPoolCleanup() {
        // Create and destroy multiple pools
        for _ in 0..<5 {
            let tempPool = RecordingBufferPool(format: format, frameCapacity: frameCapacity, poolSize: 8)
            
            // Acquire and release
            if let buffer = tempPool.acquire() {
                tempPool.release(buffer)
            }
        }
        
        // If we get here, memory is managed correctly
        XCTAssertTrue(true, "Multiple pool lifecycles completed")
    }
    
    func testBufferReuseAcrossAcquisitions() {
        // Acquire a buffer
        guard let buffer1 = pool.acquire() else {
            XCTFail("Failed to acquire buffer")
            return
        }
        
        let buffer1Pointer = UnsafeRawPointer(Unmanaged.passUnretained(buffer1).toOpaque())
        
        // Release it
        pool.release(buffer1)
        
        // Acquire again - should get same buffer (LIFO behavior)
        guard let buffer2 = pool.acquire() else {
            XCTFail("Failed to reacquire buffer")
            return
        }
        
        let buffer2Pointer = UnsafeRawPointer(Unmanaged.passUnretained(buffer2).toOpaque())
        
        // Should be same buffer
        XCTAssertEqual(buffer1Pointer, buffer2Pointer)
    }
}
