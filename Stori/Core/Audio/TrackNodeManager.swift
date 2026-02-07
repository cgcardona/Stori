//
//  TrackNodeManager.swift
//  Stori
//
//  Manages track audio node lifecycle: creation, destruction, and access.
//  Extracted from AudioEngine.swift for better maintainability.
//
//  ARCHITECTURE:
//  - Owns the trackNodes dictionary (single source of truth)
//  - Handles node creation and attachment to AVAudioEngine
//  - Coordinates with rebuildTrackGraph for connections (not done here)
//  - Coordinates with MixerController for state reset after setup
//

import Foundation
import AVFoundation

/// Manages track audio node lifecycle: creation, destruction, and access
@MainActor
final class TrackNodeManager {
    
    // MARK: - Track Nodes Storage (Single Source of Truth)
    
    /// Dictionary of track nodes keyed by track ID
    private var trackNodes: [UUID: TrackAudioNode] = [:]
    
    // MARK: - Debug Logging
    
    /// Uses centralized debug config (see AudioDebugConfig)
    private var debugAudioFlow: Bool { AudioDebugConfig.logAudioFlow }
    
    /// Debug logging with autoclosure to prevent string allocation when disabled
    private func logDebug(_ message: @autoclosure () -> String, category: String = "TRACK") {
        guard debugAudioFlow else { return }
        AppLogger.shared.debug("[\(category)] \(message())", category: .audio)
    }
    
    // MARK: - Dependencies (set by AudioEngine)
    
    /// The AVAudioEngine to attach nodes to
    @ObservationIgnored
    var engine: AVAudioEngine!
    
    /// The audio format for the graph
    @ObservationIgnored
    var getGraphFormat: (() -> AVAudioFormat?)?
    
    /// Callback to ensure the audio engine is running
    @ObservationIgnored
    var onEnsureEngineRunning: (() -> Void)?
    
    /// Callback to rebuild track graph connections after node creation
    @ObservationIgnored
    var onRebuildTrackGraph: ((UUID) -> Void)?
    
    /// Callback to safely disconnect a track node
    @ObservationIgnored
    var onSafeDisconnectTrackNode: ((TrackAudioNode) -> Void)?
    
    /// Callback to load an audio region into a track node
    @ObservationIgnored
    var onLoadAudioRegion: ((AudioRegion, TrackAudioNode) -> Void)?
    
    /// Callback to perform batch graph operations (suspends rate limiting)
    @ObservationIgnored
    var onPerformBatchOperation: ((@escaping () -> Void) -> Void)?
    
    /// Callback to update automation engine's cached track IDs
    /// REAL-TIME SAFETY: Called when tracks change to avoid 120Hz array allocation
    @ObservationIgnored
    var onUpdateAutomationTrackCache: (() -> Void)?
    
    /// Reference to metronome for reconnection after setup
    @ObservationIgnored
    weak var installedMetronome: MetronomeEngine?
    
    /// Reference to main mixer for metronome reconnection
    @ObservationIgnored
    var mixer: AVAudioMixerNode!
    
    /// Reference to mixer controller for state reset
    @ObservationIgnored
    var mixerController: MixerController?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public API
    
    /// Get all track nodes (read-only access)
    func getAllTrackNodes() -> [UUID: TrackAudioNode] {
        return trackNodes
    }
    
    /// Get a specific track node by ID
    func getTrackNode(for trackId: UUID) -> TrackAudioNode? {
        return trackNodes[trackId]
    }
    
    /// Check if a track node exists
    func hasTrackNode(for trackId: UUID) -> Bool {
        return trackNodes[trackId] != nil
    }
    
    /// Set up all track nodes for a project
    /// This clears existing nodes and creates new ones for each track
    func setupTracksForProject(_ project: AudioProject) {
        // Clear existing track nodes
        clearAllTracks()
        
        // Create track nodes for each track
        for track in project.tracks {
            let trackNode = createTrackNode(for: track)
            trackNodes[track.id] = trackNode
        }
        
        // REAL-TIME SAFETY: Update automation engine's cached track IDs
        onUpdateAutomationTrackCache?()
        
        // BATCH MODE: Use batch operation for bulk track connection setup
        // This prevents rate limiting when loading projects with many tracks
        onPerformBatchOperation? { [weak self] in
            // Use centralized rebuild for all track connections
            // This handles both tracks with and without sends
            for track in project.tracks {
                self?.onRebuildTrackGraph?(track.id)
            }
        }
        
        // CRITICAL FIX: Reconnect metronome after track connections
        // AVAudioEngine can disconnect other mixer inputs when connecting to specific buses
        installedMetronome?.reconnectNodes(dawMixer: mixer)
        
        // ATOMIC OPERATION: Restore all track mixer states (mute/solo) from project data
        // This is atomic to prevent any window where mixer state is inconsistent
        mixerController?.atomicResetTrackStates(from: project.tracks)
    }
    
