//
//  QuantizeOddTimeSignatureTests.swift
//  StoriTests
//
//  Issue #64: Piano Roll Quantize May Shift Notes to Wrong Beat on Odd Time Signatures
//
//  CRITICAL VALIDATION:
//  - Quantization works correctly for 5/4, 7/8, 12/8, 15/8, etc.
//  - Notes snap to valid positions within the time signature's grid
//  - Bar-level quantization uses correct bar duration (not hardcoded 4/4)
//  - Subdivision quantization (1/8, 1/16) remains accurate
//  - WYSIWYG: quantized positions match musical intent
//

import XCTest
@testable import Stori

final class QuantizeOddTimeSignatureTests: XCTestCase {
    
    // MARK: - Test 1: 7/8 Time Signature
    
    func testQuantize7_8TimeSignature_EighthNotes() {
        // Given: 7/8 time signature (7 eighth notes per bar = 3.5 quarter-note beats)
        let timeSignature = TimeSignature(numerator: 7, denominator: 8)
        let resolution = SnapResolution.eighth // 0.5 beats in 4/4, same in 7/8
        
        // Create notes slightly off-grid
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.02, durationBeats: 0.5),  // Should snap to 0.0
            MIDINote(pitch: 62, velocity: 100, startBeat: 0.52, durationBeats: 0.5),  // Should snap to 0.5
            MIDINote(pitch: 64, velocity: 100, startBeat: 1.03, durationBeats: 0.5),  // Should snap to 1.0
            MIDINote(pitch: 65, velocity: 100, startBeat: 1.48, durationBeats: 0.5),  // Should snap to 1.5
            MIDINote(pitch: 67, velocity: 100, startBeat: 2.01, durationBeats: 0.5),  // Should snap to 2.0
            MIDINote(pitch: 69, velocity: 100, startBeat: 2.53, durationBeats: 0.5),  // Should snap to 2.5
            MIDINote(pitch: 71, velocity: 100, startBeat: 3.02, durationBeats: 0.5),  // Should snap to 3.0
        ]
        
        // When: Quantize to 1/8 notes with 100% strength
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        // Then: All notes should be on valid 1/8 positions within 7/8
        let expectedPositions = [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
        for (index, note) in quantized.enumerated() {
            XCTAssertEqual(note.startBeat, expectedPositions[index], accuracy: 0.001,
                           "Note \(index) should quantize to \(expectedPositions[index]) in 7/8")
        }
    }
    
    func testQuantize7_8TimeSignature_BarLevel() {
        // Given: 7/8 time signature (bar = 3.5 beats)
        let timeSignature = TimeSignature(numerator: 7, denominator: 8)
        let resolution = SnapResolution.bar
        
        // Create notes across multiple bars
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.1, durationBeats: 0.5),   // Bar 1: snap to 0.0
            MIDINote(pitch: 62, velocity: 100, startBeat: 3.6, durationBeats: 0.5),   // Bar 2: snap to 3.5
            MIDINote(pitch: 64, velocity: 100, startBeat: 7.2, durationBeats: 0.5),   // Bar 3: snap to 7.0
            MIDINote(pitch: 65, velocity: 100, startBeat: 10.3, durationBeats: 0.5),  // Bar 4: snap to 10.5
        ]
        
        // When: Quantize to bar with 100% strength
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        // Then: Notes should snap to bar boundaries (multiples of 3.5)
        let expectedPositions = [0.0, 3.5, 7.0, 10.5]
        for (index, note) in quantized.enumerated() {
            XCTAssertEqual(note.startBeat, expectedPositions[index], accuracy: 0.001,
                           "Note \(index) should quantize to bar boundary at \(expectedPositions[index])")
        }
    }
    
    // MARK: - Test 2: 5/4 Time Signature
    
    func testQuantize5_4TimeSignature_QuarterNotes() {
        // Given: 5/4 time signature (5 quarter notes per bar = 5.0 beats)
        let timeSignature = TimeSignature(numerator: 5, denominator: 4)
        let resolution = SnapResolution.quarter
        
        // Create notes slightly off-grid
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.08, durationBeats: 1.0),  // Snap to 0.0
            MIDINote(pitch: 62, velocity: 100, startBeat: 1.92, durationBeats: 1.0),  // Snap to 2.0
            MIDINote(pitch: 64, velocity: 100, startBeat: 4.05, durationBeats: 1.0),  // Snap to 4.0
            MIDINote(pitch: 65, velocity: 100, startBeat: 5.12, durationBeats: 1.0),  // Snap to 5.0 (next bar)
        ]
        
        // When: Quantize to quarter notes
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        // Then: Notes should be on quarter-note grid
        let expectedPositions = [0.0, 2.0, 4.0, 5.0]
        for (index, note) in quantized.enumerated() {
            XCTAssertEqual(note.startBeat, expectedPositions[index], accuracy: 0.001,
                           "Note \(index) should quantize to \(expectedPositions[index]) in 5/4")
        }
    }
    
    func testQuantize5_4TimeSignature_BarLevel() {
        // Given: 5/4 time signature (bar = 5.0 beats)
        let timeSignature = TimeSignature(numerator: 5, denominator: 4)
        let resolution = SnapResolution.bar
        
        // Create notes across bars
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.3, durationBeats: 1.0),   // Bar 1: snap to 0.0
            MIDINote(pitch: 62, velocity: 100, startBeat: 5.2, durationBeats: 1.0),   // Bar 2: snap to 5.0
            MIDINote(pitch: 64, velocity: 100, startBeat: 9.8, durationBeats: 1.0),   // Bar 3: snap to 10.0
        ]
        
        // When: Quantize to bar
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        // Then: Notes should snap to bar boundaries (multiples of 5.0)
        let expectedPositions = [0.0, 5.0, 10.0]
        for (index, note) in quantized.enumerated() {
            XCTAssertEqual(note.startBeat, expectedPositions[index], accuracy: 0.001,
                           "Note \(index) should quantize to bar boundary at \(expectedPositions[index])")
        }
    }
    
    // MARK: - Test 3: 12/8 Compound Meter
    
    func testQuantize12_8TimeSignature_EighthNotes() {
        // Given: 12/8 time signature (12 eighth notes per bar = 6.0 quarter-note beats)
        let timeSignature = TimeSignature(numerator: 12, denominator: 8)
        let resolution = SnapResolution.eighth
        
        // Create notes across the bar
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.03, durationBeats: 0.5),  // Snap to 0.0
            MIDINote(pitch: 62, velocity: 100, startBeat: 1.52, durationBeats: 0.5),  // Snap to 1.5
            MIDINote(pitch: 64, velocity: 100, startBeat: 3.02, durationBeats: 0.5),  // Snap to 3.0
            MIDINote(pitch: 65, velocity: 100, startBeat: 4.48, durationBeats: 0.5),  // Snap to 4.5
            MIDINote(pitch: 67, velocity: 100, startBeat: 5.97, durationBeats: 0.5),  // Snap to 6.0 (next bar)
        ]
        
        // When: Quantize to 1/8 notes
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        // Then: All notes on 1/8 grid
        let expectedPositions = [0.0, 1.5, 3.0, 4.5, 6.0]
        for (index, note) in quantized.enumerated() {
            XCTAssertEqual(note.startBeat, expectedPositions[index], accuracy: 0.001,
                           "Note \(index) should quantize to \(expectedPositions[index]) in 12/8")
        }
    }
    
    func testQuantize12_8TimeSignature_BarLevel() {
        // Given: 12/8 time signature (bar = 6.0 beats)
        let timeSignature = TimeSignature(numerator: 12, denominator: 8)
        let resolution = SnapResolution.bar
        
        // Create notes across bars
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.2, durationBeats: 1.0),   // Bar 1: snap to 0.0
            MIDINote(pitch: 62, velocity: 100, startBeat: 6.3, durationBeats: 1.0),   // Bar 2: snap to 6.0
            MIDINote(pitch: 64, velocity: 100, startBeat: 11.8, durationBeats: 1.0),  // Bar 3: snap to 12.0
        ]
        
        // When: Quantize to bar
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        // Then: Notes should snap to bar boundaries (multiples of 6.0)
        let expectedPositions = [0.0, 6.0, 12.0]
        for (index, note) in quantized.enumerated() {
            XCTAssertEqual(note.startBeat, expectedPositions[index], accuracy: 0.001,
                           "Note \(index) should quantize to bar boundary at \(expectedPositions[index])")
        }
    }
    
    // MARK: - Test 4: 15/8 Complex Odd Meter
    
    func testQuantize15_8TimeSignature() {
        // Given: 15/8 time signature (15 eighth notes per bar = 7.5 quarter-note beats)
        // This is a complex meter often found in Balkan music
        let timeSignature = TimeSignature(numerator: 15, denominator: 8)
        let resolution = SnapResolution.eighth
        
        // Create notes across the bar
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.05, durationBeats: 0.5),  // Snap to 0.0
            MIDINote(pitch: 62, velocity: 100, startBeat: 2.02, durationBeats: 0.5),  // Snap to 2.0
            MIDINote(pitch: 64, velocity: 100, startBeat: 4.48, durationBeats: 0.5),  // Snap to 4.5
            MIDINote(pitch: 65, velocity: 100, startBeat: 7.03, durationBeats: 0.5),  // Snap to 7.0
            MIDINote(pitch: 67, velocity: 100, startBeat: 7.52, durationBeats: 0.5),  // Snap to 7.5 (next bar)
        ]
        
        // When: Quantize to 1/8 notes
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        // Then: All notes on 1/8 grid
        let expectedPositions = [0.0, 2.0, 4.5, 7.0, 7.5]
        for (index, note) in quantized.enumerated() {
            XCTAssertEqual(note.startBeat, expectedPositions[index], accuracy: 0.001,
                           "Note \(index) should quantize to \(expectedPositions[index]) in 15/8")
        }
    }
    
    // MARK: - Test 5: Quantize Strength with Odd Time Signatures
    
    func testQuantizeStrength50Percent_OddTimeSignature() {
        // Given: 7/8 time signature with 50% quantize strength
        let timeSignature = TimeSignature(numerator: 7, denominator: 8)
        let resolution = SnapResolution.eighth
        
        // Create note 0.1 beats off-grid
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.6, durationBeats: 0.5)  // 0.1 past 0.5
        ]
        
        // When: Quantize with 50% strength
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 0.5,
            quantizeDuration: false
        )
        
        // Then: Note should move halfway to grid
        // Original: 0.6, Target: 0.5, Halfway: 0.55
        XCTAssertEqual(quantized[0].startBeat, 0.55, accuracy: 0.001,
                       "50% strength should move note halfway to grid in 7/8")
    }
    
    // MARK: - Test 6: Regression - 4/4 Still Works
    
    func testQuantize4_4TimeSignature_BackwardCompatibility() {
        // Given: Standard 4/4 time signature
        let timeSignature = TimeSignature.fourFour
        let resolution = SnapResolution.quarter
        
        // Create notes
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.08, durationBeats: 1.0),
            MIDINote(pitch: 62, velocity: 100, startBeat: 1.92, durationBeats: 1.0),
            MIDINote(pitch: 64, velocity: 100, startBeat: 3.05, durationBeats: 1.0),
        ]
        
        // When: Quantize
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        // Then: Standard 4/4 quantization still works
        let expectedPositions = [0.0, 2.0, 3.0]
        for (index, note) in quantized.enumerated() {
            XCTAssertEqual(note.startBeat, expectedPositions[index], accuracy: 0.001,
                           "4/4 quantization should work as before")
        }
    }
    
    // MARK: - Test 7: Grid Calculation Correctness
    
    func testStepDurationBeats_7_8() {
        // Given: 7/8 time signature
        let timeSignature = TimeSignature(numerator: 7, denominator: 8)
        
        // When: Calculate step durations
        let barDuration = SnapResolution.bar.stepDurationBeats(timeSignature: timeSignature)
        let halfDuration = SnapResolution.half.stepDurationBeats(timeSignature: timeSignature)
        let quarterDuration = SnapResolution.quarter.stepDurationBeats(timeSignature: timeSignature)
        let eighthDuration = SnapResolution.eighth.stepDurationBeats(timeSignature: timeSignature)
        
        // Then: Durations should match 7/8 grid
        XCTAssertEqual(barDuration, 3.5, accuracy: 0.001, "Bar in 7/8 = 3.5 quarter-note beats")
        XCTAssertEqual(halfDuration, 1.75, accuracy: 0.001, "Half bar in 7/8 = 1.75 beats")
        XCTAssertEqual(quarterDuration, 1.0, accuracy: 0.001, "Quarter note = 1.0 beat (universal)")
        XCTAssertEqual(eighthDuration, 0.5, accuracy: 0.001, "Eighth note = 0.5 beat (universal)")
    }
    
    func testStepDurationBeats_5_4() {
        // Given: 5/4 time signature
        let timeSignature = TimeSignature(numerator: 5, denominator: 4)
        
        // When: Calculate bar duration
        let barDuration = SnapResolution.bar.stepDurationBeats(timeSignature: timeSignature)
        let halfDuration = SnapResolution.half.stepDurationBeats(timeSignature: timeSignature)
        
        // Then: Bar in 5/4 = 5.0 quarter-note beats
        XCTAssertEqual(barDuration, 5.0, accuracy: 0.001, "Bar in 5/4 = 5.0 beats")
        XCTAssertEqual(halfDuration, 2.5, accuracy: 0.001, "Half bar in 5/4 = 2.5 beats")
    }
    
    func testStepDurationBeats_12_8() {
        // Given: 12/8 compound meter
        let timeSignature = TimeSignature(numerator: 12, denominator: 8)
        
        // When: Calculate bar duration
        let barDuration = SnapResolution.bar.stepDurationBeats(timeSignature: timeSignature)
        
        // Then: Bar in 12/8 = 6.0 quarter-note beats (12 eighth notes = 6 quarters)
        XCTAssertEqual(barDuration, 6.0, accuracy: 0.001, "Bar in 12/8 = 6.0 beats")
    }
    
    // MARK: - Test 8: Cross-Bar Quantization
    
    func testQuantize_CrossBarBoundary_7_8() {
        // Given: 7/8 time signature, note near bar boundary
        let timeSignature = TimeSignature(numerator: 7, denominator: 8)
        let resolution = SnapResolution.half // Half bar = 1.75 beats in 7/8
        
        // Create note just before bar 2 (at 3.4, should snap to 3.5)
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 3.4, durationBeats: 0.5)
        ]
        
        // When: Quantize to half bar
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        // Then: Note should snap to bar 2 start (3.5)
        // Half-bar grid in 7/8: 0.0, 1.75, 3.5, 5.25, 7.0, ...
        // 3.4 is closest to 3.5
        XCTAssertEqual(quantized[0].startBeat, 3.5, accuracy: 0.001,
                       "Note should snap to bar boundary in 7/8")
    }
    
    // MARK: - Test 9: Duration Quantization with Odd Time Signatures
    
    func testQuantizeDuration_OddTimeSignature() {
        // Given: 7/8 time signature, quantize duration enabled
        let timeSignature = TimeSignature(numerator: 7, denominator: 8)
        let resolution = SnapResolution.eighth
        
        // Create note with off-grid duration (0.72 beats; nearest 1/8 grid = 0.5)
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.0, durationBeats: 0.72)
        ]
        
        // When: Quantize with duration quantization
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: true
        )
        
        // Then: Duration snaps to nearest 1/8 grid (0.72 → 0.5)
        XCTAssertEqual(quantized[0].durationBeats, 0.5, accuracy: 0.001,
                       "Duration should quantize to nearest grid in 7/8")
    }
    
    // MARK: - Test 10: Musical Realism - Jazz 5/4 Pattern
    
    func testQuantize_JazzPattern_5_4() {
        // Given: Jazz composition in 5/4 (like "Take Five")
        let timeSignature = TimeSignature(numerator: 5, denominator: 4)
        let resolution = SnapResolution.quarter
        
        // Create typical jazz phrase with swing timing
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.02, durationBeats: 0.8),
            MIDINote(pitch: 64, velocity: 90, startBeat: 1.05, durationBeats: 0.8),
            MIDINote(pitch: 67, velocity: 95, startBeat: 1.97, durationBeats: 1.2),
            MIDINote(pitch: 72, velocity: 100, startBeat: 3.12, durationBeats: 0.8),
            MIDINote(pitch: 69, velocity: 85, startBeat: 3.88, durationBeats: 1.0),
        ]
        
        // When: Quantize to quarter notes
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        // Then: All notes on quarter-note grid
        let expectedPositions = [0.0, 1.0, 2.0, 3.0, 4.0]
        for (index, note) in quantized.enumerated() {
            XCTAssertEqual(note.startBeat, expectedPositions[index], accuracy: 0.001,
                           "Jazz phrase should quantize correctly in 5/4")
        }
    }
    
    // MARK: - Test 11: Progressive Rock Polymeter
    
    func testQuantize_ProgressiveRockPolymeter() {
        // Given: Tool-style 7/8 + 4/4 polymeter (using 7/8 for this test)
        let timeSignature = TimeSignature(numerator: 7, denominator: 8)
        let resolution = SnapResolution.sixteenth
        
        // Create polyrhythmic pattern
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.01, durationBeats: 0.25),
            MIDINote(pitch: 60, velocity: 80, startBeat: 0.26, durationBeats: 0.25),
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.49, durationBeats: 0.25),
            MIDINote(pitch: 60, velocity: 80, startBeat: 0.76, durationBeats: 0.25),
        ]
        
        // When: Quantize to 16th notes
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        // Then: Notes on 16th-note grid
        let expectedPositions = [0.0, 0.25, 0.5, 0.75]
        for (index, note) in quantized.enumerated() {
            XCTAssertEqual(note.startBeat, expectedPositions[index], accuracy: 0.001,
                           "Polymeter should quantize correctly in 7/8")
        }
    }
    
    // MARK: - Test 12: Caller contract — UI and AI must pass time signature for odd meters
    
    /// Documents that Piano Roll and AI quantize use the time-signature-aware API.
    /// With 7/8, a note at 3.6 beats snaps to bar boundary 3.5.
    func testTimeSignatureAwareAPI_RequiredForOddMeters() {
        let timeSignature = TimeSignature(numerator: 7, denominator: 8)
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 3.6, durationBeats: 0.5)
        ]
        
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: .bar,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        XCTAssertEqual(quantized[0].startBeat, 3.5, accuracy: 0.001,
                       "In 7/8, 3.6 → 3.5 (bar boundary)")
    }
    
    // MARK: - Test 13: 4/4 explicit time signature
    
    func testQuantize_WithFourFourTimeSignature() {
        let timeSignature = TimeSignature.fourFour
        let resolution = SnapResolution.quarter
        
        let notes = [
            MIDINote(pitch: 60, velocity: 100, startBeat: 0.08, durationBeats: 1.0),
            MIDINote(pitch: 62, velocity: 100, startBeat: 1.92, durationBeats: 1.0),
        ]
        
        let quantized = QuantizationEngine.quantize(
            notes: notes,
            resolution: resolution,
            timeSignature: timeSignature,
            strength: 1.0,
            quantizeDuration: false
        )
        
        let expectedPositions = [0.0, 2.0]
        for (index, note) in quantized.enumerated() {
            XCTAssertEqual(note.startBeat, expectedPositions[index], accuracy: 0.001,
                           "4/4 quantization")
        }
    }
}
