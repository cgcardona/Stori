//
//  RTSafeAtomic.swift
//  Stori
//
//  Real-time safe atomic wrappers using Swift Atomics (lock-free)
//  NO unsafe keywords - 100% safe, modern Swift
//

import Foundation
import Atomics

// MARK: - Real-Time Safe Counter (Lock-Free)

/// Lock-free atomic counter for real-time audio thread
/// Uses ManagedAtomic from Swift Atomics (official Apple package)
/// 
/// PROFESSIONAL DAW STANDARD:
/// - Truly lock-free (no locks, no blocking, no unsafe)
/// - Safe to use from any thread including RT audio callbacks
/// - Zero allocation, zero blocking, zero syscalls
///
/// USAGE:
/// ```swift
/// @ObservationIgnored
/// private let clipCount = RTSafeCounter()
///
/// // RT audio thread (lock-free):
/// clipCount.increment()
///
/// // Non-RT thread:
/// let count = clipCount.readAndReset()
/// ```
final class RTSafeCounter: Sendable {
    private let counter: ManagedAtomic<UInt32>
    
    init() {
        self.counter = ManagedAtomic(0)
    }
    
    /// Increment counter (lock-free, safe from any thread including RT)
    func increment() {
        counter.wrappingIncrement(ordering: .relaxed)
    }
    
    /// Read and reset counter to 0 (lock-free, typically called from non-RT thread)
    func readAndReset() -> UInt32 {
        counter.exchange(0, ordering: .relaxed)
    }
    
    /// Read current value without resetting (lock-free)
    func read() -> UInt32 {
        counter.load(ordering: .relaxed)
    }
}

// MARK: - Real-Time Safe Max Tracker (Lock-Free)

/// Lock-free atomic max value tracker for real-time audio thread
/// Uses ManagedAtomic with compare-and-swap loop
///
/// PROFESSIONAL DAW STANDARD:
/// - Truly lock-free (no locks, no blocking, no unsafe)
/// - Safe to use from any thread including RT audio callbacks
/// - Uses CAS loop for max tracking (standard lock-free pattern)
///
/// USAGE:
/// ```swift
/// @ObservationIgnored
/// private let maxLevel = RTSafeMaxTracker()
///
/// // RT audio thread (lock-free):
/// maxLevel.updateMax(1.05)
///
/// // Non-RT thread:
/// let max = maxLevel.readAndReset()
/// ```
final class RTSafeMaxTracker: Sendable {
    private let maxValue: ManagedAtomic<UInt32>  // Store as bits (reinterpret Float as UInt32)
    
    init() {
        self.maxValue = ManagedAtomic(0)
    }
    
    /// Update max value (lock-free CAS loop, safe from RT thread)
    func updateMax(_ newValue: Float) {
        let newBits = newValue.bitPattern
        
        // CAS loop: standard lock-free pattern for max tracking
        var currentBits = maxValue.load(ordering: .relaxed)
        while true {
            let currentValue = Float(bitPattern: currentBits)
            
            // Only update if new value is greater
            guard newValue > currentValue else { break }
            
            // Try to swap: if someone else updated, loop and try again
            let (exchanged, original) = maxValue.compareExchange(
                expected: currentBits,
                desired: newBits,
                ordering: .relaxed
            )
            
            if exchanged {
                break  // Success!
            }
            
            // Another thread updated, try again with new value
            currentBits = original
        }
    }
    
    /// Read and reset max to 0.0 (lock-free)
    func readAndReset() -> Float {
        let bits = maxValue.exchange(0, ordering: .relaxed)
        return Float(bitPattern: bits)
    }
    
    /// Read current max without resetting (lock-free)
    func read() -> Float {
        let bits = maxValue.load(ordering: .relaxed)
        return Float(bitPattern: bits)
    }
}

// MARK: - Documentation

/*
 WHY SWIFT ATOMICS INSTEAD OF os_unfair_lock?
 
 1. **Truly Lock-Free**: ManagedAtomic uses CPU atomic instructions (e.g., LDREX/STREX on ARM,
    LOCK CMPXCHG on x86). No kernel calls, no thread blocking, no priority inversion.
    
 2. **No Unsafe Keywords**: Swift Atomics is designed for Swift 6 strict concurrency.
    No `nonisolated(unsafe)`, no `@unchecked Sendable` required.
    
 3. **Real-Time Safe**: Lock-free atomics are standard in professional audio software.
    Logic Pro, Pro Tools, Ableton Live all use similar techniques.
    
 4. **Official Apple Package**: Maintained by the Swift team, designed for exactly this use case.
 
 5. **Performance**: Atomic operations are ~1-5 CPU cycles. Locks can be 100+ cycles and
    may cause context switches (catastrophic for RT audio).
 
 MEMORY ORDERING:
 - We use `.relaxed` ordering because we don't need happens-before guarantees.
 - The counter is just for statistics (logging). Slight delay is acceptable.
 - If we needed strict ordering, we'd use `.sequentiallyConsistent`.
 
 FLOAT AS UINT32:
 - We store Float as UInt32 bits because ManagedAtomic requires AtomicValue protocol.
 - Float doesn't conform to AtomicValue, but UInt32 does.
 - bitPattern conversion is zero-cost (just reinterpret bits).
 - CAS loop handles race conditions correctly even with this encoding.
 
 PERFORMANCE:
 - RTSafeCounter.increment(): ~2 CPU cycles (one atomic wrappingIncrement)
 - RTSafeMaxTracker.updateMax(): ~10-50 cycles (CAS loop, typically 1-2 iterations)
 - Both are well under 1 microsecond, safe for RT thread with <10ms deadline
 
 COMPARISON TO LOCKS:
 - os_unfair_lock: 50-200 cycles, may spin, can cause priority inversion
 - pthread_mutex: 100-500 cycles, syscall, can block thread
 - Swift Atomics: 2-50 cycles, never blocks, truly lock-free
 
 REFERENCES:
 - Swift Atomics: https://github.com/apple/swift-atomics
 - Lock-Free Programming: "The Art of Multiprocessor Programming" by Herlihy & Shavit
 - Real-Time Audio: "Designing Audio Effect Plugins in C++" by Pirkle (Chapter on RT safety)
 */
