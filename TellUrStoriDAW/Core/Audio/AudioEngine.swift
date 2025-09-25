//
//  AudioEngine.swift
//  TellUrStoriDAW
//
//  Core audio engine for real-time audio processing
//

import Foundation
import AVFoundation
import AVKit
import Combine

// MARK: - Audio Engine Manager
@MainActor
class AudioEngine: ObservableObject {
    
    // MARK: - Published Properties
    @Published var transportState: TransportState = .stopped
    @Published var currentPosition: PlaybackPosition = PlaybackPosition()
    @Published var isRecording: Bool = false
    @Published var audioLevels: [Float] = []
    @Published var isCycleEnabled: Bool = false
    @Published var cycleStartTime: TimeInterval = 0.0
    @Published var masterVolume: Double = 0.8  // Shared master volume state
    @Published var cycleEndTime: TimeInterval = 4.0
    
    // MARK: - Private Properties
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var trackNodes: [UUID: TrackAudioNode] = [:]
    private var busNodes: [UUID: BusAudioNode] = [:]
    private var startTime: TimeInterval = 0
    private var pausedTime: TimeInterval = 0
    private var soloTracks: Set<UUID> = []
    
    // MARK: - Recording Properties
    private var recordingFile: AVAudioFile?
    private var recordingStartTime: TimeInterval = 0
    private var recordingTrackId: UUID?
    
    // MARK: - Current Project
    @Published var currentProject: AudioProject?
    
    // MARK: - Timer for position updates
    private var positionTimer: Timer?
    private var transportFrozen: Bool = false
    
    // MARK: - Cycle Loop Constants
    private let cycleEpsilon: TimeInterval = 0.002 // ~2ms safety for floating-point drift
    private var lastCycleJumpTime: TimeInterval = 0 // Prevent rapid cycle re-triggering
    private let cycleCooldown: TimeInterval = 0.1 // 100ms cooldown between cycle jumps
    
    // MARK: - Initialization
    init() {
        setupAudioEngine()
        setupPositionTimer()
    }
    
    deinit {
        positionTimer?.invalidate()
        // Note: Cannot access @MainActor properties in deinit
        // The engine will be cleaned up automatically
    }
    
    // MARK: - Audio Engine Setup
    private func setupAudioEngine() {
        // Connect mixer to output with explicit device format
        engine.attach(mixer)
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(mixer, to: engine.outputNode, format: deviceFormat)
        print("🎯 MASTER SETUP: Using device format: \(deviceFormat)")
        
        // Set default master volume to match published property
        mixer.outputVolume = Float(masterVolume)
       
        // Start the engine
        startAudioEngine()
    }
    
