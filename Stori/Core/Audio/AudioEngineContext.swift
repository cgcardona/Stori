//
//  AudioEngineContext.swift
//  Stori
//
//  Protocol for dependency injection of audio engine capabilities.
//  Enables loose coupling between components and the AudioEngine.
//
//  DESIGN RATIONALE:
//  - Components receive only the capabilities they need
//  - Enables testing with mock implementations
//  - Breaks circular dependencies between audio subsystems
//  - Clear separation between observable UI state and thread-safe audio state
//

import Foundation
import AVFoundation

// MARK: - Audio Engine Context Protocol

/// Protocol providing read-only access to core audio engine state.
/// Components can depend on this protocol instead of the concrete AudioEngine class.
///
/// This protocol is split into sub-protocols for fine-grained dependency injection:
/// - `AudioTimingProvider`: Timing and scheduling information
/// - `AudioTransportProvider`: Transport state and control
/// - `AudioGraphProvider`: Audio graph access
///
/// Usage:
/// ```swift
/// class MyComponent {
///     private let timingProvider: AudioTimingProvider
///     
///     init(timingProvider: AudioTimingProvider) {
///         self.timingProvider = timingProvider
///     }
///     
///     func process() {
///         let context = timingProvider.schedulingContext
///         let samples = context.beatsToSamples(4.0)
///     }
/// }
/// ```
protocol AudioEngineContext: AudioTimingProvider, AudioTransportProvider, AudioGraphProvider {}

// MARK: - Audio Timing Provider

/// Provides timing and scheduling information.
/// Thread-safe: These properties can be read from any thread.
protocol AudioTimingProvider: AnyObject, Sendable {
    
    /// Current scheduling context (sample rate, tempo, time signature)
    /// Use this for all beat ↔ sample ↔ seconds conversions
    var schedulingContext: AudioSchedulingContext { get }
    
    /// Current hardware sample rate
    var currentSampleRate: Double { get }
    
    /// Current project tempo in BPM
    var currentTempo: Double { get }
    
    /// Current time signature
    var currentTimeSignature: TimeSignature { get }
}

// MARK: - Audio Transport Provider

/// Provides transport state information.
/// Note: Some properties are thread-safe (atomic*), others require MainActor.
protocol AudioTransportProvider: AnyObject {
    
    /// Current transport state (stopped, playing, paused, recording)
    @MainActor var transportState: TransportState { get }
    
    /// Whether playback is currently active
    @MainActor var isPlaying: Bool { get }
    
    /// Current playback position
    @MainActor var currentPosition: PlaybackPosition { get }
    
    /// Cycle (loop) enabled state
    @MainActor var isCycleEnabled: Bool { get }
    
    /// Cycle start beat
    @MainActor var cycleStartBeat: Double { get }
    
    /// Cycle end beat
    @MainActor var cycleEndBeat: Double { get }
    
    // MARK: - Thread-Safe Accessors (for audio/MIDI schedulers)
    
    /// Thread-safe beat position (readable from any thread)
    nonisolated var atomicBeatPosition: Double { get }
    
    /// Thread-safe playing state (readable from any thread)
    nonisolated var atomicIsPlaying: Bool { get }
}

// MARK: - Audio Graph Provider

/// Provides access to the audio graph for components that need to connect nodes.
protocol AudioGraphProvider: AnyObject {
    
    /// The underlying AVAudioEngine (for attaching nodes)
    @MainActor var sharedAVAudioEngine: AVAudioEngine { get }
    
    /// The main mixer node (for connecting track outputs)
    @MainActor var sharedMixer: AVAudioMixerNode { get }
    
    /// Whether the audio graph is currently stable (safe for UI enumeration)
    @MainActor var isGraphStable: Bool { get }
    
    /// Whether the graph is ready for playback (all nodes connected)
    var isGraphReadyForPlayback: Bool { get }
}

// MARK: - Minimal Timing Context (Thread-Safe)

/// A minimal, thread-safe timing context that can be captured and passed between threads.
/// Unlike the full providers, this is a struct that can be freely copied.
///
/// Use this when you need to pass timing information to a background thread
/// or audio callback without maintaining a reference to the engine.
struct CapturedTimingContext: Sendable {
    /// The scheduling context at capture time
    let schedulingContext: AudioSchedulingContext
    
    /// Beat position at capture time
    let beatPosition: Double
    
    /// Whether transport was playing at capture time
    let isPlaying: Bool
    
    /// Host time when this context was captured
    let captureHostTime: UInt64
    
    /// Create a captured context from a timing provider
    @MainActor
    init(from provider: AudioTimingProvider & AudioTransportProvider) {
        self.schedulingContext = provider.schedulingContext
        self.beatPosition = provider.currentPosition.beats
        self.isPlaying = provider.isPlaying
        self.captureHostTime = mach_absolute_time()
    }
    
