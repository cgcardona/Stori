//
//  ScoreCoordinateMapperTests.swift
//  StoriTests
//
//  Comprehensive tests for the Score coordinate mapping layer.
//  Validates that beat↔x and pitch↔y conversions are exact inverses,
//  remain stable under zoom, and that hit-testing matches rendering.
//
//  These tests are intentionally pure math — no UI, no async, no mocks.
//  If these pass, the mouse cannot lie.
//

import XCTest
@testable import Stori

final class ScoreCoordinateMapperTests: XCTestCase {
    
    // MARK: - Shared Fixtures
    
    /// Default mapper for most tests: treble clef, C Major, 4/4, zoom 1.0
    private func defaultMapper(
        clef: Clef = .treble,
        keySignature: KeySignature = .cMajor,
        timeSignature: ScoreTimeSignature = .common,
        zoom: CGFloat = 1.0
    ) -> ScoreCoordinateMapper {
        ScoreCoordinateMapper(
            metrics: ScoreLayoutMetrics(),
            clef: clef,
            keySignature: keySignature,
            timeSignature: timeSignature,
            horizontalZoom: zoom
        )
    }
    
    // MARK: - Beat ↔ X Round-Trip Tests
    
    func testBeatToXToBeadRoundTrip_BeatZero() {
        let mapper = defaultMapper()
        let beat = 0.0
        let x = mapper.xForBeat(beat)
        let recovered = mapper.beatAtX(x)
        XCTAssertEqual(recovered, beat, accuracy: 0.000001,
                       "Beat 0.0 must round-trip exactly")
    }
    
    func testBeatToXToBeatRoundTrip_MidMeasure() {
        let mapper = defaultMapper()
        let beat = 1.5  // Middle of second beat in 4/4
        let x = mapper.xForBeat(beat)
        let recovered = mapper.beatAtX(x)
        XCTAssertEqual(recovered, beat, accuracy: 0.000001,
                       "Mid-measure beat must round-trip exactly")
    }
    
    func testBeatToXToBeatRoundTrip_MeasureBoundary() {
        let mapper = defaultMapper()
        let beat = 4.0  // Start of measure 2 in 4/4
        let x = mapper.xForBeat(beat)
        let recovered = mapper.beatAtX(x)
        XCTAssertEqual(recovered, beat, accuracy: 0.000001,
                       "Measure boundary beat must round-trip exactly")
    }
    
    func testBeatToXToBeatRoundTrip_FractionalBeat() {
        let mapper = defaultMapper()
        let beat = 2.3456  // Precise fractional beat
        let x = mapper.xForBeat(beat)
        let recovered = mapper.beatAtX(x)
        XCTAssertEqual(recovered, beat, accuracy: 0.0001,
                       "Fractional beat must round-trip with high precision")
    }
    
    func testBeatToXToBeatRoundTrip_MultipleBeats() {
        let mapper = defaultMapper()
        let beats = [0.0, 0.25, 0.5, 1.0, 2.0, 3.0, 3.99, 4.0, 7.5, 15.0]
        
        for beat in beats {
            let x = mapper.xForBeat(beat)
            let recovered = mapper.beatAtX(x)
            XCTAssertEqual(recovered, beat, accuracy: 0.001,
                           "Beat \(beat) must round-trip correctly")
        }
    }
    
    func testBeatToXIncreases() {
        let mapper = defaultMapper()
        let x0 = mapper.xForBeat(0.0)
        let x1 = mapper.xForBeat(1.0)
        let x2 = mapper.xForBeat(2.0)
        let x4 = mapper.xForBeat(4.0)
        
        XCTAssertLessThan(x0, x1, "X must increase with beat")
        XCTAssertLessThan(x1, x2, "X must increase with beat")
        XCTAssertLessThan(x2, x4, "X must increase with beat")
    }
    
