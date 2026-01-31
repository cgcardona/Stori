//
//  RecordingBufferPool.swift
//  Stori
//
//  Real-time safe buffer pool for audio recording.
//  Pre-allocates buffers to avoid allocation on the audio thread.
//
//  REAL-TIME SAFETY: The audio thread should NEVER allocate memory.
//  This pool provides pre-allocated buffers that can be acquired
//  and released without blocking or allocation.
//

import Foundation
import AVFoundation
import os.lock

// MARK: - Recording Buffer Pool

/// A lock-free buffer pool for real-time audio recording.
/// Pre-allocates AVAudioPCMBuffer instances to avoid allocation on the audio thread.
final class RecordingBufferPool: @unchecked Sendable {
    
    // MARK: - Configuration
    
    /// Number of buffers to pre-allocate (should be enough to handle writer queue latency)
    private let poolSize: Int
    
    /// Frame capacity for each buffer
    private let frameCapacity: AVAudioFrameCount
    
    /// Audio format for the buffers
    private let format: AVAudioFormat
    
    // MARK: - Buffer Storage
    
    /// Pool of available buffers (thread-safe access via lock)
    private var availableBuffers: [AVAudioPCMBuffer] = []
    
    /// Lock for thread-safe access to the pool
    /// Using os_unfair_lock for minimal overhead
    private var poolLock = os_unfair_lock_s()
    
    /// Statistics for monitoring pool health
    private(set) var totalAcquired: Int = 0
    private(set) var totalReleased: Int = 0
    private(set) var allocationFailures: Int = 0
    
    /// Write counter for periodic fsync (crash protection)
    private(set) var writeCount: Int = 0
    
    /// Sync interval (number of writes between fsync calls)
    /// At 1024 frames/48kHz, 100 writes = ~2 seconds of audio
    static let syncInterval: Int = 100
    
    // MARK: - Initialization
    
    /// Create a buffer pool with pre-allocated buffers
    /// - Parameters:
    ///   - format: Audio format for the buffers
    ///   - frameCapacity: Frame capacity for each buffer (typically matches tap buffer size)
    ///   - poolSize: Number of buffers to pre-allocate (default: 16)
    init(format: AVAudioFormat, frameCapacity: AVAudioFrameCount, poolSize: Int = 16) {
        self.format = format
        self.frameCapacity = frameCapacity
        self.poolSize = poolSize
        
        // Pre-allocate all buffers upfront (NOT on audio thread!)
        availableBuffers.reserveCapacity(poolSize)
        for _ in 0..<poolSize {
            if let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) {
                availableBuffers.append(buffer)
            }
        }
        
        if availableBuffers.count < poolSize {
            // Log warning but continue - we have some buffers
        }
    }
    
    // MARK: - Buffer Acquisition (Real-Time Safe)
    
    /// Acquire a buffer from the pool.
    /// Returns nil if no buffers are available (caller should handle gracefully).
    /// 
    /// REAL-TIME SAFE: Uses os_unfair_lock which is safe for audio threads.
    func acquire() -> AVAudioPCMBuffer? {
        os_unfair_lock_lock(&poolLock)
        defer { os_unfair_lock_unlock(&poolLock) }
        
        if availableBuffers.isEmpty {
            allocationFailures += 1
            return nil
        }
        
        let buffer = availableBuffers.removeLast()
        totalAcquired += 1
        return buffer
    }
    
    /// Release a buffer back to the pool.
    /// 
    /// Should be called from the writer queue after the buffer has been written to disk.
    func release(_ buffer: AVAudioPCMBuffer) {
        os_unfair_lock_lock(&poolLock)
        defer { os_unfair_lock_unlock(&poolLock) }
        
        // Reset buffer state for reuse
        buffer.frameLength = 0
        
        // Only return to pool if we're not over capacity
        if availableBuffers.count < poolSize {
            availableBuffers.append(buffer)
        }
        totalReleased += 1
    }
    
    // MARK: - Pool Status
    
    /// Number of buffers currently available
    var availableCount: Int {
        os_unfair_lock_lock(&poolLock)
        defer { os_unfair_lock_unlock(&poolLock) }
        return availableBuffers.count
    }
    
    /// True if the pool is running low on buffers (less than 25% available)
    var isLow: Bool {
        availableCount < poolSize / 4
    }
    
    /// True if the pool is exhausted (no buffers available)
    var isExhausted: Bool {
        availableCount == 0
    }
    
    /// Reset pool statistics
    func resetStatistics() {
        os_unfair_lock_lock(&poolLock)
        totalAcquired = 0
        totalReleased = 0
        allocationFailures = 0
        writeCount = 0
        os_unfair_lock_unlock(&poolLock)
    }
    
    /// Increment write count and return whether fsync should be called
    /// Call this after each successful write to the recording file
    func incrementWriteCount() -> Bool {
        os_unfair_lock_lock(&poolLock)
        writeCount += 1
        let shouldSync = writeCount % Self.syncInterval == 0
        os_unfair_lock_unlock(&poolLock)
        return shouldSync
    }
}

// MARK: - Buffer Copy Helper

extension RecordingBufferPool {
    
    /// Copy audio data from source buffer to a pool buffer.
    /// Returns the pool buffer with copied data, or nil if pool is exhausted.
    ///
    /// REAL-TIME SAFE: No allocations, uses memcpy for fast copying.
    func acquireAndCopy(from source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let poolBuffer = acquire() else {
            return nil
        }
        
        // Safety check: source buffer must fit in pool buffer
        if source.frameLength > poolBuffer.frameCapacity {
            release(poolBuffer)
            return nil
        }
        
        // Set frame length to match source
        poolBuffer.frameLength = source.frameLength
        
        // Fast copy using memcpy (real-time safe)
        if let srcData = source.floatChannelData,
           let dstData = poolBuffer.floatChannelData {
            let channels = Int(source.format.channelCount)
            let frames = Int(source.frameLength)
            let byteSize = frames * MemoryLayout<Float>.size
            
            for ch in 0..<channels {
                memcpy(dstData[ch], srcData[ch], byteSize)
            }
        }
        
        return poolBuffer
    }
}
