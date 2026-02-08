//
//  AudioGraphManager.swift
//  Stori
//
//  Manages audio graph mutations and node connections.
//  Extracted from AudioEngine.swift for better maintainability.
//

import Foundation
@preconcurrency import AVFoundation
import Observation

/// Manages audio graph mutations with tiered performance characteristics
@Observable
@MainActor
final class AudioGraphManager {
    
    // MARK: - Types
    
    /// Graph mutation types with different performance characteristics
    enum MutationType {
        /// Structural: Adding/removing nodes globally - requires full stop, reset, and restart
        /// Use for: add/remove tracks, device changes, catastrophic recovery
        case structural
        
        /// Connection: Reconnecting existing nodes - requires pause/resume only
        /// Use for: routing changes, toggling plugin bypass, bus send changes
        case connection
        
        /// Hot-swap: Adding/removing nodes on a single track - minimal disruption
        /// Use for: plugin insertion/removal on a specific track
        /// Only resets the affected track's instruments, not all tracks
        case hotSwap(trackId: UUID)
    }
    
    /// Pending mutation for coalescing
    private struct PendingMutation {
        let type: MutationType
        let work: () -> Void  // Non-throwing wrapper
        let timestamp: Date
        let targetKey: String
        
        var isStale: Bool {
            // Access the static property from MainActor context
            Date().timeIntervalSince(timestamp) > 10.0  // 10 seconds staleness threshold
        }
    }
    
    // MARK: - State
    
    /// Flag indicating if a graph mutation is currently in progress
    @ObservationIgnored
    private var _isGraphMutationInProgress = false
    
    /// Public accessor for mutation in progress state
    var isGraphMutationInProgress: Bool {
        _isGraphMutationInProgress
    }
    
    /// Graph generation counter - incremented on structural changes
    @ObservationIgnored
    private(set) var graphGeneration: Int = 0
    
    // MARK: - Rate Limiting & Coalescing
    
    /// Timestamps of recent mutations for rate limiting
    @ObservationIgnored
    private var recentMutationTimestamps: [Date] = []
    
    /// Maximum mutations allowed per second (prevents rebuild storms)
    private static let maxMutationsPerSecond = 10
    
    /// Time window for rate limiting (seconds)
    private static let rateLimitWindow: TimeInterval = 1.0
    
    /// Batch mode: temporarily suspends rate limiting for bulk operations
    @ObservationIgnored
    private var isBatchMode: Bool = false
    
    /// Pending mutations with target-based coalescing
    @ObservationIgnored
    private var pendingMutations: [String: PendingMutation] = [:]
    
    /// Timer for flushing coalesced mutations
    @ObservationIgnored
    private var flushTimer: Timer?
    
    /// Flush delay for mutation coalescing (milliseconds)
    private static let coalescingDelayMs: TimeInterval = 0.050 // 50ms - one buffer period at 512 samples / 48kHz
    
    /// Maximum staleness for mutations (discard if older than this)
    private static let mutationStalenessThreshold: TimeInterval = 0.500 // 500ms
    
    // MARK: - Dependencies (set by AudioEngine)
    
    @ObservationIgnored
    var engine: AVAudioEngine!
    
    @ObservationIgnored
    var getTrackNodes: (() -> [UUID: TrackAudioNode])?
    
    @ObservationIgnored
    var getCurrentProject: (() -> AudioProject?)?
    
    @ObservationIgnored
    var midiPlaybackEngine: MIDIPlaybackEngine?
    
    @ObservationIgnored
    var transportController: TransportController?
    
    @ObservationIgnored
    var installedMetronome: MetronomeEngine?
    
    @ObservationIgnored
    var mixer: AVAudioMixerNode!
    
    @ObservationIgnored
    var getTransportState: (() -> TransportState)?
    
    @ObservationIgnored
    var getCurrentPosition: (() -> PlaybackPosition)?
    
    @ObservationIgnored
    var setGraphReady: ((Bool) -> Void)?
    
    @ObservationIgnored
    var onPlayFromBeat: ((Double) -> Void)?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public API
    
    /// Performs a structural graph mutation (adding/removing nodes globally)
    func modifyGraphSafely(_ work: @escaping () throws -> Void) rethrows {
        try modifyGraph(.structural, work)
    }
    
    /// Performs a connection-only graph mutation (reconnecting existing nodes)
    func modifyGraphConnections(_ work: @escaping () throws -> Void) rethrows {
        try modifyGraph(.connection, work)
    }
    
