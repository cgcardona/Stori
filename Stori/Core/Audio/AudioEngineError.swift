//
//  AudioEngineError.swift
//  Stori
//
//  Comprehensive error types for audio engine operations.
//  Provides structured error handling with recovery hints.
//

import Foundation

// MARK: - Audio Engine Error

/// Comprehensive error type for audio engine operations.
/// Includes recovery hints and structured information for diagnostics.
enum AudioEngineError: Error, LocalizedError, CustomStringConvertible {
    
    // MARK: - Engine State Errors
    
    case engineNotRunning
    case engineNotReady
    case graphUnstable
    case invalidEngineState(reason: String)
    
    // MARK: - Format Errors
    
    case invalidFormat(reason: String)
    case formatMismatch(expected: Double, actual: Double)
    case unsupportedSampleRate(rate: Double)
    case unsupportedChannelCount(count: Int)
    
    // MARK: - Node Errors
    
    case nodeNotAttached(nodeName: String)
    case nodeAttachedToWrongEngine(nodeName: String)
    case missingNode(nodeName: String)
    case invalidNodeConnection(from: String, to: String, reason: String)
    
    // MARK: - Track Errors
    
    case trackNotFound(trackId: UUID)
    case trackNodeMissing(trackId: UUID)
    case invalidTrackState(trackId: UUID, reason: String)
    
    // MARK: - Audio File Errors
    
    case audioFileNotFound(path: String)
    case audioFileInvalid(path: String, reason: String)
    case audioFileEmpty(path: String)
    case audioFileTooLarge(path: String, size: Int64)
    
    // MARK: - Plugin Errors
    
    case pluginLoadFailed(name: String, reason: String)
    case pluginChainInvalidState(state: String, expectedState: String)
    case pluginNotFound(slot: Int)
    
    // MARK: - MIDI Errors
    
    case midiBlockMissing(trackId: UUID)
    case midiTimingReferenceStale
    case invalidMIDIData(reason: String)
    
    // MARK: - Resource Errors
    
    case memoryPressure
    case allocationLimitReached
    case resourcePoolExhausted
    
    // MARK: - Operation Errors
    
    case operationCancelled(reason: String)
    case operationTimedOut(operation: String, timeout: TimeInterval)
    case staleOperation(reason: String)
    
    // MARK: - LocalizedError Conformance
    
    var errorDescription: String? {
        switch self {
        // Engine State
        case .engineNotRunning:
            return "Audio engine is not running"
        case .engineNotReady:
            return "Audio engine is not ready for operation"
        case .graphUnstable:
            return "Audio graph is being modified - please wait"
        case .invalidEngineState(let reason):
            return "Invalid engine state: \(reason)"
            
        // Format
        case .invalidFormat(let reason):
            return "Invalid audio format: \(reason)"
        case .formatMismatch(let expected, let actual):
            return "Format mismatch: expected \(Int(expected))Hz, got \(Int(actual))Hz"
        case .unsupportedSampleRate(let rate):
            return "Unsupported sample rate: \(Int(rate))Hz"
        case .unsupportedChannelCount(let count):
            return "Unsupported channel count: \(count)"
            
        // Node
        case .nodeNotAttached(let name):
            return "Node '\(name)' is not attached to engine"
        case .nodeAttachedToWrongEngine(let name):
            return "Node '\(name)' is attached to wrong engine instance"
        case .missingNode(let name):
            return "Required node '\(name)' is missing"
        case .invalidNodeConnection(let from, let to, let reason):
            return "Cannot connect \(from) to \(to): \(reason)"
            
        // Track
        case .trackNotFound(let trackId):
            return "Track not found: \(trackId)"
        case .trackNodeMissing(let trackId):
            return "Audio node missing for track: \(trackId)"
        case .invalidTrackState(let trackId, let reason):
            return "Invalid track state for \(trackId): \(reason)"
            
        // Audio File
        case .audioFileNotFound(let path):
            return "Audio file not found: \(path)"
        case .audioFileInvalid(let path, let reason):
            return "Invalid audio file '\(path)': \(reason)"
        case .audioFileEmpty(let path):
            return "Audio file is empty: \(path)"
        case .audioFileTooLarge(let path, let size):
            return "Audio file too large (\(size / 1_000_000)MB): \(path)"
            
        // Plugin
        case .pluginLoadFailed(let name, let reason):
            return "Failed to load plugin '\(name)': \(reason)"
        case .pluginChainInvalidState(let state, let expectedState):
            return "Plugin chain in invalid state '\(state)' (expected '\(expectedState)')"
        case .pluginNotFound(let slot):
            return "No plugin in slot \(slot)"
            
        // MIDI
        case .midiBlockMissing(let trackId):
            return "MIDI block missing for track \(trackId) - instrument not configured"
        case .midiTimingReferenceStale:
            return "MIDI timing reference is stale - regenerating"
        case .invalidMIDIData(let reason):
            return "Invalid MIDI data: \(reason)"
            
        // Resource
        case .memoryPressure:
            return "System is under memory pressure - close other applications"
        case .allocationLimitReached:
            return "Allocation limit reached - too many concurrent operations"
        case .resourcePoolExhausted:
            return "Audio resource pool exhausted - restart recommended"
            
        // Operation
        case .operationCancelled(let reason):
            return "Operation cancelled: \(reason)"
        case .operationTimedOut(let operation, let timeout):
            return "Operation '\(operation)' timed out after \(timeout)s"
        case .staleOperation(let reason):
            return "Operation is stale: \(reason)"
        }
    }
    
