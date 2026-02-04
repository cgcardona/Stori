//
//  PluginChain.swift
//  Stori
//
//  Manages chains of Audio Unit plugins for tracks and buses.
//

import Foundation
import AVFoundation
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
enum ChainState: String, CustomStringConvertible {
    /// Chain created but not associated with an engine
    case uninstalled
    
    /// Engine reference stored but mixer nodes not created
    /// Audio flows directly through track nodes (lazy optimization)
    case installed
    
    /// Mixer nodes created and attached to engine
    /// Ready for plugin insertion
    case realized
    
    var description: String { rawValue }
    
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

// MARK: - Plugin Chain

/// Manages an ordered chain of plugin instances for audio processing.
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
    
    // MARK: - State Machine
    
    /// Current state of the plugin chain
    @ObservationIgnored
    private(set) var state: ChainState = .uninstalled
    
    /// Transition to a new state (validates transition and logs errors)
    /// In release builds, invalid transitions are logged but proceed to prevent crashes
    /// This allows graceful degradation while still making bugs visible
    @discardableResult
    private func transition(to newState: ChainState) -> Bool {
        guard state.canTransition(to: newState) else {
            let error = PluginChainError.invalidStateTransition(from: state, to: newState)
            AppLogger.shared.error("PluginChain: \(error.localizedDescription)", category: .audio)
            #if DEBUG
            // In debug builds, crash immediately to catch bugs early
            fatalError(error.localizedDescription)
            #else
            // In release builds, force the transition to prevent stuck states
            // This is a recovery path - the chain may be in an inconsistent state
            state = newState
            return false
            #endif
        }
        state = newState
        return true
    }
    
    // MARK: - State Validation
    
    /// Validates that the current state matches actual engine attachment state
    /// Returns true if state is consistent, false if desync detected
    func validateState() -> Bool {
        switch state {
        case .uninstalled:
            // Should have no engine reference and no mixers
            if engine != nil {
                AppLogger.shared.warning("PluginChain state=uninstalled but engine != nil", category: .audio)
                return false
            }
            if _inputMixer != nil || _outputMixer != nil {
                AppLogger.shared.warning("PluginChain state=uninstalled but mixers exist", category: .audio)
                return false
            }
            return true
            
        case .installed:
            // Should have engine reference but mixers not attached
            guard let engine = engine else {
                AppLogger.shared.warning("PluginChain state=installed but engine == nil", category: .audio)
                return false
            }
            
            // Mixers should either not exist or not be attached
            if let inputMixer = _inputMixer, inputMixer.engine != nil {
                AppLogger.shared.warning("PluginChain state=installed but inputMixer is attached", category: .audio)
                return false
            }
            if let outputMixer = _outputMixer, outputMixer.engine != nil {
                AppLogger.shared.warning("PluginChain state=installed but outputMixer is attached", category: .audio)
                return false
            }
            
            // Verify engine is valid
            if !engine.attachedNodes.contains(engine.outputNode) {
                AppLogger.shared.error("PluginChain engine reference is invalid (outputNode not attached)", category: .audio)
                return false
            }
            
            return true
            
        case .realized:
            // Should have engine, mixers exist and attached
            guard let engine = engine else {
                AppLogger.shared.error("PluginChain state=realized but engine == nil", category: .audio)
                return false
            }
            
            guard let inputMixer = _inputMixer else {
                AppLogger.shared.error("PluginChain state=realized but inputMixer == nil", category: .audio)
                return false
            }
            
            guard let outputMixer = _outputMixer else {
                AppLogger.shared.error("PluginChain state=realized but outputMixer == nil", category: .audio)
                return false
            }
            
            // Verify mixers are attached to the correct engine
            if inputMixer.engine !== engine {
                AppLogger.shared.error("PluginChain inputMixer attached to wrong engine", category: .audio)
                return false
            }
            
            if outputMixer.engine !== engine {
                AppLogger.shared.error("PluginChain outputMixer attached to wrong engine", category: .audio)
                return false
            }
            
            // Verify mixers are in engine's attached nodes
            if !engine.attachedNodes.contains(inputMixer) {
                AppLogger.shared.error("PluginChain inputMixer not in engine's attachedNodes", category: .audio)
                return false
            }
            
            if !engine.attachedNodes.contains(outputMixer) {
                AppLogger.shared.error("PluginChain outputMixer not in engine's attachedNodes", category: .audio)
                return false
            }
            
            return true
        }
    }
    