    private func startAudioEngine() {
        guard !engine.isRunning else { 
            print("Audio engine already running")
            return 
        }
        
        do {
            // Ensure we have proper audio format
            let format = engine.outputNode.outputFormat(forBus: 0)
            print("Starting audio engine with format: \(format)")
            
            try engine.start()
            print("Audio engine started successfully")
            
            // Verify it's actually running
            if !engine.isRunning {
                print("Warning: Engine reports not running after start attempt")
            }
        } catch {
            print("Failed to start audio engine: \(error)")
            
            // Try to reset and start again
            engine.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                do {
                    try self.engine.start()
                    print("Audio engine started on retry")
                } catch {
                    print("Failed to start audio engine on retry: \(error)")
                }
            }
        }
    }
    
    // MARK: - Timer for Position Updates
    private func setupPositionTimer() {
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updatePosition()
            }
        }
    }
    
    private func updatePosition() {
        guard transportState.isPlaying, !transportFrozen else { 
            // print("⏸️ Not playing or transport frozen, skipping position update")
            return 
        }
        
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - startTime + pausedTime
        
        if let project = currentProject {
            currentPosition = PlaybackPosition(
                timeInterval: elapsed,
                tempo: project.tempo,
                timeSignature: project.timeSignature
            )
        }   
        
        // Position updates happen at 60fps for smooth playback tracking
        // Check for cycle loop
        checkCycleLoop()
        // Position timer update complete
    }
    
    // MARK: - Project Management
    func loadProject(_ project: AudioProject) {
        transportState = .stopped
        stopPlayback()
        currentProject = project
        
        // Ensure engine is running before setting up tracks
        startAudioEngine()
        
        // Wait a bit longer to ensure engine is fully ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Double-check engine is still running
            if self.engine.isRunning {
                self.setupTracksForProject(project)
                self.setupBusesForProject(project)
            } else {
                print("Engine not running, retrying...")
                self.startAudioEngine()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.setupTracksForProject(project)
                    self.setupBusesForProject(project)
                }
            }
        }
    }
    
    func updateCurrentProject(_ project: AudioProject) {
        // Update the project reference without stopping playback or rebuilding everything
        let oldProject = currentProject
        currentProject = project
        
        // Check for new tracks that need audio node setup
        if let oldProject = oldProject {
            let oldTrackIds = Set(oldProject.tracks.map { $0.id })
            let newTrackIds = Set(project.tracks.map { $0.id })
            let addedTrackIds = newTrackIds.subtracting(oldTrackIds)
            
            
            // Set up audio nodes for new tracks
            for trackId in addedTrackIds {
                if let newTrack = project.tracks.first(where: { $0.id == trackId }) {
                    print("🎵 Setting up audio node for new track: \(newTrack.name)")
                    let trackNode = createTrackNode(for: newTrack)
                    trackNodes[trackId] = trackNode
                }
            }
            
            // CRITICAL FIX: Check for new regions added to existing tracks
            for track in project.tracks {
                if let oldTrack = oldProject.tracks.first(where: { $0.id == track.id }),
                   let trackNode = trackNodes[track.id] {
                    
                    // Compare region counts to detect new regions
                    let oldRegionIds = Set(oldTrack.regions.map { $0.id })
                    let newRegionIds = Set(track.regions.map { $0.id })
                    let addedRegionIds = newRegionIds.subtracting(oldRegionIds)
                    
                    
                    // Load audio for new regions
                    for regionId in addedRegionIds {
                        if let newRegion = track.regions.first(where: { $0.id == regionId }) {
                            print("🎵 Loading new audio region: \(newRegion.audioFile.name) for track: \(track.name)")
                            loadAudioRegion(newRegion, trackNode: trackNode)
                        }
                    }
                    
                    // Handle removed regions (clear audio files that are no longer needed)
                    let removedRegionIds = oldRegionIds.subtracting(newRegionIds)
                    if !removedRegionIds.isEmpty {
                        print("🗑️ Removed \(removedRegionIds.count) regions from track: \(track.name)")
                        // Note: TrackAudioNode handles multiple regions, so we don't need to explicitly remove
                        // The next playback will only schedule the remaining regions
                    }
                    
                    // CRITICAL FIX: Check for moved regions (same ID but different position)
                    var hasRegionPositionChanges = false
                    for newRegion in track.regions {
                        if let oldRegion = oldTrack.regions.first(where: { $0.id == newRegion.id }) {
                            if abs(oldRegion.startTime - newRegion.startTime) > 0.001 { // 1ms tolerance
                                print("🔄 REGION MOVED: '\(newRegion.audioFile.name)' from \(String(format: "%.2f", oldRegion.startTime))s to \(String(format: "%.2f", newRegion.startTime))s")
                                hasRegionPositionChanges = true
                            }
                        }
                    }
                    
                    // If regions were moved, handle re-scheduling based on transport state
                    if hasRegionPositionChanges {
                        if transportState == .playing {
                            // Currently playing: Re-schedule immediately
                            print("🔄 RE-SCHEDULING: Track '\(track.name)' due to region position changes (PLAYING)")
                            trackNode.playerNode.stop()
                            
                            // Re-schedule from current position
                            let currentTime = currentPosition.timeInterval
                            do {
                                try trackNode.scheduleFromPosition(currentTime, audioRegions: track.regions)
                                if !trackNode.playerNode.isPlaying {
                                    trackNode.playerNode.play()
                                    print("✅ RE-SCHEDULED: Track '\(track.name)' playing from \(String(format: "%.2f", currentTime))s")
                                }
                            } catch {
                                print("❌ RE-SCHEDULE FAILED: Track '\(track.name)': \(error)")
                            }
                        } else {
                            // Currently stopped: Clear audio cache so next playback uses updated positions
                            print("🔄 CLEARING CACHE: Track '\(track.name)' due to region position changes (STOPPED)")
                            trackNode.playerNode.stop()
                            print("✅ CACHE CLEARED: Track '\(track.name)' ready for next playback with updated positions")
                        }
                    }
                }
            }
            
            // Clean up removed tracks
            let removedTrackIds = oldTrackIds.subtracting(newTrackIds)
            for trackId in removedTrackIds {
                if let trackNode = trackNodes[trackId] {
                    print("🗑️ Removing audio node for deleted track: \(trackId)")
                    // [BUGFIX] Safe node disconnection with existence checks
                    safeDisconnectTrackNode(trackNode)
                    trackNodes.removeValue(forKey: trackId)
                }
            }
            
            // Update solo state in case new tracks affect it
            updateSoloState()
        }
        
    }
    
    private func setupTracksForProject(_ project: AudioProject) {
        // Clear existing track nodes
        clearAllTracks()
        
        // Create track nodes for each track
        for track in project.tracks {
            let trackNode = createTrackNode(for: track)
            trackNodes[track.id] = trackNode
        }
        
        // Update solo state
        updateSoloState()
    }
    
    // [V2-ANALYSIS] Public access to track nodes for pitch/tempo adjustments
    func getTrackNode(for trackId: UUID) -> TrackAudioNode? {
        return trackNodes[trackId]
    }
    
    private func createTrackNode(for track: AudioTrack) -> TrackAudioNode {
        let playerNode = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()  // [V2-PITCH/TEMPO]
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        
        // Ensure engine is running before attaching nodes
        if !engine.isRunning {
            print("Warning: Engine not running, starting it now...")
            startAudioEngine()
            // Give it a moment to start
            Thread.sleep(forTimeInterval: 0.15)
            if !engine.isRunning {
                print("Error: Audio engine failed to start")
                return TrackAudioNode(
                    id: track.id,
                    playerNode: playerNode,
                    volumeNode: volumeNode,
                    panNode: panNode,
                    eqNode: eqNode,
                    volume: track.mixerSettings.volume,
                    pan: track.mixerSettings.pan,
                    isMuted: track.mixerSettings.isMuted,
                    isSolo: track.mixerSettings.isSolo
                )
            }
        }
        
        // Attach nodes to engine
        engine.attach(playerNode)
        engine.attach(timePitch)            // [V2-PITCH/TEMPO]
        engine.attach(eqNode)
        engine.attach(volumeNode)
        engine.attach(panNode)
        
        // Connect the audio chain: player -> timePitch -> EQ -> volume -> pan -> main mixer
        do {
            // ChatGPT Fix: Use format negotiation inside graph, device format only at boundaries
            let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
            print("🎯 TRACK SETUP: Using format negotiation (nil) inside graph, device format at boundary")
            print("   Device format: \(deviceFormat)")
            
            // Let AVAudioEngine negotiate formats inside the graph
            engine.connect(playerNode, to: timePitch, format: nil)        // [V2-PITCH/TEMPO]
            engine.connect(timePitch,  to: eqNode,    format: nil)        // [V2-PITCH/TEMPO]
            engine.connect(eqNode, to: volumeNode, format: nil)
            engine.connect(volumeNode, to: panNode, format: nil)
            
            // Only constrain the final hop to device format
            engine.connect(panNode, to: mixer, format: deviceFormat)
            print("Successfully created and connected track node with EQ for: \(track.name)")
        } catch {
            print("Failed to connect audio nodes: \(error)")
            // Return a basic track node without connections if connection fails
            return TrackAudioNode(
                id: track.id,
                playerNode: playerNode,
                volumeNode: volumeNode,
                panNode: panNode,
                eqNode: eqNode,
                volume: track.mixerSettings.volume,
                pan: track.mixerSettings.pan,
                isMuted: track.mixerSettings.isMuted,
                isSolo: track.mixerSettings.isSolo
            )
        }
        
        let trackNode = TrackAudioNode(
            id: track.id,
            playerNode: playerNode,
            volumeNode: volumeNode,
            panNode: panNode,
            eqNode: eqNode,
            volume: track.mixerSettings.volume,
            pan: track.mixerSettings.pan,
            isMuted: track.mixerSettings.isMuted,
            isSolo: track.mixerSettings.isSolo
        )
        
        // Apply initial settings
        trackNode.setVolume(track.mixerSettings.volume)
        trackNode.setPan(track.mixerSettings.pan)
        trackNode.setMuted(track.mixerSettings.isMuted)
        trackNode.setSolo(track.mixerSettings.isSolo)
        
        // [V2-PITCH/TEMPO] Initialize timePitch unit with defaults
        trackNode.timePitchUnit.rate = 1.0
        trackNode.timePitchUnit.overlap = 8.0
        
        // Load audio regions for this track
        for region in track.regions {
            loadAudioRegion(region, trackNode: trackNode)
        }
        
        return trackNode
    }
    
    private func clearAllTracks() {
        print("Clearing \(trackNodes.count) track nodes...")
        
        // First, explicitly clean up each track node to remove taps safely
        for (trackId, trackNode) in trackNodes {
            print("Cleaning up track node: \(trackId)")
            
            // [BUGFIX] Use safe disconnection method
            safeDisconnectTrackNode(trackNode)
            print("Successfully cleaned up track node: \(trackId)")
        }
        
        // Clear the collections
        trackNodes.removeAll()
        soloTracks.removeAll()
        print("All track nodes cleared")
    }
    
    // MARK: - Bus Management
    func setupBusesForProject(_ project: AudioProject) {
        // Clear existing bus nodes
        clearAllBuses()
        
        // Create bus nodes for each bus
        for bus in project.buses {
            let busNode = createBusNode(for: bus)
            busNodes[bus.id] = busNode
            
            // Setup effects for this bus
            for effect in bus.effects {
                busNode.addEffect(effect)
            }
        }
        
        print("🎛️ Set up \(project.buses.count) bus nodes")
        
        // Restore track sends after buses are set up
        restoreTrackSendsForProject(project)
    }
    
    private func createBusNode(for bus: MixerBus) -> BusAudioNode {
        let busNode = BusAudioNode(busId: bus.id)
        
        // Ensure engine is running before attaching nodes
        if !engine.isRunning {
            print("Warning: Engine not running for bus setup, starting it now...")
            startAudioEngine()
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Attach bus nodes to engine
        engine.attach(busNode.getInputNode())
        engine.attach(busNode.getOutputNode())
        
        // Connect bus output to main mixer with device format
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(busNode.getOutputNode(), to: mixer, format: deviceFormat)
        print("🎯 BUS SETUP: Connected bus output to mixer with device format: \(deviceFormat)")
        
        // Apply bus settings with defensive defaults for audibility
        busNode.inputGain = Float(bus.inputLevel)
        busNode.outputGain = Float(bus.outputLevel)
        busNode.isMuted = bus.isMuted
        busNode.isSolo = bus.isSolo
        
        // STEP 1: Force sane audible defaults while debugging reverb
        busNode.isMuted = false          // ensure return isn't killed by model defaults
        busNode.outputGain = 1.0         // louder than 0.75 while debugging audibility
        busNode.inputGain = 1.0          // keep the send bus hot
        print("🔊 BUS AUDIBILITY: Forced unmuted with input=1.0, output=1.0 for debugging")
        
        // STEP 2: Enable level monitoring to prove signal flow
        busNode.startLevelMonitoring()
        print("📊 BUS MONITORING: Level monitoring enabled for debugging")
        
        // Quick debug check after a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🔎 BUS LEVELS — in:\(busNode.inputLevel)  out:\(busNode.outputLevel)")
        }
        
        print("🎛️ Created bus node: \(bus.name)")
        return busNode
    }
    
    func addBus(_ bus: MixerBus) {
        guard busNodes[bus.id] == nil else { return }
        
        let busNode = createBusNode(for: bus)
        busNodes[bus.id] = busNode
        
        // Setup effects
        for effect in bus.effects {
            busNode.addEffect(effect)
        }
        
        // STEP 1: Force sane audible defaults while debugging reverb
        busNode.isMuted = false          // ensure return isn't killed by model defaults
        busNode.outputGain = 1.0         // louder than 0.75 while debugging audibility
        busNode.inputGain = 1.0          // keep the send bus hot
        print("🔊 BUS AUDIBILITY: Forced unmuted with input=1.0, output=1.0 for debugging")
        
        // STEP 2: Enable level monitoring to prove signal flow
        busNode.startLevelMonitoring()
        print("📊 BUS MONITORING: Level monitoring enabled for debugging")
        
        // Quick debug check after a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            print("🔎 BUS LEVELS — in:\(busNode.inputLevel)  out:\(busNode.outputLevel)")
        }
        
        // Wire the bus chain: input → effects → output
        rebuildBusChain(busNode)
    }
    
    func removeBus(withId busId: UUID) {
        guard let busNode = busNodes[busId] else { return }
        
        // Disconnect and detach bus nodes
        engine.disconnectNodeInput(busNode.getInputNode())
        engine.disconnectNodeInput(busNode.getOutputNode())
        engine.detach(busNode.getInputNode())
        engine.detach(busNode.getOutputNode())
        
        // Remove from collection
        busNodes.removeValue(forKey: busId)
        
        print("🗑️ Removed bus node: \(busId)")
    }
    
    func updateBusEffect(_ busId: UUID, effect: BusEffect) {
        print("🎵 AUDIO ENGINE: Updating bus effect - Bus: \(busId), Effect: \(effect.type)")
        guard let busNode = busNodes[busId] else { 
            print("❌ AUDIO ENGINE: Bus node not found for ID: \(busId)")
            return 
        }
        print("✅ AUDIO ENGINE: Found bus node, calling updateEffect...")
        busNode.updateEffect(effect)
        
        // Rebuild the bus chain after effect update
        rebuildBusChain(busNode)
    }
    
    func addEffectToBus(_ busId: UUID, effect: BusEffect) {
        guard let busNode = busNodes[busId] else { return }
        busNode.addEffect(effect)
        
        // Rebuild the bus chain after adding effect
        rebuildBusChain(busNode)
    }
    
    func removeEffectFromBus(_ busId: UUID, effectId: UUID) {
        guard let busNode = busNodes[busId] else { return }
        busNode.removeEffect(withId: effectId)
        
        // Rebuild the bus chain after removing effect
        rebuildBusChain(busNode)
    }
    
    // MARK: - Track Send Management
    private var trackSendIds: [String: UUID] = [:]  // Key: "trackId-busId" -> sendId
    
    // MARK: [BUGFIX] Safe Node Disconnection
    private func safeDisconnectTrackNode(_ trackNode: TrackAudioNode) {
        print("🛡️ SAFE DISCONNECT: Safely disconnecting track node...")
        
        // Check and disconnect each node only if it's actually connected
        let nodesToDisconnect: [(node: AVAudioNode, name: String)] = [
            (trackNode.panNode, "panNode"),
            (trackNode.volumeNode, "volumeNode"), 
            (trackNode.eqNode, "eqNode"),
            (trackNode.timePitchUnit, "timePitchUnit"),
            (trackNode.playerNode, "playerNode")
        ]
        
        for (node, name) in nodesToDisconnect {
            if engine.attachedNodes.contains(node) {
                do {
                    // Stop player nodes before disconnecting
                    if let playerNode = node as? AVAudioPlayerNode, playerNode.isPlaying {
                        playerNode.stop()
                    }
                    
                    engine.disconnectNodeInput(node)
                    engine.detach(node)
                    print("🛡️ SAFE DISCONNECT: Successfully disconnected \(name)")
                } catch {
                    print("⚠️ SAFE DISCONNECT: Failed to disconnect \(name): \(error)")
                }
            } else {
                print("🛡️ SAFE DISCONNECT: \(name) not attached, skipping")
            }
        }
        
        print("🛡️ SAFE DISCONNECT: Track node disconnection complete")
    }

    // MARK: - Safe Graph Mutation (ChatGPT's Critical Section Pattern)
    private func modifyGraphSafely(_ work: () throws -> Void) rethrows {
        // ChatGPT Fix: Suspend all timers and transport during graph mutation
        print("🛡️ SAFE MUTATION: Freezing transport and timers...")
        
        let wasRunning = engine.isRunning
        let wasPlaying = transportState.isPlaying
        
        // 1) Freeze transport callbacks - prevent position updates and cycle checks
        transportFrozen = true
        positionTimer?.invalidate()
        
        // 2) Pause engine + stop all players
        if wasRunning {
            engine.pause()
            print("🛡️ SAFE MUTATION: Engine paused")
        }
        
        // Stop all player nodes to prevent scheduling conflicts
        for node in engine.attachedNodes {
            if let playerNode = node as? AVAudioPlayerNode, playerNode.isPlaying {
                playerNode.stop()
            }
        }
        
        // 3) Perform the graph mutation atomically
        try work()
        
        // 4) Prepare and restart engine
        engine.prepare()
        if wasRunning {
            do {
                try engine.start()
                print("🛡️ SAFE MUTATION: Engine restarted successfully")
            } catch {
                print("❌ SAFE MUTATION: Failed to restart engine: \(error)")
            }
        }
        
        // 5) Reschedule all active regions and restart transport
        if wasPlaying {
            print("🛡️ SAFE MUTATION: Rescheduling active regions after graph change...")
            // Restart playback immediately - the engine is already prepared
            playFromPosition(currentPosition.timeInterval)
        }
        
        // 6) Restart position timer and unfreeze transport
        setupPositionTimer()
        transportFrozen = false
        print("🛡️ SAFE MUTATION: Transport and timers restored")
    }
    
    func setupTrackSend(_ trackId: UUID, to busId: UUID, level: Double) {
        print("🚀 CONNECTION POINTS: Setting up track \(trackId) to bus \(busId) at level \(level)")
        
        guard let trackNode = trackNodes[trackId],
              let busNode = busNodes[busId] else { 
            print("❌ Track or bus node not found: track=\(trackId), bus=\(busId)")
            return 
        }
        
        let sendKey = "\(trackId)-\(busId)"
        
        // Use ChatGPT's safe graph mutation pattern
        modifyGraphSafely {
            // Get the device format for consistency (same as master and tracks)
            let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
            print("🎯 SEND SETUP: Using device format: \(deviceFormat)")
            
            // Get the send mixer (create if needed)
            let sendMixer = busNode.getInputNode()
            
            // CHATGPT'S BREAKTHROUGH: Use AVAudioConnectionPoint for multi-destination
            let mainConnectionPoint = AVAudioConnectionPoint(node: mixer, bus: 0)
            let sendConnectionPoint = AVAudioConnectionPoint(node: sendMixer, bus: 0)
            
            print("🔗 NATIVE MULTI-DESTINATION: Creating connection points...")
            print("   - Main: \(mixer) bus 0")
            print("   - Send: \(sendMixer) bus 0")
            
            // Disconnect current output (this is safe because we reconnect atomically)
            engine.disconnectNodeOutput(trackNode.panNode)
            print("   ⚡ Disconnected pan node output")
            
            // ATOMIC RECONNECTION: Connect to multiple destinations simultaneously
            // ChatGPT Fix: Pin the split to device format to prevent 44.1k islands
            engine.connect(
                trackNode.panNode, 
                to: [mainConnectionPoint, sendConnectionPoint], 
                fromBus: 0, 
                format: deviceFormat
            )
            print("   ✅ ATOMIC MULTI-CONNECT: Pan → [Main + Send] completed!")
            
            // CHATGPT'S SEND LEVEL CONTROL: Use AVAudioMixingDestination
            if let mixing = trackNode.panNode as? AVAudioMixing,
               let destination = mixing.destination(forMixer: sendMixer, bus: 0) {
                destination.volume = Float(level)
                print("   🎚️ MIXING DESTINATION: Set send level to \(level)")
            } else {
                print("   ⚠️ Could not set mixing destination volume")
            }
            
            // Store send for future updates
            trackSendIds[sendKey] = UUID() // Generate a unique ID for this send
        }
        
        print("🎉 CHATGPT SOLUTION COMPLETE:")
        print("   - Method: Native AVAudioConnectionPoint multi-destination")
        print("   - Send Control: AVAudioMixingDestination volume")
        print("   - Safety: Atomic reconnection with engine pause/resume")
        print("   - Format: Consistent device format (\(engine.outputNode.inputFormat(forBus: 0).sampleRate)Hz)")
        print("🚀 MAKE IT SO! ✨")
        
    }
    
    
    func updateTrackSendLevel(_ trackId: UUID, busId: UUID, level: Double) {
        let sendKey = "\(trackId)-\(busId)"
        guard let _ = trackSendIds[sendKey],
              let trackNode = trackNodes[trackId],
              let busNode = busNodes[busId] else {
            print("❌ CONNECTION POINTS: Send not found for update")
            return
        }
        
        // CHATGPT'S SEND LEVEL CONTROL: Use AVAudioMixingDestination
        let sendMixer = busNode.getInputNode()
        
        if let mixing = trackNode.panNode as? AVAudioMixing,
           let destination = mixing.destination(forMixer: sendMixer, bus: 0) {
            destination.volume = Float(level)
            print("🎚️ MIXING DESTINATION: Updated send level to \(level)")
        } else {
            print("⚠️ Could not update mixing destination volume")
        }
    }
    
    func removeTrackSend(_ trackId: UUID, from busId: UUID) {
        let sendKey = "\(trackId)-\(busId)"
        
        guard let _ = trackSendIds[sendKey],
              let trackNode = trackNodes[trackId] else {
            print("❌ CONNECTION POINTS: Send not found for removal")
            return
        }
        
        // Use safe graph mutation for removal
        modifyGraphSafely {
            let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
            
            // Reconnect to main mixer only (removes the send connection)
            let mainConnectionPoint = AVAudioConnectionPoint(node: mixer, bus: 0)
            
            engine.disconnectNodeOutput(trackNode.panNode)
            engine.connect(
                trackNode.panNode,
                to: [mainConnectionPoint],
                fromBus: 0,
                format: deviceFormat
            )
        }
        
        trackSendIds.removeValue(forKey: sendKey)
        print("🗑️ CONNECTION POINTS: Removed send from track \(trackId) to bus \(busId)")
    }
    
    // MARK: - Track Send Restoration
    private func restoreTrackSendsForProject(_ project: AudioProject) {
        print("🔄 SEND RESTORATION: Restoring track sends for project...")
        
        for track in project.tracks {
            for (sendIndex, trackSend) in track.sends.enumerated() {
                // Skip placeholder sends (empty UUID)
                if trackSend.busId != UUID() {
                    // Check if the bus exists
                    if busNodes[trackSend.busId] != nil {
                        print("🔄 RESTORING SEND: Track '\(track.name)' S\(sendIndex + 1) → Bus \(trackSend.busId) at level \(trackSend.sendLevel)")
                        
                        // Set up the audio routing
                        setupTrackSend(track.id, to: trackSend.busId, level: trackSend.sendLevel)
                    } else {
                        print("⚠️ SEND RESTORATION: Bus \(trackSend.busId) not found for track '\(track.name)' send \(sendIndex + 1)")
                    }
                }
            }
        }
        
        print("✅ SEND RESTORATION: Completed restoring track sends")
    }
    
    private func rebuildBusChain(_ bus: BusAudioNode) {
        print("🔧 REBUILD BUS CHAIN: Wiring input → effects → output for bus")
        
        let inNode = bus.getInputNode()
        let outNode = bus.getOutputNode()
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        
        // Get enabled effect units from the bus
        let enabledUnits = bus.getEnabledEffectUnits()
        
        // Disconnect input node first
        engine.disconnectNodeOutput(inNode)
        
        if enabledUnits.isEmpty {
            // Direct connection: input → output
            engine.connect(inNode, to: outNode, format: deviceFormat)
            print("🔧 BUS CHAIN: Direct input → output (no effects)")
        } else {
            // Attach any units not yet in the engine
            for unit in enabledUnits where unit.engine == nil {
                engine.attach(unit)
            }
            
            // Chain connection: input → effect1 → effect2 → ... → output
            engine.connect(inNode, to: enabledUnits[0], format: deviceFormat)
            
            // Connect effects in sequence
            for i in 0..<(enabledUnits.count - 1) {
                engine.disconnectNodeOutput(enabledUnits[i])
                engine.connect(enabledUnits[i], to: enabledUnits[i + 1], format: deviceFormat)
            }
            
            // Connect last effect to output
            engine.disconnectNodeOutput(enabledUnits.last!)
            engine.connect(enabledUnits.last!, to: outNode, format: deviceFormat)
            
            print("🔧 BUS CHAIN: input → \(enabledUnits.count) effects → output")
        }
    }
    
    private func clearAllBuses() {
        print("🧹 Clearing all bus nodes...")
        
        // Clear all send connections first (professional channel strips handle this)
        for (sendKey, _) in trackSendIds {
            let components = sendKey.split(separator: "-")
            if components.count == 2,
               let trackId = UUID(uuidString: String(components[0])),
               let busId = UUID(uuidString: String(components[1])) {
                removeTrackSend(trackId, from: busId)
            }
        }
        
        for (busId, busNode) in busNodes {
            // Stop level monitoring
            busNode.stopLevelMonitoring()
            
            // Disconnect and detach nodes
            if engine.attachedNodes.contains(busNode.getInputNode()) {
                engine.disconnectNodeInput(busNode.getInputNode())
                engine.detach(busNode.getInputNode())
            }
            if engine.attachedNodes.contains(busNode.getOutputNode()) {
                engine.disconnectNodeInput(busNode.getOutputNode())
                engine.detach(busNode.getOutputNode())
            }
            
            print("Cleared bus node: \(busId)")
        }
        
        busNodes.removeAll()
        
        // Clear send IDs (professional channel strips handle cleanup)
        trackSendIds.removeAll()
        
        print("All bus nodes cleared")
    }
    
    // MARK: - Transport Controls
    func play() {
        guard currentProject != nil else { return }
        
        switch transportState {
        case .stopped:
            startTime = CACurrentMediaTime()
            pausedTime = 0
            transportState = .playing
            
        case .paused:
            startTime = CACurrentMediaTime()
            transportState = .playing
            
        case .playing, .recording:
            return // Already playing
        }
        
        startPlayback()
    }
    
    func pause() {
        guard transportState.isPlaying else { return }
        
        pausedTime = currentPosition.timeInterval
        transportState = .paused
        stopPlayback()
    }
    
    func stop() {
        transportState = .stopped
        // Keep current playhead position instead of resetting to 0
        pausedTime = currentPosition.timeInterval
        // Don't reset currentPosition - keep it where it stopped
        stopPlayback()
    }
    
    func record() {
        print("🎙️ RECORD: ========== STARTING RECORDING PROCESS ==========")
        print("🎙️ RECORD: Current transport state: \(transportState)")
        print("🎙️ RECORD: Current recording state: \(isRecording)")
        
        guard let project = currentProject else { 
            print("❌ RECORD: No project loaded")
            return 
        }
        
        print("🎙️ RECORD: Project loaded: \(project.name)")
        print("🎙️ RECORD: Project has \(project.tracks.count) tracks")
        
        // Check for record-enabled tracks
        let recordEnabledTracks = project.tracks.filter { $0.mixerSettings.isRecordEnabled }
        print("🎙️ RECORD: Found \(recordEnabledTracks.count) record-enabled tracks:")
        for track in recordEnabledTracks {
            print("   - \(track.name) (ID: \(track.id))")
        }
        
        if recordEnabledTracks.isEmpty {
            print("⚠️ RECORD: No tracks are record-enabled! Recording may not work properly.")
        }
        
        if transportState != .playing {
            print("🎙️ RECORD: Starting playback first...")
            play()
        }
        
        print("🎙️ RECORD: Setting transport state to recording...")
        transportState = .recording
        isRecording = true
        print("🎙️ RECORD: Calling startRecording()...")
        startRecording()
    }
    
    func stopRecording() {
        print("🎙️ STOP RECORD: Stopping recording...")
        if transportState == .recording {
            print("🎙️ STOP RECORD: Processing recorded audio...")
            stopRecordingInternal()
            transportState = .stopped
            isRecording = false
            stopPlayback()
            print("🎙️ STOP RECORD: Recording stopped successfully")
        } else {
            print("❌ STOP RECORD: Not currently recording (state: \(transportState))")
        }
    }
    
    // MARK: - Playback Implementation
    private func startPlayback() {
        guard let project = currentProject else { return }

        let startTime = currentPosition.timeInterval
        var tracksStarted = 0

        for track in project.tracks {
            guard let trackNode = trackNodes[track.id] else { continue }

            do {
                try trackNode.scheduleFromPosition(startTime, audioRegions: track.regions)
                if trackNode.playerNode.isPlaying {
                    tracksStarted += 1
                }
            } catch {
                print("❌ Failed scheduling track '\(track.name)': \(error)")
            }
        }

        print("🎵 Started \(tracksStarted) track(s) from \(String(format: "%.2f", startTime))s")
    }
    
    private func stopPlayback() {
        // Stop all player nodes
        for node in engine.attachedNodes {
            if let playerNode = node as? AVAudioPlayerNode {
                playerNode.stop()
            }
        }
    }
    
    private func playTrack(_ track: AudioTrack, from startTime: TimeInterval) {
        // Get the track's dedicated player node
        guard let trackNode = trackNodes[track.id] else {
            print("No track node found for track: \(track.name)")
            return
        }
        
        // Schedule ALL regions - let TrackAudioNode handle timing internally
        // Don't filter by "active" status based on current position
        let allRegions = track.regions
        
        // Schedule audio for each region on this track's player node
        for region in allRegions {
            scheduleRegion(region, on: trackNode, at: startTime)
        }
    }
    
    private func scheduleRegion(_ region: AudioRegion, on trackNode: TrackAudioNode, at currentTime: TimeInterval) {
        let playerNode = trackNode.playerNode
        
        do {
            let audioFile = try AVAudioFile(forReading: region.audioFile.url)
            let offsetInFile = currentTime - region.startTime + region.offset
            let remainingDuration = region.endTime - currentTime
            let framesToPlay = AVAudioFrameCount(remainingDuration * audioFile.processingFormat.sampleRate)
            
            if offsetInFile >= 0 && offsetInFile < region.audioFile.duration {
                let startFrame = AVAudioFramePosition(offsetInFile * audioFile.processingFormat.sampleRate)
                
                // Stop any existing playback on this node first
                if playerNode.isPlaying {
                    playerNode.stop()
                }
                
                // Schedule the audio segment
                playerNode.scheduleSegment(
                    audioFile,
                    startingFrame: startFrame,
                    frameCount: framesToPlay,
                    at: nil
                )
                
                // Start playback on this specific track's player node
                safePlay(playerNode)
                
                print("🎵 Scheduled region '\(region.displayName)' on track '\(trackNode.id)' from \(offsetInFile)s")
            }
        } catch {
            print("❌ Failed to schedule region '\(region.displayName)': \(error)")
        }
    }
    
    private func scheduleRegionForSynchronizedPlayback(_ region: AudioRegion, on trackNode: TrackAudioNode, at currentTime: TimeInterval) -> Bool {
        let playerNode = trackNode.playerNode
        
        do {
            let audioFile = try AVAudioFile(forReading: region.audioFile.url)
            let offsetInFile = currentTime - region.startTime + region.offset
            let remainingDuration = region.endTime - currentTime
            let framesToPlay = AVAudioFrameCount(remainingDuration * audioFile.processingFormat.sampleRate)
            
            if offsetInFile >= 0 && offsetInFile < region.audioFile.duration {
                let startFrame = AVAudioFramePosition(offsetInFile * audioFile.processingFormat.sampleRate)
                
                // Stop any existing playback on this node first
                if playerNode.isPlaying {
                    playerNode.stop()
                }
                
                // Schedule the audio segment (but don't start playing yet)
                playerNode.scheduleSegment(
                    audioFile,
                    startingFrame: startFrame,
                    frameCount: framesToPlay,
                    at: nil
                )
                
                print("🎵 Scheduled region '\(region.displayName)' for synchronized playback")
                return true
            }
        } catch {
            print("❌ Failed to schedule region '\(region.displayName)' for sync: \(error)")
        }
        
        return false
    }
    
    // MARK: - Recording Implementation
    private func startRecording() {
        print("🎙️ START RECORD: Checking project...")
        guard currentProject != nil else {
            print("❌ Cannot start recording: No project loaded")
            return
        }
        
        print("🎙️ START RECORD: Requesting microphone permission...")
        // Request microphone permission
        requestMicrophonePermission { [weak self] granted in
            DispatchQueue.main.async {
                if granted {
                    print("✅ PERMISSION: Microphone access granted")
                    self?.setupRecording()
                } else {
                    print("❌ PERMISSION: Microphone permission denied")
                    self?.stopRecording()
                }
            }
        }
    }
    
    private func requestMicrophonePermission(completion: @escaping (Bool) -> Void) {
        print("🎙️ PERMISSION: Checking microphone permission status...")
        
        // Check current permission status
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        print("🎙️ PERMISSION: Current status: \(status) (rawValue: \(status.rawValue))")
        
        switch status {
        case .authorized:
            print("✅ PERMISSION: Microphone permission already granted")
            completion(true)
        case .denied, .restricted:
            print("❌ PERMISSION: Microphone permission denied or restricted")
            print("💡 PERMISSION: Please grant microphone access in System Preferences > Security & Privacy > Microphone")
            print("💡 PERMISSION: Or reset permissions with: tccutil reset Microphone tellurstori.TellUrStoriDAW")
            
            // Show alert to user about manual permission grant
            DispatchQueue.main.async {
                self.showPermissionAlert()
            }
            completion(false)
        case .notDetermined:
            print("🎙️ PERMISSION: Permission not determined, requesting access...")
            print("🎙️ PERMISSION: Attempting to show permission dialog...")
            
            // Try multiple approaches for permission request
            self.requestPermissionWithFallbacks(completion: completion)
            
        @unknown default:
            print("❌ PERMISSION: Unknown permission state: \(status)")
            completion(false)
        }
    }
    
    private func requestPermissionWithFallbacks(completion: @escaping (Bool) -> Void) {
        print("🎙️ FALLBACK: Trying primary permission request...")
        
        // Primary approach: Standard AVCaptureDevice request
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            print("🎙️ PRIMARY REQUEST: Result = \(granted)")
            
            if granted {
                DispatchQueue.main.async {
                    print("✅ PERMISSION: Microphone permission granted by user")
                    completion(true)
                }
                return
            }
            
            // If denied, try alternative approach
            print("🎙️ FALLBACK: Primary request failed, trying alternative...")
            DispatchQueue.main.async {
                self.tryAlternativePermissionRequest(completion: completion)
            }
        }
    }
    
    private func tryAlternativePermissionRequest(completion: @escaping (Bool) -> Void) {
        print("🎙️ ALTERNATIVE: Attempting alternative permission request...")
        
        // Alternative approach for macOS: Try to access input node directly
        // This might trigger permission dialog on macOS
        do {
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            print("✅ ALTERNATIVE: Successfully accessed input node with format: \(inputFormat)")
            
            // Check permission again after accessing input
            let newStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            print("🎙️ ALTERNATIVE: New status after input access: \(newStatus)")
            
            if newStatus == .authorized {
                completion(true)
            } else {
                print("❌ ALTERNATIVE: Still not authorized, showing manual instructions")
                self.showPermissionAlert()
                completion(false)
            }
            
        } catch {
            print("❌ ALTERNATIVE: Input node access failed: \(error)")
            self.showPermissionAlert()
            completion(false)
        }
    }
    
    private func showPermissionAlert() {
        print("🚨 PERMISSION ALERT: Showing manual permission instructions")
        print("📋 INSTRUCTIONS:")
        print("   1. Open System Preferences > Security & Privacy > Privacy")
        print("   2. Select 'Microphone' from the left sidebar")
        print("   3. Check the box next to 'TellUrStoriDAW'")
        print("   4. Restart the app")
        print("   OR")
        print("   5. Run: tccutil reset Microphone tellurstori.TellUrStoriDAW")
        print("   6. Try recording again")
        
        // TODO: Show actual macOS alert dialog here if needed
    }
    
    private func setupRecording() {
        print("🎙️ SETUP RECORD: Setting up recording...")
        guard let project = currentProject else { 
            print("❌ SETUP RECORD: No project available")
            return 
        }
        
        do {
            // Find the first record-enabled track or create a new one
            let recordTrack = findOrCreateRecordTrack(in: project)
            recordingTrackId = recordTrack.id
            print("🎙️ SETUP RECORD: Using track: \(recordTrack.name) (ID: \(recordTrack.id))")
            
            // Create recording file URL
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let recordingURL = documentsPath.appendingPathComponent("Recording_\(Date().timeIntervalSince1970).wav")
            print("🎙️ SETUP RECORD: Recording to: \(recordingURL.path)")
            
            // Set up audio format (44.1kHz, 16-bit, stereo)
            let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
            print("🎙️ SETUP RECORD: Using format: \(format)")
            
            // Create recording file
            recordingFile = try AVAudioFile(forWriting: recordingURL, settings: format.settings)
            print("✅ SETUP RECORD: Recording file created successfully")
            
            // Set up input node
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)
            print("🎙️ SETUP RECORD: Input format: \(inputFormat)")
            
            // Install tap on input node to capture audio
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
                guard let self = self, let recordingFile = self.recordingFile else { return }
                
                do {
                    try recordingFile.write(from: buffer)
                } catch {
                    print("❌ Error writing audio buffer: \(error)")
                }
            }
            
            recordingStartTime = currentPosition.timeInterval
            print("✅ RECORDING STARTED: Recording to \(recordingURL.lastPathComponent) from time \(recordingStartTime)")
            
        } catch {
            print("❌ Failed to setup recording: \(error)")
            stopRecording()
        }
    }
    
    private func findOrCreateRecordTrack(in project: AudioProject) -> AudioTrack {
        // Find first record-enabled track
        if let recordTrack = project.tracks.first(where: { $0.mixerSettings.isRecordEnabled }) {
            return recordTrack
        }
        
        // If no record-enabled track, find first audio track
        if let audioTrack = project.tracks.first(where: { $0.trackType == .audio }) {
            return audioTrack
        }
        
        // If no audio tracks, return first track (will be created if needed)
        return project.tracks.first ?? AudioTrack(name: "Audio 1", trackType: .audio)
    }
    
    private func stopRecordingInternal() {
        guard let recordingFile = recordingFile,
              let recordingTrackId = recordingTrackId,
              var project = currentProject else {
            print("❌ No active recording to stop")
            return
        }
        
        // Remove input tap
        engine.inputNode.removeTap(onBus: 0)
        
        // Calculate recording duration
        let recordingDuration = currentPosition.timeInterval - recordingStartTime
        
        do {
            // Create AudioFile object
            let audioFile = AudioFile(
                name: recordingFile.url.deletingPathExtension().lastPathComponent,
                url: recordingFile.url,
                duration: recordingDuration,
                sampleRate: recordingFile.processingFormat.sampleRate,
                channels: Int(recordingFile.processingFormat.channelCount),
                bitDepth: 16, // Assuming 16-bit
                fileSize: Int64(try recordingFile.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0),
                format: .wav
            )
            
            // Create audio region
            let audioRegion = AudioRegion(
                audioFile: audioFile,
                startTime: recordingStartTime,
                duration: recordingDuration,
                fadeIn: 0,
                fadeOut: 0,
                gain: 1.0,
                isLooped: false,
                offset: 0
            )
            
            // Add region to the recorded track
            if let trackIndex = project.tracks.firstIndex(where: { $0.id == recordingTrackId }) {
                project.tracks[trackIndex].regions.append(audioRegion)
                currentProject = project
                
                // Update track node with new region
                if trackNodes[recordingTrackId] != nil {
                    // The track node will pick up the new region on next playback
                }
                
                print("✅ Recording completed: \(audioFile.name) (\(String(format: "%.2f", recordingDuration))s)")
            }
            
        } catch {
            print("❌ Error processing recorded audio: \(error)")
        }
        
        // Clean up
        self.recordingFile = nil
        self.recordingStartTime = 0
        self.recordingTrackId = nil
    }
    
    // MARK: - Position Control
    func seek(to position: TimeInterval) {
        let wasPlaying = transportState.isPlaying
        
        if wasPlaying {
            stopPlayback()
        }
        
        pausedTime = position
        
        if let project = currentProject {
            currentPosition = PlaybackPosition(
                timeInterval: position,
                tempo: project.tempo,
                timeSignature: project.timeSignature
            )
        }
        
        if wasPlaying {
            startTime = CACurrentMediaTime()
            startPlayback()
        }
    }
    
    // MARK: - Mixer Controls
    func setTrackVolume(_ trackId: UUID, volume: Float) {
        guard let project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            var updatedProject = project
            updatedProject.tracks[trackIndex].mixerSettings.volume = volume
            currentProject = updatedProject
            
            // Update the actual audio node volume
            updateTrackMixerSettings(trackId, settings: updatedProject.tracks[trackIndex].mixerSettings)
        }
    }
    
    func setTrackPan(_ trackId: UUID, pan: Float) {
        guard let project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            var updatedProject = project
            updatedProject.tracks[trackIndex].mixerSettings.pan = pan
            currentProject = updatedProject
            
            updateTrackMixerSettings(trackId, settings: updatedProject.tracks[trackIndex].mixerSettings)
        }
    }
    
    func muteTrack(_ trackId: UUID, muted: Bool) {
        guard let project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            var updatedProject = project
            updatedProject.tracks[trackIndex].mixerSettings.isMuted = muted
            currentProject = updatedProject
            
            // Update actual mute state in audio engine
            updateTrackMuteState(trackId, muted: muted)
        }
    }
    
    func soloTrack(_ trackId: UUID, solo: Bool) {
        guard let project = currentProject else { return }
        
        var updatedProject = project
        
        if solo {
            // Solo this track, un-solo all others
            for i in 0..<updatedProject.tracks.count {
                updatedProject.tracks[i].mixerSettings.isSolo = updatedProject.tracks[i].id == trackId
            }
        } else {
            // Un-solo this track
            if let trackIndex = updatedProject.tracks.firstIndex(where: { $0.id == trackId }) {
                updatedProject.tracks[trackIndex].mixerSettings.isSolo = false
            }
        }
        
        currentProject = updatedProject
        updateAllTrackStates()
    }
    
    private func updateTrackMixerSettings(_ trackId: UUID, settings: MixerSettings) {
        // Find and update the mixer node for this track
        // Implementation would depend on how you map tracks to nodes
    }
    
    private func updateTrackMuteState(_ trackId: UUID, muted: Bool) {
        // Call the existing updateTrackMute method that handles the actual audio muting
        updateTrackMute(trackId: trackId, isMuted: muted)
    }
    
    private func updateAllTrackStates() {
        guard let project = currentProject else { return }
        
        // Update mute/solo states for all tracks
        for track in project.tracks {
            // Update mute state
            updateTrackMute(trackId: track.id, isMuted: track.mixerSettings.isMuted)
            
            // Update solo state
            updateTrackSolo(trackId: track.id, isSolo: track.mixerSettings.isSolo)
        }
    }
    
    // MARK: - Audio File Import
    func importAudioFile(from url: URL) async throws -> AudioFile {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        
        let audioFileFormat: AudioFileFormat
        switch url.pathExtension.lowercased() {
        case "wav": audioFileFormat = .wav
        case "aiff", "aif": audioFileFormat = .aiff
        case "mp3": audioFileFormat = .mp3
        case "m4a": audioFileFormat = .m4a
        case "flac": audioFileFormat = .flac
        default: audioFileFormat = .wav
        }
        
        return AudioFile(
            name: url.deletingPathExtension().lastPathComponent,
            url: url,
            duration: Double(audioFile.length) / format.sampleRate,
            sampleRate: format.sampleRate,
            channels: Int(format.channelCount),
            bitDepth: 16, // Simplified
            fileSize: fileSize,
            format: audioFileFormat
        )
    }
    
    // MARK: - Audio Region Loading
    private func loadAudioRegion(_ region: AudioRegion, trackNode: TrackAudioNode) {
        let audioFile = region.audioFile
        
        do {
            try trackNode.loadAudioFile(audioFile)
        } catch {
            print("Failed to load audio file: \(error)")
        }
    }
    
    // MARK: - Mixer Controls
    func updateTrackVolume(trackId: UUID, volume: Float) {
        guard let trackNode = trackNodes[trackId] else { return }
        trackNode.setVolume(volume)
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.volume = volume
        }
    }
    
    func updateTrackPan(trackId: UUID, pan: Float) {
        guard let trackNode = trackNodes[trackId] else { return }
        trackNode.setPan(pan)
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.pan = pan
        }
    }
    
    func updateTrackMute(trackId: UUID, isMuted: Bool) {
        guard let trackNode = trackNodes[trackId] else { 
            print("⚠️ AudioEngine: No trackNode found for \(trackId)")
            return 
        }
        
        trackNode.setMuted(isMuted)
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.isMuted = isMuted
        }
    }
    
    func updateTrackSolo(trackId: UUID, isSolo: Bool) {
        guard let trackNode = trackNodes[trackId] else { 
            print("⚠️ AudioEngine: No trackNode found for \(trackId)")
            return 
        }
        
        if isSolo {
            soloTracks.insert(trackId)
        } else {
            soloTracks.remove(trackId)
        }
        
        trackNode.setSolo(isSolo)
        updateSoloState()
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.isSolo = isSolo
        }
    }
    
    private func updateSoloState() {
        let hasSoloTracks = !soloTracks.isEmpty
        
        for (trackId, trackNode) in trackNodes {
            if hasSoloTracks {
                // If there are solo tracks, mute all non-solo tracks
                let shouldBeMuted = !soloTracks.contains(trackId)
                trackNode.setMuted(shouldBeMuted || trackNode.isMuted)
            } else {
                // If no solo tracks, restore original mute state
                if let project = currentProject,
                   let track = project.tracks.first(where: { $0.id == trackId }) {
                    trackNode.setMuted(track.mixerSettings.isMuted)
                }
            }
        }
    }
    
    func updateTrackEQ(trackId: UUID, highEQ: Float, midEQ: Float, lowEQ: Float) {
        guard let trackNode = trackNodes[trackId] else { return }
        
        // Apply EQ to the audio node
        trackNode.setEQ(highGain: highEQ, midGain: midEQ, lowGain: lowEQ)
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.highEQ = highEQ
            settings.midEQ = midEQ
            settings.lowEQ = lowEQ
        }
    }
    
    func updateTrackRecordEnabled(trackId: UUID, isRecordEnabled: Bool) {
        // Update the project model
        if let project = currentProject,
           let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            currentProject?.tracks[trackIndex].mixerSettings.isRecordEnabled = isRecordEnabled
        }
        
        print("🔴 Record \(isRecordEnabled ? "enabled" : "disabled") for track \(trackId)")
    }
    
    // MARK: - Master Volume Control
    func updateMasterVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        mixer.outputVolume = clampedVolume
        masterVolume = Double(clampedVolume)  // Update published property
        print("🔊 Master volume updated to \(Int(clampedVolume * 100))%")
    }
    
    func getMasterVolume() -> Float {
        return mixer.outputVolume
    }
    
    // MARK: - Bus Output Level Control
    func updateBusOutputLevel(_ busId: UUID, outputLevel: Double) {
        // Update the bus node's output gain
        if let busNode = busNodes[busId] {
            busNode.outputGain = Float(outputLevel)
            // Only log significant changes to reduce noise
            if abs(Double(busNode.outputGain) - outputLevel) > 0.05 {
                print("🎛️ Bus output level updated to \(Int(outputLevel * 100))%")
            }
        }
        
        // Update the project model
        guard var project = currentProject,
              let busIndex = project.buses.firstIndex(where: { $0.id == busId }) else {
            return
        }
        
        project.buses[busIndex].outputLevel = outputLevel
        project.modifiedAt = Date()
        currentProject = project
    }
    
    private func updateProjectTrackMixerSettings(trackId: UUID, update: (inout MixerSettings) -> Void) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            update(&project.tracks[trackIndex].mixerSettings)
            project.modifiedAt = Date()
            currentProject = project
            
            // CRITICAL: Notify that project has been updated so SwiftUI views refresh
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
    

    
    func removeTrack(trackId: UUID) {
        guard var project = currentProject else { return }
        
        // Remove from project
        project.tracks.removeAll { $0.id == trackId }
        currentProject = project
        
        // Remove track node
        if let trackNode = trackNodes[trackId] {
            // [BUGFIX] Use safe disconnection method
            safeDisconnectTrackNode(trackNode)
            trackNodes.removeValue(forKey: trackId)
        }
        
        // Remove from solo tracks if present
        soloTracks.remove(trackId)
        updateSoloState()
    }
    
    // MARK: - Level Monitoring
    func getTrackLevels() -> [UUID: (current: Float, peak: Float)] {
        var levels: [UUID: (current: Float, peak: Float)] = [:]
        
        for (trackId, trackNode) in trackNodes {
            levels[trackId] = (current: trackNode.currentLevel, peak: trackNode.peakLevel)
        }
        
        return levels
    }
    
    func getMasterLevel() -> (current: Float, peak: Float) {
        // Get the actual master bus level from the main mixer node
        // This represents the combined output of all tracks after mixing
        
        // Get current master volume setting
        let masterVolume = getMasterVolume()
        
        // If master volume is 0, return silent levels
        guard masterVolume > 0.0 else {
            return (current: 0.0, peak: 0.0)
        }
        
        // Calculate RMS of all active (non-muted) tracks
        let trackLevels = getTrackLevels()
        let activeTracks = trackLevels.values.filter { $0.current > 0.0 }
        
        guard !activeTracks.isEmpty else {
            return (current: 0.0, peak: 0.0)
        }
        
        // Calculate RMS (Root Mean Square) for more accurate master level
        let sumOfSquares = activeTracks.map { $0.current * $0.current }.reduce(0, +)
        let rms = sqrt(sumOfSquares / Float(activeTracks.count))
        
        let maxPeak = activeTracks.map { $0.peak }.max() ?? 0.0
        
        // Apply master volume to the calculated levels (post-fader metering)
        let postFaderRMS = rms * masterVolume
        let postFaderPeak = maxPeak * masterVolume
        
        return (current: postFaderRMS, peak: postFaderPeak)
    }
    
    // MARK: - Timeline Navigation
    
    func seekToPosition(_ timeInterval: TimeInterval) {
        let wasPlaying = transportState == .playing
        let newTime = max(0, timeInterval)
        
        print("🎯 Seeking to position: \(String(format: "%.2f", newTime))s, wasPlaying=\(wasPlaying)")
        
        if wasPlaying {
            // Use transport-safe jump for atomic seek during playback
            transportSafeJump(to: newTime)
        } else {
            // Simple position update when paused
            pausedTime = newTime
            currentPosition = PlaybackPosition(
                timeInterval: newTime,
                tempo: currentProject?.tempo ?? 120,
                timeSignature: currentProject?.timeSignature ?? .fourFour
            )
        }
        
        print("🎵 Seeked to position: \(currentTimeString)")
    }
    
    private func playFromPosition(_ startTime: TimeInterval) {
        guard let project = currentProject else { return }
        
        print("🎯 Starting playback from position: \(String(format: "%.2f", startTime))s")
        
        // Set transport state
        transportState = .playing
        
        // Schedule and start all tracks from the specified position
        var tracksStarted = 0
        
        for track in project.tracks {
            guard let trackNode = trackNodes[track.id] else { continue }
            
            // Only play tracks that have audio regions at or after the start time
            let relevantRegions = track.regions.filter { region in
                region.startTime + region.duration > startTime
            }
            
            if !relevantRegions.isEmpty {
                do {
                    try trackNode.scheduleFromPosition(startTime, audioRegions: track.regions)
                    trackNode.play()
                    tracksStarted += 1
                } catch {
                    print("❌ Failed to schedule track \(track.name) from position \(startTime): \(error)")
                }
            }
        }
        
        if tracksStarted > 0 {
            print("🎵 Started \(tracksStarted) tracks from position \(String(format: "%.2f", startTime))s")
        } else {
            print("⚠️ No tracks to play from position \(String(format: "%.2f", startTime))s")
        }
    }
    
    func rewind(_ seconds: TimeInterval = 1.0) {
        let newTime = max(0, currentPosition.timeInterval - seconds)
        seekToPosition(newTime)
    }
    
    func fastForward(_ seconds: TimeInterval = 1.0) {
        let newTime = currentPosition.timeInterval + seconds
        seekToPosition(newTime)
    }
    
    func skipToBeginning() {
        seekToPosition(0)
    }
    
    func skipToEnd() {
        // Skip to end of longest track or 10 seconds forward if no tracks
        guard let project = currentProject else {
            seekToPosition(currentPosition.timeInterval + 10)
            return
        }
        
        let maxDuration = project.tracks.compactMap { track in
            track.regions.map { region in
                region.startTime + region.duration
            }.max()
        }.max() ?? currentPosition.timeInterval + 10
        
        seekToPosition(maxDuration)
    }
    
    // MARK: - Cycle Controls
    
    func toggleCycle() {
        isCycleEnabled.toggle()
        print("🔄 Cycle \(isCycleEnabled ? "enabled" : "disabled"): \(cycleStartTime)s - \(cycleEndTime)s")
    }
    
    func setCycleRegion(start: TimeInterval, end: TimeInterval) {
        cycleStartTime = max(0, start)
        cycleEndTime = max(cycleStartTime + 0.1, end) // Ensure minimum 0.1s cycle length
        // Cycle region updated silently for smooth interaction
    }
    
    private func checkCycleLoop() {
        guard isCycleEnabled else { 
            // print("🔄 Cycle disabled, skipping loop check")
            return 
        }
        
        guard transportState.isPlaying else { 
            // print("🔄 Not playing, skipping loop check")
            return 
        }
        
        guard !transportFrozen else {
            // print("🔄 Transport frozen, skipping cycle check")
            return
        }
        
        let currentTime = currentPosition.timeInterval
        let currentSystemTime = CACurrentMediaTime()
        
        // Prevent rapid re-triggering with cooldown
        if currentSystemTime - lastCycleJumpTime < cycleCooldown {
            return
        }
        
        // Check if we've reached the cycle end point with epsilon for floating-point safety
        if currentTime >= (cycleEndTime - cycleEpsilon) {
            print("🔄 LOOPING! Cycling back to start: \(cycleStartTime)s (current: \(currentTime)s, end: \(cycleEndTime)s)")
            lastCycleJumpTime = currentSystemTime
            transportSafeJump(to: cycleStartTime)
        }
    }
}

