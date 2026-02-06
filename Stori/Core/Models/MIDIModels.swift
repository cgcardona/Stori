//
//  MIDIModels.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  Core MIDI data models for professional MIDI workflow.
//  Supports note recording, editing, and playback with full velocity/CC support.
//

import Foundation
import SwiftUI

// MARK: - MIDINote

/// Represents a single MIDI note event with pitch, velocity, timing, and channel.
struct MIDINote: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var pitch: UInt8           // 0-127 (C-1 to G9)
    var velocity: UInt8        // 0-127 (0 = note off in some contexts)
    var startBeat: Double      // Position in region (musical time, beats)
    var durationBeats: Double  // Note length (musical time, beats)
    var channel: UInt8         // MIDI channel (0-15)
    
    // MARK: - Computed Properties
    
    /// Human-readable note name (e.g., "C4", "F#5")
    var noteName: String { MIDIHelper.noteName(for: pitch) }
    
    /// Octave number (-1 to 9)
    var octave: Int { Int(pitch / 12) - 1 }
    
    /// Note within octave (0-11, where 0 = C)
    var noteInOctave: Int { Int(pitch % 12) }
    
    /// End beat of the note
    var endBeat: Double { startBeat + durationBeats }
    
    /// Whether this is a black key
    var isBlackKey: Bool { MIDIHelper.isBlackKey(pitch) }
    
    /// Frequency in Hz (A4 = 440Hz)
    var frequencyHz: Double { MIDIHelper.frequencyHz(for: pitch) }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        pitch: UInt8,
        velocity: UInt8 = 100,
        startBeat: Double,
        durationBeats: Double,
        channel: UInt8 = 0
    ) {
        // MIDI PROTOCOL: Validate pitch is in valid MIDI range (0-127)
        assert(pitch <= 127, "MIDI pitch must be 0-127 (got \(pitch))")
        
        // MIDI PROTOCOL: Validate velocity is in valid MIDI range (0-127)
        assert(velocity <= 127, "MIDI velocity must be 0-127 (got \(velocity))")
        
        // MIDI PROTOCOL: Validate channel is in valid MIDI range (0-15)
        assert(channel <= 15, "MIDI channel must be 0-15 (got \(channel))")
        
        self.id = id
        // Clamp to safe values (release builds or corrupt data)
        self.pitch = min(pitch, 127)
        self.velocity = min(velocity, 127)
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.channel = min(channel, 15)
    }
    
    // MARK: - Factory Methods
    
    /// Create a note from note name string (e.g., "C4", "F#5")
    static func fromNoteName(_ name: String, velocity: UInt8 = 100, startBeat: Double, durationBeats: Double) -> MIDINote? {
        guard let pitch = MIDIHelper.pitch(for: name) else { return nil }
        return MIDINote(pitch: pitch, velocity: velocity, startBeat: startBeat, durationBeats: durationBeats)
    }
    
    // MARK: - Resize Collision (Issue #79)
    
    /// Maximum end beat allowed when resizing this note (right edge) so it does not overlap
    /// the next note on the same pitch. Prevents invalid MIDI (Note On before Note Off).
    ///
    /// - Parameters:
    ///   - resizingNote: The note being resized (must be in `allNotes`).
    ///   - allNotes: All notes in the region (including the note being resized).
    ///   - requestedEndBeat: The end beat the user requested (e.g. after snap).
    /// - Returns: The maximum allowed end beat (≤ requestedEndBeat) that does not overlap
    ///   any same-pitch note that starts after this note. If no such note exists, returns
    ///   `requestedEndBeat`.
    static func maxEndBeatForResize(resizingNote: MIDINote, allNotes: [MIDINote], requestedEndBeat: Double) -> Double {
        let nextSamePitchStarts = allNotes
            .filter { $0.pitch == resizingNote.pitch && $0.id != resizingNote.id && $0.startBeat > resizingNote.startBeat }
            .map(\.startBeat)
        guard let limit = nextSamePitchStarts.min() else { return requestedEndBeat }
        return min(requestedEndBeat, limit)
    }
}

// MARK: - MIDIRegion

