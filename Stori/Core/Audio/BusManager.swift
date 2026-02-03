//
//  BusManager.swift
//  Stori
//
//  Extracted from AudioEngine - handles bus nodes, bus effects, and track sends
//

import Foundation
import AVFoundation

// MARK: - Bus Manager

/// Service responsible for bus/aux channel management and track sends.
/// Extracted from AudioEngine to reduce complexity and isolate bus-related logic.
///
/// Responsibilities:
/// - Bus node lifecycle (create, add, remove)
/// - Bus effect management (built-in effects)
/// - Bus plugin chain management (AU/VST)
/// - Track send setup and level management
/// - Bus output level control
@MainActor
class BusManager {
    
    // MARK: - Bus Node Storage
    
    /// Dictionary of all active bus audio nodes
    private(set) var busNodes: [UUID: BusAudioNode] = [:]
    
    // MARK: - Track Send State
    
    /// Tracks active send connections (key: "trackId-busId")
    private var trackSendIds: [String: UUID] = [:]
    
    /// Stores the input bus number for each send connection
    private var trackSendInputBus: [String: AVAudioNodeBus] = [:]
    
    // MARK: - Dependencies (injected from AudioEngine)
    
    /// Reference to the AVAudioEngine
    private let engine: AVAudioEngine
    
    /// Reference to the main mixer node
    private let mixer: AVAudioMixerNode
    
    /// Accessor for track nodes
    private let trackNodesAccessor: () -> [UUID: TrackAudioNode]
    
    /// Accessor for current project
    private let currentProjectAccessor: () -> AudioProject?
    
    /// Accessor for transport state
    private let transportStateAccessor: () -> TransportState
    
    /// Safe graph modification callback
    private let modifyGraphSafely: (@escaping () -> Void) -> Void
    
    /// Callback to update solo state after bus changes
    private let updateSoloState: () -> Void
    
    /// Callback to reconnect metronome after graph changes
    private let reconnectMetronome: () -> Void
    
    /// Callback to setup position timer
    private let setupPositionTimer: () -> Void
    
    /// Callback to get/set isInstallingPlugin flag
    private let isInstallingPluginAccessor: () -> Bool
    private let setIsInstallingPlugin: (Bool) -> Void
    
    // MARK: - Initialization
    
    init(
        engine: AVAudioEngine,
        mixer: AVAudioMixerNode,
        trackNodes: @escaping () -> [UUID: TrackAudioNode],
        currentProject: @escaping () -> AudioProject?,
        transportState: @escaping () -> TransportState,
        modifyGraphSafely: @escaping (@escaping () -> Void) -> Void,
        updateSoloState: @escaping () -> Void,
        reconnectMetronome: @escaping () -> Void,
        setupPositionTimer: @escaping () -> Void,
        isInstallingPlugin: @escaping () -> Bool,
        setIsInstallingPlugin: @escaping (Bool) -> Void
    ) {
        self.engine = engine
        self.mixer = mixer
        self.trackNodesAccessor = trackNodes
        self.currentProjectAccessor = currentProject
        self.transportStateAccessor = transportState
        self.modifyGraphSafely = modifyGraphSafely
        self.updateSoloState = updateSoloState
        self.reconnectMetronome = reconnectMetronome
        self.setupPositionTimer = setupPositionTimer
        self.isInstallingPluginAccessor = isInstallingPlugin
        self.setIsInstallingPlugin = setIsInstallingPlugin
    }
    
    // MARK: - Bus Setup
    
    /// Setup buses for a project
    func setupBusesForProject(_ project: AudioProject) {
        
        // Clear existing bus nodes
        clearAllBuses()
        
        // Create bus nodes for each bus
        for (index, bus) in project.buses.enumerated() {
            let busNode = createBusNode(for: bus)
            busNodes[bus.id] = busNode
            
            // Rebuild bus chain after setup
            rebuildBusChain(busNode)
            
            // Note: Bus plugins are now managed via TrackPluginManager/PluginChain
            // similar to track plugin management
        }
        
        
        // Restore track sends after buses are set up
        restoreTrackSendsForProject(project)
        
        
        // Update solo state AFTER sends are restored
        updateSoloState()
        
        // Reconnect metronome after all bus/effect connections
        reconnectMetronome()
        
    }
    
