//
//  AudioEngineHealthMonitor.swift
//  Stori
//
//  Validates audio engine state consistency and detects desyncs.
//  CRITICAL: Prevents silent failures where UI shows "playing" but audio is broken.
//

import Foundation
import AVFoundation
import Observation

// MARK: - Engine Health Status

/// Represents the health status of the audio engine
enum EngineHealthStatus: Equatable {
    case healthy
    case degraded(reason: String)
    case unhealthy(reason: String)
    case critical(reason: String)
    
    var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }
    
    var requiresRecovery: Bool {
        switch self {
        case .unhealthy, .critical:
            return true
        default:
            return false
        }
    }
}

// MARK: - Engine Health Monitor

/// Validates audio engine state consistency and detects desyncs.
/// Call `validateState()` before critical operations to ensure engine is ready.
@Observable
@MainActor
final class AudioEngineHealthMonitor {
    
    // MARK: - Observable State
    
    private(set) var currentHealth: EngineHealthStatus = .healthy
    private(set) var lastValidationTime: Date = Date()
    
    // MARK: - Validation Results
    
    struct ValidationResult {
        let isValid: Bool
        let issues: [ValidationIssue]
        let timestamp: Date
        
        var criticalIssues: [ValidationIssue] {
            issues.filter { $0.severity == .critical }
        }
        
        var errorIssues: [ValidationIssue] {
            issues.filter { $0.severity == .error }
        }
    }
    
    struct ValidationIssue {
        enum Severity {
            case warning
            case error
            case critical
        }
        
        let severity: Severity
        let component: String
        let description: String
        let recoveryHint: String?
        
        var logMessage: String {
            var msg = "[\(severity)] \(component): \(description)"
            if let hint = recoveryHint {
                msg += " (Hint: \(hint))"
            }
            return msg
        }
    }
    
    // MARK: - Dependencies
    
    private weak var engine: AVAudioEngine?
    private weak var mixer: AVAudioMixerNode?
    private weak var masterEQ: AVAudioUnitEQ?
    private weak var masterLimiter: AVAudioUnitEffect?
    private var getGraphFormat: (() -> AVAudioFormat?)?
    private var getIsGraphStable: (() -> Bool)?
    private var getIsGraphReady: (() -> Bool)?
    private var getTrackNodes: (() -> [UUID: TrackAudioNode])?
    
    // MARK: - Configuration
    
    func configure(
        engine: AVAudioEngine,
        mixer: AVAudioMixerNode,
        masterEQ: AVAudioUnitEQ,
        masterLimiter: AVAudioUnitEffect,
        getGraphFormat: @escaping () -> AVAudioFormat?,
        getIsGraphStable: @escaping () -> Bool,
        getIsGraphReady: @escaping () -> Bool,
        getTrackNodes: @escaping () -> [UUID: TrackAudioNode]
    ) {
        self.engine = engine
        self.mixer = mixer
        self.masterEQ = masterEQ
        self.masterLimiter = masterLimiter
        self.getGraphFormat = getGraphFormat
        self.getIsGraphStable = getIsGraphStable
        self.getIsGraphReady = getIsGraphReady
        self.getTrackNodes = getTrackNodes
    }
    
    // MARK: - Validation
    
