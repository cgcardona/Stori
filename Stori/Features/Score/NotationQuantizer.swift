//
//  NotationQuantizer.swift
//  Stori
//
//  Converts MIDI notes to displayable score notation
//  Handles quantization, beam grouping, tuplet detection, and rest insertion
//

import Foundation

/// Engine for converting MIDI data to musical notation
/// 
/// ARCHITECTURE (Issue #67): This is a DISPLAY-ONLY converter.
/// - Creates ScoreNote objects for visual rendering
/// - NEVER modifies source MIDI data (preserves sub-beat precision)
/// - ScoreNotes reference MIDI notes via midiNoteId for bidirectional lookup
/// - Quantization is for display aesthetics, not data modification
class NotationQuantizer {
    
    // MARK: - Configuration
    
    var quantizeResolution: NoteDuration = .sixteenth
    var detectTuplets: Bool = true
    var autoBeam: Bool = true
    
    /// Engraver for intelligent layout
    private let engraver = NotationEngraver()
    
    
    // MARK: - Main Quantization
    
    /// Convert MIDI notes to score measures
    func quantize(
        notes: [MIDINote],
        timeSignature: ScoreTimeSignature,
        tempo: Double,
        keySignature: KeySignature = .cMajor
    ) -> [ScoreMeasure] {
        
        guard !notes.isEmpty else { return [] }
        
        // Note: MIDI note startTime, duration, and endTime are already in BEATS (not seconds!)
        // No conversion needed - just use the values directly
        guard timeSignature.measureDuration > 0 else { return [] }
        
        let measureDuration = timeSignature.measureDuration
        
        // Find the total duration (endTime is already in beats)
        let maxEndBeat = notes.map { $0.endBeat }.max() ?? 0
        let measureCount = min(100, max(1, Int(ceil(maxEndBeat / measureDuration)))) // Safety: limit to 100 measures
        
        // Create empty measures
        var measures: [ScoreMeasure] = (1...measureCount).map { num in
            ScoreMeasure(measureNumber: num)
        }
        
        // Convert each MIDI note to a score note
        // Note: startTime and duration are already in beats!
        for midiNote in notes {
            let startBeat = midiNote.startBeat
            let durationBeats = midiNote.durationBeats
            
            // Determine which measure this note starts in
            let measureIndex = Int(startBeat / measureDuration)
            guard measureIndex < measures.count else { continue }
            
            // Convert to score note
            let (duration, dots, needsTie) = determineNoteDuration(
                durationBeats: durationBeats,
                quantizeResolution: quantizeResolution
            )
            
            // Calculate accidental based on key signature
            let accidental = calculateAccidental(
                pitch: midiNote.pitch,
                keySignature: keySignature
            )
            
            let scoreNote = ScoreNote(
                id: UUID(),
                midiNoteId: midiNote.id,
                pitch: midiNote.pitch,
                startBeat: startBeat,
                displayDuration: duration,
                dotCount: dots,
                accidental: accidental,
                tieToNext: needsTie,
                velocity: midiNote.velocity
            )
            
            measures[measureIndex].notes.append(scoreNote)
            
            // Handle ties across measure boundaries
            if needsTie {
                addTiedNotes(
                    originalNote: scoreNote,
                    remainingDuration: durationBeats - duration.rawValue * (1.0 + Double(dots) * 0.5),
                    measures: &measures,
                    startMeasureIndex: measureIndex + 1,
                    measureDuration: measureDuration
                )
            }
        }
        
        // Sort notes within each measure
        for i in 0..<measures.count {
            measures[i].notes.sort { $0.startBeat < $1.startBeat }
        }
        
        // Insert rests where needed (disabled for MVP - cleaner score display)
        if false { // TODO: Make this configurable via ScoreConfiguration
            for i in 0..<measures.count {
                measures[i].rests = insertRests(
                    notes: measures[i].notes,
                    measureStartBeat: Double(i) * measureDuration,
                    measureDuration: measureDuration,
                    timeSignature: timeSignature
                )
            }
        }
        
        // Group beams
        if autoBeam {
            for i in 0..<measures.count {
                measures[i].notes = groupBeams(
                    notes: measures[i].notes,
                    timeSignature: timeSignature
                )
            }
        }
        
        // Apply intelligent engraving rules (stem directions, spacing, etc.)
        for i in 0..<measures.count {
            applyEngraving(to: &measures[i], clef: .treble, keySignature: keySignature)
        }
        
        return measures
    }
    
    // MARK: - Duration Calculation
    
