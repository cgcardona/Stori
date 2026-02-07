//
//  RTSafeAtomic.swift
//  Stori
//
//  Real-time safe atomic wrappers for audio thread access
//  Encapsulates nonisolated(unsafe) in auditable, type-safe wrappers
//

import Foundation

/// Real-time safe atomic wrapper for value types
/// Uses os_unfair_lock with trylock pattern for RT thread access
///
/// PROFESSIONAL DAW STANDARD:
/// - RT threads use trylock (never block)
/// - Non-RT threads take lock normally
/// - Value types only (no reference types to avoid retain/release)
///
/// USAGE:
/// ```swift
/// @ObservationIgnored
/// private let clipCount = RTSafeAtomic<UInt32>(0)
///
/// // RT thread (never blocks):
/// clipCount.tryUpdate { $0 += 1 }
///
/// // Non-RT thread (can wait):
/// let count = clipCount.read()
/// clipCount.write(0)
/// ```
final class RTSafeAtomic<Value> where Value: Sendable {
    /// Lock protecting the value
    /// MUST be nonisolated(unsafe) for trylock from RT thread
    private nonisolated(unsafe) var lock = os_unfair_lock_s()
    
    /// Stored value (protected by lock)
    /// MUST be nonisolated(unsafe) for access from RT thread
    private nonisolated(unsafe) var value: Value
    
    /// Initialize with default value
    init(_ initialValue: Value) {
        self.value = initialValue
    }
    
    // MARK: - RT-Safe Operations (trylock - never blocks)
    
    /// Try to update value from RT thread (never blocks)
    /// Returns true if update succeeded, false if lock was busy
    ///
    /// USE THIS FROM RT AUDIO THREAD ONLY
    /// If lock is busy, returns false immediately (no blocking)
    @discardableResult
    nonisolated func tryUpdate(_ block: (inout Value) -> Void) -> Bool {
        guard os_unfair_lock_trylock(&lock) else {
            return false  // Lock busy, skip update
        }
        defer { os_unfair_lock_unlock(&lock) }
        
        block(&value)
        return true
    }
    
    /// Try to read value from RT thread (never blocks)
    /// Returns nil if lock was busy
    ///
    /// USE THIS FROM RT AUDIO THREAD ONLY
    nonisolated func tryRead() -> Value? {
        guard os_unfair_lock_trylock(&lock) else {
            return nil  // Lock busy, skip read
        }
        defer { os_unfair_lock_unlock(&lock) }
        
        return value
    }
    
    // MARK: - Non-RT Operations (normal lock - can wait)
    
    /// Read value (blocks if lock is held)
    /// DO NOT USE FROM RT AUDIO THREAD
    nonisolated func read() -> Value {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return value
    }
    
    /// Write value (blocks if lock is held)
    /// DO NOT USE FROM RT AUDIO THREAD
    nonisolated func write(_ newValue: Value) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        value = newValue
    }
    
    /// Update value with block (blocks if lock is held)
    /// DO NOT USE FROM RT AUDIO THREAD
    nonisolated func update(_ block: (inout Value) -> Void) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        block(&value)
    }
    
    /// Read and reset to default value atomically
    /// DO NOT USE FROM RT AUDIO THREAD
    nonisolated func readAndReset(to resetValue: Value) -> Value {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        let currentValue = value
        value = resetValue
        return currentValue
    }
}

// MARK: - Specialized RT-Safe Types

/// RT-safe counter for error tracking
/// Optimized for increment-heavy workloads (clipping detection, error counts)
final class RTSafeCounter {
    private let atomic: RTSafeAtomic<UInt32>
    
    init() {
        self.atomic = RTSafeAtomic(0)
    }
    
    /// Increment counter from RT thread (never blocks)
    @discardableResult
    nonisolated func tryIncrement() -> Bool {
        atomic.tryUpdate { $0 += 1 }
    }
    
    /// Read and reset counter from non-RT thread
    nonisolated func readAndReset() -> UInt32 {
        atomic.readAndReset(to: 0)
    }
    
    /// Read current value (non-RT thread)
    nonisolated func read() -> UInt32 {
        atomic.read()
    }
}

/// RT-safe max tracker for peak detection
/// Optimized for compare-and-update pattern (peak metering, clipping detection)
final class RTSafeMaxTracker {
    private let atomic: RTSafeAtomic<Float>
    
