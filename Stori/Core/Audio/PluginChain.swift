//
//  PluginChain.swift
//  Stori
//
//  Manages chains of Audio Unit plugins for tracks and buses.
//
//  NOTE: @preconcurrency import must be the first import of that module in this file (Swift compiler limitation).
@preconcurrency import AVFoundation
import Foundation
import Combine
import Observation

// MARK: - Plugin Chain Errors

/// Errors that can occur during plugin chain operations
enum PluginChainError: Error, LocalizedError {
    case invalidStateTransition(from: ChainState, to: ChainState)
    case noEngineReference
    case chainNotRealized
    case slotOutOfBounds(slot: Int, max: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidStateTransition(let from, let to):
            return "Invalid chain state transition: \(from) → \(to)"
        case .noEngineReference:
            return "Plugin chain has no engine reference"
        case .chainNotRealized:
            return "Plugin chain is not realized (mixers not created)"
        case .slotOutOfBounds(let slot, let max):
            return "Plugin slot \(slot) out of bounds (max: \(max - 1))"
        }
    }
}

// MARK: - Plugin Chain State Machine

/// Explicit state machine for plugin chain lifecycle.
/// Prevents invalid state transitions and makes the chain's status clear.
enum ChainState: String, @unchecked Sendable {
    /// Chain created but not associated with an engine
    case uninstalled
    
    /// Engine reference stored but mixer nodes not created
    /// Audio flows directly through track nodes (lazy optimization)
    case installed
    
    /// Mixer nodes created and attached to engine
    /// Ready for plugin insertion
    case realized
}

extension ChainState: CustomStringConvertible {
    nonisolated var description: String { rawValue }
    
    /// Valid transitions from this state
    var validTransitions: Set<ChainState> {
        switch self {
        case .uninstalled: return [.installed]
        case .installed: return [.realized, .uninstalled]
        case .realized: return [.installed, .uninstalled]  // Can go back to installed if unrealized
        }
    }
    
    func canTransition(to newState: ChainState) -> Bool {
        validTransitions.contains(newState)
    }
}

// MARK: - Plugin Chain Core (Nonisolated Resource Owner)

/// Owns audio graph resources (mixer nodes, engine connection) with deterministic RAII cleanup.
///
/// # Architecture: Core + Model Split
///
/// `PluginChainCore` is intentionally **not** `@MainActor`. It owns the
/// `AVAudioMixerNode` instances and manages their attachment to the
/// `AVAudioEngine`. These resources are cleaned up in `deinit`, which
/// can run on any thread without requiring an actor hop.
///
/// The `@MainActor @Observable` `PluginChain` holds this core and manages
/// the plugin slot array and bypass state for UI observation.
final class PluginChainCore {
    
    // MARK: - Audio Nodes (Lazy — Only Created When Needed)
    
    /// Input mixer node — only created when first plugin is inserted
    private(set) var inputMixer: AVAudioMixerNode?
    
    /// Output mixer node — only created when first plugin is inserted
    private(set) var outputMixer: AVAudioMixerNode?
    
    /// Weak reference to the audio engine
    weak var engine: AVAudioEngine?
    
    /// Audio format for chain connections
    var chainFormat: AVAudioFormat?
    
    /// Current state of the plugin chain
    private(set) var state: ChainState = .uninstalled
    
    // MARK: - Lazy Mixer Access
    
    /// Get or create the input mixer (lazy instantiation)
    func getOrCreateInputMixer() -> AVAudioMixerNode {
        if let existing = inputMixer { return existing }
        let mixer = AVAudioMixerNode()
        inputMixer = mixer
        return mixer
    }
    
    /// Get or create the output mixer (lazy instantiation)
    func getOrCreateOutputMixer() -> AVAudioMixerNode {
        if let existing = outputMixer { return existing }
        let mixer = AVAudioMixerNode()
        outputMixer = mixer
        return mixer
    }
    
    // MARK: - State Machine
    
