//
//  TrackInstrument.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  Represents a virtual instrument attached to a MIDI/Instrument track.
//  Wraps SynthEngine or SamplerEngine and manages its lifecycle.
//

import Foundation
import Combine
import AVFoundation
import Observation

// MARK: - Track Instrument Type

enum TrackInstrumentType: String, Codable, CaseIterable, Identifiable {
    case synth = "Synthesizer"
    case sampler = "Sampler"
    case drumKit = "Drum Kit"
    case audioUnit = "Audio Unit"
    case external = "External MIDI"
    case none = "None"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .synth: return "waveform"
        case .sampler: return "pianokeys"
        case .drumKit: return "drum"
        case .audioUnit: return "puzzlepiece.extension"
        case .external: return "cable.connector"
        case .none: return "speaker.slash"
        }
    }
    
    var description: String {
        switch self {
        case .synth: return "Built-in synthesizer with oscillators, filter, and envelope"
        case .sampler: return "Sample-based instrument using SoundFont"
        case .drumKit: return "Sample-based drum kit with GM-compatible mapping"
        case .audioUnit: return "Audio Unit instrument plugin"
        case .external: return "Route to external MIDI device"
        case .none: return "No instrument assigned"
        }
    }
}

// MARK: - Track Instrument

/// Represents a virtual instrument attached to a track.
/// Manages the lifecycle of the underlying audio engine (synth/sampler).
// PERFORMANCE: Using @Observable for fine-grained SwiftUI updates
@Observable
@MainActor
class TrackInstrument: Identifiable {
    
    // MARK: - Observable Properties
    
    @ObservationIgnored
    let id: UUID
    
    var type: TrackInstrumentType
    var name: String
    var preset: SynthPreset
    var isEnabled: Bool = true
    
    /// The underlying synth engine (nil if type is not .synth)
    @ObservationIgnored
    private(set) var synthEngine: SynthEngine?
    
    /// The underlying sampler engine (nil if type is not .sampler)
    @ObservationIgnored
    private(set) var samplerEngine: SamplerEngine?
    
    /// The underlying Audio Unit instrument host (nil if type is not .audioUnit)
    @ObservationIgnored
    private(set) var audioUnitHost: InstrumentPluginHost?
    
    /// The underlying drum kit engine (nil if type is not .drumKit)
    @ObservationIgnored
    private(set) var drumKitEngine: DrumKitEngine?
    
    /// Plugin descriptor for Audio Unit instruments
    private(set) var pluginDescriptor: PluginDescriptor?
    
    /// Currently loaded GM instrument (for sampler type)
    private(set) var gmInstrument: GMInstrument?
    
    /// Whether the audio engine is currently running
    private(set) var isRunning: Bool = false
    
    /// Activity indicator - true when notes are playing
    private(set) var isActive: Bool = false
    
    /// Currently held notes for this instrument
    @ObservationIgnored
    private var heldNotes: Set<UInt8> = []
    
    /// Reference to the main DAW audio engine (for sampler creation)
    @ObservationIgnored
    private weak var dawAudioEngine: AVAudioEngine?
    
    /// True if sampler setup was deferred because no engine was available
    @ObservationIgnored
    private(set) var pendingSamplerSetup: Bool = false
    
    // MARK: - Initialization
    
    /// Create a track instrument
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - type: Type of instrument (synth, sampler, etc.)
    ///   - name: Display name
    ///   - preset: Synth preset (for synth type)
    ///   - gmInstrument: GM instrument (for sampler type)
    ///   - pluginDescriptor: AU plugin descriptor (for audioUnit type)
    ///   - audioEngine: The main DAW audio engine. REQUIRED for sampler type to ensure
    ///                  the sampler node is attached to the correct engine for plugin routing.
    init(
        id: UUID = UUID(),
        type: TrackInstrumentType = .synth,
        name: String = "TUS Synth",
        preset: SynthPreset = .default,
        gmInstrument: GMInstrument? = nil,
        pluginDescriptor: PluginDescriptor? = nil,
        audioEngine: AVAudioEngine? = nil
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.preset = preset
        self.gmInstrument = gmInstrument
        self.pluginDescriptor = pluginDescriptor
        self.dawAudioEngine = audioEngine  // Store for later use (e.g., instrument switching)
        
        setupInstrument(audioEngine: audioEngine)
    }
    
