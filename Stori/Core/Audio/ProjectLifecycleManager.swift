//
//  ProjectLifecycleManager.swift
//  Stori
//
//  Manages project loading, unloading, and lifecycle state transitions.
//  Extracted from AudioEngine.swift for better maintainability.
//

import Foundation
import AVFoundation
import Observation

/// Manages project loading and unloading with explicit state machine
@Observable
@MainActor
final class ProjectLifecycleManager {
    
    // MARK: - Types
    
    /// State machine for project loading - explicit states replace scattered asyncAfter delays
    enum LoadingState: String {
        case idle
        case preparingEngine
        case settingUpTracks
        case restoringPlugins
        case connectingInstruments
        case validating
        case ready
        case failed
        
        var isLoading: Bool {
            switch self {
            case .preparingEngine, .settingUpTracks, .restoringPlugins, .connectingInstruments, .validating:
                return true
            case .idle, .ready, .failed:
                return false
            }
        }
        
        var progressPercentage: Double {
            switch self {
            case .idle: return 0
            case .preparingEngine: return 0.1
            case .settingUpTracks: return 0.3
            case .restoringPlugins: return 0.5
            case .connectingInstruments: return 0.7
            case .validating: return 0.9
            case .ready: return 1.0
            case .failed: return 0
            }
        }
        
        var userFacingDescription: String {
            switch self {
            case .idle: return "Ready"
            case .preparingEngine: return "Starting audio engine..."
            case .settingUpTracks: return "Setting up tracks..."
            case .restoringPlugins: return "Loading plugins..."
            case .connectingInstruments: return "Connecting instruments..."
            case .validating: return "Validating connections..."
            case .ready: return "Ready"
            case .failed: return "Load failed"
            }
        }
    }
    
    // MARK: - Properties
    
    /// Current project loading state (for debugging and UI feedback)
    private(set) var loadingState: LoadingState = .idle
    
    /// Generation counter for cancelling stale loads
    @ObservationIgnored
    private var projectLoadGeneration: Int = 0
    
    /// Current project (synchronized with AudioEngine)
    @ObservationIgnored
    var currentProject: AudioProject?
    
    // MARK: - Dependencies (set by AudioEngine)
    
    @ObservationIgnored
    var engine: AVAudioEngine!
    
    @ObservationIgnored
    var automationProcessor: AutomationProcessor!
    
    @ObservationIgnored
    var onSetupTracks: ((AudioProject) -> Void)?
    
    @ObservationIgnored
    var onSetupBuses: ((AudioProject) -> Void)?
    
    @ObservationIgnored
    var onUpdateAutomation: (() -> Void)?
    
    @ObservationIgnored
    var onRestorePlugins: (() async -> Void)?
    
    @ObservationIgnored
    var onConnectInstruments: ((AudioProject) async -> Void)?
    
    @ObservationIgnored
    var onValidateConnections: (() -> Void)?
    
    @ObservationIgnored
    var onStartEngine: (() -> Void)?
    
    @ObservationIgnored
    var onStopPlayback: (() -> Void)?
    
    @ObservationIgnored
    var onSetGraphStable: ((Bool) -> Void)?
    
    @ObservationIgnored
    var onSetGraphReady: ((Bool) -> Void)?
    
    @ObservationIgnored
    var onSetTransportStopped: (() -> Void)?
    
    @ObservationIgnored
    var onStopAutomationEngine: (() -> Void)?
    
    @ObservationIgnored
    var onStopPositionTimer: (() -> Void)?
    
    @ObservationIgnored
    var logDebug: ((String, String) -> Void)?
    
    @ObservationIgnored
    var onProjectLoaded: ((AudioProject) -> Void)?
    
    // MARK: - Initialization
    
    init() {}
    
    nonisolated deinit {}
    
    // MARK: - Public API
    
    /// Lightweight project data update - does NOT rebuild audio graph
    /// Use this for region edits (resize, move, loop) that don't require graph changes
    func updateProjectData(_ project: AudioProject) {
        currentProject = project
        logDebug?("📝 updateProjectData - lightweight update for '\(project.name)'", "PROJECT")
    }
    