    /// Transition to a new state (validates transition and logs errors)
    @discardableResult
    func transition(to newState: ChainState) -> Bool {
        guard state.canTransition(to: newState) else {
            let error = PluginChainError.invalidStateTransition(from: state, to: newState)
            AppLogger.shared.error("PluginChain: \(error.localizedDescription)", category: .audio)
            #if DEBUG
            fatalError(error.localizedDescription)
            #else
            state = newState
            return false
            #endif
        }
        state = newState
        return true
    }
    
    /// Force state (for teardown/reconciliation where transitions may be invalid)
    func forceState(_ newState: ChainState) {
        state = newState
    }
    
    // MARK: - Mixer Management
    
    /// Create new mixer nodes (for recreateMixers)
    func createFreshMixers() {
        inputMixer = AVAudioMixerNode()
        outputMixer = AVAudioMixerNode()
    }
    
    /// Clear mixer references
    func clearMixers() {
        inputMixer = nil
        outputMixer = nil
    }
    
    // MARK: - RAII Cleanup
    
    /// Deterministic cleanup of audio graph resources.
    /// Detaches mixer nodes from the engine if still attached.
    deinit {
        guard let engine = engine else { return }
        
        if let inputMixer = inputMixer, inputMixer.engine === engine {
            engine.disconnectNodeOutput(inputMixer)
            engine.disconnectNodeInput(inputMixer)
            engine.detach(inputMixer)
        }
        
        if let outputMixer = outputMixer, outputMixer.engine === engine {
            engine.disconnectNodeOutput(outputMixer)
            engine.disconnectNodeInput(outputMixer)
            engine.detach(outputMixer)
        }
    }
}

// MARK: - Plugin Chain (@MainActor Observable Model)

/// Manages an ordered chain of plugin instances for audio processing.
///
/// # Architecture: @MainActor Observable Model
///
/// Holds a `PluginChainCore` that owns audio graph resources (mixer nodes).
/// Plugin slots and bypass state are `@Observable` for SwiftUI.
///
/// STATE MACHINE:
/// - `uninstalled` → Chain created, no engine reference
/// - `installed` → Engine reference stored, mixers NOT created (lazy optimization)
/// - `realized` → Mixers created and attached, ready for plugins
///
/// ARCHITECTURE NOTE (Lazy Node Attachment):
/// To reduce node count, the inputMixer and outputMixer are only created
/// when plugins are actually inserted. When no plugins exist, the track's
/// signal flows directly without these intermediate nodes.
///
/// This saves 2 nodes per track × 64 tracks = 128 nodes for typical projects.
// PERFORMANCE: Using @Observable for fine-grained SwiftUI updates
@Observable
@MainActor
class PluginChain {
    
    // MARK: - Observable Properties
    
    @ObservationIgnored
    let id: UUID
    
    @ObservationIgnored
    let maxSlots: Int
    
    /// Plugin instances in order (nil = empty slot)
    var slots: [PluginInstance?]
    
    /// Whether the entire chain is bypassed
    var isBypassed: Bool = false
    
    // MARK: - Core (Nonisolated Resource Owner)
    
    /// Nonisolated core that owns mixer nodes and handles RAII cleanup.
    @ObservationIgnored
    private let core = PluginChainCore()
    
    // MARK: - State Machine (delegates to core)
    
    /// Current state of the plugin chain
    var state: ChainState { core.state }
    
    /// Whether the chain mixers have been realized (attached to engine)
    var isRealized: Bool { core.state == .realized }
    
    // MARK: - Mixer Access (delegates to core)
    
    /// Get or create the input mixer (lazy instantiation)
    var inputMixer: AVAudioMixerNode { core.getOrCreateInputMixer() }
    
    /// Get or create the output mixer (lazy instantiation)
    var outputMixer: AVAudioMixerNode { core.getOrCreateOutputMixer() }
    
    // MARK: - Graph Mutation Callback
    
    @ObservationIgnored
    var onRequestGraphMutation: ((@escaping () -> Void) -> Void)?
    
    // MARK: - Initialization
    