    func testXForNoteInMeasureMatchesXForBeat() {
        let mapper = defaultMapper()
        
        // Create a ScoreNote at beat 1.5
        let note = ScoreNote(
            id: UUID(),
            midiNoteId: UUID(),
            pitch: 60,
            startBeat: 1.5,
            displayDuration: .quarter
        )
        
        let xFromBeat = mapper.xForBeat(1.5)
        let xFromNote = mapper.xForNoteInMeasure(note, measureIndex: 0)
        
        XCTAssertEqual(xFromBeat, xFromNote, accuracy: 0.001,
                       "xForBeat and xForNoteInMeasure must agree for the same position")
    }
    
    // MARK: - Pitch ↔ Y Round-Trip Tests
    
    func testPitchToYToPitchRoundTrip_MiddleC() {
        let mapper = defaultMapper(clef: .treble)
        let pitch: UInt8 = 60  // Middle C
        let y = mapper.yForPitch(pitch)
        let recovered = mapper.pitchAtY(y)
        XCTAssertEqual(recovered, pitch,
                       "Middle C must round-trip exactly in treble clef")
    }
    
    func testPitchToYToPitchRoundTrip_AllClefs() {
        let clefs: [Clef] = [.treble, .bass, .alto, .tenor]
        let testPitches: [UInt8] = [48, 55, 60, 64, 67, 72, 79, 84]
        
        for clef in clefs {
            let mapper = defaultMapper(clef: clef)
            for pitch in testPitches {
                let y = mapper.yForPitch(pitch)
                let recovered = mapper.pitchAtY(y)
                XCTAssertEqual(recovered, pitch,
                               "Pitch \(pitch) must round-trip in \(clef) clef")
            }
        }
    }
    
    func testPitchToYToPitchRoundTrip_ExtendedRange() {
        // Test pitches across the practical range (C2 to C7)
        let mapper = defaultMapper(clef: .treble)
        let pitches: [UInt8] = [36, 40, 43, 48, 52, 55, 57, 59, 60, 62, 64, 65, 67, 69, 71, 72, 76, 79, 84, 88, 96]
        
        for pitch in pitches {
            let y = mapper.yForPitch(pitch)
            let recovered = mapper.pitchAtY(y)
            XCTAssertEqual(recovered, pitch,
                           "Pitch \(pitch) must round-trip exactly")
        }
    }
    
    func testPitchToYDecreases() {
        // Higher pitches should have lower Y values (screen coordinates)
        let mapper = defaultMapper(clef: .treble)
        let y60 = mapper.yForPitch(60)  // C4
        let y64 = mapper.yForPitch(64)  // E4
        let y72 = mapper.yForPitch(72)  // C5
        
        XCTAssertGreaterThan(y60, y64, "Higher pitch should have lower Y")
        XCTAssertGreaterThan(y64, y72, "Higher pitch should have lower Y")
    }
    
    // MARK: - pitchFromStaffPosition Correctness Tests
    
    func testPitchFromStaffPosition_MiddleC_Treble() {
        let mapper = defaultMapper(clef: .treble)
        // Middle C in treble clef: staffPosition = -6 (one ledger line below)
        let pitch = mapper.pitchFromStaffPosition(-6)
        XCTAssertEqual(pitch, 60, "Staff position -6 in treble should be C4 (MIDI 60)")
    }
    
    func testPitchFromStaffPosition_MiddleC_Bass() {
        let mapper = defaultMapper(clef: .bass)
        // Middle C in bass clef: staffPosition = 6 (one ledger line above)
        let pitch = mapper.pitchFromStaffPosition(6)
        XCTAssertEqual(pitch, 60, "Staff position 6 in bass should be C4 (MIDI 60)")
    }
    
    func testPitchFromStaffPosition_MiddleC_Alto() {
        let mapper = defaultMapper(clef: .alto)
        // Middle C in alto clef: staffPosition = 0 (middle line)
        let pitch = mapper.pitchFromStaffPosition(0)
        XCTAssertEqual(pitch, 60, "Staff position 0 in alto should be C4 (MIDI 60)")
    }
    
