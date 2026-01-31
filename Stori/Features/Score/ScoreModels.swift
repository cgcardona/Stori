//
//  ScoreModels.swift
//  Stori
//
//  Core data models for music score notation
//  Maps MIDI data to traditional Western music notation
//

import SwiftUI

// MARK: - Score Configuration

/// Configuration for how the score should be displayed
struct ScoreConfiguration: Codable, Equatable {
    var clef: Clef = .treble
    var keySignature: KeySignature = .cMajor
    var timeSignature: ScoreTimeSignature = .common
    var tempo: Double = 120.0
    var showMeasureNumbers: Bool = true
    var showDynamics: Bool = true
    var showArticulations: Bool = true
    var staffSpacing: CGFloat = 10.0
}

// MARK: - Clef

/// Musical clef types
enum Clef: String, CaseIterable, Codable, Identifiable {
    case treble
    case bass
    case alto
    case tenor
    case percussion
    
    var id: String { rawValue }
    
    /// The MIDI pitch that sits on the middle line of the staff
    var middleLinePitch: UInt8 {
        switch self {
        case .treble: return 71    // B4
        case .bass: return 50      // D3
        case .alto: return 60      // C4 (middle C)
        case .tenor: return 57     // A3
        case .percussion: return 60
        }
    }
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .treble: return "Treble (G)"
        case .bass: return "Bass (F)"
        case .alto: return "Alto (C)"
        case .tenor: return "Tenor (C)"
        case .percussion: return "Percussion"
        }
    }
    
    /// SF Symbol for toolbar
    var iconName: String {
        switch self {
        case .treble: return "music.note"
        case .bass: return "music.note.list"
        case .alto: return "music.quarternote.3"
        case .tenor: return "music.mic"
        case .percussion: return "drum"
        }
    }
    
    /// Clef glyph (using Unicode musical symbols)
    /// Note: Percussion clef is drawn as custom bars in StaffRenderer
    var glyph: String {
        switch self {
        case .treble: return "𝄞"       // U+1D11E - G Clef (curl wraps line 1 = G4)
        case .bass: return "𝄢"         // U+1D122 - F Clef (dots straddle line 3 = F3)
        case .alto: return "𝄡"         // U+1D121 - C Clef (center points to line 2 = C4)
        case .tenor: return "𝄡"        // U+1D121 - C Clef (center points to line 1 = C4)
        case .percussion: return "||"  // Custom drawn as two vertical bars
        }
    }
}

// MARK: - Key Signature

/// Musical key signatures (circle of fifths)
struct KeySignature: Hashable, Codable, Identifiable {
    /// Number of sharps (positive) or flats (negative)
    let sharps: Int
    
    var id: Int { sharps }
    
    // Common key signatures
    static let cMajor = KeySignature(sharps: 0)
    static let gMajor = KeySignature(sharps: 1)
    static let dMajor = KeySignature(sharps: 2)
    static let aMajor = KeySignature(sharps: 3)
    static let eMajor = KeySignature(sharps: 4)
    static let bMajor = KeySignature(sharps: 5)
    static let fSharpMajor = KeySignature(sharps: 6)
    static let cSharpMajor = KeySignature(sharps: 7)
    
    static let fMajor = KeySignature(sharps: -1)
    static let bFlatMajor = KeySignature(sharps: -2)
    static let eFlatMajor = KeySignature(sharps: -3)
    static let aFlatMajor = KeySignature(sharps: -4)
    static let dFlatMajor = KeySignature(sharps: -5)
    static let gFlatMajor = KeySignature(sharps: -6)
    static let cFlatMajor = KeySignature(sharps: -7)
    
    /// All key signatures in circle of fifths order
    static var allKeys: [KeySignature] {
        (-7...7).map { KeySignature(sharps: $0) }
    }
    
    var displayName: String {
        switch sharps {
        case 0: return "C Major / A minor"
        case 1: return "G Major / E minor"
        case 2: return "D Major / B minor"
        case 3: return "A Major / F♯ minor"
        case 4: return "E Major / C♯ minor"
        case 5: return "B Major / G♯ minor"
        case 6: return "F♯ Major / D♯ minor"
        case 7: return "C♯ Major / A♯ minor"
        case -1: return "F Major / D minor"
        case -2: return "B♭ Major / G minor"
        case -3: return "E♭ Major / C minor"
        case -4: return "A♭ Major / F minor"
        case -5: return "D♭ Major / B♭ minor"
        case -6: return "G♭ Major / E♭ minor"
        case -7: return "C♭ Major / A♭ minor"
        default: return "Custom"
        }
    }
    