    private func createBusNode(for bus: MixerBus) -> BusAudioNode {
        let busNode = BusAudioNode(busId: bus.id)
        
        // Ensure engine is running before attaching nodes
        if !engine.isRunning {
            engine.prepare()
        }
        
        // Attach bus nodes to engine
        engine.attach(busNode.getInputNode())
        engine.attach(busNode.getOutputNode())
        
        // Connect bus output to main mixer with device format
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        engine.connect(busNode.getOutputNode(), to: mixer, format: deviceFormat)
        
        // Apply bus settings from project (WYSIWYG: respect saved mute/levels)
        busNode.inputGain = Float(bus.inputLevel)
        busNode.outputGain = Float(bus.outputLevel)
        busNode.isMuted = bus.isMuted
        busNode.isSolo = bus.isSolo
        
        // Enable level monitoring
        busNode.startLevelMonitoring()
        
        // Wire the bus chain immediately
        rebuildBusChain(busNode)
        
        return busNode
    }
    
    // MARK: - Bus CRUD Operations
    
    func addBus(_ bus: MixerBus) {
        guard busNodes[bus.id] == nil else { return }
        
        let busNode = createBusNode(for: bus)
        busNodes[bus.id] = busNode
        
        // Note: Bus plugins are now managed via TrackPluginManager/PluginChain
        
        // Enable level monitoring
        busNode.startLevelMonitoring()
        
        // Wire the bus chain
        rebuildBusChain(busNode)
    }
    
    /// Reconnect all bus nodes after the engine was reset (e.g. output device change).
    /// After reset(), nodes remain attached; only reattach if detached, then reconnect.
    func reconnectAllBusesAfterEngineReset(deviceFormat: AVAudioFormat) {
        for (_, busNode) in busNodes {
            if busNode.getInputNode().engine == nil {
                engine.attach(busNode.getInputNode())
            }
            if busNode.getOutputNode().engine == nil {
                engine.attach(busNode.getOutputNode())
            }
            busNode.pluginChain.install(in: engine, format: deviceFormat)
            engine.connect(busNode.getOutputNode(), to: mixer, format: deviceFormat)
            rebuildBusChainInternal(busNode, format: deviceFormat)
            if busNode.pluginChain.inputMixer.engine != nil {
                engine.connect(busNode.pluginChain.outputMixer, to: busNode.getOutputNode(), format: deviceFormat)
            }
        }
    }
    
    /// Restore track sends after engine reset without using modifyGraphSafely.
    /// Call from AudioEngine.handleAudioConfigurationChange after reconnectAllBusesAfterEngineReset.
    func restoreTrackSendsAfterReset(project: AudioProject, deviceFormat: AVAudioFormat) {
        for (trackIndex, track) in project.tracks.enumerated() {
            var validSends: [(busId: UUID, level: Double)] = []
            for trackSend in track.sends where trackSend.busId != UUID() {
                if busNodes[trackSend.busId] != nil {
                    validSends.append((busId: trackSend.busId, level: trackSend.sendLevel))
                }
            }
            if validSends.isEmpty { continue }
            guard let trackNode = trackNodesAccessor()[track.id] else { continue }
            var connectionPoints: [AVAudioConnectionPoint] = []
            let trackBusNumber = AVAudioNodeBus(trackIndex)
            connectionPoints.append(AVAudioConnectionPoint(node: mixer, bus: trackBusNumber))
            var busIndexLookup: [UUID: AVAudioNodeBus] = [:]
            for send in validSends {
                guard let busNode = busNodes[send.busId] else { continue }
                let inBus = busNode.getInputNode().nextAvailableInputBus
                busIndexLookup[send.busId] = inBus
                connectionPoints.append(AVAudioConnectionPoint(node: busNode.getInputNode(), bus: inBus))
            }
            engine.connect(trackNode.panNode, to: connectionPoints, fromBus: 0, format: deviceFormat)
            for send in validSends {
                guard let busNode = busNodes[send.busId],
                      let mixing = trackNode.panNode as? AVAudioMixing,
                      let inBus = busIndexLookup[send.busId] else { continue }
                let sendMixer = busNode.getInputNode()
                if let dest = mixing.destination(forMixer: sendMixer, bus: inBus) {
                    dest.volume = Float(send.level)
                    let key = "\(track.id)-\(send.busId)"
                    trackSendIds[key] = UUID()
                    trackSendInputBus[key] = inBus
                }
            }
        }
        updateSoloState()
    }
    