/// A region containing MIDI notes and controller events, placed on the timeline.
struct MIDIRegion: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var notes: [MIDINote]
    var startBeat: Double            // Position on timeline (musical time, beats)
    var durationBeats: Double        // Region length (musical time, beats)
    var instrumentId: UUID?          // Linked virtual instrument
    var colorHex: String             // Color as hex string for Codable
    var isLooped: Bool
    var loopCount: Int
    var isMuted: Bool
    
    /// Content length for one loop iteration (in beats). Defaults to original note content duration.
    /// When resized with empty space, this becomes larger than the original notes span.
    /// Looping repeats this contentLength, not the original notes duration.
    var contentLengthBeats: Double
    
    // Controller data
    var controllerEvents: [MIDICCEvent]
    var pitchBendEvents: [MIDIPitchBendEvent]
    
    // MARK: - Computed Properties
    
    var color: Color {
        get { Color(hex: colorHex) ?? .blue }
        set { colorHex = newValue.toHex() }
    }
    
    /// End beat of the region
    var endBeat: Double { startBeat + durationBeats }
    
    /// Total duration - same as durationBeats since it already represents the full region length
    /// Note: loopCount is legacy and redundant; durationBeats is updated when looping via resize
    var totalDurationBeats: Double {
        durationBeats  // durationBeats already includes the full looped length
    }
    
    /// Number of notes in this region
    var noteCount: Int { notes.count }
    
    /// Pitch range of notes
    var pitchRange: ClosedRange<UInt8>? {
        guard let minPitch = notes.map(\.pitch).min(),
              let maxPitch = notes.map(\.pitch).max() else { return nil }
        return minPitch...maxPitch
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        name: String = "MIDI Region",
        notes: [MIDINote] = [],
        startBeat: Double = 0,
        durationBeats: Double = 4.0,
        instrumentId: UUID? = nil,
        color: Color = .blue,
        isLooped: Bool = false,
        loopCount: Int = 1,
        isMuted: Bool = false,
        controllerEvents: [MIDICCEvent] = [],
        pitchBendEvents: [MIDIPitchBendEvent] = [],
        contentLengthBeats: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.notes = notes
        // Ensure non-negative timeline values
        self.startBeat = max(0, startBeat)
        self.durationBeats = max(0, durationBeats)
        self.instrumentId = instrumentId
        self.colorHex = color.toHex()
        self.isLooped = isLooped
        self.loopCount = max(1, loopCount)
        self.isMuted = isMuted
        self.controllerEvents = controllerEvents
        self.pitchBendEvents = pitchBendEvents
        // Default contentLength to durationBeats if not specified
        self.contentLengthBeats = contentLengthBeats ?? max(0, durationBeats)
    }
    
    // MARK: - Note Editing
    
    /// Add a note to the region
    mutating func addNote(_ note: MIDINote) {
        notes.append(note)
        // Auto-extend duration if needed
        if note.endBeat > durationBeats {
            durationBeats = note.endBeat
            // Keep contentLength in sync for proper looping behavior
            contentLengthBeats = max(contentLengthBeats, note.endBeat)
        }
    }
    
    /// Remove notes by IDs
    mutating func removeNotes(withIds ids: Set<UUID>) {
        notes.removeAll { ids.contains($0.id) }
    }
    
    /// Get notes at a specific beat
    func notes(at beat: Double) -> [MIDINote] {
        notes.filter { $0.startBeat <= beat && $0.endBeat > beat }
    }
    
    /// Get notes in a beat range
    func notes(in range: ClosedRange<Double>) -> [MIDINote] {
        notes.filter { $0.startBeat < range.upperBound && $0.endBeat > range.lowerBound }
    }
    
    /// Transpose all notes by semitones
    /// Returns the number of notes that were clamped (out-of-range)
    @discardableResult
    mutating func transpose(by semitones: Int) -> Int {
        var clampedCount = 0
        
        notes = notes.map { note in
            var transposed = note
            let newPitch = Int(note.pitch) + semitones
            
            // Check if transposition would go out of range
            if newPitch < 0 || newPitch > 127 {
                clampedCount += 1
                AppLogger.shared.warning(
                    "MIDI transpose: Note \(note.noteName) + \(semitones) = \(newPitch) out of range (0-127), clamping",
                    category: .midi
                )
            }
            
            // Clamp to valid MIDI range (0-127, not UInt8 range 0-255)
            let clampedPitch = max(0, min(127, newPitch))
            transposed.pitch = UInt8(clampedPitch)
            return transposed
        }
        
        // Notify user if any notes were clamped
        if clampedCount > 0 {
            AppLogger.shared.info(
                "Transpose clamped \(clampedCount) note(s) to MIDI range (0-127)",
                category: .midi
            )
        }
        
        return clampedCount
    }
    
    /// Shift all notes in time
    mutating func shift(by beats: Double) {
        notes = notes.map { note in
            var shifted = note
            shifted.startBeat = max(0, note.startBeat + beats)
            return shifted
        }
    }
}