    var description: String {
        errorDescription ?? "Unknown audio engine error"
    }
    
    // MARK: - Recovery Hints
    
    /// Suggested recovery action for this error
    var recoveryHint: String? {
        switch self {
        case .engineNotRunning:
            return "Call engine.start()"
        case .engineNotReady:
            return "Wait for graph stabilization"
        case .graphUnstable:
            return "Wait for current operation to complete"
        case .nodeNotAttached:
            return "Rebuild audio graph"
        case .trackNodeMissing:
            return "Recreate track audio node"
        case .audioFileInvalid:
            return "Check file format and integrity"
        case .pluginLoadFailed:
            return "Verify plugin is installed and compatible"
        case .midiBlockMissing:
            return "Reload instrument or restart track"
        case .memoryPressure:
            return "Close other applications or clear caches"
        case .staleOperation:
            return "Retry operation"
        default:
            return nil
        }
    }
    
    // MARK: - Error Severity
    
    /// Severity level for error tracking
    var severity: AudioErrorSeverity {
        switch self {
        case .engineNotRunning, .engineNotReady, .invalidEngineState,
             .nodeAttachedToWrongEngine, .trackNodeMissing,
             .pluginChainInvalidState, .resourcePoolExhausted:
            return .critical
            
        case .graphUnstable, .nodeNotAttached, .trackNotFound,
             .audioFileNotFound, .audioFileInvalid, .audioFileTooLarge,
             .pluginLoadFailed, .midiBlockMissing, .allocationLimitReached:
            return .error
            
        case .formatMismatch, .invalidNodeConnection, .invalidTrackState,
             .audioFileEmpty, .pluginNotFound, .invalidMIDIData,
             .memoryPressure, .operationTimedOut:
            return .warning
            
        case .midiTimingReferenceStale, .operationCancelled, .staleOperation:
            return .info
            
        case .invalidFormat, .unsupportedSampleRate, .unsupportedChannelCount, .missingNode:
            return .error
        }
    }
    
    // MARK: - Component Name
    
    /// Component that generated this error (for tracking)
    var component: String {
        switch self {
        case .engineNotRunning, .engineNotReady, .graphUnstable, .invalidEngineState:
            return "AudioEngine"
        case .invalidFormat, .formatMismatch, .unsupportedSampleRate, .unsupportedChannelCount:
            return "AudioFormat"
        case .nodeNotAttached, .nodeAttachedToWrongEngine, .missingNode, .invalidNodeConnection:
            return "AudioNode"
        case .trackNotFound, .trackNodeMissing, .invalidTrackState:
            return "Track"
        case .audioFileNotFound, .audioFileInvalid, .audioFileEmpty, .audioFileTooLarge:
            return "AudioFile"
        case .pluginLoadFailed, .pluginChainInvalidState, .pluginNotFound:
            return "Plugin"
        case .midiBlockMissing, .midiTimingReferenceStale, .invalidMIDIData:
            return "MIDI"
        case .memoryPressure, .allocationLimitReached, .resourcePoolExhausted:
            return "Resource"
        case .operationCancelled, .operationTimedOut, .staleOperation:
            return "Operation"
        }
    }
}

// MARK: - Error Extension Helpers

extension AudioEngineError {
    /// Create appropriate context dictionary for error tracking
    var context: [String: String] {
        var ctx: [String: String] = [:]
        
        switch self {
        case .formatMismatch(let expected, let actual):
            ctx["expected"] = String(Int(expected))
            ctx["actual"] = String(Int(actual))
        case .trackNotFound(let trackId), .trackNodeMissing(let trackId),
             .invalidTrackState(let trackId, _), .midiBlockMissing(let trackId):
            ctx["trackId"] = trackId.uuidString
        case .audioFileNotFound(let path), .audioFileInvalid(let path, _),
             .audioFileEmpty(let path), .audioFileTooLarge(let path, _):
            ctx["file"] = URL(fileURLWithPath: path).lastPathComponent
        case .pluginNotFound(let slot):
            ctx["slot"] = String(slot)
        case .operationTimedOut(let operation, let timeout):
            ctx["operation"] = operation
            ctx["timeout"] = String(timeout)
        default:
            break
        }
        
        return ctx
    }
    
    /// Record this error to the error tracker
    func record() {
        Task { @MainActor in
            AudioEngineErrorTracker.shared.recordError(
                severity: severity,
                component: component,
                message: errorDescription ?? description,
                context: context
            )
        }
    }
}