    // MARK: - Setup
    
    /// Complete sampler setup that was deferred due to missing audio engine
    /// Called by InstrumentManager/AudioEngine when the engine becomes available
    func completeSamplerSetup(with engine: AVAudioEngine) {
        guard pendingSamplerSetup, type == .sampler else { return }
        
        dawAudioEngine = engine
        pendingSamplerSetup = false
        
        // Create sampler attached to the engine
        samplerEngine = SamplerEngine(attachTo: engine, connectToMixer: false)
        
        // Load SoundFont and instrument (check bundled OR downloaded)
        if let soundFontURL = SoundFontManager.shared.anySoundFontURL() {
            do {
                try samplerEngine?.loadSoundFont(at: soundFontURL)
                if let instrument = gmInstrument {
                    try samplerEngine?.loadInstrument(instrument)
                }
            } catch {
                // SoundFont loading failed silently
            }
        }
    }
    
    /// Force sampler creation when the engine becomes available
    /// Use this when an instrument exists but has no sampler (e.g., track created before engine was ready)
    func ensureSamplerExists(with engine: AVAudioEngine) {
        guard type == .sampler, samplerEngine == nil else { return }
        
        dawAudioEngine = engine
        pendingSamplerSetup = false
        
        // Create sampler attached to the engine with deferred attachment
        samplerEngine = SamplerEngine(attachTo: engine, connectToMixer: false, deferAttachment: true)
        
        // Load SoundFont and instrument (check bundled OR downloaded)
        if let soundFontURL = SoundFontManager.shared.anySoundFontURL() {
            do {
                try samplerEngine?.loadSoundFont(at: soundFontURL)
                if let instrument = gmInstrument {
                    try samplerEngine?.loadInstrument(instrument)
                }
                // Attach after loading samples
                samplerEngine?.attachToEngine()
            } catch {
            }
        }
    }
    
    private func setupInstrument(audioEngine: AVAudioEngine?) {
        switch type {
        case .synth:
            synthEngine = SynthEngine()
            synthEngine?.loadPreset(preset)
            
        case .sampler:
            // CRITICAL: Sampler can ONLY be created if we have an audio engine
            // This ensures all samplers are part of the main DAW graph for plugin routing
            guard let engine = audioEngine else {
                // DEFER creation - do not create anything without an engine
                // The sampler will be created later when the engine is available
                // via completeSamplerSetup() or when the instrument is re-initialized
                pendingSamplerSetup = true
                return
            }
            
            // Create sampler with DEFERRED attachment - load samples before attaching
            // This avoids crashes when loading samples on a running engine
            samplerEngine = SamplerEngine(attachTo: engine, connectToMixer: false, deferAttachment: true)
            
            // Load SoundFont and instrument BEFORE attaching to engine
            if let soundFontURL = SoundFontManager.shared.anySoundFontURL() {
                do {
                    try samplerEngine?.loadSoundFont(at: soundFontURL)
                    if let instrument = gmInstrument {
                        try samplerEngine?.loadInstrument(instrument)
                    }
                    
                    // NOW attach to the engine after samples are loaded
                    samplerEngine?.attachToEngine()
                } catch {
                    // SoundFont loading failed silently
                }
            }
            
        case .drumKit:
            // Drum kit requires an audio engine for attachment
            guard let engine = audioEngine else {
                pendingSamplerSetup = true  // Reuse flag for deferred setup
                return
            }
            
            // Create and attach drum kit engine
            drumKitEngine = DrumKitEngine()
            drumKitEngine?.attach(to: engine, connectToMixer: false)
            
        case .audioUnit:
            // Audio Unit setup is async - handled separately via loadAudioUnit()
            break
            
        case .external:
            // External MIDI routing - no local engine needed
            break
            
        case .none:
            break
        }
    }
    
