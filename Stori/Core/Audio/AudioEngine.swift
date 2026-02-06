//
//  AudioEngine.swift
//  Stori
//
//  Core audio engine for real-time audio processing
//

import Foundation
import AVFoundation
import AVKit
import Combine
import Accelerate
import Observation

// MARK: - Audio Engine Manager
// PERFORMANCE: Using @Observable for fine-grained SwiftUI updates
// Only views that READ a specific property will re-render when that property changes
// This eliminates the "broadcast invalidation" problem of ObservableObject
@Observable
@MainActor
class AudioEngine: AudioEngineContext {
    
    // MARK: - Debug Logging
    /// Enable extensive debug logging for audio flow troubleshooting
    /// Uses centralized debug config (see AudioDebugConfig)
    var debugAudioFlow: Bool { AudioDebugConfig.logAudioFlow }
    
    /// Debug logging with autoclosure to prevent string allocation when disabled
    /// PERFORMANCE: When debugAudioFlow is false, the message closure is never evaluated
    func logDebug(_ message: @autoclosure () -> String, category: String = "AUDIO") {
        guard debugAudioFlow else { return }
        AppLogger.shared.debug("[\(category)] \(message())", category: .audio)
    }
    
    // MARK: - Observable Properties (trigger UI updates when read)
    // Transport state is managed by TransportController; computed properties provide public API
    var transportState: TransportState {
        get { transportController?.transportState ?? .stopped }
        set { transportController?.transportState = newValue }
    }
    var currentPosition: PlaybackPosition {
        get { transportController?.currentPosition ?? PlaybackPosition() }
        set { transportController?.currentPosition = newValue }
    }
    var isRecording: Bool {
        get { recordingController?.isRecording ?? false }
        set { recordingController?.isRecording = newValue }
    }
    var inputLevel: Float {
        get { recordingController?.inputLevel ?? 0.0 }
        set { recordingController?.inputLevel = newValue }
    }
    var audioLevels: [Float] = []
    var isCycleEnabled: Bool {
        get { transportController?.isCycleEnabled ?? false }
        set { transportController?.isCycleEnabled = newValue }
    }
    var cycleStartBeat: Double {
        get { transportController?.cycleStartBeat ?? 0.0 }
        set { transportController?.cycleStartBeat = newValue }
    }
    var masterVolume: Double {
        get { mixerController?.masterVolume ?? 0.8 }
        set { mixerController?.masterVolume = newValue }
    }
    var cycleEndBeat: Double {
        get { transportController?.cycleEndBeat ?? 4.0 }
        set { transportController?.cycleEndBeat = newValue }
    }
    
    /// True when the audio graph is stable and safe for UI to enumerate
    /// Set to false during project load, plugin restoration, etc.
    /// Mixer UI should not open or enumerate nodes while this is false
    var isGraphStable: Bool = true
    
    // MARK: - Track Selection (for record-follows-selection behavior)
    @ObservationIgnored
    var selectedTrackId: UUID?  // Currently selected track in the UI
    
    // MARK: - MIDI Playback
    @ObservationIgnored
    let midiPlaybackEngine = MIDIPlaybackEngine()
    
    // MARK: - Step Sequencer (MIDI-based, persistent instance)
    @ObservationIgnored
    lazy var sequencerEngine: SequencerEngine = {
        let engine = SequencerEngine(tempo: currentProject?.tempo ?? 120.0)
        configureSequencerMIDICallbacks(engine)
        return engine
    }()
    
    // MARK: - Automation
    @ObservationIgnored
    let automationProcessor = AutomationProcessor()
    
    /// High-priority automation engine (runs on dedicated queue)
    @ObservationIgnored
    let automationEngine = AutomationEngine()
    
    /// Automation recorder for capturing parameter changes during playback
    @ObservationIgnored
    let automationRecorder = AutomationRecorder()
    
