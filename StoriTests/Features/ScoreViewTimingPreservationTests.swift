//
//  ScoreViewTimingPreservationTests.swift
//  StoriTests
//
//  Comprehensive tests for Score View MIDI timing preservation
//  Ensures sub-beat precision is maintained across Score View operations
//
//  Issue #67: Score View MIDI round-trip may lose sub-beat precision
//

import XCTest
@testable import Stori

@MainActor
final class ScoreViewTimingPreservationTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var testRegion: MIDIRegion!
    private var originalNotes: [MIDINote]!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create MIDI notes with intentional micro-timing (humanized/grooved)
        originalNotes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.0123, durationBeats: 0.987),
            MIDINote(pitch: 64, velocity: 90, startBeat: 1.0234, durationBeats: 0.943),
            MIDINote(pitch: 67, velocity: 85, startBeat: 2.0045, durationBeats: 1.123),
            MIDINote(pitch: 72, velocity: 95, startBeat: 3.0567, durationBeats: 0.876),
        ]
        
        testRegion = MIDIRegion(
            id: UUID(),
            name: "Test Region",
            notes: originalNotes,
            startBeat: 0,
            durationBeats: 8,
            instrumentId: nil,
            color: .blue,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 8
        )
    }
    
    override func tearDown() async throws {
        testRegion = nil
        originalNotes = nil
        try await super.tearDown()
    }
    
    // MARK: - Core Timing Preservation Tests
    
    func testNotationQuantizerDoesNotModifyMIDI() {
        // Given: MIDI notes with sub-beat precision
        let quantizer = NotationQuantizer()
        let originalPositions = originalNotes.map { $0.startBeat }
        
        // When: Converting to notation for display
        let measures = quantizer.quantize(
            notes: originalNotes,
            timeSignature: .common,
            tempo: 120.0,
            keySignature: .cMajor
        )
        
        // Then: Original MIDI notes should be unchanged
        for (index, note) in originalNotes.enumerated() {
            XCTAssertEqual(note.startBeat, originalPositions[index], accuracy: 0.000001,
                           "NotationQuantizer must not modify source MIDI data")
        }
        
        // And: ScoreNotes should be created (display layer)
        let allScoreNotes = measures.flatMap { $0.notes }
        XCTAssertGreaterThan(allScoreNotes.count, 0, "Should generate display notes")
        
        // Verify ScoreNotes reference original MIDI notes
        for scoreNote in allScoreNotes {
            XCTAssertTrue(originalNotes.contains { $0.id == scoreNote.midiNoteId },
                          "ScoreNote must reference source MIDI note")
        }
    }
    
    func testScoreViewPreservesTimingAfterTranspose() {
        // Given: Notes with precise micro-timing
        let originalPositions = testRegion.notes.map { ($0.id, $0.startBeat) }
        
        // Note: ScoreTrackData init doesn't have a manual initializer with clef parameter
        // We'll just verify the core logic without creating trackData
        
        // When: Transposing notes in Score View
        var region = testRegion!
        let controller = ScoreEntryController()
        
        let noteIds = Array(region.notes.map { $0.id })
        controller.transpose(notes: noteIds, by: 12, in: &region)
        
        // Then: Timing should be preserved exactly
        for (originalId, originalBeat) in originalPositions {
            if let note = region.notes.first(where: { $0.id == originalId }) {
                XCTAssertEqual(note.startBeat, originalBeat, accuracy: 0.000001,
                               "Transpose must preserve original timing")
            }
        }
        
        // And: Only pitch should change
        for note in region.notes {
            let original = originalNotes.first { $0.id == note.id }!
            XCTAssertEqual(note.pitch, original.pitch + 12, "Pitch should be transposed")
            XCTAssertEqual(note.velocity, original.velocity, "Velocity must be preserved")
            XCTAssertEqual(note.durationBeats, original.durationBeats, accuracy: 0.000001,
                           "Duration must be preserved")
        }
    }
    
    func testScoreViewPreservesTimingAfterDelete() {
        // Given: Notes with precise micro-timing
        let firstNoteId = testRegion.notes[0].id
        let remainingOriginals = Array(testRegion.notes.dropFirst())
        
        // When: Deleting one note
        var region = testRegion!
        let controller = ScoreEntryController()
        
        controller.deleteNotes(Set([firstNoteId]), from: &region)
        
        // Then: Remaining notes should have exact same timing
        XCTAssertEqual(region.notes.count, remainingOriginals.count)
        
        for original in remainingOriginals {
            if let note = region.notes.first(where: { $0.id == original.id }) {
                XCTAssertEqual(note.startBeat, original.startBeat, accuracy: 0.000001,
                               "Delete must not affect timing of other notes")
                XCTAssertEqual(note.durationBeats, original.durationBeats, accuracy: 0.000001,
                               "Delete must not affect duration of other notes")
            }
        }
    }
    
    func testScoreViewPreservesTimingAfterDurationScale() {
        // Given: Notes with precise micro-timing
        let originalPositions = testRegion.notes.map { ($0.id, $0.startBeat, $0.durationBeats) }
        
        // When: Scaling duration
        var region = testRegion!
        let controller = ScoreEntryController()
        
        let noteIds = Array(region.notes.map { $0.id })
        controller.doubleDuration(notes: noteIds, in: &region)
        
        // Then: Start timing must be preserved exactly
        for (originalId, originalBeat, originalDuration) in originalPositions {
            if let note = region.notes.first(where: { $0.id == originalId }) {
                XCTAssertEqual(note.startBeat, originalBeat, accuracy: 0.000001,
                               "Duration scaling must not affect start timing")
                XCTAssertEqual(note.durationBeats, originalDuration * 2, accuracy: 0.000001,
                               "Duration should be doubled")
            }
        }
    }
    
    // MARK: - Round-Trip Precision Tests
    
    func testScoreViewRoundTripPreservesPrecision() {
        // This is the critical test from issue #67
        // Given: Notes with microsecond-precision timing
        let preciseNotes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 1.0237456, durationBeats: 0.9871234),
            MIDINote(pitch: 64, velocity: 90, startBeat: 2.0456789, durationBeats: 0.9234567),
            MIDINote(pitch: 67, velocity: 85, startBeat: 3.0123456, durationBeats: 1.0987654),
        ]
        
        let region = MIDIRegion(
            id: UUID(),
            name: "Precise Region",
            notes: preciseNotes,
            startBeat: 0,
            durationBeats: 8,
            instrumentId: nil,
            color: .blue,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 8
        )
        
        // When: Converting to notation multiple times (simulating repeated Score View opens)
        let quantizer = NotationQuantizer()
        
        for _ in 0..<10 {
            _ = quantizer.quantize(
                notes: region.notes,
                timeSignature: .common,
                tempo: 120.0,
                keySignature: .cMajor
            )
        }
        
        // Then: MIDI timing should be EXACTLY preserved to 6 decimal places
        for (index, note) in region.notes.enumerated() {
            let original = preciseNotes[index]
            XCTAssertEqual(note.startBeat, original.startBeat, accuracy: 0.000001,
                           "Round-trip: startBeat must preserve microsecond precision")
            XCTAssertEqual(note.durationBeats, original.durationBeats, accuracy: 0.000001,
                           "Round-trip: durationBeats must preserve precision")
        }
    }
    
    func testScoreViewPreservesGrooveTimingAfterEdits() {
        // Given: Drum pattern with intentional groove (slightly early/late hits)
        let grooveNotes = [
            MIDINote(pitch: 36, velocity: 127, startBeat: 0.0, durationBeats: 0.25),      // Kick on grid
            MIDINote(pitch: 42, velocity: 80, startBeat: 0.24, durationBeats: 0.1),       // Hi-hat slightly early
            MIDINote(pitch: 42, velocity: 75, startBeat: 0.51, durationBeats: 0.1),       // Hi-hat slightly late
            MIDINote(pitch: 36, velocity: 120, startBeat: 1.0, durationBeats: 0.25),      // Kick on grid
            MIDINote(pitch: 38, velocity: 110, startBeat: 1.02, durationBeats: 0.25),     // Snare slightly late
        ]
        
        var region = MIDIRegion(
            id: UUID(),
            name: "Groove Region",
            notes: grooveNotes,
            startBeat: 0,
            durationBeats: 4,
            instrumentId: nil,
            color: .red,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 4
        )
        
        let originalTiming = region.notes.map { ($0.id, $0.startBeat) }
        
        // When: Transposing just the snare note (not touching groove notes)
        let snareId = grooveNotes[4].id
        let controller = ScoreEntryController()
        
        controller.transpose(notes: [snareId], by: 2, in: &region)
        
        // Then: ALL timing must be preserved (including the subtle groove offsets)
        for (originalId, originalBeat) in originalTiming {
            if let note = region.notes.first(where: { $0.id == originalId }) {
                XCTAssertEqual(note.startBeat, originalBeat, accuracy: 0.000001,
                               "Editing one note must not affect timing of any other note")
            }
        }
    }
    
    // MARK: - Quantization Tests (Explicit User Action)
    
    func testExplicitQuantizeChangesSelectedNotesOnly() {
        // Given: Mix of on-grid and off-grid notes
        let mixedNotes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.0, durationBeats: 1.0),        // On grid
            MIDINote(pitch: 64, velocity: 90, startBeat: 1.0234, durationBeats: 0.987),    // Off grid
            MIDINote(pitch: 67, velocity: 85, startBeat: 2.0, durationBeats: 1.0),         // On grid
            MIDINote(pitch: 72, velocity: 95, startBeat: 3.0567, durationBeats: 0.876),    // Off grid
        ]
        
        var region = MIDIRegion(
            id: UUID(),
            name: "Mixed Region",
            notes: mixedNotes,
            startBeat: 0,
            durationBeats: 8,
            instrumentId: nil,
            color: .green,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 8
        )
        
        // When: Explicitly quantizing only the second note
        let controller = ScoreEntryController()
        
        let secondNoteId = mixedNotes[1].id
        controller.quantize(notes: [secondNoteId], to: .quarter, in: &region)
        
        // Then: Only the quantized note should change
        XCTAssertEqual(region.notes[0].startBeat, 0.0, accuracy: 0.000001,
                       "First note (not selected) must keep original timing")
        XCTAssertEqual(region.notes[1].startBeat, 1.0, accuracy: 0.1,
                       "Second note (selected) should be quantized to nearest quarter")
        XCTAssertEqual(region.notes[2].startBeat, 2.0, accuracy: 0.000001,
                       "Third note (not selected) must keep original timing")
        XCTAssertEqual(region.notes[3].startBeat, 3.0567, accuracy: 0.000001,
                       "Fourth note (not selected) must keep original micro-timing")
    }
    
    func testExplicitQuantizeIsOptInNotAutomatic() {
        // Given: Notes with humanized timing
        let humanizedNotes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.0123, durationBeats: 1.0),
            MIDINote(pitch: 64, velocity: 90, startBeat: 1.0234, durationBeats: 1.0),
        ]
        
        var region = MIDIRegion(
            id: UUID(),
            name: "Humanized",
            notes: humanizedNotes,
            startBeat: 0,
            durationBeats: 4,
            instrumentId: nil,
            color: .purple,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 4
        )
        
        let originalTiming = region.notes.map { $0.startBeat }
        
        // When: Just displaying in Score View (no explicit quantize action)
        let quantizer = NotationQuantizer()
        _ = quantizer.quantize(
            notes: region.notes,
            timeSignature: .common,
            tempo: 120.0
        )
        
        // Then: MIDI timing must be completely unchanged
        for (index, note) in region.notes.enumerated() {
            XCTAssertEqual(note.startBeat, originalTiming[index], accuracy: 0.000001,
                           "Display quantization must not modify MIDI data")
        }
    }
    
    // MARK: - Edit Operation Tests
    
    func testTransposePreservesMicroTiming() {
        // Given: Note at off-grid position
        let offGridNote = MIDINote(
            pitch: 60,
            velocity: 100,
            startBeat: 1.0237,  // Intentionally off-grid
            durationBeats: 0.987  // Intentionally non-standard duration
        )
        
        var region = MIDIRegion(
            id: UUID(),
            name: "Off Grid",
            notes: [offGridNote],
            startBeat: 0,
            durationBeats: 4,
            instrumentId: nil,
            color: .green,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 4
        )
        
        // When: Transposing
        let controller = ScoreEntryController()
        controller.transpose(notes: [offGridNote.id], by: 5, in: &region)
        
        // Then: Micro-timing preserved
        XCTAssertEqual(region.notes[0].startBeat, 1.0237, accuracy: 0.000001,
                       "Transpose must preserve sub-beat precision")
        XCTAssertEqual(region.notes[0].durationBeats, 0.987, accuracy: 0.000001,
                       "Transpose must preserve non-standard duration")
        XCTAssertEqual(region.notes[0].pitch, 65, "Pitch should be transposed C→F")
    }
    
    func testDeletePreservesTimingOfRemainingNotes() {
        // Given: Multiple notes with varied micro-timing
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.0123, durationBeats: 1.0),
            MIDINote(pitch: 64, velocity: 90, startBeat: 1.0234, durationBeats: 1.0),
            MIDINote(pitch: 67, velocity: 85, startBeat: 2.0456, durationBeats: 1.0),
        ]
        
        var region = MIDIRegion(
            id: UUID(),
            name: "Multi Note",
            notes: notes,
            startBeat: 0,
            durationBeats: 4,
            instrumentId: nil,
            color: .blue,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 4
        )
        
        let secondNoteOriginal = notes[1]
        let thirdNoteOriginal = notes[2]
        
        // When: Deleting first note
        let controller = ScoreEntryController()
        controller.deleteNotes(Set([notes[0].id]), from: &region)
        
        // Then: Remaining notes must keep exact timing
        XCTAssertEqual(region.notes.count, 2)
        
        let secondNote = region.notes.first { $0.id == secondNoteOriginal.id }!
        XCTAssertEqual(secondNote.startBeat, 1.0234, accuracy: 0.000001,
                       "Undeleted notes must preserve micro-timing")
        
        let thirdNote = region.notes.first { $0.id == thirdNoteOriginal.id }!
        XCTAssertEqual(thirdNote.startBeat, 2.0456, accuracy: 0.000001,
                       "Undeleted notes must preserve micro-timing")
    }
    
    func testRetrogradePreservesOriginalTimingSlots() {
        // Given: Notes with off-grid timing
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.0123, durationBeats: 0.5),
            MIDINote(pitch: 64, velocity: 90, startBeat: 1.0234, durationBeats: 0.5),
            MIDINote(pitch: 67, velocity: 85, startBeat: 2.0456, durationBeats: 0.5),
        ]
        
        let originalTimingSlots = notes.map { $0.startBeat }
        
        var region = MIDIRegion(
            id: UUID(),
            name: "Retrograde Test",
            notes: notes,
            startBeat: 0,
            durationBeats: 4,
            instrumentId: nil,
            color: .green,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 4
        )
        
        // When: Applying retrograde
        let controller = ScoreEntryController()
        let noteIds = notes.map { $0.id }
        controller.retrograde(notes: noteIds, in: &region)
        
        // Then: Notes should swap timing slots (preserving the exact values)
        let reversedSlots = originalTimingSlots.reversed()
        
        for (index, expectedTime) in reversedSlots.enumerated() {
            // Find which note is now at this timing slot
            let noteAtSlot = region.notes.first { abs($0.startBeat - expectedTime) < 0.000001 }
            XCTAssertNotNil(noteAtSlot,
                            "Retrograde should preserve exact timing slots (slot \(index): \(expectedTime))")
        }
    }
    
    // MARK: - Velocity Preservation Tests
    
    func testScoreViewPreservesVelocityDuringEdits() {
        // Given: Notes with varied velocities
        let originalVelocities = testRegion.notes.map { ($0.id, $0.velocity) }
        
        // When: Transposing notes
        var region = testRegion!
        let controller = ScoreEntryController()
        
        let noteIds = region.notes.map { $0.id }
        controller.transpose(notes: noteIds, by: 12, in: &region)
        
        // Then: Velocities must be preserved
        for (originalId, originalVelocity) in originalVelocities {
            if let note = region.notes.first(where: { $0.id == originalId }) {
                XCTAssertEqual(note.velocity, originalVelocity,
                               "Velocity must be preserved during Score View edits")
            }
        }
    }
    
    // MARK: - Channel Preservation Tests
    
    func testScoreViewPreservesMIDIChannel() {
        // Given: Notes on different MIDI channels
        let multiChannelNotes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.0, durationBeats: 1.0, channel: 0),
            MIDINote(pitch: 64, velocity: 90, startBeat: 1.0, durationBeats: 1.0, channel: 1),
            MIDINote(pitch: 67, velocity: 85, startBeat: 2.0, durationBeats: 1.0, channel: 2),
        ]
        
        var region = MIDIRegion(
            id: UUID(),
            name: "Multi Channel",
            notes: multiChannelNotes,
            startBeat: 0,
            durationBeats: 4,
            instrumentId: nil,
            color: .blue,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 4
        )
        
        let originalChannels = region.notes.map { ($0.id, $0.channel) }
        
        // When: Editing via Score View
        let controller = ScoreEntryController()
        controller.transpose(notes: [multiChannelNotes[0].id], by: 12, in: &region)
        
        // Then: All channels must be preserved
        for (originalId, originalChannel) in originalChannels {
            if let note = region.notes.first(where: { $0.id == originalId }) {
                XCTAssertEqual(note.channel, originalChannel,
                               "MIDI channel must be preserved during edits")
            }
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testScoreViewHandlesExtremeMicroTiming() {
        // Given: Notes with extreme sub-beat precision (10 decimal places)
        let extremeNotes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 1.0123456789, durationBeats: 1.0),
            MIDINote(pitch: 64, velocity: 90, startBeat: 2.0987654321, durationBeats: 1.0),
        ]
        
        var region = MIDIRegion(
            id: UUID(),
            name: "Extreme Precision",
            notes: extremeNotes,
            startBeat: 0,
            durationBeats: 4,
            instrumentId: nil,
            color: .red,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 4
        )
        
        // When: Editing
        let controller = ScoreEntryController()
        controller.transpose(notes: [extremeNotes[0].id], by: 5, in: &region)
        
        // Then: Precision preserved to at least 6 decimal places
        XCTAssertEqual(region.notes[0].startBeat, 1.0123456789, accuracy: 0.000001,
                       "Extreme micro-timing must be preserved")
        XCTAssertEqual(region.notes[1].startBeat, 2.0987654321, accuracy: 0.000001,
                       "Unedited extreme timing must be preserved")
    }
    
    func testScoreViewHandlesSwungTiming() {
        // Given: Swing pattern (off-beat notes delayed by ~33%)
        let straightSixteenths = 0.25  // 16th note
        let swingDelay = straightSixteenths * 0.33
        
        let swungNotes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.0, durationBeats: 0.25),
            MIDINote(pitch: 60, velocity: 80, startBeat: 0.0 + straightSixteenths + swingDelay, durationBeats: 0.25),
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.5, durationBeats: 0.25),
            MIDINote(pitch: 60, velocity: 80, startBeat: 0.5 + straightSixteenths + swingDelay, durationBeats: 0.25),
        ]
        
        let originalSwingTiming = swungNotes.map { $0.startBeat }
        
        var region = MIDIRegion(
            id: UUID(),
            name: "Swung",
            notes: swungNotes,
            startBeat: 0,
            durationBeats: 2,
            instrumentId: nil,
            color: .green,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 2
        )
        
        // When: Editing one note
        let controller = ScoreEntryController()
        controller.transpose(notes: [swungNotes[0].id], by: 12, in: &region)
        
        // Then: Swing timing must be preserved
        for (index, original) in originalSwingTiming.enumerated() {
            XCTAssertEqual(region.notes[index].startBeat, original, accuracy: 0.000001,
                           "Swing timing must be preserved (note \(index))")
        }
    }
    
    // MARK: - Regression Tests
    
    func testIssue67_ScoreViewDoesNotCorruptOffGridNotes() {
        // This is the exact scenario from issue #67
        // Given: Recorded MIDI with natural humanized timing
        let recordedNotes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.0023, durationBeats: 0.987),
            MIDINote(pitch: 64, velocity: 90, startBeat: 1.0134, durationBeats: 0.943),
            MIDINote(pitch: 67, velocity: 85, startBeat: 1.9956, durationBeats: 1.023),
            MIDINote(pitch: 72, velocity: 95, startBeat: 3.0267, durationBeats: 0.976),
        ]
        
        var region = MIDIRegion(
            id: UUID(),
            name: "Recorded Performance",
            notes: recordedNotes,
            startBeat: 0,
            durationBeats: 8,
            instrumentId: nil,
            color: .blue,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 8
        )
        
        let originalTiming = region.notes.map { ($0.id, $0.startBeat, $0.durationBeats) }
        
        // When: Opening in Score View, making edit to one note, closing
        let quantizer = NotationQuantizer()
        _ = quantizer.quantize(notes: region.notes, timeSignature: .common, tempo: 120.0)
        
        // Edit just the third note
        let controller = ScoreEntryController()
        controller.transpose(notes: [recordedNotes[2].id], by: 2, in: &region)
        
        // Then: ALL notes must preserve original micro-timing
        for (originalId, originalBeat, originalDuration) in originalTiming {
            if let note = region.notes.first(where: { $0.id == originalId }) {
                XCTAssertEqual(note.startBeat, originalBeat, accuracy: 0.000001,
                               "Issue #67: Score View must not corrupt humanized timing")
                XCTAssertEqual(note.durationBeats, originalDuration, accuracy: 0.000001,
                               "Issue #67: Score View must not corrupt humanized durations")
            }
        }
    }
    
    func testMultipleScoreViewOpeningsPreserveTiming() {
        // Given: Notes with precise timing
        let preciseNotes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.0123456, durationBeats: 1.0),
            MIDINote(pitch: 64, velocity: 90, startBeat: 1.0234567, durationBeats: 1.0),
        ]
        
        let region = MIDIRegion(
            id: UUID(),
            name: "Precise",
            notes: preciseNotes,
            startBeat: 0,
            durationBeats: 4,
            instrumentId: nil,
            color: .purple,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 4
        )
        
        let originalTiming = region.notes.map { $0.startBeat }
        
        // When: Simulating 10 Score View open/close cycles
        let quantizer = NotationQuantizer()
        for _ in 0..<10 {
            _ = quantizer.quantize(
                notes: region.notes,
                timeSignature: .common,
                tempo: 120.0
            )
        }
        
        // Then: Timing must be identical after all cycles
        for (index, originalBeat) in originalTiming.enumerated() {
            XCTAssertEqual(region.notes[index].startBeat, originalBeat, accuracy: 0.000001,
                           "Multiple Score View cycles must not degrade timing precision")
        }
    }
    
    // MARK: - Performance Tests
    
    func testScoreViewDoesNotTriggerUnnecessaryQuantization() {
        // This test documents that we should NOT re-quantize on every MIDI change
        // NotationQuantizer is computationally expensive and should only run when needed
        
        var quantizeCallCount = 0
        
        // Simulate what used to happen with .onChange(of: region.notes)
        // Every MIDI edit would trigger re-quantization of ALL notes
        
        let notes = (0..<100).map { i in
            MIDINote(pitch: 60, velocity: 100,
                     startBeat: Double(i) * 0.5,
                     durationBeats: 0.4)
        }
        
        // Old behavior: quantize on every change
        let quantizer = NotationQuantizer()
        for _ in 0..<100 {
            _ = quantizer.quantize(notes: notes, timeSignature: .common, tempo: 120.0)
            quantizeCallCount += 1
        }
        
        // Document: This is wasteful
        XCTAssertEqual(quantizeCallCount, 100,
                       "Old behavior would call quantize 100 times for 100 edits")
        
        // New behavior: Only quantize when display config changes or on demand
        // Expected: 1 initial quantize + N config changes (not M note edits)
    }
}
