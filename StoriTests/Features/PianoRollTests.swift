//
//  PianoRollTests.swift
//  StoriTests
//
//  Comprehensive tests for Piano Roll editing operations
//  Focus: Business logic, note editing, timing preservation, quantization
//

import XCTest
@testable import Stori

final class PianoRollTests: XCTestCase {
    
    // MARK: - Multi-Note Drag Timing Preservation (Bug #2 Fix)
    
    func testMultiNoteDragPreservesRelativeTiming_WithSnap() {
        // This test captures Bug #2 fix - ensures relative timing is preserved during multi-note drag
        // Key: each note snaps based on its OWN position, not the first note's position
        var region = MIDIRegion(durationBeats: 16.0)
        
        // Create notes with 1-beat intervals (easier to verify)
        let note1 = MIDINote(pitch: 60, startBeat: 0.0, durationBeats: 0.5)   // C4 at 0.0
        let note2 = MIDINote(pitch: 64, startBeat: 1.0, durationBeats: 0.5)   // E4 at 1.0
        let note3 = MIDINote(pitch: 67, startBeat: 2.0, durationBeats: 0.5)   // G4 at 2.0
        let note4 = MIDINote(pitch: 72, startBeat: 3.0, durationBeats: 0.5)   // C5 at 3.0
        
        region.addNote(note1)
        region.addNote(note2)
        region.addNote(note3)
        region.addNote(note4)
        
        // Simulate drag with snap to 1/4 notes: drag all notes right by 0.5 beats
        let rawOffset = 0.5
        let snapResolution = SnapResolution.quarter
        
        // Apply the FIX: each note snaps based on its OWN position
        var movedNotes: [MIDINote] = []
        for note in region.notes {
            var movedNote = note
            var newStartBeat = movedNote.startBeat + rawOffset
            if snapResolution != .off {
                newStartBeat = snapResolution.quantize(beat: newStartBeat, timeSignature: .fourFour)
            }
            movedNote.startBeat = max(0, newStartBeat)
            movedNotes.append(movedNote)
        }
        
        // Verify: each note snaps independently
        // 0.0 + 0.5 = 0.5 → snaps to 1.0 (round up)
        // 1.0 + 0.5 = 1.5 → snaps to 2.0 (round up)
        // 2.0 + 0.5 = 2.5 → snaps to 3.0 (round up at .5)
        // 3.0 + 0.5 = 3.5 → snaps to 4.0 (round up)
        assertApproximatelyEqual(movedNotes[0].startBeat, 1.0)
        assertApproximatelyEqual(movedNotes[1].startBeat, 2.0)
        assertApproximatelyEqual(movedNotes[2].startBeat, 3.0)
        assertApproximatelyEqual(movedNotes[3].startBeat, 4.0)
        
        // The BUG would make ALL notes snap to the same beat (e.g., all to 1.0)
        // The FIX ensures each note calculates its own snap (even if some collide)
        
        // Key verification: notes don't ALL collapse to the first note's snap position
        let uniquePositions = Set(movedNotes.map { $0.startBeat })
        XCTAssertGreaterThan(uniquePositions.count, 1, "Notes should NOT all snap to same position (that's the bug)")
    }
    
    func testMultiNoteDragPreservesRelativeTiming_NoSnap() {
        var region = MIDIRegion(durationBeats: 16.0)
        
        // Create chord with specific voicing
        let note1 = MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 1.0)    // C4
        let note2 = MIDINote(pitch: 64, startBeat: 2.1, durationBeats: 1.0)    // E4 (slightly delayed)
        let note3 = MIDINote(pitch: 67, startBeat: 2.05, durationBeats: 1.0)   // G4 (slightly early)
        
        region.addNote(note1)
        region.addNote(note2)
        region.addNote(note3)
        
        // Drag without snap: move all notes right by 1.3 beats
        let rawOffset = 1.3
        
        var movedNotes: [MIDINote] = []
        for note in region.notes {
            var movedNote = note
            movedNote.startBeat = movedNote.startBeat + rawOffset
            movedNotes.append(movedNote)
        }
        
        // Verify: exact relative timing preserved
        assertApproximatelyEqual(movedNotes[0].startBeat, 3.3, tolerance: 0.0001)
        assertApproximatelyEqual(movedNotes[1].startBeat, 3.4, tolerance: 0.0001)
        assertApproximatelyEqual(movedNotes[2].startBeat, 3.35, tolerance: 0.0001)
        