// MARK: - Audio Engine Extensions
extension AudioEngine {
    
    var isPlaying: Bool {
        transportState.isPlaying
    }
    
    var currentTimeString: String {
        let minutes = Int(currentPosition.timeInterval) / 60
        let seconds = Int(currentPosition.timeInterval) % 60
        let milliseconds = Int((currentPosition.timeInterval.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    var currentMusicalTimeString: String {
        guard let project = currentProject else { return "1.1.00" }
        return currentPosition.displayString(timeSignature: project.timeSignature)
    }
    
    // MARK: - Track-Specific Methods
    func getTrackLevel(_ trackId: UUID) -> Float {
        // Return the current audio level for the specified track
        guard let trackNode = trackNodes[trackId] else { return 0.0 }
        return trackNode.currentLevel
    }
    
    func updateTrackRecordEnable(_ trackId: UUID, _ enabled: Bool) {
        print("🔴 Record enable called: \(enabled) for track \(trackId)")
        guard var project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].mixerSettings.isRecordEnabled = enabled
        currentProject = project
        
        // Update audio node if it exists
        trackNodes[trackId]?.setRecordEnabled(enabled)
        
        print("🎙️ Track \(project.tracks[trackIndex].name) record enable: \(enabled)")
    }
    
    func updateInputMonitoring(_ trackId: UUID, _ enabled: Bool) {
        guard var project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].mixerSettings.inputMonitoring = enabled
        currentProject = project
        
        // Update audio node if it exists
        trackNodes[trackId]?.setInputMonitoring(enabled)
        
        print("🎧 Track \(project.tracks[trackIndex].name) input monitoring: \(enabled)")
    }
    
    func toggleTrackFreeze(_ trackId: UUID) {
        guard var project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].isFrozen.toggle()
        currentProject = project
        
        let isFrozen = project.tracks[trackIndex].isFrozen
        
        // Update audio processing for frozen tracks
        if let trackNode = trackNodes[trackId] {
            trackNode.setFrozen(isFrozen)
        }
        
        print("❄️ Track \(project.tracks[trackIndex].name) freeze: \(isFrozen)")
    }
    
