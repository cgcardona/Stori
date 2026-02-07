//
//  AudioPerformanceMonitor.swift
//  Stori
//
//  Performance monitoring and telemetry for audio operations.
//  Tracks operation timing and identifies performance bottlenecks.
//

import Foundation
import QuartzCore
import Observation

// MARK: - Performance Event

struct PerformanceEvent {
    let operation: String
    let durationMs: Double
    let timestamp: Date
    let context: [String: String]
    
    var isSlow: Bool {
        // Operations over 100ms are considered slow for audio
        durationMs > 100
    }
    
    var isVerySlow: Bool {
        // Operations over 500ms are critical performance issues
        durationMs > 500
    }
}

// MARK: - Audio Performance Monitor

/// Monitors performance of audio operations and identifies bottlenecks.
@Observable
@MainActor
final class AudioPerformanceMonitor {
    
    // MARK: - Configuration
    
    /// Whether performance monitoring is enabled
    var isEnabled: Bool = true
    
    /// Maximum number of events to keep in history
    private static let maxEventHistory = 500
    
    /// Threshold for slow operation warnings (ms)
    private static let slowOperationThreshold: Double = 100
    
    /// Threshold for very slow operation errors (ms)
    private static let verySlowOperationThreshold: Double = 500
    
    // MARK: - State
    
    /// Recent performance events (newest first)
    private(set) var recentEvents: [PerformanceEvent] = []
    
    /// Statistics per operation type
    private(set) var operationStats: [String: OperationStatistics] = [:]
    
    struct OperationStatistics {
        var callCount: Int = 0
        var totalDurationMs: Double = 0
        var minDurationMs: Double = .infinity
        var maxDurationMs: Double = 0
        var slowCount: Int = 0
        var verySlowCount: Int = 0
        
        var averageDurationMs: Double {
            guard callCount > 0 else { return 0 }
            return totalDurationMs / Double(callCount)
        }
        
        var slowPercentage: Double {
            guard callCount > 0 else { return 0 }
            return Double(slowCount) / Double(callCount) * 100
        }
    }
    
    // MARK: - Singleton
    
    static let shared = AudioPerformanceMonitor()
    
    init() {}
    
    // MARK: - Timing Measurement
    
    /// Measure the performance of an operation.
    /// Returns the result of the operation and records timing.
    func measure<T>(
        operation: String,
        context: [String: String] = [:],
        _ work: () throws -> T
    ) rethrows -> T {
        guard isEnabled else {
            return try work()
        }
        
        let start = CACurrentMediaTime()
        defer {
            let duration = CACurrentMediaTime() - start
            recordTiming(operation: operation, durationSeconds: duration, context: context)
        }
        
        return try work()
    }
    
    /// Measure async operation performance
    func measureAsync<T: Sendable>(
        operation: String,
        context: [String: String] = [:],
        _ work: () async throws -> T
    ) async rethrows -> T {
        guard isEnabled else {
            return try await work()
        }
        
        let start = CACurrentMediaTime()
        defer {
            let duration = CACurrentMediaTime() - start
            recordTiming(operation: operation, durationSeconds: duration, context: context)
        }
        
        return try await work()
    }
    
    // MARK: - Manual Timing
    
    /// Start timing an operation (for manual measurement)
    func startTiming() -> TimeInterval {
        return CACurrentMediaTime()
    }
    
    /// Record timing for a manually timed operation
    func recordTiming(operation: String, startTime: TimeInterval, context: [String: String] = [:]) {
        let duration = CACurrentMediaTime() - startTime
        recordTiming(operation: operation, durationSeconds: duration, context: context)
    }
    
    // MARK: - Private Implementation
    
    private func recordTiming(operation: String, durationSeconds: TimeInterval, context: [String: String]) {
        let durationMs = durationSeconds * 1000.0
        
        // Create event
        let event = PerformanceEvent(
            operation: operation,
            durationMs: durationMs,
            timestamp: Date(),
            context: context
        )
        
        // Add to history
        recentEvents.insert(event, at: 0)
        if recentEvents.count > Self.maxEventHistory {
            recentEvents.removeLast()
        }
        
        // Update statistics
        var stats = operationStats[operation] ?? OperationStatistics()
        stats.callCount += 1
        stats.totalDurationMs += durationMs
        stats.minDurationMs = min(stats.minDurationMs, durationMs)
        stats.maxDurationMs = max(stats.maxDurationMs, durationMs)
        
        if durationMs > Self.slowOperationThreshold {
            stats.slowCount += 1
        }
        if durationMs > Self.verySlowOperationThreshold {
            stats.verySlowCount += 1
        }
        
        operationStats[operation] = stats
        
        // Log slow operations
        if event.isVerySlow {
            let contextStr = context.isEmpty ? "" : " (\(context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")))"
            AppLogger.shared.warning(
                "Performance: \(operation) took \(String(format: "%.1f", durationMs))ms\(contextStr)",
                category: .audio
            )
        } else if event.isSlow {
            let contextStr = context.isEmpty ? "" : " (\(context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")))"
            AppLogger.shared.debug(
                "Performance: \(operation) took \(String(format: "%.1f", durationMs))ms\(contextStr)",
                category: .audio
            )
        }
    }
    
    // MARK: - Query Methods
    
    /// Get statistics for a specific operation
    func getStatistics(for operation: String) -> OperationStatistics? {
        return operationStats[operation]
    }
    
    /// Get all operations sorted by average duration
    func getSlowestOperations(limit: Int = 10) -> [(operation: String, stats: OperationStatistics)] {
        return operationStats
            .map { ($0.key, $0.value) }
            .sorted { $0.1.averageDurationMs > $1.1.averageDurationMs }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Get recent slow operations
    func getRecentSlowOperations(within seconds: TimeInterval = 60, limit: Int = 20) -> [PerformanceEvent] {
        let cutoff = Date().addingTimeInterval(-seconds)
        return recentEvents
            .filter { $0.timestamp > cutoff && $0.isSlow }
            .prefix(limit)
            .map { $0 }
    }
    
    /// Clear all performance data
    func reset() {
        recentEvents.removeAll()
        operationStats.removeAll()
        AppLogger.shared.info("AudioPerformanceMonitor: Performance data cleared", category: .audio)
    }
    
    /// Get performance summary for logging
    func getSummary() -> String {
        let totalOps = operationStats.values.reduce(0) { $0 + $1.callCount }
        let totalSlowOps = operationStats.values.reduce(0) { $0 + $1.slowCount }
        let slowPercentage = totalOps > 0 ? Double(totalSlowOps) / Double(totalOps) * 100 : 0
        
        return "Total ops: \(totalOps), Slow: \(totalSlowOps) (\(String(format: "%.1f", slowPercentage))%)"
    }
    
    // MARK: - Cleanup
    
    deinit {
        // CRITICAL: Protective deinit for @Observable @MainActor class (ASan Issue #84742+)
        // Prevents double-free from implicit Swift Concurrency property change notification tasks
    }
}