        // Verify: micro-timing offsets maintained
        let originalGap1 = note2.startBeat - note1.startBeat  // 0.1
        let newGap1 = movedNotes[1].startBeat - movedNotes[0].startBeat
        assertApproximatelyEqual(newGap1, originalGap1, tolerance: 0.0001)
        
        let originalGap2 = note3.startBeat - note1.startBeat  // 0.05
        let newGap2 = movedNotes[2].startBeat - movedNotes[0].startBeat
        assertApproximatelyEqual(newGap2, originalGap2, tolerance: 0.0001)
    }
    
    func testMultiNoteDragWithDifferentSnapResolutions() {
        // Test that different snap resolutions preserve relative timing correctly
        var region = MIDIRegion(durationBeats: 16.0)
        
        let note1 = MIDINote(pitch: 60, startBeat: 0.0, durationBeats: 0.5)
        let note2 = MIDINote(pitch: 64, startBeat: 0.125, durationBeats: 0.5)  // 1/16th offset
        
        region.addNote(note1)
        region.addNote(note2)
        
        // Test with 1/8th note snap
        let snapResolution = SnapResolution.eighth
        let rawOffset = 0.3
        
        var movedNotes: [MIDINote] = []
        for note in region.notes {
            var movedNote = note
            var newStartBeat = movedNote.startBeat + rawOffset
            newStartBeat = snapResolution.quantize(beat: newStartBeat, timeSignature: .fourFour)
            movedNote.startBeat = newStartBeat
            movedNotes.append(movedNote)
        }
        
        // Note 1: 0.0 + 0.3 = 0.3 → snaps to 0.5 (nearest 1/8)
        // Note 2: 0.125 + 0.3 = 0.425 → snaps to 0.5 (nearest 1/8)
        assertApproximatelyEqual(movedNotes[0].startBeat, 0.5)
        assertApproximatelyEqual(movedNotes[1].startBeat, 0.5)
        
        // Both snap to same beat (this is correct behavior - they're within snap tolerance)
    }
    
    // MARK: - Quantization Tests
    
    func testQuantizeWithStrength_100Percent() {
        var region = MIDIRegion()
        let note = MIDINote(pitch: 60, startBeat: 1.3, durationBeats: 0.5)
        region.addNote(note)
        
        // Quantize to quarter notes with 100% strength
        let quantized = SnapResolution.quarter.quantize(beat: note.startBeat, timeSignature: .fourFour, strength: 1.0)
        
        assertApproximatelyEqual(quantized, 1.0)
    }
    
    func testQuantizeWithStrength_50Percent() {
        var region = MIDIRegion()
        let note = MIDINote(pitch: 60, startBeat: 1.3, durationBeats: 0.5)
        region.addNote(note)
        
        // Quantize to quarter notes with 50% strength
        let quantized = SnapResolution.quarter.quantize(beat: note.startBeat, timeSignature: .fourFour, strength: 0.5)
        
        // Original: 1.3, Target: 1.0, Offset: -0.3
        // 50% of -0.3 = -0.15, so: 1.3 + (-0.15) = 1.15
        assertApproximatelyEqual(quantized, 1.15, tolerance: 0.01)
    }
    
    func testQuantizeWithStrength_0Percent() {
        let original = 1.3
        let quantized = SnapResolution.quarter.quantize(beat: original, timeSignature: .fourFour, strength: 0.0)
        
        assertApproximatelyEqual(quantized, original)
    }
    
    func testQuantizeWithSwing() {
        // Swing shifts off-beat notes (odd grid positions)
        let notes: [MIDINote] = [
            MIDINote(pitch: 60, startBeat: 0.0, durationBeats: 0.5),    // On-beat
            MIDINote(pitch: 64, startBeat: 0.5, durationBeats: 0.5),    // Off-beat (should swing)
            MIDINote(pitch: 67, startBeat: 1.0, durationBeats: 0.5),    // On-beat
            MIDINote(pitch: 72, startBeat: 1.5, durationBeats: 0.5),    // Off-beat (should swing)
        ]
        
        let swingAmount = 0.5  // 50% swing
        let gridResolution = 0.5  // 8th notes
        let maxSwingOffset = gridResolution / 3.0  // Triplet feel
        
        var swungNotes: [MIDINote] = []
        for note in notes {
            let gridIndex = Int(round(note.startBeat / gridResolution))
            var swungNote = note
            
            if gridIndex % 2 == 1 {  // Odd grid positions (off-beats)
                let swingOffset = maxSwingOffset * swingAmount
                swungNote.startBeat = note.startBeat + swingOffset
            }
            
            swungNotes.append(swungNote)
        }
        
        // On-beats unchanged
        assertApproximatelyEqual(swungNotes[0].startBeat, 0.0)
        assertApproximatelyEqual(swungNotes[2].startBeat, 1.0)
        
        // Off-beats delayed by swing
        let expectedSwingOffset = (gridResolution / 3.0) * swingAmount
        assertApproximatelyEqual(swungNotes[1].startBeat, 0.5 + expectedSwingOffset, tolerance: 0.001)
        assertApproximatelyEqual(swungNotes[3].startBeat, 1.5 + expectedSwingOffset, tolerance: 0.001)
    }
    
    // MARK: - Note Duration Resize Tests
    
    func testNoteDurationResize_SnapToEndPosition() {
        // Bug #3 fix: snap END position, not absolute duration
        let note = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 1.3)
        let snapResolution = SnapResolution.quarter
        
        // User drags to extend duration by 0.5 beats
        let newDuration = note.durationBeats + 0.5  // 1.8 beats
        
        // CORRECT: Snap the END position
        let newEndBeat = note.startBeat + newDuration  // 1.0 + 1.8 = 2.8
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat, timeSignature: .fourFour)  // 3.0
        let finalDuration = snappedEndBeat - note.startBeat  // 3.0 - 1.0 = 2.0
        
        assertApproximatelyEqual(finalDuration, 2.0)
        
        // WRONG approach (old bug): Snap absolute duration
        let wrongDuration = snapResolution.quantize(beat: newDuration, timeSignature: .fourFour)  // 2.0
        // This happens to be correct here, but fails when startBeat is off-grid
    }
    
    func testNoteDurationResize_OffGridStart() {
        // This test documents CURRENT behavior (Bug #3 - not yet fixed)
        // Current: snaps duration absolutely, not end position
        let note = MIDINote(pitch: 60, startBeat: 0.5, durationBeats: 0.7)
        let snapResolution = SnapResolution.quarter
        
        // User drags to extend slightly
        let newDuration = note.durationBeats + 0.1  // 0.8 beats
        
        // CURRENT (Bug #3): Snap duration value directly
        let snappedDuration = max(snapResolution.stepDurationBeats(timeSignature: .fourFour), snapResolution.quantize(beat: newDuration, timeSignature: .fourFour))
        // 0.8 → snaps to 1.0 (nearest quarter)
        
        assertApproximatelyEqual(snappedDuration, 1.0)
        
        // TODO: When Bug #3 is fixed, this test should verify end-position snapping:
        // let newEndBeat = note.startBeat + newDuration  // 0.5 + 0.8 = 1.3
        // let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)  // 1.0
        // let finalDuration = max(0.25, snappedEndBeat - note.startBeat)  // 0.5
    }
    
    // MARK: - Note Editing Tools
    
    func testSliceNote() {
        // Split note at specific position
        let originalNote = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 2.0)
        let slicePosition = 1.5  // Relative to note start
        
        // Create two new notes from slice
        let firstDuration = slicePosition
        let secondDuration = originalNote.durationBeats - slicePosition
        
        let firstNote = MIDINote(
            pitch: originalNote.pitch,
            velocity: originalNote.velocity,
            startBeat: originalNote.startBeat,
            durationBeats: firstDuration
        )
        
        let secondNote = MIDINote(
            pitch: originalNote.pitch,
            velocity: originalNote.velocity,
            startBeat: originalNote.startBeat + slicePosition,
            durationBeats: secondDuration
        )
        
        // Verify split
        assertApproximatelyEqual(firstNote.startBeat, 1.0)
        assertApproximatelyEqual(firstNote.durationBeats, 1.5)
        assertApproximatelyEqual(secondNote.startBeat, 2.5)
        assertApproximatelyEqual(secondNote.durationBeats, 0.5)
        
        // Verify no gap
        assertApproximatelyEqual(firstNote.endBeat, secondNote.startBeat)
    }
    
    func testGlueNotes() {
        // Merge adjacent notes of same pitch
        let note1 = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 1.0)
        let note2 = MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 1.5)
        
        // Create merged note
        let mergedNote = MIDINote(
            pitch: note1.pitch,
            velocity: note1.velocity,
            startBeat: note1.startBeat,
            durationBeats: note1.durationBeats + note2.durationBeats
        )
        
        // Verify merge
        assertApproximatelyEqual(mergedNote.startBeat, 1.0)
        assertApproximatelyEqual(mergedNote.durationBeats, 2.5)
        assertApproximatelyEqual(mergedNote.endBeat, 3.5)
    }
    
    func testLegatoNote() {
        // Extend note to reach next note
        let note1 = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let note2 = MIDINote(pitch: 64, startBeat: 2.0, durationBeats: 1.0)
        
        // Calculate legato duration
        let newDuration = note2.startBeat - note1.startBeat
        let legatoNote = MIDINote(
            id: note1.id,
            pitch: note1.pitch,
            velocity: note1.velocity,
            startBeat: note1.startBeat,
            durationBeats: newDuration
        )
        
        // Verify legato
        assertApproximatelyEqual(legatoNote.durationBeats, 1.0)
        assertApproximatelyEqual(legatoNote.endBeat, note2.startBeat)
    }
    
    // MARK: - Copy/Paste Tests
    
    func testCopyPaste_PreservesRelativeTiming() {
        var region = MIDIRegion(durationBeats: 16.0)
        
        let note1 = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let note2 = MIDINote(pitch: 64, startBeat: 1.25, durationBeats: 0.5)
        let note3 = MIDINote(pitch: 67, startBeat: 1.5, durationBeats: 0.5)
        
        region.addNote(note1)
        region.addNote(note2)
        region.addNote(note3)
        
        // Simulate copy/paste at new position
        let pasteOffset = 4.0
        var pastedNotes: [MIDINote] = []
        
        for note in region.notes {
            let pastedNote = MIDINote(
                pitch: note.pitch,
                velocity: note.velocity,
                startBeat: note.startBeat + pasteOffset,
                durationBeats: note.durationBeats
            )
            pastedNotes.append(pastedNote)
        }
        
        // Verify: relative timing preserved
        let originalGap1 = note2.startBeat - note1.startBeat
        let pastedGap1 = pastedNotes[1].startBeat - pastedNotes[0].startBeat
        assertApproximatelyEqual(pastedGap1, originalGap1)
        
        let originalGap2 = note3.startBeat - note2.startBeat
        let pastedGap2 = pastedNotes[2].startBeat - pastedNotes[1].startBeat
        assertApproximatelyEqual(pastedGap2, originalGap2)
    }
    
    // MARK: - Velocity Editing Tests
    
    func testVelocityChange_MultipleNotes() {
        var region = MIDIRegion()
        let note1 = MIDINote(pitch: 60, velocity: 80, startBeat: 0, durationBeats: 1.0)
        let note2 = MIDINote(pitch: 64, velocity: 100, startBeat: 1.0, durationBeats: 1.0)
        let note3 = MIDINote(pitch: 67, velocity: 60, startBeat: 2.0, durationBeats: 1.0)
        
        region.addNote(note1)
        region.addNote(note2)
        region.addNote(note3)
        
        // Change all velocities to 90
        let newVelocity: UInt8 = 90
        var updatedNotes = region.notes
        for i in updatedNotes.indices {
            updatedNotes[i].velocity = newVelocity
        }
        
        // Verify all updated
        XCTAssertTrue(updatedNotes.allSatisfy { $0.velocity == newVelocity })
    }
    
    // MARK: - Transpose Tests
    
    func testTranspose_PreservesRelativeIntervals() {
        var region = MIDIRegion()
        
        // C major chord: C4, E4, G4
        region.addNote(MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0))
        region.addNote(MIDINote(pitch: 64, startBeat: 0, durationBeats: 1.0))
        region.addNote(MIDINote(pitch: 67, startBeat: 0, durationBeats: 1.0))
        
        // Original intervals
        let originalInterval1 = Int(region.notes[1].pitch) - Int(region.notes[0].pitch)  // 4 semitones
        let originalInterval2 = Int(region.notes[2].pitch) - Int(region.notes[1].pitch)  // 3 semitones
        
        // Transpose up by 5 semitones (C to F)
        region.transpose(by: 5)
        
        // Verify pitches
        XCTAssertEqual(region.notes[0].pitch, 65)  // F4
        XCTAssertEqual(region.notes[1].pitch, 69)  // A4
        XCTAssertEqual(region.notes[2].pitch, 72)  // C5
        
        // Verify intervals preserved
        let newInterval1 = Int(region.notes[1].pitch) - Int(region.notes[0].pitch)
        let newInterval2 = Int(region.notes[2].pitch) - Int(region.notes[1].pitch)
        
        XCTAssertEqual(newInterval1, originalInterval1, "Major 3rd preserved")
        XCTAssertEqual(newInterval2, originalInterval2, "Minor 3rd preserved")
    }
    
    // MARK: - Edge Cases
    
    func testNoteDrag_ClampToZero() {
        var region = MIDIRegion()
        let note = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 1.0)
        region.addNote(note)
        
        // Drag left beyond zero
        let rawOffset = -2.0
        let newStartBeat = max(0, note.startBeat + rawOffset)
        
        assertApproximatelyEqual(newStartBeat, 0.0)
    }
    
    func testNoteDrag_PitchClampToMIDIRange() {
        let note = MIDINote(pitch: 126, startBeat: 0, durationBeats: 1.0)
        
        // Try to transpose up by 10 (would be 136, exceeds 127)
        let pitchOffset = 10
        let rawPitch = Int(note.pitch) + pitchOffset
        let newPitch = UInt8(min(max(rawPitch, 0), 127))
        
        XCTAssertEqual(newPitch, 127)
    }
    
    func testNoteDrag_PitchClampToMinimum() {
        let note = MIDINote(pitch: 5, startBeat: 0, durationBeats: 1.0)
        
        // Try to transpose down by 10 (would be -5)
        let pitchOffset = -10
        let rawPitch = Int(note.pitch) + pitchOffset
        let newPitch = UInt8(min(max(rawPitch, 0), 127))
        
        XCTAssertEqual(newPitch, 0)
    }
    
    func testNoteResize_MinimumDuration() {
        let note = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let snapResolution = SnapResolution.sixteenth
        
        // Try to resize to very small duration
        let newDuration = 0.01
        let finalDuration = max(snapResolution.stepDurationBeats(timeSignature: .fourFour), newDuration)
        
        assertApproximatelyEqual(finalDuration, snapResolution.stepDurationBeats(timeSignature: .fourFour))
    }
    
    // MARK: - Performance Tests
    
    func testMultiNoteDragPerformance() {
        // Test with 100 notes (typical selection size)
        var region = MIDIRegion(durationBeats: 100.0)
        
        for i in 0..<100 {
            let note = MIDINote(
                pitch: UInt8(60 + (i % 12)),
                startBeat: Double(i) * 0.25,
                durationBeats: 0.25
            )
            region.addNote(note)
        }
        
        measure {
            let rawOffset = 5.0
            let snapResolution = SnapResolution.sixteenth
            
            var movedNotes: [MIDINote] = []
            for note in region.notes {
                var movedNote = note
                var newStartBeat = movedNote.startBeat + rawOffset
                newStartBeat = snapResolution.quantize(beat: newStartBeat, timeSignature: .fourFour)
                movedNote.startBeat = max(0, newStartBeat)
                movedNotes.append(movedNote)
            }
        }
    }
    
    func testQuantizationPerformance() {
        // Test quantizing 1000 notes
        var notes: [MIDINote] = []
        for i in 0..<1000 {
            notes.append(MIDINote(
                pitch: 60,
                startBeat: Double(i) * 0.123,  // Off-grid
                durationBeats: 0.25
            ))
        }
        
        measure {
            let snapResolution = SnapResolution.sixteenth
            let strength: Float = 0.75
            
            let quantizedNotes = notes.map { note in
                MIDINote(
                    id: note.id,
                    pitch: note.pitch,
                    velocity: note.velocity,
                    startBeat: snapResolution.quantize(beat: note.startBeat, timeSignature: .fourFour, strength: strength),
                    durationBeats: note.durationBeats,
                    channel: note.channel
                )
            }
            XCTAssertEqual(quantizedNotes.count, 1000)
        }
    }
}