// MARK: - MIDICCEvent

/// MIDI Continuous Controller event for automation and expression.
struct MIDICCEvent: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var controller: UInt8      // CC number (0-127)
    var value: UInt8           // 0-127
    var beat: Double           // Position in region (beats)
    var channel: UInt8         // MIDI channel (0-15)
    
    // MARK: - Common CC Numbers
    
    static let modWheel: UInt8 = 1
    static let breath: UInt8 = 2
    static let foot: UInt8 = 4
    static let portamentoTime: UInt8 = 5
    static let volume: UInt8 = 7
    static let balance: UInt8 = 8
    static let pan: UInt8 = 10
    static let expression: UInt8 = 11
    static let sustain: UInt8 = 64
    static let portamento: UInt8 = 65
    static let sostenuto: UInt8 = 66
    static let softPedal: UInt8 = 67
    static let legato: UInt8 = 68
    static let hold2: UInt8 = 69
    static let filterCutoff: UInt8 = 74
    static let filterResonance: UInt8 = 71
    static let releaseTime: UInt8 = 72
    static let attackTime: UInt8 = 73
    static let brightness: UInt8 = 74
    static let reverbSend: UInt8 = 91
    static let chorusSend: UInt8 = 93
    static let allSoundOff: UInt8 = 120
    static let allNotesOff: UInt8 = 123
    
    // MARK: - Computed Properties
    
    /// Human-readable name for common CC numbers
    var controllerName: String {
        switch controller {
        case Self.modWheel: return "Mod Wheel"
        case Self.breath: return "Breath"
        case Self.volume: return "Volume"
        case Self.pan: return "Pan"
        case Self.expression: return "Expression"
        case Self.sustain: return "Sustain"
        case Self.filterCutoff: return "Filter Cutoff"
        case Self.filterResonance: return "Filter Resonance"
        case Self.reverbSend: return "Reverb Send"
        case Self.chorusSend: return "Chorus Send"
        default: return "CC \(controller)"
        }
    }
    
    /// Normalized value (0.0 - 1.0)
    var normalizedValue: Float { Float(value) / 127.0 }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        controller: UInt8,
        value: UInt8,
        beat: Double,
        channel: UInt8 = 0
    ) {
        self.id = id
        self.controller = controller
        self.value = value
        self.beat = beat
        self.channel = channel
    }
}

// MARK: - MIDIPitchBendEvent

/// MIDI Pitch Bend event for smooth pitch modulation.
struct MIDIPitchBendEvent: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var value: Int16           // -8192 to +8191 (0 = center)
    var beat: Double           // Position in region (beats)
    var channel: UInt8         // MIDI channel (0-15)
    
    // MARK: - Constants
    
    static let center: Int16 = 0
    static let maxUp: Int16 = 8191
    static let maxDown: Int16 = -8192
    static let range: ClosedRange<Int16> = -8192...8191
    
    // MARK: - Computed Properties
    
    /// Normalized value (-1.0 to 1.0)
    var normalizedValue: Float {
        if value >= 0 {
            return Float(value) / Float(Self.maxUp)
        } else {
            return Float(value) / Float(-Self.maxDown)
        }
    }
    
    /// Semitone offset (assuming ±2 semitone bend range)
    func semitoneOffset(bendRange: Float = 2.0) -> Float {
        normalizedValue * bendRange
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        value: Int16,
        beat: Double,
        channel: UInt8 = 0
    ) {
        self.id = id
        self.value = value.clamped(to: Self.range)
        self.beat = beat
        self.channel = channel
    }
    
    /// Create from normalized value (-1.0 to 1.0)
    static func fromNormalized(_ normalized: Float, beat: Double, channel: UInt8 = 0) -> MIDIPitchBendEvent {
        let value: Int16
        if normalized >= 0 {
            value = Int16(normalized * Float(maxUp))
        } else {
            value = Int16(normalized * Float(-maxDown))
        }
        return MIDIPitchBendEvent(value: value, beat: beat, channel: channel)
    }
}

