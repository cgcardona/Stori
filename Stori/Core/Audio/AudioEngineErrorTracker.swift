//
//  AudioEngineErrorTracker.swift
//  Stori
//
//  Tracks audio engine errors and surfaces critical issues to users.
//  CRITICAL: Prevents silent failures where playback stops working without explanation.
//

import Foundation
import Observation

// MARK: - Error Severity

enum AudioErrorSeverity: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case critical = 4
    
    static func < (lhs: AudioErrorSeverity, rhs: AudioErrorSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
    
    var logLevel: AppLogger.Level {
        switch self {
        case .debug, .info: return .info
        case .warning: return .warning
        case .error, .critical: return .error
        }
    }
    
    var displayName: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        case .critical: return "Critical"
        }
    }
    
    var userFacingLabel: String {
        switch self {
        case .debug, .info: return "ℹ️"
        case .warning: return "⚠️"
        case .error: return "❌"
        case .critical: return "🔴"
        }
    }
}

// MARK: - Error Entry

struct AudioErrorEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let severity: AudioErrorSeverity
    let component: String
    let message: String
    let context: [String: String]
    let stackTrace: String?
    
    init(
        severity: AudioErrorSeverity,
        component: String,
        message: String,
        context: [String: String] = [:],
        stackTrace: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.severity = severity
        self.component = component
        self.message = message
        self.context = context
        self.stackTrace = stackTrace
    }
    
    /// User-facing error description
    var userDescription: String {
        "\(severity.userFacingLabel) \(component): \(message)"
    }
    
    /// Detailed description for logging/debugging
    var detailedDescription: String {
        var desc = "[\(severity.displayName)] \(component): \(message)"
        if !context.isEmpty {
            let contextStr = context.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            desc += " (\(contextStr))"
        }
        if let stack = stackTrace {
            desc += "\n\(stack)"
        }
        return desc
    }
}

// MARK: - Audio Engine Error Tracker

/// Tracks audio engine errors and provides health insights.
/// Surfaces critical errors to users via notifications.
@Observable
@MainActor
final class AudioEngineErrorTracker {
    
    // MARK: - Configuration
    
    /// Maximum number of errors to keep in history
    private static let maxErrorHistory = 200
    
    /// Time window for critical error counting (seconds)
    private static let criticalErrorWindow: TimeInterval = 60
    
    /// Maximum critical errors before declaring unhealthy
    private static let maxCriticalErrorsInWindow = 3
    
    /// Time window for error rate calculation (seconds)
    private static let errorRateWindow: TimeInterval = 30
    
    // MARK: - State
    
    /// Recent error history (newest first)
    private(set) var recentErrors: [AudioErrorEntry] = []
    
    /// Current engine health based on error patterns
    private(set) var engineHealth: EngineHealthStatus = .healthy
    
    /// Last time health was recalculated
    private var lastHealthCheck: Date = Date()
    
    /// Whether to show errors in UI
    var showErrorsInUI: Bool = true
    
    // MARK: - Singleton
    
    static let shared = AudioEngineErrorTracker()
    