    func testPitchFromStaffPosition_NegativePositions() {
        // This test validates the floor division fix.
        // Without the fix, negative positions produce wrong octaves.
        let mapper = defaultMapper(clef: .treble)
        
        // B3 (MIDI 59) in treble clef: position = -7
        XCTAssertEqual(mapper.pitchFromStaffPosition(-7), 59, "Position -7 should be B3")
        
        // A3 (MIDI 57) in treble clef: position = -8
        XCTAssertEqual(mapper.pitchFromStaffPosition(-8), 57, "Position -8 should be A3")
        
        // G3 (MIDI 55) in treble clef: position = -9
        XCTAssertEqual(mapper.pitchFromStaffPosition(-9), 55, "Position -9 should be G3")
        
        // C3 (MIDI 48) in treble clef: position = -13
        XCTAssertEqual(mapper.pitchFromStaffPosition(-13), 48, "Position -13 should be C3")
    }
    
    func testPitchFromStaffPosition_IsInverseOfStaffPosition() {
        // For every diatonic pitch, converting to staff position and back
        // should return the original pitch.
        let clefs: [Clef] = [.treble, .bass, .alto, .tenor]
        
        // Diatonic pitches only (C, D, E, F, G, A, B across multiple octaves)
        let diatonicPitches: [UInt8] = [
            36, 38, 40, 41, 43, 45, 47,  // C2-B2
            48, 50, 52, 53, 55, 57, 59,  // C3-B3
            60, 62, 64, 65, 67, 69, 71,  // C4-B4
            72, 74, 76, 77, 79, 81, 83,  // C5-B5
            84, 86, 88, 89, 91, 93, 95,  // C6-B6
        ]
        
        for clef in clefs {
            let mapper = defaultMapper(clef: clef)
            for pitch in diatonicPitches {
                let position = pitch.staffPosition(for: clef)
                let recovered = mapper.pitchFromStaffPosition(position)
                XCTAssertEqual(recovered, pitch,
                               "Pitch \(pitch) → position \(position) → pitch \(recovered) (expected \(pitch), clef: \(clef))")
            }
        }
    }
    
    // MARK: - Zoom Stability Tests
    
    func testBeatRoundTripStableUnderZoom() {
        let zoomLevels: [CGFloat] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        let beat = 5.678
        
        for zoom in zoomLevels {
            let mapper = defaultMapper(zoom: zoom)
            let x = mapper.xForBeat(beat)
            let recovered = mapper.beatAtX(x)
            XCTAssertEqual(recovered, beat, accuracy: 0.001,
                           "Beat round-trip must be stable at zoom \(zoom)")
        }
    }
    
    func testPitchRoundTripStableUnderZoom() {
        // Pitch conversion is independent of zoom (vertical axis)
        // but let's verify the mapper doesn't introduce any coupling
        let zoomLevels: [CGFloat] = [0.5, 1.0, 2.0]
        let pitch: UInt8 = 64  // E4
        
        for zoom in zoomLevels {
            let mapper = defaultMapper(zoom: zoom)
            let y = mapper.yForPitch(pitch)
            let recovered = mapper.pitchAtY(y)
            XCTAssertEqual(recovered, pitch,
                           "Pitch round-trip must be stable at zoom \(zoom)")
        }
    }
    
    // MARK: - ContentStartX Consistency Tests
    
    func testContentStartX_CMajor() {
        let mapper = defaultMapper(keySignature: .cMajor)
        // C Major has 0 accidentals: clefStart(10) + clefWidth(35) + 0 + timeSig(30) + postSpacing(10) = 85
        XCTAssertEqual(mapper.contentStartX, 85, accuracy: 0.01,
                       "C Major contentStartX should be 85")
    }
    