// MARK: - MIDITrack

/// A track containing MIDI regions for virtual instrument playback.
struct MIDITrack: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var regions: [MIDIRegion]
    var instrumentId: UUID?
    var colorHex: String
    var isMuted: Bool
    var isSolo: Bool
    var isRecordEnabled: Bool
    var volume: Float          // 0.0 - 1.0
    var pan: Float             // -1.0 (L) to 1.0 (R)
    
    // MIDI-specific settings
    var inputDevice: String?
    var inputChannel: UInt8?   // nil = omni (all channels)
    var outputChannel: UInt8
    var transpose: Int8        // -48 to +48 semitones
    var velocityOffset: Int8   // -127 to +127
    
    // MARK: - Computed Properties
    
    var color: Color {
        get { Color(hex: colorHex) ?? .purple }
        set { colorHex = newValue.toHex() }
    }
    
    /// Total number of notes across all regions
    var totalNoteCount: Int {
        regions.reduce(0) { $0 + $1.noteCount }
    }
    
    /// Track duration (end of last region, in beats)
    var durationBeats: Double {
        regions.map(\.endBeat).max() ?? 0
    }
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        name: String = "MIDI Track",
        regions: [MIDIRegion] = [],
        instrumentId: UUID? = nil,
        color: Color = .purple,
        isMuted: Bool = false,
        isSolo: Bool = false,
        isRecordEnabled: Bool = false,
        volume: Float = 0.8,
        pan: Float = 0.0,
        inputDevice: String? = nil,
        inputChannel: UInt8? = nil,
        outputChannel: UInt8 = 0,
        transpose: Int8 = 0,
        velocityOffset: Int8 = 0
    ) {
        self.id = id
        self.name = name
        self.regions = regions
        self.instrumentId = instrumentId
        self.colorHex = color.toHex() ?? "#800080"
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.isRecordEnabled = isRecordEnabled
        self.volume = volume
        self.pan = pan
        self.inputDevice = inputDevice
        self.inputChannel = inputChannel
        self.outputChannel = outputChannel
        self.transpose = transpose
        self.velocityOffset = velocityOffset
    }
    
    // MARK: - Region Management
    
    /// Add a region to the track
    mutating func addRegion(_ region: MIDIRegion) {
        regions.append(region)
    }
    
    /// Remove a region by ID
    mutating func removeRegion(withId id: UUID) {
        regions.removeAll { $0.id == id }
    }
    
    /// Get regions at a specific beat
    func regions(at beat: Double) -> [MIDIRegion] {
        regions.filter { $0.startBeat <= beat && $0.endBeat > beat }
    }
    
    /// Get all notes at a specific beat across all regions
    func notes(at beat: Double) -> [MIDINote] {
        regions(at: beat).flatMap { region in
            let relativeBeat = beat - region.startBeat
            return region.notes(at: relativeBeat)
        }
    }
}

// MARK: - Snap Resolution

/// Grid resolution for quantization and snapping.
enum SnapResolution: String, CaseIterable, Codable {
    case bar = "1 Bar"
    case half = "1/2"
    case quarter = "1/4"
    case eighth = "1/8"
    case sixteenth = "1/16"
    case thirtysecond = "1/32"
    case sixtyfourth = "1/64"
    case tripletQuarter = "1/4T"
    case tripletEighth = "1/8T"
    case tripletSixteenth = "1/16T"
    case off = "Off"
    
