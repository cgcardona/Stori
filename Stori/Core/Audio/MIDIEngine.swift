//
//  MIDIEngine.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  MIDI playback engine that plays MIDI regions through virtual instruments.
//  Handles timing, scheduling, and real-time parameter automation.
//

import Foundation
import AVFoundation

// MARK: - MIDIEngine

/// Engine for playing back MIDI regions with virtual instruments.
@MainActor
@Observable
class MIDIEngine {
    
    // MARK: - Properties
    
    /// Currently playing MIDI tracks
    var midiTracks: [MIDITrack] = []
    
    /// Virtual instrument engines (one per track)
    var synthEngines: [UUID: SynthEngine] = [:]
    
    /// Playback state
    var isPlaying = false
    
    /// Current playback position in beats
    var currentPosition: TimeInterval = 0
    
    /// Project tempo (BPM)
    var tempo: Double = 120.0
    
    /// Look-ahead time for scheduling (seconds)
    let lookAheadTime: TimeInterval = 0.1
    
    /// Scheduled note events (for tracking what's playing)
    private var scheduledNotes: [ScheduledNote] = []
    
    /// Playback timer
    private var playbackTimer: Timer?
    
    /// Last processed position for each track
    private var lastProcessedPosition: [UUID: TimeInterval] = [:]
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Track Management
    
    /// Add a MIDI track to the engine
    func addTrack(_ track: MIDITrack) {
        midiTracks.append(track)
        
        // Create synth engine for this track
        let synth = SynthEngine()
        synthEngines[track.id] = synth
        
        // Start synth engine
        do {
            try synth.start()
        } catch {
        }
        
    }
    
    /// Remove a MIDI track
    func removeTrack(withId id: UUID) {
        midiTracks.removeAll { $0.id == id }
        
        if let synth = synthEngines[id] {
            synth.stop()
            synthEngines.removeValue(forKey: id)
        }
    }
    
    /// Get synth engine for a track
    func synthEngine(for trackId: UUID) -> SynthEngine? {
        synthEngines[trackId]
    }
    
    // MARK: - Playback Control
    