    /// Performs a track-scoped hot-swap mutation (adding/removing nodes on one track)
    func modifyGraphForTrack(_ trackId: UUID, _ work: @escaping () throws -> Void) rethrows {
        try modifyGraph(.hotSwap(trackId: trackId), work)
    }
    
    /// Performs multiple graph mutations in batch mode (suspends rate limiting).
    /// Use this for bulk operations like project load, multi-track import, etc.
    /// The Logic Pro approach: batch legitimate bulk operations, rate-limit user spam.
    ///
    /// ARCHITECTURE: Sets _isGraphMutationInProgress so nested modifyGraph calls
    /// (from rebuildTrackGraphInternal etc.) hit the reentrancy handler and run
    /// work directly on the running engine. This avoids both:
    ///   - engine.pause() deadlock (hot-swap mutation)
    ///   - engine.reset() corrupting freshly attached nodes (structural mutation)
    /// AVAudioEngine supports connect/disconnect on a running engine; during project
    /// load there's no active playback so transient disconnects are harmless.
    func performBatchOperation(_ work: @escaping () throws -> Void) rethrows {
        let wasBatchMode = isBatchMode
        let wasInProgress = _isGraphMutationInProgress
        isBatchMode = true
        _isGraphMutationInProgress = true
        defer {
            _isGraphMutationInProgress = wasInProgress
            isBatchMode = wasBatchMode
            // Clear rate limit history after batch to prevent spillover
            recentMutationTimestamps.removeAll()
        }
        
        try work()
    }
    
    /// Check if generation is still valid after an await point
    func isGraphGenerationValid(_ capturedGeneration: Int) -> Bool {
        return capturedGeneration == graphGeneration
    }
    
    // MARK: - Private Implementation
    
    /// Core graph mutation implementation with tiered behavior and coalescing
    private func modifyGraph(_ type: MutationType, _ work: @escaping () throws -> Void) rethrows {
        // REENTRANCY HANDLING: If already in a mutation, just run the work directly
        if _isGraphMutationInProgress {
            try work()
            return
        }
        
        // COALESCING: For rapid mutations on same target, queue only the latest
        let targetKey = mutationTargetKey(for: type)
        
        // Check if we should coalesce this mutation
        if shouldCoalesceMutation(type: type, targetKey: targetKey) {
            // Wrap work in a non-throwing closure that logs errors
            // This allows us to store it without @escaping in the function signature
            let mutation = PendingMutation(
                type: type,
                work: {
                    do {
                        try work()
                    } catch {
                        AppLogger.shared.error(
                            "AudioGraphManager: Error in coalesced mutation: \(error)",
                            category: .audio
                        )
                    }
                },
                timestamp: Date(),
                targetKey: targetKey
            )
            
            // Replace any existing mutation for same target (coalescing)
            pendingMutations[targetKey] = mutation
            
            // Schedule flush if not already scheduled
            scheduleFlush()
            return
        }
        
        // RATE LIMITING: Prevent rebuild storms for immediate execution
        if shouldRateLimitMutation(type: type) {
            let recentCount = recentMutationTimestamps.count
            AppLogger.shared.warning(
                "AudioGraphManager: Rate limit exceeded (\(recentCount) mutations in last \(Self.rateLimitWindow)s), rejecting mutation",
                category: .audio
            )
            
            AudioEngineErrorTracker.shared.recordError(
                severity: .warning,
                component: "AudioGraphManager",
                message: "Graph mutation rate limit exceeded",
                context: [
                    "type": String(describing: type),
                    "recentCount": String(recentCount)
                ]
            )
            
            return
        }
        
        // Execute immediately
        try executeGraphMutation(type: type, work: work)
    }
    
    // MARK: - Rate Limiting Helpers
    
    /// Generate a unique target key for mutation coalescing
    private func mutationTargetKey(for type: MutationType) -> String {
        switch type {
        case .structural:
            return "structural-global"
        case .connection:
            return "connection-global"
        case .hotSwap(let trackId):
            return "hotswap-\(trackId.uuidString)"
        }
    }
    
    /// Check if mutation should be coalesced (queued and merged with existing)
    private func shouldCoalesceMutation(type: MutationType, targetKey: String) -> Bool {
        // Don't coalesce in batch mode (bulk operations like project load)
        if isBatchMode {
            return false
        }
        
        // Don't coalesce structural mutations - always execute immediately
        if case .structural = type {
            return false
        }
        
        // Coalesce connection and hot-swap mutations
        // This prevents rapid UI spam from causing audio glitches
        return true
    }
    