    // MARK: - Wet-Solo Debug Helper
    
    /// STEP 3: Wet-Solo functionality for instant audibility check
    func enableWetSolo(trackId: UUID, enabled: Bool) {
        guard let trackNode = trackNodes[trackId] else {
            print("❌ WET-SOLO: Track node not found for ID: \(trackId)")
            return
        }
        
        // Get the main mixer destination for this track's pan node
        guard let mixing = trackNode.panNode as? AVAudioMixing,
              let mainDest = mixing.destination(forMixer: mixer, bus: 0) else {
            print("❌ WET-SOLO: Could not get main destination for track \(trackId)")
            return
        }
        
        if enabled {
            // Wet-solo ON: kill the dry branch for this track
            mainDest.volume = 0.0
            print("🔇 WET-SOLO ON: Muted dry signal for track \(trackId)")
        } else {
            // Wet-solo OFF: restore the dry branch for this track
            mainDest.volume = 1.0
            print("🔊 WET-SOLO OFF: Restored dry signal for track \(trackId)")
        }
    }
    
    /// Debug helper to check bus levels
    func debugBusLevels(busId: UUID) {
        guard let busNode = busNodes[busId] else {
            print("❌ BUS DEBUG: Bus node not found for ID: \(busId)")
            return
        }
        
        print("🔎 BUS LEVELS DEBUG — Bus: \(busId)")
        print("   Input Level: \(busNode.inputLevel)")
        print("   Output Level: \(busNode.outputLevel)")
        print("   Input Gain: \(busNode.inputGain)")
        print("   Output Gain: \(busNode.outputGain)")
        print("   Is Muted: \(busNode.isMuted)")
    }
    