    func removeBus(withId busId: UUID) {
        guard let busNode = busNodes[busId] else { return }
        
        // Clean up all sends pointing to this bus from all tracks
        for trackId in trackNodesAccessor().keys {
            removeTrackSend(trackId, from: busId)
        }
        
        // Clean up send tracking for this bus
        let sendKeysToRemove = trackSendIds.keys.filter { $0.hasSuffix("-\(busId.uuidString)") }
        for key in sendKeysToRemove {
            trackSendIds.removeValue(forKey: key)
            trackSendInputBus.removeValue(forKey: key)
        }
        
        // Stop level monitoring
        busNode.stopLevelMonitoring()
        
        // Note: Bus plugins are now managed via pluginChain.detachAllPlugins()
        
        // Disconnect and detach bus nodes
        engine.disconnectNodeInput(busNode.getInputNode())
        engine.disconnectNodeOutput(busNode.getInputNode())
        engine.disconnectNodeInput(busNode.getOutputNode())
        engine.disconnectNodeOutput(busNode.getOutputNode())
        engine.detach(busNode.getInputNode())
        engine.detach(busNode.getOutputNode())
        
        // Remove from collection
        busNodes.removeValue(forKey: busId)
    }
    
    private func clearAllBuses() {
        // Clear all send connections first
        for sendKey in trackSendIds.keys {
            let components = sendKey.split(separator: "-")
            if components.count == 2,
               let trackId = UUID(uuidString: String(components[0])),
               let busId = UUID(uuidString: String(components[1])) {
                removeTrackSend(trackId, from: busId)
            }
        }
        
        for (_, busNode) in busNodes {
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
        }
        
        busNodes.removeAll()
        trackSendIds.removeAll()
        trackSendInputBus.removeAll()
    }
    
    // MARK: - Bus Plugins (uses same plugin system as tracks)
    // Note: Bus plugin management should use TrackPluginManager or similar service
    
    // MARK: - Bus Plugin Chain Management (AU/VST)
    
    func getBusPluginChain(for busId: UUID) -> PluginChain? {
        return busNodes[busId]?.pluginChain
    }
    
    func insertBusPlugin(busId: UUID, descriptor: PluginDescriptor, atSlot slot: Int, sandboxed: Bool = false) async throws {
        // Set flag to prevent playback during plugin installation
        setIsInstallingPlugin(true)
        
        defer { setIsInstallingPlugin(false) }
        
        guard let busNode = busNodes[busId] else { return }
        
        // Capture format BEFORE stopping engine
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        
        // Install and realize plugin chain if not already
        if !busNode.pluginChain.isRealized {
            let engineWasRunning = engine.isRunning
            if engineWasRunning {
                engine.stop()
            }
            
            // Install engine reference if needed
            if busNode.pluginChain.state == .uninstalled {
                busNode.pluginChain.install(in: engine, format: deviceFormat)
            }
            
            // Realize the chain (creates and attaches mixers)
            busNode.pluginChain.realize()
            
            // Connect bus input → plugin chain → bus output
            engine.disconnectNodeOutput(busNode.getInputNode())
            
            engine.connect(busNode.getInputNode(), to: busNode.pluginChain.inputMixer, format: deviceFormat)
            engine.connect(busNode.pluginChain.outputMixer, to: busNode.getOutputNode(), format: deviceFormat)
            
            engine.prepare()
            if engineWasRunning {
                try? engine.start()
            }
            
            setupPositionTimer()
        }
        
        // Create and load plugin instance
        let instance = PluginInstanceManager.shared.createInstance(from: descriptor)
        
        // Get hardware sample rate from engine output node
        let sampleRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        
        if sandboxed {
            try await instance.loadSandboxed(sampleRate: sampleRate)
        } else {
            try await instance.load(sampleRate: sampleRate)
        }
        
        guard instance.avAudioUnit != nil else { return }
        
        // Graph modifications on main thread
        let engineWasRunning = engine.isRunning
        if engineWasRunning {
            engine.stop()
        }
        
        busNode.pluginChain.storePlugin(instance, atSlot: slot)
        busNode.pluginChain.rebuildChainConnections(engine: engine)
        
        engine.prepare()
        if engineWasRunning {
            try? engine.start()
        }
        
        setupPositionTimer()
        
        // Configure reverb plugins for aux send use (100% wet)
        if descriptor.name.lowercased().contains("reverb") {
            instance.setParameter(address: 0, value: 100.0)
        }
    }
    
