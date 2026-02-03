//
//  TimingPrecisionTests.swift
//  StoriTests
//
//  Integration tests for timing precision (PUMP IT UP Phase 1).
//  Verifies deterministic automation and sample-accurate playback.
//

import XCTest
@testable import Stori

final class TimingPrecisionTests: XCTestCase {

    // MARK: - Automation Determinism

    /// Playback before first automation point uses initialValue (mixer snapshot), not current mixer.
    func testAutomationBeforeFirstPointUsesInitialValue() {
        // Lane with one point at beat 8 and initialValue 0.7 (mixer snapshot at lane creation)
        var lane = AutomationLane(
            parameter: .volume,
            points: [AutomationPoint(beat: 8, value: 0.5, curve: .linear)],
            initialValue: 0.7,
            color: .blue
        )
        // At beat 0 we expect initialValue (0.7), not the point's value (0.5)
        XCTAssertEqual(lane.value(atBeat: 0), 0.7, accuracy: 0.001)
        XCTAssertEqual(lane.value(atBeat: 4), 0.7, accuracy: 0.001)
        XCTAssertEqual(lane.value(atBeat: 8), 0.5, accuracy: 0.001)
    }

    /// Lane with no points returns parameter default when no initialValue.
    func testEmptyLaneReturnsDefaultWhenNoInitialValue() {
        let lane = AutomationLane(parameter: .volume, points: [], initialValue: nil, color: .blue)
        XCTAssertEqual(lane.value(atBeat: 0), AutomationParameter.volume.defaultValue, accuracy: 0.001)
    }

    /// Lane with initialValue returns it before first point.
    func testLaneWithInitialValueReturnsItBeforeFirstPoint() {
        var lane = AutomationLane(parameter: .volume, points: [], initialValue: 0.85, color: .blue)
        lane.addPoint(atBeat: 4, value: 0.5, curve: .linear)
        XCTAssertEqual(lane.value(atBeat: 0), 0.85, accuracy: 0.001)
        XCTAssertEqual(lane.value(atBeat: 2), 0.85, accuracy: 0.001)
    }
    
    // MARK: - Performance (PUMP IT UP Phase 2)
    
    /// Automation value lookup for many lanes: target < 1ms for 1000 lookups.
    func testAutomationLookupPerformance() {
        var lane = AutomationLane(parameter: .volume, points: [], initialValue: 0.5, color: .blue)
        for i in 1..<100 {
            lane.addPoint(atBeat: Double(i) * 4, value: Float(i) / 100, curve: .linear)
        }
        let beat = 50.0
        measure {
            for _ in 0..<1000 {
                _ = lane.value(atBeat: beat)
            }
        }
    }
}