    /// Attempt to reconcile state with actual engine attachment state
    /// Call this when validateState() returns false
    func reconcileStateWithEngine() {
        AppLogger.shared.warning("PluginChain: Attempting state reconciliation", category: .audio)
        
        // Determine actual state based on engine attachment
        let actualState: ChainState
        
        if engine == nil {
            actualState = .uninstalled
        } else if _inputMixer?.engine != nil && _outputMixer?.engine != nil {
            actualState = .realized
        } else {
            actualState = .installed
        }
        
        if actualState != state {
            AppLogger.shared.warning("PluginChain: Reconciling state \(state) -> \(actualState)", category: .audio)
            state = actualState
        }
    }
    
    // MARK: - Audio Nodes (Lazy - Only Created When Needed)
    
    /// Input mixer node - only created when first plugin is inserted
    @ObservationIgnored
    private var _inputMixer: AVAudioMixerNode?
    
    /// Output mixer node - only created when first plugin is inserted
    @ObservationIgnored
    private var _outputMixer: AVAudioMixerNode?
    
    /// Get or create the input mixer (lazy instantiation)
    var inputMixer: AVAudioMixerNode {
        if let existing = _inputMixer {
            return existing
        }
        let mixer = AVAudioMixerNode()
        _inputMixer = mixer
        return mixer
    }
    
    /// Get or create the output mixer (lazy instantiation)
    var outputMixer: AVAudioMixerNode {
        if let existing = _outputMixer {
            return existing
        }
        let mixer = AVAudioMixerNode()
        _outputMixer = mixer
        return mixer
    }
    
    /// Whether the chain mixers have been realized (attached to engine)
    /// This is a derived property based on actual state
    var isRealized: Bool {
        return state == .realized
    }
    
    // NOTE: hasActivePlugins is defined later in the file (includes bypass check)
    
    @ObservationIgnored
    private weak var engine: AVAudioEngine?
    
    @ObservationIgnored
    private var chainFormat: AVAudioFormat?
    
    @ObservationIgnored
    var onRequestGraphMutation: ((@escaping () -> Void) -> Void)?
    
    // MARK: - Initialization
    
    init(id: UUID = UUID(), maxSlots: Int = 8) {
        self.id = id
        self.maxSlots = maxSlots
        self.slots = Array(repeating: nil, count: maxSlots)
        // NOTE: Mixers are NOT created here - lazy instantiation
    }
    
    // MARK: - Engine Integration
    
    /// Install the chain into an audio engine (stores reference, does NOT create nodes)
    /// Nodes are created lazily when the first plugin is inserted.
    /// State transition: uninstalled → installed
    func install(in engine: AVAudioEngine, format: AVAudioFormat?) {
        self.engine = engine
        self.chainFormat = format
        
        // Transition: uninstalled → installed
        if state == .uninstalled {
            transition(to: .installed)
        }
        // NOTE: Mixers are NOT attached here - they're created lazily when needed
        // This saves 2 nodes per track for tracks without plugins
    }
    