    /// Start playback from current position
    func play() {
        guard !isPlaying else { return }
        
        isPlaying = true
        
        // Initialize position tracking
        for track in midiTracks {
            lastProcessedPosition[track.id] = currentPosition
        }
        
        // Start playback timer (60fps for smooth scheduling)
        // THREAD SAFETY: Use DispatchQueue.main.async instead of Task { @MainActor }
        // Task creation can crash in swift_getObjectType when accessing weak self
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.processPlayback()
            }
        }
        
    }
    
    /// Pause playback
    func pause() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
        
        // Release all playing notes
        allNotesOff()
        
    }
    
    /// Stop playback and return to start
    func stop() {
        pause()
        currentPosition = 0
        lastProcessedPosition.removeAll()
        scheduledNotes.removeAll()
        
    }
    
    /// Seek to a beat position
    func seek(toBeat beat: Double) {
        let wasPlaying = isPlaying
        
        if wasPlaying {
            pause()
        }
        
        currentPosition = max(0, beat)
        lastProcessedPosition.removeAll()
        scheduledNotes.removeAll()
        
        if wasPlaying {
            play()
        }
    }
    
    /// Turn off all playing notes
    func allNotesOff() {
        for synth in synthEngines.values {
            synth.allNotesOff()
        }
        scheduledNotes.removeAll()
    }
    
    // MARK: - Playback Processing
    
    private func processPlayback() {
        guard isPlaying else { return }
        
        // Advance position based on tempo
        let beatIncrement = (tempo / 60.0) / 60.0 // beats per frame at 60fps
        currentPosition += beatIncrement
        
        // Calculate look-ahead window
        let lookAheadBeats = (tempo / 60.0) * lookAheadTime
        let windowEnd = currentPosition + lookAheadBeats
        
        // Process each track
        for track in midiTracks {
            guard !track.isMuted else { continue }
            
            guard let synth = synthEngines[track.id] else { continue }
            
            let lastPosition = lastProcessedPosition[track.id] ?? currentPosition
            
            // Process each region in the track
            for region in track.regions {
                guard !region.isMuted else { continue }
                
                // Check if region is in our window
                if region.startBeat > windowEnd || region.endBeat < lastPosition {
                    continue
                }
                
                // Process notes in this region
                for note in region.notes {
                    let absoluteNoteStart = region.startBeat + note.startBeat
                    let absoluteNoteEnd = absoluteNoteStart + note.durationBeats
                    
                    // Apply track transpose and velocity offset
                    let transposedPitch = UInt8(clamping: Int(note.pitch) + Int(track.transpose))
                    let adjustedVelocity = UInt8(clamping: Int(note.velocity) + Int(track.velocityOffset))
                    
                    // Schedule note on
                    if absoluteNoteStart >= lastPosition && absoluteNoteStart < windowEnd {
                        synth.noteOn(pitch: transposedPitch, velocity: adjustedVelocity)
                        
                        scheduledNotes.append(ScheduledNote(
                            trackId: track.id,
                            pitch: transposedPitch,
                            noteOffTime: absoluteNoteEnd
                        ))
                    }
                }
                
                // Process CC events
                for ccEvent in region.controllerEvents {
                    let absoluteTime = region.startBeat + ccEvent.beat
                    
                    if absoluteTime >= lastPosition && absoluteTime < windowEnd {
                        applyControlChange(
                            controller: ccEvent.controller,
                            value: ccEvent.value,
                            to: synth
                        )
                    }
                }
            }
            
            lastProcessedPosition[track.id] = currentPosition
        }
        
        // Process note offs
        let notesToRelease = scheduledNotes.filter { $0.noteOffTime <= currentPosition }
        for scheduledNote in notesToRelease {
            if let synth = synthEngines[scheduledNote.trackId] {
                synth.noteOff(pitch: scheduledNote.pitch)
            }
        }
        scheduledNotes.removeAll { $0.noteOffTime <= currentPosition }
    }
    
    /// Apply a control change to a synth
    private func applyControlChange(controller: UInt8, value: UInt8, to synth: SynthEngine) {
        let normalizedValue = Float(value) / 127.0
        
        switch controller {
        case MIDICCEvent.modWheel:
            // Could modulate LFO depth or filter
            break
        case MIDICCEvent.volume:
            synth.setMasterVolume(normalizedValue)
        case MIDICCEvent.filterCutoff:
            synth.setFilterCutoff(normalizedValue)
        case MIDICCEvent.filterResonance:
            synth.setFilterResonance(normalizedValue)
        default:
            break
        }
    }
    
    // MARK: - Real-time Note Input
    
    /// Play a note immediately (for live preview)
    func previewNote(pitch: UInt8, velocity: UInt8, trackId: UUID?) {
        let synth: SynthEngine
        
        if let id = trackId, let trackSynth = synthEngines[id] {
            synth = trackSynth
        } else if let firstSynth = synthEngines.values.first {
            synth = firstSynth
        } else {
            // Create a temporary synth for preview
            let tempSynth = SynthEngine()
            do {
                try tempSynth.start()
                tempSynth.noteOn(pitch: pitch, velocity: velocity)
                
                // Auto note-off after 0.5 seconds
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    tempSynth.noteOff(pitch: pitch)
                }
            } catch {
            }
            return
        }
        
        synth.noteOn(pitch: pitch, velocity: velocity)
    }
    
    /// Stop a preview note
    func stopPreviewNote(pitch: UInt8, trackId: UUID?) {
        if let id = trackId, let synth = synthEngines[id] {
            synth.noteOff(pitch: pitch)
        } else if let synth = synthEngines.values.first {
            synth.noteOff(pitch: pitch)
        }
    }
}

// MARK: - ScheduledNote

/// Represents a scheduled note for tracking note-off times.
private struct ScheduledNote {
    let trackId: UUID
    let pitch: UInt8
    let noteOffTime: TimeInterval
}

// MARK: - Quantization Engine

/// Quantization utilities for MIDI notes.
enum QuantizationEngine {
    
    /// Quantize notes to a grid resolution
    static func quantize(
        notes: [MIDINote],
        resolution: SnapResolution,
        strength: Float = 1.0,
        quantizeDuration: Bool = true
    ) -> [MIDINote] {
        guard resolution != .off, strength > 0 else { return notes }
        
        return notes.map { note in
            var quantized = note
            
            // Quantize start time
            let quantizedStart = resolution.quantize(beat: note.startBeat, strength: strength)
            quantized.startBeat = max(0, quantizedStart)
            
            // Quantize duration if requested
            if quantizeDuration {
                let quantizedDuration = resolution.quantize(beat: note.durationBeats)
                quantized.durationBeats = max(resolution.stepDurationBeats, quantizedDuration)
            }
            
            return quantized
        }
    }
    
