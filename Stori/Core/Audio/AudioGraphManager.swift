//
//  AudioGraphManager.swift
//  Stori
//
//  Manages audio graph mutations and node connections.
//  Extracted from AudioEngine.swift for better maintainability.
//

import Foundation
import AVFoundation
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
    func modifyGraphSafely(_ work: () throws -> Void) rethrows {
        try modifyGraph(.structural, work)
    }
    
    /// Performs a connection-only graph mutation (reconnecting existing nodes)
    func modifyGraphConnections(_ work: () throws -> Void) rethrows {
        try modifyGraph(.connection, work)
    }
    
    /// Performs a track-scoped hot-swap mutation (adding/removing nodes on one track)
    func modifyGraphForTrack(_ trackId: UUID, _ work: () throws -> Void) rethrows {
        try modifyGraph(.hotSwap(trackId: trackId), work)
    }
    
    /// Check if generation is still valid after an await point
    func isGraphGenerationValid(_ capturedGeneration: Int) -> Bool {
        return capturedGeneration == graphGeneration
    }
    
    // MARK: - Private Implementation
    
    /// Core graph mutation implementation with tiered behavior
    private func modifyGraph(_ type: MutationType, _ work: () throws -> Void) rethrows {
        // REENTRANCY HANDLING: If already in a mutation, just run the work directly
        if _isGraphMutationInProgress {
            try work()
            return
        }
        
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
    
    /// Structural mutation: Full stop, reset, work, restart
    private func performStructuralMutation(
        work: () throws -> Void,
        wasRunning: Bool,
        wasPlaying: Bool,
        savedBeatPosition: Double,
        mutationStartTime: TimeInterval
    ) rethrows {
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
    }
    
    /// Connection mutation: Pause, work, resume
    private func performConnectionMutation(
        work: () throws -> Void,
        wasRunning: Bool
    ) rethrows {
        if wasRunning {
            engine.pause()
        }
        
        try work()
        
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
        if wasRunning {
            engine.pause()
        }
        
        // Only reset the affected track's instrument (not all tracks!)
        if let instrument = InstrumentManager.shared.getInstrument(for: trackId) {
            instrument.fullRenderReset()
        }
        
        try work()
        
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
            let currentTimeSeconds = correctedBeat * (60.0 / tempo)
            
            do {
                try trackNode.scheduleFromPosition(currentTimeSeconds, audioRegions: track.regions, tempo: tempo)
                if !track.regions.isEmpty {
                    trackNode.play()
                }
            } catch {
                AppLogger.shared.error("Failed to reschedule track after hot-swap", category: .audio)
            }
        }
    }
}
