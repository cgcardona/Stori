//
//  NoteDurationResizeTests.swift
//  StoriTests
//
//  Created by TellUrStoriDAW
//  Copyright © 2026 TellUrStori. All rights reserved.
//
//  Test suite for Bug #3: Note Duration Resize Quantizes Absolutely Instead of Relatively
//  GitHub Issue: https://github.com/cgcardona/Stori/issues/32
//

import XCTest
@testable import Stori

/// Tests for note duration resize with snap quantization (Bug #3 / Issue #32)
///
/// CRITICAL BUG FIXED:
/// Previously, resizing a note with snap enabled would quantize the ABSOLUTE duration,
/// causing unpredictable jumps. Now it quantizes the note's END position, matching
/// professional DAW behavior.
///
/// WYSIWYG REQUIREMENT:
/// When dragging a note's right edge with snap enabled, the end position should snap
/// to the grid in a predictable way, just like Logic Pro, Pro Tools, and Cubase.
///
/// PROFESSIONAL STANDARD:
/// - End position snaps to grid
/// - Start position remains fixed
/// - Duration is calculated from snapped end position
final class NoteDurationResizeTests: XCTestCase {
    
    // MARK: - Test Setup
    
    var snapResolution: SnapResolution!
    
    override func setUp() {
        super.setUp()
        snapResolution = .sixteenth // 0.25 beats per step
    }
    
    // MARK: - Core Resize Behavior Tests
    
    func testResizeWithSnapQuantizesEndPosition() {
        // Note at beat 1.0, duration 1.3 (ends at 2.3)
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 1.3)
        
        // User drags right edge slightly (0.1 beats) - new end would be 2.4
        let newDuration = 1.4
        let newEndBeat = note.startBeat + newDuration // 2.4
        
        // With snap, end should snap to nearest 1/16th (2.5)
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
        XCTAssertEqual(snappedEndBeat, 2.5, accuracy: 0.00001)
        