    func testContentStartX_GMajor() {
        let mapper = defaultMapper(keySignature: .gMajor)
        // G Major has 1 sharp: 85 + 1×14.4 + 12 = 111.4
        let expected: CGFloat = 85 + 1 * 12.0 * 1.2 + 12.0
        XCTAssertEqual(mapper.contentStartX, expected, accuracy: 0.01,
                       "G Major contentStartX should account for 1 sharp")
    }
    
    func testContentStartX_IncreasesWithAccidentals() {
        let cMajor = defaultMapper(keySignature: .cMajor)
        let gMajor = defaultMapper(keySignature: .gMajor)
        let dMajor = defaultMapper(keySignature: .dMajor)
        
        XCTAssertLessThan(cMajor.contentStartX, gMajor.contentStartX,
                          "More accidentals should push contentStartX right")
        XCTAssertLessThan(gMajor.contentStartX, dMajor.contentStartX,
                          "More accidentals should push contentStartX right")
    }
    
    func testContentStartX_FlatsAlsoIncrease() {
        let cMajor = defaultMapper(keySignature: .cMajor)
        let fMajor = defaultMapper(keySignature: .fMajor)  // 1 flat
        
        XCTAssertLessThan(cMajor.contentStartX, fMajor.contentStartX,
                          "Flats should also increase contentStartX")
    }
    
    // MARK: - Hit Testing Tests
    
    func testFindNote_ExactPosition() {
        let mapper = defaultMapper()
        
        let note = ScoreNote(
            id: UUID(),
            midiNoteId: UUID(),
            pitch: 64,  // E4
            startBeat: 1.0,
            displayDuration: .quarter
        )
        
        let measure = ScoreMeasure(
            measureNumber: 1,
            notes: [note]
        )
        
        // Click exactly where the note renders
        let noteX = mapper.xForNoteInMeasure(note, measureIndex: 0)
        let noteY = mapper.yForPitch(note.pitch)
        let clickPoint = CGPoint(x: noteX, y: noteY)
        
        let found = mapper.findNote(at: clickPoint, in: [measure])
        XCTAssertNotNil(found, "Clicking exactly on a note must find it")
        XCTAssertEqual(found?.id, note.id, "Must find the correct note")
    }
    
    func testFindNote_NearPosition() {
        let mapper = defaultMapper()
        
        let note = ScoreNote(
            id: UUID(),
            midiNoteId: UUID(),
            pitch: 67,  // G4
            startBeat: 2.0,
            displayDuration: .quarter
        )
        
        let measure = ScoreMeasure(
            measureNumber: 1,
            notes: [note]
        )
        
        let noteX = mapper.xForNoteInMeasure(note, measureIndex: 0)
        let noteY = mapper.yForPitch(note.pitch)
        
        // Click slightly offset (within hit radius)
        let offset: CGFloat = 10
        let clickPoint = CGPoint(x: noteX + offset, y: noteY - offset / 2)
        let distance = hypot(offset, offset / 2)
        XCTAssertLessThan(distance, mapper.metrics.hitTargetRadius,
                          "Test setup: click should be within hit radius")
        
        let found = mapper.findNote(at: clickPoint, in: [measure])
        XCTAssertNotNil(found, "Clicking near a note must find it")
        XCTAssertEqual(found?.id, note.id, "Must find the correct note")
    }
    
    func testFindNote_TooFar() {
        let mapper = defaultMapper()
        
        let note = ScoreNote(
            id: UUID(),
            midiNoteId: UUID(),
            pitch: 60,
            startBeat: 0.0,
            displayDuration: .quarter
        )
        
        let measure = ScoreMeasure(
            measureNumber: 1,
            notes: [note]
        )
        
        // Click far from the note
        let clickPoint = CGPoint(x: 500, y: 500)
        let found = mapper.findNote(at: clickPoint, in: [measure])
        XCTAssertNil(found, "Clicking far from a note must return nil")
    }
    
