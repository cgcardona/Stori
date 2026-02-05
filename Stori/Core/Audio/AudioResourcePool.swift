//
//  AudioResourcePool.swift
//  Stori
//
//  Resource pool for expensive audio objects to prevent allocation storms.
//  Reuses buffers and limits concurrent allocations during device changes.
//

import Foundation
import AVFoundation
import Observation

// MARK: - Audio Resource Pool

/// Manages reusable audio buffers and limits allocation storms during device changes.
/// CRITICAL: Prevents memory spikes when engine.reset() triggers cascading reallocations.
@Observable
@MainActor
final class AudioResourcePool {
    
    // MARK: - Configuration
    
    /// Maximum number of buffers to keep in pool
    private static let maxPoolSize = 100
    
    /// Maximum number of buffers that can be borrowed at once
    private static let maxBorrowedBuffers = 50
    
    /// Memory pressure threshold (bytes) - start rejecting allocations above this
    private static let memoryPressureThreshold: Int = 500_000_000  // 500MB
    
    // MARK: - State
    
    /// Available buffers (not currently in use)
    @ObservationIgnored
    private var availableBuffers: [PooledBuffer] = []
    
    /// Borrowed buffers (currently in use)
    @ObservationIgnored
    private var borrowedBuffers: Set<ObjectIdentifier> = []
    
    /// Total memory allocated by pool (approximate)
    private(set) var totalMemoryBytes: Int = 0
    
    /// Whether pool is under memory pressure
    private(set) var isUnderMemoryPressure: Bool = false
    
    /// Statistics for monitoring
    private(set) var stats = PoolStatistics()
    
    struct PoolStatistics {
        var totalAllocations: Int = 0
        var totalReuses: Int = 0
        var peakBorrowed: Int = 0
        var rejectedAllocations: Int = 0
        
        var reuseRate: Double {
            guard totalAllocations > 0 else { return 0 }
            return Double(totalReuses) / Double(totalAllocations)
        }
    }
    
    // MARK: - Pooled Buffer
    
    struct PooledBuffer {
        let buffer: AVAudioPCMBuffer
        let sampleRate: Double
        let channelCount: AVAudioChannelCount
        let frameCapacity: AVAudioFrameCount
        let memorySize: Int
        
        /// Check if this buffer is compatible with requested parameters
        func isCompatible(
            sampleRate: Double,
            channelCount: AVAudioChannelCount,
            frameCapacity: AVAudioFrameCount
        ) -> Bool {
            return abs(self.sampleRate - sampleRate) < 1.0 &&
                   self.channelCount == channelCount &&
                   self.frameCapacity >= frameCapacity
        }
    }
    
    // MARK: - Singleton
    
    static let shared = AudioResourcePool()
    
    private init() {}
    
    // MARK: - Buffer Borrowing
    
    /// Borrow a buffer from the pool or allocate a new one.
    /// Returns nil if under memory pressure or allocation limit reached.
    func borrowBuffer(
        format: AVAudioFormat,
        frameCapacity: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        // Check if we're at borrowing limit
        if borrowedBuffers.count >= Self.maxBorrowedBuffers {
            stats.rejectedAllocations += 1
            AppLogger.shared.warning("AudioResourcePool: Max borrowed buffers reached (\(Self.maxBorrowedBuffers))", category: .audio)
            return nil
        }
        
        // Check memory pressure
        if isUnderMemoryPressure {
            stats.rejectedAllocations += 1
            AppLogger.shared.warning("AudioResourcePool: Rejecting allocation due to memory pressure", category: .audio)
            return nil
        }
        
        let sampleRate = format.sampleRate
        let channelCount = format.channelCount
        
        // Try to find compatible buffer in pool
        if let index = availableBuffers.firstIndex(where: {
            $0.isCompatible(
                sampleRate: sampleRate,
                channelCount: channelCount,
                frameCapacity: frameCapacity
            )
        }) {
            let pooledBuffer = availableBuffers.remove(at: index)
            borrowedBuffers.insert(ObjectIdentifier(pooledBuffer.buffer))
            
            // Reusing a buffer - increment both allocations (total borrows) and reuses
            stats.totalAllocations += 1
            stats.totalReuses += 1
            stats.peakBorrowed = max(stats.peakBorrowed, borrowedBuffers.count)
            
            return pooledBuffer.buffer
        }
        
        // Allocate new buffer
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            stats.rejectedAllocations += 1
            AppLogger.shared.error("AudioResourcePool: Failed to allocate buffer", category: .audio)
            return nil
        }
        