    // MARK: - Private Properties (all ignored for observation)
    @ObservationIgnored
    let engine = AVAudioEngine()
    @ObservationIgnored
    let mixer = AVAudioMixerNode()
    @ObservationIgnored
    internal let masterEQ = AVAudioUnitEQ(numberOfBands: 3)  // Master EQ: Hi, Mid, Lo (internal for export parity)
    @ObservationIgnored
    private let masterLimiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))
    
    // MARK: - Feedback Protection (Issue #57)
    
    /// Real-time feedback detection and auto-mute protection
    @ObservationIgnored
    private let feedbackMonitor = FeedbackProtectionMonitor()
    
    /// Whether emergency feedback mute is active
    var isFeedbackMuted: Bool = false
    
    // NOTE: Graph mutation coordination is now handled by AudioGraphManager
    
    @ObservationIgnored
    private var pendingGraphMutations: [() -> Void] = []
    
    /// Graph generation counter - delegated to AudioGraphManager
    var graphGeneration: Int {
        graphManager?.graphGeneration ?? 0
    }
    
    /// Error thrown when an async operation is cancelled due to state change
    enum AsyncOperationError: Error, LocalizedError {
        case cancelled(reason: String)
        case staleGraphGeneration
        case staleProjectLoadGeneration
        case trackNotFound(UUID)
        case engineNotRunning
        
        var errorDescription: String? {
            switch self {
            case .cancelled(let reason): return "Operation cancelled: \(reason)"
            case .staleGraphGeneration: return "Graph was modified during async operation"
            case .staleProjectLoadGeneration: return "Project load was superseded by newer load"
            case .trackNotFound(let id): return "Track \(id) not found"
            case .engineNotRunning: return "Audio engine is not running"
            }
        }
    }
    
    /// Check graph generation consistency after an await point
    /// DELEGATED to AudioGraphManager
    func isGraphGenerationValid(_ capturedGeneration: Int, context: String = "") -> Bool {
        let valid = graphManager.isGraphGenerationValid(capturedGeneration)
        if !valid {
            logDebug("Stale operation detected after await: \(context) (captured: \(capturedGeneration), current: \(graphGeneration))", category: "ASYNC")
        }
        return valid
    }
    
    // MARK: - Graph Ready Gate (prevents scheduler from firing during mutations)
    /// When false, MIDI scheduler should not trigger any sounds
    /// This prevents "player started when in a disconnected state" crashes
    @ObservationIgnored
    var isGraphReadyForPlayback: Bool = false
    
    // MARK: - Engine Health Watchdog
    /// Low-priority timer for health checks (runs on .utility queue to avoid audio thread contention; issue #80)
    @ObservationIgnored
    private var engineHealthTimer: DispatchSourceTimer?
    
    /// Queue label and QoS used for health monitoring (exposed for tests; issue #80).
    static let healthMonitorQueueLabelForTesting = "com.stori.engine.health"
    static let healthMonitorQueueQoSForTesting: DispatchQoS.QoSClass = .utility
    
    /// Background queue for health monitoring (utility priority - not critical path; issue #80).
    @ObservationIgnored
    private let healthMonitorQueue = DispatchQueue(
        label: "com.stori.engine.health",
        qos: .utility
    )
    
    /// Whether the engine is expected to be running (for health monitoring)
    @ObservationIgnored
    private var engineExpectedToRun: Bool = false
    
    /// Thread-safe mirror of engineExpectedToRun for health timer (avoids MainActor hop every tick)
    @ObservationIgnored
    private nonisolated(unsafe) var _atomicEngineExpectedToRun: Bool = false
    
    /// Thread-safe cache of engine.isRunning; updated on MainActor when we run checkEngineHealth or start/stop
    @ObservationIgnored
    private nonisolated(unsafe) var _atomicLastKnownEngineRunning: Bool = false
    
    /// Tick counter for health timer (only accessed from healthMonitorQueue). Used for staggered refresh.
    @ObservationIgnored
    private nonisolated(unsafe) var _healthCheckTickCount: Int = 0
    
    /// Refresh every N ticks when engine expected running; back off when playing to reduce CPU impact (issue #80).
    private static let healthCheckRefreshTicksWhenStopped = 6
    private static let healthCheckRefreshTicksWhenPlaying = 15
    
    /// Count of consecutive health check failures (for escalating recovery)
    @ObservationIgnored
    private var healthCheckFailureCount: Int = 0
    
    // MARK: - Metronome (installed into audio graph for sample-accurate sync)
    /// Reference to the metronome engine - installed during setup, before engine starts
    private weak var installedMetronome: MetronomeEngine?
    
    // MARK: - Public Accessors for Shared Audio Engine
    /// Provides access to the underlying AVAudioEngine for components that need to share it
    /// (e.g., MetronomeEngine for sample-accurate sync)
    var sharedAVAudioEngine: AVAudioEngine { engine }
    
    /// Provides access to the main mixer for components that need to connect to it
    /// (e.g., MetronomeEngine for audio routing)
    var sharedMixer: AVAudioMixerNode { mixer }
    
    /// Current sample rate of the audio engine (derived from hardware)
    /// Use this when configuring plugins or audio nodes to match the live engine rate
    var currentSampleRate: Double {
        graphFormat?.sampleRate ?? engine.outputNode.inputFormat(forBus: 0).sampleRate
    }
    
    /// Current project tempo in BPM
    var currentTempo: Double {
        currentProject?.tempo ?? 120.0
    }
    
    /// Current time signature
    var currentTimeSignature: TimeSignature {
        currentProject?.timeSignature ?? .fourFour
    }
    
    /// Current scheduling context (unified timing information)
    /// Use this for all beat/sample/seconds conversions
    var schedulingContext: AudioSchedulingContext {
        AudioSchedulingContext(
            sampleRate: currentSampleRate,
            tempo: currentTempo,
            timeSignature: currentTimeSignature
        )
    }
    
    /// Thread-safe beat position (for MIDI scheduler and automation engine)
    /// Uses nonisolated(unsafe) reference to access TransportController's atomic properties
    nonisolated var atomicBeatPosition: Double {
        _transportControllerRef?.atomicBeatPosition ?? 0
    }
    
    /// Thread-safe playing state (for MIDI scheduler and automation engine)
    /// Uses nonisolated(unsafe) reference to access TransportController's atomic properties
    nonisolated var atomicIsPlaying: Bool {
        _transportControllerRef?.atomicIsPlaying ?? false
    }
    
    // MARK: - Graph Audio Format
    @ObservationIgnored
    var graphFormat: AVAudioFormat!
    
    // MARK: - Rebuild Coalescing (prevents rebuild storms)
    @ObservationIgnored
    var pendingRebuildTrackIds: Set<UUID> = []
    
    @ObservationIgnored
    var rebuildTask: Task<Void, Never>?
    
    /// PERFORMANCE: Cache of last graph state per track.
    /// Used to skip redundant rebuilds when state hasn't actually changed.
    @ObservationIgnored
    var lastGraphState: [UUID: GraphStateSnapshot] = [:]
    
    /// Install a metronome into the audio graph (idempotent, safe to call multiple times)
    /// Handles the case where engine might already be running
    func installMetronome(_ metronome: MetronomeEngine) {
        // If already installed, skip
        guard installedMetronome == nil else { return }
        
        // Check if engine is running - if so, we need to stop/restart
        let wasRunning = engine.isRunning
        if wasRunning {
            engine.pause()
        }
        
        // Install the metronome nodes
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: self,
            transportController: transportController,
            midiScheduler: midiPlaybackEngine.sampleAccurateScheduler
        )
        installedMetronome = metronome
        
        // Restart if it was running
        if wasRunning {
            do {
                // Wrap engine.start() in ObjC exception handler since it can throw
                // NSException (not Swift Error) when the audio graph is inconsistent
                try tryObjC { try? self.engine.start() }
                // Start the metronome player node (keeps it ready for scheduling)
                metronome.preparePlayerNode()
            } catch {
                // Engine failed to restart after metronome install
                // The engine will be started on next playback attempt
                logDebug("⚠️ Engine restart after metronome install failed: \(error)", category: "METRONOME")
            }
        }
    }
    // MARK: - Track Node Manager (Extracted)
    /// Manages track audio node lifecycle: creation, destruction, and access
    @ObservationIgnored
    private var trackNodeManager: TrackNodeManager!
    
    /// Computed accessor for track nodes (delegates to TrackNodeManager)
    internal var trackNodes: [UUID: TrackAudioNode] {
        trackNodeManager?.getAllTrackNodes() ?? [:]
    }
    
    // MARK: - Bus Manager (Extracted)
    /// Handles all bus nodes, bus effects, and track sends
    @ObservationIgnored
    private var busManager: BusManager!
    
    // MARK: - Project Lifecycle Manager (Extracted)
    /// Handles project loading, unloading, and state transitions
    @ObservationIgnored
    private var projectLifecycleManager: ProjectLifecycleManager!
    
    // MARK: - Device Configuration Manager (Extracted)
    /// Handles audio device configuration changes and format updates
    @ObservationIgnored
    private var deviceConfigManager: DeviceConfigurationManager!
    
    // MARK: - Playback Scheduling Coordinator (Extracted)
    /// Coordinates audio track scheduling and cycle loop handling
    @ObservationIgnored
    var playbackScheduler: PlaybackSchedulingCoordinator!
    
    // MARK: - Audio Graph Manager (Extracted)
    /// Manages audio graph mutations with tiered performance characteristics
    @ObservationIgnored
    private var graphManager: AudioGraphManager!
    
    // MARK: - Engine Health Monitor
    /// Validates engine state consistency and detects desyncs
    @ObservationIgnored
    private var healthMonitor: AudioEngineHealthMonitor!
    
    /// Error tracker for surfacing critical issues
    @ObservationIgnored
    private var errorTracker: AudioEngineErrorTracker { AudioEngineErrorTracker.shared }
    
    /// Computed accessor for bus nodes (delegates to BusManager)
    private var busNodes: [UUID: BusAudioNode] {
        busManager?.busNodes ?? [:]
    }
    
    /// Computed accessor for solo tracks (delegates to MixerController)
    private var soloTracks: Set<UUID> {
        mixerController?.soloTracks ?? []
    }
    
    // Recording properties are now managed by RecordingController
    
    // MARK: - Metering Service (Extracted)
    /// Handles all level metering and LUFS loudness analysis
    @ObservationIgnored
    private var meteringService: MeteringService!
    
    // MARK: - Transport Controller (Extracted)
    /// Handles transport state, position tracking, and cycle behavior
    @ObservationIgnored
    var transportController: TransportController!
    
    /// Nonisolated reference for cross-thread atomic state access
    /// SAFETY: Only used to access TransportController's thread-safe atomic properties
    @ObservationIgnored
    private nonisolated(unsafe) var _transportControllerRef: TransportController?
    
    // MARK: - Recording Controller (Extracted)
    /// Handles audio/MIDI recording, input monitoring, and mic permissions
    @ObservationIgnored
    private var recordingController: RecordingController!
    
    // MARK: - Mixer Controller (Extracted)
    /// Handles track/master volume, pan, mute, solo, and EQ
    @ObservationIgnored
    private var mixerController: MixerController!
    
    // MARK: - Track Plugin Manager (Extracted)
    /// Handles track insert plugins, PDC, and sidechain routing
    @ObservationIgnored
    private var trackPluginManager: TrackPluginManager!
    
    // MARK: - Master Metering (Delegated to MeteringService)
    var masterLevelLeft: Float { meteringService.masterLevelLeft }
    var masterLevelRight: Float { meteringService.masterLevelRight }
    var masterPeakLeft: Float { meteringService.masterPeakLeft }
    var masterPeakRight: Float { meteringService.masterPeakRight }
    
    // MARK: - LUFS Loudness Metering (Delegated to MeteringService)
    var loudnessMomentary: Float { meteringService.loudnessMomentary }
    var loudnessShortTerm: Float { meteringService.loudnessShortTerm }
    var loudnessIntegrated: Float { meteringService.loudnessIntegrated }
    var truePeak: Float { meteringService.truePeak }
    
    // MARK: - Current Project (Computed - ProjectManager is Single Source of Truth)
    /// Project state is owned by ProjectManager. This computed property provides
    /// convenient access while ensuring single source of truth.
    /// Falls back to internal snapshot during initialization before configure() is called.
    var currentProject: AudioProject? {
        get { 
            projectManager?.currentProject ?? _projectSnapshot 
        }
        set { 
            if let pm = projectManager {
                pm.currentProject = newValue
            } else {
                _projectSnapshot = newValue
            }
        }
    }
    
    /// Internal snapshot used only before configure() is called
    @ObservationIgnored
    private var _projectSnapshot: AudioProject?
    
    // MARK: - Project Manager Reference (Single Source of Truth)
    @ObservationIgnored
    private weak var projectManager: ProjectManager?
    
    /// Configure the AudioEngine with a reference to the ProjectManager.
    /// This establishes ProjectManager as the single source of truth for project state.
    /// After configuration, the internal snapshot is discarded.
    func configure(projectManager: ProjectManager) {
        self.projectManager = projectManager
        // Transfer any early-loaded project to ProjectManager
        if let snapshot = _projectSnapshot, projectManager.currentProject == nil {
            projectManager.currentProject = snapshot
        }
        _projectSnapshot = nil
    }
    
    // MARK: - Plugin Installation Lock
    @ObservationIgnored
    private var isInstallingPlugin: Bool = false
    
    // MARK: - Initialization
    init() {
        // PERFORMANCE: Enable FPU denormal flushing to prevent slowdowns
        // Denormal numbers (very small floats near zero) cause massive CPU spikes
        // because they require special handling by the FPU. Flushing them to zero
        // is standard practice in professional audio software.
        // Note: Apple's Accelerate/vDSP framework already handles denormals internally,
        // and AVAudioEngine sets appropriate flags on its render threads.
        // We document this here for awareness - no additional action needed.
        
        // Initialize metering service first (needs closures to access shared state)
        meteringService = MeteringService(
            trackNodes: { [weak self] in self?.trackNodes ?? [:] },
            masterVolume: { [weak self] in Float(self?.masterVolume ?? 0.8) }
        )
        
        setupAudioEngine()
        
        // Initialize transport controller
        transportController = TransportController(
            getProject: { [weak self] in self?.currentProject },
            isInstallingPlugin: { [weak self] in self?.isInstallingPlugin ?? false },
            isGraphStable: { [weak self] in self?.isGraphStable ?? true },
            getSampleRate: { [weak self] in self?.currentSampleRate ?? 48000 },
            onStartPlayback: { [weak self] fromBeat in self?.performStartPlayback(fromBeat: fromBeat) },
            onStopPlayback: { [weak self] in self?.performStopPlayback() },
            onTransportStateChanged: { [weak self] state in self?.handleTransportStateChanged(state) },
            onPositionChanged: { [weak self] position in self?.handlePositionChanged(position) },
            onCycleJump: { [weak self] toBeat in self?.handleCycleJump(toBeat: toBeat) }
        )
        
        // Store nonisolated reference for cross-thread atomic state access
        _transportControllerRef = transportController
        
        // Initialize track node manager
        trackNodeManager = TrackNodeManager()
        trackNodeManager.engine = engine
        trackNodeManager.getGraphFormat = { [weak self] in self?.graphFormat }
        trackNodeManager.onEnsureEngineRunning = { [weak self] in self?.startAudioEngine() }
        trackNodeManager.onRebuildTrackGraph = { [weak self] trackId in self?.rebuildTrackGraph(trackId: trackId) }
        trackNodeManager.onSafeDisconnectTrackNode = { [weak self] trackNode in self?.safeDisconnectTrackNode(trackNode) }
        trackNodeManager.onLoadAudioRegion = { [weak self] region, trackNode in self?.loadAudioRegion(region, trackNode: trackNode) }
        trackNodeManager.onPerformBatchOperation = { [weak self] work in self?.performBatchGraphOperation(work) }
        trackNodeManager.onUpdateAutomationTrackCache = { [weak self] in self?.updateAutomationTrackCache() }
        trackNodeManager.mixer = mixer
        // Note: installedMetronome and mixerController are set after they're initialized
        
        // Initialize bus manager after audio engine is set up
        busManager = BusManager(
            engine: engine,
            mixer: mixer,
            trackNodes: { [weak self] in self?.trackNodes ?? [:] },
            currentProject: { [weak self] in self?.currentProject },
            transportState: { [weak self] in self?.transportController?.transportState ?? .stopped },
            modifyGraphSafely: { [weak self] work in try self?.modifyGraphSafely(work) },
            updateSoloState: { [weak self] in self?.updateSoloState() },
            reconnectMetronome: { [weak self] in self?.installedMetronome?.reconnectNodes(dawMixer: self?.mixer ?? AVAudioMixerNode()) },
            setupPositionTimer: { [weak self] in self?.transportController?.setupPositionTimer() },
            isInstallingPlugin: { [weak self] in self?.isInstallingPlugin ?? false },
            setIsInstallingPlugin: { [weak self] value in self?.isInstallingPlugin = value }
        )
        
        // Initialize recording controller
        recordingController = RecordingController(
            engine: engine,
            mixer: mixer,
            transportController: transportController,  // NEW: For thread-safe position in audio callbacks
            getProject: { [weak self] in self?.currentProject },
            getCurrentPosition: { [weak self] in self?.currentPosition ?? PlaybackPosition() },
            getSelectedTrackId: { [weak self] in self?.selectedTrackId },
            onStartRecordingMode: { [weak self] in self?.transportController?.startRecordingMode() },
            onStopRecordingMode: { [weak self] in self?.transportController?.stopRecordingMode() },
            onStartPlayback: { [weak self] in self?.startPlayback() },
            onStopPlayback: { [weak self] in self?.stopPlayback() },
            onProjectUpdated: { [weak self] project in self?.currentProject = project },
            onReconnectMetronome: { [weak self] in self?.installedMetronome?.reconnectNodes(dawMixer: self?.mixer ?? AVAudioMixerNode()) },
            loadProject: { [weak self] project in self?.loadProject(project) }
        )
        
        // Initialize mixer controller
        // NOTE: currentProject is now a computed property that uses ProjectManager as single source of truth
        mixerController = MixerController(
            getProject: { [weak self] in self?.currentProject },
            setProject: { [weak self] project in self?.currentProject = project },
            getTrackNodes: { [weak self] in self?.trackNodes ?? [:] },
            getMainMixer: { [weak self] in self?.mixer ?? AVAudioMixerNode() },
            getMasterEQ: { [weak self] in self?.masterEQ ?? AVAudioUnitEQ(numberOfBands: 3) },
            onReloadMIDIRegions: { [weak self] in
                if let project = self?.currentProject {
                    self?.midiPlaybackEngine.loadRegions(from: project.tracks, tempo: project.tempo)
                }
            },
            onSafeDisconnectTrackNode: { [weak self] trackNode in
                self?.safeDisconnectTrackNode(trackNode)
            }
        )
        
        // Wire up mixerController dependency for trackNodeManager
        trackNodeManager.mixerController = mixerController
        
        // Initialize track plugin manager
        // NOTE: getTrackInstruments removed - instruments are now accessed via InstrumentManager.shared
        trackPluginManager = TrackPluginManager(
            getEngine: { [weak self] in self?.engine ?? AVAudioEngine() },
            getProject: { [weak self] in self?.currentProject },
            setProject: { [weak self] project in self?.currentProject = project },
            getTrackNodes: { [weak self] in self?.trackNodes ?? [:] },
            getBusNodes: { [weak self] in self?.busNodes ?? [:] },
            getGraphFormat: { [weak self] in self?.graphFormat },
            isInstallingPlugin: { [weak self] in self?.isInstallingPlugin ?? false },
            setIsInstallingPlugin: { [weak self] value in self?.isInstallingPlugin = value },
            onRebuildTrackGraph: { [weak self] trackId in self?.rebuildTrackGraph(trackId: trackId) },
            onRebuildPluginChain: { [weak self] trackId in self?.rebuildPluginChain(trackId: trackId) },
            onModifyGraphSafely: { [weak self] work in self?.modifyGraphSafely(work) }
        )
        
        // Initialize project lifecycle manager
        projectLifecycleManager = ProjectLifecycleManager()
        projectLifecycleManager.engine = engine
        projectLifecycleManager.automationProcessor = automationProcessor
        projectLifecycleManager.onSetupTracks = { [weak self] project in self?.setupTracksForProject(project) }
        projectLifecycleManager.onSetupBuses = { [weak self] project in self?.setupBusesForProject(project) }
        projectLifecycleManager.onUpdateAutomation = { [weak self] in self?.updateAllTrackAutomation() }
        projectLifecycleManager.onRestorePlugins = { [weak self] in await self?.restorePluginsFromProject() }
        projectLifecycleManager.onConnectInstruments = { [weak self] project in await self?.createAndConnectMIDIInstruments(for: project) }
        projectLifecycleManager.onValidateConnections = { [weak self] in self?.validateAllTrackConnections() }
        projectLifecycleManager.onStartEngine = { [weak self] in self?.startAudioEngine() }
        projectLifecycleManager.onStopPlayback = { [weak self] in self?.stopPlayback() }
        projectLifecycleManager.onSetGraphStable = { [weak self] value in self?.isGraphStable = value }
        projectLifecycleManager.onSetGraphReady = { [weak self] value in self?.isGraphReadyForPlayback = value }
        projectLifecycleManager.onSetTransportStopped = { [weak self] in self?.transportState = .stopped }
        projectLifecycleManager.logDebug = { [weak self] message, category in self?.logDebug(message, category: category) }
        projectLifecycleManager.onProjectLoaded = { [weak self] project in
            // print("\n🎉 PROJECT LOADED: '\(project.name)'")  // DEBUG: Disabled for production
        }
        
        // Initialize device configuration manager
        deviceConfigManager = DeviceConfigurationManager()
        deviceConfigManager.engine = engine
        deviceConfigManager.mixer = mixer
        deviceConfigManager.masterEQ = masterEQ
        deviceConfigManager.masterLimiter = masterLimiter
        deviceConfigManager.getGraphFormat = { [weak self] in self?.graphFormat }
        deviceConfigManager.setGraphFormat = { [weak self] format in self?.graphFormat = format }
        deviceConfigManager.getTrackNodes = { [weak self] in self?.trackNodes ?? [:] }
        deviceConfigManager.getCurrentProject = { [weak self] in self?.currentProject }
        deviceConfigManager.busManager = busManager
        deviceConfigManager.midiPlaybackEngine = midiPlaybackEngine
        deviceConfigManager.transportController = transportController
        deviceConfigManager.installedMetronome = installedMetronome
        deviceConfigManager.getTransportState = { [weak self] in self?.transportState ?? .stopped }
        deviceConfigManager.getCurrentPosition = { [weak self] in self?.currentPosition ?? PlaybackPosition() }
        deviceConfigManager.onStop = { [weak self] in self?.stop() }
        deviceConfigManager.onSeekToBeat = { [weak self] beat in self?.seekToBeat(beat) }
        deviceConfigManager.onPlay = { [weak self] in self?.play() }
        deviceConfigManager.onReconnectAllTracks = { [weak self] in self?.reconnectAllTracksAfterFormatChange() }
        deviceConfigManager.onReprimeInstruments = { [weak self] in self?.reprimeAllInstrumentsAfterReset() }
        deviceConfigManager.setGraphReady = { [weak self] value in self?.isGraphReadyForPlayback = value }
        
        // Initialize playback scheduling coordinator
        playbackScheduler = PlaybackSchedulingCoordinator()
        playbackScheduler.engine = engine
        playbackScheduler.getTrackNodes = { [weak self] in self?.trackNodes ?? [:] }
        playbackScheduler.getCurrentProject = { [weak self] in self?.currentProject }
        playbackScheduler.midiPlaybackEngine = midiPlaybackEngine
        playbackScheduler.installedMetronome = installedMetronome
        playbackScheduler.logDebug = { [weak self] message, category in self?.logDebug(message, category: category) }
        
        // Initialize audio graph manager
        graphManager = AudioGraphManager()
        graphManager.engine = engine
        graphManager.mixer = mixer
        graphManager.getTrackNodes = { [weak self] in self?.trackNodes ?? [:] }
        graphManager.getCurrentProject = { [weak self] in self?.currentProject }
        graphManager.midiPlaybackEngine = midiPlaybackEngine
        graphManager.transportController = transportController
        graphManager.installedMetronome = installedMetronome
        graphManager.getTransportState = { [weak self] in self?.transportState ?? .stopped }
        graphManager.getCurrentPosition = { [weak self] in self?.currentPosition ?? PlaybackPosition() }
        graphManager.setGraphReady = { [weak self] value in self?.isGraphReadyForPlayback = value }
        graphManager.onPlayFromBeat = { [weak self] beat in self?.playFromBeat(beat) }
        
        // Initialize health monitor
        healthMonitor = AudioEngineHealthMonitor()
        healthMonitor.configure(
            engine: engine,
            mixer: mixer,
            masterEQ: masterEQ,
            masterLimiter: masterLimiter,
            getGraphFormat: { [weak self] in self?.graphFormat },
            getIsGraphStable: { [weak self] in self?.isGraphStable ?? true },
            getIsGraphReady: { [weak self] in self?.isGraphReadyForPlayback ?? false },
            getTrackNodes: { [weak self] in self?.trackNodes ?? [:] }
        )
        
        transportController.setupPositionTimer()
        automationRecorder.configure(audioEngine: self)
        configureAutomationEngine()
        setupProjectSaveObserver()
        setupAudioConfigurationChangeObserver()
        setupTempoChangeObserver()
    }
    
    /// Configure the high-priority automation engine - delegates to extension
    private func configureAutomationEngine() {
        configureAutomationEngineInternal()
    }
    
    /// Setup observer for tempo changes during playback
    /// Resyncs timing references to prevent MIDI/audio drift
    private func setupTempoChangeObserver() {
        NotificationCenter.default.addObserver(
            forName: .tempoChanged,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            
            // Resync transport timing references
            self.transportController?.syncTempoChange()
            
            // Resync MIDI playback engine
            if let newTempo = notification.object as? Double {
                self.midiPlaybackEngine.setTempo(newTempo)
            }
            
            // NOTE: AutomationEngine queries beat position from transport,
            // which already handles tempo changes. No explicit update needed.
            // The automation engine works in beats, not time, so tempo changes
            // are automatically reflected through the beat position provider.
        }
    }
    
    /// Setup observer to save plugin states when project is saved
    private func setupProjectSaveObserver() {
        NotificationCenter.default.addObserver(
            forName: .willSaveProject,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.saveAllPluginConfigs()
            }
        }
    }
    
    // MARK: - Audio Configuration Change (Delegated to DeviceConfigurationManager)
    
    /// Setup observer for audio hardware configuration changes
    /// DELEGATED to DeviceConfigurationManager
    private func setupAudioConfigurationChangeObserver() {
        deviceConfigManager.setupObserver()
    }
    
    // NOTE: handleAudioConfigurationChange is now handled by DeviceConfigurationManager
    
    /// Reconnect all track signal chains after a device format change.
    /// Each track's panNode must be reconnected to the mixer with the new graphFormat.
    private func reconnectAllTracksAfterFormatChange() {
        guard let project = currentProject else { return }
        
        for (trackId, trackNode) in trackNodes {
            let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) ?? 0
            let trackBusNumber = AVAudioNodeBus(trackIndex)
            
            engine.disconnectNodeOutput(trackNode.panNode)
            engine.connect(trackNode.panNode, to: mixer, fromBus: 0, toBus: trackBusNumber, format: graphFormat)
        }
    }
    
    /// Re-prime all instruments after engine.reset() to reallocate render resources.
    /// This is critical because reset() deallocates render resources; samplers won't produce
    /// audio until they're explicitly reinitialized.
    /// 
    /// Also reconnects samplers with the new graphFormat - delegates to extension
    private func reprimeAllInstrumentsAfterReset() {
        reprimeAllInstrumentsAfterResetInternal()
    }
    
    /// Reset DSP state for all active samplers after device change - delegates to extension
    private func resetAllSamplerDSPState() {
        resetAllSamplerDSPStateInternal()
    }
    
    // MARK: - Sample Rate Diagnostics
    
    /// Dump sample rate information for debugging
    /// Call this to verify sample rates are consistent across the audio graph
    func dumpSampleRateInfo() {
        let hardwareInputRate = engine.outputNode.inputFormat(forBus: 0).sampleRate
        let hardwareOutputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let graphRate = graphFormat?.sampleRate ?? 0
        
        logDebug("=== Sample Rate Diagnostic ===", category: "SAMPLERATE")
        logDebug("Hardware Input Format: \(hardwareInputRate) Hz", category: "SAMPLERATE")
        logDebug("Hardware Output Format: \(hardwareOutputRate) Hz", category: "SAMPLERATE")
        logDebug("Engine Graph Format: \(graphRate) Hz", category: "SAMPLERATE")
        
        // Log project sample rate if available
        if let project = currentProject {
            logDebug("Project Sample Rate: \(project.sampleRate) Hz (used for export/offline)", category: "SAMPLERATE")
        }
        
        // Log each track's plugin chain format
        for (trackId, trackNode) in trackNodes {
            let chainFormat = trackNode.pluginChain.format?.sampleRate ?? 0
            let trackName = currentProject?.tracks.first { $0.id == trackId }?.name ?? "Unknown"
            logDebug("Track '\(trackName)': chainFormat=\(chainFormat) Hz", category: "SAMPLERATE")
        }
        
        logDebug("==============================", category: "SAMPLERATE")
    }
    
    /// Save plugin configurations for all tracks
    /// Called before project is saved to ensure current parameter values are persisted
    @MainActor
    func saveAllPluginConfigs() async {
        guard let project = currentProject else {
            // Still post notification so ProjectManager doesn't wait forever
            NotificationCenter.default.post(name: .pluginConfigsSaved, object: currentProject)
            return 
        }
        
        var configsSaved = 0
        for track in project.tracks {
            if let pluginChain = trackNodes[track.id]?.pluginChain {
                let plugins = pluginChain.slots.compactMap { $0 }
                if !plugins.isEmpty {
                    for (_, plugin) in plugins.enumerated() {
                        if let au = plugin.auAudioUnit {
                            _ = au.fullState != nil
                            _ = au.fullState?.keys.count ?? 0
                            // Log actual parameter values
                            if let tree = au.parameterTree {
                                _ = tree.allParameters.prefix(3)
                            }
                        }
                    }
                    // triggerSave: false to avoid feedback loop - we're already in save flow
                    await savePluginConfigsToProject(trackId: track.id, triggerSave: false)
                    configsSaved += plugins.count
                }
            }
        }
        
        // Post notification with updated project so ProjectManager can save it
        NotificationCenter.default.post(name: .pluginConfigsSaved, object: currentProject)
    }
    
    deinit {
        // CRITICAL: Protective deinit for @Observable @MainActor class (ASan Issue #84742+)
        // Root cause: @Observable classes have implicit Swift Concurrency tasks
        // for property change notifications that can cause bad-free on deinit.
        // Empty deinit ensures proper Swift Concurrency / TaskLocal cleanup order.
        // See: AudioAnalyzer, MetronomeEngine, AutomationEngine; https://github.com/apple/swift/issues/84742
        // Note: Cannot access @MainActor properties in deinit.
        
        // FIX Issue #72: Cancel health timer to prevent retain cycle
        // Timer is @ObservationIgnored so it's safe to access here
        engineHealthTimer?.cancel()
    }
    
    // MARK: - Lifecycle Management (Issue #72)
    
    /// Clean up audio engine resources explicitly.
    /// Call this before releasing references to AudioEngine to ensure proper cleanup.
    /// This method prevents timer retain cycles and ensures deterministic resource release.
    ///
    /// ARCHITECTURE NOTE: While timers use [weak self], explicitly cancelling them
    /// prevents edge cases where the timer fires during deallocation.
    func cleanup() {
        // Stop playback first
        if transportController.transportState.isPlaying {
            transportController.stop()
        }
        
        // Stop automation processor
        automationProcessor.stop()
        
        // Stop MIDI playback and scheduler
        midiPlaybackEngine.stop()
        
        // Stop metronome
        metronomeEngine.stop()
        
        // Stop health monitoring timer (prevents retain cycle - Issue #72)
        stopEngineHealthMonitoring()
        
        // Stop transport position timer
        transportController.stopPositionTimer()
        
        // Stop audio engine
        if engine.isRunning {
            engine.stop()
        }
        
        // Clear all audio nodes
        for node in trackNodes.values {
            safeDisconnectTrackNode(node)
        }
        trackNodes.removeAll()
        
        AppLogger.shared.debug("AudioEngine cleanup completed", category: .audio)
    }
    
    // MARK: - Audio Engine Setup
    private func setupAudioEngine() {
        // Attach nodes
        engine.attach(mixer)
        engine.attach(masterEQ)
        engine.attach(masterLimiter)
        
        // Get device format and set stable graphFormat for ALL connections
        let deviceFormat = engine.outputNode.inputFormat(forBus: 0)
        graphFormat = AVAudioFormat(
            standardFormatWithSampleRate: deviceFormat.sampleRate,
            channels: 2
        )!
        
        // Connect: mixer → masterEQ → masterLimiter → output
        // SAFETY: Master limiter prevents clipping at the output stage
        engine.connect(mixer, to: masterEQ, format: graphFormat)
        engine.connect(masterEQ, to: masterLimiter, format: graphFormat)
        engine.connect(masterLimiter, to: engine.outputNode, format: graphFormat)
        
        // Configure master EQ bands
        setupMasterEQ()
        
        // Configure master limiter (subtle ceiling at -0.1 dBFS to prevent ISP)
        setupMasterLimiter()
        
        // Set default master volume to match published property
        mixer.outputVolume = Float(masterVolume)
        
        // Install clipping detection taps (DEBUG only)
        // DISABLED: Taps themselves can cause clicks during tests
        // #if DEBUG
        // installClippingDetectionTaps()
        // #endif
       
        // Start the engine
        startAudioEngine()
        
        // Configure high-precision MIDI scheduling after engine is running
        midiPlaybackEngine.configureSampleAccurateScheduling(
            avEngine: engine,
            sampleRate: graphFormat.sampleRate,
            transportController: transportController
        )
        
        // Start engine health monitoring
        setupEngineHealthMonitoring()
        
        // Setup master metering after engine is running
        setupMasterMeterTap()
        
        // Log sample rate diagnostic info on startup
        dumpSampleRateInfo()
        
        // print("\n🚀 AUDIO ENGINE INITIALIZED")  // DEBUG: Disabled for production
    }
    
    private func setupMasterMeterTap() {
        // Delegate to MeteringService
        meteringService.installMasterMeterTap(on: masterEQ)
    }
    
    /// Reset integrated loudness (call at start of new measurement)
    func resetIntegratedLoudness() {
        meteringService.resetIntegratedLoudness()
    }
    
    private func setupMasterEQ() {
        // Configure 3-band master EQ
        guard masterEQ.bands.count >= 3 else { return }
        
        // Band 0: High Shelf (8000 Hz)
        masterEQ.bands[0].filterType = .highShelf
        masterEQ.bands[0].frequency = 8000
        masterEQ.bands[0].gain = 0.0
        masterEQ.bands[0].bypass = false
        
        // Band 1: Mid Parametric (1000 Hz)
        masterEQ.bands[1].filterType = .parametric
        masterEQ.bands[1].frequency = 1000
        masterEQ.bands[1].bandwidth = 1.0
        masterEQ.bands[1].gain = 0.0
        masterEQ.bands[1].bypass = false
        
        // Band 2: Low Shelf (200 Hz)
        masterEQ.bands[2].filterType = .lowShelf
        masterEQ.bands[2].frequency = 200
        masterEQ.bands[2].gain = 0.0
        masterEQ.bands[2].bypass = false
    }
    
    /// Configure master limiter to prevent clipping
    /// Uses Apple's built-in PeakLimiter with subtle ceiling
    private func setupMasterLimiter() {
        let auAudioUnit = masterLimiter.auAudioUnit
        
        // Configure limiter parameters via the parameter tree
        guard let parameterTree = auAudioUnit.parameterTree else {
            AppLogger.shared.warning("Master limiter: No parameter tree available", category: .audio)
            return
        }
        
        // Apple's PeakLimiter parameters:
        // - Attack Time: 0.001 - 0.03 seconds (parameter ID 0)
        // - Release Time: 0.001 - 0.5 seconds (parameter ID 1)
        // - Pre-Gain: -40 - +40 dB (parameter ID 2)
        
        // ISSUE #57 FIX: More aggressive limiting for feedback protection
        // Set very fast attack for feedback protection (1ms)
        if let attackParam = parameterTree.parameter(withAddress: 0) {
            attackParam.value = 0.001  // 1ms attack (was 5ms) - catches feedback faster
        }
        
        // Set fast release to recover quickly after spike
        if let releaseParam = parameterTree.parameter(withAddress: 1) {
            releaseParam.value = 0.05  // 50ms release (was 100ms) - faster recovery
        }
        
        // Pre-gain at 0 dB (unity)
        if let preGainParam = parameterTree.parameter(withAddress: 2) {
            preGainParam.value = 0.0
        }
        
        AppLogger.shared.debug("Master limiter configured for feedback protection (1ms attack, 50ms release)", category: .audio)
    }
    
    /// Install audio taps to detect clipping at various points in the signal chain (DEBUG only)
    private func installClippingDetectionTaps() {
        // Tap after mixer (before EQ/limiter) - includes feedback protection monitoring
        mixer.installTap(onBus: 0, bufferSize: 512, format: graphFormat) { [weak self] buffer, time in
            guard let self = self else { return }
            
            // Check for feedback (Issue #57)
            if self.feedbackMonitor.processBuffer(buffer) {
                // Feedback detected! Trigger emergency protection on main thread
                Task { @MainActor in
                    self.triggerFeedbackProtection()
                }
            }
            
            self.detectClipping(in: buffer, location: "MIXER OUTPUT (pre-EQ)")
        }
        
        // Tap after limiter (final output)
        masterLimiter.installTap(onBus: 0, bufferSize: 512, format: graphFormat) { [weak self] buffer, time in
            self?.detectClipping(in: buffer, location: "MASTER OUTPUT (post-limiter)")
        }
        
        // Start feedback monitoring
        feedbackMonitor.startMonitoring()
        
        AppLogger.shared.info("Feedback protection: Monitoring enabled", category: .audio)
        // print("🔍 CLIPPING DETECTION: Taps installed on mixer and master output")  // DEBUG: Disabled for production
    }
    
    /// Detect and log clipping in an audio buffer
    private func detectClipping(in buffer: AVAudioPCMBuffer, location: String) {
        guard let channelData = buffer.floatChannelData else { return }
        
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        
        var maxSample: Float = 0
        var clippedFrames = 0
        
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                let sample = abs(channelData[channel][frame])
                maxSample = max(maxSample, sample)
                
                if sample > 0.99 {  // Near clipping threshold
                    clippedFrames += 1
                }
            }
        }
        
        if clippedFrames > 0 || maxSample > 0.95 {
            print("⚠️ CLIPPING DETECTED at \(location): \(clippedFrames) frames, max: \(maxSample)")
        }
    }
    
    // MARK: - Feedback Protection (Issue #57)
    
    /// Trigger emergency feedback protection
    /// Called when feedback loop is detected - mutes master output immediately
    private func triggerFeedbackProtection() {
        guard !isFeedbackMuted else { return }
        
        // Emergency mute
        isFeedbackMuted = true
        let previousVolume = mixer.outputVolume
        mixer.outputVolume = 0.0
        
        // Stop playback
        stop()
        
        // Log the event
        AppLogger.shared.error("FEEDBACK PROTECTION: Emergency mute triggered! Previous volume: \(previousVolume)", category: .audio)
        
        // Show warning to user
        let message = """
        ⚠️ FEEDBACK LOOP DETECTED
        
        Audio has been automatically muted to protect your speakers and hearing.
        
        Possible causes:
        • Bus routing feedback loop
        • Plugin feedback (delay/reverb with high feedback %)
        • Parallel routing creating feedback path
        • Excessive automation gain
        
        Please check your routing and reduce gain/feedback levels before unmuting.
        
        To unmute: Lower master volume, fix routing, then unmute manually.
        """
        
        // Notify user (could be shown in UI as alert)
        feedbackMonitor.triggerEmergencyProtection(currentLevel: previousVolume)
        
        // Could add UI notification here via SwiftUI @Published if needed
        print("🚨 \(message)")
    }
    
    /// Reset feedback protection and allow unmuting
    /// Call after user fixes routing issues
    func resetFeedbackProtection() {
        isFeedbackMuted = false
        feedbackMonitor.resetFeedbackState()
        AppLogger.shared.info("Feedback protection: Reset by user", category: .audio)
    }
    
    // MARK: - Engine Start Recovery
    
    /// Current retry attempt for engine start (for exponential backoff)
    @ObservationIgnored
    private var engineStartRetryAttempt = 0
    
    /// Maximum retry attempts for engine start
    private static let maxEngineStartRetries = 5
    
    /// Base delay for exponential backoff (doubles each attempt)
    private static let engineStartBaseDelay: TimeInterval = 0.1
    
    private func startAudioEngine() {
        guard !engine.isRunning else { 
            engineStartRetryAttempt = 0  // Reset on success
            return 
        }
        
        do {
            // Ensure we have proper audio format
            let format = engine.outputNode.outputFormat(forBus: 0)
            
            // Update PDC with actual hardware sample rate
            PluginLatencyManager.shared.setSampleRate(format.sampleRate)
            
            try engine.start()
            
            // Verify it's actually running
            if engine.isRunning {
                isGraphReadyForPlayback = true
                engineExpectedToRun = true
                _atomicEngineExpectedToRun = true
                _atomicLastKnownEngineRunning = true
                engineStartRetryAttempt = 0  // Reset retry counter on success
                
                // Validate engine health after start (only if monitor is initialized)
                if let healthMonitor = healthMonitor {
                    let healthResult = healthMonitor.validateState()
                    if !healthResult.isValid {
                        AppLogger.shared.warning("Engine started but health check found issues", category: .audio)
                        for issue in healthResult.criticalIssues {
                            AppLogger.shared.error(issue.logMessage, category: .audio)
                            errorTracker.recordError(
                                severity: .error,
                                component: issue.component,
                                message: issue.description
                            )
                        }
                    }
                }
                
                AppLogger.shared.info("Audio engine started successfully", category: .audio)
            }
        } catch {
            let errorMsg = "Engine start failed (attempt \(engineStartRetryAttempt + 1)): \(error.localizedDescription)"
            AppLogger.shared.error(errorMsg, category: .audio)
            
            // Track the error with context
            errorTracker.recordError(
                severity: engineStartRetryAttempt >= 2 ? .critical : .error,
                component: "AudioEngine",
                message: "Failed to start engine",
                context: [
                    "attempt": String(engineStartRetryAttempt + 1),
                    "maxRetries": String(Self.maxEngineStartRetries),
                    "error": error.localizedDescription
                ]
            )
            
            // Implement exponential backoff retry
            scheduleEngineStartRetry()
        }
    }
    
    /// Schedules an engine start retry with exponential backoff
    private func scheduleEngineStartRetry() {
        guard engineStartRetryAttempt < Self.maxEngineStartRetries else {
            AppLogger.shared.error("Engine start failed after \(Self.maxEngineStartRetries) attempts - giving up", category: .audio)
            engineStartRetryAttempt = 0
            return
        }
        
        // Calculate delay with exponential backoff: base * 2^attempt
        // 0.1s, 0.2s, 0.4s, 0.8s, 1.6s
        let delay = Self.engineStartBaseDelay * pow(2.0, Double(engineStartRetryAttempt))
        engineStartRetryAttempt += 1
        
        AppLogger.shared.info("Scheduling engine restart in \(String(format: "%.1f", delay))s (attempt \(engineStartRetryAttempt)/\(Self.maxEngineStartRetries))", category: .audio)
        
        // Stop and reset before retry
        engine.stop()
        _atomicLastKnownEngineRunning = false
        engine.reset()
        engine.prepare()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            
            // Check if engine was started by another path while we waited
            guard !self.engine.isRunning else {
                self.engineStartRetryAttempt = 0
                return
            }
            
            do {
                try self.engine.start()
                if self.engine.isRunning {
                    self.isGraphReadyForPlayback = true
                    self.engineExpectedToRun = true
                    self._atomicEngineExpectedToRun = true
                    self._atomicLastKnownEngineRunning = true
                    self.engineStartRetryAttempt = 0
                    AppLogger.shared.info("Engine recovery successful on attempt \(self.engineStartRetryAttempt)", category: .audio)
                } else {
                    // Still not running - schedule another retry
                    self.scheduleEngineStartRetry()
                }
            } catch {
                AppLogger.shared.error("Engine recovery failed on attempt \(self.engineStartRetryAttempt): \(error.localizedDescription)", category: .audio)
                self.scheduleEngineStartRetry()
            }
        }
    }
    
    // MARK: - Engine Health Monitoring
    
    /// Setup periodic engine health checks using DispatchSourceTimer.
    /// Runs on low-priority queue (.utility); only dispatches to MainActor when cache indicates
    /// possible desync or when due for a staggered refresh. Backs off refresh rate during
    /// playback to avoid periodic CPU spikes (issue #80).
    private func setupEngineHealthMonitoring() {
        // Mirror state for timer (timer runs on healthMonitorQueue, cannot touch MainActor every tick)
        _atomicEngineExpectedToRun = engineExpectedToRun
        _atomicLastKnownEngineRunning = engine.isRunning
        _healthCheckTickCount = 0
        
        // Cancel existing timer
        engineHealthTimer?.cancel()
        engineHealthTimer = nil
        
        // Timer on utility queue; relaxed leeway to avoid aligning with buffer boundaries
        let timer = DispatchSource.makeTimerSource(queue: healthMonitorQueue)
        timer.schedule(
            deadline: .now() + 2.0,
            repeating: 2.0,
            leeway: .milliseconds(400)
        )
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Stay on healthMonitorQueue: avoid MainActor hop when cache says engine is healthy
            if !self._atomicEngineExpectedToRun {
                self._healthCheckTickCount = 0
                return
            }
            self._healthCheckTickCount += 1
            let isPlaying = self._transportControllerRef?.atomicIsPlaying ?? false
            let ticksUntilRefresh = isPlaying
                ? Self.healthCheckRefreshTicksWhenPlaying
                : Self.healthCheckRefreshTicksWhenStopped
            let dueForRefresh = self._healthCheckTickCount >= ticksUntilRefresh
            if dueForRefresh {
                self._healthCheckTickCount = 0
            }
            let needCheck = !self._atomicLastKnownEngineRunning || dueForRefresh
            if needCheck {
                Task { @MainActor in
                    self.checkEngineHealth()
                }
            }
        }
        timer.resume()
        engineHealthTimer = timer
    }
    
    /// Check engine health and attempt recovery if needed.
    /// Updates thread-safe cache so next health timer tick can avoid MainActor if still healthy (issue #80).
    private func checkEngineHealth() {
        // Only check if we expect the engine to be running
        guard engineExpectedToRun else {
            healthCheckFailureCount = 0
            _atomicLastKnownEngineRunning = false
            return
        }
        
        let running = engine.isRunning
        _atomicLastKnownEngineRunning = running
        
        if !running {
            healthCheckFailureCount += 1
            AppLogger.shared.warning("Engine health: Not running (failure #\(healthCheckFailureCount))", category: .audio)
            
            // Attempt recovery
            attemptEngineRecovery()
        } else {
            // Reset failure count on success
            if healthCheckFailureCount > 0 {
                AppLogger.shared.info("Engine health: Recovered successfully", category: .audio)
            }
            healthCheckFailureCount = 0
        }
    }
    
    /// Attempt to recover a stopped engine
    private func attemptEngineRecovery() {
        // Don't attempt recovery during graph mutations
        guard !graphManager.isGraphMutationInProgress else { return }
        
        // Limit recovery attempts to prevent infinite loops
        guard healthCheckFailureCount <= 3 else {
            AppLogger.shared.error("Engine health: Max recovery attempts reached, stopping monitoring", category: .audio)
            engineExpectedToRun = false
            _atomicEngineExpectedToRun = false
            return
        }
        
        AppLogger.shared.info("Engine health: Attempting recovery...", category: .audio)
        
        engine.prepare()
        
        do {
            try engine.start()
            if engine.isRunning {
                isGraphReadyForPlayback = true
                AppLogger.shared.info("Engine health: Recovery successful", category: .audio)
            }
        } catch {
            AppLogger.shared.error("Engine health: Recovery failed - \(error.localizedDescription)", category: .audio)
        }
    }
    
    /// Stop engine health monitoring
    private func stopEngineHealthMonitoring() {
        engineHealthTimer?.cancel()
        engineHealthTimer = nil
    }
    
    // MARK: - Position Update State
    // PERFORMANCE: Position updates trigger fine-grained @Observable updates
    // Position timer is now managed by TransportController
    @ObservationIgnored
    private var lastPublishedPositionTime: TimeInterval = -1
    
    // MARK: - Automation Application (Delegated to AudioEngine+Automation.swift)
    
    /// Apply automation values to track parameters - delegates to extension
    private func applyAutomation(at timeInSeconds: TimeInterval) {
        applyAutomationInternal(at: timeInSeconds)
    }
    
    /// Update automation processor with track's automation data - delegates to extension
    func updateTrackAutomation(_ track: AudioTrack) {
        updateTrackAutomationInternal(track)
    }
    
    /// Commit recorded automation points to a track - delegates to extension
    func commitRecordedAutomation(
        points: [AutomationPoint],
        parameter: AutomationParameter,
        trackId: UUID,
        projectUpdateHandler: @escaping (inout AudioProject) -> Void
    ) {
        commitRecordedAutomationInternal(
            points: points,
            parameter: parameter,
            trackId: trackId,
            projectUpdateHandler: projectUpdateHandler
        )
    }
    
    /// Update automation for all tracks - delegates to extension
    private func updateAllTrackAutomation() {
        updateAllTrackAutomationInternal()
    }
    
    // MARK: - Project Management
    
    // NOTE: Project loading state is now managed by ProjectLifecycleManager
    
    /// Lightweight project data update - does NOT rebuild audio graph
    /// Use this for region edits (resize, move, loop) that don't require graph changes
    /// DELEGATED to ProjectLifecycleManager
    func updateProjectData(_ project: AudioProject) {
        currentProject = project
        projectLifecycleManager.updateProjectData(project)
    }
    
    /// Synchronous entry point that kicks off async loading
    /// DELEGATED to ProjectLifecycleManager
    func loadProject(_ project: AudioProject) {
        currentProject = project
        projectLifecycleManager.currentProject = project
        projectLifecycleManager.loadProject(project)
    }
    
    // NOTE: loadProjectAsync is now handled by ProjectLifecycleManager
    
    /// Create instruments for MIDI tracks and connect them to plugin chains - delegates to extension
    @MainActor
    private func createAndConnectMIDIInstruments(for project: AudioProject) async {
        await createAndConnectMIDIInstrumentsInternal(for: project)
    }
    
    /// Incrementally update the audio graph when project changes.
    /// - Parameters:
    ///   - project: The new project state (typically already set in ProjectManager)
    ///   - previousProject: The old project state for comparison. Required because currentProject
    ///                      now reads from ProjectManager, so we need the caller to provide the old state.
    func updateCurrentProject(_ project: AudioProject, previousProject: AudioProject? = nil) {
        logDebug("updateCurrentProject called for '\(project.name)'", category: "PROJECT-UPDATE")
        
        // Project is already set via ProjectManager (single source of truth)
        // Only set if explicitly provided to ensure sync
        if currentProject?.id != project.id {
            currentProject = project
        }
        
        // Use provided previous project for comparison
        let oldProject = previousProject
        
        // Check for new tracks that need audio node setup
        if let oldProject = oldProject {
            let oldTrackIds = Set(oldProject.tracks.map { $0.id })
            let newTrackIds = Set(project.tracks.map { $0.id })
            let addedTrackIds = newTrackIds.subtracting(oldTrackIds)
            
            if !addedTrackIds.isEmpty {
                logDebug("New tracks detected: \(addedTrackIds.count)", category: "PROJECT-UPDATE")
                
                // BATCH MODE: Wrap multiple track additions in batch to avoid rate limiting
                // This handles MIDI import creating many tracks at once
                performBatchGraphOperation {
                    // Set up audio nodes for new tracks
                    for trackId in addedTrackIds {
                        if let newTrack = project.tracks.first(where: { $0.id == trackId }) {
                            let trackNode = createTrackNode(for: newTrack)
                            trackNodeManager.storeTrackNode(trackNode, for: trackId)
                            
                            // Use centralized rebuild for all connections
                            rebuildTrackGraph(trackId: trackId)
                        }
                    }
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
                            loadAudioRegion(newRegion, trackNode: trackNode)
                        }
                    }
                    
                    // Handle removed regions (clear audio files that are no longer needed)
                    let removedRegionIds = oldRegionIds.subtracting(newRegionIds)
                    if !removedRegionIds.isEmpty {
                        // Note: TrackAudioNode handles multiple regions, so we don't need to explicitly remove
                        // The next playback will only schedule the remaining regions
                    }
                    
                    // CRITICAL FIX: Check for moved regions (same ID but different position)
                    var hasRegionPositionChanges = false
                    for newRegion in track.regions {
                        if let oldRegion = oldTrack.regions.first(where: { $0.id == newRegion.id }) {
                            if abs(oldRegion.startBeat - newRegion.startBeat) > 0.001 { // Beat tolerance
                                hasRegionPositionChanges = true
                            }
                        }
                    }
                    
                    // If regions were moved, handle re-scheduling based on transport state
                    if hasRegionPositionChanges {
                        if transportState == .playing {
                            // Currently playing: Re-schedule immediately
                            trackNode.playerNode.stop()
                            
                            // BEATS-FIRST: Use scheduleFromBeat, conversion happens at TrackAudioNode boundary
                            let tempo = currentProject?.tempo ?? 120.0
                            do {
                                try trackNode.scheduleFromBeat(currentPosition.beats, audioRegions: track.regions, tempo: tempo)
                                if !trackNode.playerNode.isPlaying {
                                    trackNode.playerNode.play()
                                }
                            } catch {
                            }
                        } else {
                            // Currently stopped: Clear audio cache so next playback uses updated positions
                            trackNode.playerNode.stop()
                        }
                    }
                }
            }
            
            // Clean up removed tracks
            let removedTrackIds = oldTrackIds.subtracting(newTrackIds)
            for trackId in removedTrackIds {
                // [BUGFIX] Safe node disconnection with existence checks
                trackNodeManager.removeTrackNode(for: trackId)
            }
            
            // Update solo state in case new tracks affect it
            updateSoloState()
            
            // Update automation data for all tracks
            updateAllTrackAutomation()
        }
        
    }
    
    // MARK: - Track Management (Delegated to TrackNodeManager)
    
    private func setupTracksForProject(_ project: AudioProject) {
        // Ensure installedMetronome is set on trackNodeManager before setup
        trackNodeManager.installedMetronome = installedMetronome
        trackNodeManager.setupTracksForProject(project)
    }
    
    // [V2-ANALYSIS] Public access to track nodes for pitch/tempo adjustments
    func getTrackNode(for trackId: UUID) -> TrackAudioNode? {
        return trackNodeManager.getTrackNode(for: trackId)
    }
    
    /// Ensures a track node exists for the given track, creating it if needed
    /// This is useful when loading instruments immediately after track creation
    func ensureTrackNodeExists(for track: AudioTrack) {
        trackNodeManager.ensureTrackNodeExists(for: track)
    }
    
    /// Creates a track node and attaches all nodes to the engine.
    /// NOTE: This only attaches nodes - caller must call rebuildTrackGraph() after storing in trackNodes
    /// DELEGATED to TrackNodeManager
    private func createTrackNode(for track: AudioTrack) -> TrackAudioNode {
        return trackNodeManager.createTrackNode(for: track)
    }
    
    private func clearAllTracks() {
        trackNodeManager.clearAllTracks()
    }
    
    // MARK: - Bus Management (Delegated to BusManager)
    func setupBusesForProject(_ project: AudioProject) {
        busManager.setupBusesForProject(project)
    }
    
    func addBus(_ bus: MixerBus) {
        busManager.addBus(bus)
    }
    
    func removeBus(withId busId: UUID) {
        busManager.removeBus(withId: busId)
    }
    
    
    
    // MARK: - Bus Plugin Chain Management (Delegated to BusManager)
    
    /// Get the plugin chain for a bus
    func getBusPluginChain(for busId: UUID) -> PluginChain? {
        busManager.getBusPluginChain(for: busId)
    }
    
    /// Insert an AU plugin into a bus's insert chain
    func insertBusPlugin(busId: UUID, descriptor: PluginDescriptor, atSlot slot: Int, sandboxed: Bool = false) async throws {
        try await busManager.insertBusPlugin(busId: busId, descriptor: descriptor, atSlot: slot, sandboxed: sandboxed)
    }
    
    /// Remove a plugin from a bus's insert chain
    func removeBusPlugin(busId: UUID, atSlot slot: Int) {
        busManager.removeBusPlugin(busId: busId, atSlot: slot)
    }
    
    /// Open the plugin editor UI for a bus slot
    func openBusPluginEditor(busId: UUID, slot: Int) {
        busManager.openBusPluginEditor(busId: busId, slot: slot, audioEngine: self)
    }
    
    // MARK: - Track Send Management (Delegated to BusManager)
    // trackSendIds and trackSendInputBus are now managed by BusManager
    
    // MARK: [BUGFIX] Safe Node Disconnection (Issue #81)
    /// Disconnects and detaches track nodes in downstream-first order to avoid EXC_BAD_ACCESS
    /// and graph corruption. Order: stop player → uninstall plugin chain → disconnect outputs
    /// (pan → volume → eq) → disconnect/detach instrument source → disconnect/detach player.
    /// Caller must have removed track from all bus sends first (so pan isn't connected to buses).
    private func safeDisconnectTrackNode(_ trackNode: TrackAudioNode) {
        modifyGraphSafely {
            let trackId = trackNode.id

            // Stop player before any disconnection
            if trackNode.playerNode.isPlaying {
                trackNode.playerNode.stop()
            }

            // 1. Uninstall plugin chain first (unloads plugins, disconnects and detaches chain mixers)
            trackNode.pluginChain.uninstall()

            // 2. Disconnect in downstream-first order (same as rebuildTrackGraphInternal).
            //    Each node: disconnect output, then input, then detach.
            self.engine.disconnectNodeOutput(trackNode.panNode)
            self.engine.disconnectNodeInput(trackNode.panNode)
            if self.engine.attachedNodes.contains(trackNode.panNode) {
                self.engine.detach(trackNode.panNode)
            }

            self.engine.disconnectNodeOutput(trackNode.volumeNode)
            self.engine.disconnectNodeInput(trackNode.volumeNode)
            if self.engine.attachedNodes.contains(trackNode.volumeNode) {
                self.engine.detach(trackNode.volumeNode)
            }

            self.engine.disconnectNodeOutput(trackNode.eqNode)
            self.engine.disconnectNodeInput(trackNode.eqNode)
            if self.engine.attachedNodes.contains(trackNode.eqNode) {
                self.engine.detach(trackNode.eqNode)
            }

            // 3. Disconnect and detach instrument source (sampler or timePitch)
            if let instrument = InstrumentManager.shared.getInstrument(for: trackId),
               let sampler = instrument.samplerEngine?.sampler {
                if self.engine.attachedNodes.contains(sampler) {
                    self.engine.disconnectNodeOutput(sampler)
                    self.engine.disconnectNodeInput(sampler)
                    self.engine.detach(sampler)
                }
            } else if let instrument = InstrumentManager.shared.getInstrument(for: trackId),
                      let auNode = instrument.audioUnitNode,
                      self.engine.attachedNodes.contains(auNode) {
                self.engine.disconnectNodeOutput(auNode)
                self.engine.disconnectNodeInput(auNode)
                self.engine.detach(auNode)
            } else if let instrument = InstrumentManager.shared.getInstrument(for: trackId),
                      let drumKit = instrument.drumKitEngine {
                drumKit.detach()
            }

            self.engine.disconnectNodeOutput(trackNode.timePitchUnit)
            self.engine.disconnectNodeInput(trackNode.timePitchUnit)
            if self.engine.attachedNodes.contains(trackNode.timePitchUnit) {
                self.engine.detach(trackNode.timePitchUnit)
            }

            self.engine.disconnectNodeOutput(trackNode.playerNode)
            self.engine.disconnectNodeInput(trackNode.playerNode)
            if self.engine.attachedNodes.contains(trackNode.playerNode) {
                self.engine.detach(trackNode.playerNode)
            }
        }
    }

    // MARK: - Tiered Graph Mutation (Delegated to AudioGraphManager)
    
    /// Performs a structural graph mutation
    /// DELEGATED to AudioGraphManager
    func modifyGraphSafely(_ work: @escaping () throws -> Void) rethrows {
        try graphManager.modifyGraphSafely(work)
    }
    
    /// Performs a connection-only graph mutation
    /// DELEGATED to AudioGraphManager
    func modifyGraphConnections(_ work: @escaping () throws -> Void) rethrows {
        try graphManager.modifyGraphConnections(work)
    }
    
    /// Performs a track-scoped hot-swap mutation
    /// DELEGATED to AudioGraphManager
    func modifyGraphForTrack(_ trackId: UUID, _ work: @escaping () throws -> Void) rethrows {
        try graphManager.modifyGraphForTrack(trackId, work)
    }
    
    /// Performs multiple graph mutations in batch mode (suspends rate limiting).
    /// Use for bulk operations like project load, multi-track import, etc.
    func performBatchGraphOperation(_ work: () throws -> Void) rethrows {
        try graphManager.performBatchOperation(work)
    }
    
    // NOTE: Core graph mutation implementation is now handled by AudioGraphManager
    
    // MARK: - Centralized Graph Rebuild (Single Source of Truth)
    
    /// Rebuilds the full track graph with correct disconnect-downstream-first order.
    /// This is the ONLY function that should connect/disconnect track nodes.
    /// Called when: changing source type, initial track creation, project load, adding instrument
    ///
    /// ARCHITECTURE NOTE (Lazy Plugin Chains):
    /// When a track has no plugins, the plugin chain is not realized (no mixer nodes).
    /// Audio flows directly: source → eqNode (bypassing inputMixer/outputMixer).
    /// This saves 2 nodes per track for typical projects with few plugins.
    ///
    /// PERFORMANCE: Uses hot-swap mutation to only affect the target track.
    /// Other tracks continue playing without interruption.
    // MARK: - Graph Building (Delegated to AudioEngine+GraphBuilding.swift)
    
    /// Rebuilds the full track graph - delegates to extension
    private func rebuildTrackGraph(trackId: UUID) {
        rebuildTrackGraphInternal(trackId: trackId)
    }
    
    /// Validates track connections - delegates to extension
    private func validateTrackConnections(trackId: UUID) {
        validateTrackConnectionsInternal(trackId: trackId)
    }
    
    /// Validates all track connections - delegates to extension
    private func validateAllTrackConnections() {
        validateAllTrackConnectionsInternal()
    }
    
    /// Audits track formats for debugging - delegates to extension
    private func auditTrackFormats(trackId: UUID, trackNode: TrackAudioNode) {
        auditTrackFormatsInternal(trackId: trackId, trackNode: trackNode)
    }
    
    /// Rebuilds plugin chain interior - delegates to extension
    private func rebuildPluginChain(trackId: UUID) {
        rebuildPluginChainInternal(trackId: trackId)
    }
    
    /// Schedules a debounced track graph rebuild - delegates to extension
    func scheduleRebuild(trackId: UUID) {
        scheduleRebuildInternal(trackId: trackId)
    }
    
    /// Gets the source node for a track - delegates to extension
    private func getSourceNode(for trackId: UUID, trackNode: TrackAudioNode) -> AVAudioNode? {
        return getSourceNodeInternal(for: trackId, trackNode: trackNode)
    }
    
    /// Connects panNode to main mixer - delegates to extension
    private func connectPanToDestinations(trackId: UUID, trackNode: TrackAudioNode, format: AVAudioFormat) {
        connectPanToDestinationsInternal(trackId: trackId, trackNode: trackNode, format: format)
    }
    
    func setupTrackSend(_ trackId: UUID, to busId: UUID, level: Double) {
        busManager.setupTrackSend(trackId, to: busId, level: level)
    }
    
    func updateTrackSendLevel(_ trackId: UUID, busId: UUID, level: Double) {
        busManager.updateTrackSendLevel(trackId, busId: busId, level: level)
    }
    
    func removeTrackSend(_ trackId: UUID, from busId: UUID) {
        busManager.removeTrackSend(trackId, from: busId)
    }
    
    // MARK: - Transport Controls (Delegated to TransportController)
    
    func play() {
        // Quick health validation
        if let healthMonitor = healthMonitor {
            let quickCheck = healthMonitor.quickValidate()
            
            if !quickCheck {
                let result = healthMonitor.validateState()
                
                if !result.isValid {
                    errorTracker.recordError(
                        severity: .critical,
                        component: "AudioEngine",
                        message: "Cannot play: Engine health check failed",
                        context: ["criticalIssues": String(result.criticalIssues.count)]
                    )
                    
                    // Attempt recovery for critical issues
                    if healthMonitor.currentHealth.requiresRecovery {
                        attemptEngineRecovery()
                    }
                    return
                }
            }
        }
        
        transportController.play()
    }
    
    func pause() {
        transportController.pause()
    }
    
    func stop() {
        transportController.stop()
    }
    
    // MARK: - Transport Callbacks (called by TransportController)
    
    /// Called by TransportController when playback should start
    private func performStartPlayback(fromBeat startBeat: Double) {
        logDebug("performStartPlayback from beat \(startBeat)", category: "TRANSPORT")
        startPlayback()
    }
    
    /// Called by TransportController when playback should stop
    private func performStopPlayback() {
        logDebug("performStopPlayback", category: "TRANSPORT")
        stopPlayback()
    }
    
    /// Called by TransportController when transport state changes
    private func handleTransportStateChanged(_ state: TransportState) {
        logDebug("Transport state changed to \(state)", category: "TRANSPORT")
        
        // Start/stop automation engine based on transport state
        if state.isPlaying {
            // BUG FIX (Issue #48): Reset smoothing values for all tracks before starting
            // Initialize from automation curves at current playhead position
            let currentBeat = transportController?.positionBeats ?? 0
            
            for (_, trackNode) in trackNodes {
                // Find the track's automation lanes
                if let track = currentProject?.tracks.first(where: { $0.id == trackNode.id }) {
                    trackNode.resetSmoothing(atBeat: currentBeat, automationLanes: track.automationLanes)
                } else {
                    // Fallback: reset without automation data
                    trackNode.resetSmoothing(atBeat: currentBeat, automationLanes: [])
                }
            }
            automationEngine.start()
        } else {
            automationEngine.stop()
        }
        
        // Recording state updates
        if state == .recording {
            isRecording = true
        } else if state == .stopped {
            isRecording = false
        }
    }
    
    /// Called by TransportController when position changes (for UI updates only)
    /// Automation is now handled by the dedicated AutomationEngine on a high-priority queue
    private func handlePositionChanged(_ position: PlaybackPosition) {
        // UI position updates are handled automatically by @Observable
        // Automation is processed by automationEngine on its own queue
        // No action needed here - keeping method for future extensions
    }
    
    /// Called by TransportController during a cycle jump
    /// Handle cycle loop jump
    /// DELEGATED to PlaybackSchedulingCoordinator
    private func handleCycleJump(toBeat targetBeat: Double) {
        playbackScheduler.handleCycleJump(toBeat: targetBeat)
    }
    
    // MARK: - Recording (Delegated to RecordingController)
    
    func prepareRecordingDuringCountIn() async {
        await recordingController.prepareRecordingDuringCountIn()
    }
    
    func startRecordingAfterCountIn() {
        recordingController.startRecordingAfterCountIn()
    }
    
    func record() {
        recordingController.record()
    }
    
    func stopRecording() {
        recordingController.stopRecording()
    }
    
    // MARK: - Playback Implementation (Delegated to AudioEngine+Playback.swift)
    
    private func startPlayback() {
        startPlaybackInternal()
    }
    
    private func stopPlayback() {
        stopPlaybackInternal()
    }
    
    // DEADCODE REMOVAL (Phase 3 beats-first cleanup):
    // Removed: playTrack, scheduleRegion, scheduleRegionForSynchronizedPlayback
    // These were never called and used seconds-based APIs.
    // All scheduling now goes through TrackAudioNode.scheduleFromBeat() which
    // handles beat→seconds conversion at the AVAudioEngine boundary.
    
    // Recording implementation is now in RecordingController
    
    // MARK: - Position Control (Delegated to TransportController)
    /// Seek to a beat position (primary method)
    func seek(toBeat beat: Double) {
        seekToBeat(beat)
    }
    
    /// Seek using seconds - for external seconds-based inputs only
    func seek(toSeconds seconds: TimeInterval) {
        seekToSeconds(seconds)
    }
    
    // MARK: - Mixer Controls (Delegated to MixerController)
    func setTrackVolume(_ trackId: UUID, volume: Float) {
        mixerController.updateTrackVolume(trackId: trackId, volume: volume)
    }
    
    func setTrackPan(_ trackId: UUID, pan: Float) {
        mixerController.updateTrackPan(trackId: trackId, pan: pan)
    }
    
    func muteTrack(_ trackId: UUID, muted: Bool) {
        mixerController.updateTrackMute(trackId: trackId, isMuted: muted)
    }
    
    func soloTrack(_ trackId: UUID, solo: Bool) {
        mixerController.updateTrackSolo(trackId: trackId, isSolo: solo)
    }
    
    private func updateAllTrackStates() {
        mixerController.updateAllTrackStates()
    }
    
    private func updateSoloState() {
        mixerController.updateAllTrackStates()
    }
    
    // MARK: - Audio File Import (Delegated to AudioEngine+Playback.swift)

    /// Maximum audio file size for import (500 MB) to prevent memory exhaustion.
    static let maxAudioImportFileSize: Int64 = 500_000_000

    func importAudioFile(from url: URL) async throws -> AudioFile {
        return try await importAudioFileInternal(from: url)
    }
    
    // MARK: - Audio Region Loading (Delegated to AudioEngine+Playback.swift)
    private func loadAudioRegion(_ region: AudioRegion, trackNode: TrackAudioNode) {
        loadAudioRegionInternal(region, trackNode: trackNode)
    }
    
    // MARK: - Mixer Controls (Delegated to MixerController)
    func updateTrackVolume(trackId: UUID, volume: Float) {
        mixerController.updateTrackVolume(trackId: trackId, volume: volume)
    }
    
    func updateTrackPan(trackId: UUID, pan: Float) {
        mixerController.updateTrackPan(trackId: trackId, pan: pan)
    }
    
    func updateTrackMute(trackId: UUID, isMuted: Bool) {
        mixerController.updateTrackMute(trackId: trackId, isMuted: isMuted)
    }
    
    func updateTrackSolo(trackId: UUID, isSolo: Bool) {
        mixerController.updateTrackSolo(trackId: trackId, isSolo: isSolo)
    }

    func updateTrackIcon(trackId: UUID, iconName: String) {
        mixerController.updateTrackIcon(trackId: trackId, iconName: iconName)
    }
    
    func updateTrackEQ(trackId: UUID, highEQ: Float, midEQ: Float, lowEQ: Float) {
        mixerController.updateTrackEQ(trackId: trackId, highEQ: highEQ, midEQ: midEQ, lowEQ: lowEQ)
    }
    
    func updateTrackRecordEnabled(trackId: UUID, isRecordEnabled: Bool) {
        mixerController.updateTrackRecordEnabled(trackId: trackId, isRecordEnabled: isRecordEnabled)
    }
    
    // MARK: - Individual EQ Band Updates (Delegated to MixerController)
    
    func updateTrackHighEQ(trackId: UUID, value: Float) {
        mixerController.updateTrackHighEQ(trackId: trackId, value: value)
    }
    
    func updateTrackMidEQ(trackId: UUID, value: Float) {
        mixerController.updateTrackMidEQ(trackId: trackId, value: value)
    }
    
    func updateTrackLowEQ(trackId: UUID, value: Float) {
        mixerController.updateTrackLowEQ(trackId: trackId, value: value)
    }
    
    func updateTrackEQEnabled(trackId: UUID, enabled: Bool) {
        mixerController.updateTrackEQEnabled(trackId: trackId, enabled: enabled)
    }
    
    // MARK: - Track Insert Effects (Delegated to MixerController)
    
    // MARK: - Track Instrument Management (MIDI/Instrument tracks)
    // ARCHITECTURE NOTE: Instruments are now owned exclusively by InstrumentManager.shared
    // AudioEngine no longer maintains its own trackInstruments dictionary.
    // This eliminates dual-ownership confusion and ensures single source of truth.
    
    /// Get the instrument for a track - delegates to extension
    func getTrackInstrument(for trackId: UUID) -> TrackInstrument? {
        return getTrackInstrumentInternal(for: trackId)
    }
    
    /// Load an AU instrument for a MIDI/Instrument track - delegates to extension
    func loadTrackInstrument(trackId: UUID, descriptor: PluginDescriptor) async throws {
        try await loadTrackInstrumentInternal(trackId: trackId, descriptor: descriptor)
    }
    
    /// Remove/unload the instrument from a track - delegates to extension
    func unloadTrackInstrument(trackId: UUID) {
        unloadTrackInstrumentInternal(trackId: trackId)
    }
    
    /// Send MIDI note to a track's instrument - delegates to extension
    func sendMIDINoteToTrack(trackId: UUID, noteOn: Bool, pitch: UInt8, velocity: UInt8) {
        sendMIDINoteToTrackInternal(trackId: trackId, noteOn: noteOn, pitch: pitch, velocity: velocity)
    }
    
    // MARK: - Step Sequencer MIDI Routing (Delegated to AudioEngine+Instruments.swift)
    
    /// Configure MIDI event callbacks for the step sequencer - delegates to extension
    private func configureSequencerMIDICallbacks(_ sequencer: SequencerEngine) {
        configureSequencerMIDICallbacksInternal(sequencer)
    }
    
    /// Handle a single MIDI event from the step sequencer - delegates to extension
    private func handleSequencerMIDIEvent(_ event: SequencerMIDIEvent) {
        handleSequencerMIDIEventInternal(event)
    }
    
    /// Handle batch MIDI events from the step sequencer - delegates to extension
    private func handleSequencerMIDIEvents(_ events: [SequencerMIDIEvent]) {
        handleSequencerMIDIEventsInternal(events)
    }
    
    /// Send a sequencer MIDI event to a track's instrument - delegates to extension
    private func sendSequencerEventToTrack(_ event: SequencerMIDIEvent, trackId: UUID) {
        sendSequencerEventToTrackInternal(event, trackId: trackId)
    }
    
    /// Get list of MIDI tracks available for sequencer routing - delegates to extension
    func getMIDITracksForSequencerRouting() -> [(id: UUID, name: String)] {
        return getMIDITracksForSequencerRoutingInternal()
    }
    
    /// Check if a track has an instrument loaded - delegates to extension
    func trackHasInstrument(_ trackId: UUID) -> Bool {
        return trackHasInstrumentInternal(trackId)
    }
    
    /// Load a GM SoundFont instrument for a MIDI/Instrument track - delegates to extension
    func loadTrackGMInstrument(trackId: UUID, instrument gmInstrument: GMInstrument) async throws {
        try await loadTrackGMInstrumentInternal(trackId: trackId, instrument: gmInstrument)
    }
    
    /// Reconnects a MIDI track's instrument to its proper destination - delegates to extension
    private func reconnectMIDIInstrumentToPluginChain(trackId: UUID) {
        reconnectMIDIInstrumentToPluginChainInternal(trackId: trackId)
    }
    
    // MARK: - Instrument Creation (Delegated to AudioEngine+Instruments.swift)
    
    /// Create a sampler instrument attached to the DAW's audio engine - delegates to extension
    func createSamplerForTrack(_ trackId: UUID, connectToPluginChain: Bool = true) -> SamplerEngine {
        return createSamplerForTrackInternal(trackId, connectToPluginChain: connectToPluginChain)
    }
    
    /// Expose the audio engine for InstrumentManager to create properly-attached samplers
    /// This ensures all audio nodes belong to the same AVAudioEngine
    var audioEngineRef: AVAudioEngine {
        return engine
    }
    
    // MARK: - Track Plugin Chain Management (Delegated to TrackPluginManager)
    
    /// Get the plugin chain for a track
    func getPluginChain(for trackId: UUID) -> PluginChain? {
        trackPluginManager.getPluginChain(for: trackId)
    }
    
    // MARK: - Plugin Delay Compensation (Delegated to TrackPluginManager)
    
    func updateDelayCompensation() {
        trackPluginManager.updateDelayCompensation()
    }
    
    func insertPlugin(trackId: UUID, descriptor: PluginDescriptor, atSlot slot: Int, sandboxed: Bool = false) async throws {
        try await trackPluginManager.insertPlugin(trackId: trackId, descriptor: descriptor, atSlot: slot, sandboxed: sandboxed)
    }
    
    func removePlugin(trackId: UUID, atSlot slot: Int) {
        trackPluginManager.removePlugin(trackId: trackId, atSlot: slot)
    }
    
    func movePlugin(trackId: UUID, fromSlot: Int, toSlot: Int) {
        trackPluginManager.movePlugin(trackId: trackId, fromSlot: fromSlot, toSlot: toSlot)
    }
    
    func setPluginBypass(trackId: UUID, slot: Int, bypassed: Bool) {
        trackPluginManager.setPluginBypass(trackId: trackId, slot: slot, bypassed: bypassed)
    }
    
    func setPluginChainBypass(trackId: UUID, bypassed: Bool) {
        trackPluginManager.setPluginChainBypass(trackId: trackId, bypassed: bypassed)
    }
    
    func getPluginChainLatency(trackId: UUID) -> Int {
        trackPluginManager.getPluginChainLatency(trackId: trackId)
    }
    
    // MARK: - Plugin Persistence (Delegated to TrackPluginManager)
    
    private func savePluginConfigsToProject(trackId: UUID, triggerSave: Bool = true) async {
        await trackPluginManager.savePluginConfigsToProject(trackId: trackId, triggerSave: triggerSave)
    }
    
    @discardableResult
    func restorePluginsFromProject() async -> PluginLoadResult {
        await trackPluginManager.restorePluginsFromProject()
    }
    
    // MARK: - Bus Node Access (Delegated to BusManager)
    
    func getBusNode(for busId: UUID) -> BusAudioNode? {
        busManager.getBusNode(for: busId)
    }
    
    func getAllBusNodes() -> [UUID: BusAudioNode] {
        busManager.getAllBusNodes()
    }
    
    func getTrackSends(for trackId: UUID) -> [(busId: UUID, level: Float)] {
        busManager.getTrackSends(for: trackId)
    }
    
    // MARK: - Plugin Editor (Delegated to TrackPluginManager)
    
    func openPluginEditor(trackId: UUID, slot: Int) {
        trackPluginManager.openPluginEditor(trackId: trackId, slot: slot, audioEngine: self)
    }
    
    // MARK: - Sidechain Routing (Delegated to TrackPluginManager)
    
    func pluginSupportsSidechain(trackId: UUID, slot: Int) -> Bool {
        trackPluginManager.pluginSupportsSidechain(trackId: trackId, slot: slot)
    }
    
    func setSidechainSource(trackId: UUID, slot: Int, source: SidechainSource) {
        trackPluginManager.setSidechainSource(trackId: trackId, slot: slot, source: source)
    }
    
    func getSidechainSource(trackId: UUID, slot: Int) -> SidechainSource {
        trackPluginManager.getSidechainSource(trackId: trackId, slot: slot)
    }
    
    // MARK: - Master Volume Control (Delegated to MixerController)
    func updateMasterVolume(_ volume: Float) {
        mixerController.updateMasterVolume(volume)
    }
    
    func getMasterVolume() -> Float {
        mixerController.getMasterVolume()
    }
    
    // MARK: - Master EQ Control (Delegated to MixerController)
    func updateMasterEQ(hi: Float, mid: Float, lo: Float) {
        mixerController.updateMasterEQ(hi: hi, mid: mid, lo: lo)
    }
    
    func updateMasterHiEQ(_ value: Float) {
        mixerController.updateMasterHiEQ(value)
    }
    
    func updateMasterMidEQ(_ value: Float) {
        mixerController.updateMasterMidEQ(value)
    }
    
    func updateMasterLoEQ(_ value: Float) {
        mixerController.updateMasterLoEQ(value)
    }
    
    // MARK: - Bus Output Level Control (Delegated to BusManager)
    func updateBusOutputLevel(_ busId: UUID, outputLevel: Double) {
        // Update the bus node's output gain via BusManager
        busManager.updateBusOutputLevel(busId, outputLevel: outputLevel)
        
        // Update the project model
        guard var project = currentProject,
              let busIndex = project.buses.firstIndex(where: { $0.id == busId }) else {
            return
        }
        
        project.buses[busIndex].outputLevel = outputLevel
        project.modifiedAt = Date()
        currentProject = project
        
        // Notify that project has been updated so SwiftUI views refresh
        NotificationCenter.default.post(name: .projectUpdated, object: project)
    }
    
    func removeTrack(trackId: UUID) {
        guard var project = currentProject else { return }
        
        // 1. Remove track from all bus sends first (while track and trackNode still exist).
        //    This disconnects pan/volume from bus mixers so teardown doesn't leave dangling refs.
        busManager.removeAllSendsForTrack(trackId)
        
        // 2. Remove from project
        project.tracks.removeAll { $0.id == trackId }
        currentProject = project
        
        // 3. Remove track node (disconnects and detaches in downstream-first order)
        trackNodeManager.removeTrackNode(for: trackId)
        
        // 4. Clean up instrument so it stops and is removed from InstrumentManager
        InstrumentManager.shared.removeInstrument(for: trackId)
        
        // 5. Update mixer controller's solo tracking
        mixerController.removeTrackFromMixer(trackId: trackId)
    }
    
    // MARK: - Level Monitoring (Delegated to MeteringService)
    func getTrackLevels() -> [UUID: (current: Float, peak: Float)] {
        meteringService.getTrackLevels()
    }
    
    func getMasterLevel() -> (current: Float, peak: Float) {
        meteringService.getMasterLevel()
    }
    
    // MARK: - Timeline Navigation
    
    /// Seek to a specific beat position (primary method)
    func seekToBeat(_ beat: Double) {
        // Validate input
        guard beat.isFinite else {
            errorTracker.recordError(
                severity: .warning,
                component: "Transport",
                message: "Invalid seek position (non-finite): \(beat)"
            )
            return
        }
        
        let targetBeat = max(0, beat)
        
        // Warn if seeking very far (might indicate bug)
        if targetBeat > 100000 {
            errorTracker.recordError(
                severity: .warning,
                component: "Transport",
                message: "Seeking to very high beat position: \(targetBeat)"
            )
        }
        
        transportController.seekToBeat(targetBeat)
        
        // Also update MIDI playback position (in beats)
        midiPlaybackEngine.seek(toBeat: targetBeat)
    }
    
    /// Seek using seconds - for external seconds-based inputs only
    func seekToSeconds(_ seconds: TimeInterval) {
        guard let tempo = currentProject?.tempo else { return }
        let beats = seconds * (tempo / 60.0)
        seekToBeat(beats)
    }
    
    /// Pre-roll time in seconds to let plugins prime their internal state
    /// Professional DAWs typically use 20-100ms for this
    private let prerollSeconds: TimeInterval = 0.05  // 50ms
    
    private func playFromBeat(_ startBeat: Double) {
        guard let project = currentProject else { return }
        
        // Set transport state (but preserve .recording if we're currently recording)
        if transportState != .recording {
            transportState = .playing
        }
        
        // Update PDC compensation before scheduling (keeps tracks phase-aligned)
        updateDelayCompensation()
        
        // BEATS-FIRST: Convert pre-roll to beats for internal calculation
        let tempo = project.tempo
        let prerollBeats = prerollSeconds * (tempo / 60.0)
        
        // Calculate pre-roll start beat (but don't go negative)
        // Pre-roll allows plugins with internal state (reverbs, delays, compressors)
        // to stabilize before we reach the actual playhead position
        let prerollStartBeat = max(0, startBeat - prerollBeats)
        let hasPreroll = startBeat > prerollBeats
        
        // Schedule and start all tracks from the specified position
        var tracksToStart: [(TrackAudioNode, AudioTrack)] = []
        
        for track in project.tracks {
            guard let trackNode = trackNodes[track.id] else { continue }
            
            // Only play tracks that have audio regions at or after the start beat
            let relevantRegions = track.regions.filter { region in
                region.endBeat > startBeat
            }
            
            if !relevantRegions.isEmpty {
                do {
                    // BEATS-FIRST: Schedule using beats, conversion to seconds at TrackAudioNode boundary
                    let scheduleBeat = hasPreroll ? prerollStartBeat : startBeat
                    try trackNode.scheduleFromBeat(scheduleBeat, audioRegions: track.regions, tempo: tempo)
                    tracksToStart.append((trackNode, track))
                } catch {
                }
            }
        }
        
        // If using pre-roll, temporarily mute during the pre-roll phase
        if hasPreroll && !tracksToStart.isEmpty {
            // Save original volumes and mute during pre-roll
            let originalVolume = mixer.outputVolume
            mixer.outputVolume = 0
            
            // Start all tracks simultaneously
            for (trackNode, _) in tracksToStart {
                trackNode.play()
            }
            
            // Fade in after pre-roll completes
            DispatchQueue.main.asyncAfter(deadline: .now() + prerollSeconds) { [weak self] in
                guard let self = self, self.transportState == .playing || self.transportState == .recording else { return }
                
                // Quick fade-in over 5ms to avoid clicks
                let fadeSteps = 5
                let fadeInterval = 0.001  // 1ms
                for step in 0..<fadeSteps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + fadeInterval * Double(step)) { [weak self] in
                        let volume = originalVolume * Float(step + 1) / Float(fadeSteps)
                        self?.mixer.outputVolume = volume
                    }
                }
            }
        } else {
            // No pre-roll, start immediately
            for (trackNode, _) in tracksToStart {
                trackNode.play()
            }
        }
    }
    
    /// Nudge playhead backward by a number of beats
    func rewindBeats(_ beats: Double = 1.0) {
        let newBeat = max(0, currentPosition.beats - beats)
        seekToBeat(newBeat)
    }
    
    /// Nudge playhead forward by a number of beats
    func fastForwardBeats(_ beats: Double = 1.0) {
        let newBeat = currentPosition.beats + beats
        seekToBeat(newBeat)
    }
    
    func skipToBeginning() {
        seekToBeat(0)
    }
    
    func skipToEnd() {
        // Skip to end of longest track or 10 beats forward if no tracks
        guard let project = currentProject else {
            seekToBeat(currentPosition.beats + 10)
            return
        }
        
        // Find the maximum end beat across all regions
        let maxEndBeat = project.tracks.compactMap { track in
            track.regions.map { region in
                region.endBeat
            }.max()
        }.max() ?? currentPosition.beats + 10
        
        seekToBeat(maxEndBeat)
    }
    
    // MARK: - Cycle Controls (Delegated to TransportController)
    
    func toggleCycle() {
        transportController.toggleCycle()
    }
    
    /// Set cycle region in BEATS (consistent with MIDI timing throughout the app)
    func setCycleRegion(startBeat: Double, endBeat: Double) {
        // Validate inputs
        guard startBeat >= 0 else {
            errorTracker.recordError(
                severity: .warning,
                component: "Transport",
                message: "Invalid cycle start beat (negative): \(startBeat)"
            )
            return
        }
        
        guard endBeat > startBeat else {
            errorTracker.recordError(
                severity: .warning,
                component: "Transport",
                message: "Invalid cycle region: end (\(endBeat)) must be > start (\(startBeat))"
            )
            return
        }
        
        transportController.setCycleRegion(startBeat: startBeat, endBeat: endBeat)
    }
}

