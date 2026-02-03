//
//  InstrumentManager.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  Centralized service for managing and routing MIDI to track instruments.
//  Routes Virtual Keyboard, Piano Roll, and external MIDI devices to the
//  correct track's instrument based on selection.
//

import Foundation
import Combine
import SwiftUI
import AVFoundation

// MARK: - InstrumentManagerProtocol

/// Protocol for InstrumentManager to enable dependency injection and testing
@MainActor
protocol InstrumentManagerProtocol: AnyObject {
    var selectedTrackId: UUID? { get set }
    var activeInstrument: TrackInstrument? { get }
    
    func getInstrument(for trackId: UUID) -> TrackInstrument?
    func getOrCreateInstrument(for trackId: UUID) -> TrackInstrument?
    func getOrCreateInstrument(for track: AudioTrack) -> TrackInstrument?
    func registerInstrument(_ instrument: TrackInstrument, for trackId: UUID)
    func unregisterInstrument(for trackId: UUID)
    func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8, forTrack trackId: UUID, atSampleTime sampleTime: AUEventSampleTime)
    func allNotesOffAllTracks()
    func configure(with projectManager: ProjectManager, audioEngine: AudioEngine)
}

// MARK: - InstrumentManager

/// Centralized service for routing MIDI events to track instruments.
/// All MIDI input (keyboard, controllers, virtual keyboard) routes through here.
@MainActor
@Observable
class InstrumentManager: InstrumentManagerProtocol {
    
    // MARK: - Singleton
    
    /// Shared instance for production use
    /// Use dependency injection for testing by passing InstrumentManager instances directly
    static let shared = InstrumentManager()
    
    // MARK: - Public Initializer for Dependency Injection
    
    /// Public initializer enables creating instances for testing
    /// In production, use `InstrumentManager.shared` for convenience
    init() {}
    
    // MARK: - Properties
    
    /// Currently active instrument (receiving MIDI input)
    private(set) var activeInstrument: TrackInstrument?
    
    /// Currently selected track ID
    var selectedTrackId: UUID? {
        didSet {
            updateActiveInstrument()
        }
    }
    
    /// All track instruments keyed by track ID
    private var instruments: [UUID: TrackInstrument] = [:]
    
    /// Notes currently held (for sustain pedal support)
    private var heldNotes: Set<UInt8> = []
    
    /// Sustain pedal state
    var isSustainActive: Bool = false {
        didSet {
            if !isSustainActive {
                // Release any sustained notes
                releaseSustainedNotes()
            }
        }
    }
    
    /// Notes sustained by pedal (need to release when sustain is lifted)
    private var sustainedNotes: Set<UInt8> = []
    
    /// Reference to project manager for track lookups
    /// Using @ObservationIgnored because weak references don't work well with @Observable macro
    @ObservationIgnored
    weak var projectManager: ProjectManager?
    
    /// Reference to audio engine for creating properly-attached samplers and playhead position
    /// CRITICAL: All samplers must be attached to the main DAW engine to avoid cross-engine crashes
    @ObservationIgnored
    weak var audioEngine: AudioEngine?
    
    // MARK: - MIDI Recording State
    
    /// Whether we're currently recording MIDI
    private(set) var isRecording = false
    
    /// The track we're recording to
    private(set) var recordingTrackId: UUID?
    
    /// Notes recorded during the current take
    private var recordedNotes: [MIDINote] = []
    
    /// Active notes (note on received, waiting for note off)
    /// Key: pitch, Value: (startBeat, velocity)
    private var activeRecordingNotes: [UInt8: (startBeat: Double, velocity: UInt8)] = [:]
    
    /// Playhead position when recording started
    private var recordingStartBeat: Double = 0
    
    /// Recording region counter for naming
    private var recordingCounter: Int = 1
    
    // MARK: - Computed Properties
    
    /// Whether we have an active instrument ready to receive MIDI
    var hasActiveInstrument: Bool {
        activeInstrument != nil
    }
    