    /// Realize the chain by creating and attaching mixer nodes.
    /// Called when the first plugin is being inserted.
    /// State transition: installed → realized
    /// Returns true if newly realized, false if already realized.
    @discardableResult
    func realize() -> Bool {
        // Validate current state before attempting realization
        if !validateState() {
            AppLogger.shared.warning("PluginChain: State validation failed before realize(), attempting reconciliation", category: .audio)
            reconcileStateWithEngine()
        }
        
        guard let engine = self.engine else {
            AppLogger.shared.error("PluginChain: Cannot realize - no engine reference", category: .audio)
            return false
        }
        
        // Verify engine is running (critical for attach operations)
        guard engine.isRunning else {
            AppLogger.shared.error("PluginChain: Cannot realize - engine is not running", category: .audio)
            return false
        }
        
        // Already realized?
        if state == .realized {
            // Validate it's actually realized
            if validateState() {
                return false
            } else {
                AppLogger.shared.warning("PluginChain: State was 'realized' but validation failed, forcing recreation", category: .audio)
                // Fall through to recreate
            }
        }
        
        // Create mixers if they don't exist
        if _inputMixer == nil {
            _inputMixer = AVAudioMixerNode()
        }
        if _outputMixer == nil {
            _outputMixer = AVAudioMixerNode()
        }
        
        // Attach to engine (safely check if already attached)
        if let inputMixer = _inputMixer {
            if inputMixer.engine == nil {
                engine.attach(inputMixer)
            } else if inputMixer.engine !== engine {
                // Attached to wrong engine - detach and reattach
                AppLogger.shared.warning("PluginChain: inputMixer attached to wrong engine, fixing", category: .audio)
                if let wrongEngine = inputMixer.engine {
                    wrongEngine.detach(inputMixer)
                }
                engine.attach(inputMixer)
            }
        }
        
        if let outputMixer = _outputMixer {
            if outputMixer.engine == nil {
                engine.attach(outputMixer)
            } else if outputMixer.engine !== engine {
                // Attached to wrong engine - detach and reattach
                AppLogger.shared.warning("PluginChain: outputMixer attached to wrong engine, fixing", category: .audio)
                if let wrongEngine = outputMixer.engine {
                    wrongEngine.detach(outputMixer)
                }
                engine.attach(outputMixer)
            }
        }
        
        // Use the engine's graph format (hardware-derived) for all connections
        // This ensures plugins match the live engine rate, not a hardcoded value
        let connectionFormat: AVAudioFormat
        if let format = chainFormat {
            connectionFormat = format
        } else {
            // Fallback: use engine's processing rate (inputFormat), not hardware output rate, to avoid format mismatch/glitches
            let engineSampleRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
            let fallbackRate = engineSampleRate > 0 ? engineSampleRate : 48000
            connectionFormat = AVAudioFormat(standardFormatWithSampleRate: fallbackRate, channels: 2)!
            AppLogger.shared.warning("PluginChain: chainFormat was nil, using derived rate \(fallbackRate)", category: .audio)
        }
        
        // Connect mixers
        do {
            engine.connect(_inputMixer!, to: _outputMixer!, format: connectionFormat)
        } catch {
            AppLogger.shared.error("PluginChain: Failed to connect mixers: \(error.localizedDescription)", category: .audio)
            return false
        }
        
        // Transition: installed → realized
        transition(to: .realized)
        
        // Final validation
        if !validateState() {
            AppLogger.shared.error("PluginChain: State validation failed after realize()", category: .audio)
            return false
        }
        
        return true
    }
    
    /// Unrealize the chain by detaching mixer nodes.
    /// Called when the last plugin is removed.
    /// State transition: realized → installed
    func unrealize() {
        guard let engine = self.engine else { return }
        
        // Only unrealize if currently realized
        guard state == .realized else { return }
        
        // Detach input mixer if attached
        if let inputMixer = _inputMixer, inputMixer.engine === engine {
            engine.disconnectNodeInput(inputMixer)
            engine.disconnectNodeOutput(inputMixer)
            engine.detach(inputMixer)
        }
        
        // Detach output mixer if attached
        if let outputMixer = _outputMixer, outputMixer.engine === engine {
            engine.disconnectNodeInput(outputMixer)
            engine.disconnectNodeOutput(outputMixer)
            engine.detach(outputMixer)
        }
        
        _inputMixer = nil
        _outputMixer = nil
        
        // Transition: realized → installed
        transition(to: .installed)
    }
    
    /// Recreate the input and output mixers to clear any residual state
    /// ChatGPT: "recreating the mixers is the pragmatic fix" for lingering graph state
    /// MUST be called within a graph mutation block (engine stopped)
    /// Reset mixer AU state to clear any stale DSP/render state
    /// ROOT CAUSE: AVAudioMixerNode can retain stale internal state after engine.reset()
    /// particularly with format changes or bus accumulation. Resetting the underlying
    /// AUAudioUnit clears this state without needing to recreate the entire node.
    func resetMixerState() {
        // Only reset if mixers exist
        guard let inputMixer = _inputMixer, let outputMixer = _outputMixer else {
            return
        }
        // Reset the underlying AU state - this clears cached formats and DSP state
        inputMixer.auAudioUnit.reset()
        outputMixer.auAudioUnit.reset()
    }
    