    /// Load an Audio Unit instrument plugin (async)
    /// - Parameters:
    ///   - descriptor: The plugin descriptor for the AU instrument
    ///   - forStandalonePlayback: If true, creates its own engine (synth panel). 
    ///                            If false, prepares for DAW engine integration.
    func loadAudioUnit(_ descriptor: PluginDescriptor, forStandalonePlayback: Bool = false) async throws {
        guard descriptor.category == .instrument else {
            throw PluginError.instantiationFailed
        }
        
        // Clean up any existing AU host
        audioUnitHost?.unload()
        audioUnitHost = nil
        
        // Create and load new host
        let host = InstrumentPluginHost(descriptor: descriptor)
        try await host.load(forStandalonePlayback: forStandalonePlayback)
        
        self.audioUnitHost = host
        self.pluginDescriptor = descriptor
        self.type = .audioUnit
        self.name = descriptor.name
        self.isRunning = true
    }
    
    /// Get the Audio Unit's AVAudioUnit node for audio graph connection
    var audioUnitNode: AVAudioUnit? {
        return audioUnitHost?.audioNode
    }
    
    // MARK: - Lifecycle
    
    /// Start the audio engine
    func start() throws {
        switch type {
        case .synth:
            guard let engine = synthEngine else { return }
            try engine.start()
            if !isRunning { isRunning = true }
            
        case .sampler:
            guard let engine = samplerEngine else { return }
            try engine.start()
            if !isRunning { isRunning = true }
            
        case .drumKit:
            // Drum kit is always "running" once attached
            let shouldBeRunning = drumKitEngine?.isReady ?? false
            if isRunning != shouldBeRunning { isRunning = shouldBeRunning }
            
        case .audioUnit:
            // AU instruments are always "running" once loaded
            let shouldBeRunning = audioUnitHost?.isLoaded ?? false
            if isRunning != shouldBeRunning { isRunning = shouldBeRunning }
            
        case .external, .none:
            break
        }
    }
    
    /// Stop the audio engine
    func stop() {
        synthEngine?.stop()
        samplerEngine?.stop()
        audioUnitHost?.allNotesOff()
        if isRunning { isRunning = false }
        heldNotes.removeAll()
        if isActive { isActive = false }
    }
    
    /// Mark the instrument as running (used when connected to DAW engine externally)
    func markAsRunning() {
        if !isRunning { isRunning = true }
    }
    
    /// Ensure the instrument is ready to play
    func ensureRunning() {
        guard !isRunning else { return }
        do {
            try start()
        } catch {
        }
    }
    
    // MARK: - Note Control
    
    /// Trigger a note on
    func noteOn(pitch: UInt8, velocity: UInt8) {
        guard isEnabled else { return }
        
        ensureRunning()
        
        switch type {
        case .synth:
            synthEngine?.noteOn(pitch: pitch, velocity: velocity)
            
        case .sampler:
            samplerEngine?.noteOn(pitch: pitch, velocity: velocity)
            
        case .drumKit:
            drumKitEngine?.noteOn(pitch: pitch, velocity: velocity)
            
        case .audioUnit:
            audioUnitHost?.noteOn(pitch: pitch, velocity: velocity)
            
        case .external:
            // Future: Send MIDI to external device
            break
            
        case .none:
            break
        }
        
        heldNotes.insert(pitch)
        // Only update observable property if value changed (avoids SwiftUI re-renders)
        if !isActive {
            isActive = true
        }
    }
    