    /// Name of the active track for display
    var activeTrackName: String? {
        guard let trackId = selectedTrackId,
              let project = projectManager?.currentProject,
              let track = project.tracks.first(where: { $0.id == trackId }) else {
            return nil
        }
        return track.name
    }
    
    /// Color of the active track for display
    var activeTrackColor: Color? {
        guard let trackId = selectedTrackId,
              let project = projectManager?.currentProject,
              let track = project.tracks.first(where: { $0.id == trackId }) else {
            return nil
        }
        return track.color.color
    }
    
    /// Whether the active instrument is currently producing sound
    var isActive: Bool {
        activeInstrument?.isActive ?? false
    }
    
    // MARK: - External Instrument Registration
    
    /// Register an instrument that was loaded externally (e.g., by AudioEngine via mixer)
    /// This allows the Virtual Keyboard to route MIDI to instruments loaded by the mixer
    func registerInstrument(_ instrument: TrackInstrument, for trackId: UUID) {
        instruments[trackId] = instrument
        
        // Update active instrument if this is the selected track
        if selectedTrackId == trackId {
            activeInstrument = instrument
        }
        
    }
    
    /// Unregister an instrument when it's removed
    func unregisterInstrument(for trackId: UUID) {
        instruments.removeValue(forKey: trackId)
        
        if selectedTrackId == trackId {
            activeInstrument = nil
        }
    }
    
    // MARK: - Instrument Management
    
    /// Get or create an instrument for a track
    /// Restores the saved voicePreset (either SynthPreset, GM instrument, or Audio Unit)
    func getOrCreateInstrument(for trackId: UUID) -> TrackInstrument? {
        // Return existing instrument
        if let instrument = instruments[trackId] {
            return instrument
        }
        
        // Check if this is a MIDI/instrument track
        guard let project = projectManager?.currentProject,
              let track = project.tracks.first(where: { $0.id == trackId }),
              track.trackType == .midi || track.trackType == .instrument else {
            return nil
        }
        
        // Delegate to track-based overload
        return getOrCreateInstrument(for: track)
    }
    