    /// Returns which note names have accidentals
    var accidentalNotes: [NoteName] {
        if sharps > 0 {
            // Sharps: F, C, G, D, A, E, B
            return Array([.f, .c, .g, .d, .a, .e, .b].prefix(sharps))
        } else if sharps < 0 {
            // Flats: B, E, A, D, G, C, F
            return Array([.b, .e, .a, .d, .g, .c, .f].prefix(-sharps))
        }
        return []
    }
    
    /// Check if a note name is affected by the key signature
    func needsAccidental(_ noteName: NoteName) -> Accidental? {
        if accidentalNotes.contains(noteName) {
            return sharps > 0 ? .sharp : .flat
        }
        return nil
    }
}

// MARK: - Score Time Signature

/// Musical time signature for score notation (extends the basic TimeSignature)
struct ScoreTimeSignature: Hashable, Codable {
    let beats: Int      // Numerator (e.g., 4 in 4/4)
    let beatValue: Int  // Denominator (e.g., 4 = quarter note)
    
    /// Common time signatures
    static let common = ScoreTimeSignature(beats: 4, beatValue: 4)      // 4/4
    static let cut = ScoreTimeSignature(beats: 2, beatValue: 2)         // 2/2
    static let waltz = ScoreTimeSignature(beats: 3, beatValue: 4)       // 3/4
    static let march = ScoreTimeSignature(beats: 2, beatValue: 4)       // 2/4
    static let compound6 = ScoreTimeSignature(beats: 6, beatValue: 8)   // 6/8
    static let compound9 = ScoreTimeSignature(beats: 9, beatValue: 8)   // 9/8
    static let compound12 = ScoreTimeSignature(beats: 12, beatValue: 8) // 12/8
    
    var displayString: String {
        "\(beats)/\(beatValue)"
    }
    
    /// Duration of one beat in quarter notes
    var beatDuration: Double {
        4.0 / Double(beatValue)
    }
    
    /// Total duration of one measure in quarter notes
    var measureDuration: Double {
        Double(beats) * beatDuration
    }
    
    /// Create from the basic TimeSignature model
    init(from timeSignature: TimeSignature) {
        self.beats = timeSignature.numerator
        self.beatValue = timeSignature.denominator
    }
    
    init(beats: Int, beatValue: Int) {
        self.beats = beats
        self.beatValue = beatValue
    }
}

// MARK: - Note Duration

/// Musical note durations (in terms of whole notes)
enum NoteDuration: Double, CaseIterable, Codable, Identifiable {
    case whole = 4.0
    case half = 2.0
    case quarter = 1.0
    case eighth = 0.5
    case sixteenth = 0.25
    case thirtySecond = 0.125
    case sixtyFourth = 0.0625
    
    var id: Double { rawValue }
    
    var displayName: String {
        switch self {
        case .whole: return "Whole"
        case .half: return "Half"
        case .quarter: return "Quarter"
        case .eighth: return "Eighth"
        case .sixteenth: return "16th"
        case .thirtySecond: return "32nd"
        case .sixtyFourth: return "64th"
        }
    }
    
    /// Number of flags/beams for notes shorter than quarter
    var flagCount: Int {
        switch self {
        case .whole, .half, .quarter: return 0
        case .eighth: return 1
        case .sixteenth: return 2
        case .thirtySecond: return 3
        case .sixtyFourth: return 4
        }
    }
    
    var hasStem: Bool {
        self != .whole
    }
    
    /// Notehead glyph (using Unicode musical symbols)
    var noteheadGlyph: String {
        switch self {
        case .whole: return "𝅝"       // U+1D15D - Musical Symbol Whole Note
        case .half: return "𝅗𝅥"        // U+1D157 U+1D165 - Half note
        default: return "♩"           // U+2669 - Quarter Note
        }
    }
    