    /// Step duration in beats adjusted for time signature.
    /// **CRITICAL (Issue #64)**: This method correctly handles odd/compound time signatures.
    /// - Parameter timeSignature: The current time signature
    /// - Returns: Step duration in beats for the given time signature
    func stepDurationBeats(timeSignature: TimeSignature) -> Double {
        // Calculate beats per bar based on time signature
        // numerator = number of beats, denominator = beat unit
        // e.g., 7/8 = 7 eighth notes = 3.5 quarter-note beats
        // e.g., 5/4 = 5 quarter notes = 5.0 quarter-note beats
        let beatsPerBar = Double(timeSignature.numerator) * (4.0 / Double(timeSignature.denominator))
        
        switch self {
        case .bar:
            return beatsPerBar
        case .half:
            return beatsPerBar / 2.0
        case .quarter:
            // Quarter note is always 1.0 beat (our base unit)
            return 1.0
        case .eighth:
            return 0.5
        case .sixteenth:
            return 0.25
        case .thirtysecond:
            return 0.125
        case .sixtyfourth:
            return 0.0625
        case .tripletQuarter:
            return 1.0 / 1.5
        case .tripletEighth:
            return 0.5 / 1.5
        case .tripletSixteenth:
            return 0.25 / 1.5
        case .off:
            return 0
        }
    }
    
    /// Icon for display
    var icon: String {
        switch self {
        case .bar: return "rectangle.fill"
        case .half, .quarter: return "music.note"
        case .eighth, .sixteenth, .thirtysecond, .sixtyfourth: return "music.note.list"
        case .tripletQuarter, .tripletEighth, .tripletSixteenth: return "3.circle"
        case .off: return "xmark.circle"
        }
    }
    
    /// Quantize a beat value to this resolution with time signature support.
    /// **CRITICAL (Issue #64)**: This method correctly handles odd/compound time signatures.
    /// - Parameters:
    ///   - beat: The beat position to quantize
    ///   - timeSignature: The current time signature
    /// - Returns: Quantized beat position
    func quantize(beat: Double, timeSignature: TimeSignature) -> Double {
        let gridSize = stepDurationBeats(timeSignature: timeSignature)
        guard gridSize > 0 else { return beat }
        return round(beat / gridSize) * gridSize
    }
    
    /// Quantize with strength and time signature support.
    /// **CRITICAL (Issue #64)**: This method correctly handles odd/compound time signatures.
    /// - Parameters:
    ///   - beat: The beat position to quantize
    ///   - timeSignature: The current time signature
    ///   - strength: Quantize strength (0.0 = no change, 1.0 = full snap to grid)
    /// - Returns: Quantized beat position
    func quantize(beat: Double, timeSignature: TimeSignature, strength: Float) -> Double {
        guard strength > 0 else { return beat }
        let quantized = quantize(beat: beat, timeSignature: timeSignature)
        let offset = quantized - beat
        return beat + (offset * Double(strength))
    }
}

// MARK: - Piano Roll Edit Mode

/// Edit mode for the piano roll editor.
enum PianoRollEditMode: String, CaseIterable {
    case select = "Select"
    case draw = "Draw"
    case erase = "Erase"
    case slice = "Slice"
    case glue = "Glue"
    case legato = "Legato"
    case brush = "Brush"
    case velocity = "Velocity"
    
    var icon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .draw: return "pencil"
        case .erase: return "eraser"
        case .slice: return "scissors"
        case .glue: return "link"
        case .legato: return "arrow.right.to.line"
        case .brush: return "paintbrush"
        case .velocity: return "waveform.path"
        }
    }
    
    var shortcut: String {
        switch self {
        case .select: return "V"
        case .draw: return "P"
        case .erase: return "E"
        case .slice: return "S"
        case .glue: return "G"
        case .legato: return "L"
        case .brush: return "B"
        case .velocity: return "U"
        }
    }
    
    var tooltip: String {
        switch self {
        case .select: return "Select and move notes"
        case .draw: return "Draw new notes"
        case .erase: return "Delete notes"
        case .slice: return "Split notes at click position"
        case .glue: return "Merge adjacent notes of same pitch"
        case .legato: return "Extend notes to next note"
        case .brush: return "Paint notes by dragging"
        case .velocity: return "Adjust note velocity"
        }
    }
}

// MARK: - Extensions

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