// MARK: - Audio Engine Extensions
extension AudioEngine {
    
    var isPlaying: Bool {
        transportState.isPlaying
    }
    
    // MARK: - Render Path Validation
    
    /// Check if a node has a valid render path to the main mixer using BFS.
    /// This is the TRUE test for whether a player node can be played.
    /// Simple outputConnectionPoints checks can pass even when the node is not in the render graph.
    func hasPathToMainMixer(from start: AVAudioNode) -> Bool {
        let target = mixer  // mainMixerNode equivalent
        var visited = Set<ObjectIdentifier>()
        var queue: [AVAudioNode] = [start]
        
        while !queue.isEmpty {
            let node = queue.removeFirst()
            let id = ObjectIdentifier(node)
            if visited.contains(id) { continue }
            visited.insert(id)
            
            if node === target { return true }
            
            // Walk all output buses
            let busCount = max(node.numberOfOutputs, 1)
            for bus in 0..<busCount {
                for cp in engine.outputConnectionPoints(for: node, outputBus: bus) {
                    if let nextNode = cp.node {
                        queue.append(nextNode)
                    }
                }
            }
        }
        return false
    }
    
    var currentTimeString: String {
        // Convert beats to seconds for time display
        let tempo = currentProject?.tempo ?? 120.0
        let timeInSeconds = currentPosition.beats * (60.0 / tempo)
        let minutes = Int(timeInSeconds) / 60
        let seconds = Int(timeInSeconds) % 60
        let milliseconds = Int((timeInSeconds.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    /// Current position as a beat string (bar.beat.subdivision)
    var currentBeatString: String {
        currentPosition.displayString(timeSignature: currentProject?.timeSignature ?? .fourFour)
    }
    
    var currentMusicalTimeString: String {
        guard let project = currentProject else { return "1.1.00" }
        return currentPosition.displayString(timeSignature: project.timeSignature)
    }
    
    // MARK: - Track-Specific Methods
    func getTrackLevel(_ trackId: UUID) -> Float {
        meteringService.getTrackLevel(trackId)
    }
    
    func updateTrackRecordEnable(_ trackId: UUID, _ enabled: Bool) {
        guard var project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].mixerSettings.isRecordEnabled = enabled
        currentProject = project
        
        // Update audio node if it exists
        trackNodes[trackId]?.setRecordEnabled(enabled)
        
    }
    
    func updateInputMonitoring(_ trackId: UUID, _ enabled: Bool) {
        guard var project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].mixerSettings.inputMonitoring = enabled
        currentProject = project
        
        // Update audio node if it exists
        trackNodes[trackId]?.setInputMonitoring(enabled)
        
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
        
    }
    
    // MARK: - Wet-Solo Debug Helper
    
    /// STEP 3: Wet-Solo functionality for instant audibility check
    func enableWetSolo(trackId: UUID, enabled: Bool) {
        guard let trackNode = trackNodes[trackId] else {
            return
        }
        
        // Get the main mixer destination for this track's pan node
        guard let mixing = trackNode.panNode as? AVAudioMixing,
              let mainDest = mixing.destination(forMixer: mixer, bus: 0) else {
            return
        }
        
        if enabled {
            // Wet-solo ON: kill the dry branch for this track
            mainDest.volume = 0.0
        } else {
            // Wet-solo OFF: restore the dry branch for this track
            mainDest.volume = 1.0
        }
    }
    
    /// Debug helper to check bus levels
    func debugBusLevels(busId: UUID) {
        guard let busNode = busNodes[busId] else {
            return
        }
        
    }
    
    // MARK: - Transport Safe Jump (internal implementation for cycle jumps)
    
    // NOTE: Scheduling methods are now handled by PlaybackSchedulingCoordinator
    
    /// Safe play guard - ensures player has output connections before playing
    /// Note: Consider moving to PlaybackSchedulingCoordinator in future refactor
    private func safePlay(_ player: AVAudioPlayerNode) {
        playbackScheduler.safePlay(player)
    }
    
    // MARK: - Memory Pressure (Phase 5: Error Recovery)
    
    /// Called under memory pressure to release non-essential caches. Safe to call from main thread.
    /// On macOS there is no system memory-warning notification; wire to DISPATCH_SOURCE_TYPE_MEMORYPRESSURE if desired.
    func handleMemoryWarning() {
        AppLogger.shared.warning("AudioEngine: Handling memory pressure", category: .audio)
        
        // Release mixer caches
        mixerController.invalidateTrackIndexCache()
        
        // Release audio buffer pool
        AudioResourcePool.shared.handleMemoryWarning()
        
        // Clear audio file caches in track nodes
        for (_, trackNode) in trackNodes {
            trackNode.clearAudioFileCache()
        }
        
        // Future: clear cachedWaveforms when those caches exist
    }
    
    // MARK: - Diagnostics
    
    /// Generate comprehensive diagnostic report for troubleshooting.
    /// Returns markdown-formatted text suitable for bug reports or logging.
    func generateDiagnosticReport() -> String {
        guard let healthMonitor = healthMonitor else {
            return "⚠️ Diagnostic report unavailable: Health monitor not yet initialized"
        }
        
        return AudioEngineDiagnostics.generateReport(
            engine: engine,
            graphFormat: graphFormat,
            trackNodes: trackNodes,
            busNodes: busNodes,
            currentProject: currentProject,
            healthMonitor: healthMonitor,
            errorTracker: errorTracker,
            performanceMonitor: AudioPerformanceMonitor.shared
        )
    }
    
    /// Save diagnostic report to Documents folder.
    /// Returns URL of saved report or nil if failed.
    @discardableResult
    func saveDiagnosticReport() -> URL? {
        guard let healthMonitor = healthMonitor else {
            AppLogger.shared.warning("Cannot save diagnostic report: Health monitor not initialized", category: .audio)
            return nil
        }
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        return AudioEngineDiagnostics.saveDiagnosticReport(
            to: documentsURL,
            engine: engine,
            graphFormat: graphFormat,
            trackNodes: trackNodes,
            busNodes: busNodes,
            currentProject: currentProject,
            healthMonitor: healthMonitor,
            errorTracker: errorTracker,
            performanceMonitor: AudioPerformanceMonitor.shared
        )
    }
    
    /// Perform comprehensive system health check.
    /// Returns true if all systems are healthy and ready for operation.
    /// Use this for quick health verification or before critical operations.
    @discardableResult
    func performSystemHealthCheck() -> Bool {
        logDebug("🏥 Performing system health check", category: "HEALTH")
        
        // Check if health monitor is initialized
        guard let healthMonitor = healthMonitor else {
            logDebug("⚠️ Health monitor not yet initialized", category: "HEALTH")
            return false
        }
        
        // 1. Validate engine state
        let healthResult = healthMonitor.validateState()
        if !healthResult.isValid {
            logDebug("❌ Health validation failed: \(healthResult.issues.count) issues", category: "HEALTH")
            for issue in healthResult.criticalIssues {
                logDebug("  - CRITICAL: \(issue.component): \(issue.description)", category: "HEALTH")
            }
            return false
        }
        
        // 2. Check error tracker health
        let errorHealth = errorTracker.engineHealth
        switch errorHealth {
        case .healthy:
            logDebug("✅ Error health: Healthy", category: "HEALTH")
        case .degraded(let reason):
            logDebug("⚠️ Error health: Degraded - \(reason)", category: "HEALTH")
        case .unhealthy(let reason):
            logDebug("❌ Error health: Unhealthy - \(reason)", category: "HEALTH")
            return false
        case .critical(let reason):
            logDebug("🔴 Error health: CRITICAL - \(reason)", category: "HEALTH")
            return false
        }
        
        // 3. Check memory pressure
        let resourcePool = AudioResourcePool.shared
        if resourcePool.isUnderMemoryPressure {
            logDebug("⚠️ Memory pressure detected", category: "HEALTH")
        }
        
        // 4. Check for recent performance issues
        let recentSlowOps = AudioPerformanceMonitor.shared.getRecentSlowOperations(within: 60, limit: 5)
        if !recentSlowOps.isEmpty {
            logDebug("⚠️ \(recentSlowOps.count) slow operations in last 60s", category: "HEALTH")
        }
        
        logDebug("✅ System health check: PASSED", category: "HEALTH")
        return true
    }
    
    /// Get a user-facing health status message.
    /// Use this to display engine status in UI.
    func getHealthStatusMessage() -> String {
        // Check if health monitor is initialized
        guard let healthMonitor = healthMonitor else {
            return "⏳ Audio Engine Initializing..."
        }
        
        let healthStatus = healthMonitor.currentHealth
        let errorStatus = errorTracker.engineHealth
        let memoryPressure = AudioResourcePool.shared.isUnderMemoryPressure
        
        // Return worst status
        if case .critical = healthStatus {
            return "🔴 Audio Engine Critical Error - Restart Required"
        }
        if case .critical = errorStatus {
            return "🔴 Multiple Critical Errors - Check Diagnostics"
        }
        if case .unhealthy = healthStatus {
            return "❌ Audio Engine Unhealthy - Playback May Fail"
        }
        if case .unhealthy = errorStatus {
            return "❌ High Error Rate - Check Error Log"
        }
        if memoryPressure {
            return "⚠️ Memory Pressure - Close Other Applications"
        }
        if case .degraded = healthStatus {
            return "⚠️ Audio Engine Degraded - Minor Issues Detected"
        }
        if case .degraded = errorStatus {
            return "⚠️ Some Warnings - Audio Should Work"
        }
        
        return "✅ Audio Engine Healthy"
    }
    
    // MARK: - Playback Debugging
}