    /// Trigger a note off
    func noteOff(pitch: UInt8) {
        switch type {
        case .synth:
            synthEngine?.noteOff(pitch: pitch)
            
        case .sampler:
            samplerEngine?.noteOff(pitch: pitch)
            
        case .drumKit:
            drumKitEngine?.noteOff(pitch: pitch)
            
        case .audioUnit:
            audioUnitHost?.noteOff(pitch: pitch)
            
        case .external:
            // Future: Send MIDI to external device
            break
            
        case .none:
            break
        }
        
        heldNotes.remove(pitch)
        // Only update observable property if value changed (avoids SwiftUI re-renders)
        let shouldBeActive = !heldNotes.isEmpty
        if isActive != shouldBeActive {
            isActive = shouldBeActive
        }
    }
    
    /// Stop all notes immediately
    func allNotesOff() {
        synthEngine?.allNotesOff()
        samplerEngine?.allNotesOff()
        audioUnitHost?.allNotesOff()
        heldNotes.removeAll()
        if isActive { isActive = false }
    }
    
    /// Send pitch bend to the instrument
    /// - Parameter value: 14-bit pitch bend value (0-16383, center = 8192)
    func pitchBend(value: UInt16) {
        switch type {
        case .synth:
            // SynthEngine currently doesn't support pitch bend
            // TODO: Add pitch bend support to SynthEngine
            break
        case .sampler:
            samplerEngine?.pitchBend(value: value)
        case .drumKit:
            // Drum kits don't respond to pitch bend
            break
        case .audioUnit:
            audioUnitHost?.pitchBend(value: value)
        case .external, .none:
            // External MIDI and None don't have internal instruments
            break
        }
    }
    
    /// Send control change to the instrument
    /// - Parameters:
    ///   - controller: CC number (0-127)
    ///   - value: CC value (0-127)
    func controlChange(controller: UInt8, value: UInt8) {
        switch type {
        case .synth:
            // SynthEngine currently doesn't support CC
            // TODO: Add CC support to SynthEngine (filter cutoff, etc.)
            break
        case .sampler:
            samplerEngine?.controlChange(controller: controller, value: value)
        case .drumKit:
            // Drum kits don't respond to CC
            break
        case .audioUnit:
            audioUnitHost?.controlChange(controller: controller, value: value)
        case .external, .none:
            // External MIDI and None don't have internal instruments
            break
        }
    }
    
    // MARK: - Sample-Accurate MIDI (Professional Timing)
    
    /// Send raw MIDI data with sample-accurate timing
    /// - Parameters:
    ///   - status: MIDI status byte (e.g., 0x90 for note on, 0x80 for note off)
    ///   - data1: First data byte (e.g., pitch)
    ///   - data2: Second data byte (e.g., velocity)
    ///   - sampleTime: Sample time for the event (AUEventSampleTimeImmediate for now)
    func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8, atSampleTime sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        guard isEnabled else { return }
        
        ensureRunning()
        
        switch type {
        case .synth:
            // SynthEngine doesn't support sample-accurate MIDI yet, use immediate methods
            let statusNibble = status & 0xF0
            if statusNibble == 0x90 && data2 > 0 {
                synthEngine?.noteOn(pitch: data1, velocity: data2)
            } else if statusNibble == 0x80 || (statusNibble == 0x90 && data2 == 0) {
                synthEngine?.noteOff(pitch: data1)
            }
            
        case .sampler:
            samplerEngine?.sendMIDI(status: status, data1: data1, data2: data2, atSampleTime: sampleTime)
            
        case .drumKit:
            // DrumKitEngine uses immediate playback, route note on/off
            let statusNibble = status & 0xF0
            if statusNibble == 0x90 && data2 > 0 {
                drumKitEngine?.noteOn(pitch: data1, velocity: data2)
            } else if statusNibble == 0x80 || (statusNibble == 0x90 && data2 == 0) {
                drumKitEngine?.noteOff(pitch: data1)
            }
            
        case .audioUnit:
            audioUnitHost?.sendMIDI(status: status, data1: data1, data2: data2, atSampleTime: sampleTime)
            
        case .external:
            // Future: Send MIDI to external device with timing
            break
            
        case .none:
            break
        }
        