    init(id: UUID = UUID(), maxSlots: Int = 8) {
        self.id = id
        self.maxSlots = maxSlots
        self.slots = Array(repeating: nil, count: maxSlots)
    }
    
    // PluginChainCore handles RAII cleanup — no manual deinit needed.
    
    // MARK: - State Validation
    
    /// Validates that the current state matches actual engine attachment state
    func validateState() -> Bool {
        switch core.state {
        case .uninstalled:
            if core.engine != nil {
                AppLogger.shared.warning("PluginChain state=uninstalled but engine != nil", category: .audio)
                return false
            }
            if core.inputMixer != nil || core.outputMixer != nil {
                AppLogger.shared.warning("PluginChain state=uninstalled but mixers exist", category: .audio)
                return false
            }
            return true
            
        case .installed:
            guard let engine = core.engine else {
                AppLogger.shared.warning("PluginChain state=installed but engine == nil", category: .audio)
                return false
            }
            
            if let inputMixer = core.inputMixer, inputMixer.engine != nil {
                AppLogger.shared.warning("PluginChain state=installed but inputMixer is attached", category: .audio)
                return false
            }
            if let outputMixer = core.outputMixer, outputMixer.engine != nil {
                AppLogger.shared.warning("PluginChain state=installed but outputMixer is attached", category: .audio)
                return false
            }
            
            return true
            
        case .realized:
            guard let engine = core.engine else {
                AppLogger.shared.error("PluginChain state=realized but engine == nil", category: .audio)
                return false
            }
            
            guard let inputMixer = core.inputMixer else {
                AppLogger.shared.error("PluginChain state=realized but inputMixer == nil", category: .audio)
                return false
            }
            
            guard let outputMixer = core.outputMixer else {
                AppLogger.shared.error("PluginChain state=realized but outputMixer == nil", category: .audio)
                return false
            }
            
            if engine.attachedNodes.isEmpty {
                AppLogger.shared.error("PluginChain state=realized but engine has no attached nodes (likely reset)", category: .audio)
                return false
            }
            
            let inputAttached = engine.attachedNodes.contains { $0 === inputMixer }
            let outputAttached = engine.attachedNodes.contains { $0 === outputMixer }
            
            if !inputAttached {
                AppLogger.shared.error("PluginChain inputMixer not attached after validation", category: .audio)
                return false
            }
            
            if !outputAttached {
                AppLogger.shared.error("PluginChain outputMixer not attached after validation", category: .audio)
                return false
            }
            
            return true
        }
    }
    
    /// Attempt to reconcile state with actual engine attachment state
    func reconcileStateWithEngine() {
        AppLogger.shared.warning("PluginChain: Attempting state reconciliation", category: .audio)
        
        let actualState: ChainState
        
        if core.engine == nil {
            actualState = .uninstalled
        } else if core.inputMixer?.engine != nil && core.outputMixer?.engine != nil {
            actualState = .realized
        } else {
            actualState = .installed
        }
        
        if actualState != core.state {
            AppLogger.shared.warning("PluginChain: Reconciling state \(core.state) -> \(actualState)", category: .audio)
            core.forceState(actualState)
        }
    }
    
    // MARK: - Engine Integration
    
    /// Install the chain into an audio engine (stores reference, does NOT create nodes)
    func install(in engine: AVAudioEngine, format: AVAudioFormat?) {
        core.engine = engine
        core.chainFormat = format
        
        if core.state == .uninstalled {
            core.transition(to: .installed)
        }
    }
    