    /// Determine the best note duration for a given MIDI duration
    func determineNoteDuration(
        durationBeats: Double,
        quantizeResolution: NoteDuration
    ) -> (duration: NoteDuration, dots: Int, needsTie: Bool) {
        
        let minDuration = quantizeResolution.rawValue
        
        // Try each duration from longest to shortest
        let durations: [(NoteDuration, Int)] = [
            (.whole, 2),      // Double-dotted whole
            (.whole, 1),      // Dotted whole
            (.whole, 0),      // Whole
            (.half, 2),       // Double-dotted half
            (.half, 1),       // Dotted half
            (.half, 0),       // Half
            (.quarter, 2),    // Double-dotted quarter
            (.quarter, 1),    // Dotted quarter
            (.quarter, 0),    // Quarter
            (.eighth, 1),     // Dotted eighth
            (.eighth, 0),     // Eighth
            (.sixteenth, 1),  // Dotted sixteenth
            (.sixteenth, 0),  // Sixteenth
            (.thirtySecond, 0),
            (.sixtyFourth, 0)
        ]
        
        for (duration, dots) in durations {
            let totalDuration = calculateDottedDuration(base: duration.rawValue, dots: dots)
            
            // If this duration fits and is >= our minimum resolution
            if totalDuration <= durationBeats + 0.001 && duration.rawValue >= minDuration {
                let needsTie = durationBeats - totalDuration > minDuration * 0.5
                return (duration, dots, needsTie)
            }
        }
        
        // Default to the quantize resolution
        return (quantizeResolution, 0, durationBeats > quantizeResolution.rawValue * 1.5)
    }
    
    private func calculateDottedDuration(base: Double, dots: Int) -> Double {
        var total = base
        var addition = base * 0.5
        for _ in 0..<dots {
            total += addition
            addition *= 0.5
        }
        return total
    }
    
    // MARK: - Accidental Calculation
    
    /// Calculate whether a note needs an explicit accidental
    func calculateAccidental(pitch: UInt8, keySignature: KeySignature) -> Accidental? {
        let (noteName, naturalAccidental) = NoteName.from(midiPitch: pitch)
        let keyAccidental = keySignature.needsAccidental(noteName)
        
        // If the note has an accidental not in the key signature, show it
        if let natural = naturalAccidental {
            if keyAccidental != natural {
                return natural
            }
            // If it matches the key signature, don't show it
            return nil
        } else {
            // Natural note - show natural if key signature would make it sharp/flat
            if keyAccidental != nil {
                return .natural
            }
            return nil
        }
    }
    
    // MARK: - Tie Handling
    
    private func addTiedNotes(
        originalNote: ScoreNote,
        remainingDuration: Double,
        measures: inout [ScoreMeasure],
        startMeasureIndex: Int,
        measureDuration: Double
    ) {
        guard remainingDuration > 0.01, startMeasureIndex < measures.count else { return }
        
        var remaining = remainingDuration
        var currentMeasure = startMeasureIndex
        var currentBeat = Double(currentMeasure) * measureDuration
        
        while remaining > 0.01 && currentMeasure < measures.count {
            let (duration, dots, needsMoreTie) = determineNoteDuration(
                durationBeats: min(remaining, measureDuration),
                quantizeResolution: quantizeResolution
            )
            
            let actualDuration = calculateDottedDuration(base: duration.rawValue, dots: dots)
            
            let tiedNote = ScoreNote(
                id: UUID(),
                midiNoteId: originalNote.midiNoteId,
                pitch: originalNote.pitch,
                startBeat: currentBeat,
                displayDuration: duration,
                dotCount: dots,
                tieToNext: needsMoreTie && remaining - actualDuration > 0.01,
                tieFromPrevious: true,
                velocity: originalNote.velocity
            )
            
            measures[currentMeasure].notes.append(tiedNote)
            
            remaining -= actualDuration
            currentBeat += actualDuration
            
            if currentBeat >= Double(currentMeasure + 1) * measureDuration {
                currentMeasure += 1
                currentBeat = Double(currentMeasure) * measureDuration
            }
        }
    }
    
    // MARK: - Rest Insertion
    
    /// Insert rests to fill gaps between notes
    func insertRests(
        notes: [ScoreNote],
        measureStartBeat: Double,
        measureDuration: Double,
        timeSignature: ScoreTimeSignature
    ) -> [ScoreRest] {
        
        var rests: [ScoreRest] = []
        var currentBeat = measureStartBeat
        let measureEndBeat = measureStartBeat + measureDuration
        
        // Sort notes by start beat
        let sortedNotes = notes.sorted { $0.startBeat < $1.startBeat }
        
        for note in sortedNotes {
            // Insert rest if there's a gap
            if note.startBeat > currentBeat + 0.01 {
                let gapDuration = note.startBeat - currentBeat
                let gapRests = createRestsForDuration(
                    duration: gapDuration,
                    startBeat: currentBeat
                )
                rests.append(contentsOf: gapRests)
            }
            
            // Move current position past this note
            currentBeat = max(currentBeat, note.endBeat)
        }
        
        // Fill remaining measure with rests
        if currentBeat < measureEndBeat - 0.01 {
            let gapDuration = measureEndBeat - currentBeat
            let gapRests = createRestsForDuration(
                duration: gapDuration,
                startBeat: currentBeat
            )
            rests.append(contentsOf: gapRests)
        }
        
        return rests
    }
    
