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
            
            // 11) Resume playback if it was playing
            if wasPlaying {
                onSeekToBeat?(savedPosition.beats)
                onPlay?()
            }
        } catch {
            AppLogger.shared.error("Failed to restart engine after device change: \(error)", category: .audio)
            setGraphReady?(true)
        }
        transportController?.setupPositionTimer()
    }
}