    /// Create a captured context with explicit values
    init(
        schedulingContext: AudioSchedulingContext,
        beatPosition: Double,
        isPlaying: Bool
    ) {
        self.schedulingContext = schedulingContext
        self.beatPosition = beatPosition
        self.isPlaying = isPlaying
        self.captureHostTime = mach_absolute_time()
    }
    
    /// Estimate current beat position based on elapsed time since capture
    /// Useful for audio callbacks that need an approximate current position
    func estimatedBeatPosition() -> Double {
        guard isPlaying else { return beatPosition }
        
        // Calculate elapsed time since capture
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        
        let currentHostTime = mach_absolute_time()
        let elapsedNanos = (currentHostTime - captureHostTime) * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        let elapsedSeconds = Double(elapsedNanos) / 1_000_000_000.0
        
        // Convert elapsed seconds to beats
        let elapsedBeats = schedulingContext.secondsToBeats(elapsedSeconds)
        return beatPosition + elapsedBeats
    }
}

// MARK: - Mock Implementation for Testing

#if DEBUG
/// Mock implementation of AudioEngineContext for unit tests
@MainActor
final class MockAudioEngineContext: AudioEngineContext {
    
    // MARK: - AudioTimingProvider
    
    var schedulingContext: AudioSchedulingContext
    var currentSampleRate: Double { schedulingContext.sampleRate }
    var currentTempo: Double { schedulingContext.tempo }
    var currentTimeSignature: TimeSignature { schedulingContext.timeSignature }
    
    // MARK: - AudioTransportProvider
    
    var transportState: TransportState = .stopped
    var isPlaying: Bool { transportState.isPlaying }
    var currentPosition: PlaybackPosition = PlaybackPosition()
    var isCycleEnabled: Bool = false
    var cycleStartBeat: Double = 0.0
    var cycleEndBeat: Double = 4.0
    
    // Thread-safe properties
    nonisolated var atomicBeatPosition: Double { 0.0 }
    nonisolated var atomicIsPlaying: Bool { false }
    
    // MARK: - AudioGraphProvider
    
    var sharedAVAudioEngine: AVAudioEngine = AVAudioEngine()
    var sharedMixer: AVAudioMixerNode = AVAudioMixerNode()
    var isGraphStable: Bool = true
    var isGraphReadyForPlayback: Bool = true
    
    // MARK: - Initialization
    
    init(
        sampleRate: Double = 48000,
        tempo: Double = 120,
        timeSignature: TimeSignature = .fourFour
    ) {
        self.schedulingContext = AudioSchedulingContext(
            sampleRate: sampleRate,
            tempo: tempo,
            timeSignature: timeSignature
        )
    }
    
    // MARK: - Test Helpers
    
    func setTempo(_ tempo: Double) {
        schedulingContext = schedulingContext.with(tempo: tempo)
    }
    
    func setSampleRate(_ sampleRate: Double) {
        schedulingContext = schedulingContext.with(sampleRate: sampleRate)
    }
    
    func setPlaying(_ playing: Bool, at beat: Double = 0) {
        transportState = playing ? .playing : .stopped
        currentPosition = PlaybackPosition(
            beats: beat,
            timeSignature: currentTimeSignature,
            tempo: currentTempo
        )
    }
    
    // CRITICAL: Protective deinit for @MainActor class (ASan Issue #84742+)
    // Root cause: @MainActor creates implicit actor isolation task-local storage
    deinit {
    }
}
#endif

// MARK: - Safe Audio Node Operations

/// Extension providing safe node operations that won't crash if nodes are in unexpected states.
/// These helpers check preconditions before performing operations that would otherwise crash.
extension AVAudioEngine {
    
    /// Safely detach a node if it's currently attached.
    /// No-op if the node is not attached or is nil.
    /// - Parameter node: The node to detach
    func safeDetach(_ node: AVAudioNode?) {
        guard let node = node else { return }
        
        // Only detach if this engine actually has the node
        guard node.engine === self else { return }
        
        // Disconnect first (some nodes require this)
        disconnectNodeOutput(node)
        disconnectNodeInput(node)
        detach(node)
    }
    
    /// Safely disconnect a node's output if it's connected.
    /// No-op if the node is not attached or has no connections.
    /// - Parameter node: The node whose output to disconnect
    func safeDisconnectOutput(_ node: AVAudioNode?) {
        guard let node = node else { return }
        guard node.engine === self else { return }
        
        // Check if there are any output connections before disconnecting
        let outputCount = node.numberOfOutputs
        guard outputCount > 0 else { return }
        
        disconnectNodeOutput(node)
    }
    
    /// Safely disconnect a node's input if it's connected.
    /// No-op if the node is not attached or has no input connections.
    /// - Parameter node: The node whose input to disconnect
    func safeDisconnectInput(_ node: AVAudioNode?) {
        guard let node = node else { return }
        guard node.engine === self else { return }
        
        // Check if there are any input connections before disconnecting
        let inputCount = node.numberOfInputs
        guard inputCount > 0 else { return }
        
        disconnectNodeInput(node)
    }
}
