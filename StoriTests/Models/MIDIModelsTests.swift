//
//  MIDIModelsTests.swift
//  StoriTests
//
//  Unit tests for MIDIModels.swift - MIDI data models
//

import XCTest
@testable import Stori

final class MIDIModelsTests: XCTestCase {
    
    // MARK: - MIDINote Tests
    
    func testMIDINoteInitialization() {
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 1.0)
        
        XCTAssertEqual(note.pitch, 60)
        XCTAssertEqual(note.velocity, 100)
        XCTAssertEqual(note.startBeat, 0)
        XCTAssertEqual(note.durationBeats, 1.0)
        XCTAssertEqual(note.channel, 0)
    }
    
    func testMIDINoteEndTime() {
        let note = MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 1.5)
        XCTAssertEqual(note.endBeat, 3.5)
    }
    
    func testMIDINoteOctave() {
        // C4 = MIDI 60
        let c4 = MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0)
        XCTAssertEqual(c4.octave, 4)
        
        // C-1 = MIDI 0
        let cMinus1 = MIDINote(pitch: 0, startBeat: 0, durationBeats: 1.0)
        XCTAssertEqual(cMinus1.octave, -1)
        
        // G9 = MIDI 127
        let g9 = MIDINote(pitch: 127, startBeat: 0, durationBeats: 1.0)
        XCTAssertEqual(g9.octave, 9)
    }
    
    func testMIDINoteInOctave() {
        // C = 0, C# = 1, D = 2, etc.
        let c = MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0)  // C4
        XCTAssertEqual(c.noteInOctave, 0)
        
        let fSharp = MIDINote(pitch: 66, startBeat: 0, durationBeats: 1.0)  // F#4
        XCTAssertEqual(fSharp.noteInOctave, 6)
        
        let b = MIDINote(pitch: 71, startBeat: 0, durationBeats: 1.0)  // B4
        XCTAssertEqual(b.noteInOctave, 11)
    }
    
    func testMIDINoteIsBlackKey() {
        // White keys: C, D, E, F, G, A, B (0, 2, 4, 5, 7, 9, 11)
        let c = MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0)
        XCTAssertFalse(c.isBlackKey)
        
        // Black keys: C#, D#, F#, G#, A# (1, 3, 6, 8, 10)
        let cSharp = MIDINote(pitch: 61, startBeat: 0, durationBeats: 1.0)
        XCTAssertTrue(cSharp.isBlackKey)
        
        let fSharp = MIDINote(pitch: 66, startBeat: 0, durationBeats: 1.0)
        XCTAssertTrue(fSharp.isBlackKey)
    }
    
    func testMIDINoteFrequency() {
        // A4 = 440 Hz
        let a4 = MIDINote(pitch: 69, startBeat: 0, durationBeats: 1.0)
        assertApproximatelyEqual(a4.frequencyHz, 440.0, tolerance: 0.01)
        
        // A5 = 880 Hz (one octave up)
        let a5 = MIDINote(pitch: 81, startBeat: 0, durationBeats: 1.0)
        assertApproximatelyEqual(a5.frequencyHz, 880.0, tolerance: 0.01)
        
        // A3 = 220 Hz (one octave down)
        let a3 = MIDINote(pitch: 57, startBeat: 0, durationBeats: 1.0)
        assertApproximatelyEqual(a3.frequencyHz, 220.0, tolerance: 0.01)
    }
    
    func testMIDINoteCodable() {
        let note = MIDINote(pitch: 64, velocity: 80, startBeat: 1.5, durationBeats: 0.5, channel: 2)
        assertCodableRoundTrip(note)
    }
    
    func testMIDINoteFromNoteName() {
        let c4 = MIDINote.fromNoteName("C4", velocity: 100, startBeat: 0, durationBeats: 1.0)
        XCTAssertNotNil(c4)
        XCTAssertEqual(c4?.pitch, 60)
        
        let fSharp5 = MIDINote.fromNoteName("F#5", velocity: 80, startBeat: 0, durationBeats: 0.5)
        XCTAssertNotNil(fSharp5)
        XCTAssertEqual(fSharp5?.pitch, 78)
        
        let invalid = MIDINote.fromNoteName("XYZ", startBeat: 0, durationBeats: 1.0)
        XCTAssertNil(invalid)
    }
    
    // MARK: - Resize Collision (Issue #79)
    
    /// maxEndBeatForResize: prevents overlapping same-pitch notes when resizing (right edge).
    func testMaxEndBeatForResizeNoNextNoteReturnsRequested() {
        let note = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let allNotes = [note]
        let requestedEndBeat = 3.0
        let result = MIDINote.maxEndBeatForResize(resizingNote: note, allNotes: allNotes, requestedEndBeat: requestedEndBeat)
        XCTAssertEqual(result, 3.0, accuracy: 0.00001, "No next same-pitch note: should return requested end")
    }
    
    func testMaxEndBeatForResizeCapsAtNextSamePitch() {
        let first = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)   // C3 at beat 1
        let second = MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 0.5)   // C3 at beat 2
        let allNotes = [first, second]
        let requestedEndBeat = 2.5  // User tried to extend first note past beat 2
        let result = MIDINote.maxEndBeatForResize(resizingNote: first, allNotes: allNotes, requestedEndBeat: requestedEndBeat)
        XCTAssertEqual(result, 2.0, accuracy: 0.00001, "Should cap at next note's start (beat 2)")
    }
    
    func testMaxEndBeatForResizeDifferentPitchNoCap() {
        let first = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)   // C3
        let second = MIDINote(pitch: 64, startBeat: 2.0, durationBeats: 0.5)  // E3
        let allNotes = [first, second]
        let requestedEndBeat = 2.5
        let result = MIDINote.maxEndBeatForResize(resizingNote: first, allNotes: allNotes, requestedEndBeat: requestedEndBeat)
        XCTAssertEqual(result, 2.5, accuracy: 0.00001, "Different pitch: no collision cap")
    }
    
    func testMaxEndBeatForResizeExactIssue79Scenario() {
        // Issue #79: two consecutive C3 notes at beat 1 and beat 2; resize first to 2.5 -> must cap at 2
        let first = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let second = MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 0.5)
        let allNotes = [first, second]
        let result = MIDINote.maxEndBeatForResize(resizingNote: first, allNotes: allNotes, requestedEndBeat: 2.5)
        XCTAssertEqual(result, 2.0, accuracy: 0.00001)
        let maxDuration = result - first.startBeat
        XCTAssertEqual(maxDuration, 1.0, accuracy: 0.00001, "First note duration limited to 1 beat (ends at 2)")
    }
    
    func testMaxEndBeatForResizeMultipleSamePitchCapsAtNearest() {
        let first = MIDINote(pitch: 60, startBeat: 0.0, durationBeats: 0.5)
        let second = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let third = MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 0.5)
        let allNotes = [first, second, third]
        let result = MIDINote.maxEndBeatForResize(resizingNote: first, allNotes: allNotes, requestedEndBeat: 3.0)
        XCTAssertEqual(result, 1.0, accuracy: 0.00001, "Should cap at nearest next same-pitch (beat 1)")
    }
    
    func testMaxEndBeatForResizeRequestedBeforeNextReturnsRequested() {
        let first = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let second = MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 0.5)
        let allNotes = [first, second]
        let requestedEndBeat = 1.5  // User shortens; no collision
        let result = MIDINote.maxEndBeatForResize(resizingNote: first, allNotes: allNotes, requestedEndBeat: requestedEndBeat)
        XCTAssertEqual(result, 1.5, accuracy: 0.00001)
    }
    
    func testMaxEndBeatForResizeIgnoresNotesBeforeResizingNote() {
        let other = MIDINote(pitch: 60, startBeat: 0.0, durationBeats: 0.5)
        let resizing = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let allNotes = [other, resizing]
        let result = MIDINote.maxEndBeatForResize(resizingNote: resizing, allNotes: allNotes, requestedEndBeat: 3.0)
        XCTAssertEqual(result, 3.0, accuracy: 0.00001, "Notes before resizing note should not cap")
    }
    
    func testMaxEndBeatForResizeIgnoresSelf() {
        let note = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let allNotes = [note]
        let result = MIDINote.maxEndBeatForResize(resizingNote: note, allNotes: allNotes, requestedEndBeat: 2.0)
        XCTAssertEqual(result, 2.0, accuracy: 0.00001, "Only other notes (different id) are considered")
    }
    
    func testMaxEndBeatForResizePolyphonicNoOverlapSamePitch() {
        // C3 at 1, E3 at 1.5, C3 at 2. Resizing first C3: can extend to 2, not to 2.5
        let c1 = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let e = MIDINote(pitch: 64, startBeat: 1.5, durationBeats: 0.5)
        let c2 = MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 0.5)
        let allNotes = [c1, e, c2]
        let result = MIDINote.maxEndBeatForResize(resizingNote: c1, allNotes: allNotes, requestedEndBeat: 2.5)
        XCTAssertEqual(result, 2.0, accuracy: 0.00001, "Cap at next C3 (beat 2), not E3 (beat 1.5)")
    }

    func testMaxEndBeatForResizeRequestedExactlyAtNextNoteStart() {
        // Requested end exactly at next same-pitch note start: allowed (no overlap)
        let first = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let second = MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 0.5)
        let allNotes = [first, second]
        let requestedEndBeat = 2.0
        let result = MIDINote.maxEndBeatForResize(resizingNote: first, allNotes: allNotes, requestedEndBeat: requestedEndBeat)
        XCTAssertEqual(result, 2.0, accuracy: 0.00001, "Requested end at next note start is allowed (boundary)")
    }

    func testMaxEndBeatForResizeRequestedBeforeNoteStartReturnsRequested() {
        // Requested end before resizing note start (e.g. drag left past start); no next same-pitch → return requested.
        // Caller (PianoRollView) enforces minimum duration so note does not invert.
        let note = MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.5)
        let allNotes = [note]
        let requestedEndBeat = 0.5
        let result = MIDINote.maxEndBeatForResize(resizingNote: note, allNotes: allNotes, requestedEndBeat: requestedEndBeat)
        XCTAssertEqual(result, 0.5, accuracy: 0.00001, "No next same-pitch: return requested; caller enforces min duration")
    }

    // MARK: - MIDIRegion Tests
    
    func testMIDIRegionInitialization() {
        let region = MIDIRegion(name: "Melody", startBeat: 4.0, durationBeats: 8.0)
        
        XCTAssertEqual(region.name, "Melody")
        XCTAssertEqual(region.startBeat, 4.0)
        XCTAssertEqual(region.durationBeats, 8.0)
        XCTAssertTrue(region.notes.isEmpty)
        XCTAssertFalse(region.isLooped)
        XCTAssertFalse(region.isMuted)
    }
    
    func testMIDIRegionEndTime() {
        let region = MIDIRegion(startBeat: 4.0, durationBeats: 8.0)
        XCTAssertEqual(region.endBeat, 12.0)
    }
    
    func testMIDIRegionAddNote() {
        var region = MIDIRegion(durationBeats: 4.0)
        let note = MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0)
        
        region.addNote(note)
        
        XCTAssertEqual(region.noteCount, 1)
        XCTAssertEqual(region.notes.first?.pitch, 60)
    }
    
    func testMIDIRegionAutoExtendDuration() {
        var region = MIDIRegion(durationBeats: 4.0)
        let longNote = MIDINote(pitch: 60, startBeat: 3.0, durationBeats: 3.0)  // Ends at 6.0
        
        region.addNote(longNote)
        
        XCTAssertEqual(region.durationBeats, 6.0, "Region should auto-extend to contain note")
    }
    
    func testMIDIRegionRemoveNotes() {
        var region = MIDIRegion()
        let note1 = MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0)
        let note2 = MIDINote(pitch: 64, startBeat: 1.0, durationBeats: 1.0)
        
        region.addNote(note1)
        region.addNote(note2)
        XCTAssertEqual(region.noteCount, 2)
        
        region.removeNotes(withIds: Set([note1.id]))
        XCTAssertEqual(region.noteCount, 1)
        XCTAssertEqual(region.notes.first?.pitch, 64)
    }
    
    func testMIDIRegionNotesAtTime() {
        var region = MIDIRegion()
        let note1 = MIDINote(pitch: 60, startBeat: 0, durationBeats: 2.0)    // 0-2
        let note2 = MIDINote(pitch: 64, startBeat: 1.0, durationBeats: 2.0)  // 1-3
        let note3 = MIDINote(pitch: 67, startBeat: 2.5, durationBeats: 1.0)  // 2.5-3.5
        
        region.addNote(note1)
        region.addNote(note2)
        region.addNote(note3)
        
        // At time 1.5: note1 and note2 are playing
        let notesAt1_5 = region.notes(at: 1.5)
        XCTAssertEqual(notesAt1_5.count, 2)
        
        // At time 0: only note1 is playing
        let notesAt0 = region.notes(at: 0)
        XCTAssertEqual(notesAt0.count, 1)
        XCTAssertEqual(notesAt0.first?.pitch, 60)
    }
    
    func testMIDIRegionNotesInRange() {
        var region = MIDIRegion()
        let note1 = MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0)
        let note2 = MIDINote(pitch: 64, startBeat: 2.0, durationBeats: 1.0)
        let note3 = MIDINote(pitch: 67, startBeat: 4.0, durationBeats: 1.0)
        
        region.addNote(note1)
        region.addNote(note2)
        region.addNote(note3)
        
        let notesInRange = region.notes(in: 1.5...3.5)
        XCTAssertEqual(notesInRange.count, 1)
        XCTAssertEqual(notesInRange.first?.pitch, 64)
    }
    
    func testMIDIRegionTranspose() {
        var region = MIDIRegion()
        region.addNote(MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0))
        region.addNote(MIDINote(pitch: 64, startBeat: 1.0, durationBeats: 1.0))
        
        region.transpose(by: 5)
        
        XCTAssertEqual(region.notes[0].pitch, 65)
        XCTAssertEqual(region.notes[1].pitch, 69)
    }
    
    func testMIDIRegionTransposeClamping() {
        var region = MIDIRegion()
        // Start with valid pitch near the top of the range
        region.addNote(MIDINote(pitch: 120, startBeat: 0, durationBeats: 1.0))
        
        // Transpose by +10 would give 130, but max MIDI pitch is 127
        region.transpose(by: 10)
        
        // Should clamp to 127 (max valid MIDI pitch)
        XCTAssertEqual(region.notes[0].pitch, 127)
    }
    
    func testMIDIRegionShift() {
        var region = MIDIRegion()
        region.addNote(MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 1.0))
        region.addNote(MIDINote(pitch: 64, startBeat: 2.0, durationBeats: 1.0))
        
        region.shift(by: 2.0)
        
        assertApproximatelyEqual(region.notes[0].startBeat, 3.0)
        assertApproximatelyEqual(region.notes[1].startBeat, 4.0)
    }
    
    func testMIDIRegionShiftNonNegative() {
        var region = MIDIRegion()
        region.addNote(MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 1.0))
        
        region.shift(by: -5.0)  // Would make startBeat negative
        
        assertApproximatelyEqual(region.notes[0].startBeat, 0.0)
    }
    
    func testMIDIRegionPitchRange() {
        var region = MIDIRegion()
        XCTAssertNil(region.pitchRange)
        
        region.addNote(MIDINote(pitch: 48, startBeat: 0, durationBeats: 1.0))
        region.addNote(MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 1.0))
        region.addNote(MIDINote(pitch: 72, startBeat: 2.0, durationBeats: 1.0))
        
        XCTAssertEqual(region.pitchRange, 48...72)
    }
    
    func testMIDIRegionCodable() {
        var region = MIDIRegion(name: "Test Region", startBeat: 4.0, durationBeats: 8.0)
        region.addNote(MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0))
        region.isLooped = true
        
        assertCodableRoundTrip(region)
    }
    
    // MARK: - MIDICCEvent Tests
    
    func testMIDICCEventInitialization() {
        let event = MIDICCEvent(controller: 7, value: 100, beat: 2.0)
        
        XCTAssertEqual(event.controller, 7)
        XCTAssertEqual(event.value, 100)
        XCTAssertEqual(event.beat, 2.0)
        XCTAssertEqual(event.channel, 0)
    }
    
    func testMIDICCEventControllerNames() {
        let modWheel = MIDICCEvent(controller: MIDICCEvent.modWheel, value: 64, beat: 0)
        XCTAssertEqual(modWheel.controllerName, "Mod Wheel")
        
        let volume = MIDICCEvent(controller: MIDICCEvent.volume, value: 100, beat: 0)
        XCTAssertEqual(volume.controllerName, "Volume")
        
        let unknown = MIDICCEvent(controller: 50, value: 64, beat: 0)
        XCTAssertEqual(unknown.controllerName, "CC 50")
    }
    
    func testMIDICCEventNormalizedValue() {
        let event = MIDICCEvent(controller: 7, value: 127, beat: 0)
        assertApproximatelyEqual(event.normalizedValue, 1.0)
        
        let event2 = MIDICCEvent(controller: 7, value: 0, beat: 0)
        assertApproximatelyEqual(event2.normalizedValue, 0.0)
        
        let event3 = MIDICCEvent(controller: 7, value: 64, beat: 0)
        assertApproximatelyEqual(event3.normalizedValue, 64.0 / 127.0)
    }
    
    func testMIDICCEventCodable() {
        let event = MIDICCEvent(controller: 74, value: 80, beat: 1.5, channel: 5)
        assertCodableRoundTrip(event)
    }
    
    // MARK: - MIDIPitchBendEvent Tests
    
    func testMIDIPitchBendEventInitialization() {
        let event = MIDIPitchBendEvent(value: 4000, beat: 1.0)
        
        XCTAssertEqual(event.value, 4000)
        XCTAssertEqual(event.beat, 1.0)
        XCTAssertEqual(event.channel, 0)
    }
    
    func testMIDIPitchBendEventClamping() {
        let tooHigh = MIDIPitchBendEvent(value: 10000, beat: 0)
        XCTAssertEqual(tooHigh.value, MIDIPitchBendEvent.maxUp)
        
        let tooLow = MIDIPitchBendEvent(value: -10000, beat: 0)
        XCTAssertEqual(tooLow.value, MIDIPitchBendEvent.maxDown)
    }
    
    func testMIDIPitchBendEventNormalizedValue() {
        let center = MIDIPitchBendEvent(value: 0, beat: 0)
        assertApproximatelyEqual(center.normalizedValue, 0.0)
        
        let maxUp = MIDIPitchBendEvent(value: MIDIPitchBendEvent.maxUp, beat: 0)
        assertApproximatelyEqual(maxUp.normalizedValue, 1.0)
        
        let maxDown = MIDIPitchBendEvent(value: MIDIPitchBendEvent.maxDown, beat: 0)
        assertApproximatelyEqual(maxDown.normalizedValue, -1.0)
    }
    
    func testMIDIPitchBendEventSemitoneOffset() {
        let event = MIDIPitchBendEvent(value: MIDIPitchBendEvent.maxUp, beat: 0)
        
        // Default bend range is 2 semitones
        assertApproximatelyEqual(event.semitoneOffset(), 2.0)
        
        // Custom bend range
        assertApproximatelyEqual(event.semitoneOffset(bendRange: 12.0), 12.0)
    }
    
    func testMIDIPitchBendEventFromNormalized() {
        let event = MIDIPitchBendEvent.fromNormalized(0.5, beat: 1.0)
        assertApproximatelyEqual(event.normalizedValue, 0.5)
        
        let negative = MIDIPitchBendEvent.fromNormalized(-0.5, beat: 0)
        assertApproximatelyEqual(negative.normalizedValue, -0.5)
    }
    
    func testMIDIPitchBendEventCodable() {
        let event = MIDIPitchBendEvent(value: 2048, beat: 3.5, channel: 1)
        assertCodableRoundTrip(event)
    }
    
    // MARK: - SnapResolution Tests (beats-based API)
    
    func testSnapResolutionStepDurationBeats() {
        assertApproximatelyEqual(SnapResolution.bar.stepDurationBeats, 4.0)
        assertApproximatelyEqual(SnapResolution.half.stepDurationBeats, 2.0)
        assertApproximatelyEqual(SnapResolution.quarter.stepDurationBeats, 1.0)
        assertApproximatelyEqual(SnapResolution.eighth.stepDurationBeats, 0.5)
        assertApproximatelyEqual(SnapResolution.sixteenth.stepDurationBeats, 0.25)
        assertApproximatelyEqual(SnapResolution.thirtysecond.stepDurationBeats, 0.125)
        assertApproximatelyEqual(SnapResolution.off.stepDurationBeats, 0.0)
    }
    
    func testSnapResolutionTripletStepDurationBeats() {
        // Triplet quarter note = 2/3 of a beat
        assertApproximatelyEqual(SnapResolution.tripletQuarter.stepDurationBeats, 1.0 / 1.5)
        
        // Triplet eighth = 1/3 of a beat
        assertApproximatelyEqual(SnapResolution.tripletEighth.stepDurationBeats, 0.5 / 1.5)
    }
    
    func testSnapResolutionQuantizeBeat() {
        // Quantize to quarter notes (beats)
        assertApproximatelyEqual(SnapResolution.quarter.quantize(beat: 1.3), 1.0)
        assertApproximatelyEqual(SnapResolution.quarter.quantize(beat: 1.6), 2.0)
        assertApproximatelyEqual(SnapResolution.quarter.quantize(beat: 1.5), 2.0)  // Round up at .5
        
        // Quantize to eighth notes
        assertApproximatelyEqual(SnapResolution.eighth.quantize(beat: 0.3), 0.5)
        assertApproximatelyEqual(SnapResolution.eighth.quantize(beat: 0.1), 0.0)
    }
    
    func testSnapResolutionQuantizeBeatWithStrength() {
        let original = 1.3
        
        // Full strength = full quantize
        assertApproximatelyEqual(
            SnapResolution.quarter.quantize(beat: original, strength: 1.0),
            1.0
        )
        
        // Zero strength = no change
        assertApproximatelyEqual(
            SnapResolution.quarter.quantize(beat: original, strength: 0.0),
            1.3
        )
        
        // Half strength = halfway
        assertApproximatelyEqual(
            SnapResolution.quarter.quantize(beat: original, strength: 0.5),
            1.15  // Halfway between 1.3 and 1.0
        )
    }
    
    func testSnapResolutionOff() {
        XCTAssertEqual(SnapResolution.off.quantize(beat: 1.234), 1.234)
    }
    
    func testSnapResolutionCodable() {
        for resolution in SnapResolution.allCases {
            assertCodableRoundTrip(resolution)
        }
    }
    
    // MARK: - MIDITrack Tests
    
    func testMIDITrackInitialization() {
        let track = MIDITrack(name: "Piano")
        
        XCTAssertEqual(track.name, "Piano")
        XCTAssertTrue(track.regions.isEmpty)
        XCTAssertFalse(track.isMuted)
        XCTAssertFalse(track.isSolo)
        XCTAssertEqual(track.volume, 0.8)
        XCTAssertEqual(track.pan, 0.0)
        XCTAssertEqual(track.transpose, 0)
    }
    
    func testMIDITrackAddRemoveRegion() {
        var track = MIDITrack(name: "Test")
        let region = MIDIRegion(name: "Region 1")
        
        track.addRegion(region)
        XCTAssertEqual(track.regions.count, 1)
        
        track.removeRegion(withId: region.id)
        XCTAssertTrue(track.regions.isEmpty)
    }
    
    func testMIDITrackTotalNoteCount() {
        var track = MIDITrack()
        var region1 = MIDIRegion()
        region1.addNote(MIDINote(pitch: 60, startBeat: 0, durationBeats: 1.0))
        region1.addNote(MIDINote(pitch: 64, startBeat: 1.0, durationBeats: 1.0))
        
        var region2 = MIDIRegion()
        region2.addNote(MIDINote(pitch: 67, startBeat: 0, durationBeats: 1.0))
        
        track.addRegion(region1)
        track.addRegion(region2)
        
        XCTAssertEqual(track.totalNoteCount, 3)
    }
    
    func testMIDITrackDuration() {
        var track = MIDITrack()
        XCTAssertEqual(track.durationBeats, 0)
        
        track.addRegion(MIDIRegion(startBeat: 0, durationBeats: 4.0))
        track.addRegion(MIDIRegion(startBeat: 8.0, durationBeats: 4.0))
        
        XCTAssertEqual(track.durationBeats, 12.0)
    }
    
    func testMIDITrackCodable() {
        var track = MIDITrack(name: "Test", volume: 0.6, pan: -0.5, transpose: 2)
        track.addRegion(MIDIRegion(name: "Region 1"))
        
        assertCodableRoundTrip(track)
    }
    
    // MARK: - Performance Tests
    
    func testMIDINoteCreationPerformance() {
        measure {
            for i in 0..<1000 {
                _ = MIDINote(pitch: UInt8(i % 128), startBeat: Double(i), durationBeats: 0.5)
            }
        }
    }
    
    func testMIDIRegionNoteQueryPerformance() {
        var region = MIDIRegion()
        for i in 0..<1000 {
            region.addNote(MIDINote(pitch: 60, startBeat: Double(i) * 0.25, durationBeats: 0.25))
        }
        
        measure {
            for i in 0..<100 {
                _ = region.notes(at: Double(i) * 2.5)
            }
        }
    }
}