    /// Ensures a track node exists for the given track, creating it if needed
    /// This is useful when loading instruments immediately after track creation
    func ensureTrackNodeExists(for track: AudioTrack) {
        guard trackNodes[track.id] == nil else {
            return
        }
        
        // Create and attach nodes
        let trackNode = createTrackNode(for: track)
        trackNodes[track.id] = trackNode
        
        // REAL-TIME SAFETY: Update automation engine's cached track IDs
        onUpdateAutomationTrackCache?()
        
        // Use centralized rebuild for all connections
        onRebuildTrackGraph?(track.id)
    }
    
    /// Store a track node directly (used when AudioEngine creates nodes in updateCurrentProject)
    func storeTrackNode(_ trackNode: TrackAudioNode, for trackId: UUID) {
        trackNodes[trackId] = trackNode
        
        // REAL-TIME SAFETY: Update automation engine's cached track IDs
        onUpdateAutomationTrackCache?()
    }
    
    /// Remove a track node by ID
    func removeTrackNode(for trackId: UUID) {
        if let trackNode = trackNodes[trackId] {
            onSafeDisconnectTrackNode?(trackNode)
            trackNodes.removeValue(forKey: trackId)
            
            // REAL-TIME SAFETY: Update automation engine's cached track IDs
            onUpdateAutomationTrackCache?()
        }
    }
    
    /// Clear all track nodes
    func clearAllTracks() {
        // First, explicitly clean up each track node to remove taps safely
        for (_, trackNode) in trackNodes {
            onSafeDisconnectTrackNode?(trackNode)
        }
        
        // Clear the collections
        trackNodes.removeAll()
        mixerController?.clearSoloTracks()
        
        // REAL-TIME SAFETY: Update automation engine's cached track IDs
        onUpdateAutomationTrackCache?()
    }
    
    // MARK: - Node Creation
    
    /// Creates a track node and attaches all nodes to the engine.
    /// NOTE: This only attaches nodes - caller must call rebuildTrackGraph() after storing in trackNodes
    func createTrackNode(for track: AudioTrack) -> TrackAudioNode {
        let playerNode = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()  // [V2-PITCH/TEMPO]
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        
        // Create plugin chain for insert effects (8 slots)
        let pluginChain = PluginChain(id: UUID(), maxSlots: 8)
        
        // Ensure engine is running before attaching nodes
        if !engine.isRunning {
            onEnsureEngineRunning?()
            engine.prepare()  // Ensure audio graph is ready for node attachment
        }
        
        // Get graph format
        guard let graphFormat = getGraphFormat?() else {
            fatalError("TrackNodeManager: graphFormat is nil")
        }
        
        // Attach nodes to engine (NO CONNECTIONS - rebuildTrackGraph handles that)
        engine.attach(playerNode)
        engine.attach(timePitch)
        engine.attach(eqNode)
        engine.attach(volumeNode)
        engine.attach(panNode)
        
        // Install plugin chain into engine (attaches inputMixer/outputMixer, initial internal connection)
        pluginChain.install(in: engine, format: graphFormat)
        
        // Also connect playerNode → timePitch (this is track-internal, always needed for audio tracks)
        engine.connect(playerNode, to: timePitch, format: graphFormat)
        
        let trackNode = TrackAudioNode(
            id: track.id,
            playerNode: playerNode,
            volumeNode: volumeNode,
            panNode: panNode,
            eqNode: eqNode,
            pluginChain: pluginChain,
            timePitchUnit: timePitch,
            volume: track.mixerSettings.volume,
            pan: track.mixerSettings.pan,
            isMuted: track.mixerSettings.isMuted,
            isSolo: track.mixerSettings.isSolo
        )
        
        // Apply initial settings
        trackNode.setVolume(track.mixerSettings.volume)
        // Convert pan from 0-1 range (mixer) to -1 to +1 range (audio node)
        trackNode.setPan(track.mixerSettings.pan * 2 - 1)
        trackNode.setMuted(track.mixerSettings.isMuted)
        trackNode.setSolo(track.mixerSettings.isSolo)
        
        // [V2-PITCH/TEMPO] Initialize timePitch unit with defaults
        trackNode.timePitchUnit.rate = 1.0
        trackNode.timePitchUnit.overlap = 8.0
        
        // Load audio regions for this track
        for region in track.regions {
            onLoadAudioRegion?(region, trackNode)
        }
        
        return trackNode
    }
    
    // MARK: - Cleanup
    
    /// Explicit deinit to prevent Swift Concurrency task leak
    /// @MainActor classes can have implicit tasks from Swift Concurrency runtime
    /// that cause memory corruption during deallocation if not properly cleaned up
}
