//
//  CancellationBag.swift
//  Stori
//
//  Owns timers and tasks in a nonisolated place for clean deinit
//  Eliminates retain cycles and nonisolated(unsafe) anti-pattern
//

import Foundation

/// Owns cancellation of timers/tasks in a nonisolated place.
/// Use this to eliminate timer retain cycles and enable clean deinit.
///
/// PROBLEM IT SOLVES:
/// 1. Timer retain cycle: self → timer → handler → self
/// 2. deinit isolation: @MainActor class can't access actor properties in deinit
/// 3. nonisolated(unsafe) anti-pattern: forced to use unsafe escapes
///
/// SOLUTION:
/// - CancellationBag is NOT actor-isolated
/// - CancellationBag is @ObservationIgnored (not observable)
/// - deinit can synchronously cancel everything
/// - Timers/tasks use [weak self] to break cycles
///
/// USAGE:
/// ```swift
/// @Observable @MainActor
/// final class AudioEngine {
///     @ObservationIgnored
///     private let cancels = CancellationBag()
///
///     func startTimer() {
///         let timer = DispatchSource.makeTimerSource(queue: .utility)
///         timer.schedule(deadline: .now() + 1, repeating: 1)
///         timer.setEventHandler { [weak self] in
///             guard let self else { return }
///             self.doWork()
///         }
///         timer.resume()
///         cancels.insert(timer: timer)
///     }
///
///     deinit {
///         // ✅ Legal: cancels is nonisolated
///         // ✅ Synchronous: happens before dealloc
///         cancels.cancelAll()
///     }
/// }
/// ```
final class CancellationBag {
    private var timers: [DispatchSourceTimer] = []
    private var tasks: [Task<Void, Never>] = []
    private let lock = NSLock()
    
    /// Add a timer to the bag
    /// Timer will be cancelled when bag is deallocated or cancelAll() is called
    func insert(timer: DispatchSourceTimer) {
        lock.lock()
        defer { lock.unlock() }
        timers.append(timer)
    }
    
    /// Add a task to the bag
    /// Task will be cancelled when bag is deallocated or cancelAll() is called
    func insert(task: Task<Void, Never>) {
        lock.lock()
        defer { lock.unlock() }
        tasks.append(task)
    }
    
    /// Cancel all timers and tasks synchronously
    /// Safe to call multiple times (idempotent)
    func cancelAll() {
        lock.lock()
        let tasksToCancel = tasks
        let timersToCancel = timers
        tasks.removeAll()
        timers.removeAll()
        lock.unlock()
        
        DiagnosticLogger.shared.log("🧹 CancellationBag cancelling \(tasksToCancel.count) tasks, \(timersToCancel.count) timers")
        
        // Cancel tasks first so they stop scheduling work
        for task in tasksToCancel {
            task.cancel()
        }
        
        // Cancel timers and clear handlers to break retain cycles
        for timer in timersToCancel {
            // Defensive: clear handler before cancel to break any remaining cycles
            timer.setEventHandler {}
            timer.cancel()
        }
        
        DiagnosticLogger.shared.log("✅ CancellationBag cancel complete")
    }
    
    /// Synchronously cancel everything before deallocation
    deinit {
        cancelAll()
    }
}

// MARK: - Testing Helper

#if DEBUG
extension CancellationBag {
    /// Check if bag has been emptied (for tests)
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return timers.isEmpty && tasks.isEmpty
    }
    
    /// Count of active timers/tasks (for diagnostics)
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return timers.count + tasks.count
    }
}
#endif