    func testFindNote_SelectsClosestNote() {
        let mapper = defaultMapper()
        
        let note1 = ScoreNote(
            id: UUID(),
            midiNoteId: UUID(),
            pitch: 60,
            startBeat: 0.0,
            displayDuration: .quarter
        )
        let note2 = ScoreNote(
            id: UUID(),
            midiNoteId: UUID(),
            pitch: 64,
            startBeat: 1.0,
            displayDuration: .quarter
        )
        
        let measure = ScoreMeasure(
            measureNumber: 1,
            notes: [note1, note2]
        )
        
        // Click closer to note2
        let note2X = mapper.xForNoteInMeasure(note2, measureIndex: 0)
        let note2Y = mapper.yForPitch(note2.pitch)
        let clickPoint = CGPoint(x: note2X - 2, y: note2Y + 2)
        
        let found = mapper.findNote(at: clickPoint, in: [measure])
        XCTAssertEqual(found?.id, note2.id,
                       "Must select the closest note when multiple are in range")
    }
    
    func testFindNote_CorrectMeasureIndexing() {
        let mapper = defaultMapper()
        
        // Note in measure 2 (measureNumber = 2, 0-indexed = 1)
        let note = ScoreNote(
            id: UUID(),
            midiNoteId: UUID(),
            pitch: 67,
            startBeat: 5.0,  // Beat 5 = measure 2, beat 1 in 4/4
            displayDuration: .quarter
        )
        
        let measure = ScoreMeasure(
            measureNumber: 2,
            notes: [note]
        )
        
        let noteX = mapper.xForNoteInMeasure(note, measureIndex: 1)
        let noteY = mapper.yForPitch(note.pitch)
        let clickPoint = CGPoint(x: noteX, y: noteY)
        
        let found = mapper.findNote(at: clickPoint, in: [measure])
        XCTAssertNotNil(found, "Must find note in measure 2")
        XCTAssertEqual(found?.id, note.id)
    }
    
    // MARK: - Layout Bounds Tests
    
    func testStaffBounds() {
        let mapper = defaultMapper()
        
        XCTAssertEqual(mapper.staffTopY, mapper.yOffset,
                       "Staff top should equal yOffset")
        XCTAssertEqual(mapper.staffBottomY, mapper.yOffset + mapper.staffHeight,
                       "Staff bottom should equal yOffset + staffHeight")
        XCTAssertEqual(mapper.staffCenterY, mapper.yOffset + mapper.staffHeight / 2,
                       "Staff center should be between top and bottom")
    }
    
    func testMeasureStartX() {
        let mapper = defaultMapper()
        
        let m0 = mapper.measureStartX(at: 0)
        let m1 = mapper.measureStartX(at: 1)
        let m2 = mapper.measureStartX(at: 2)
        
        XCTAssertEqual(m0, mapper.contentStartX, accuracy: 0.01,
                       "Measure 0 should start at contentStartX")
        XCTAssertEqual(m1 - m0, mapper.scaledMeasureWidth, accuracy: 0.01,
                       "Measures should be spaced by scaledMeasureWidth")
        XCTAssertEqual(m2 - m1, mapper.scaledMeasureWidth, accuracy: 0.01,
                       "Measures should be evenly spaced")
    }
    
    func testNotesWithinStaffRowBounds() {
        let mapper = defaultMapper()
        let metrics = mapper.metrics
        
        // Notes on staff lines (positions 0-8 in treble) should be within row bounds
        let staffPitches: [UInt8] = [64, 67, 71, 74, 77]  // E4, G4, B4, D5, F5 (on treble lines)
        
        for pitch in staffPitches {
            let y = mapper.yForPitch(pitch)
            XCTAssertGreaterThanOrEqual(y, 0,
                                        "Staff note Y should be >= 0 within row")
            XCTAssertLessThanOrEqual(y, metrics.staffRowHeight,
                                     "Staff note Y should be <= staffRowHeight")
        }
    }
    
    // MARK: - Time Signature Tests
    