    func removeBusPlugin(busId: UUID, atSlot slot: Int) {
        guard let pluginChain = busNodes[busId]?.pluginChain else { return }
        
        if let instance = pluginChain.slots[slot] {
            PluginInstanceManager.shared.removeInstance(instance)
        }
        pluginChain.removePlugin(atSlot: slot)
    }
    
    func openBusPluginEditor(busId: UUID, slot: Int, audioEngine: AudioEngine) {
        guard let pluginChain = busNodes[busId]?.pluginChain,
              let instance = pluginChain.slots[slot] else { return }
        PluginEditorWindow.open(for: instance, audioEngine: audioEngine)
    }
    
    // MARK: - Track Send Management
    
    func setupTrackSend(_ trackId: UUID, to busId: UUID, level: Double, isPreFader: Bool = false) {
        let sendKey = "\(trackId)-\(busId)"
        
        // Prevent duplicate setup - if this send already exists, just update the level
        if trackSendIds[sendKey] != nil {
            updateTrackSendLevel(trackId, busId: busId, level: level)
            return
        }
        
        // Validate bus exists
        guard busNodes[busId] != nil else {
            AppLogger.shared.warning("Cannot create send: bus \(busId) does not exist", category: .audio)
            return
        }
        
        // Prevent circular routing
        if hasCircularRouting(from: trackId, to: busId) {
            AppLogger.shared.warning("Cannot create send: circular routing detected from track \(trackId) to bus \(busId)", category: .audio)
            return
        }
        
        // Prevent self-routing (bus sending to itself)
        guard let project = currentProjectAccessor(),
              let track = project.tracks.first(where: { $0.id == trackId }) else { return }
        
        if track.trackType == .bus && track.id == busId {
            AppLogger.shared.warning("Cannot create send: bus cannot send to itself", category: .audio)
            return
        }
        
        guard let trackNode = trackNodesAccessor()[trackId],
              let busNode = busNodes[busId],
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        let sendMixer = busNode.getInputNode()
        let trackBusNumber = AVAudioNodeBus(trackIndex)
        let inBus = sendMixer.nextAvailableInputBus
        
        // CRITICAL: Choose tap point based on pre/post-fader setting
        // Signal flow: playerNode → plugins → volumeNode → panNode → mixer
        // Pre-fader: Tap AFTER plugins/volume but BEFORE track fader is applied to send
        // Post-fader: Tap AFTER volume/pan (normal behavior)
        let tapNode = isPreFader ? trackNode.volumeNode : trackNode.panNode
        
        modifyGraphSafely { [self] in
            let mainConnectionPoint = AVAudioConnectionPoint(node: mixer, bus: trackBusNumber)
            let sendConnectionPoint = AVAudioConnectionPoint(node: sendMixer, bus: inBus)
            
            if isPreFader {
                // Pre-fader: Split signal after volumeNode
                // volumeNode → [panNode (normal flow), sendBus]
                engine.disconnectNodeOutput(trackNode.volumeNode)
                engine.connect(
                    trackNode.volumeNode,
                    to: [
                        AVAudioConnectionPoint(node: trackNode.panNode, bus: 0),
                        sendConnectionPoint
                    ],
                    fromBus: 0,
                    format: deviceFormat
                )
            } else {
                // Post-fader: Split signal after panNode (current behavior)
                // panNode → [mixer, sendBus]
                engine.disconnectNodeOutput(trackNode.panNode)
                engine.connect(
                    trackNode.panNode,
                    to: [mainConnectionPoint, sendConnectionPoint],
                    fromBus: 0,
                    format: deviceFormat
                )
            }
            
            trackSendIds[sendKey] = UUID()
            trackSendInputBus[sendKey] = inBus
        }
        
        // Set send level immediately after graph mutation completes
        // The engine is now running again and the connection is established
        if let mixing = tapNode as? AVAudioMixing,
           let destination = mixing.destination(forMixer: sendMixer, bus: inBus) {
            destination.volume = Float(level)
        }
    }
    
    func updateTrackSendLevel(_ trackId: UUID, busId: UUID, level: Double) {
        let sendKey = "\(trackId)-\(busId)"
        guard let inBus = trackSendInputBus[sendKey],
              let trackNode = trackNodesAccessor()[trackId],
              let busNode = busNodes[busId],
              let mixing = trackNode.panNode as? AVAudioMixing,
              let dest = mixing.destination(forMixer: busNode.getInputNode(), bus: inBus) else { return }
        
        dest.volume = Float(level)
    }
    
