//
//  AudioEngine+Instruments.swift
//  Stori
//
//  Extension containing instrument and MIDI routing logic.
//  Separated from main AudioEngine.swift for better maintainability.
//
//  ARCHITECTURE:
//  - Track instrument management (load/unload)
//  - MIDI note routing
//  - Step sequencer MIDI callbacks
//  - Sampler creation and connection
//  - Instrument DSP state management
//

import Foundation
@preconcurrency import AVFoundation

// MARK: - Instruments Extension

extension AudioEngine {
    
    // MARK: - Instrument DSP State Management
    
    /// Reprimes all instruments after an engine reset (e.g., device sample rate change).
    /// Also reconnects samplers with the new graphFormat - essential when going from higher
    /// to lower sample rate (e.g., 48kHz Mac → 44.1kHz Bluetooth).
    func reprimeAllInstrumentsAfterResetInternal() {
        for (trackId, trackNode) in trackNodes {
            guard let instrument = InstrumentManager.shared.getInstrument(for: trackId),
                  let samplerEngine = instrument.samplerEngine else { continue }
            
            let sampler = samplerEngine.sampler
            let pluginChain = trackNode.pluginChain
            
            samplerEngine.fullRenderReset()
            
            if pluginChain.hasActivePlugins {
                pluginChain.updateFormat(graphFormat)
                pluginChain.rebuildChainConnections(engine: engine)
            }
            
            engine.disconnectNodeOutput(sampler)
            
            if pluginChain.hasActivePlugins {
                engine.connect(sampler, to: pluginChain.inputMixer, fromBus: 0, toBus: 0, format: graphFormat)
            } else {
                engine.connect(sampler, to: trackNode.eqNode, format: graphFormat)
            }
            
            try? sampler.auAudioUnit.allocateRenderResources()
        }
    }
    
    /// Reset DSP state for all active samplers after device change
    /// This ensures samplers work correctly when switching output devices (e.g., to Bluetooth speakers)
    func resetAllSamplerDSPStateInternal() {
        logDebug("Resetting all sampler DSP states after device change", category: "DEVICE")
        
        // Reset all track instruments that use samplers
        // Use fullRenderReset() to deallocate render resources and cached sample rate converters
        // This is critical when switching between devices with different sample rates
        for (trackId, _) in trackNodes {
            if let instrument = InstrumentManager.shared.getInstrument(for: trackId),
               let samplerEngine = instrument.samplerEngine {
                samplerEngine.fullRenderReset()
                logDebug("Full render reset for sampler on track \(trackId)", category: "DEVICE")
            }
        }
    }
    
    // MARK: - MIDI Instrument Creation
    