    /// Validates the complete engine state.
    /// Call before critical operations like play, record, or plugin insertion.
    /// Returns true if engine is healthy and ready for operation.
    @discardableResult
    func validateState() -> ValidationResult {
        var issues: [ValidationIssue] = []
        
        // 1. Validate engine reference
        guard let engine = engine else {
            issues.append(ValidationIssue(
                severity: .critical,
                component: "Engine",
                description: "AVAudioEngine reference is nil",
                recoveryHint: "Reinitialize audio engine"
            ))
            return finalize(issues: issues)
        }
        
        // 2. Validate engine is running when expected
        let isGraphReady = getIsGraphReady?() ?? false
        if isGraphReady && !engine.isRunning {
            issues.append(ValidationIssue(
                severity: .critical,
                component: "Engine",
                description: "Graph marked ready but engine is not running",
                recoveryHint: "Call engine.start()"
            ))
        }
        
        // 3. Validate critical nodes are attached
        guard let mixer = mixer else {
            issues.append(ValidationIssue(
                severity: .critical,
                component: "Mixer",
                description: "Main mixer node is nil",
                recoveryHint: "Recreate mixer node"
            ))
            return finalize(issues: issues)
        }
        
        // CRITICAL: Check mixer.engine first, before calling AVFoundation methods
        // Calling engine.attachedNodes.contains() on a node from another engine causes assertions
        if mixer.engine !== engine {
            issues.append(ValidationIssue(
                severity: .critical,
                component: "Mixer",
                description: "Mixer is attached to different engine instance",
                recoveryHint: "Detach and reattach to correct engine"
            ))
            // Early return - can't safely query engine about this mixer
            return finalize(issues: issues)
        }
        
        if !engine.attachedNodes.contains(mixer) {
            issues.append(ValidationIssue(
                severity: .critical,
                component: "Mixer",
                description: "Mixer node is not attached to engine",
                recoveryHint: "Call engine.attach(mixer)"
            ))
            // Early return - can't safely query outputConnectionPoints for unattached node
            return finalize(issues: issues)
        }
        
        // 4. Validate master chain nodes
        if let masterEQ = masterEQ {
            // Check if attached to correct engine first
            if masterEQ.engine !== engine {
                issues.append(ValidationIssue(
                    severity: .error,
                    component: "MasterEQ",
                    description: "Master EQ is attached to different engine instance",
                    recoveryHint: "Detach and reattach to correct engine"
                ))
            } else if !engine.attachedNodes.contains(masterEQ) {
                issues.append(ValidationIssue(
                    severity: .error,
                    component: "MasterEQ",
                    description: "Master EQ is not attached to engine",
                    recoveryHint: "Reattach master chain"
                ))
            }
        }
        
        if let masterLimiter = masterLimiter {
            // Check if attached to correct engine first
            if masterLimiter.engine !== engine {
                issues.append(ValidationIssue(
                    severity: .error,
                    component: "MasterLimiter",
                    description: "Master limiter is attached to different engine instance",
                    recoveryHint: "Detach and reattach to correct engine"
                ))
            } else if !engine.attachedNodes.contains(masterLimiter) {
                issues.append(ValidationIssue(
                    severity: .error,
                    component: "MasterLimiter",
                    description: "Master limiter is not attached to engine",
                    recoveryHint: "Reattach master chain"
                ))
            }
        }
        
        // 5. Validate output node connections
        let outputConnections = engine.outputConnectionPoints(for: mixer, outputBus: 0)
        if outputConnections.isEmpty && engine.isRunning {
            issues.append(ValidationIssue(
                severity: .critical,
                component: "Routing",
                description: "Mixer has no output connections",
                recoveryHint: "Rebuild master signal chain"
            ))
        }
        
        // 6. Validate format consistency
        if let graphFormat = getGraphFormat?() {
            let hardwareFormat = engine.outputNode.inputFormat(forBus: 0)
            
            // Warn if sample rates don't match (could indicate missing converter)
            if abs(graphFormat.sampleRate - hardwareFormat.sampleRate) > 1.0 {
                issues.append(ValidationIssue(
                    severity: .warning,
                    component: "Format",
                    description: "Graph format (\(graphFormat.sampleRate)Hz) != hardware format (\(hardwareFormat.sampleRate)Hz)",
                    recoveryHint: "Update graphFormat or add sample rate converter"
                ))
            }
            
            // Check channel count consistency
            if graphFormat.channelCount != hardwareFormat.channelCount {
                issues.append(ValidationIssue(
                    severity: .warning,
                    component: "Format",
                    description: "Channel count mismatch: graph=\(graphFormat.channelCount), hardware=\(hardwareFormat.channelCount)",
                    recoveryHint: "Rebuild connections with correct channel count"
                ))
            }
        }
        
        // 7. Validate track node consistency
        if let trackNodes = getTrackNodes?() {
            for (trackId, trackNode) in trackNodes {
                // Check if player node is attached
                if trackNode.playerNode.engine !== engine {
                    issues.append(ValidationIssue(
                        severity: .error,
                        component: "Track[\(trackId)]",
                        description: "Player node attached to wrong engine",
                        recoveryHint: "Rebuild track graph"
                    ))
                }
                
                // Check if player has output connections when it should
                if engine.isRunning && engine.attachedNodes.contains(trackNode.playerNode) {
                    let connections = engine.outputConnectionPoints(for: trackNode.playerNode, outputBus: 0)
                    if connections.isEmpty {
                        issues.append(ValidationIssue(
                            severity: .error,
                            component: "Track[\(trackId)]",
                            description: "Player node has no output connections",
                            recoveryHint: "Rebuild track connections"
                        ))
                    }
                }
            }
        }
        
        // 8. Validate state consistency
        let isGraphStable = getIsGraphStable?() ?? true
        if !isGraphStable && engine.isRunning && isGraphReady {
            issues.append(ValidationIssue(
                severity: .warning,
                component: "State",
                description: "Graph unstable but marked as ready",
                recoveryHint: "Wait for graph stabilization"
            ))
        }
        
        return finalize(issues: issues)
    }
    