    func removeTrackSend(_ trackId: UUID, from busId: UUID) {
        let sendKey = "\(trackId)-\(busId)"
        
        guard trackSendIds[sendKey] != nil,
              let trackNode = trackNodesAccessor()[trackId],
              let project = currentProjectAccessor(),
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        let trackBusNumber = AVAudioNodeBus(trackIndex)
        
        modifyGraphSafely { [self] in
            let mainConnectionPoint = AVAudioConnectionPoint(node: mixer, bus: trackBusNumber)
            
            engine.disconnectNodeOutput(trackNode.panNode)
            engine.connect(
                trackNode.panNode,
                to: [mainConnectionPoint],
                fromBus: 0,
                format: deviceFormat
            )
        }
        
        trackSendIds.removeValue(forKey: sendKey)
        trackSendInputBus.removeValue(forKey: sendKey)
    }
    
    private func restoreTrackSendsForProject(_ project: AudioProject) {
        
        for (trackIndex, track) in project.tracks.enumerated() {
            var validSends: [(busId: UUID, level: Double)] = []
            
            for trackSend in track.sends {
                if trackSend.busId != UUID() {
                    if busNodes[trackSend.busId] != nil {
                        validSends.append((busId: trackSend.busId, level: trackSend.sendLevel))
                    }
                }
            }
            
            if !validSends.isEmpty {
                setupMultipleTrackSends(track.id, trackIndex: trackIndex, sends: validSends)
            }
        }
        
    }
    
    private func setupMultipleTrackSends(_ trackId: UUID, trackIndex: Int, sends: [(busId: UUID, level: Double)]) {
        
        guard let trackNode = trackNodesAccessor()[trackId] else {
            return
        }
        
        var connectionPoints: [AVAudioConnectionPoint] = []
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        let trackBusNumber = AVAudioNodeBus(trackIndex)
        
        connectionPoints.append(AVAudioConnectionPoint(node: mixer, bus: trackBusNumber))
        
        var busIndexLookup: [UUID: AVAudioNodeBus] = [:]
        for (idx, send) in sends.enumerated() {
            guard let busNode = busNodes[send.busId] else {
                continue
            }
            let sendMixer = busNode.getInputNode()
            let inBus = sendMixer.nextAvailableInputBus
            busIndexLookup[send.busId] = inBus
            connectionPoints.append(AVAudioConnectionPoint(node: sendMixer, bus: inBus))
        }
        
        
        modifyGraphSafely { [self] in
            engine.disconnectNodeOutput(trackNode.panNode)
            engine.connect(trackNode.panNode, to: connectionPoints, fromBus: 0, format: deviceFormat)
            
            // Rebuild bus chains INSIDE the same stopped state
            for (idx, send) in sends.enumerated() {
                guard let busNode = busNodes[send.busId] else { continue }
                
                let inNode = busNode.getInputNode()
                let outNode = busNode.getOutputNode()
                let busFormat = engine.outputNode.inputFormat(forBus: 0)
                
                engine.disconnectNodeOutput(inNode)
                engine.disconnectNodeOutput(outNode)
                
                // Bus plugins are managed via pluginChain
                let pluginChainInstalled = busNode.pluginChain.inputMixer.engine != nil
                
                if pluginChainInstalled {
                    // Connect through plugin chain
                    engine.connect(inNode, to: busNode.pluginChain.inputMixer, format: busFormat)
                    engine.connect(busNode.pluginChain.outputMixer, to: outNode, format: busFormat)
                } else {
                    // Direct connection
                    engine.connect(inNode, to: outNode, format: busFormat)
                }
                
                engine.connect(outNode, to: mixer, format: busFormat)
            }
        }
        
        // Set per-destination volumes AFTER the engine restarts
        for send in sends {
            guard let busNode = busNodes[send.busId],
                  let mixing = trackNode.panNode as? AVAudioMixing,
                  let inBus = busIndexLookup[send.busId] else { continue }
            
            let sendMixer = busNode.getInputNode()
            if let dest = mixing.destination(forMixer: sendMixer, bus: inBus) {
                dest.volume = Float(send.level)
                let key = "\(trackId)-\(send.busId)"
                trackSendIds[key] = UUID()
                trackSendInputBus[key] = inBus
            }
        }
    }
    