    /// Synchronous entry point that kicks off async loading
    func loadProject(_ project: AudioProject) {
        logDebug?("⚡️ loadProject called for '\(project.name)' with \(project.tracks.count) tracks", "PROJECT")
        
        // Check if a load is already in progress
        if loadingState.isLoading {
            AppLogger.shared.warning("ProjectLifecycleManager: Load already in progress (state=\(loadingState)), cancelling previous load", category: .audio)
            AudioEngineErrorTracker.shared.recordError(
                severity: .warning,
                component: "ProjectLoad",
                message: "Previous project load cancelled by new load request",
                context: ["currentState": loadingState.rawValue]
            )
        }
        
        // Mark graph as unstable during rebuild
        onSetGraphStable?(false)
        loadingState = .idle
        
        onSetTransportStopped?()
        onStopPlayback?()
        currentProject = project
        
        // Increment generation to invalidate any pending async operations
        projectLoadGeneration += 1
        let thisGeneration = projectLoadGeneration
        logDebug?("Project generation: \(thisGeneration)", "PROJECT")
        
        // Stop all background timers SYNCHRONOUSLY before the async Task below.
        // Without this, background queue handlers can access freed TrackAudioNodes
        // after clearAllTracks() runs in loadProjectAsync().
        automationProcessor?.clearAll()
        onStopAutomationEngine?()
        onStopPositionTimer?()
        
        // Launch async loading with proper state machine
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadProjectAsync(project, generation: thisGeneration)
        }
    }
    
    // MARK: - Private Implementation
    
    /// Async project loading with explicit state machine (no asyncAfter delays)
    /// RAII Pattern: isGraphStable is always restored on exit via defer
    @MainActor
    private func loadProjectAsync(_ project: AudioProject, generation: Int) async {
        let loadStartTime = CACurrentMediaTime()
        
        // RAII: Ensure isGraphStable is restored even on early returns
        var loadSucceeded = false
        defer {
            let loadDuration = (CACurrentMediaTime() - loadStartTime) * 1000
            
            if !loadSucceeded {
                // Load was cancelled or failed - restore stable state to allow retry
                onSetGraphStable?(true)
                onSetGraphReady?(true)
                logDebug?("⚠️ Project load did not complete - restoring stable state", "PROJECT")
                
                // Record performance of failed load
                AudioPerformanceMonitor.shared.recordTiming(
                    operation: "ProjectLoad",
                    startTime: loadStartTime,
                    context: [
                        "success": "false",
                        "state": loadingState.rawValue,
                        "tracks": String(project.tracks.count)
                    ]
                )
            } else {
                // Record successful load timing
                AudioPerformanceMonitor.shared.recordTiming(
                    operation: "ProjectLoad",
                    startTime: loadStartTime,
                    context: [
                        "success": "true",
                        "tracks": String(project.tracks.count),
                        "durationMs": String(format: "%.1f", loadDuration)
                    ]
                )
            }
        }
        
        // STATE 1: Preparing Engine
        loadingState = .preparingEngine
        logDebug?("State: \(loadingState.rawValue)", "PROJECT")
        
        // Ensure engine is running
        if engine?.isRunning == false {
            onStartEngine?()
            engine?.prepare()
        }
        
        // Verify engine is ready (poll briefly if needed, but no arbitrary delay)
        var engineAttempts = 0
        while engine?.isRunning == false && engineAttempts < 10 {
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms per attempt, max 200ms
            engineAttempts += 1
        }
        
        guard engine?.isRunning == true else {
            loadingState = .failed
            let errorMsg = "Project load failed: Engine could not start after \(engineAttempts) attempts"
            AppLogger.shared.error(errorMsg, category: .audio)
            
            AudioEngineErrorTracker.shared.recordError(
                severity: .critical,
                component: "ProjectLoad",
                message: errorMsg,
                context: ["attempts": String(engineAttempts), "projectName": project.name]
            )
            
            return  // defer will restore stable state
        }
        
        // Check generation is still valid
        guard generation == projectLoadGeneration else {
            logDebug?("Project load cancelled (generation mismatch)", "PROJECT")
            return  // defer will restore stable state
        }
        
        // STATE 2: Setting Up Tracks
        loadingState = .settingUpTracks
        logDebug?("State: \(loadingState.rawValue)", "PROJECT")
        
        onSetupTracks?(project)
        onSetupBuses?(project)
        onUpdateAutomation?()
        
        guard generation == projectLoadGeneration else { return }
        
        // STATE 3: Restoring Plugins
        loadingState = .restoringPlugins
        logDebug?("State: \(loadingState.rawValue)", "PROJECT")
        
        await onRestorePlugins?()
        
        guard generation == projectLoadGeneration else { return }
        
        // STATE 4: Connecting MIDI Instruments
        loadingState = .connectingInstruments
        logDebug?("State: \(loadingState.rawValue)", "PROJECT")
        
        await onConnectInstruments?(project)
        
        guard generation == projectLoadGeneration else { return }
        
        // STATE 5: Validating
        loadingState = .validating
        logDebug?("State: \(loadingState.rawValue)", "PROJECT")
        
        onValidateConnections?()
        
        // STATE 6: Ready - Mark success before setting stable
        loadSucceeded = true
        loadingState = .ready
        onSetGraphStable?(true)
        onSetGraphReady?(true)
        
        logDebug?("✅ State: \(loadingState.rawValue) - Graph is stable", "PROJECT")
        
        // Record successful load
        AudioEngineErrorTracker.shared.recordError(
            severity: .info,
            component: "ProjectLoad",
            message: "Project '\(project.name)' loaded successfully",
            context: [
                "tracks": String(project.tracks.count),
                "duration": String(format: "%.2fs", Date().timeIntervalSince(currentProject?.createdAt ?? Date()))
            ]
        )
        
        // Notify that project finished loading
        onProjectLoaded?(project)
    }
    
    // MARK: - Cleanup
}