    // MARK: - Transport Safe Jump
    
    /// ChatGPT's transport-safe jump for atomic cycle transitions
    private func transportSafeJump(to startTime: TimeInterval) {
        print("🚀 TRANSPORT SAFE JUMP: Jumping to \(startTime)s")
        
        // 1) Freeze callbacks
        transportFrozen = true
        positionTimer?.invalidate()
        
        let wasRunning = engine.isRunning
        engine.pause()
        print("🚀 SAFE JUMP: Engine paused for atomic jump")
        
        // 2) Stop & reset players so they're clean for re-schedule
        for node in engine.attachedNodes {
            if let p = node as? AVAudioPlayerNode {
                p.stop()
                p.reset() // <-- important at loop edges
            }
        }
        print("🚀 SAFE JUMP: All players stopped and reset")
        
        // 3) Reset timing variables and recompute currentPosition
        self.startTime = CACurrentMediaTime() // Reset start time to now
        self.pausedTime = startTime // Set paused time to the jump target
        
        currentPosition = PlaybackPosition(
            timeInterval: startTime,
            tempo: currentProject?.tempo ?? 120,
            timeSignature: currentProject?.timeSignature ?? .fourFour
        )
        
        engine.prepare()
        if wasRunning { 
            do {
                try engine.start()
                print("🚀 SAFE JUMP: Engine restarted")
            } catch {
                print("❌ SAFE JUMP: Failed to restart engine: \(error)")
            }
        }
        
        // 4) Schedule all tracks using consistent player-time scheduling
        
        for track in currentProject?.tracks ?? [] {
            guard let trackNode = trackNodes[track.id] else { continue }
            do {
                try trackNode.scheduleFromPosition(startTime, audioRegions: track.regions)
                // Note: scheduleFromPosition now handles playerNode.play() internally
                print("🚀 SAFE JUMP: Scheduled track \(track.name) with player-time")
            } catch {
                print("❌ SAFE JUMP: Failed to schedule track \(track.name): \(error)")
            }
        }
        
        // 5) Unfreeze
        setupPositionTimer()
        transportFrozen = false
        print("🚀 SAFE JUMP: Transport unfrozen, jump complete")
    }
    