    /// Get or create an instrument for a track (direct track version - use when projectManager may not be set)
    /// This is the preferred method during project load when projectManager might not be ready
    ///
    /// Priority order for instrument type detection:
    /// 1. drumKitId (numeric) - Drum kit
    /// 2. gmProgram (numeric) - GM SoundFont sampler
    /// 3. voicePreset string matching (legacy fallback)
    /// 4. Default synth
    func getOrCreateInstrument(for track: AudioTrack) -> TrackInstrument? {
        // Return existing instrument
        if let instrument = instruments[track.id] {
            return instrument
        }
        
        // Check if this is a MIDI/instrument track
        guard track.trackType == .midi || track.trackType == .instrument else {
            return nil
        }
        
        // PRIORITY 1: Check drumKitId (numeric/string identifier)
        if let drumKitId = track.drumKitId {
            let instrument = TrackInstrument(
                type: .drumKit,
                name: "\(track.name) Drums",
                preset: .default,
                audioEngine: audioEngine?.audioEngineRef
            )
            instrument.setVolume(track.mixerSettings.volume)
            instrument.isEnabled = !track.mixerSettings.isMuted
            instruments[track.id] = instrument
            return instrument
        }
        
        // PRIORITY 2: Check gmProgram (numeric program number 0-127)
        if let gmProgram = track.gmProgram,
           let gmInstrument = GMInstrument(rawValue: gmProgram) {
            let instrument = TrackInstrument(
                type: .sampler,
                name: "\(track.name) Sampler",
                preset: .default,
                gmInstrument: gmInstrument,
                audioEngine: audioEngine?.audioEngineRef
            )
            instrument.setVolume(track.mixerSettings.volume)
            instrument.isEnabled = !track.mixerSettings.isMuted
            instrument.samplerEngine?.setPan(track.mixerSettings.pan)
            instruments[track.id] = instrument
            // Reduced logging: per-track instrument creation is noisy
            return instrument
        }
        
        // PRIORITY 3: Check synthPresetId (numeric preset index)
        if let synthPresetId = track.synthPresetId,
           synthPresetId >= 0 && synthPresetId < SynthPreset.allPresets.count {
            let preset = SynthPreset.allPresets[synthPresetId]
            let instrument = TrackInstrument(
                type: .synth,
                name: "\(track.name) Synth",
                preset: preset
            )
            instrument.setVolume(track.mixerSettings.volume)
            instrument.isEnabled = !track.mixerSettings.isMuted
            instruments[track.id] = instrument
            return instrument
        }
        
        // LEGACY FALLBACK: Check voicePreset string (for backward compatibility)
        
        // Check if the saved voicePreset is an Audio Unit
        if let voicePresetName = track.voicePreset,
           InstrumentManager.isAudioUnitPreset(voicePresetName) {
            let instrument = TrackInstrument(
                type: .synth,
                name: "\(track.name) Synth",
                preset: .default
            )
            instrument.setVolume(track.mixerSettings.volume)
            instrument.isEnabled = !track.mixerSettings.isMuted
            instruments[track.id] = instrument
            return instrument
        }
        
        // Check if the saved voicePreset is a Drum Kit (legacy string match)
        if let voicePresetName = track.voicePreset,
           InstrumentManager.isDrumKitPreset(voicePresetName) {
            let instrument = TrackInstrument(
                type: .drumKit,
                name: "\(track.name) Drums",
                preset: .default,
                audioEngine: audioEngine?.audioEngineRef
            )
            instrument.setVolume(track.mixerSettings.volume)
            instrument.isEnabled = !track.mixerSettings.isMuted
            instruments[track.id] = instrument
            return instrument
        }
        
        // Check if the saved voicePreset is a GM instrument (legacy string match)
        if let voicePresetName = track.voicePreset,
           let gmInstrument = GMInstrument.allCases.first(where: { $0.name == voicePresetName }) {
            let instrument = TrackInstrument(
                type: .sampler,
                name: "\(track.name) Sampler",
                preset: .default,
                gmInstrument: gmInstrument,
                audioEngine: audioEngine?.audioEngineRef
            )
            instrument.setVolume(track.mixerSettings.volume)
            instrument.isEnabled = !track.mixerSettings.isMuted
            instrument.samplerEngine?.setPan(track.mixerSettings.pan)
            instruments[track.id] = instrument
            return instrument
        }
        
        // Check if the saved voicePreset is a SynthPreset (legacy string match)
        let preset: SynthPreset
        if let voicePresetName = track.voicePreset,
           let trackPreset = SynthPreset.preset(named: voicePresetName) {
            preset = trackPreset
        } else {
            preset = .default
        }
        
        // DEFAULT: Create synth instrument with the selected preset
        let instrument = TrackInstrument(
            type: .synth,
            name: "\(track.name) Synth",
            preset: preset
        )
        
        // Apply mixer settings (volume, mute) from track
        instrument.setVolume(track.mixerSettings.volume)
        instrument.isEnabled = !track.mixerSettings.isMuted
        
        instruments[track.id] = instrument
        
        return instrument
    }
    
    /// Get instrument for a track (if it exists)
    func getInstrument(for trackId: UUID) -> TrackInstrument? {
        return instruments[trackId]
    }
    
    /// Remove instrument for a track
    func removeInstrument(for trackId: UUID) {
        if let instrument = instruments[trackId] {
            instrument.stop()
            instruments.removeValue(forKey: trackId)
            
            // Clear active if this was the active instrument
            if activeInstrument?.id == instrument.id {
                activeInstrument = nil
            }
            
        }
    }
    