    /// Quick validation for hot paths (play/pause/seek).
    /// Only checks critical invariants without detailed graph inspection.
    func quickValidate() -> Bool {
        guard let engine = engine else { return false }
        guard let mixer = mixer else { return false }
        
        // Must have engine running and mixer attached
        if !engine.isRunning { return false }
        if !engine.attachedNodes.contains(mixer) { return false }
        if mixer.engine !== engine { return false }
        
        return true
    }
    
    // MARK: - Private Helpers
    
    private func finalize(issues: [ValidationIssue]) -> ValidationResult {
        lastValidationTime = Date()
        
        // Update health status
        if issues.isEmpty {
            currentHealth = .healthy
        } else if let criticalIssue = issues.first(where: { $0.severity == .critical }) {
            currentHealth = .critical(reason: criticalIssue.description)
        } else if let errorIssue = issues.first(where: { $0.severity == .error }) {
            currentHealth = .unhealthy(reason: errorIssue.description)
        } else if let warningIssue = issues.first {
            currentHealth = .degraded(reason: warningIssue.description)
        } else {
            // Fallback: should never reach here, but be safe
            currentHealth = .healthy
        }
        
        // Log issues
        for issue in issues {
            switch issue.severity {
            case .warning:
                AppLogger.shared.warning(issue.logMessage, category: .audio)
            case .error, .critical:
                AppLogger.shared.error(issue.logMessage, category: .audio)
            }
        }
        
        return ValidationResult(
            isValid: issues.filter({ $0.severity != .warning }).isEmpty,
            issues: issues,
            timestamp: Date()
        )
    }
    
    // MARK: - Recovery Suggestions
    
    /// Get suggested recovery actions for current health status
    func getRecoverySuggestions() -> [String] {
        switch currentHealth {
        case .healthy:
            return []
        case .degraded(let reason):
            return ["Warning: \(reason)"]
        case .unhealthy(let reason):
            return [
                "Engine is unhealthy: \(reason)",
                "Try: Stop playback and restart audio engine",
                "If issue persists: Check Audio MIDI Setup preferences"
            ]
        case .critical(let reason):
            return [
                "CRITICAL: \(reason)",
                "Required: Restart audio engine immediately",
                "Stop all playback and rebuild audio graph",
                "If this persists, quit and relaunch the application"
            ]
        }
    }
    
    // MARK: - Cleanup
    
    // No async resources owned.
    // No deinit required.
}