        // Calculate approximate memory size
        // Note: mBytesPerFrame already accounts for all channels
        let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
        let memorySize = Int(bytesPerFrame) * Int(frameCapacity)
        
        totalMemoryBytes += memorySize
        borrowedBuffers.insert(ObjectIdentifier(buffer))
        
        stats.totalAllocations += 1
        stats.peakBorrowed = max(stats.peakBorrowed, borrowedBuffers.count)
        
        // Check if we've crossed memory pressure threshold
        if totalMemoryBytes > Self.memoryPressureThreshold {
            isUnderMemoryPressure = true
            AppLogger.shared.warning("AudioResourcePool: Memory pressure threshold reached (\(totalMemoryBytes / 1_000_000)MB)", category: .audio)
        }
        
        return buffer
    }
    
    /// Return a buffer to the pool for reuse.
    /// If pool is full, buffer is released instead.
    func returnBuffer(_ buffer: AVAudioPCMBuffer) {
        let bufferID = ObjectIdentifier(buffer)
        
        // Remove from borrowed set
        guard borrowedBuffers.contains(bufferID) else {
            // Buffer wasn't borrowed from this pool - ignore
            return
        }
        borrowedBuffers.remove(bufferID)
        
        // If pool is full, don't keep it
        if availableBuffers.count >= Self.maxPoolSize {
            // Calculate memory size and subtract from total
            // Note: mBytesPerFrame already accounts for all channels
            let format = buffer.format
            let bytesPerFrame = format.streamDescription.pointee.mBytesPerFrame
            let memorySize = Int(bytesPerFrame) * Int(buffer.frameCapacity)
            totalMemoryBytes -= memorySize
            return
        }
        
        // Add to available pool
        let pooledBuffer = PooledBuffer(
            buffer: buffer,
            sampleRate: buffer.format.sampleRate,
            channelCount: buffer.format.channelCount,
            frameCapacity: buffer.frameCapacity,
            memorySize: Int(buffer.format.streamDescription.pointee.mBytesPerFrame) * Int(buffer.frameCapacity)
        )
        
        availableBuffers.append(pooledBuffer)
    }
    
    // MARK: - Memory Management
    
    /// Release all available buffers to reduce memory footprint.
    /// Call during memory pressure or when switching projects.
    func releaseAvailableBuffers() {
        let releasedMemory = availableBuffers.reduce(0) { $0 + $1.memorySize }
        availableBuffers.removeAll()
        totalMemoryBytes -= releasedMemory
        
        // Reset memory pressure flag if we've freed enough
        if totalMemoryBytes < Self.memoryPressureThreshold / 2 {
            isUnderMemoryPressure = false
        }
        
        AppLogger.shared.info("AudioResourcePool: Released \(releasedMemory / 1_000_000)MB from pool", category: .audio)
    }
    
    /// Force release all buffers (borrowed and available).
    /// DANGER: Only use when tearing down entire audio system.
    func releaseAllBuffers() {
        availableBuffers.removeAll()
        borrowedBuffers.removeAll()
        totalMemoryBytes = 0
        isUnderMemoryPressure = false
        
        AppLogger.shared.info("AudioResourcePool: Force released all buffers", category: .audio)
    }
    
    /// Handle system memory warning.
    /// Releases available buffers and rejects new allocations.
    func handleMemoryWarning() {
        AppLogger.shared.warning("AudioResourcePool: Handling memory warning", category: .audio)
        
        releaseAvailableBuffers()
        isUnderMemoryPressure = true
        
        // Post notification so other subsystems can clear caches
        NotificationCenter.default.post(name: .audioMemoryPressure, object: nil)
    }
    
    /// Reset memory pressure flag (call after user closes projects or clears caches)
    func resetMemoryPressure() {
        isUnderMemoryPressure = false
        AppLogger.shared.info("AudioResourcePool: Memory pressure cleared", category: .audio)
    }
    
    // MARK: - Statistics
    
    /// Get current pool statistics for monitoring
    func getStatistics() -> PoolStatistics {
        return stats
    }
    
    /// Reset statistics (for testing or after major operations)
    func resetStatistics() {
        stats = PoolStatistics()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when audio subsystem is under memory pressure
    static let audioMemoryPressure = Notification.Name("audioMemoryPressure")
}