    func testBeatRoundTrip_ThreeFourTime() {
        let mapper = defaultMapper(timeSignature: .waltz)  // 3/4
        let beat = 2.5  // Middle of measure 1 in 3/4
        let x = mapper.xForBeat(beat)
        let recovered = mapper.beatAtX(x)
        XCTAssertEqual(recovered, beat, accuracy: 0.001,
                       "Beat round-trip must work in 3/4 time")
    }
    
    func testBeatRoundTrip_SixEightTime() {
        let mapper = defaultMapper(timeSignature: .compound6)  // 6/8
        let beat = 1.5  // 6/8 has measureDuration = 3.0
        let x = mapper.xForBeat(beat)
        let recovered = mapper.beatAtX(x)
        XCTAssertEqual(recovered, beat, accuracy: 0.001,
                       "Beat round-trip must work in 6/8 time")
    }
    
    // MARK: - Performance Guardrail Tests
    
    func testMapperCreationIsLightweight() {
        // Creating a mapper should be trivially fast (no allocations beyond the struct)
        measure {
            for _ in 0..<10000 {
                let mapper = ScoreCoordinateMapper(
                    metrics: ScoreLayoutMetrics(),
                    clef: .treble,
                    keySignature: .cMajor,
                    timeSignature: .common,
                    horizontalZoom: 1.0
                )
                _ = mapper.contentStartX
            }
        }
    }
    
    func testHitTestingPerformance_LargeScore() {
        let mapper = defaultMapper()
        
        // Create a dense score (100 measures, 8 notes each = 800 notes)
        var measures: [ScoreMeasure] = []
        for m in 0..<100 {
            var notes: [ScoreNote] = []
            for n in 0..<8 {
                let beat = Double(m) * 4.0 + Double(n) * 0.5
                notes.append(ScoreNote(
                    id: UUID(),
                    midiNoteId: UUID(),
                    pitch: UInt8(60 + (n % 12)),
                    startBeat: beat,
                    displayDuration: .eighth
                ))
            }
            measures.append(ScoreMeasure(measureNumber: m + 1, notes: notes))
        }
        
        // Hit-testing should complete quickly even with 800 notes
        measure {
            for _ in 0..<100 {
                _ = mapper.findNote(at: CGPoint(x: 500, y: 50), in: measures)
            }
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testBeatAtX_BeforeContentStart() {
        let mapper = defaultMapper()
        // Clicking before the content area should return beat 0
        let beat = mapper.beatAtX(0)
        XCTAssertEqual(beat, 0, accuracy: 0.001,
                       "X before content should clamp to beat 0")
    }
    
    func testPitchAtY_ExtremeValues() {
        let mapper = defaultMapper()
        // Very high Y (below staff) should return a low pitch, clamped to 0-127
        let lowPitch = mapper.pitchAtY(mapper.yOffset + 200)
        XCTAssertGreaterThanOrEqual(lowPitch, 0, "Pitch should not underflow")
        XCTAssertLessThanOrEqual(lowPitch, 127, "Pitch should not overflow")
        
        // Very low Y (above staff) should return a high pitch, clamped to 0-127
        let highPitch = mapper.pitchAtY(mapper.yOffset - 200)
        XCTAssertGreaterThanOrEqual(highPitch, 0, "Pitch should not underflow")
        XCTAssertLessThanOrEqual(highPitch, 127, "Pitch should not overflow")
    }
    
    func testScaledMeasureWidth_ReflectsZoom() {
        let metrics = ScoreLayoutMetrics()
        let mapper50 = defaultMapper(zoom: 0.5)
        let mapper100 = defaultMapper(zoom: 1.0)
        let mapper200 = defaultMapper(zoom: 2.0)
        
        XCTAssertEqual(mapper50.scaledMeasureWidth, metrics.baseMeasureWidth * 0.5, accuracy: 0.01)
        XCTAssertEqual(mapper100.scaledMeasureWidth, metrics.baseMeasureWidth, accuracy: 0.01)
        XCTAssertEqual(mapper200.scaledMeasureWidth, metrics.baseMeasureWidth * 2.0, accuracy: 0.01)
    }
}