    /// Recreate the input/output mixers to clear corrupted state
    /// This is a more aggressive fix than resetMixerState() - use when reset alone doesn't work.
    /// ROOT CAUSE IDENTIFIED: AVAudioMixerNode accumulates input buses when sources are
    /// reconnected multiple times. After engine.reset(), the mixer's internal bus mapping
    /// can become inconsistent, causing audio to flow to a stale/unused bus.
    /// The fix is to ensure we explicitly disconnect ALL buses before reconnecting.
    func recreateMixers() {
        guard let engine = self.engine else {
            return
        }
        
        // Only recreate if mixers exist
        guard let oldInputMixer = _inputMixer, let oldOutputMixer = _outputMixer else {
            return
        }
        
        // Diagnostic: Check engine refs and bus count before disconnection
        let oldInputEngineRef = oldInputMixer.engine
        let oldInputBusCount = oldInputMixer.numberOfInputs
        
        // Disconnect ALL input buses explicitly (not just the node)
        // This is the key fix - mixer nodes accumulate buses and we need to clear them all
        for bus in 0..<oldInputMixer.numberOfInputs {
            engine.disconnectNodeInput(oldInputMixer, bus: bus)
        }
        engine.disconnectNodeOutput(oldInputMixer)
        
        for bus in 0..<oldOutputMixer.numberOfInputs {
            engine.disconnectNodeInput(oldOutputMixer, bus: bus)
        }
        engine.disconnectNodeOutput(oldOutputMixer)
        
        // Detach old mixers from engine
        engine.detach(oldInputMixer)
        engine.detach(oldOutputMixer)
        
        // Create new mixers with fresh state
        _inputMixer = AVAudioMixerNode()
        _outputMixer = AVAudioMixerNode()
        
        // Attach new mixers
        engine.attach(_inputMixer!)
        engine.attach(_outputMixer!)
        
        // Log if we cleared accumulated buses (indicates bus accumulation was the issue)
        if oldInputBusCount > 1 {
        }
        
        if oldInputEngineRef == nil {
        }
    }
    
    /// Ensure the chain has a valid engine reference
    /// This is needed when tracks are restored from a saved project - the nodes may be
    /// attached to the engine but the chain's internal reference may be nil
    func ensureEngineReference(_ engine: AVAudioEngine) {
        if self.engine == nil {
            self.engine = engine
            self.chainFormat = engine.outputNode.inputFormat(forBus: 0)
        }
    }
    
    /// Update the chain's format to match the canonical format
    /// CRITICAL: Call this before rebuilding connections to ensure consistent format
    func updateFormat(_ format: AVAudioFormat) {
        self.chainFormat = format
    }
    
    /// Remove the chain from the engine
    /// State transition: (any) → uninstalled
    func uninstall() {
        guard let engine = engine else { return }
        
        // Unload all plugins
        for slot in slots {
            slot?.unload()
        }
        
        // Safely detach mixers - only if they exist and are attached to this engine
        if let inputMixer = _inputMixer, inputMixer.engine === engine {
            engine.disconnectNodeOutput(inputMixer)
            engine.disconnectNodeInput(inputMixer)
            engine.detach(inputMixer)
        }
        
        if let outputMixer = _outputMixer, outputMixer.engine === engine {
            engine.disconnectNodeOutput(outputMixer)
            engine.disconnectNodeInput(outputMixer)
            engine.detach(outputMixer)
        }
        
        _inputMixer = nil
        _outputMixer = nil
        self.engine = nil
        
        // Transition to uninstalled (force - this is teardown)
        state = .uninstalled
    }
    
    // MARK: - Plugin Management
    