    /// Schedule a flush of pending coalesced mutations
    private func scheduleFlush() {
        // Invalidate existing timer
        flushTimer?.invalidate()
        
        // Schedule new timer on main thread
        flushTimer = Timer.scheduledTimer(withTimeInterval: Self.coalescingDelayMs, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.flushPendingMutations()
            }
        }
    }
    
    /// Flush all pending coalesced mutations immediately (public for testing)
    @MainActor
    func flushPendingMutations() {
        let mutations = pendingMutations.values.sorted { $0.timestamp < $1.timestamp }
        pendingMutations.removeAll()
        
        var executedCount = 0
        var discardedStale = 0
        
        for mutation in mutations {
            // Discard stale mutations (older than 500ms)
            if mutation.isStale {
                AppLogger.shared.warning(
                    "AudioGraphManager: Discarding stale mutation for target '\(mutation.targetKey)' (age: \(String(format: "%.0f", Date().timeIntervalSince(mutation.timestamp) * 1000))ms)",
                    category: .audio
                )
                discardedStale += 1
                continue
            }
            
            // Execute mutation (work is non-throwing wrapper)
            executeGraphMutationNonThrowing(type: mutation.type, work: mutation.work)
            executedCount += 1
        }
        
        if discardedStale > 0 {
            AppLogger.shared.info(
                "AudioGraphManager: Flush complete - executed: \(executedCount), discarded stale: \(discardedStale)",
                category: .audio
            )
        }
    }
    
    /// Execute a graph mutation immediately (core implementation)
    private func executeGraphMutation(type: MutationType, work: () throws -> Void) rethrows {
        // Record mutation timestamp
        recordMutationTimestamp()
        
        _isGraphMutationInProgress = true
        defer {
            _isGraphMutationInProgress = false
            // CENTRALIZED: Always reconnect metronome after any graph mutation
            installedMetronome?.reconnectNodes(dawMixer: mixer)
        }
        
        let wasRunning = engine.isRunning
        let wasPlaying = getTransportState?().isPlaying ?? false
        
        // CRITICAL: Capture position BEFORE stopping engine to compensate for drift
        let savedBeatPosition = getCurrentPosition?().beats ?? 0.0
        let mutationStartTime = CACurrentMediaTime()
        
        // Gate playback during mutation
        setGraphReady?(false)
        
        switch type {
        case .structural:
            try performStructuralMutation(
                work: work,
                wasRunning: wasRunning,
                wasPlaying: wasPlaying,
                savedBeatPosition: savedBeatPosition,
                mutationStartTime: mutationStartTime
            )
            
        case .connection:
            try performConnectionMutation(
                work: work,
                wasRunning: wasRunning
            )
            
        case .hotSwap(let affectedTrackId):
            try performHotSwapMutation(
                trackId: affectedTrackId,
                work: work,
                wasRunning: wasRunning,
                wasPlaying: wasPlaying,
                savedBeatPosition: savedBeatPosition,
                mutationStartTime: mutationStartTime
            )
        }
    }
    
    /// Execute a graph mutation with non-throwing work (for coalesced mutations)
    private func executeGraphMutationNonThrowing(type: MutationType, work: () -> Void) {
        // Record mutation timestamp
        recordMutationTimestamp()
        
        _isGraphMutationInProgress = true
        defer {
            _isGraphMutationInProgress = false
            // CENTRALIZED: Always reconnect metronome after any graph mutation
            installedMetronome?.reconnectNodes(dawMixer: mixer)
        }
        
        let wasRunning = engine.isRunning
        let wasPlaying = getTransportState?().isPlaying ?? false
        
        // CRITICAL: Capture position BEFORE stopping engine to compensate for drift
        let savedBeatPosition = getCurrentPosition?().beats ?? 0.0
        let mutationStartTime = CACurrentMediaTime()
        
        // Gate playback during mutation
        setGraphReady?(false)
        
        switch type {
        case .structural:
            performStructuralMutationNonThrowing(
                work: work,
                wasRunning: wasRunning,
                wasPlaying: wasPlaying,
                savedBeatPosition: savedBeatPosition,
                mutationStartTime: mutationStartTime
            )
            
        case .connection:
            performConnectionMutationNonThrowing(
                work: work,
                wasRunning: wasRunning
            )
            
        case .hotSwap(let affectedTrackId):
            performHotSwapMutationNonThrowing(
                trackId: affectedTrackId,
                work: work,
                wasRunning: wasRunning,
                wasPlaying: wasPlaying,
                savedBeatPosition: savedBeatPosition,
                mutationStartTime: mutationStartTime
            )
        }
    }
    
    /// Check if mutation should be rate limited
    private func shouldRateLimitMutation(type: MutationType) -> Bool {
        // Don't rate limit in batch mode (bulk operations like project load)
        if isBatchMode {
            return false
        }
        
        // Don't rate limit connection-only mutations (very fast)
        if case .connection = type {
            return false
        }
        
        // Clean up old timestamps
        let cutoff = Date().addingTimeInterval(-Self.rateLimitWindow)
        recentMutationTimestamps.removeAll { $0 < cutoff }
        
        // Check if over limit
        return recentMutationTimestamps.count >= Self.maxMutationsPerSecond
    }
    
    /// Record a mutation timestamp for rate limiting
    private func recordMutationTimestamp() {
        recentMutationTimestamps.append(Date())
        
        // Keep only recent timestamps
        let cutoff = Date().addingTimeInterval(-Self.rateLimitWindow)
        recentMutationTimestamps.removeAll { $0 < cutoff }
    }
    
    // MARK: - Mutation Implementations
    
    /// Structural mutation: Full stop, reset, work, restart
    private func performStructuralMutation(
        work: () throws -> Void,
        wasRunning: Bool,
        wasPlaying: Bool,
        savedBeatPosition: Double,
        mutationStartTime: TimeInterval
    ) rethrows {
        let operationStart = CACurrentMediaTime()
        
        // Increment graph generation
        graphGeneration += 1
        
        transportController?.stopPositionTimer()
        
        if wasPlaying {
            midiPlaybackEngine?.stop()
        }
        
        if wasRunning {
            engine.stop()
            engine.reset()
            
            // Reset all samplers after engine.reset()
            if let trackNodes = getTrackNodes?() {
                for trackId in trackNodes.keys {
                    if let instrument = InstrumentManager.shared.getInstrument(for: trackId) {
                        instrument.fullRenderReset()
                    }
                }
            }
        }
        
        try work()
        
        // Only prepare/start if engine has nodes attached
        // AVFoundation requires at least one connection before prepare()
        guard !engine.attachedNodes.isEmpty else {
            setGraphReady?(true)
            transportController?.setupPositionTimer()
            return
        }
        
        engine.prepare()
        
        if wasRunning {
            do {
                try engine.start()
                installedMetronome?.preparePlayerNode()
            } catch {
                AppLogger.shared.error("Engine restart failed after structural mutation", category: .audio)
            }
        }
        
        setGraphReady?(true)
        
        if wasPlaying {
            // Compensate for mutation duration to prevent drift
            let mutationDuration = CACurrentMediaTime() - mutationStartTime
            let tempo = getCurrentProject?()?.tempo ?? 120.0
            let driftBeats = (tempo / 60.0) * mutationDuration
            let correctedBeat = savedBeatPosition + driftBeats
            onPlayFromBeat?(correctedBeat)
        }
        
        transportController?.setupPositionTimer()
        
        // Record performance
        let duration = (CACurrentMediaTime() - operationStart) * 1000
        AudioPerformanceMonitor.shared.recordTiming(
            operation: "StructuralMutation",
            startTime: operationStart,
            context: [
                "wasRunning": String(wasRunning),
                "wasPlaying": String(wasPlaying),
                "durationMs": String(format: "%.1f", duration)
            ]
        )
    }
    
    /// Connection mutation: Pause, work, resume
    private func performConnectionMutation(
        work: () throws -> Void,
        wasRunning: Bool
    ) rethrows {
        let operationStart = CACurrentMediaTime()
        
        if wasRunning {
            engine.pause()
        }
        
        try work()
        
        // Only prepare/start if engine has nodes attached
        // AVFoundation requires at least one connection before prepare()
        guard !engine.attachedNodes.isEmpty else {
            setGraphReady?(true)
            return
        }
        
        engine.prepare()
        
        if wasRunning {
            do {
                try engine.start()
            } catch {
                AppLogger.shared.error("Engine restart failed after connection mutation", category: .audio)
            }
        }
        
        setGraphReady?(true)
        // No need to reschedule audio for connection changes
        
        // Record performance
        let duration = (CACurrentMediaTime() - operationStart) * 1000
        AudioPerformanceMonitor.shared.recordTiming(
            operation: "ConnectionMutation",
            startTime: operationStart,
            context: ["durationMs": String(format: "%.1f", duration)]
        )
    }
    
    /// Hot-swap mutation: Pause, reset affected track only, work, resume
    private func performHotSwapMutation(
        trackId: UUID,
        work: () throws -> Void,
        wasRunning: Bool,
        wasPlaying: Bool,
        savedBeatPosition: Double,
        mutationStartTime: TimeInterval
    ) rethrows {
        let operationStart = CACurrentMediaTime()
        
        if wasRunning {
            engine.pause()
        }
        
        // Only reset the affected track's instrument (not all tracks!)
        if let instrument = InstrumentManager.shared.getInstrument(for: trackId) {
            instrument.fullRenderReset()
        }
        
        try work()
        
        // Only prepare/start if engine has nodes attached
        // AVFoundation requires at least one connection before prepare()
        guard !engine.attachedNodes.isEmpty else {
            setGraphReady?(true)
            return
        }
        
        engine.prepare()
        
        if wasRunning {
            do {
                try engine.start()
            } catch {
                AppLogger.shared.error("Engine restart failed after hot-swap mutation: \(error)", category: .audio)
            }
        }
        
        setGraphReady?(true)
        
        // If playing, only reschedule the affected track with drift compensation
        if wasPlaying,
           let trackNodes = getTrackNodes?(),
           let trackNode = trackNodes[trackId],
           let project = getCurrentProject?(),
           let track = project.tracks.first(where: { $0.id == trackId }) {
            
            let tempo = project.tempo
            let mutationDuration = CACurrentMediaTime() - mutationStartTime
            let driftBeats = (tempo / 60.0) * mutationDuration
            let correctedBeat = savedBeatPosition + driftBeats
            
            do {
                // BEATS-FIRST: Use scheduleFromBeat, conversion to seconds at TrackAudioNode boundary
                try trackNode.scheduleFromBeat(correctedBeat, audioRegions: track.regions, tempo: tempo)
                if !track.regions.isEmpty {
                    trackNode.play()
                }
            } catch {
                AppLogger.shared.error("Failed to reschedule track after hot-swap", category: .audio)
            }
        }
        
        // Record performance
        let duration = (CACurrentMediaTime() - operationStart) * 1000
        AudioPerformanceMonitor.shared.recordTiming(
            operation: "HotSwapMutation",
            startTime: operationStart,
            context: [
                "trackId": trackId.uuidString,
                "wasPlaying": String(wasPlaying),
                "durationMs": String(format: "%.1f", duration)
            ]
        )
    }
    
    // MARK: - Non-Throwing Mutation Implementations (for coalesced mutations)
    
    /// Structural mutation: Full stop, reset, work, restart (non-throwing)
    private func performStructuralMutationNonThrowing(
        work: () -> Void,
        wasRunning: Bool,
        wasPlaying: Bool,
        savedBeatPosition: Double,
        mutationStartTime: TimeInterval
    ) {
        let operationStart = CACurrentMediaTime()
        
        // Increment graph generation
        graphGeneration += 1
        
        transportController?.stopPositionTimer()
        
        if wasPlaying {
            midiPlaybackEngine?.stop()
        }
        
        if wasRunning {
            engine.stop()
            engine.reset()
            
            // Reset all samplers after engine.reset()
            if let trackNodes = getTrackNodes?() {
                for trackId in trackNodes.keys {
                    if let instrument = InstrumentManager.shared.getInstrument(for: trackId) {
                        instrument.fullRenderReset()
                    }
                }
            }
        }
        
        work()
        
        // Only prepare/start if engine has nodes attached
        guard !engine.attachedNodes.isEmpty else {
            setGraphReady?(true)
            transportController?.setupPositionTimer()
            return
        }
        
        engine.prepare()
        
        if wasRunning {
            do {
                try engine.start()
                installedMetronome?.preparePlayerNode()
            } catch {
                AppLogger.shared.error("Engine restart failed after structural mutation", category: .audio)
            }
        }
        
        setGraphReady?(true)
        
        if wasPlaying {
            // Compensate for mutation duration to prevent drift
            let mutationDuration = CACurrentMediaTime() - mutationStartTime
            let tempo = getCurrentProject?()?.tempo ?? 120.0
            let driftBeats = (tempo / 60.0) * mutationDuration
            let correctedBeat = savedBeatPosition + driftBeats
            onPlayFromBeat?(correctedBeat)
        }
        
        transportController?.setupPositionTimer()
        
        // Record performance
        let duration = (CACurrentMediaTime() - operationStart) * 1000
        AudioPerformanceMonitor.shared.recordTiming(
            operation: "StructuralMutation",
            startTime: operationStart,
            context: [
                "wasRunning": String(wasRunning),
                "wasPlaying": String(wasPlaying),
                "durationMs": String(format: "%.1f", duration)
            ]
        )
    }
    
    /// Connection mutation: Pause, work, resume (non-throwing)
    private func performConnectionMutationNonThrowing(
        work: () -> Void,
        wasRunning: Bool
    ) {
        let operationStart = CACurrentMediaTime()
        
        if wasRunning {
            engine.pause()
        }
        
        work()
        
        // Only prepare/start if engine has nodes attached
        guard !engine.attachedNodes.isEmpty else {
            setGraphReady?(true)
            return
        }
        
        engine.prepare()
        
        if wasRunning {
            do {
                try engine.start()
            } catch {
                AppLogger.shared.error("Engine restart failed after connection mutation", category: .audio)
            }
        }
        
        setGraphReady?(true)
        // No need to reschedule audio for connection changes
        
        // Record performance
        let duration = (CACurrentMediaTime() - operationStart) * 1000
        AudioPerformanceMonitor.shared.recordTiming(
            operation: "ConnectionMutation",
            startTime: operationStart,
            context: ["durationMs": String(format: "%.1f", duration)]
        )
    }
    
    /// Hot-swap mutation: Pause, reset affected track only, work, resume (non-throwing)
    private func performHotSwapMutationNonThrowing(
        trackId: UUID,
        work: () -> Void,
        wasRunning: Bool,
        wasPlaying: Bool,
        savedBeatPosition: Double,
        mutationStartTime: TimeInterval
    ) {
        let operationStart = CACurrentMediaTime()
        
        if wasRunning {
            engine.pause()
        }
        
        // Only reset the affected track's instrument (not all tracks!)
        if let instrument = InstrumentManager.shared.getInstrument(for: trackId) {
            instrument.fullRenderReset()
        }
        
        work()
        
        // Only prepare/start if engine has nodes attached
        guard !engine.attachedNodes.isEmpty else {
            setGraphReady?(true)
            return
        }
        
        engine.prepare()
        
        if wasRunning {
            do {
                try engine.start()
            } catch {
                AppLogger.shared.error("Engine restart failed after hot-swap mutation", category: .audio)
            }
        }
        
        setGraphReady?(true)
        
        // If playing, only reschedule the affected track with drift compensation
        if wasPlaying,
           let trackNodes = getTrackNodes?(),
           let trackNode = trackNodes[trackId],
           let project = getCurrentProject?(),
           let track = project.tracks.first(where: { $0.id == trackId }) {
            
            let tempo = project.tempo
            let mutationDuration = CACurrentMediaTime() - mutationStartTime
            let driftBeats = (tempo / 60.0) * mutationDuration
            let correctedBeat = savedBeatPosition + driftBeats
            
            do {
                // BEATS-FIRST: Use scheduleFromBeat, conversion to seconds at TrackAudioNode boundary
                try trackNode.scheduleFromBeat(correctedBeat, audioRegions: track.regions, tempo: tempo)
                if !track.regions.isEmpty {
                    trackNode.play()
                }
            } catch {
                AppLogger.shared.error("Failed to reschedule track after hot-swap", category: .audio)
            }
        }
        
        // Record performance
        let duration = (CACurrentMediaTime() - operationStart) * 1000
        AudioPerformanceMonitor.shared.recordTiming(
            operation: "HotSwapMutation",
            startTime: operationStart,
            context: [
                "trackId": trackId.uuidString,
                "wasPlaying": String(wasPlaying),
                "durationMs": String(format: "%.1f", duration)
            ]
        )
    }
    
    // MARK: - Cleanup
    
    nonisolated deinit {
        // Cancel pending flush timer to prevent retain cycle.
        flushTimer?.invalidate()
        flushTimer = nil
    }
}