    private init() {
        // Setup periodic health recalculation
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recalculateHealth()
            }
        }
    }
    
    // MARK: - Error Recording
    
    /// Record an error with full context.
    /// Critical errors trigger immediate user notification.
    func recordError(
        severity: AudioErrorSeverity,
        component: String,
        message: String,
        context: [String: String] = [:],
        stackTrace: String? = nil
    ) {
        let entry = AudioErrorEntry(
            severity: severity,
            component: component,
            message: message,
            context: context,
            stackTrace: stackTrace
        )
        
        // Add to history (prepend for newest-first)
        recentErrors.insert(entry, at: 0)
        
        // Trim history if needed
        if recentErrors.count > Self.maxErrorHistory {
            recentErrors.removeLast()
        }
        
        // Log to system logger
        switch severity.logLevel {
        case .info:
            AppLogger.shared.info(entry.detailedDescription, category: .audio)
        case .warning:
            AppLogger.shared.warning(entry.detailedDescription, category: .audio)
        case .error:
            AppLogger.shared.error(entry.detailedDescription, category: .audio)
        @unknown default:
            AppLogger.shared.info(entry.detailedDescription, category: .audio)
        }
        
        // Critical errors trigger immediate notification
        if severity == .critical {
            NotificationCenter.default.post(
                name: .audioEngineCriticalError,
                object: entry,
                userInfo: ["message": message, "component": component]
            )
        }
        
        // Recalculate health after new error
        recalculateHealth()
    }
    
    /// Convenience method for recording errors with Error object and automatic stack trace
    func recordError(
        severity: AudioErrorSeverity,
        component: String,
        message: String,
        error: Error,
        additionalContext: [String: String] = [:]
    ) {
        var context = additionalContext
        context["error"] = error.localizedDescription
        context["errorType"] = String(describing: type(of: error))
        
        // Capture stack trace for critical errors (debug builds only)
        var stackTrace: String? = nil
        #if DEBUG
        if severity >= .error {
            stackTrace = Thread.callStackSymbols.joined(separator: "\n")
        }
        #endif
        
        recordError(
            severity: severity,
            component: component,
            message: message,
            context: context,
            stackTrace: stackTrace
        )
    }
    
    // MARK: - Health Analysis
    
    /// Recalculate engine health based on recent error patterns
    private func recalculateHealth() {
        lastHealthCheck = Date()
        
        let now = Date()
        
        // Count critical errors in recent window
        let recentCritical = recentErrors.filter {
            $0.severity == .critical &&
            now.timeIntervalSince($0.timestamp) < Self.criticalErrorWindow
        }
        
        if recentCritical.count >= Self.maxCriticalErrorsInWindow {
            engineHealth = .critical(
                reason: "Multiple critical errors (\(recentCritical.count)) in last \(Int(Self.criticalErrorWindow))s"
            )
            return
        }
        
        // Count errors in recent window
        let recentErrorsInWindow = recentErrors.filter {
            $0.severity >= .error &&
            now.timeIntervalSince($0.timestamp) < Self.errorRateWindow
        }
        
        if recentErrorsInWindow.count >= 10 {
            engineHealth = .unhealthy(
                reason: "High error rate (\(recentErrorsInWindow.count) errors in \(Int(Self.errorRateWindow))s)"
            )
            return
        }
        
        // Count warnings in recent window
        let recentWarnings = recentErrors.filter {
            $0.severity == .warning &&
            now.timeIntervalSince($0.timestamp) < Self.errorRateWindow
        }
        
        if recentWarnings.count >= 20 {
            engineHealth = .degraded(
                reason: "Many warnings (\(recentWarnings.count) in \(Int(Self.errorRateWindow))s)"
            )
            return
        }
        
        // No significant issues
        engineHealth = .healthy
    }
    
    // MARK: - Query Methods
    
    /// Get errors by severity
    func getErrors(severity: AudioErrorSeverity) -> [AudioErrorEntry] {
        return recentErrors.filter { $0.severity == severity }
    }
    
    /// Get errors by component
    func getErrors(component: String) -> [AudioErrorEntry] {
        return recentErrors.filter { $0.component == component }
    }
    
    /// Get recent errors (last N seconds)
    func getRecentErrors(within seconds: TimeInterval = 60) -> [AudioErrorEntry] {
        let cutoff = Date().addingTimeInterval(-seconds)
        return recentErrors.filter { $0.timestamp > cutoff }
    }
    
    /// Get error summary for display
    func getErrorSummary() -> String {
        let criticalCount = recentErrors.filter { $0.severity == .critical }.count
        let errorCount = recentErrors.filter { $0.severity == .error }.count
        let warningCount = recentErrors.filter { $0.severity == .warning }.count
        
        if criticalCount > 0 {
            return "🔴 \(criticalCount) critical, \(errorCount) errors, \(warningCount) warnings"
        } else if errorCount > 0 {
            return "❌ \(errorCount) errors, \(warningCount) warnings"
        } else if warningCount > 0 {
            return "⚠️ \(warningCount) warnings"
        } else {
            return "✅ No recent issues"
        }
    }
    
    /// Clear all errors (for testing or user action)
    func clearErrors() {
        recentErrors.removeAll()
        recalculateHealth()
        AppLogger.shared.info("AudioEngineErrorTracker: Error history cleared", category: .audio)
    }
    
    /// Clear errors older than specified time
    func clearOldErrors(olderThan seconds: TimeInterval = 300) {
        let cutoff = Date().addingTimeInterval(-seconds)
        let beforeCount = recentErrors.count
        recentErrors.removeAll { $0.timestamp < cutoff }
        let removed = beforeCount - recentErrors.count
        
        if removed > 0 {
            AppLogger.shared.debug("AudioEngineErrorTracker: Cleared \(removed) old errors", category: .audio)
            recalculateHealth()
        }
    }
    
    // MARK: - Cleanup
    
    deinit {
        // CRITICAL: Protective deinit for @Observable @MainActor class (ASan Issue #84742+)
        // Prevents double-free from implicit Swift Concurrency property change notification tasks
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when a critical audio error occurs (userInfo contains error details)
    static let audioEngineCriticalError = Notification.Name("audioEngineCriticalError")
}
