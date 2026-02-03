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
    private var debugAudioFlow: Bool { AudioDebugConfig.logAudioFlow }
    
    /// Debug logging with autoclosure to prevent string allocation when disabled
    /// PERFORMANCE: When debugAudioFlow is false, the message closure is never evaluated
    private func logDebug(_ message: @autoclosure () -> String, category: String = "AUDIO") {
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
    private let midiPlaybackEngine = MIDIPlaybackEngine()
    
    // MARK: - Step Sequencer (MIDI-based, persistent instance)
    @ObservationIgnored
    lazy var sequencerEngine: SequencerEngine = {
        let engine = SequencerEngine(tempo: currentProject?.tempo ?? 120.0)
        configureSequencerMIDICallbacks(engine)
        return engine
    }()
    
    // MARK: - Automation
    @ObservationIgnored
    private let automationProcessor = AutomationProcessor()
    
    /// High-priority automation engine (runs on dedicated queue)
    @ObservationIgnored
    private let automationEngine = AutomationEngine()
    
    /// Automation recorder for capturing parameter changes during playback
    @ObservationIgnored
    let automationRecorder = AutomationRecorder()
    
    // MARK: - Private Properties (all ignored for observation)
    @ObservationIgnored
    private let engine = AVAudioEngine()
    @ObservationIgnored
    private let mixer = AVAudioMixerNode()
    @ObservationIgnored
    private let masterEQ = AVAudioUnitEQ(numberOfBands: 3)  // Master EQ: Hi, Mid, Lo
    @ObservationIgnored
    private let masterLimiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    ))
    
    // NOTE: Graph mutation coordination is now handled by AudioGraphManager
    
    @ObservationIgnored
    private var pendingGraphMutations: [() -> Void] = []
    
    /// Graph generation counter - delegated to AudioGraphManager
    private var graphGeneration: Int {
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
    private func isGraphGenerationValid(_ capturedGeneration: Int, context: String = "") -> Bool {
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
    /// High-priority timer for health checks (immune to main thread blocking)
    @ObservationIgnored
    private var engineHealthTimer: DispatchSourceTimer?
    
    /// Background queue for health monitoring (utility priority - not critical path)
    @ObservationIgnored
    private let healthMonitorQueue = DispatchQueue(
        label: "com.stori.engine.health",
        qos: .utility
    )
    
    /// Whether the engine is expected to be running (for health monitoring)
    @ObservationIgnored
    private var engineExpectedToRun: Bool = false
    
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
    private var graphFormat: AVAudioFormat!
    
    // MARK: - Rebuild Coalescing (prevents rebuild storms)
    @ObservationIgnored
    private var pendingRebuildTrackIds: Set<UUID> = []
    
    @ObservationIgnored
    private var rebuildTask: Task<Void, Never>?
    
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
        metronome.install(into: engine, dawMixer: mixer, audioEngine: self)
        installedMetronome = metronome
        
        // Restart if it was running
        if wasRunning {
            do {
                try engine.start()
                // Start the metronome player node (keeps it ready for scheduling)
                metronome.preparePlayerNode()
            } catch {
            }
        }
    }
    @ObservationIgnored
    private var trackNodes: [UUID: TrackAudioNode] = [:]
    
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
    private var playbackScheduler: PlaybackSchedulingCoordinator!
    
    // MARK: - Audio Graph Manager (Extracted)
    /// Manages audio graph mutations with tiered performance characteristics
    @ObservationIgnored
    private var graphManager: AudioGraphManager!
    
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
    private var transportController: TransportController!
    
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
        
        // Initialize bus manager after audio engine is set up
        busManager = BusManager(
            engine: engine,
            mixer: mixer,
            trackNodes: { [weak self] in self?.trackNodes ?? [:] },
            currentProject: { [weak self] in self?.currentProject },
            transportState: { [weak self] in self?.transportController?.transportState ?? .stopped },
            modifyGraphSafely: { [weak self] work in self?.modifyGraphSafely(work) },
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
        
        transportController.setupPositionTimer()
        automationRecorder.configure(audioEngine: self)
        configureAutomationEngine()
        setupProjectSaveObserver()
        setupAudioConfigurationChangeObserver()
        setupTempoChangeObserver()
    }
    
    /// Configure the high-priority automation engine
    private func configureAutomationEngine() {
        automationEngine.processor = automationProcessor
        
        // Thread-safe beat position provider (uses atomic accessor)
        automationEngine.beatPositionProvider = { [weak self] in
            self?.transportController?.atomicBeatPosition ?? 0
        }
        
        // Unified scheduling context provider (preferred for multi-value access)
        automationEngine.schedulingContextProvider = { [weak self] in
            self?.schedulingContext ?? .default
        }
        
        // Track IDs provider
        automationEngine.trackIdsProvider = { [weak self] in
            guard let self = self else { return [] }
            return Array(self.trackNodes.keys)
        }
        
        // Thread-safe automation value applier
        automationEngine.applyValuesHandler = { [weak self] trackId, volume, pan, eqLow, eqMid, eqHigh in
            guard let trackNode = self?.trackNodes[trackId] else { return }
            
            // Apply automation values (TrackAudioNode methods are thread-safe)
            trackNode.applyAutomationValues(
                volume: volume,
                pan: pan,
                eqLow: eqLow,
                eqMid: eqMid,
                eqHigh: eqHigh
            )
        }
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
    /// Also reconnects samplers with the new graphFormat - essential when going from higher
    /// to lower sample rate (e.g., 48kHz Mac → 44.1kHz Bluetooth).
    private func reprimeAllInstrumentsAfterReset() {
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
    private func resetAllSamplerDSPState() {
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
        // Note: Cannot access @MainActor properties in deinit
        // TransportController's timer will be cleaned up automatically
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
        
        // Set fast attack for transparent limiting
        if let attackParam = parameterTree.parameter(withAddress: 0) {
            attackParam.value = 0.005  // 5ms attack
        }
        
        // Set moderate release to avoid pumping
        if let releaseParam = parameterTree.parameter(withAddress: 1) {
            releaseParam.value = 0.1  // 100ms release
        }
        
        // Pre-gain at 0 dB (unity)
        if let preGainParam = parameterTree.parameter(withAddress: 2) {
            preGainParam.value = 0.0
        }
        
        AppLogger.shared.debug("Master limiter configured for safe headroom", category: .audio)
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
                engineStartRetryAttempt = 0  // Reset retry counter on success
                AppLogger.shared.info("Audio engine started successfully", category: .audio)
            }
        } catch {
            AppLogger.shared.error("Engine start failed (attempt \(engineStartRetryAttempt + 1)): \(error.localizedDescription)", category: .audio)
            
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
    
    /// Setup periodic engine health checks using DispatchSourceTimer
    /// This timer runs on a background queue and is immune to main thread blocking
    private func setupEngineHealthMonitoring() {
        // Cancel existing timer
        engineHealthTimer?.cancel()
        engineHealthTimer = nil
        
        // Create timer on background queue
        let timer = DispatchSource.makeTimerSource(queue: healthMonitorQueue)
        timer.schedule(
            deadline: .now() + 2.0,
            repeating: 2.0,
            leeway: .seconds(1)  // Relaxed leeway since health checks are not time-critical
        )
        timer.setEventHandler { [weak self] in
            // Dispatch to MainActor for engine access
            Task { @MainActor in
                self?.checkEngineHealth()
            }
        }
        timer.resume()
        engineHealthTimer = timer
    }
    
    /// Check engine health and attempt recovery if needed
    private func checkEngineHealth() {
        // Only check if we expect the engine to be running
        guard engineExpectedToRun else {
            healthCheckFailureCount = 0
            return
        }
        
        if !engine.isRunning {
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
    
    // MARK: - Automation Application
    
    /// Apply automation values to track parameters at the current playback position
    private func applyAutomation(at timeInSeconds: TimeInterval) {
        guard let project = currentProject else { return }
        
        // Convert seconds to beats for automation lookup (automation is stored in beats)
        let beatsPerSecond = project.tempo / 60.0
        let timeInBeats = timeInSeconds * beatsPerSecond
        
        for track in project.tracks {
            guard let node = trackNodes[track.id] else { continue }
            
            // Skip if automation is off for this track
            guard track.automationMode.canRead else { continue }
            
            // Get all automation values for this track at current beat position
            if let values = automationProcessor.getAllValues(for: track.id, atBeat: timeInBeats) {
                // Apply volume automation with smoothing to prevent zippering
                // Fall back to mixer settings if nil (before first breakpoint)
                let volume = values.volume ?? track.mixerSettings.volume
                node.setVolumeSmoothed(volume)
                
                // Apply pan automation with smoothing
                // Pan: mixer stores 0-1, automation stores 0-1, convert to -1..+1 for node
                let pan = values.pan ?? track.mixerSettings.pan
                node.setPanSmoothed(pan * 2 - 1)
                
                // Apply EQ automation (convert 0-1 to -12..+12 dB)
                // EQ parameters can change without smoothing (band gains are less sensitive to zippering)
                let eqLow = ((values.eqLow ?? 0.5) - 0.5) * 24
                let eqMid = ((values.eqMid ?? 0.5) - 0.5) * 24
                let eqHigh = ((values.eqHigh ?? 0.5) - 0.5) * 24
                
                node.setEQ(
                    highGain: eqHigh,
                    midGain: eqMid,
                    lowGain: eqLow
                )
            } else {
                // No automation data at all for this track - apply mixer settings (no smoothing needed)
                node.setVolume(track.mixerSettings.volume)
                node.setPan(track.mixerSettings.pan * 2 - 1)
                node.setEQ(highGain: 0, midGain: 0, lowGain: 0)
            }
        }
    }
    
    /// Update automation processor with track's automation data
    func updateTrackAutomation(_ track: AudioTrack) {
        automationProcessor.updateAutomation(
            for: track.id,
            lanes: track.automationLanes,
            mode: track.automationMode
        )
    }
    
    /// Commit recorded automation points to a track
    /// Called by AutomationRecorder when recording stops
    /// - Parameters:
    ///   - points: The recorded automation points
    ///   - parameter: The parameter that was automated
    ///   - trackId: The track to add automation to
    ///   - projectUpdateHandler: Callback to update the project state
    func commitRecordedAutomation(
        points: [AutomationPoint],
        parameter: AutomationParameter,
        trackId: UUID,
        projectUpdateHandler: @escaping (inout AudioProject) -> Void
    ) {
        guard var project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        
        var track = project.tracks[trackIndex]
        
        // Find or create the automation lane for this parameter
        if let laneIndex = track.automationLanes.firstIndex(where: { $0.parameter == parameter }) {
            // Merge points into existing lane
            let startBeat = points.first?.beat ?? 0
            let endBeat = points.last?.beat ?? 0
            
            AutomationRecorder.mergePoints(
                recorded: points,
                into: &track.automationLanes[laneIndex].points,
                startTime: startBeat,
                endTime: endBeat,
                mode: track.automationMode
            )
        } else {
            // Create new lane with the recorded points
            var newLane = AutomationLane(
                parameter: parameter,
                color: parameter.color
            )
            newLane.points = points
            track.automationLanes.append(newLane)
        }
        
        project.tracks[trackIndex] = track
        currentProject = project
        
        // Update the automation processor with new data
        updateTrackAutomation(track)
        
        // Call the project update handler to persist changes
        projectUpdateHandler(&project)
    }
    
    /// Update automation for all tracks in current project
    private func updateAllTrackAutomation() {
        guard let project = currentProject else { return }
        for track in project.tracks {
            updateTrackAutomation(track)
        }
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
    
    /// Create instruments for MIDI tracks and connect them to plugin chains
    /// Called after plugin restoration to ensure samplers are routed through effects
    @MainActor
    private func createAndConnectMIDIInstruments(for project: AudioProject) async {
        
        // Ensure InstrumentManager has our engine reference
        InstrumentManager.shared.audioEngine = self
        
        // Also ensure projectManager is set (needed for getOrCreateInstrument)
        if InstrumentManager.shared.projectManager == nil {
            // Try to get projectManager from the environment
            // For now, we'll create instruments directly from track data
        }
        
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
                    rebuildTrackGraph(trackId: track.id)
                } else {
                }
            } else {
            }
        }
        
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
            }
            
            
            // Set up audio nodes for new tracks
            for trackId in addedTrackIds {
                if let newTrack = project.tracks.first(where: { $0.id == trackId }) {
                    let trackNode = createTrackNode(for: newTrack)
                    trackNodes[trackId] = trackNode
                    
                    // Use centralized rebuild for all connections
                    rebuildTrackGraph(trackId: trackId)
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
                            
                            // Re-schedule from current position (convert beats to seconds for AVAudioEngine)
                            let tempo = currentProject?.tempo ?? 120.0
                            let currentTimeSeconds = currentPosition.beats * (60.0 / tempo)
                            do {
                                try trackNode.scheduleFromPosition(currentTimeSeconds, audioRegions: track.regions, tempo: tempo)
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
                if let trackNode = trackNodes[trackId] {
                    // [BUGFIX] Safe node disconnection with existence checks
                    safeDisconnectTrackNode(trackNode)
                    trackNodes.removeValue(forKey: trackId)
                }
            }
            
            // Update solo state in case new tracks affect it
            updateSoloState()
            
            // Update automation data for all tracks
            updateAllTrackAutomation()
        }
        
    }
    
    private func setupTracksForProject(_ project: AudioProject) {
        logDebug("setupTracksForProject: \(project.tracks.count) tracks", category: "PROJECT")
        
        // Clear existing track nodes
        clearAllTracks()
        
        // Create track nodes for each track
        for track in project.tracks {
            logDebug("Creating node for track '\(track.name)' (type: \(track.trackType), regions: \(track.regions.count), midiRegions: \(track.midiRegions.count))", category: "PROJECT")
            let trackNode = createTrackNode(for: track)
            trackNodes[track.id] = trackNode
        }
        
        logDebug("Created \(trackNodes.count) track nodes", category: "PROJECT")
        
        // Use centralized rebuild for all track connections
        // This handles both tracks with and without sends
        for track in project.tracks {
            rebuildTrackGraph(trackId: track.id)
        }
        
        // CRITICAL FIX: Reconnect metronome after track connections
        // AVAudioEngine can disconnect other mixer inputs when connecting to specific buses
        installedMetronome?.reconnectNodes(dawMixer: mixer)
        
        // ATOMIC OPERATION: Restore all track mixer states (mute/solo) from project data
        // This is atomic to prevent any window where mixer state is inconsistent
        mixerController.atomicResetTrackStates(from: project.tracks)
    }
    
    // [V2-ANALYSIS] Public access to track nodes for pitch/tempo adjustments
    func getTrackNode(for trackId: UUID) -> TrackAudioNode? {
        return trackNodes[trackId]
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
        
        // Use centralized rebuild for all connections
        rebuildTrackGraph(trackId: track.id)
        
    }
    
    /// Creates a track node and attaches all nodes to the engine.
    /// NOTE: This only attaches nodes - caller must call rebuildTrackGraph() after storing in trackNodes
    private func createTrackNode(for track: AudioTrack) -> TrackAudioNode {
        logDebug("Creating track node for '\(track.name)' (id: \(track.id), type: \(track.trackType))", category: "TRACK")
        
        let playerNode = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()  // [V2-PITCH/TEMPO]
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        
        // Create plugin chain for insert effects (8 slots)
        let pluginChain = PluginChain(id: UUID(), maxSlots: 8)
        
        // Ensure engine is running before attaching nodes
        // NOTE: engine.start() is synchronous - no sleep needed after it returns
        if !engine.isRunning {
            startAudioEngine()
            engine.prepare()  // Ensure audio graph is ready for node attachment
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
        logDebug("Attached all track nodes to engine (connections pending)", category: "TRACK")
        
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
        
        // 🔍 LOGGING: Confirm unit passed to TrackAudioNode
        
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
            loadAudioRegion(region, trackNode: trackNode)
        }
        
        return trackNode
    }
    
    private func clearAllTracks() {
        // First, explicitly clean up each track node to remove taps safely
        for (_, trackNode) in trackNodes {
            // [BUGFIX] Use safe disconnection method
            safeDisconnectTrackNode(trackNode)
        }
        
        // Clear the collections
        trackNodes.removeAll()
        mixerController.clearSoloTracks()
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
    
    // MARK: [BUGFIX] Safe Node Disconnection
    /// Disconnects and detaches track nodes. Must run inside graph mutation serialization to avoid races.
    private func safeDisconnectTrackNode(_ trackNode: TrackAudioNode) {
        modifyGraphSafely {
            // Uninstall plugin chain first (this unloads all plugins and detaches mixers)
            trackNode.pluginChain.uninstall()

            let nodesToDisconnect: [(node: AVAudioNode, name: String)] = [
                (trackNode.panNode, "panNode"),
                (trackNode.volumeNode, "volumeNode"),
                (trackNode.eqNode, "eqNode"),
                (trackNode.timePitchUnit, "timePitchUnit"),
                (trackNode.playerNode, "playerNode")
            ]

            for (node, _) in nodesToDisconnect {
                if engine.attachedNodes.contains(node) {
                    do {
                        if let playerNode = node as? AVAudioPlayerNode, playerNode.isPlaying {
                            playerNode.stop()
                        }
                        engine.disconnectNodeInput(node)
                        engine.detach(node)
                    } catch {
                    }
                }
            }
        }
    }

    // MARK: - Tiered Graph Mutation (Delegated to AudioGraphManager)
    
    /// Performs a structural graph mutation
    /// DELEGATED to AudioGraphManager
    private func modifyGraphSafely(_ work: () throws -> Void) rethrows {
        try graphManager.modifyGraphSafely(work)
    }
    
    /// Performs a connection-only graph mutation
    /// DELEGATED to AudioGraphManager
    private func modifyGraphConnections(_ work: () throws -> Void) rethrows {
        try graphManager.modifyGraphConnections(work)
    }
    
    /// Performs a track-scoped hot-swap mutation
    /// DELEGATED to AudioGraphManager
    func modifyGraphForTrack(_ trackId: UUID, _ work: () throws -> Void) rethrows {
        try graphManager.modifyGraphForTrack(trackId, work)
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
    private func rebuildTrackGraph(trackId: UUID) {
        guard let trackNode = trackNodes[trackId] else {
            return
        }
        
        let format = graphFormat!
        let pluginChain = trackNode.pluginChain
        let hasPlugins = pluginChain.hasActivePlugins
        let chainIsRealized = pluginChain.isRealized
        
        // Use hot-swap mutation for minimal disruption to other tracks
        modifyGraphForTrack(trackId) {
            // Reset AU units FIRST before disconnection to clear DSP state
            if let instrument = InstrumentManager.shared.getInstrument(for: trackId),
               let sampler = instrument.samplerEngine?.sampler {
                sampler.auAudioUnit.reset()
            }
            for plugin in pluginChain.activePlugins {
                plugin.auAudioUnit?.reset()
            }
            
            // 1. DISCONNECT downstream-first
            self.engine.disconnectNodeOutput(trackNode.panNode)
            self.engine.disconnectNodeOutput(trackNode.volumeNode)
            self.engine.disconnectNodeOutput(trackNode.eqNode)
            
            if chainIsRealized {
                self.engine.disconnectNodeOutput(pluginChain.outputMixer)
                self.engine.disconnectNodeOutput(pluginChain.inputMixer)
                self.engine.disconnectNodeInput(pluginChain.inputMixer)
            }
            
            if let instrument = InstrumentManager.shared.getInstrument(for: trackId),
               let sampler = instrument.samplerEngine?.sampler {
                self.engine.disconnectNodeOutput(sampler)
                self.engine.disconnectNodeInput(sampler)
            } else {
                self.engine.disconnectNodeOutput(trackNode.timePitchUnit)
            }
            
            // Note: fullRenderReset for ALL samplers now happens in modifyGraphSafely
            // after engine.reset() to prevent cross-track corruption
            
            // MIDI Track Mixer State Management
            if chainIsRealized && InstrumentManager.shared.getInstrument(for: trackId) != nil {
                let inputBusCount = pluginChain.inputMixer.numberOfInputs
                pluginChain.resetMixerState()
                if inputBusCount > 1 {
                    pluginChain.recreateMixers()
                }
            }
            
            // 2. CONNECT based on whether plugins exist
            let sourceNode = self.getSourceNode(for: trackId, trackNode: trackNode)
            
            if hasPlugins {
                // WITH PLUGINS: source → inputMixer → [plugins] → outputMixer → eq
                pluginChain.realize()
                
                // CRITICAL: Connect outputMixer → trackEQ FIRST to prime output format to 48kHz
                // This prevents AVAudioEngine from inserting a 48kHz→44.1kHz converter
                self.engine.connect(pluginChain.outputMixer, to: trackNode.eqNode, format: format)
                
                // Rebuild internal chain connections
                pluginChain.updateFormat(format)
                pluginChain.rebuildChainConnections(engine: self.engine)
                
                // Source → chain input
                if let source = sourceNode {
                    self.engine.connect(source, to: pluginChain.inputMixer, fromBus: 0, toBus: 0, format: format)
                } else {
                    self.engine.connect(trackNode.playerNode, to: trackNode.timePitchUnit, fromBus: 0, toBus: 0, format: format)
                    self.engine.connect(trackNode.timePitchUnit, to: pluginChain.inputMixer, fromBus: 0, toBus: 0, format: format)
                }
                
            } else {
                // NO PLUGINS: source → eq (bypass chain entirely)
                if chainIsRealized {
                    pluginChain.unrealize()
                }
                
                if let source = sourceNode {
                    self.engine.connect(source, to: trackNode.eqNode, fromBus: 0, toBus: 0, format: format)
                } else {
                    self.engine.connect(trackNode.playerNode, to: trackNode.timePitchUnit, fromBus: 0, toBus: 0, format: format)
                    self.engine.connect(trackNode.timePitchUnit, to: trackNode.eqNode, fromBus: 0, toBus: 0, format: format)
                }
            }
            
            // EQ → Volume → Pan → main mixer
            self.engine.connect(trackNode.eqNode, to: trackNode.volumeNode, format: format)
            self.engine.connect(trackNode.volumeNode, to: trackNode.panNode, format: format)
            self.connectPanToDestinations(trackId: trackId, trackNode: trackNode, format: format)
            
            trackNode.timePitchUnit.reset()
        }
        
        // Validate connections after rebuild
        validateTrackConnections(trackId: trackId)
    }
    
    // MARK: - Graph Validation
    
    /// Validates that a track's audio graph connections are properly established
    /// Logs warnings if broken connections are detected
    private func validateTrackConnections(trackId: UUID) {
        guard let trackNode = trackNodes[trackId] else {
            AppLogger.shared.warning("Graph validation: Track \(trackId) not found in trackNodes")
            return
        }
        
        var isValid = true
        
        // Check panNode has output connections (should connect to mixer and/or sends)
        let panConnections = engine.outputConnectionPoints(for: trackNode.panNode, outputBus: 0)
        if panConnections.isEmpty {
            AppLogger.shared.warning("Graph validation: Track \(trackId) panNode has no output connections")
            isValid = false
        }
        
        // Check volumeNode → panNode connection
        let volumeConnections = engine.outputConnectionPoints(for: trackNode.volumeNode, outputBus: 0)
        if volumeConnections.isEmpty {
            AppLogger.shared.warning("Graph validation: Track \(trackId) volumeNode has no output connections")
            isValid = false
        }
        
        // Check eqNode → volumeNode connection
        let eqConnections = engine.outputConnectionPoints(for: trackNode.eqNode, outputBus: 0)
        if eqConnections.isEmpty {
            AppLogger.shared.warning("Graph validation: Track \(trackId) eqNode has no output connections")
            isValid = false
        }
        
        // Check plugin chain connections (only if chain is realized)
        if trackNode.pluginChain.isRealized {
            let chainOutputConnections = engine.outputConnectionPoints(for: trackNode.pluginChain.outputMixer, outputBus: 0)
            if chainOutputConnections.isEmpty {
                AppLogger.shared.warning("Graph validation: Track \(trackId) pluginChain.outputMixer has no output connections")
                isValid = false
            }
            
            let chainInputConnections = engine.inputConnectionPoint(for: trackNode.pluginChain.inputMixer, inputBus: 0)
            if chainInputConnections == nil {
                AppLogger.shared.warning("Graph validation: Track \(trackId) pluginChain.inputMixer has no input connection")
                isValid = false
            }
        }
        // If chain is not realized, audio flows directly source→eq which is valid
        
        if isValid && debugAudioFlow {
            logDebug("Graph validation: Track \(trackId) connections valid", category: "GRAPH")
        }
    }
    
    /// Validates all track connections in the current project
    /// Call after major graph operations like project load
    private func validateAllTrackConnections() {
        for trackId in trackNodes.keys {
            validateTrackConnections(trackId: trackId)
        }
    }
    
    /// Logs all node formats in the track signal path for debugging format mismatches
    private func auditTrackFormats(trackId: UUID, trackNode: TrackAudioNode) {
        
        // Source format
        if let instrument = InstrumentManager.shared.getInstrument(for: trackId),
           let sampler = instrument.samplerEngine?.sampler {
            _ = sampler.outputFormat(forBus: 0)
        } else {
            _ = trackNode.timePitchUnit.outputFormat(forBus: 0)
        }
        
        // Plugin chain (only if realized)
        if trackNode.pluginChain.isRealized {
            _ = trackNode.pluginChain.inputMixer.inputFormat(forBus: 0)
            _ = trackNode.pluginChain.inputMixer.outputFormat(forBus: 0)
            
            for plugin in trackNode.pluginChain.activePlugins {
                if let node = plugin.avAudioUnit {
                    _ = node.inputFormat(forBus: 0)
                    _ = node.outputFormat(forBus: 0)
                }
            }
            
            _ = trackNode.pluginChain.outputMixer.inputFormat(forBus: 0)
            _ = trackNode.pluginChain.outputMixer.outputFormat(forBus: 0)
        }
        
        // EQ, Volume, Pan
        _ = trackNode.eqNode.outputFormat(forBus: 0)
        _ = trackNode.volumeNode.outputFormat(forBus: 0)
        _ = trackNode.panNode.outputFormat(forBus: 0)
        
        // Main mixer input
        if let project = currentProject,
           let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            _ = mixer.inputFormat(forBus: AVAudioNodeBus(trackIndex))
        }
        
    }
    
    /// Rebuilds only the plugin chain interior (minimal blast radius).
    /// Called when: toggling bypass, reconnecting existing plugins.
    /// Uses connection-only mutation (pause/resume, no reset) for minimal disruption.
    private func rebuildPluginChain(trackId: UUID) {
        guard let trackNode = trackNodes[trackId] else {
            return
        }
        
        let format = graphFormat!
        
        // Use lighter-weight connection mutation - no engine reset needed
        // since we're only reconnecting existing nodes
        modifyGraphConnections {
            trackNode.pluginChain.updateFormat(format)
            trackNode.pluginChain.rebuildChainConnections(engine: self.engine)
        }
    }
    
    /// Schedules a track graph rebuild with coalescing (debounced).
    /// Multiple calls within 50ms will be batched into a single rebuild operation.
    /// Use this when you expect rapid-fire state changes that each want a rebuild.
    func scheduleRebuild(trackId: UUID) {
        logDebug("📅 scheduleRebuild: track=\(trackId)")
        logDebug("   Stack trace: \(Thread.callStackSymbols.joined(separator: "\n"))")
        
        pendingRebuildTrackIds.insert(trackId)
        
        rebuildTask?.cancel()
        rebuildTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
            guard !Task.isCancelled else {
                logDebug("   ⚠️ Rebuild task cancelled")
                return
            }
            
            let tracksToRebuild = pendingRebuildTrackIds
            pendingRebuildTrackIds.removeAll()
            
            logDebug("   ✅ Executing scheduled rebuild for \(tracksToRebuild.count) tracks")
            for trackId in tracksToRebuild {
                rebuildTrackGraph(trackId: trackId)
            }
        }
    }
    
    /// Gets the source node for a track (sampler for MIDI, timePitch for audio)
    private func getSourceNode(for trackId: UUID, trackNode: TrackAudioNode) -> AVAudioNode? {
        // Use InstrumentManager as single source of truth for instruments
        if let instrument = InstrumentManager.shared.getInstrument(for: trackId) {
            // Check for sampler-based instrument
            if let samplerEngine = instrument.samplerEngine,
               samplerEngine.sampler.engine === engine {
                return samplerEngine.sampler
            }
            
            // Check for drum kit instrument
            if let drumKitEngine = instrument.drumKitEngine {
                return drumKitEngine.getOutputNode()
            }
            
            // Check for AU-based instrument
            if let auNode = instrument.audioUnitNode,
               auNode.engine === engine {
                return auNode
            }
        }
        
        // Return nil to indicate audio track (use timePitch)
        return nil
    }
    
    /// Connects panNode to main mixer
    /// Note: Track sends are handled separately by BusManager during project/bus setup
    private func connectPanToDestinations(trackId: UUID, trackNode: TrackAudioNode, format: AVAudioFormat) {
        guard let project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            // Fallback: just connect to main mixer on bus 0
            engine.connect(trackNode.panNode, to: mixer, format: format)
            return
        }
        
        let trackBusNumber = AVAudioNodeBus(trackIndex)
        
        // Connect to main mixer - sends are configured separately by BusManager
        engine.connect(trackNode.panNode, to: mixer, fromBus: 0, toBus: trackBusNumber, format: format)
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
            // Reset smoothing values for all tracks before starting
            for (_, trackNode) in trackNodes {
                trackNode.resetSmoothing()
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
    
    // MARK: - Playback Implementation
    private func startPlayback() {
        guard let project = currentProject else {
            logDebug("⚠️ startPlayback: No current project", category: "PLAYBACK")
            return
        }

        let startBeat = currentPosition.beats
        let tempo = project.tempo
        // Convert beats to seconds for audio scheduling (AVAudioEngine boundary)
        let startTimeSeconds = startBeat * (60.0 / tempo)
        
        logDebug("startPlayback: \(project.tracks.count) tracks, startBeat: \(startBeat), tempo: \(tempo)", category: "PLAYBACK")

        for track in project.tracks {
            guard let trackNode = trackNodes[track.id] else {
                logDebug("⚠️ No trackNode for track '\(track.name)' (id: \(track.id))", category: "PLAYBACK")
                continue
            }
            
            logDebug("Scheduling track '\(track.name)': \(track.regions.count) audio regions, \(track.midiRegions.count) MIDI regions", category: "PLAYBACK")

            do {
                // scheduleFromPosition takes seconds for AVAudioEngine scheduling
                try trackNode.scheduleFromPosition(startTimeSeconds, audioRegions: track.regions, tempo: tempo)
                if !track.regions.isEmpty {
                    trackNode.play()
                    logDebug("Track '\(track.name)' started playing", category: "PLAYBACK")
                }
            } catch {
                logDebug("⚠️ Error scheduling track \(track.name): \(error)", category: "PLAYBACK")
            }
        }

        // Start MIDI playback with tempo for beats→seconds conversion
        // FIX: Call directly (both are @MainActor) - Task wrapper caused async delay
        // which missed notes at beat 0 on initial playback
        // Note: MIDI engine always runs - it only plays if MIDI regions exist
        logDebug("Configuring MIDI playback engine", category: "PLAYBACK")
        midiPlaybackEngine.configure(with: InstrumentManager.shared, audioEngine: self)
        midiPlaybackEngine.loadRegions(from: project.tracks, tempo: project.tempo)
        midiPlaybackEngine.play(fromBeat: startBeat)
        logDebug("MIDI playback started", category: "PLAYBACK")
    }
    
    private func stopPlayback() {
        // Stop MIDI playback - call directly (both are @MainActor)
        midiPlaybackEngine.stop()
        
        // Stop all player nodes immediately
        // Plugin tails (reverb/delay) will naturally ring out through the graph
        // No volume manipulation needed - let the audio decay naturally
        for (_, trackNode) in trackNodes {
            trackNode.playerNode.stop()
        }
    }
    
    private func playTrack(_ track: AudioTrack, from startTime: TimeInterval) {
        // Get the track's dedicated player node
        guard let trackNode = trackNodes[track.id] else {
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
        let tempo = currentProject?.tempo ?? 120.0
        
        // SECURITY (H-1): Validate header before passing to AVAudioFile
        guard AudioFileHeaderValidator.validateHeader(at: region.audioFile.url) else { return }
        
        do {
            let audioFile = try AVAudioFile(forReading: region.audioFile.url)
            let regionStartSeconds = region.startTimeSeconds(tempo: tempo)
            let regionEndSeconds = regionStartSeconds + region.durationSeconds(tempo: tempo)
            let offsetInFile = currentTime - regionStartSeconds + region.offset
            let remainingDuration = regionEndSeconds - currentTime
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
                
            }
        } catch {
        }
    }
    
    private func scheduleRegionForSynchronizedPlayback(_ region: AudioRegion, on trackNode: TrackAudioNode, at currentTime: TimeInterval) -> Bool {
        let playerNode = trackNode.playerNode
        let tempo = currentProject?.tempo ?? 120.0
        
        // SECURITY (H-1): Validate header before passing to AVAudioFile
        guard AudioFileHeaderValidator.validateHeader(at: region.audioFile.url) else { return false }
        
        do {
            let audioFile = try AVAudioFile(forReading: region.audioFile.url)
            let regionStartSeconds = region.startTimeSeconds(tempo: tempo)
            let regionEndSeconds = regionStartSeconds + region.durationSeconds(tempo: tempo)
            let offsetInFile = currentTime - regionStartSeconds + region.offset
            let remainingDuration = regionEndSeconds - currentTime
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
                
                return true
            }
        } catch {
        }
        
        return false
    }
    
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
    
    // MARK: - Audio File Import

    /// Maximum audio file size for import (500 MB) to prevent memory exhaustion.
    static let maxAudioImportFileSize: Int64 = 500_000_000

    func importAudioFile(from url: URL) async throws -> AudioFile {
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        guard fileSize <= Self.maxAudioImportFileSize else {
            throw NSError(domain: "AudioEngine", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Audio file too large (\(fileSize / 1_000_000) MB). Maximum is \(Self.maxAudioImportFileSize / 1_000_000) MB."
            ])
        }
        // SECURITY (H-1): Validate header before passing to AVAudioFile
        guard AudioFileHeaderValidator.validateHeader(at: url) else {
            throw NSError(domain: "AudioEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid or unsupported audio file format"])
        }

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        
        let audioFileFormat: AudioFileFormat
        switch url.pathExtension.lowercased() {
        case "wav": audioFileFormat = .wav
        case "aiff", "aif": audioFileFormat = .aiff
        case "mp3", "m4a": audioFileFormat = .m4a  // MP3 not supported, treat as M4A
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
        logDebug("Loading audio region '\(region.id)' with file '\(audioFile.name)' at beat \(region.startBeat)", category: "REGION")
        
        do {
            try trackNode.loadAudioFile(audioFile)
            logDebug("Audio file loaded successfully: \(audioFile.url.lastPathComponent)", category: "REGION")
        } catch {
            logDebug("⚠️ Failed to load audio file: \(error)", category: "REGION")
        }
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
    
    /// Get the instrument for a track (delegates to InstrumentManager)
    func getTrackInstrument(for trackId: UUID) -> TrackInstrument? {
        return InstrumentManager.shared.getInstrument(for: trackId)
    }
    
    /// Load an AU instrument for a MIDI/Instrument track
    /// Uses serialized graph queue to prevent concurrent access crashes
    func loadTrackInstrument(trackId: UUID, descriptor: PluginDescriptor) async throws {
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
    func unloadTrackInstrument(trackId: UUID) {
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
    func sendMIDINoteToTrack(trackId: UUID, noteOn: Bool, pitch: UInt8, velocity: UInt8) {
        // Use InstrumentManager for MIDI routing (single source of truth)
        if noteOn {
            InstrumentManager.shared.noteOn(pitch: pitch, velocity: velocity, forTrack: trackId)
        } else {
            InstrumentManager.shared.noteOff(pitch: pitch, forTrack: trackId)
        }
    }
    
    // MARK: - Step Sequencer MIDI Routing
    
    /// Configure MIDI event callbacks for the step sequencer
    private func configureSequencerMIDICallbacks(_ sequencer: SequencerEngine) {
        // Handle individual MIDI events
        sequencer.onMIDIEvent = { [weak self] event in
            self?.handleSequencerMIDIEvent(event)
        }
        
        // Handle batch events (more efficient for routing multiple notes)
        sequencer.onMIDIEvents = { [weak self] events in
            self?.handleSequencerMIDIEvents(events)
        }
    }
    
    /// Handle a single MIDI event from the step sequencer
    private func handleSequencerMIDIEvent(_ event: SequencerMIDIEvent) {
        let routing = sequencerEngine.routing
        
        switch routing.mode {
        case .preview:
            // Preview mode - internal sampler handles playback
            // MIDI events are still generated but not routed
            break
            
        case .singleTrack:
            // Route to single target track
            if let trackId = routing.targetTrackId {
                sendSequencerEventToTrack(event, trackId: trackId)
            }
            
        case .multiTrack:
            // Route based on per-lane configuration
            if let trackId = routing.perLaneRouting[event.laneId] ?? routing.targetTrackId {
                sendSequencerEventToTrack(event, trackId: trackId)
            }
            
        case .external:
            // TODO: External MIDI device output
            break
        }
    }
    
    /// Handle batch MIDI events from the step sequencer
    private func handleSequencerMIDIEvents(_ events: [SequencerMIDIEvent]) {
        for event in events {
            handleSequencerMIDIEvent(event)
        }
    }
    
    /// Send a sequencer MIDI event to a track's instrument
    private func sendSequencerEventToTrack(_ event: SequencerMIDIEvent, trackId: UUID) {
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
    func getMIDITracksForSequencerRouting() -> [(id: UUID, name: String)] {
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
    func trackHasInstrument(_ trackId: UUID) -> Bool {
        return InstrumentManager.shared.getInstrument(for: trackId) != nil
    }
    
    /// Load a GM SoundFont instrument for a MIDI/Instrument track
    func loadTrackGMInstrument(trackId: UUID, instrument gmInstrument: GMInstrument) async throws {
        // Use InstrumentManager as single source of truth for instruments
        let trackInstrument: TrackInstrument
        if let existing = InstrumentManager.shared.getInstrument(for: trackId) {
            // Clean up any existing AU node if switching from AU to sampler
            if let oldAuNode = existing.audioUnitNode {
                modifyGraphSafely {
                    engine.disconnectNodeInput(oldAuNode)
                    engine.disconnectNodeOutput(oldAuNode)
                    engine.detach(oldAuNode)
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
        rebuildTrackGraph(trackId: trackId)
        
        
        // Mark the instrument as running since it's now connected to the DAW engine
        trackInstrument.markAsRunning()
    }
    
    /// Reconnects a MIDI track's instrument (sampler/synth) to its proper destination.
    /// If the track has plugins, connects to pluginChain.inputMixer.
    /// If no plugins, connects directly to eqNode (lazy chain optimization).
    /// This is needed after project reload or when inserting plugins on existing MIDI tracks.
    private func reconnectMIDIInstrumentToPluginChain(trackId: UUID) {
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
    
    // MARK: - Instrument Creation (Single Engine Ownership)
    
    /// Create a sampler instrument attached to the DAW's audio engine
    /// This ensures the sampler is part of the main audio graph and can be routed through plugin chains
    /// - Parameters:
    ///   - trackId: The track this sampler belongs to
    ///   - connectToPluginChain: If true, connects sampler output to the track's plugin chain input
    /// - Returns: A SamplerEngine attached to the main audio engine
    func createSamplerForTrack(_ trackId: UUID, connectToPluginChain: Bool = true) -> SamplerEngine {
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
        
        // Remove from project
        project.tracks.removeAll { $0.id == trackId }
        currentProject = project
        
        // Remove track node
        if let trackNode = trackNodes[trackId] {
            // [BUGFIX] Use safe disconnection method
            safeDisconnectTrackNode(trackNode)
            trackNodes.removeValue(forKey: trackId)
        }
        
        // Update mixer controller's solo tracking
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
        let targetBeat = max(0, beat)
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
        
        // Convert beats to seconds for AVAudioEngine scheduling
        let tempo = project.tempo
        let startTimeSeconds = startBeat * (60.0 / tempo)
        
        // Calculate pre-roll start time (but don't go negative)
        // Pre-roll allows plugins with internal state (reverbs, delays, compressors)
        // to stabilize before we reach the actual playhead position
        let prerollStartSeconds = max(0, startTimeSeconds - prerollSeconds)
        let hasPreroll = startTimeSeconds > prerollSeconds
        
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
                    // Schedule from pre-roll position if we have room, otherwise from start
                    let scheduleTime = hasPreroll ? prerollStartSeconds : startTimeSeconds
                    try trackNode.scheduleFromPosition(scheduleTime, audioRegions: track.regions, tempo: tempo)
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
}