    /// Store a plugin at a specific slot (does not rebuild chain - caller must do that)
    func storePlugin(_ plugin: PluginInstance, atSlot slot: Int) {
        guard slot >= 0, slot < maxSlots else {
            return
        }
        
        // Remove existing plugin at this slot
        if slots[slot] != nil {
            removePlugin(atSlot: slot)
        }
        
        // Store the plugin
        slots[slot] = plugin
    }
    
    /// Rebuild chain connections - assumes engine is already stopped by caller
    /// NOTE: If the chain is not realized (no mixers), this is a no-op.
    /// The caller (AudioEngine) should check isRealized and route directly if false.
    func rebuildChainConnections(engine callerEngine: AVAudioEngine) {
        // Verify the engine matches
        guard let storedEngine = self.engine else { return }
        
        // If chain is not realized (no plugins), nothing to rebuild
        guard let inputMixer = _inputMixer, let outputMixer = _outputMixer else { return }
        
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
        // FIX 2: Loop-disconnect ALL input buses on mixers, not just bus 0.
        // This prevents stale buses (and stale converter paths) from persisting.
        for bus in 0..<inputMixer.numberOfInputs {
            engine.disconnectNodeInput(inputMixer, bus: bus)
        }
        engine.disconnectNodeOutput(inputMixer)
        
        for node in activeNodes {
            engine.disconnectNodeInput(node)
            engine.disconnectNodeOutput(node)
        }
        
        // Disconnect ALL outputMixer input buses (keep output connection to EQ)
        for bus in 0..<outputMixer.numberOfInputs {
            engine.disconnectNodeInput(outputMixer, bus: bus)
        }
        
        // STEP 3: Reconnect the chain using the engine's graph format (hardware-derived)
        // This ensures all connections match the live engine rate, preventing pitch corruption
        guard let connectionFormat = chainFormat else {
            return
        }
        
        if !hasActivePlugins || isBypassed {
            // Empty or bypassed: input → output
            engine.connect(inputMixer, to: outputMixer, format: connectionFormat)
        } else {
            // Chain: input → plugin1 → plugin2 → ... → output
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
    /// NOTE: Caller must rebuild the graph after calling this
    func removePlugin(atSlot slot: Int) {
        guard slot >= 0, slot < maxSlots, let plugin = slots[slot] else { return }
        
        // Detach from engine if attached
        if let avUnit = plugin.avAudioUnit, let engine = engine {
            engine.disconnectNodeOutput(avUnit)
            engine.disconnectNodeInput(avUnit)
            engine.detach(avUnit)
        }
        
        // Unload and remove
        plugin.unload()
        slots[slot] = nil
        
        // NOTE: Caller must call rebuildChainConnections() or rebuildTrackGraph()
        // DO NOT call rebuildChain() here - it doesn't properly reset the engine
    }
    
    
    /// Get all active (non-nil) plugins in order
    var activePlugins: [PluginInstance] {
        slots.compactMap { $0 }
    }
    
    /// Get the audio format used by this chain (for external connections)
    var format: AVAudioFormat? {
        chainFormat
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
    /// Creates fresh AU instances with identical state for use in export
    /// - Returns: Array of cloned AVAudioUnit nodes in chain order (excludes bypassed plugins)
    nonisolated func cloneActivePlugins() async throws -> [AVAudioUnit] {
        // Get active plugins on MainActor
        let plugins = await activePlugins
        let chainBypassed = await isBypassed
        
        // If entire chain is bypassed, return empty array
        guard !chainBypassed else {
            return []
        }
        
        var clonedNodes: [AVAudioUnit] = []
        
        for plugin in plugins {
            // Skip bypassed plugins
            let isBypassed = await plugin.isBypassed
            if isBypassed {
                continue
            }
            
            do {
                let clonedNode = try await plugin.cloneForOfflineRender()
                clonedNodes.append(clonedNode)
            } catch {
                // Log warning but continue - graceful degradation
                let name = await plugin.descriptor.name
            }
        }
        
        return clonedNodes
    }
    
}

// MARK: - Track Plugin Extension

/// Extension to TrackAudioNode for plugin support
extension TrackAudioNode {
    
    /// Create a plugin chain for this track
    /// Note: This is called from AudioEngine when setting up a track
    static func createPluginChain() -> PluginChain {
        return PluginChain(maxSlots: 8)
    }
}