    /// Rest glyph (using ASCII-safe representations)
    /// These are visual approximations that work on all systems
    var restGlyph: String {
        switch self {
        case .whole: return "━"      // Whole rest (box drawing heavy horizontal)
        case .half: return "▄"       // Half rest (lower half block)
        case .quarter: return "♩"    // Quarter rest (basic music note)
        case .eighth: return "♪"     // Eighth rest  (eighth note symbol)
        case .sixteenth: return "♬"  // Sixteenth rest (beamed eighth notes)
        case .thirtySecond: return "‰" // 32nd rest (per mille sign)
        case .sixtyFourth: return "‱"  // 64th rest (per ten thousand sign)
        }
    }
    
    /// Keyboard shortcut number (1-7)
    var shortcutNumber: Int {
        switch self {
        case .whole: return 1
        case .half: return 2
        case .quarter: return 3
        case .eighth: return 4
        case .sixteenth: return 5
        case .thirtySecond: return 6
        case .sixtyFourth: return 7
        }
    }
}

// MARK: - Note Name

/// Musical note names (pitch class)
enum NoteName: Int, CaseIterable, Codable {
    case c = 0, d = 2, e = 4, f = 5, g = 7, a = 9, b = 11
    
    var displayName: String {
        switch self {
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .a: return "A"
        case .b: return "B"
        }
    }
    
    /// Create from MIDI pitch (ignoring octave)
    static func from(midiPitch: UInt8) -> (name: NoteName, accidental: Accidental?) {
        let pitchClass = Int(midiPitch) % 12
        
        switch pitchClass {
        case 0: return (.c, nil)
        case 1: return (.c, .sharp)  // or D♭
        case 2: return (.d, nil)
        case 3: return (.d, .sharp)  // or E♭
        case 4: return (.e, nil)
        case 5: return (.f, nil)
        case 6: return (.f, .sharp)  // or G♭
        case 7: return (.g, nil)
        case 8: return (.g, .sharp)  // or A♭
        case 9: return (.a, nil)
        case 10: return (.a, .sharp) // or B♭
        case 11: return (.b, nil)
        default: return (.c, nil)
        }
    }
    
    /// Get the staff line offset from middle C
    var staffLineOffset: Int {
        switch self {
        case .c: return 0
        case .d: return 1
        case .e: return 2
        case .f: return 3
        case .g: return 4
        case .a: return 5
        case .b: return 6
        }
    }
}

// MARK: - Accidental

/// Musical accidentals
enum Accidental: String, Codable {
    case sharp
    case flat
    case natural
    case doubleSharp
    case doubleFlat
    
    var displaySymbol: String {
        switch self {
        case .sharp: return "♯"
        case .flat: return "♭"
        case .natural: return "♮"
        case .doubleSharp: return "𝄪"
        case .doubleFlat: return "𝄫"
        }
    }
    
    /// Accidental glyph (using Unicode musical symbols)
    var glyph: String {
        switch self {
        case .sharp: return "♯"        // U+266F - Music Sharp Sign
        case .flat: return "♭"         // U+266D - Music Flat Sign
        case .natural: return "♮"      // U+266E - Music Natural Sign
        case .doubleSharp: return "𝄪"  // U+1D12A - Musical Symbol Double Sharp
        case .doubleFlat: return "𝄫"   // U+1D12B - Musical Symbol Double Flat
        }
    }
    
    /// Pitch modification in semitones
    var semitones: Int {
        switch self {
        case .sharp: return 1
        case .flat: return -1
        case .natural: return 0
        case .doubleSharp: return 2
        case .doubleFlat: return -2
        }
    }
}

// MARK: - Stem Direction

enum StemDirection {
    case up
    case down
    case auto  // Determined by note position
    
    /// Calculate stem direction based on pitch and clef
    static func forPitch(_ pitch: UInt8, clef: Clef) -> StemDirection {
        // Notes above middle line get stems down, below get stems up
        if pitch >= clef.middleLinePitch {
            return .down
        } else {
            return .up
        }
    }
}

// MARK: - Articulation

enum Articulation: String, CaseIterable, Codable {
    case staccato
    case accent
    case tenuto
    case marcato
    case staccatissimo
    case fermata
    case trill
    case mordent
    case turn
    case upBow      // For strings
    case downBow    // For strings
    case breathMark
    
    var displayName: String {
        switch self {
        case .staccato: return "Staccato"
        case .accent: return "Accent"
        case .tenuto: return "Tenuto"
        case .marcato: return "Marcato"
        case .staccatissimo: return "Staccatissimo"
        case .fermata: return "Fermata"
        case .trill: return "Trill"
        case .mordent: return "Mordent"
        case .turn: return "Turn"
        case .upBow: return "Up Bow"
        case .downBow: return "Down Bow"
        case .breathMark: return "Breath Mark"
        }
    }
    
