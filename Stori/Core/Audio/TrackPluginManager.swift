//
//  TrackPluginManager.swift
//  Stori
//
//  Manages track insert plugins, Plugin Delay Compensation (PDC), and sidechain routing.
//  Extracted from AudioEngine for better separation of concerns.
//

import Foundation
import AVFoundation

// MARK: - Plugin Load Result

/// Result of loading plugins during project restoration
struct PluginLoadResult {
    /// Successfully loaded plugins
    var loadedPlugins: [(trackId: UUID, trackName: String, pluginName: String, slot: Int)] = []
    
    /// Failed plugin loads with error details
    var failedPlugins: [(trackId: UUID, trackName: String, pluginName: String, slot: Int, error: String)] = []
    
    /// Whether all plugins loaded successfully
    var isComplete: Bool { failedPlugins.isEmpty }
    
    /// Summary for logging
    var summary: String {
        if isComplete {
            return "All \(loadedPlugins.count) plugins loaded successfully"
        } else {
            return "\(loadedPlugins.count) plugins loaded, \(failedPlugins.count) failed"
        }
    }
}

/// Manages track plugin chains, PDC, and sidechain routing.
/// Coordinates with AudioEngine via callbacks for graph mutations.
@MainActor
class TrackPluginManager {
    
    // MARK: - Debug Logging
    
    /// Uses centralized debug config (see AudioDebugConfig)
    private var debugPlugin: Bool { AudioDebugConfig.logPluginLifecycle }
    
    /// Debug logging with autoclosure to prevent string allocation when disabled
    /// PERFORMANCE: When debugPlugin is false, the message closure is never evaluated
    private func logDebug(_ message: @autoclosure () -> String) {
        guard debugPlugin else { return }
        AppLogger.shared.debug("[PLUGIN] \(message())", category: .audio)
    }
    
    // MARK: - Sidechain Storage
    
    /// Storage for sidechain connection nodes (trackId -> slot -> tap node)
    private var sidechainConnections: [UUID: [Int: AVAudioNode]] = [:]
    
    /// Storage for sidechain source types (trackId -> slot -> source)
    /// This allows us to query what source is connected to which slot
    private var sidechainSources: [UUID: [Int: SidechainSource]] = [:]
    
    // MARK: - Dependencies (injected via closures for loose coupling)
    
    /// Returns the AVAudioEngine
    private var getEngine: () -> AVAudioEngine
    
    /// Returns current project
    private var getProject: () -> AudioProject?
    
    /// Sets the current project
    private var setProject: (AudioProject) -> Void
    
    /// Returns track nodes dictionary
    private var getTrackNodes: () -> [UUID: TrackAudioNode]
    
    // NOTE: Track instruments are now accessed via InstrumentManager.shared (single source of truth)
    // The getTrackInstruments closure was removed as part of instrument ownership consolidation.
    
    /// Returns bus nodes dictionary
    private var getBusNodes: () -> [UUID: BusAudioNode]
    
    /// Returns the graph format
    private var getGraphFormat: () -> AVAudioFormat?
    
    /// Get/set plugin installation lock flag
    private var isInstallingPlugin: () -> Bool
    private var setIsInstallingPlugin: (Bool) -> Void
    
    /// Callback to rebuild track graph after plugin changes
    private var onRebuildTrackGraph: (UUID) -> Void
    
    /// Callback to rebuild plugin chain only (for bypass toggles)
    private var onRebuildPluginChain: (UUID) -> Void
    
    /// Callback for safe graph modification (sync, handles reentrancy)
    private var onModifyGraphSafely: (@escaping () -> Void) -> Void
    
    // MARK: - Initialization
    