    // MARK: - Routing Validation
    
    /// Check if adding a send from sourceTrackId to targetBusId would create circular routing.
    /// Uses depth-first search to detect cycles in the bus routing graph.
    private func hasCircularRouting(from sourceTrackId: UUID, to targetBusId: UUID) -> Bool {
        guard let project = currentProjectAccessor() else { return false }
        
        // Build routing graph: track/bus ID -> set of destination bus IDs
        var routingGraph: [UUID: Set<UUID>] = [:]
        
        for track in project.tracks {
            var destinations = Set<UUID>()
            for send in track.sends where send.busId != UUID() {
                destinations.insert(send.busId)
            }
            routingGraph[track.id] = destinations
        }
        
        // Add the proposed new send to the graph
        var proposedDestinations = routingGraph[sourceTrackId] ?? Set<UUID>()
        proposedDestinations.insert(targetBusId)
        routingGraph[sourceTrackId] = proposedDestinations
        
        // Check if targetBusId can route back to sourceTrackId (cycle detection)
        return canReach(from: targetBusId, to: sourceTrackId, in: routingGraph, visited: Set<UUID>())
    }
    
    /// Depth-first search to check if we can reach 'target' from 'current' node.
    private func canReach(from current: UUID, to target: UUID, in graph: [UUID: Set<UUID>], visited: Set<UUID>) -> Bool {
        // If we've already visited this node, no cycle through this path
        if visited.contains(current) {
            return false
        }
        
        var newVisited = visited
        newVisited.insert(current)
        
        // Get destinations from current node
        guard let destinations = graph[current] else {
            return false
        }
        
        // Check direct connection
        if destinations.contains(target) {
            return true
        }
        
        // Check indirect connections (recursive DFS)
        for destination in destinations {
            if canReach(from: destination, to: target, in: graph, visited: newVisited) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Bus Chain Rebuild
    
    private func rebuildBusChain(_ bus: BusAudioNode) {
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        
        if transportStateAccessor().isPlaying {
            modifyGraphSafely { [self] in
                rebuildBusChainInternal(bus, format: deviceFormat)
            }
        } else {
            rebuildBusChainInternal(bus, format: deviceFormat)
        }
    }
    
    private func rebuildBusChainInternal(_ bus: BusAudioNode, format deviceFormat: AVAudioFormat) {
        let inNode = bus.getInputNode()
        let outNode = bus.getOutputNode()
        
        let pluginChainInstalled = bus.pluginChain.inputMixer.engine != nil
        
        engine.disconnectNodeOutput(inNode)
        
        // Bus plugins are managed via pluginChain (same as tracks)
        if pluginChainInstalled {
            // Connect through plugin chain
            engine.connect(inNode, to: bus.pluginChain.inputMixer, format: deviceFormat)
            // Plugin chain's output is connected to outNode elsewhere
        } else {
            // Direct connection (no plugins)
            engine.connect(inNode, to: outNode, format: deviceFormat)
        }
    }
    
    // MARK: - Bus Output Level
    
    func updateBusOutputLevel(_ busId: UUID, outputLevel: Double) {
        if let busNode = busNodes[busId] {
            busNode.outputGain = Float(outputLevel)
        }
    }
    
    // MARK: - Bus Node Access (for Export)
    
    func getBusNode(for busId: UUID) -> BusAudioNode? {
        return busNodes[busId]
    }
    
    func getAllBusNodes() -> [UUID: BusAudioNode] {
        return busNodes
    }
    
    func getTrackSends(for trackId: UUID) -> [(busId: UUID, level: Float)] {
        var sends: [(busId: UUID, level: Float)] = []
        
        guard let trackNode = trackNodesAccessor()[trackId],
              let mixing = trackNode.panNode as? AVAudioMixing else {
            return sends
        }
        
        for sendKey in trackSendIds.keys {
            let components = sendKey.split(separator: "-")
            guard components.count == 2,
                  let sendTrackId = UUID(uuidString: String(components[0])),
                  let busId = UUID(uuidString: String(components[1])),
                  sendTrackId == trackId,
                  let inBus = trackSendInputBus[sendKey],
                  let busNode = busNodes[busId] else {
                continue
            }
            
            if let dest = mixing.destination(forMixer: busNode.getInputNode(), bus: inBus) {
                sends.append((busId: busId, level: dest.volume))
            }
        }
        
        return sends
    }
}
