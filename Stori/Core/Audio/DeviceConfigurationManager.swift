//
//  DeviceConfigurationManager.swift
//  Stori
//
//  Manages audio device configuration changes and format updates.
//  Extracted from AudioEngine.swift for better maintainability.
//

import Foundation
import AVFoundation
import Observation

/// Manages audio hardware configuration changes (e.g., switching audio interfaces)
@Observable
@MainActor
final class DeviceConfigurationManager {
    
    // MARK: - Properties
    
    /// Guard against double observer registration
    @ObservationIgnored
    private var didInstallConfigObserver = false
    
    /// Cancellable task for debounced configuration change handling
    @ObservationIgnored
    private var reconfigTask: Task<Void, Never>?
    
    // MARK: - Dependencies (set by AudioEngine)
    
    @ObservationIgnored
    var engine: AVAudioEngine!
    
    @ObservationIgnored
    var mixer: AVAudioMixerNode!
    
    @ObservationIgnored
    var masterEQ: AVAudioUnitEQ!
    
    @ObservationIgnored
    var masterLimiter: AVAudioUnitEffect!
    
    @ObservationIgnored
    var getGraphFormat: (() -> AVAudioFormat?)?
    
    @ObservationIgnored
    var setGraphFormat: ((AVAudioFormat) -> Void)?
    
    @ObservationIgnored
    var getTrackNodes: (() -> [UUID: TrackAudioNode])?
    
    @ObservationIgnored
    var getCurrentProject: (() -> AudioProject?)?
    
    @ObservationIgnored
    var busManager: BusManager?
    
    @ObservationIgnored
    var midiPlaybackEngine: MIDIPlaybackEngine?
    
    @ObservationIgnored
    var transportController: TransportController?
    
    @ObservationIgnored
    var installedMetronome: MetronomeEngine?
    
    @ObservationIgnored
    var getTransportState: (() -> TransportState)?
    
    @ObservationIgnored
    var getCurrentPosition: (() -> PlaybackPosition)?
    
    @ObservationIgnored
    var onStop: (() -> Void)?
    
    @ObservationIgnored
    var onSeekToBeat: ((Double) -> Void)?
    
    @ObservationIgnored
    var onPlay: (() -> Void)?
    
    @ObservationIgnored
    var onReconnectAllTracks: (() -> Void)?
    
    @ObservationIgnored
    var onReprimeInstruments: (() -> Void)?
    
    @ObservationIgnored
    var setGraphReady: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public API
    