    /// Realize the chain by creating and attaching mixer nodes.
    @discardableResult
    func realize() -> Bool {
        if !validateState() {
            AppLogger.shared.warning("PluginChain: State validation failed before realize(), attempting reconciliation", category: .audio)
            reconcileStateWithEngine()
        }
        
        guard let engine = core.engine else {
            AppLogger.shared.error("PluginChain: Cannot realize - no engine reference", category: .audio)
            return false
        }
        
        guard engine.isRunning else {
            AppLogger.shared.error("PluginChain: Cannot realize - engine is not running", category: .audio)
            return false
        }
        
        if core.state == .realized {
            if validateState() {
                return false
            } else {
                AppLogger.shared.warning("PluginChain: State was 'realized' but validation failed, forcing recreation", category: .audio)
            }
        }
        
        // Create mixers if they don't exist
        let inMixer = core.getOrCreateInputMixer()
        let outMixer = core.getOrCreateOutputMixer()
        
        // Attach to engine
        if inMixer.engine == nil {
            engine.attach(inMixer)
        } else if inMixer.engine !== engine {
            AppLogger.shared.warning("PluginChain: inputMixer attached to wrong engine, fixing", category: .audio)
            if let wrongEngine = inMixer.engine {
                wrongEngine.detach(inMixer)
            }
            engine.attach(inMixer)
        }
        
        if outMixer.engine == nil {
            engine.attach(outMixer)
        } else if outMixer.engine !== engine {
            AppLogger.shared.warning("PluginChain: outputMixer attached to wrong engine, fixing", category: .audio)
            if let wrongEngine = outMixer.engine {
                wrongEngine.detach(outMixer)
            }
            engine.attach(outMixer)
        }
        
        let connectionFormat: AVAudioFormat
        if let format = core.chainFormat {
            connectionFormat = format
        } else {
            let engineSampleRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
            let fallbackRate = engineSampleRate > 0 ? engineSampleRate : 48000
            connectionFormat = AVAudioFormat(standardFormatWithSampleRate: fallbackRate, channels: 2)!
            AppLogger.shared.warning("PluginChain: chainFormat was nil, using derived rate \(fallbackRate)", category: .audio)
        }
        
        do {
            engine.connect(inMixer, to: outMixer, format: connectionFormat)
        } catch {
            AppLogger.shared.error("PluginChain: Failed to connect mixers: \(error.localizedDescription)", category: .audio)
            return false
        }
        
        core.transition(to: .realized)
        
        if !validateState() {
            AppLogger.shared.error("PluginChain: State validation failed after realize()", category: .audio)
            return false
        }
        
        return true
    }
    
    /// Unrealize the chain by detaching mixer nodes.
    func unrealize() {
        guard let engine = core.engine else { return }
        guard core.state == .realized else { return }
        
        if let inputMixer = core.inputMixer, inputMixer.engine === engine {
            engine.disconnectNodeInput(inputMixer)
            engine.disconnectNodeOutput(inputMixer)
            engine.detach(inputMixer)
        }
        
        if let outputMixer = core.outputMixer, outputMixer.engine === engine {
            engine.disconnectNodeInput(outputMixer)
            engine.disconnectNodeOutput(outputMixer)
            engine.detach(outputMixer)
        }
        
        core.clearMixers()
        core.transition(to: .installed)
    }
    
    /// Reset mixer AU state to clear any stale DSP/render state
    func resetMixerState() {
        guard let inputMixer = core.inputMixer, let outputMixer = core.outputMixer else {
            return
        }
        inputMixer.auAudioUnit.reset()
        outputMixer.auAudioUnit.reset()
    }
    
    /// Recreate the input/output mixers to clear corrupted state
    func recreateMixers() {
        guard let engine = core.engine else { return }
        guard let oldInputMixer = core.inputMixer, let oldOutputMixer = core.outputMixer else { return }
        
        let oldInputBusCount = oldInputMixer.numberOfInputs
        
        // Disconnect ALL input buses explicitly
        for bus in 0..<oldInputMixer.numberOfInputs {
            engine.disconnectNodeInput(oldInputMixer, bus: bus)
        }
        engine.disconnectNodeOutput(oldInputMixer)
        
        for bus in 0..<oldOutputMixer.numberOfInputs {
            engine.disconnectNodeInput(oldOutputMixer, bus: bus)
        }
        engine.disconnectNodeOutput(oldOutputMixer)
        
        engine.detach(oldInputMixer)
        engine.detach(oldOutputMixer)
        
        // Create new mixers with fresh state
        core.createFreshMixers()
        
        engine.attach(core.inputMixer!)
        engine.attach(core.outputMixer!)
        
        if oldInputBusCount > 1 {
        }
    }
    