    /// Update the active instrument based on selected track
    private func updateActiveInstrument() {
        // Release any held notes on previous instrument
        activeInstrument?.allNotesOff()
        heldNotes.removeAll()
        sustainedNotes.removeAll()
        
        guard let trackId = selectedTrackId else {
            activeInstrument = nil
            return
        }
        
        // Get or create instrument for the selected track
        if let instrument = getOrCreateInstrument(for: trackId) {
            activeInstrument = instrument
        } else {
            activeInstrument = nil
        }
    }
    
    // MARK: - MIDI Event Routing
    
    /// Route a note on event to the active instrument
    func noteOn(pitch: UInt8, velocity: UInt8) {
        guard let instrument = activeInstrument else {
            return
        }
        
        // Play the note through the instrument
        instrument.noteOn(pitch: pitch, velocity: velocity)
        heldNotes.insert(pitch)
        
        // Record the note if recording is active (use beats for MIDI timing)
        if isRecording {
            let timeInBeats = currentPlayheadBeats
            activeRecordingNotes[pitch] = (startBeat: timeInBeats, velocity: velocity)
        }
    }
    
    /// Route a note off event to the active instrument
    func noteOff(pitch: UInt8) {
        guard let instrument = activeInstrument else { return }
        
        heldNotes.remove(pitch)
        
        if isSustainActive {
            // Don't send note off - just track it for later
            sustainedNotes.insert(pitch)
        } else {
            instrument.noteOff(pitch: pitch)
        }
        
        // Record the note if recording is active (use beats for MIDI timing)
        if isRecording, let noteInfo = activeRecordingNotes[pitch] {
            let durationInBeats = currentPlayheadBeats - noteInfo.startBeat
            let note = MIDINote(
                pitch: pitch,
                velocity: noteInfo.velocity,
                startBeat: noteInfo.startBeat - recordingStartBeat,
                durationBeats: max(0.1, durationInBeats),
                channel: 0
            )
            recordedNotes.append(note)
            activeRecordingNotes.removeValue(forKey: pitch)
        }
    }
    
    // MARK: - Multi-Track MIDI Playback (for playback engine - doesn't affect selected track)
    
    /// Route a note on event directly to a specific track's instrument
    /// Used by MIDIPlaybackEngine for multi-track playback without switching selection
    /// PERFORMANCE: Uses direct dictionary lookup instead of getOrCreateInstrument
    /// since instruments should already exist during playback
    func noteOn(pitch: UInt8, velocity: UInt8, forTrack trackId: UUID) {
        guard let instrument = instruments[trackId] else { return }
        
        // Play the note through the track's instrument (no recording, no held notes tracking)
        instrument.noteOn(pitch: pitch, velocity: velocity)
    }
    
    /// Route a note off event directly to a specific track's instrument
    /// Used by MIDIPlaybackEngine for multi-track playback without switching selection
    func noteOff(pitch: UInt8, forTrack trackId: UUID) {
        guard let instrument = instruments[trackId] else { return }
        
        // Send note off to the track's instrument (no sustain handling for playback)
        instrument.noteOff(pitch: pitch)
    }
    
    /// Send pitch bend to a specific track's instrument (used by MIDIPlaybackEngine)
    /// - Parameters:
    ///   - value: Pitch bend value -8192 to +8191 (0 = center)
    ///   - trackId: The track whose instrument should receive the pitch bend
    func pitchBend(value: Int16, forTrack trackId: UUID) {
        guard let instrument = instruments[trackId] else { return }
        
        // Convert from signed -8192...+8191 to unsigned 0...16383 (center = 8192)
        let midiValue = UInt16(clamping: Int(value) + 8192)
        instrument.pitchBend(value: midiValue)
    }
    
    /// Send control change to a specific track's instrument (used by MIDIPlaybackEngine)
    /// - Parameters:
    ///   - controller: CC number (0-127)
    ///   - value: CC value (0-127)
    ///   - trackId: The track whose instrument should receive the CC
    func controlChange(controller: UInt8, value: UInt8, forTrack trackId: UUID) {
        guard let instrument = instruments[trackId] else { return }
        instrument.controlChange(controller: controller, value: value)
    }
    