    /// Articulation glyph (using Unicode musical symbols)
    var glyph: String {
        switch self {
        case .staccato: return "•"      // Bullet point as staccato dot
        case .accent: return ">"        // Greater-than as accent
        case .tenuto: return "–"        // En-dash as tenuto line
        case .marcato: return "^"       // Caret as marcato
        case .staccatissimo: return "▾" // Small triangle
        case .fermata: return "𝄐"       // U+1D110 - Musical Symbol Fermata
        case .trill: return "tr"        // Text representation
        case .mordent: return "𝄔"       // U+1D114 - Musical Symbol Mordent
        case .turn: return "𝄕"          // U+1D115 - Musical Symbol Turn
        case .upBow: return "∨"         // V shape for up bow
        case .downBow: return "∏"       // Pi shape for down bow
        case .breathMark: return ","    // Comma for breath mark
        }
    }
    
    /// Whether articulation goes above or below the note
    var defaultPosition: ArticulationPosition {
        switch self {
        case .staccato, .accent, .tenuto, .marcato, .staccatissimo:
            return .nearNotehead
        case .fermata, .trill, .mordent, .turn:
            return .aboveStaff
        case .upBow, .downBow, .breathMark:
            return .aboveStaff
        }
    }
}

enum ArticulationPosition {
    case aboveStaff
    case belowStaff
    case nearNotehead  // Opposite side of stem
}

// MARK: - Dynamic

enum Dynamic: String, CaseIterable, Codable {
    case ppp, pp, p, mp, mf, f, ff, fff
    case sfz, fp, sfp, fz
    case crescendo, decrescendo
    
    var displayName: String {
        rawValue
    }
    
    /// Dynamic glyph (using italic text representation)
    var glyph: String {
        switch self {
        case .ppp: return "ppp"
        case .pp: return "pp"
        case .p: return "p"
        case .mp: return "mp"
        case .mf: return "mf"
        case .f: return "f"
        case .ff: return "ff"
        case .fff: return "fff"
        case .sfz: return "sfz"
        case .fp: return "fp"
        case .sfp: return "sfp"
        case .fz: return "fz"
        case .crescendo: return "<"    // Hairpin open
        case .decrescendo: return ">"  // Hairpin close
        }
    }
    
    /// Approximate MIDI velocity
    var velocity: UInt8 {
        switch self {
        case .ppp: return 16
        case .pp: return 33
        case .p: return 49
        case .mp: return 64
        case .mf: return 80
        case .f: return 96
        case .ff: return 112
        case .fff: return 127
        case .sfz, .fz: return 127
        case .fp, .sfp: return 112
        case .crescendo, .decrescendo: return 80
        }
    }
}

// MARK: - Score Note

/// A note as displayed in the score (derived from MIDINote)
struct ScoreNote: Identifiable, Equatable {
    let id: UUID
    let midiNoteId: UUID          // Reference to source MIDI note
    var pitch: UInt8
    var startBeat: Double         // Position in beats
    var displayDuration: NoteDuration
    var dotCount: Int = 0         // 0-2 dots
    var accidental: Accidental?   // Shown accidental (may differ from key signature)
    var tieToNext: Bool = false
    var tieFromPrevious: Bool = false
    var articulations: [Articulation] = []
    var dynamic: Dynamic?
    var velocity: UInt8 = 80
    var stemDirection: StemDirection = .auto
    var beamGroupId: UUID?        // For grouping beamed notes
    
    /// Total duration including dots
    var totalDuration: Double {
        var duration = displayDuration.rawValue
        var dotMultiplier = 0.5
        for _ in 0..<dotCount {
            duration += displayDuration.rawValue * dotMultiplier
            dotMultiplier *= 0.5
        }
        return duration
    }
    
    /// End beat position
    var endBeat: Double {
        startBeat + totalDuration
    }
    
    /// Get note name and octave
    var noteName: NoteName {
        NoteName.from(midiPitch: pitch).name
    }
    
    var octave: Int {
        Int(pitch) / 12 - 1  // MIDI 60 = C4
    }
    
