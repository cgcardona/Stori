//
//  MIDIHelper.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  MIDI utility functions for note conversion, frequency calculation,
//  and other MIDI-related operations.
//

import Foundation
import AVFoundation

// MARK: - MIDIHelper

/// Utility enum providing MIDI helper functions for note names, frequencies, and conversions.
enum MIDIHelper {
    
    // MARK: - Constants
    
    /// Note names in chromatic order
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    /// Alternative flat note names
    static let flatNoteNames = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]
    
    /// Middle C (C4) MIDI pitch
    static let middleC: UInt8 = 60
    
    /// A440 (A4) MIDI pitch - tuning reference
    static let a440: UInt8 = 69
    
    /// Standard tuning frequency for A4
    static let standardTuning: Double = 440.0
    
    /// Valid MIDI pitch range
    static let pitchRange: ClosedRange<UInt8> = 0...127
    
    /// Valid MIDI velocity range
    static let velocityRange: ClosedRange<UInt8> = 1...127
    
    // MARK: - Note Name Conversion
    
    /// Convert MIDI pitch to note name (e.g., 60 → "C4")
    static func noteName(for pitch: UInt8, useFlats: Bool = false) -> String {
        let octave = Int(pitch / 12) - 1
        let noteIndex = Int(pitch % 12)
        let names = useFlats ? flatNoteNames : noteNames
        return "\(names[noteIndex])\(octave)"
    }
    
    /// Convert note name to MIDI pitch (e.g., "C4" → 60)
    static func pitch(for noteName: String) -> UInt8? {
        let trimmed = noteName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        // Parse note letter and accidental
        var noteIndex: Int?
        var charIndex = trimmed.startIndex
        
        let firstChar = String(trimmed[charIndex]).uppercased()
        
        // Find base note
        let baseNotes = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
        guard let baseNote = baseNotes[firstChar] else { return nil }
        noteIndex = baseNote
        charIndex = trimmed.index(after: charIndex)
        
        // Check for accidental
        if charIndex < trimmed.endIndex {
            let accidental = trimmed[charIndex]
            if accidental == "#" || accidental == "♯" {
                noteIndex! += 1
                charIndex = trimmed.index(after: charIndex)
            } else if accidental == "b" || accidental == "♭" {
                noteIndex! -= 1
                charIndex = trimmed.index(after: charIndex)
            }
        }
        
        // Parse octave
        let octaveString = String(trimmed[charIndex...])
        guard let octave = Int(octaveString) else { return nil }
        
        // Calculate MIDI pitch (octave -1 = 0-11, octave 0 = 12-23, etc.)
        let pitch = (octave + 1) * 12 + (noteIndex! % 12)
        
        guard pitch >= 0 && pitch <= 127 else { return nil }
        return UInt8(pitch)
    }
    
    // MARK: - Frequency Conversion
    
    /// Convert MIDI pitch to frequency in Hz (A4 = 440Hz)
    static func frequencyHz(for pitch: UInt8, tuning: Double = standardTuning) -> Double {
        tuning * pow(2.0, Double(Int(pitch) - Int(a440)) / 12.0)
    }
    
    /// Convert frequency in Hz to nearest MIDI pitch
    static func pitch(for frequency: Double, tuning: Double = standardTuning) -> UInt8 {
        let pitch = 12.0 * log2(frequency / tuning) + Double(a440)
        return UInt8(clamping: Int(round(pitch)))
    }
    
    /// Get cents deviation from exact pitch
    static func centsDeviation(frequency: Double, pitch: UInt8, tuning: Double = standardTuning) -> Double {
        let exactFrequency = frequencyHz(for: pitch, tuning: tuning)
        return 1200.0 * log2(frequency / exactFrequency)
    }
    
    // MARK: - Note Properties
    
    /// Check if a pitch is a black key
    static func isBlackKey(_ pitch: UInt8) -> Bool {
        let noteInOctave = pitch % 12
        return [1, 3, 6, 8, 10].contains(Int(noteInOctave))
    }
    
    /// Check if a pitch is a white key
    static func isWhiteKey(_ pitch: UInt8) -> Bool {
        !isBlackKey(pitch)
    }
    
    /// Get the octave for a pitch (-1 to 9)
    static func octave(for pitch: UInt8) -> Int {
        Int(pitch / 12) - 1
    }
    
    /// Get the note within octave (0-11, where 0 = C)
    static func noteInOctave(for pitch: UInt8) -> Int {
        Int(pitch % 12)
    }
    
    /// Get all pitches for a given note name across all octaves (e.g., all C notes)
    static func allPitches(for noteName: String) -> [UInt8] {
        guard let noteIndex = noteNames.firstIndex(of: noteName.uppercased()) ??
              flatNoteNames.firstIndex(of: noteName.uppercased()) else {
            return []
        }
        
        return (0..<11).map { octave in
            UInt8((octave * 12) + noteIndex)
        }.filter { pitchRange.contains($0) }
    }
    
    // MARK: - Interval Helpers
    
    /// Interval names
    static let intervalNames = [
        0: "Unison",
        1: "Minor 2nd",
        2: "Major 2nd",
        3: "Minor 3rd",
        4: "Major 3rd",
        5: "Perfect 4th",
        6: "Tritone",
        7: "Perfect 5th",
        8: "Minor 6th",
        9: "Major 6th",
        10: "Minor 7th",
        11: "Major 7th",
        12: "Octave"
    ]
    
    /// Get interval name between two pitches
    static func intervalName(from pitch1: UInt8, to pitch2: UInt8) -> String {
        let semitones = abs(Int(pitch2) - Int(pitch1)) % 12
        return intervalNames[semitones] ?? "\(semitones) semitones"
    }
    
    // MARK: - Velocity Helpers
    
    /// Velocity descriptions
    static func velocityDescription(_ velocity: UInt8) -> String {
        switch velocity {
        case 0: return "Off"
        case 1...31: return "ppp"
        case 32...47: return "pp"
        case 48...63: return "p"
        case 64...79: return "mp"
        case 80...95: return "mf"
        case 96...111: return "f"
        case 112...126: return "ff"
        case 127: return "fff"
        default: return "?"
        }
    }
    
    /// Convert velocity (0-127) to normalized value (0.0-1.0)
    static func normalizeVelocity(_ velocity: UInt8) -> Float {
        Float(velocity) / 127.0
    }
    
    /// Convert normalized value (0.0-1.0) to velocity (0-127)
    static func denormalizeVelocity(_ normalized: Float) -> UInt8 {
        UInt8(clamping: Int(normalized * 127.0))
    }
    
    // MARK: - Time Conversion
    // 
    // ARCHITECTURE: Beats are the source of truth in the DAW.
    // Use these conversions ONLY when interfacing with:
    // - AVAudioEngine (requires seconds/samples)
    // - AI generation services (API uses seconds)
    // - Audio file metadata (native duration in seconds)
    //
    
    /// Convert beats to seconds at a given tempo
    /// Use only at AVAudioEngine boundary
    static func beatsToSeconds(_ beats: Double, tempo: Double) -> TimeInterval {
        beats * (60.0 / tempo)
    }
    
    /// Convert seconds to beats at a given tempo
    /// Use only when receiving time from external seconds-based sources
    static func secondsToBeats(_ seconds: TimeInterval, tempo: Double) -> Double {
        seconds * (tempo / 60.0)
    }
    
    /// Convert beats to samples at a given tempo and sample rate
    /// Use only for AVAudioEngine scheduling
    static func beatsToSamples(_ beats: Double, tempo: Double, sampleRate: Double) -> Int64 {
        Int64(beatsToSeconds(beats, tempo: tempo) * sampleRate)
    }
    
    /// Convert samples to beats at a given tempo and sample rate
    /// Use only when receiving sample positions from AVAudioEngine
    static func samplesToBeats(_ samples: Int64, tempo: Double, sampleRate: Double) -> Double {
        let seconds = Double(samples) / sampleRate
        return secondsToBeats(seconds, tempo: tempo)
    }
    
    /// Convert beats to AVAudioFramePosition
    /// Use only for AVAudioEngine scheduling
    static func beatsToFramePosition(_ beats: Double, tempo: Double, sampleRate: Double) -> AVAudioFramePosition {
        AVAudioFramePosition(beatsToSeconds(beats, tempo: tempo) * sampleRate)
    }
    
    /// Format beats as bar.beat.tick string (e.g., "1.2.240")
    static func formatBeatPosition(_ beats: Double, ticksPerBeat: Int = 480, beatsPerBar: Int = 4) -> String {
        let totalTicks = Int(beats * Double(ticksPerBeat))
        let ticksPerBar = ticksPerBeat * beatsPerBar
        
        let bars = totalTicks / ticksPerBar + 1
        let remainingTicks = totalTicks % ticksPerBar
        let beatInBar = remainingTicks / ticksPerBeat + 1
        let ticks = remainingTicks % ticksPerBeat
        
        return String(format: "%d.%d.%03d", bars, beatInBar, ticks)
    }
    
    /// Format beats as bar.beat.subdivision string (e.g., "1.2.50")
    static func formatBeatPositionShort(_ beats: Double, beatsPerBar: Int = 4) -> String {
        let bars = Int(beats / Double(beatsPerBar)) + 1
        let beatInBar = Int(beats.truncatingRemainder(dividingBy: Double(beatsPerBar))) + 1
        let subdivision = Int((beats.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d.%d.%02d", bars, beatInBar, subdivision)
    }
    
    // MARK: - MIDI Message Helpers
    
    /// Note On status byte for a channel
    static func noteOnStatus(channel: UInt8) -> UInt8 {
        0x90 | (channel & 0x0F)
    }
    
    /// Note Off status byte for a channel
    static func noteOffStatus(channel: UInt8) -> UInt8 {
        0x80 | (channel & 0x0F)
    }
    
    /// Control Change status byte for a channel
    static func controlChangeStatus(channel: UInt8) -> UInt8 {
        0xB0 | (channel & 0x0F)
    }
    
    /// Pitch Bend status byte for a channel
    static func pitchBendStatus(channel: UInt8) -> UInt8 {
        0xE0 | (channel & 0x0F)
    }
    
    /// Program Change status byte for a channel
    static func programChangeStatus(channel: UInt8) -> UInt8 {
        0xC0 | (channel & 0x0F)
    }
}

// MARK: - Scale Definitions

/// Musical scale definitions for scale snapping and highlighting.
struct Scale: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let name: String
    let intervals: [Int]  // Semitones from root
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Common Scales
    
    static let major = Scale(
        id: UUID(),
        name: "Major",
        intervals: [0, 2, 4, 5, 7, 9, 11]
    )
    
    static let naturalMinor = Scale(
        id: UUID(),
        name: "Natural Minor",
        intervals: [0, 2, 3, 5, 7, 8, 10]
    )
    
    static let harmonicMinor = Scale(
        id: UUID(),
        name: "Harmonic Minor",
        intervals: [0, 2, 3, 5, 7, 8, 11]
    )
    
    static let melodicMinor = Scale(
        id: UUID(),
        name: "Melodic Minor",
        intervals: [0, 2, 3, 5, 7, 9, 11]
    )
    
    static let pentatonicMajor = Scale(
        id: UUID(),
        name: "Pentatonic Major",
        intervals: [0, 2, 4, 7, 9]
    )
    
    static let pentatonicMinor = Scale(
        id: UUID(),
        name: "Pentatonic Minor",
        intervals: [0, 3, 5, 7, 10]
    )
    
    static let blues = Scale(
        id: UUID(),
        name: "Blues",
        intervals: [0, 3, 5, 6, 7, 10]
    )
    
    static let dorian = Scale(
        id: UUID(),
        name: "Dorian",
        intervals: [0, 2, 3, 5, 7, 9, 10]
    )
    
    static let phrygian = Scale(
        id: UUID(),
        name: "Phrygian",
        intervals: [0, 1, 3, 5, 7, 8, 10]
    )
    
    static let lydian = Scale(
        id: UUID(),
        name: "Lydian",
        intervals: [0, 2, 4, 6, 7, 9, 11]
    )
    
    static let mixolydian = Scale(
        id: UUID(),
        name: "Mixolydian",
        intervals: [0, 2, 4, 5, 7, 9, 10]
    )
    
    static let locrian = Scale(
        id: UUID(),
        name: "Locrian",
        intervals: [0, 1, 3, 5, 6, 8, 10]
    )
    
    static let wholeTone = Scale(
        id: UUID(),
        name: "Whole Tone",
        intervals: [0, 2, 4, 6, 8, 10]
    )
    
    static let chromatic = Scale(
        id: UUID(),
        name: "Chromatic",
        intervals: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
    )
    
    /// All available scales
    static let allScales: [Scale] = [
        major, naturalMinor, harmonicMinor, melodicMinor,
        pentatonicMajor, pentatonicMinor, blues,
        dorian, phrygian, lydian, mixolydian, locrian,
        wholeTone, chromatic
    ]
    
    // MARK: - Scale Operations
    
    /// Check if a pitch belongs to this scale with given root
    func contains(pitch: UInt8, root: UInt8) -> Bool {
        let interval = (Int(pitch) - Int(root)).mod(12)
        return intervals.contains(interval)
    }
    
    /// Get the nearest note in this scale
    func nearestNote(to pitch: UInt8, root: UInt8) -> UInt8 {
        let octave = Int(pitch) / 12
        let noteInOctave = Int(pitch) % 12
        let rootOffset = Int(root) % 12
        
        // Find nearest scale degree
        var minDistance = 12
        var nearestInterval = 0
        
        for interval in intervals {
            let scaleDegree = (interval + rootOffset) % 12
            let distance = min(
                abs(scaleDegree - noteInOctave),
                12 - abs(scaleDegree - noteInOctave)
            )
            if distance < minDistance {
                minDistance = distance
                nearestInterval = interval
            }
        }
        
        let result = octave * 12 + (nearestInterval + rootOffset) % 12
        return UInt8(clamping: result)
    }
    
    /// Get all scale notes in a given octave
    func notes(in octave: Int, root: UInt8) -> [UInt8] {
        let rootOffset = Int(root) % 12
        return intervals.compactMap { interval in
            let pitch = octave * 12 + (interval + rootOffset) % 12
            guard pitch >= 0 && pitch <= 127 else { return nil }
            return UInt8(pitch)
        }
    }
    
    /// Get all scale notes in MIDI range
    func allNotes(root: UInt8) -> [UInt8] {
        var notes: [UInt8] = []
        for octave in -1...9 {
            notes.append(contentsOf: self.notes(in: octave + 1, root: root))
        }
        return notes.filter { MIDIHelper.pitchRange.contains($0) }
    }
}

// MARK: - Int Extension for Modulo

extension Int {
    /// Positive modulo (handles negative numbers correctly)
    func mod(_ n: Int) -> Int {
        let result = self % n
        return result >= 0 ? result : result + n
    }
}