    // MARK: - Sample-Accurate MIDI (Professional Timing)
    
    /// Send raw MIDI data with sample-accurate timing to a specific track's instrument
    /// Used by SampleAccurateMIDIScheduler for sub-millisecond precision
    /// - Parameters:
    ///   - status: MIDI status byte (e.g., 0x90 for note on, 0x80 for note off)
    ///   - data1: First data byte (e.g., pitch)
    ///   - data2: Second data byte (e.g., velocity)
    ///   - trackId: The track whose instrument should receive the MIDI
    ///   - sampleTime: Sample time for the event (AUEventSampleTimeImmediate for now)
    func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8, forTrack trackId: UUID, atSampleTime sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        guard let instrument = instruments[trackId] else { return }
        instrument.sendMIDI(status: status, data1: data1, data2: data2, atSampleTime: sampleTime)
    }
    
    /// Stop all notes on the active instrument
    func allNotesOff() {
        activeInstrument?.allNotesOff()
        heldNotes.removeAll()
        sustainedNotes.removeAll()
    }
    
    /// Stop all notes on ALL track instruments (safety measure for stopping playback)
    func allNotesOffAllTracks() {
        for (_, instrument) in instruments {
            instrument.allNotesOff()
        }
        heldNotes.removeAll()
        sustainedNotes.removeAll()
    }
    
    /// Panic - stop all sounds immediately
    func panic() {
        activeInstrument?.panic()
        heldNotes.removeAll()
        sustainedNotes.removeAll()
        isSustainActive = false
    }
    
    /// Release notes that were sustained by the pedal
    private func releaseSustainedNotes() {
        guard let instrument = activeInstrument else { return }
        
        for pitch in sustainedNotes {
            if !heldNotes.contains(pitch) {
                instrument.noteOff(pitch: pitch)
            }
        }
        sustainedNotes.removeAll()
    }
    
    // MARK: - Control Change Routing
    
    /// Route a control change event
    func controlChange(controller: UInt8, value: UInt8) {
        // Handle sustain pedal (CC64)
        if controller == 64 {
            isSustainActive = value >= 64
        }
        
        // Future: Route other CC to instrument/track parameters
    }
    
    /// Route pitch bend event
    func pitchBend(value: Int16) {
        // Future: Route to active instrument
    }
    
    /// Route mod wheel event
    func modWheel(value: UInt8) {
        // Future: Route to active instrument
    }
    
    // MARK: - MIDI Recording
    
    /// Get current playhead position in beats (source of truth; use this for MIDI recording and UI)
    var currentPlayheadBeats: Double {
        audioEngine?.currentPosition.beats ?? 0
    }
    
    /// Check if the selected track is a MIDI track
    var selectedTrackIsMIDI: Bool {
        guard let trackId = selectedTrackId,
              let project = projectManager?.currentProject,
              let track = project.tracks.first(where: { $0.id == trackId }) else {
            return false
        }
        return track.isMIDITrack
    }
    
    /// Start recording MIDI to the selected track
    /// - Parameters:
    ///   - trackId: The track to record to
    ///   - positionBeats: The playhead position in beats when recording starts
    func startRecording(trackId: UUID, atBeats positionBeats: Double) {
        guard let project = projectManager?.currentProject,
              let track = project.tracks.first(where: { $0.id == trackId }),
              track.isMIDITrack else {
            return
        }
        
        isRecording = true
        recordingTrackId = trackId
        recordingStartBeat = positionBeats
        recordedNotes = []
        activeRecordingNotes = [:]
        
    }
    
    /// Stop recording and return the captured MIDI region
    /// - Returns: The recorded MIDI region, or nil if no notes were captured
    func stopRecording() -> MIDIRegion? {
        guard isRecording else { return nil }
        
        let wasRecordingTrackId = recordingTrackId
        isRecording = false
        
        // Close any still-active notes (held when recording stopped) - use beats
        let stopTimeBeats = currentPlayheadBeats
        for (pitch, noteInfo) in activeRecordingNotes {
            let durationInBeats = stopTimeBeats - noteInfo.startBeat
            let note = MIDINote(
                pitch: pitch,
                velocity: noteInfo.velocity,
                startBeat: noteInfo.startBeat - recordingStartBeat,
                durationBeats: max(0.1, durationInBeats),
                channel: 0
            )
            recordedNotes.append(note)
        }
        activeRecordingNotes = [:]
        
        guard !recordedNotes.isEmpty else {
            recordingTrackId = nil
            return nil
        }
        
        // Calculate region duration from captured notes (in beats)
        let regionDuration = recordedNotes.map { $0.endBeat }.max() ?? 4.0
        
        // Get track color and name for the region
        var trackColor: Color = .purple // Default purple
        var trackName: String = "MIDI Recording \(recordingCounter)"
        if let trackId = wasRecordingTrackId,
           let project = projectManager?.currentProject,
           let track = project.tracks.first(where: { $0.id == trackId }) {
            trackColor = track.color.color
            trackName = track.name  // Use track name instead of generic "MIDI Recording"
        }
        
        // Create the MIDI region (all times in beats)
        let region = MIDIRegion(
            id: UUID(),
            name: trackName,
            notes: recordedNotes,
            startBeat: recordingStartBeat,
            durationBeats: regionDuration,
            instrumentId: nil,
            color: trackColor,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: []
        )
        
        recordingCounter += 1
        recordingTrackId = nil
        
        return region
    }
    
    /// Cancel the current recording without saving
    func cancelRecording() {
        isRecording = false
        recordingTrackId = nil
        recordedNotes = []
        activeRecordingNotes = [:]
    }
    
    // MARK: - Preset Management
    
    /// Load a preset into the active instrument
    func loadPreset(_ preset: SynthPreset) {
        activeInstrument?.loadPreset(preset)
    }
    
    /// Get the current preset from the active instrument
    var currentPreset: SynthPreset? {
        activeInstrument?.preset
    }
    
    // MARK: - Volume/Pan Control for Mixer Integration
    
    /// Set volume for a specific track's instrument (called by AudioEngine when mixer faders change)
    func setVolume(_ volume: Float, forTrack trackId: UUID) {
        guard let instrument = instruments[trackId] else { return }
        instrument.setVolume(volume)
    }
    
    /// Set pan for a specific track's instrument (called by AudioEngine when mixer pans change)
    func setPan(_ pan: Float, forTrack trackId: UUID) {
        guard let instrument = instruments[trackId] else { return }
        // Note: TrackInstrument doesn't have pan yet, but SamplerEngine does
        instrument.samplerEngine?.setPan(pan)
        // SynthEngine doesn't have pan, would need to add it
    }
    
    /// Set muted state for a specific track's instrument
    func setMuted(_ muted: Bool, forTrack trackId: UUID) {
        guard let instrument = instruments[trackId] else { return }
        // Mute by setting volume to 0, unmute by restoring
        // For now, just disable the instrument
        instrument.isEnabled = !muted
        if muted {
            instrument.allNotesOff()
        }
    }
    
    // MARK: - Audio Unit Instrument Management
    
    /// Load an Audio Unit instrument for a track
    /// - Parameters:
    ///   - descriptor: The plugin descriptor for the AU instrument
    ///   - trackId: The track to assign the instrument to
    /// - Returns: The created TrackInstrument
    func loadAudioUnitInstrument(_ descriptor: PluginDescriptor, forTrack trackId: UUID) async throws -> TrackInstrument {
        guard descriptor.category == .instrument else {
            throw PluginError.instantiationFailed
        }
        
        // Remove existing instrument for this track
        removeInstrument(for: trackId)
        
        // Create the AU-based instrument
        let instrument = TrackInstrument.createAudioUnit(
            name: descriptor.name,
            descriptor: descriptor
        )
        
        // Load the AU (async)
        try await instrument.loadAudioUnit(descriptor)
        
        // Store in our map
        instruments[trackId] = instrument
        
        // Update active if this is the selected track
        if selectedTrackId == trackId {
            activeInstrument = instrument
        }
        
        // Update the track's voicePreset to store the AU identifier
        if let project = projectManager?.currentProject,
           let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            // Store AU identifier as "AU:name:manufacturer"
            let auIdentifier = "AU:\(descriptor.name):\(descriptor.manufacturer)"
            projectManager?.currentProject?.tracks[trackIndex].voicePreset = auIdentifier
        }
        
        return instrument
    }
    
    /// Check if a voicePreset string represents an Audio Unit
    static func isAudioUnitPreset(_ preset: String?) -> Bool {
        guard let preset = preset else { return false }
        return preset.hasPrefix("AU:")
    }
    
    /// Check if a voicePreset string represents a Drum Kit
    /// Recognizes "Standard Drum Kit" and any kit name from DrumKitLoader
    static func isDrumKitPreset(_ preset: String?) -> Bool {
        guard let preset = preset else { return false }
        
        // Check for standard drum kit names
        let drumKitNames = [
            "Standard Drum Kit",
            "Drum Kit",
            "TR-909",
            "TR-808",
            "Acoustic Kit",
            "Electronic Kit"
        ]
        
        // Check if preset matches any known drum kit name (case-insensitive contains)
        for kitName in drumKitNames {
            if preset.localizedCaseInsensitiveContains(kitName) {
                return true
            }
        }
        
        // Also check against available kits from DrumKitLoader
        // Note: This is a static check - we can't access the shared instance here
        // The above list covers the common cases
        
        return false
    }
    
    /// Parse an AU voicePreset string to get the plugin name and manufacturer
    static func parseAudioUnitPreset(_ preset: String) -> (name: String, manufacturer: String)? {
        guard preset.hasPrefix("AU:") else { return nil }
        let components = preset.dropFirst(3).split(separator: ":")
        guard components.count >= 2 else { return nil }
        return (name: String(components[0]), manufacturer: String(components[1]))
    }
    
    // MARK: - Cleanup
    
    /// Stop all instruments
    func stopAll() {
        for instrument in instruments.values {
            instrument.stop()
        }
    }
    
    /// Remove all instruments
    func removeAll() {
        stopAll()
        instruments.removeAll()
        activeInstrument = nil
    }
}