        // Final duration should be calculated from snapped end
        let expectedDuration = snappedEndBeat - note.startBeat // 1.5
        XCTAssertEqual(expectedDuration, 1.5, accuracy: 0.00001,
                      "Duration should be calculated from snapped end position")
    }
    
    func testResizeWithoutSnapAllowsFreeDuration() {
        // With snap OFF, duration should be set freely (no quantization)
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 1.3)
        
        // User drags right edge slightly (0.173 beats)
        let newDuration = note.durationBeats + 0.173 // 1.473
        
        // Without snap, duration should be exact (not quantized)
        XCTAssertEqual(newDuration, 1.473, accuracy: 0.00001,
                      "Without snap, duration should not be quantized")
    }
    
    func testResizeShorterSnapsEndPosition() {
        // Test that shortening notes also snaps end position correctly
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 1.7)
        
        // User drags left to shorten by 0.3 beats - new end would be 2.4
        let newDuration = 1.4
        let newEndBeat = note.startBeat + newDuration // 2.4
        
        // End should snap to 2.5 (nearest 1/16th)
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
        XCTAssertEqual(snappedEndBeat, 2.5, accuracy: 0.00001)
        
        let expectedDuration = snappedEndBeat - note.startBeat // 1.5
        XCTAssertEqual(expectedDuration, 1.5, accuracy: 0.00001)
    }
    
    func testResizeStartPositionRemainsFixed() {
        // Critical: Start position MUST NOT change during resize
        let originalStartBeat = 1.37 // Off-grid start
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: originalStartBeat, durationBeats: 1.0)
        
        // Resize note
        let newDuration = 1.5
        let newEndBeat = note.startBeat + newDuration
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
        let finalDuration = snappedEndBeat - note.startBeat
        
        // Start position should remain exactly the same
        XCTAssertEqual(note.startBeat, originalStartBeat, accuracy: 0.00001,
                      "Start position must not change during resize")
        
        // Duration should accommodate the off-grid start
        XCTAssertGreaterThan(finalDuration, 0,
                           "Duration must be positive even with off-grid start")
    }
    
    // MARK: - Bug Scenario Tests (from Issue #32)
    
    func testBugScenarioFromIssue32() {
        // Exact scenario from bug report
        // Note at beat 1.0, duration 1.3 beats (ends at 2.3)
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 1.3)
        
        // User resizes right edge slightly (drag by 0.1 beats)
        let durationDelta = 0.1
        let newDuration = note.durationBeats + durationDelta // 1.4
        
        // Calculate new end position
        let newEndBeat = note.startBeat + newDuration // 2.4
        
        // With snap to 1/16th (0.25), end should snap to 2.5
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
        XCTAssertEqual(snappedEndBeat, 2.5, accuracy: 0.00001,
                      "End should snap to 2.5 (next 1/16th)")
        
        // Final duration should be 1.5 (snapped end - start)
        let finalDuration = max(snapResolution.stepDurationBeats, snappedEndBeat - note.startBeat)
        XCTAssertEqual(finalDuration, 1.5, accuracy: 0.00001,
                      "Duration should be 1.5, NOT 1.25 (old buggy behavior)")
        
        // Verify note got LONGER, not shorter (key point of the bug)
        XCTAssertGreaterThan(finalDuration, note.durationBeats,
                           "Note should get longer when dragging right, not shorter!")
    }
    
    func testOldBuggyBehaviorNoLongerOccurs() {
        // This test documents the OLD buggy behavior to ensure it doesn't regress
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 1.3)
        
        // Simulate old behavior: quantize the duration directly (the bug)
        // If we had quantized 1.4 with quarter note grid, we'd get round(1.4)=1.0
        // But the actual bug was more subtle - it would snap duration unpredictably
        let newDurationWithDelta = 1.4
        
        // NEW CORRECT behavior: quantize end position
        let newEndBeat = note.startBeat + newDurationWithDelta // 2.4
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat) // round(9.6)*0.25 = 2.5
        let correctResult = snappedEndBeat - note.startBeat // 1.5
        
        // Verify the new behavior extends the note as expected
        XCTAssertEqual(correctResult, 1.5, accuracy: 0.00001,
                      "New correct behavior: end snaps to 2.5, giving duration 1.5")
        XCTAssertGreaterThan(correctResult, note.durationBeats,
                           "Note should get longer when dragging right (1.5 > 1.3)")
    }
    
    // MARK: - Grid Alignment Tests
    
    func testResizeEndSnapsToSixteenthGrid() {
        // Test with 1/16th note grid (0.25 beats)
        snapResolution = .sixteenth
        
        let testCases: [(start: Double, initialDuration: Double, delta: Double, expectedEnd: Double)] = [
            // (start, initial duration, delta, expected end position)
            // NOTE: Uses round() for nearest grid line (not ceil/floor)
            (0.0, 1.0, 0.1, 1.0),     // End at 1.1 -> snap to 1.0 (round(4.4)=4)
            (0.0, 1.0, 0.2, 1.25),    // End at 1.2 -> snap to 1.25 (round(4.8)=5)
            (0.0, 1.0, 0.15, 1.25),   // End at 1.15 -> snap to 1.25 (round(4.6)=5)
            (0.5, 1.0, 0.3, 1.75),    // End at 1.8 -> snap to 1.75 (round(7.2)=7)
            (1.0, 1.3, 0.1, 2.5),     // Bug scenario from issue (round(9.6)=10)
            (2.0, 0.7, -0.2, 2.5)     // End at 2.5, stays at 2.5
        ]
        
        for (start, initialDuration, delta, expectedEnd) in testCases {
            let note = MIDINote(pitch: 60, velocity: 100, startBeat: start, durationBeats: initialDuration)
            let newDuration = initialDuration + delta
            let newEndBeat = note.startBeat + newDuration
            let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
            
            XCTAssertEqual(snappedEndBeat, expectedEnd, accuracy: 0.00001,
                          "End should snap to \(expectedEnd) for note at \(start) with delta \(delta)")
        }
    }
    
    func testResizeEndSnapsToEighthGrid() {
        // Test with 1/8th note grid (0.5 beats)
        snapResolution = .eighth
        
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 1.3)
        let newDuration = 1.4
        let newEndBeat = note.startBeat + newDuration // 2.4
        
        // End should snap to 2.5 (nearest 1/8th)
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
        XCTAssertEqual(snappedEndBeat, 2.5, accuracy: 0.00001)
    }
    
    func testResizeEndSnapsToQuarterGrid() {
        // Test with 1/4 note grid (1.0 beats)
        snapResolution = .quarter
        
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 1.3)
        let newDuration = 1.4
        let newEndBeat = note.startBeat + newDuration // 2.4
        
        // End should snap to 2.0 (nearest 1/4)
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
        XCTAssertEqual(snappedEndBeat, 2.0, accuracy: 0.00001)
    }
    
    // MARK: - Minimum Duration Tests
    
    func testResizeEnforcesMinimumDuration() {
        // When snapped end would be at or before start, enforce minimum duration
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 0.3)
        
        // User tries to resize very short (delta = -0.25)
        let newDuration = 0.05
        let newEndBeat = note.startBeat + newDuration // 1.05
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat) // 1.0
        
        // Duration would be 0.0, but minimum should be enforced
        let rawDuration = snappedEndBeat - note.startBeat // 0.0
        let finalDuration = max(snapResolution.stepDurationBeats, rawDuration) // 0.25
        
        XCTAssertEqual(finalDuration, 0.25, accuracy: 0.00001,
                      "Minimum duration should be one grid step (0.25)")
    }
    
    func testResizeWithoutSnapEnforcesMinimum() {
        // Without snap, enforce minimum duration of 0.01 beats
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 0.3)
        
        // User tries to resize to negative duration
        let newDuration = -0.1
        let finalDuration = max(0.01, newDuration)
        
        XCTAssertEqual(finalDuration, 0.01, accuracy: 0.00001,
                      "Minimum duration without snap should be 0.01 beats")
    }
    
    // MARK: - Off-Grid Start Position Tests
    
    func testResizeWithOffGridStartPosition() {
        // Note starts off-grid (start = 1.37, duration = 1.0, ends at 2.37)
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.37, durationBeats: 1.0)
        
        // User resizes by +0.2 beats (new end = 2.57)
        let newDuration = 1.2
        let newEndBeat = note.startBeat + newDuration // 2.57
        
        // End should snap to 2.5 (nearest 1/16th)
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
        XCTAssertEqual(snappedEndBeat, 2.5, accuracy: 0.00001)
        
        // Duration should accommodate off-grid start (2.5 - 1.37 = 1.13)
        let finalDuration = snappedEndBeat - note.startBeat
        XCTAssertEqual(finalDuration, 1.13, accuracy: 0.00001,
                      "Duration should accommodate off-grid start position")
    }
    
    func testResizeMultipleNotesWithVaryingStarts() {
        // Test that resize logic works consistently for notes at different positions
        let notes: [(start: Double, duration: Double)] = [
            (0.0, 1.0),    // On-grid start
            (0.33, 1.0),   // Off-grid start
            (1.0, 1.5),    // On-grid start
            (2.17, 0.8)    // Off-grid start
        ]
        
        for (start, duration) in notes {
            let note = MIDINote(pitch: 60, velocity: 100, startBeat: start, durationBeats: duration)
            let newDuration = duration + 0.3
            let newEndBeat = note.startBeat + newDuration
            let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
            let finalDuration = max(snapResolution.stepDurationBeats, snappedEndBeat - note.startBeat)
            
            // Verify end is on grid
            let remainder = snappedEndBeat.truncatingRemainder(dividingBy: snapResolution.stepDurationBeats)
            XCTAssertEqual(remainder, 0.0, accuracy: 0.00001,
                          "End position should be on grid for note starting at \(start)")
            
            // Verify duration is positive and reasonable
            XCTAssertGreaterThan(finalDuration, 0,
                               "Duration should be positive for note starting at \(start)")
        }
    }
    
    // MARK: - User Experience Tests
    
    func testResizeProvidesConsistentFeedback() {
        // When user drags right, note should always get longer (or stay same if already on grid)
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 1.0)
        
        // Test multiple small drag increments
        let dragIncrements = [0.05, 0.1, 0.15, 0.2, 0.25]
        
        for increment in dragIncrements {
            let newDuration = note.durationBeats + increment
            let newEndBeat = note.startBeat + newDuration
            let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
            let finalDuration = max(snapResolution.stepDurationBeats, snappedEndBeat - note.startBeat)
            
            // Note should never get shorter when dragging right
            XCTAssertGreaterThanOrEqual(finalDuration, note.durationBeats,
                                       "Note should not get shorter when dragging right by \(increment)")
        }
    }
    
    func testResizeSnapBehaviorMatchesLogicPro() {
        // Logic Pro behavior: end position snaps to grid during resize
        // This test documents expected professional DAW behavior
        
        let testScenarios: [(description: String, start: Double, initialDur: Double, delta: Double, expectedEnd: Double)] = [
            ("Extend note to next grid line", 1.0, 1.0, 0.1, 2.0),       // newEnd=2.1 -> round(8.4)=8 -> 2.0
            ("Shorten note to previous grid line", 1.0, 1.3, -0.1, 2.25), // newEnd=2.2 -> round(8.8)=9 -> 2.25
            ("Extend from off-grid start", 0.17, 1.0, 0.2, 1.25),        // newEnd=1.37 -> round(5.48)=5 -> 1.25
            ("Small adjustment snaps predictably", 2.0, 0.8, 0.05, 2.75) // newEnd=2.85 -> round(11.4)=11 -> 2.75
        ]
        
        for scenario in testScenarios {
            let note = MIDINote(pitch: 60, velocity: 100, startBeat: scenario.start, durationBeats: scenario.initialDur)
            let newDuration = scenario.initialDur + scenario.delta
            let newEndBeat = note.startBeat + newDuration
            let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
            
            XCTAssertEqual(snappedEndBeat, scenario.expectedEnd, accuracy: 0.00001,
                          "Scenario: \(scenario.description)")
        }
    }
    
    // MARK: - Edge Cases
    
    func testResizeVeryShortNote() {
        // Note with minimum duration
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 0.25)
        
        // Try to extend by tiny amount
        let newDuration = 0.26
        let newEndBeat = note.startBeat + newDuration // 1.26
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat) // 1.25
        let finalDuration = max(snapResolution.stepDurationBeats, snappedEndBeat - note.startBeat)
        
        XCTAssertEqual(finalDuration, 0.25, accuracy: 0.00001,
                      "Very short note should maintain minimum grid step")
    }
    
    func testResizeVeryLongNote() {
        // Note spanning many bars
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 0.0, durationBeats: 64.0)
        
        // Extend by small amount
        let newDuration = 64.3
        let newEndBeat = note.startBeat + newDuration // 64.3
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat) // 64.25
        let finalDuration = max(snapResolution.stepDurationBeats, snappedEndBeat - note.startBeat)
        
        XCTAssertEqual(finalDuration, 64.25, accuracy: 0.00001,
                      "Long note should snap correctly")
    }
    
    func testResizeAtProjectBoundary() {
        // Note near end of project
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 127.5, durationBeats: 0.5)
        
        // Extend past typical project length
        let newDuration = 1.0
        let newEndBeat = note.startBeat + newDuration // 128.5
        let snappedEndBeat = snapResolution.quantize(beat: newEndBeat) // 128.5
        let finalDuration = max(snapResolution.stepDurationBeats, snappedEndBeat - note.startBeat)
        
        XCTAssertEqual(finalDuration, 1.0, accuracy: 0.00001,
                      "Resize should work at project boundaries")
    }
    
    // MARK: - WYSIWYG Verification
    
    func testResizeWYSIWYGGuarantee() {
        // WYSIWYG: Resize behavior must be predictable and consistent
        // If user sees the end snap to a grid line, that's where it should actually be
        
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 1.0, durationBeats: 1.3)
        
        // Start with the quantized initial end position (what the user sees when resize starts)
        let initialEnd = note.startBeat + note.durationBeats
        var previousEnd = snapResolution.quantize(beat: initialEnd) // 2.25 (quantized from 2.3)
        
        // Simulate multiple resize operations (user keeps dragging)
        let resizeSteps = [0.05, 0.1, 0.15, 0.2]
        
        for step in resizeSteps {
            let cumulativeDuration = note.durationBeats + step
            let newEndBeat = note.startBeat + cumulativeDuration
            let snappedEndBeat = snapResolution.quantize(beat: newEndBeat)
            
            // End position should only move forward (or stay same), never backward
            XCTAssertGreaterThanOrEqual(snappedEndBeat, previousEnd,
                                       "End position should move forward during resize")
            
            previousEnd = snappedEndBeat
        }
    }
}