    /// Full display name (e.g., "C4", "F#5")
    var fullDisplayName: String {
        let (name, acc) = NoteName.from(midiPitch: pitch)
        let accStr = acc?.displaySymbol ?? ""
        return "\(name.displayName)\(accStr)\(octave)"
    }
}

// MARK: - Score Rest

/// A rest in the score
struct ScoreRest: Identifiable, Equatable {
    let id = UUID()
    var startBeat: Double
    var duration: NoteDuration
    var dotCount: Int = 0
    
    var totalDuration: Double {
        var dur = duration.rawValue
        var dotMultiplier = 0.5
        for _ in 0..<dotCount {
            dur += duration.rawValue * dotMultiplier
            dotMultiplier *= 0.5
        }
        return dur
    }
}

// MARK: - Score Measure

/// A single measure of music
struct ScoreMeasure: Identifiable, Equatable {
    let id = UUID()
    var measureNumber: Int
    var notes: [ScoreNote] = []
    var rests: [ScoreRest] = []
    var keySignature: KeySignature?           // If changed from previous
    var timeSignature: ScoreTimeSignature?    // If changed from previous
    var tempoMarking: Double?            // If changed from previous
    var repeatStart: Bool = false
    var repeatEnd: Bool = false
    var endingNumber: Int?               // For 1st/2nd endings
    
    /// All elements sorted by start beat
    var sortedElements: [any ScoreElement] {
        let allElements: [any ScoreElement] = notes + rests
        return allElements.sorted { $0.startBeat < $1.startBeat }
    }
}

// MARK: - Score Element Protocol

protocol ScoreElement {
    var startBeat: Double { get }
    var totalDuration: Double { get }
}

extension ScoreNote: ScoreElement {}
extension ScoreRest: ScoreElement {}

// MARK: - Beam Group

/// A group of notes connected by beams
struct BeamGroup: Identifiable {
    let id = UUID()
    var notes: [ScoreNote]
    var beamCount: Int  // Number of beam lines (1 for 8ths, 2 for 16ths, etc.)
    
    var startBeat: Double {
        notes.first?.startBeat ?? 0
    }
    
    var endBeat: Double {
        notes.last?.endBeat ?? 0
    }
}

// MARK: - Tuplet

/// Tuplet group (triplets, etc.)
struct Tuplet: Identifiable {
    let id = UUID()
    var notes: [ScoreNote]
    var actualNotes: Int    // e.g., 3 for triplet
    var normalNotes: Int    // e.g., 2 for triplet (3 in the space of 2)
    var showNumber: Bool = true
    var showBracket: Bool = true
    
    var ratio: String {
        "\(actualNotes):\(normalNotes)"
    }
}

// MARK: - Staff System

/// A system of staves (for grand staff, orchestral scores, etc.)
struct StaffSystem: Identifiable {
    let id = UUID()
    var staves: [StaffData]
    var startMeasure: Int
    var endMeasure: Int
    
    struct StaffData: Identifiable {
        let id = UUID()
        var clef: Clef
        var measures: [ScoreMeasure]
        var name: String?  // e.g., "Piano RH", "Violin I"
    }
}

// MARK: - Pitch Helpers

extension UInt8 {
    /// Convert MIDI pitch to staff position (lines/spaces from middle C)
    func staffPosition(for clef: Clef) -> Int {
        let middleC: UInt8 = 60
        let (noteName, _) = NoteName.from(midiPitch: self)
        let octave = Int(self) / 12 - 1
        let middleCOctave = 4
        
        // Calculate position relative to middle C
        let octaveOffset = (octave - middleCOctave) * 7
        let noteOffset = noteName.staffLineOffset
        
        // Adjust for clef
        let clefOffset: Int
        switch clef {
        case .treble:
            clefOffset = -6  // Middle C is one ledger line below
        case .bass:
            clefOffset = 6   // Middle C is one ledger line above
        case .alto:
            clefOffset = 0   // Middle C is on the middle line
        case .tenor:
            clefOffset = 2   // Middle C is on the fourth line
        case .percussion:
            clefOffset = 0
        }
        
        return octaveOffset + noteOffset + clefOffset
    }
    
    /// Check if this pitch requires ledger lines
    func needsLedgerLines(for clef: Clef) -> Int {
        let position = staffPosition(for: clef)
        if position < -1 {
            return (-1 - position + 1) / 2  // Below staff
        } else if position > 9 {
            return (position - 9 + 1) / 2   // Above staff
        }
        return 0
    }
}