// MARK: - InstrumentManager + ProjectManager Integration

extension InstrumentManager {
    
    /// Setup the instrument manager with a project manager
    func configure(with projectManager: ProjectManager) {
        self.projectManager = projectManager
        
        // NOTE: Do NOT create instruments here - wait for audioEngine to be set first
        // Instruments will be created on-demand when MIDI is played or when explicitly requested
        // This ensures samplers are attached to the correct audio engine
    }
    
    /// Configure with both ProjectManager and AudioEngine
    /// This is the preferred method - ensures all samplers are attached to the correct engine
    func configure(with projectManager: ProjectManager, audioEngine: AudioEngine) {
        self.projectManager = projectManager
        self.audioEngine = audioEngine
        
        // Create instruments for existing MIDI tracks
        // Now that we have the audio engine, samplers will be properly attached
        if let project = projectManager.currentProject {
            for track in project.tracks where track.trackType == .midi || track.trackType == .instrument {
                let _ = getOrCreateInstrument(for: track.id)
            }
        }
    }
    
    /// Handle track being added to project
    func trackAdded(_ track: AudioTrack) {
        if track.trackType == .midi || track.trackType == .instrument {
            let _ = getOrCreateInstrument(for: track.id)
        }
    }
    
    /// Handle track being removed from project
    func trackRemoved(trackId: UUID) {
        removeInstrument(for: trackId)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let instrumentManagerActiveChanged = Notification.Name("instrumentManagerActiveChanged")
}

