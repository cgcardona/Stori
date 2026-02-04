//
//  AudioResourcePoolTests.swift
//  StoriTests
//
//  Tests for audio resource pool and memory management.
//

import XCTest
import AVFoundation
@testable import Stori

@MainActor
final class AudioResourcePoolTests: XCTestCase {
    
    var pool: AudioResourcePool!
    var format48k: AVAudioFormat!
    var format44k: AVAudioFormat!
    
    override func setUp() async throws {
        pool = AudioResourcePool.shared
        pool.releaseAllBuffers()
        pool.resetStatistics()
        pool.resetMemoryPressure()
        
        format48k = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        format44k = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
    }
    
    override func tearDown() async throws {
        pool.releaseAllBuffers()
        pool.resetMemoryPressure()
    }
    
    // MARK: - Basic Pool Tests
    
    func testBorrowAndReturnBuffer() {
        let buffer = pool.borrowBuffer(format: format48k, frameCapacity: 512)
        
        XCTAssertNotNil(buffer, "Should be able to borrow buffer")
        XCTAssertEqual(pool.getStatistics().totalAllocations, 1)
        
        pool.returnBuffer(buffer!)
        
        // Borrow again - should reuse
        let buffer2 = pool.borrowBuffer(format: format48k, frameCapacity: 512)
        XCTAssertNotNil(buffer2, "Should reuse buffer")
        XCTAssertEqual(pool.getStatistics().totalReuses, 1, "Should track reuse")
    }
    
    func testBufferCompatibilityMatching() {
        // Borrow and return buffer with specific format
        let buffer1 = pool.borrowBuffer(format: format48k, frameCapacity: 1024)
        pool.returnBuffer(buffer1!)
        
        // Request compatible buffer (same rate, smaller capacity)
        let buffer2 = pool.borrowBuffer(format: format48k, frameCapacity: 512)
        XCTAssertNotNil(buffer2, "Should reuse buffer with larger capacity")
        XCTAssertEqual(pool.getStatistics().totalReuses, 1)
        
        pool.returnBuffer(buffer2!)
        
        // Request incompatible buffer (different rate)
        let buffer3 = pool.borrowBuffer(format: format44k, frameCapacity: 512)
        XCTAssertNotNil(buffer3, "Should allocate new buffer for different rate")
        XCTAssertEqual(pool.getStatistics().totalAllocations, 2)
    }
    
    func testMemoryPressureRejectsAllocations() {
        // Trigger memory pressure
        pool.handleMemoryWarning()
        
        XCTAssertTrue(pool.isUnderMemoryPressure, "Should be under memory pressure")
        
        let buffer = pool.borrowBuffer(format: format48k, frameCapacity: 512)
        
        XCTAssertNil(buffer, "Should reject allocations under memory pressure")
        XCTAssertEqual(pool.getStatistics().rejectedAllocations, 1)
    }
    
    func testReleaseAvailableBuffers() {
        // Borrow and return several buffers
        for _ in 0..<5 {
            let buffer = pool.borrowBuffer(format: format48k, frameCapacity: 512)
            pool.returnBuffer(buffer!)
        }
        
        let memoryBefore = pool.totalMemoryBytes
        XCTAssertGreaterThan(memoryBefore, 0, "Should have memory allocated")
        
        pool.releaseAvailableBuffers()
        
        XCTAssertEqual(pool.totalMemoryBytes, 0, "Should release all available buffers")
    }
    
    func testMaxBorrowedBufferLimit() {
        var borrowedBuffers: [AVAudioPCMBuffer] = []
        
        // Try to borrow more than max
        for _ in 0..<60 {
            if let buffer = pool.borrowBuffer(format: format48k, frameCapacity: 512) {
                borrowedBuffers.append(buffer)
            }
        }
        
        XCTAssertLessThanOrEqual(borrowedBuffers.count, 50, "Should enforce max borrowed buffer limit")
        XCTAssertGreaterThan(pool.getStatistics().rejectedAllocations, 0, "Should reject allocations over limit")
    }
    
    func testReuseRateCalculation() {
        // Allocate
        let buffer1 = pool.borrowBuffer(format: format48k, frameCapacity: 512)
        pool.returnBuffer(buffer1!)
        
        // Reuse
        let buffer2 = pool.borrowBuffer(format: format48k, frameCapacity: 512)
        pool.returnBuffer(buffer2!)
        
        let stats = pool.getStatistics()
        XCTAssertEqual(stats.reuseRate, 0.5, accuracy: 0.01, "Reuse rate should be 50%")
    }
}