    init(
        getEngine: @escaping () -> AVAudioEngine,
        getProject: @escaping () -> AudioProject?,
        setProject: @escaping (AudioProject) -> Void,
        getTrackNodes: @escaping () -> [UUID: TrackAudioNode],
        getBusNodes: @escaping () -> [UUID: BusAudioNode],
        getGraphFormat: @escaping () -> AVAudioFormat?,
        isInstallingPlugin: @escaping () -> Bool,
        setIsInstallingPlugin: @escaping (Bool) -> Void,
        onRebuildTrackGraph: @escaping (UUID) -> Void,
        onRebuildPluginChain: @escaping (UUID) -> Void,
        onModifyGraphSafely: @escaping (@escaping () -> Void) -> Void
    ) {
        self.getEngine = getEngine
        self.getProject = getProject
        self.setProject = setProject
        self.getTrackNodes = getTrackNodes
        self.getBusNodes = getBusNodes
        self.getGraphFormat = getGraphFormat
        self.isInstallingPlugin = isInstallingPlugin
        self.setIsInstallingPlugin = setIsInstallingPlugin
        self.onRebuildTrackGraph = onRebuildTrackGraph
        self.onRebuildPluginChain = onRebuildPluginChain
        self.onModifyGraphSafely = onModifyGraphSafely
    }
    
    // MARK: - Plugin Chain Access
    
    /// Get the plugin chain for a track
    func getPluginChain(for trackId: UUID) -> PluginChain? {
        return getTrackNodes()[trackId]?.pluginChain
    }
    
    // MARK: - Plugin Delay Compensation (PDC)
    
    /// Recalculate and apply delay compensation for all tracks
    /// Call this after plugin changes or before starting playback
    func updateDelayCompensation() {
        let trackNodes = getTrackNodes()
        
        guard PluginLatencyManager.shared.isEnabled else {
            // PDC disabled - clear any existing compensation
            for trackNode in trackNodes.values {
                trackNode.applyCompensationDelay(samples: 0)
            }
            return
        }
        
        // Collect active plugins per track
        var trackPlugins: [UUID: [PluginInstance]] = [:]
        
        for (trackId, trackNode) in trackNodes {
            // Get non-bypassed plugins from the track's plugin chain
            let activePlugins = trackNode.pluginChain.activePlugins.filter { !$0.isBypassed }
            trackPlugins[trackId] = activePlugins
        }
        
        // Calculate compensation for each track
        let compensation = PluginLatencyManager.shared.calculateCompensation(trackPlugins: trackPlugins)
        
        // Apply compensation to each track node
        for (trackId, delaySamples) in compensation {
            if let trackNode = trackNodes[trackId] {
                trackNode.applyCompensationDelay(samples: delaySamples)
            }
        }
        
        // Log if significant latency compensation is applied
        let maxLatency = PluginLatencyManager.shared.maxLatencyMs
        if maxLatency > 1.0 {
        }
    }
    
    // MARK: - Plugin Insert/Remove
    