        // Track active notes
        let statusNibble = status & 0xF0
        if statusNibble == 0x90 && data2 > 0 {
            heldNotes.insert(data1)
            if !isActive { isActive = true }
        } else if statusNibble == 0x80 || (statusNibble == 0x90 && data2 == 0) {
            heldNotes.remove(data1)
            if heldNotes.isEmpty && isActive { isActive = false }
        }
    }
    
    /// Get the AUScheduleMIDIEventBlock for direct MIDI dispatch
    /// This block is thread-safe and can be called from any thread
    /// Returns nil if the instrument doesn't support sample-accurate MIDI
    func getMIDIBlock() -> AUScheduleMIDIEventBlock? {
        switch type {
        case .sampler:
            return samplerEngine?.midiEventBlock
        case .audioUnit:
            return audioUnitHost?.midiEventBlock
        default:
            // Synth, DrumKit, External don't support sample-accurate MIDI
            return nil
        }
    }
    
    /// Panic - stop all sounds immediately
    func panic() {
        synthEngine?.panic()
        samplerEngine?.allNotesOff()
        audioUnitHost?.panic()
        heldNotes.removeAll()
        if isActive { isActive = false }
    }
    
    // MARK: - Preset Management
    
    /// Load a synth preset into the instrument
    func loadPreset(_ newPreset: SynthPreset) {
        self.preset = newPreset
        synthEngine?.loadPreset(newPreset)
    }
    
    /// Replace the sampler engine with a new one (for live graph repair)
    /// Called by AudioEngine when inserting plugins to ensure clean sampler state
    func replaceSamplerEngine(_ newSamplerEngine: SamplerEngine) {
        guard type == .sampler else { return }
        samplerEngine = newSamplerEngine
    }
    
    /// Load a GM instrument into the sampler
    func loadGMInstrument(_ instrument: GMInstrument) {
        guard type == .sampler else { return }
        
        // If switching instruments, completely recreate the sampler engine
        // AVAudioUnitSampler doesn't reliably switch programs otherwise
        if let currentGM = gmInstrument, currentGM != instrument {
            // Stop and destroy old sampler
            samplerEngine?.stop()
            samplerEngine = nil
            
            // Create new sampler engine - MUST have stored DAW engine
            guard let engine = dawAudioEngine else {
                return
            }
            samplerEngine = SamplerEngine(attachTo: engine, connectToMixer: false)
            
            // Load SoundFont and instrument
            if let soundFontURL = SoundFontManager.shared.anySoundFontURL() {
                do {
                    try samplerEngine?.loadSoundFont(at: soundFontURL)
                    try samplerEngine?.loadInstrument(instrument)
                    self.gmInstrument = instrument
                    self.name = instrument.name
                } catch {
                    // Sampler recreation failed silently
                }
            }
            return
        }
        
        // First time loading - just load the instrument
        guard let engine = samplerEngine else { return }
        
        do {
            try engine.loadInstrument(instrument)
            self.gmInstrument = instrument
            self.name = instrument.name
        } catch {
            // GM instrument loading failed silently
        }
    }
    
    /// Reset the sampler's DSP state after graph modifications.
    /// This is a lightweight operation that clears render buffers without
    /// reloading the entire SoundFont.
    ///
    /// ARCHITECTURE NOTE: This replaces the previous reloadCurrentInstrument()
    /// which was expensive. The root cause of sampler corruption after engine.reset()
    /// is stale render buffers, not the instrument data itself.
    func reloadCurrentInstrument() {
        guard type == .sampler, let engine = samplerEngine else {
            return
        }
        
        // Use lightweight DSP reset instead of reloading entire SoundFont
        engine.resetDSPState()
    }
    
    /// 🔥 FIX 1: Full render resource reset for sampler
    /// Use this when plugin chain topology changes (insert/remove plugin).
    /// Unlike `reloadCurrentInstrument()`, this deallocates render resources
    /// and reloads the instrument, guaranteeing no stale sample rate state.
    func fullRenderReset() {
        guard type == .sampler, let engine = samplerEngine else {
            return
        }
        
        engine.fullRenderReset()
    }
    
    /// Reload the actual SoundFont instrument (expensive operation).
    /// Only use this when the instrument actually needs to change.
    func forceReloadInstrument() {
        guard type == .sampler, let instrument = gmInstrument, let engine = samplerEngine else {
            return
        }
        
        do {
            try engine.loadInstrument(instrument)
        } catch {
            AppLogger.shared.warning("Failed to reload instrument: \(error.localizedDescription)")
        }
    }
    
    /// Change the instrument type
    /// Note: When changing to sampler type, this will use standalone mode (deprecated)
    /// For proper plugin routing, create a new TrackInstrument with audioEngine parameter
    func changeType(to newType: TrackInstrumentType, audioEngine: AVAudioEngine? = nil) {
        guard newType != type else { return }
        
        // Stop and cleanup current engines
        stop()
        synthEngine = nil
        samplerEngine = nil
        audioUnitHost?.unload()
        audioUnitHost = nil
        pluginDescriptor = nil
        
        // Update stored engine if new one provided
        if let engine = audioEngine {
            dawAudioEngine = engine
        }
        
        // Update type and setup new engine (use stored engine if parameter is nil)
        type = newType
        setupInstrument(audioEngine: audioEngine ?? dawAudioEngine)
    }
    
    // MARK: - Parameter Control
    
    func setVolume(_ volume: Float) {
        synthEngine?.setMasterVolume(volume)
        samplerEngine?.setVolume(volume)
    }
    
    func setFilterCutoff(_ cutoff: Float) {
        synthEngine?.setFilterCutoff(cutoff)
    }
    
    func setFilterResonance(_ resonance: Float) {
        synthEngine?.setFilterResonance(resonance)
    }
    
    func setAttack(_ attack: Float) {
        synthEngine?.setAttack(attack)
    }
    
    func setDecay(_ decay: Float) {
        synthEngine?.setDecay(decay)
    }
    
    func setSustain(_ sustain: Float) {
        synthEngine?.setSustain(sustain)
    }
    
    func setRelease(_ release: Float) {
        synthEngine?.setRelease(release)
    }
}