    /// Ensure the chain has a valid engine reference
    func ensureEngineReference(_ engine: AVAudioEngine) {
        if core.engine == nil {
            core.engine = engine
            core.chainFormat = engine.outputNode.inputFormat(forBus: 0)
        }
    }
    
    /// Update the chain's format to match the canonical format
    func updateFormat(_ format: AVAudioFormat) {
        core.chainFormat = format
    }
    
    /// Remove the chain from the engine
    /// SAFETY (Issue #62): Uses deferred deallocation for plugins
    func uninstall() {
        guard let engine = core.engine else { return }
        
        // Schedule plugins for deferred deallocation
        for slot in slots {
            if let plugin = slot {
                PluginDeferredDeallocationManager.shared.schedulePluginForDeallocation(plugin)
            }
        }
        
        // Clear slots immediately
        for i in 0..<maxSlots {
            slots[i] = nil
        }
        
        // Safely detach mixers
        if let inputMixer = core.inputMixer, inputMixer.engine === engine, engine.attachedNodes.contains(inputMixer) {
            engine.disconnectNodeOutput(inputMixer)
            engine.disconnectNodeInput(inputMixer)
            engine.detach(inputMixer)
        }
        
        if let outputMixer = core.outputMixer, outputMixer.engine === engine, engine.attachedNodes.contains(outputMixer) {
            engine.disconnectNodeOutput(outputMixer)
            engine.disconnectNodeInput(outputMixer)
            engine.detach(outputMixer)
        }
        
        core.clearMixers()
        core.engine = nil
        core.forceState(.uninstalled)
    }
    
    // MARK: - Plugin Management
    
    /// Store a plugin at a specific slot (does not rebuild chain - caller must do that)
    func storePlugin(_ plugin: PluginInstance, atSlot slot: Int) {
        guard slot >= 0, slot < maxSlots else { return }
        
        if slots[slot] != nil {
            removePlugin(atSlot: slot)
        }
        
        slots[slot] = plugin
    }
    
    // MARK: - Playback Preparation (BUG FIX Issue #54)
    
    /// Prepare all plugins for playback by ensuring render resources are allocated.
    func prepareForPlayback() -> Bool {
        guard core.engine != nil else {
            AppLogger.shared.warning("PluginChain.prepareForPlayback: No engine reference", category: .audio)
            return false
        }
        
        guard hasActivePlugins else {
            return true
        }
        
        if !isRealized {
            let didRealize = realize()
            if !didRealize {
                AppLogger.shared.error("PluginChain.prepareForPlayback: Failed to realize chain", category: .audio)
                return false
            }
        }
        
        var allPrepared = true
        
        for plugin in activePlugins {
            guard let au = plugin.auAudioUnit else {
                AppLogger.shared.warning("PluginChain.prepareForPlayback: Plugin '\(plugin.descriptor.name)' has no AUAudioUnit", category: .audio)
                allPrepared = false
                continue
            }
            
            if plugin.isBypassed {
                continue
            }
            
            if !au.renderResourcesAllocated {
                do {
                    try au.allocateRenderResources()
                    AppLogger.shared.info("PluginChain.prepareForPlayback: Allocated resources for '\(plugin.descriptor.name)'", category: .audio)
                } catch {
                    AppLogger.shared.error("PluginChain.prepareForPlayback: Failed to allocate resources for '\(plugin.descriptor.name)': \(error)", category: .audio)
                    allPrepared = false
                }
            }
        }
        
        return allPrepared
    }
    