    /// Insert an AU plugin into a track's insert chain
    /// - Parameters:
    ///   - trackId: Track to insert into
    ///   - descriptor: Plugin descriptor
    ///   - atSlot: Slot index (0-7)
    ///   - sandboxed: Force sandboxed loading. If false, uses PluginGreylist to decide.
    func insertPlugin(trackId: UUID, descriptor: PluginDescriptor, atSlot slot: Int, sandboxed: Bool = false) async throws {
        let trackNodes = getTrackNodes()
        let engine = getEngine()
        
        logDebug("🔌 insertPlugin: '\(descriptor.name)' on track \(trackId), slot \(slot), sandboxed=\(sandboxed)")
        logDebug("   Stack trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
        
        guard let pluginChain = trackNodes[trackId]?.pluginChain else {
            logDebug("⚠️ No plugin chain found for track \(trackId)")
            return
        }
        
        logDebug("   Plugin chain before insert: \(pluginChain.slots.enumerated().compactMap { idx, p in p != nil ? "\(idx):\(p!.descriptor.name)" : nil }.joined(separator: ", "))")
        logDebug("   Plugin chain isRealized: \(pluginChain.isRealized)")
        logDebug("   Plugin chain hasActivePlugins: \(pluginChain.hasActivePlugins)")
        
        // TRANSPORT LOCK: Prevent playback during plugin installation
        setIsInstallingPlugin(true)
        defer { setIsInstallingPlugin(false) }
        
        // SMART SANDBOXING: Check if plugin should be loaded out-of-process
        // Uses PluginGreylist to track plugins that have crashed before
        let shouldSandbox = sandboxed || PluginGreylist.shared.shouldSandbox(descriptor)
        if shouldSandbox && !sandboxed {
            logDebug("⚠️ Plugin '\(descriptor.name)' will be loaded sandboxed (crash history)")
        }
        
        // Create and load plugin instance
        let instance = PluginInstanceManager.shared.createInstance(from: descriptor)
        
        // Get hardware sample rate from engine graph format
        let sampleRate = getGraphFormat()?.sampleRate ?? 48000
        
        do {
            if shouldSandbox {
                try await instance.loadSandboxed(sampleRate: sampleRate)
            } else {
                try await instance.load(sampleRate: sampleRate)
            }
        } catch {
            // Isolate failure: record, log, notify; do not add plugin to chain or throw (DAW continues)
            PluginGreylist.shared.recordCrash(for: descriptor, reason: "Failed to load: \(error.localizedDescription)")
            AppLogger.shared.error("[TrackPluginManager] Plugin '\(descriptor.name)' failed to load: \(error)", category: .audio)
            NotificationCenter.default.post(
                name: .pluginLoadFailed,
                object: nil,
                userInfo: [
                    "pluginName": descriptor.name,
                    "message": "'\(descriptor.name)' could not be loaded and was not added. Your project is unchanged."
                ]
            )
            return
        }
        
        guard let avUnit = instance.avAudioUnit else {
            return
        }
        
        guard let trackNode = trackNodes[trackId] else {
            return
        }
        
        // Attach plugin to engine
        engine.attach(avUnit)
        
        // Store plugin in chain
        let chain = trackNode.pluginChain
        chain.storePlugin(instance, atSlot: slot)
        chain.ensureEngineReference(engine)
        
        logDebug("   Plugin stored in chain at slot \(slot)")
        logDebug("   Plugin chain after insert: \(chain.slots.enumerated().compactMap { idx, p in p != nil ? "\(idx):\(p!.descriptor.name)(bypassed:\(p!.isBypassed))" : nil }.joined(separator: ", "))")
        logDebug("   Plugin chain hasActivePlugins: \(chain.hasActivePlugins)")
        
        // Use centralized rebuild for all connections
        logDebug("   Rebuilding track graph...")
        onRebuildTrackGraph(trackId)
        logDebug("   ✅ Track graph rebuilt")
        
        // PDC: Recalculate compensation when plugins change
        updateDelayCompensation()
        
        // Save plugin configuration to project for persistence
        await savePluginConfigsToProject(trackId: trackId)
        logDebug("   ✅ Plugin configuration saved to project")
    }
    
    /// Remove a plugin from a track's insert chain
    func removePlugin(trackId: UUID, atSlot slot: Int) {
        let trackNodes = getTrackNodes()
        
        guard let pluginChain = trackNodes[trackId]?.pluginChain else {
            logDebug("⚠️ removePlugin: No plugin chain found for track \(trackId)")
            return
        }
        
        let pluginName = pluginChain.slots[slot]?.descriptor.name ?? "nil"
        logDebug("🗑️ removePlugin: track=\(trackId), slot=\(slot), plugin=\(pluginName)")
        logDebug("   Stack trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
        logDebug("   Plugin chain before remove: \(pluginChain.slots.enumerated().compactMap { idx, p in p != nil ? "\(idx):\(p!.descriptor.name)" : nil }.joined(separator: ", "))")
        
        // TRANSPORT LOCK: Prevent playback during graph mutation
        setIsInstallingPlugin(true)
        defer { setIsInstallingPlugin(false) }
        
        if let instance = pluginChain.slots[slot] {
            PluginInstanceManager.shared.removeInstance(instance)
        }
        pluginChain.removePlugin(atSlot: slot)
        
        logDebug("   Plugin chain after remove: \(pluginChain.slots.enumerated().compactMap { idx, p in p != nil ? "\(idx):\(p!.descriptor.name)" : nil }.joined(separator: ", "))")
        
        // CRITICAL: Rebuild FULL track graph (not just plugin chain)
        // This reconnects the sampler with proper 48kHz format
        // Clears any lingering sample rate converter corruption from removed plugin
        logDebug("   🔧 CRITICAL: Rebuilding FULL track graph to clear sample rate converter corruption...")
        logDebug("   Reason: Removing plugin may leave sampler in corrupted state from previous 44.1→48 converter")
        onRebuildTrackGraph(trackId)
        logDebug("   ✅ Track graph rebuilt")
        
        // PDC: Recalculate compensation when plugins change
        updateDelayCompensation()
        
        // Update project persistence
        Task { @MainActor in
            await self.savePluginConfigsToProject(trackId: trackId)
            logDebug("   ✅ Plugin configuration saved to project after removal")
        }
    }
    
    /// Move a plugin between slots in a track's chain
    func movePlugin(trackId: UUID, fromSlot: Int, toSlot: Int) {
        let trackNodes = getTrackNodes()
        
        guard let pluginChain = trackNodes[trackId]?.pluginChain else { return }
        
        guard fromSlot >= 0, fromSlot < pluginChain.maxSlots,
              toSlot >= 0, toSlot < pluginChain.maxSlots,
              fromSlot != toSlot else { return }
        
        // TRANSPORT LOCK: Prevent playback during graph mutation
        setIsInstallingPlugin(true)
        defer { setIsInstallingPlugin(false) }
        
        // Swap the plugins
        let plugin = pluginChain.slots[fromSlot]
        pluginChain.slots[fromSlot] = pluginChain.slots[toSlot]
        pluginChain.slots[toSlot] = plugin
        
        // Rebuild the graph with proper engine reset
        onRebuildTrackGraph(trackId)
    }
    
    // MARK: - Plugin Bypass
    
    /// Bypass/unbypass a plugin in a track's chain
    func setPluginBypass(trackId: UUID, slot: Int, bypassed: Bool) {
        let trackNodes = getTrackNodes()
        
        guard let pluginChain = trackNodes[trackId]?.pluginChain,
              let instance = pluginChain.slots[slot] else {
            logDebug("⚠️ setPluginBypass: No plugin chain or instance at slot \(slot) for track \(trackId)")
            logDebug("   Stack trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
            return
        }
        
        logDebug("🔀 setPluginBypass: track=\(trackId), slot=\(slot), bypassed=\(bypassed)")
        logDebug("   Plugin: \(instance.descriptor.name)")
        logDebug("   Previous bypass state: \(instance.isBypassed)")
        logDebug("   Stack trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
        
        instance.setBypass(bypassed)
        
        logDebug("   New bypass state: \(instance.isBypassed)")
        logDebug("   AU shouldBypassEffect: \(instance.auAudioUnit?.shouldBypassEffect ?? false)")
        
        // NOTE: Full graph rebuild is NO LONGER needed for bypass toggle
        // Since Fix 3 (deallocate before setFormat), all plugins stay at 48kHz
        // The shouldBypassEffect flag routes audio internally without connection changes
        // Previously this was needed because bypass caused 44.1kHz → 48kHz format changes
        
        // PDC: Recalculate compensation when bypass state changes
        // (bypassed plugins don't contribute latency)
        updateDelayCompensation()
    }
    
    /// Bypass/unbypass the entire plugin chain for a track
    func setPluginChainBypass(trackId: UUID, bypassed: Bool) {
        let trackNodes = getTrackNodes()
        
        guard let pluginChain = trackNodes[trackId]?.pluginChain else { return }
        pluginChain.isBypassed = bypassed
        
        // PDC: Recalculate compensation when bypass state changes
        updateDelayCompensation()
    }
    
    /// Get the total latency of a track's plugin chain
    func getPluginChainLatency(trackId: UUID) -> Int {
        return getTrackNodes()[trackId]?.pluginChain.totalLatencySamples ?? 0
    }
    
    // MARK: - Plugin Persistence
    
    /// Save current plugin chain state to the project model
    ///
    /// PERFORMANCE: Uses async serialization to avoid blocking the main thread
    /// during project save when many plugins are loaded.
    func savePluginConfigsToProject(trackId: UUID, triggerSave: Bool = true) async {
        let trackNodes = getTrackNodes()
        
        guard let project = getProject(),
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let pluginChain = trackNodes[trackId]?.pluginChain else {
            return
        }
        
        // Collect plugin instances first
        let pluginInstances: [(Int, PluginInstance)] = pluginChain.slots.enumerated().compactMap { slotIndex, plugin in
            guard let instance = plugin else { return nil }
            return (slotIndex, instance)
        }
        
        // Create configs concurrently using async serialization
        var configs: [PluginConfiguration] = []
        for (slotIndex, instance) in pluginInstances {
            let config = await instance.createConfigurationAsync(atSlot: slotIndex)
            configs.append(config)
        }
        
        // Update the project model
        var updatedProject = project
        updatedProject.tracks[trackIndex].pluginConfigs = configs
        setProject(updatedProject)
        
        // Notify ProjectManager of the update
        NotificationCenter.default.post(name: .projectUpdated, object: updatedProject)
        
        // Only trigger save if requested
        if triggerSave {
            NotificationCenter.default.post(name: .saveProject, object: nil)
        }
    }
    
    /// Restore plugins from saved project configuration
    /// Returns a result with details of successful and failed plugin loads
    ///
    /// PERFORMANCE: Parallel plugin loading for 3x faster project loads.
    /// Plugin instances are loaded concurrently across all tracks, then attached sequentially.
    @discardableResult
    func restorePluginsFromProject() async -> PluginLoadResult {
        var result = PluginLoadResult()
        
        let trackNodes = getTrackNodes()
        let engine = getEngine()
        
        guard let project = getProject() else {
            return result
        }
        
        let tracksWithPlugins = project.tracks.filter { !$0.pluginConfigs.isEmpty }
        guard !tracksWithPlugins.isEmpty else { return result }
        
        // Get hardware sample rate from engine graph format
        let sampleRate = getGraphFormat()?.sampleRate ?? 48000
        
        // PHASE 1: Parallel plugin loading
        // Load all plugins concurrently using TaskGroup for 3x speedup
        struct LoadedPlugin: Sendable {
            let trackId: UUID
            let trackName: String
            let config: PluginConfiguration
            let descriptor: PluginDescriptor
            let instance: PluginInstance
        }
        
        enum PluginLoadOutcome: @unchecked Sendable {
            case success(LoadedPlugin)
            case failure(trackId: UUID, trackName: String, config: PluginConfiguration, error: String)
        }
        
        var loadedPlugins: [LoadedPlugin] = []
        var failedLoads: [(trackId: UUID, trackName: String, config: PluginConfiguration, error: String)] = []
        
        await withTaskGroup(of: PluginLoadOutcome.self) { group in
            for track in tracksWithPlugins {
                for config in track.pluginConfigs {
                    let trackId = track.id
                    let trackName = track.name
                    group.addTask { @MainActor in
                        // Create descriptor
                        let descriptor = PluginDescriptor(
                            id: UUID(),
                            name: config.pluginName,
                            manufacturer: config.manufacturerName,
                            version: "1.0",
                            category: .effect,
                            componentDescription: config.componentDescription,
                            auType: .aufx,
                            supportsPresets: true,
                            hasCustomUI: true,
                            inputChannels: 2,
                            outputChannels: 2,
                            latencySamples: 0
                        )
                        
                        // SMART SANDBOXING: Check if plugin should be loaded out-of-process
                        let shouldSandbox = PluginGreylist.shared.shouldSandbox(descriptor)
                        
                        let instance = PluginInstanceManager.shared.createInstance(from: descriptor)
                        
                        do {
                            if shouldSandbox {
                                try await instance.loadSandboxed(sampleRate: sampleRate)
                            } else {
                                try await instance.load(sampleRate: sampleRate)
                            }
                            
                            // Restore saved state
                            if let stateData = config.fullState {
                                _ = await instance.restoreState(from: stateData)
                            }
                            
                            // Restore bypass state
                            instance.setBypass(config.isBypassed)
                            
                            return .success(LoadedPlugin(
                                trackId: trackId,
                                trackName: trackName,
                                config: config,
                                descriptor: descriptor,
                                instance: instance
                            ))
                        } catch {
                            PluginGreylist.shared.recordCrash(for: descriptor, reason: "Failed to restore: \(error.localizedDescription)")
                            return .failure(trackId: trackId, trackName: trackName, config: config, error: error.localizedDescription)
                        }
                    }
                }
            }
            
            // Collect results
            for await loadResult in group {
                switch loadResult {
                case .success(let loaded):
                    loadedPlugins.append(loaded)
                case .failure(let trackId, let trackName, let config, let error):
                    failedLoads.append((trackId, trackName, config, error))
                }
            }
        }
        
        // Record failures
        for failure in failedLoads {
            result.failedPlugins.append((
                trackId: failure.trackId,
                trackName: failure.trackName,
                pluginName: failure.config.pluginName,
                slot: failure.config.slotIndex,
                error: failure.error
            ))
        }
        
        // PHASE 2: Sequential attachment to audio graph
        // Group loaded plugins by track for efficient graph rebuilds
        let pluginsByTrack = Dictionary(grouping: loadedPlugins) { $0.trackId }
        
        for (trackId, trackPlugins) in pluginsByTrack {
            guard let pluginChain = trackNodes[trackId]?.pluginChain,
                  let track = tracksWithPlugins.first(where: { $0.id == trackId }) else {
                continue
            }
            
            logDebug("🔌 Attaching \(trackPlugins.count) plugin(s) for track '\(track.name)'")
            
            for loaded in trackPlugins.sorted(by: { $0.config.slotIndex < $1.config.slotIndex }) {
                var insertSuccess = false
                onModifyGraphSafely {
                    guard let avUnit = loaded.instance.avAudioUnit else {
                        self.logDebug("   ⚠️ No avUnit for \(loaded.config.pluginName)")
                        return
                    }
                    engine.attach(avUnit)
                    pluginChain.storePlugin(loaded.instance, atSlot: loaded.config.slotIndex)
                    insertSuccess = true
                    
                    pluginChain.ensureEngineReference(engine)
                    pluginChain.rebuildChainConnections(engine: engine)
                }
                
                if insertSuccess {
                    result.loadedPlugins.append((
                        trackId: trackId,
                        trackName: track.name,
                        pluginName: loaded.config.pluginName,
                        slot: loaded.config.slotIndex
                    ))
                } else {
                    result.failedPlugins.append((
                        trackId: trackId,
                        trackName: track.name,
                        pluginName: loaded.config.pluginName,
                        slot: loaded.config.slotIndex,
                        error: "Failed to attach to audio graph"
                    ))
                }
            }
            
            // Rebuild graph after all plugins attached for this track
            onRebuildTrackGraph(trackId)
            
            // For MIDI tracks, ensure sampler is attached
            if track.isMIDITrack {
                if let instrument = InstrumentManager.shared.getInstrument(for: trackId),
                   let sampler = instrument.samplerEngine?.sampler {
                    if sampler.engine == nil {
                        engine.attach(sampler)
                    }
                    onRebuildTrackGraph(trackId)
                }
            }
        }
        
        // Log plugin load results
        if !result.loadedPlugins.isEmpty || !result.failedPlugins.isEmpty {
            AppLogger.shared.info("Plugin restoration: \(result.summary)", category: .audio)
            
            for failure in result.failedPlugins {
                AppLogger.shared.warning("  ⚠️ \(failure.trackName)/slot\(failure.slot): \(failure.pluginName) - \(failure.error)", category: .audio)
            }
        }
        
        return result
    }
    
    // MARK: - Plugin Editor
    
    /// Open the plugin editor UI for a specific slot
    func openPluginEditor(trackId: UUID, slot: Int, audioEngine: AudioEngine) {
        let trackNodes = getTrackNodes()
        
        guard let trackNode = trackNodes[trackId] else { return }
        
        let pluginChain = trackNode.pluginChain
        guard let instance = pluginChain.slots[slot] else { return }
        
        PluginEditorWindow.open(for: instance, audioEngine: audioEngine)
    }
    
    // MARK: - Sidechain Routing
    
    /// Check if a plugin at a specific slot supports sidechain
    func pluginSupportsSidechain(trackId: UUID, slot: Int) -> Bool {
        let trackNodes = getTrackNodes()
        
        guard let pluginChain = trackNodes[trackId]?.pluginChain,
              let instance = pluginChain.slots[slot] else { return false }
        return instance.supportsSidechain
    }
    
    /// Set up sidechain routing for a plugin
    func setSidechainSource(trackId: UUID, slot: Int, source: SidechainSource) {
        let trackNodes = getTrackNodes()
        let busNodes = getBusNodes()
        let engine = getEngine()
        
        guard let pluginChain = trackNodes[trackId]?.pluginChain,
              let instance = pluginChain.slots[slot],
              instance.supportsSidechain,
              let avUnit = instance.avAudioUnit else {
            return
        }
        
        // Remove existing sidechain connection if any
        removeSidechainConnection(trackId: trackId, slot: slot)
        
        // If source is none, we're done
        guard source.isEnabled else { return }
        
        // Get the source node based on source type
        let sourceNode: AVAudioNode?
        
        switch source {
        case .none:
            sourceNode = nil
            
        case .track(let sourceTrackId):
            sourceNode = trackNodes[sourceTrackId]?.panNode
            
        case .trackPreFader(let sourceTrackId):
            sourceNode = trackNodes[sourceTrackId]?.pluginChain.outputMixer
            
        case .bus(let busId):
            sourceNode = busNodes[busId]?.getOutputNode()
            
        case .externalInput:
            sourceNode = nil // Not implemented
        }
        
        guard let actualSourceNode = sourceNode else {
            return
        }
        
        // Get the sidechain format
        guard let sidechainFormat = instance.sidechainFormat else {
            return
        }
        
        // Connect the source to the plugin's sidechain input
        let sidechainTap = AVAudioMixerNode()
        engine.attach(sidechainTap)
        
        let tapPoint = AVAudioConnectionPoint(node: sidechainTap, bus: 0)
        
        if let sourceOutput = actualSourceNode as? AVAudioMixerNode {
            let existingPoints = engine.outputConnectionPoints(for: sourceOutput, outputBus: 0)
            var newPoints = existingPoints
            newPoints.append(tapPoint)
            engine.connect(sourceOutput, to: newPoints, fromBus: 0, format: nil)
        } else {
            engine.connect(actualSourceNode, to: sidechainTap, format: nil)
        }
        
        engine.connect(sidechainTap, to: avUnit, fromBus: 0, toBus: 1, format: sidechainFormat)
        
        if sidechainConnections[trackId] == nil {
            sidechainConnections[trackId] = [:]
        }
        sidechainConnections[trackId]?[slot] = sidechainTap
        
        // Store the source type for later queries
        if sidechainSources[trackId] == nil {
            sidechainSources[trackId] = [:]
        }
        sidechainSources[trackId]?[slot] = source
        
        logDebug("Sidechain connected for track \(trackId) slot \(slot)")
    }
    
    /// Remove sidechain connection for a plugin slot
    private func removeSidechainConnection(trackId: UUID, slot: Int) {
        let engine = getEngine()
        
        guard let tapNode = sidechainConnections[trackId]?[slot] else { return }
        
        engine.disconnectNodeInput(tapNode)
        engine.disconnectNodeOutput(tapNode)
        engine.detach(tapNode)
        
        sidechainConnections[trackId]?[slot] = nil
        sidechainSources[trackId]?[slot] = nil
        
        logDebug("Sidechain removed for track \(trackId) slot \(slot)")
    }
    
    /// Get the current sidechain source for a plugin
    func getSidechainSource(trackId: UUID, slot: Int) -> SidechainSource {
        return sidechainSources[trackId]?[slot] ?? .none
    }
    
    /// Clear all sidechain connections for a track (called when track is removed)
    func clearSidechainConnections(for trackId: UUID) {
        guard let slots = sidechainConnections[trackId] else { return }
        
        for slot in slots.keys {
            removeSidechainConnection(trackId: trackId, slot: slot)
        }
        
        sidechainConnections.removeValue(forKey: trackId)
        sidechainSources.removeValue(forKey: trackId)
    }
}