    /// Apply swing to notes (affects off-beat notes)
    static func applySwing(
        notes: [MIDINote],
        amount: Float,  // 0.0 to 1.0
        gridResolution: SnapResolution = .eighth
    ) -> [MIDINote] {
        guard amount > 0 else { return notes }
        
        let gridDuration = gridResolution.stepDurationBeats
        
        return notes.map { note in
            var swung = note
            
            // Check if note is on an off-beat
            let gridPosition = note.startBeat / gridDuration
            let isOffBeat = (Int(gridPosition) % 2) == 1
            
            if isOffBeat {
                // Push the note later based on swing amount
                let swingOffset = gridDuration * Double(amount) * 0.5
                swung.startBeat += swingOffset
            }
            
            return swung
        }
    }
    
    /// Humanize notes (add subtle timing and velocity variations)
    static func humanize(
        notes: [MIDINote],
        timingVariation: TimeInterval = 0.02,  // beats
        velocityVariation: UInt8 = 10
    ) -> [MIDINote] {
        return notes.map { note in
            var humanized = note
            
            // Randomize timing
            let timeOffset = Double.random(in: -timingVariation...timingVariation)
            humanized.startBeat = max(0, note.startBeat + timeOffset)
            
            // Randomize velocity
            let velOffset = Int.random(in: -Int(velocityVariation)...Int(velocityVariation))
            humanized.velocity = UInt8(clamping: Int(note.velocity) + velOffset)
            
            return humanized
        }
    }
    
    /// Legato: extend each note to connect with the next
    static func legato(notes: [MIDINote]) -> [MIDINote] {
        let sortedNotes = notes.sorted { $0.startBeat < $1.startBeat }
        var result: [MIDINote] = []
        
        for i in 0..<sortedNotes.count {
            var note = sortedNotes[i]
            
            if i < sortedNotes.count - 1 {
                let nextNote = sortedNotes[i + 1]
                // Extend to next note start, leaving tiny gap
                note.durationBeats = nextNote.startBeat - note.startBeat - 0.01
            }
            
            result.append(note)
        }
        
        return result
    }
    
    /// Staccato: shorten all notes
    static func staccato(notes: [MIDINote], factor: Float = 0.5) -> [MIDINote] {
        return notes.map { note in
            var staccato = note
            staccato.durationBeats *= Double(factor)
            staccato.durationBeats = max(0.01, staccato.durationBeats)
            return staccato
        }
    }
}

// MARK: - Scale Snap Engine

/// Scale snapping utilities for MIDI notes.
enum ScaleSnapEngine {
    
    /// Snap notes to a scale
    static func snap(
        notes: [MIDINote],
        to scale: Scale,
        root: UInt8 = 60  // C4
    ) -> [MIDINote] {
        return notes.map { note in
            var snapped = note
            snapped.pitch = scale.nearestNote(to: note.pitch, root: root)
            return snapped
        }
    }
    
    /// Check if all notes are in a scale
    static func allNotesInScale(
        notes: [MIDINote],
        scale: Scale,
        root: UInt8 = 60
    ) -> Bool {
        return notes.allSatisfy { note in
            scale.contains(pitch: note.pitch, root: root)
        }
    }
    
    /// Get notes that are not in a scale
    static func notesOutOfScale(
        notes: [MIDINote],
        scale: Scale,
        root: UInt8 = 60
    ) -> [MIDINote] {
        return notes.filter { note in
            !scale.contains(pitch: note.pitch, root: root)
        }
    }
    
    /// Transpose notes to a new key
    static func transpose(notes: [MIDINote], by semitones: Int) -> [MIDINote] {
        return notes.map { note in
            var transposed = note
            transposed.pitch = UInt8(clamping: Int(note.pitch) + semitones)
            return transposed
        }
    }
    
    /// Invert notes around a center pitch
    static func invert(notes: [MIDINote], around center: UInt8 = 60) -> [MIDINote] {
        return notes.map { note in
            var inverted = note
            let offset = Int(note.pitch) - Int(center)
            inverted.pitch = UInt8(clamping: Int(center) - offset)
            return inverted
        }
    }
    
    /// Retrograde: reverse note order
    static func retrograde(notes: [MIDINote]) -> [MIDINote] {
        let sortedNotes = notes.sorted { $0.startBeat < $1.startBeat }
        guard let lastNote = sortedNotes.last else { return notes }
        
        let totalDuration = lastNote.endBeat
        
        return sortedNotes.map { note in
            var reversed = note
            reversed.startBeat = totalDuration - note.endBeat
            return reversed
        }
    }
}