    private func createRestsForDuration(duration: Double, startBeat: Double) -> [ScoreRest] {
        var rests: [ScoreRest] = []
        var remaining = duration
        var currentBeat = startBeat
        
        // Use largest possible rests
        let restDurations: [NoteDuration] = [
            .whole, .half, .quarter, .eighth, .sixteenth, .thirtySecond, .sixtyFourth
        ]
        
        // Safety: limit iterations to prevent infinite loops
        var iterations = 0
        let maxIterations = 100
        
        while remaining > 0.01 && iterations < maxIterations {
            iterations += 1
            var foundRest = false
            
            for restDuration in restDurations {
                if restDuration.rawValue <= remaining + 0.01 {
                    rests.append(ScoreRest(
                        startBeat: currentBeat,
                        duration: restDuration
                    ))
                    remaining -= restDuration.rawValue
                    currentBeat += restDuration.rawValue
                    foundRest = true
                    break
                }
            }
            
            // If no rest fits, break to prevent infinite loop
            if !foundRest {
                break
            }
        }
        
        return rests
    }
    
    // MARK: - Beam Grouping
    
    /// Group notes that should be beamed together
    func groupBeams(
        notes: [ScoreNote],
        timeSignature: ScoreTimeSignature
    ) -> [ScoreNote] {
        
        var result = notes
        
        // Find sequences of beamable notes (eighth notes or shorter)
        var beamableSequences: [[Int]] = []
        var currentSequence: [Int] = []
        
        for (index, note) in notes.enumerated() {
            if note.displayDuration.flagCount > 0 {
                currentSequence.append(index)
            } else {
                if currentSequence.count >= 2 {
                    beamableSequences.append(currentSequence)
                }
                currentSequence = []
            }
        }
        
        if currentSequence.count >= 2 {
            beamableSequences.append(currentSequence)
        }
        
        // Assign beam group IDs
        for sequence in beamableSequences {
            let groupId = UUID()
            for index in sequence {
                result[index].beamGroupId = groupId
            }
        }
        
        return result
    }
    
    // MARK: - Tuplet Detection
    
    /// Detect triplets and other tuplets in the note sequence
    func detectTuplets(notes: [ScoreNote], tempo: Double) -> [Tuplet] {
        var tuplets: [Tuplet] = []
        
        // Look for patterns that suggest triplets
        // This is a simplified implementation - a full implementation would
        // analyze timing ratios more carefully
        
        var i = 0
        while i < notes.count - 2 {
            let note1 = notes[i]
            let note2 = notes[i + 1]
            let note3 = notes[i + 2]
            
            // Check if three notes span roughly the duration of two
            let totalDuration = note3.endBeat - note1.startBeat
            let expectedTripletDuration = note1.displayDuration.rawValue * 2
            
            let ratio = totalDuration / expectedTripletDuration
            if ratio > 0.9 && ratio < 1.1 {
                // Likely a triplet
                tuplets.append(Tuplet(
                    notes: [note1, note2, note3],
                    actualNotes: 3,
                    normalNotes: 2
                ))
                i += 3
            } else {
                i += 1
            }
        }
        
        return tuplets
    }
    
    // MARK: - Engraving Application
    
    /// Apply intelligent engraving rules to a measure
    private func applyEngraving(
        to measure: inout ScoreMeasure,
        clef: Clef,
        keySignature: KeySignature
    ) {
        // Calculate stem directions based on note positions
        for i in 0..<measure.notes.count {
            let neighbors = Array(measure.notes.prefix(i))
            measure.notes[i].stemDirection = engraver.calculateStemDirection(
                for: measure.notes[i],
                clef: clef,
                neighborNotes: neighbors
            )
        }
        
        // For beamed groups, unify stem direction
        var beamGroups: [UUID: [Int]] = [:]
        for (index, note) in measure.notes.enumerated() {
            if let groupId = note.beamGroupId {
                beamGroups[groupId, default: []].append(index)
            }
        }
        
        for (_, indices) in beamGroups {
            let groupNotes = indices.map { measure.notes[$0] }
            let groupDirection = engraver.calculateGroupStemDirection(notes: groupNotes, clef: clef)
            
            for index in indices {
                measure.notes[index].stemDirection = groupDirection
            }
        }
    }
}

// MARK: - Convenience Extensions

extension NotationQuantizer {
    
    /// Quick quantize with default settings
    static func quickQuantize(
        midiNotes: [MIDINote],
        tempo: Double = 120.0
    ) -> [ScoreMeasure] {
        let quantizer = NotationQuantizer()
        return quantizer.quantize(
            notes: midiNotes,
            timeSignature: ScoreTimeSignature.common,
            tempo: tempo
        )
    }
}