// MARK: - TrackInstrument Extension for Track Integration

extension TrackInstrument {
    
    /// Create an instrument appropriate for a track type
    static func create(for trackType: TrackType, name: String? = nil) -> TrackInstrument? {
        switch trackType {
        case .midi, .instrument:
            return TrackInstrument(
                type: .synth,
                name: name ?? "TUS Synth"
            )
        case .audio, .bus:
            // Audio tracks don't have instruments
            return nil
        }
    }
    
    /// Create a sampler instrument with a specific GM instrument
    static func createSampler(name: String, gmInstrument: GMInstrument) -> TrackInstrument {
        return TrackInstrument(
            type: .sampler,
            name: name,
            gmInstrument: gmInstrument
        )
    }
    
    /// Create an Audio Unit instrument (async loading required)
    static func createAudioUnit(name: String, descriptor: PluginDescriptor) -> TrackInstrument {
        return TrackInstrument(
            type: .audioUnit,
            name: name,
            pluginDescriptor: descriptor
        )
    }
    
    /// Whether this instrument uses a SoundFont sampler
    var isSampler: Bool {
        type == .sampler
    }
    
    /// Whether this instrument uses the built-in synthesizer
    var isSynth: Bool {
        type == .synth
    }
    
    /// Whether this instrument uses an Audio Unit plugin
    var isAudioUnit: Bool {
        type == .audioUnit
    }
}