    /// Setup observer for audio hardware configuration changes (e.g., Bluetooth speaker connected)
    /// This ensures the DAW follows the system default audio output device
    func setupObserver() {
        guard !didInstallConfigObserver else { return }
        didInstallConfigObserver = true
        
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleHandler()
        }
    }
    
    // MARK: - Private Implementation
    
    /// Schedule the configuration change handler with debouncing using Task cancellation.
    private func scheduleHandler() {
        reconfigTask?.cancel()
        reconfigTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 350_000_000) // 0.35s debounce
            } catch {
                return // Cancelled
            }
            guard !Task.isCancelled else { return }
            self?.handleConfigurationChange()
        }
    }
    
    /// Handle audio hardware configuration change (e.g., switching to Bluetooth speakers).
    /// Rebuilds the audio graph with the new device's format to ensure proper sample rate matching.
    ///
    /// BUG FIX (Issue #51): Device Sample Rate Change Handling
    /// ========================================================
    /// When audio device changes, ALL scheduled events with sample times must be invalidated.
    /// Sample times are calculated at a specific sample rate and become invalid when rate changes.
    ///
    /// Example: Audio scheduled at 44.1kHz will play at nearly 2x speed if interpreted at 96kHz
    /// because the same sample time represents half the duration.
    ///
    /// This function ensures:
    /// 1. All pending audio is cleared (engine.reset())
    /// 2. All nodes reconnected with new format
    /// 3. MIDI scheduler regenerates timing reference at new rate
    /// 4. Metronome updates sample rate and regenerates click buffers
    /// 5. Playback resumes at same BEAT position (not sample position)
    ///
    /// The beats-first architecture helps here: transport position is stored in beats (musical time)
    /// which remains constant across sample rate changes.
    func handleConfigurationChange() {
        let wasPlaying = getTransportState?().isPlaying ?? false
        let savedPosition = getCurrentPosition?() ?? PlaybackPosition()
        
        // 1) Stop transport + stop schedulers first
        transportController?.stopPositionTimer()
        if wasPlaying {
            onStop?()
        }
        midiPlaybackEngine?.stop()
        setGraphReady?(false)
        
        // 2) Stop + reset the engine (reset clears pending audio data)
        engine.stop()
        engine.reset()
        
        // 3) Get NEW device format and update graphFormat
        let newDeviceFormat = engine.outputNode.outputFormat(forBus: 0)
        let newFormat = AVAudioFormat(
            standardFormatWithSampleRate: newDeviceFormat.sampleRate,
            channels: 2
        )!
        setGraphFormat?(newFormat)
        
        // 3a) Update PDC with new sample rate
        PluginLatencyManager.shared.setSampleRate(newDeviceFormat.sampleRate)
        
        // 4) Reconnect main chain with new format: mixer → masterEQ → masterLimiter → outputNode
        engine.disconnectNodeOutput(mixer)
        engine.disconnectNodeOutput(masterEQ)
        engine.disconnectNodeOutput(masterLimiter)
        engine.connect(mixer, to: masterEQ, format: newFormat)
        engine.connect(masterEQ, to: masterLimiter, format: newFormat)
        engine.connect(masterLimiter, to: engine.outputNode, format: newFormat)
        
        // 5) Update plugin chain formats BEFORE reconnecting tracks
        if let trackNodes = getTrackNodes?() {
            for (_, trackNode) in trackNodes {
                trackNode.pluginChain.updateFormat(newFormat)
            }
        }
        
        // 6) Reconnect all tracks to mixer with new format
        onReconnectAllTracks?()
        
        // 7) Reconnect all buses with new format
        if let project = getCurrentProject?() {
            busManager?.reconnectAllBusesAfterEngineReset(deviceFormat: newFormat)
            busManager?.restoreTrackSendsAfterReset(project: project, deviceFormat: newFormat)
        }
        
        // 8) Re-prime all instruments (reallocate render resources for new format)
        onReprimeInstruments?()
        installedMetronome?.reconnectNodes(dawMixer: mixer)
        installedMetronome?.preparePlayerNode()
        
        // 9) Reconfigure MIDI scheduling for new sample rate
        // CRITICAL: Update sample rate to regenerate timing reference if playing
        midiPlaybackEngine?.setSampleRate(newFormat.sampleRate)
        midiPlaybackEngine?.configureSampleAccurateScheduling(
            avEngine: engine,
            sampleRate: newFormat.sampleRate,
            transportController: transportController
        )
        
        // 10) Start engine
        engine.prepare()
        do {
            try engine.start()
            setGraphReady?(true)
            NotificationCenter.default.post(
                name: .audioDeviceChangeSucceeded,
                object: nil,
                userInfo: ["message": "Audio device changed successfully."]
            )
            // 11) Resume playback if it was playing
            if wasPlaying {
                onSeekToBeat?(savedPosition.beats)
                onPlay?()
            }
        } catch {
            AppLogger.shared.error("[DeviceConfig] Failed to restart engine after device change: \(error)", category: .audio)
            setGraphReady?(true)
            NotificationCenter.default.post(
                name: .audioDeviceChangeFailed,
                object: nil,
                userInfo: ["message": "Could not start audio. Check your audio device in System Settings."]
            )
        }
        transportController?.setupPositionTimer()
    }
    
    // MARK: - Cleanup
}