    /// Rebuild chain connections - assumes engine is already stopped by caller
    func rebuildChainConnections(engine callerEngine: AVAudioEngine) {
        guard let storedEngine = core.engine else { return }
        guard let inputMixer = core.inputMixer, let outputMixer = core.outputMixer else { return }
        
        let engine = storedEngine
        
        // STEP 1: Attach nodes if needed
        if inputMixer.engine == nil { engine.attach(inputMixer) }
        if outputMixer.engine == nil { engine.attach(outputMixer) }
        
        var activeNodes: [AVAudioNode] = []
        for plugin in activePlugins {
            if let avUnit = plugin.avAudioUnit {
                if avUnit.engine == nil { engine.attach(avUnit) }
                activeNodes.append(avUnit)
            }
        }
        
        // STEP 2: Disconnect chain nodes for clean rebuild
        for bus in 0..<inputMixer.numberOfInputs {
            engine.disconnectNodeInput(inputMixer, bus: bus)
        }
        engine.disconnectNodeOutput(inputMixer)
        
        for node in activeNodes {
            engine.disconnectNodeInput(node)
            engine.disconnectNodeOutput(node)
        }
        
        for bus in 0..<outputMixer.numberOfInputs {
            engine.disconnectNodeInput(outputMixer, bus: bus)
        }
        
        // STEP 3: Reconnect the chain
        guard let connectionFormat = core.chainFormat else {
            return
        }
        
        if !hasActivePlugins || isBypassed {
            engine.connect(inputMixer, to: outputMixer, format: connectionFormat)
        } else {
            let nonBypassedPlugins = activePlugins.filter { !$0.isBypassed }
            var previousNode: AVAudioNode = inputMixer
            
            for plugin in nonBypassedPlugins {
                if let node = plugin.avAudioUnit {
                    engine.connect(previousNode, to: node, format: connectionFormat)
                    previousNode = node
                }
            }
            
            engine.connect(previousNode, to: outputMixer, format: connectionFormat)
        }
    }
    
    
    /// Remove a plugin from a slot
    /// SAFETY (Issue #62): Uses deferred deallocation to prevent use-after-free during hot-swap
    func removePlugin(atSlot slot: Int) {
        guard slot >= 0, slot < maxSlots, let plugin = slots[slot] else { return }
        
        // Detach from engine if attached
        if let avUnit = plugin.avAudioUnit, let engine = core.engine {
            engine.disconnectNodeOutput(avUnit)
            engine.disconnectNodeInput(avUnit)
            engine.detach(avUnit)
        }
        
        // Schedule for deferred deallocation
        PluginDeferredDeallocationManager.shared.schedulePluginForDeallocation(
            plugin,
            trackId: nil,
            slotIndex: slot
        )
        
        slots[slot] = nil
    }
    
    
    /// Get all active (non-nil) plugins in order
    var activePlugins: [PluginInstance] {
        slots.compactMap { $0 }
    }
    
    /// Get the audio format used by this chain (for external connections)
    var format: AVAudioFormat? {
        core.chainFormat
    }
    
    /// Get the total latency of all plugins in samples
    var totalLatencySamples: Int {
        activePlugins.reduce(0) { $0 + $1.latencySamples }
    }
    
    /// Whether this chain has any active (non-bypassed) plugins
    var hasActivePlugins: Bool {
        activePlugins.contains { !$0.isBypassed }
    }
    
    // MARK: - Offline Render Cloning
    
    /// Clone all active plugins for offline rendering
    nonisolated func cloneActivePlugins() async throws -> [AVAudioUnit] {
        let plugins = await activePlugins
        let chainBypassed = await isBypassed
        
        guard !chainBypassed else {
            return []
        }
        
        var clonedNodes: [AVAudioUnit] = []
        
        for plugin in plugins {
            let isBypassed = await plugin.isBypassed
            if isBypassed {
                continue
            }
            
            do {
                let clonedNode = try await plugin.cloneForOfflineRender()
                clonedNodes.append(clonedNode)
            } catch {
                let name = await plugin.descriptor.name
            }
        }
        
        return clonedNodes
    }
    
    // MARK: - Cleanup
    // PluginChainCore handles RAII cleanup — no manual deinit needed.
}

// MARK: - Track Plugin Extension

/// Extension to TrackAudioNode for plugin support
extension TrackAudioNode {
    
    /// Create a plugin chain for this track
    nonisolated static func createPluginChain() -> PluginChain {
        return MainActor.assumeIsolated {
            PluginChain(maxSlots: 8)
        }
    }
}