    /// Create instruments for MIDI tracks and connect them to plugin chains
    /// Called after plugin restoration to ensure samplers are routed through effects
    @MainActor
    func createAndConnectMIDIInstrumentsInternal(for project: AudioProject) async {
        
        // Ensure InstrumentManager has our engine reference
        InstrumentManager.shared.audioEngine = self
        
        // Also ensure projectManager is set (needed for getOrCreateInstrument)
        if InstrumentManager.shared.projectManager == nil {
            // Try to get projectManager from the environment
            // For now, we'll create instruments directly from track data
        }
        
        // BATCH MODE: Suspend rate limiting for bulk instrument creation
        // This allows importing 15+ track MIDI files without hitting rate limits
        performBatchGraphOperation {
            for track in project.tracks where track.isMIDITrack {
                
                // Get or create instrument for this MIDI track
                // Use track-based overload to avoid projectManager dependency
                if let instrument = InstrumentManager.shared.getOrCreateInstrument(for: track) {
                    
                    // Ensure sampler exists and is attached to engine
                    if instrument.samplerEngine?.sampler == nil {
                        if instrument.pendingSamplerSetup {
                            instrument.completeSamplerSetup(with: engine)
                        } else {
                            instrument.ensureSamplerExists(with: engine)
                        }
                    }
                    
                    // Attach sampler to engine if needed
                    if let sampler = instrument.samplerEngine?.sampler {
                        if sampler.engine == nil {
                            engine.attach(sampler)
                        }
                        // Use centralized rebuild for all connections
                        rebuildTrackGraphInternal(trackId: track.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Track Instrument Management
    
    /// Get the instrument for a track (delegates to InstrumentManager)
    func getTrackInstrumentInternal(for trackId: UUID) -> TrackInstrument? {
        return InstrumentManager.shared.getInstrument(for: trackId)
    }
    
    /// Load an AU instrument for a MIDI/Instrument track
    /// Uses serialized graph queue to prevent concurrent access crashes
    func loadTrackInstrumentInternal(trackId: UUID, descriptor: PluginDescriptor) async throws {
        // Check both category and auType since they should both indicate an instrument
        guard descriptor.category == .instrument || descriptor.auType == .aumu else {
            return
        }
        
        // Capture current graph generation to detect stale operations
        let capturedGeneration = graphGeneration
        
        // Step 1: Create or get existing TrackInstrument and load the AU
        // Use InstrumentManager as single source of truth for instruments
        let instrument: TrackInstrument
        if let existing = InstrumentManager.shared.getInstrument(for: trackId) {
            instrument = existing
        } else {
            instrument = TrackInstrument(type: .audioUnit, name: descriptor.name)
            // Register with InstrumentManager immediately
            InstrumentManager.shared.registerInstrument(instrument, for: trackId)
        }
        
        // Load the AU - this does the async instantiation internally
        // IMPORTANT: forStandalonePlayback: false - we attach to the main DAW engine, not a separate one
        try await instrument.loadAudioUnit(descriptor, forStandalonePlayback: false)
        
        // STATE CONSISTENCY CHECK: Verify graph wasn't rebuilt during await
        guard isGraphGenerationValid(capturedGeneration, context: "loadTrackInstrument(\(trackId))") else {
            throw AsyncOperationError.staleGraphGeneration
        }
        
        // Step 2: All graph mutations happen serialized
        modifyGraphSafely {
            // Double-check inside mutation (defensive)
            guard self.isGraphGenerationValid(capturedGeneration, context: "loadTrackInstrument-mutation") else {
                return
            }
            
            // Re-fetch trackNode to ensure we have current reference
            guard let trackNode = self.trackNodes[trackId] else {
                return
            }
            
            // Get the AU node from the instrument (now loaded)
            guard let auNode = instrument.audioUnitNode else {
                return
            }
            
            // Verify the track's pluginChain is realized (has mixers attached)
            // If not realized, we need to realize it for the AU instrument
            if !trackNode.pluginChain.isRealized {
                trackNode.pluginChain.realize()
            }
            
            // Attach AU node to engine if not already attached
            if auNode.engine == nil {
                self.engine.attach(auNode)
            }
            
            // Connect: AU Instrument → Track's plugin chain input
            // CRITICAL: Always use explicit bus 0→0 to prevent bus accumulation
            self.engine.connect(auNode, to: trackNode.pluginChain.inputMixer, fromBus: 0, toBus: 0, format: self.graphFormat)
        }
    }
    
    /// Remove/unload the instrument from a track
    func unloadTrackInstrumentInternal(trackId: UUID) {
        // Get instrument from InstrumentManager (single source of truth)
        guard let instrument = InstrumentManager.shared.getInstrument(for: trackId) else { return }
        
        // Disconnect and remove AU node
        if let auNode = instrument.audioUnitNode {
            engine.disconnectNodeInput(auNode)
            engine.disconnectNodeOutput(auNode)
            engine.detach(auNode)
        }
        
        // Also handle sampler nodes
        if let samplerNode = instrument.samplerEngine?.sampler {
            if samplerNode.engine != nil {
                engine.disconnectNodeInput(samplerNode)
                engine.disconnectNodeOutput(samplerNode)
                engine.detach(samplerNode)
            }
        }
        
        instrument.stop()
        
        // Unregister from InstrumentManager (removes from their dictionary)
        InstrumentManager.shared.unregisterInstrument(for: trackId)
    }
    
    /// Send MIDI note to a track's instrument
    func sendMIDINoteToTrackInternal(trackId: UUID, noteOn: Bool, pitch: UInt8, velocity: UInt8) {
        // Use InstrumentManager for MIDI routing (single source of truth)
        if noteOn {
            InstrumentManager.shared.noteOn(pitch: pitch, velocity: velocity, forTrack: trackId)
        } else {
            InstrumentManager.shared.noteOff(pitch: pitch, forTrack: trackId)
        }
    }
    
    // MARK: - Step Sequencer MIDI Routing
    
    /// Configure MIDI event callbacks for the step sequencer
    func configureSequencerMIDICallbacksInternal(_ sequencer: SequencerEngine) {
        // Handle individual MIDI events
        sequencer.onMIDIEvent = { [weak self] event in
            self?.handleSequencerMIDIEventInternal(event)
        }
        
        // Handle batch events (more efficient for routing multiple notes)
        sequencer.onMIDIEvents = { [weak self] events in
            self?.handleSequencerMIDIEventsInternal(events)
        }
    }
    
    /// Handle a single MIDI event from the step sequencer
    func handleSequencerMIDIEventInternal(_ event: SequencerMIDIEvent) {
        let routing = sequencerEngine.routing
        
        switch routing.mode {
        case .preview:
            // Preview mode - internal sampler handles playback
            // MIDI events are still generated but not routed
            break
            
        case .singleTrack:
            // Route to single target track
            if let trackId = routing.targetTrackId {
                sendSequencerEventToTrackInternal(event, trackId: trackId)
            }
            
        case .multiTrack:
            // Route based on per-lane configuration
            if let trackId = routing.perLaneRouting[event.laneId] ?? routing.targetTrackId {
                sendSequencerEventToTrackInternal(event, trackId: trackId)
            }
            
        case .external:
            // TODO: External MIDI device output
            break
        }
    }
    
    /// Handle batch MIDI events from the step sequencer
    func handleSequencerMIDIEventsInternal(_ events: [SequencerMIDIEvent]) {
        for event in events {
            handleSequencerMIDIEventInternal(event)
        }
    }
    
    /// Send a sequencer MIDI event to a track's instrument
    func sendSequencerEventToTrackInternal(_ event: SequencerMIDIEvent, trackId: UUID) {
        // Use InstrumentManager for MIDI routing (single source of truth)
        guard InstrumentManager.shared.getInstrument(for: trackId) != nil else {
            return
        }
        
        // Trigger note on (note off will be handled by duration)
        InstrumentManager.shared.noteOn(pitch: event.note, velocity: event.velocity, forTrack: trackId)
        
        // Schedule note off after duration
        // Duration is in beats, need to convert to seconds based on tempo
        let tempo = currentProject?.tempo ?? 120.0
        let beatsPerSecond = tempo / 60.0
        let durationSeconds = event.duration / beatsPerSecond
        
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(durationSeconds))
            InstrumentManager.shared.noteOff(pitch: event.note, forTrack: trackId)
        }
    }
    
    /// Get list of MIDI tracks available for sequencer routing
    func getMIDITracksForSequencerRoutingInternal() -> [(id: UUID, name: String)] {
        guard let project = currentProject else { return [] }
        
        var result: [(id: UUID, name: String)] = []
        for track in project.tracks {
            if track.trackType == .midi || track.trackType == .instrument {
                result.append((id: track.id, name: track.name))
            }
        }
        return result
    }
    
    /// Check if a track has an instrument loaded (for routing validation)
    func trackHasInstrumentInternal(_ trackId: UUID) -> Bool {
        return InstrumentManager.shared.getInstrument(for: trackId) != nil
    }
    
    // MARK: - GM Instrument Loading
    
    /// Load a GM SoundFont instrument for a MIDI/Instrument track
    func loadTrackGMInstrumentInternal(trackId: UUID, instrument gmInstrument: GMInstrument) async throws {
        // Use InstrumentManager as single source of truth for instruments
        let trackInstrument: TrackInstrument
        if let existing = InstrumentManager.shared.getInstrument(for: trackId) {
            // Clean up any existing AU node if switching from AU to sampler
            if let oldAuNode = existing.audioUnitNode {
                modifyGraphSafely {
                    self.engine.disconnectNodeInput(oldAuNode)
                    self.engine.disconnectNodeOutput(oldAuNode)
                    self.engine.detach(oldAuNode)
                }
            }
            // If it was a different type, we need to reconfigure
            if existing.type != .sampler {
                existing.changeType(to: .sampler, audioEngine: engine)
            }
            // Ensure sampler exists even if type didn't change
            existing.ensureSamplerExists(with: engine)
            trackInstrument = existing
        } else {
            // CRITICAL: Pass audioEngine so sampler is created attached to main DAW engine
            trackInstrument = TrackInstrument(
                type: .sampler,
                name: gmInstrument.name,
                gmInstrument: gmInstrument,
                audioEngine: engine
            )
            // Register with InstrumentManager immediately
            InstrumentManager.shared.registerInstrument(trackInstrument, for: trackId)
        }
        
        // Load the GM instrument into the sampler
        trackInstrument.loadGMInstrument(gmInstrument)
        
        // Attach sampler to engine if needed
        if let samplerEngine = trackInstrument.samplerEngine {
            let samplerNode = samplerEngine.sampler
            if samplerNode.engine == nil {
                engine.attach(samplerNode)
            }
        }
        
        // Use centralized rebuild for all connections
        // This handles sampler → pluginChain → downstream correctly
        rebuildTrackGraphInternal(trackId: trackId)
        
        // Mark the instrument as running since it's now connected to the DAW engine
        trackInstrument.markAsRunning()
    }
    
    // MARK: - Instrument Connection
    
    /// Reconnects a MIDI track's instrument (sampler/synth) to its proper destination.
    /// If the track has plugins, connects to pluginChain.inputMixer.
    /// If no plugins, connects directly to eqNode (lazy chain optimization).
    /// This is needed after project reload or when inserting plugins on existing MIDI tracks.
    func reconnectMIDIInstrumentToPluginChainInternal(trackId: UUID) {
        guard let trackNode = trackNodes[trackId] else {
            return
        }
        
        let pluginChain = trackNode.pluginChain
        let hasPlugins = pluginChain.hasActivePlugins
        
        // Determine the destination node based on whether plugins exist
        let destinationNode: AVAudioNode
        if hasPlugins {
            // Ensure chain is realized before connecting
            if !pluginChain.isRealized {
                pluginChain.realize()
            }
            destinationNode = pluginChain.inputMixer
        } else {
            // No plugins - connect directly to EQ
            destinationNode = trackNode.eqNode
        }
        
        // Try InstrumentManager first (for GM instruments created via UI)
        // Note: We're already on MainActor, so no need for MainActor.run
        if let trackInstrument = InstrumentManager.shared.getInstrument(for: trackId),
           let samplerEngine = trackInstrument.samplerEngine {
            let samplerNode = samplerEngine.sampler
            
            // Check if sampler is already connected to the correct destination
            let connections = self.engine.outputConnectionPoints(for: samplerNode, outputBus: 0)
            let alreadyConnected = connections.contains { $0.node === destinationNode }
            
            if alreadyConnected {
                return
            }
            
            modifyGraphSafely {
                if samplerNode.engine == nil {
                    self.engine.attach(samplerNode)
                }
                self.engine.disconnectNodeOutput(samplerNode)
                self.engine.connect(samplerNode, to: destinationNode, fromBus: 0, toBus: 0, format: self.graphFormat)
            }
            return
        }
        
        // Check for AU instruments via InstrumentManager
        if let trackInstrument = InstrumentManager.shared.getInstrument(for: trackId),
           let auNode = trackInstrument.audioUnitNode {
            
            let connections = self.engine.outputConnectionPoints(for: auNode, outputBus: 0)
            let alreadyConnected = connections.contains { $0.node === destinationNode }
            
            if alreadyConnected {
                return
            }
            
            modifyGraphSafely {
                if auNode.engine == nil {
                    self.engine.attach(auNode)
                }
                self.engine.disconnectNodeOutput(auNode)
                self.engine.connect(auNode, to: destinationNode, fromBus: 0, toBus: 0, format: self.graphFormat)
            }
            return
        }
    }
    
    // MARK: - Sampler Creation
    
    /// Create a sampler instrument attached to the DAW's audio engine
    /// This ensures the sampler is part of the main audio graph and can be routed through plugin chains
    /// - Parameters:
    ///   - trackId: The track this sampler belongs to
    ///   - connectToPluginChain: If true, connects sampler output to the track's plugin chain input
    /// - Returns: A SamplerEngine attached to the main audio engine
    func createSamplerForTrackInternal(_ trackId: UUID, connectToPluginChain: Bool = true) -> SamplerEngine {
        // Create sampler attached to our engine (NOT connected to mainMixerNode)
        let samplerEngine = SamplerEngine(attachTo: engine, connectToMixer: false)
        
        // Wrap graph modifications in modifyGraphSafely for thread safety
        modifyGraphSafely {
            // If requested, wire the sampler to the track's signal path
            if connectToPluginChain, let trackNode = self.trackNodes[trackId] {
                let pluginChain = trackNode.pluginChain
                
                // Use lazy chain: connect to inputMixer only if plugins exist, otherwise to EQ directly
                if pluginChain.hasActivePlugins {
                    if !pluginChain.isRealized {
                        pluginChain.realize()
                    }
                    self.engine.connect(samplerEngine.sampler, to: pluginChain.inputMixer, fromBus: 0, toBus: 0, format: self.graphFormat)
                } else {
                    // No plugins - connect directly to EQ
                    self.engine.connect(samplerEngine.sampler, to: trackNode.eqNode, fromBus: 0, toBus: 0, format: self.graphFormat)
                }
            } else if !connectToPluginChain {
                // Connect directly to main mixer (standalone mode)
                self.engine.connect(samplerEngine.sampler, to: self.engine.mainMixerNode, format: nil)
            } else {
                // Track node doesn't exist yet - connect to main mixer as fallback
                self.engine.connect(samplerEngine.sampler, to: self.engine.mainMixerNode, format: nil)
            }
        }
        
        return samplerEngine
    }
}