    // MARK: - Safe Play Guard
    
    /// ChatGPT's safe play guard - ensures player has output connections before playing
    private func safePlay(_ player: AVAudioPlayerNode) {
        // Check if player is attached to engine and engine is running
        guard player.engine != nil else {
            print("⛔️ SAFE PLAY: Player not attached to engine - cannot play!")
            return
        }
        
        guard engine.isRunning else {
            print("⛔️ SAFE PLAY: Engine not running - cannot play!")
            return
        }
        
        // Additional check: verify the player is in our attached nodes
        guard engine.attachedNodes.contains(player) else {
            print("⛔️ SAFE PLAY: Player not in engine's attached nodes - cannot play!")
            return
        }
        
        // If we have active sends, add extra safety check
        if !trackSendIds.isEmpty {
            print("🔗 SAFE PLAY: Active sends detected, using extra caution...")
            // Check if player has valid output connections before playing
            let outputConnections = engine.outputConnectionPoints(for: player, outputBus: 0)
            guard !outputConnections.isEmpty else {
                print("❌ SAFE PLAY: Player has no output connections with sends active - cannot play!")
                return
            }
            print("✅ SAFE PLAY: Player has \(outputConnections.count) output connections with sends - safe to play")
        } else {
            print("✅ SAFE PLAY: Player attached and engine running - safe to play")
        }
        
        // Play immediately without async dispatch
        do {
            player.play()
            print("✅ SAFE PLAY: Player started successfully")
        } catch {
            print("❌ SAFE PLAY: Failed to start player: \(error)")
        }
    }
}