    init() {
        self.atomic = RTSafeAtomic(0.0)
    }
    
    /// Update max value from RT thread (never blocks)
    @discardableResult
    nonisolated func tryUpdateMax(_ newValue: Float) -> Bool {
        atomic.tryUpdate { currentMax in
            if newValue > currentMax {
                currentMax = newValue
            }
        }
    }
    
    /// Read and reset max from non-RT thread
    nonisolated func readAndReset() -> Float {
        atomic.readAndReset(to: 0.0)
    }
    
    /// Read current max (non-RT thread)
    nonisolated func read() -> Float {
        atomic.read()
    }
}

// MARK: - Simple Atomic Primitives (for non-RT cross-thread state)

/// Thread-safe atomic boolean
/// Use for flags that need to be read/written from multiple threads (NOT RT thread)
/// For RT thread access, use RTSafeAtomic<Bool> instead
final class AtomicBool {
    private nonisolated(unsafe) var lock = os_unfair_lock_s()
    private nonisolated(unsafe) var value: Bool
    
    init(_ initialValue: Bool = false) {
        self.value = initialValue
    }
    
    nonisolated func load() -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return value
    }
    
    nonisolated func store(_ newValue: Bool) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        value = newValue
    }
    
    /// Compare and swap
    @discardableResult
    nonisolated func compareAndSwap(expected: Bool, desired: Bool) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        
        if value == expected {
            value = desired
            return true
        }
        return false
    }
}

/// Thread-safe atomic integer
/// Use for counters/ticks that need cross-thread access (NOT RT thread)
/// For RT thread access, use RTSafeCounter or RTSafeAtomic<Int> instead
final class AtomicInt {
    private nonisolated(unsafe) var lock = os_unfair_lock_s()
    private nonisolated(unsafe) var value: Int
    
    init(_ initialValue: Int = 0) {
        self.value = initialValue
    }
    
    nonisolated func load() -> Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return value
    }
    
    nonisolated func store(_ newValue: Int) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        value = newValue
    }
    
    nonisolated func increment() -> Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        value += 1
        return value
    }
    
    nonisolated func decrement() -> Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        value -= 1
        return value
    }
}

/// Thread-safe atomic double
/// Use for timing/position values that need cross-thread access
final class AtomicDouble {
    private nonisolated(unsafe) var lock = os_unfair_lock_s()
    private nonisolated(unsafe) var value: Double
    
    init(_ initialValue: Double = 0.0) {
        self.value = initialValue
    }
    
    nonisolated func load() -> Double {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return value
    }
    
    nonisolated func store(_ newValue: Double) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        value = newValue
    }
}

// MARK: - Usage Documentation

/*
 WHY THIS PATTERN IS NECESSARY:
 
 Real-time audio threads have unique constraints:
 1. CANNOT block (no async/await, no waiting on locks)
 2. CANNOT allocate memory (heap allocation causes latency spikes)
 3. MUST complete in <10ms (often <1ms for low latency)
 
 Swift's actor model is NOT suitable for RT audio:
 - Actors require async/await (RT threads can't wait)
 - Actor isolation hops are not deterministic
 - Actor state access can allocate/block
 
 This RTSafeAtomic pattern:
 ✅ RT thread uses trylock (returns immediately if busy)
 ✅ Non-RT thread can wait (it's not time-critical)
 ✅ Type-safe wrapper encapsulates all unsafety
 ✅ Clear API distinction (try* vs normal methods)
 ✅ Auditable (all nonisolated(unsafe) in ONE file)
 
 PROFESSIONAL DAW STANDARD:
 - Logic Pro, Pro Tools, Ableton use similar patterns
 - Apple's Core Audio examples use trylock for RT threads
 - AVAudioEngine internals use lock-free atomics
 
 WHEN TO USE:
 - Audio thread needs to read transport state (beat position, tempo)
 - Audio thread needs to write error counters (clipping, underruns)
 - Audio thread needs to access plugin state (latency, bypass)
 - Background thread needs to read/reset those values
 
 WHEN NOT TO USE:
 - Main thread ↔ main thread (use @MainActor)
 - Background ↔ background (use actor)
 - No RT constraints (use Sendable + actor)
 */
