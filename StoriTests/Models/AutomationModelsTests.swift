//
//  AutomationModelsTests.swift
//  StoriTests
//
//  Unit tests for AutomationModels.swift - Automation data models
//

import XCTest
@testable import Stori

final class AutomationModelsTests: XCTestCase {
    
    // MARK: - AutomationMode Tests
    
    func testAutomationModeCanRecord() {
        XCTAssertFalse(AutomationMode.off.canRecord)
        XCTAssertFalse(AutomationMode.read.canRecord)
        XCTAssertTrue(AutomationMode.touch.canRecord)
        XCTAssertTrue(AutomationMode.latch.canRecord)
        XCTAssertTrue(AutomationMode.write.canRecord)
    }
    
    func testAutomationModeCanRead() {
        XCTAssertFalse(AutomationMode.off.canRead)
        XCTAssertTrue(AutomationMode.read.canRead)
        XCTAssertTrue(AutomationMode.touch.canRead)
        XCTAssertTrue(AutomationMode.latch.canRead)
        XCTAssertTrue(AutomationMode.write.canRead)
    }
    
    func testAutomationModeShortLabels() {
        XCTAssertEqual(AutomationMode.off.shortLabel, "Off")
        XCTAssertEqual(AutomationMode.read.shortLabel, "R")
        XCTAssertEqual(AutomationMode.touch.shortLabel, "T")
        XCTAssertEqual(AutomationMode.latch.shortLabel, "L")
        XCTAssertEqual(AutomationMode.write.shortLabel, "W")
    }
    
    func testAutomationModeCodable() {
        for mode in AutomationMode.allCases {
            assertCodableRoundTrip(mode)
        }
    }
    
    // MARK: - CurveType Tests
    
    func testCurveTypeDescriptions() {
        XCTAssertFalse(CurveType.linear.description.isEmpty)
        XCTAssertFalse(CurveType.smooth.description.isEmpty)
        XCTAssertFalse(CurveType.step.description.isEmpty)
        XCTAssertFalse(CurveType.exponential.description.isEmpty)
        XCTAssertFalse(CurveType.logarithmic.description.isEmpty)
        XCTAssertFalse(CurveType.sCurve.description.isEmpty)
    }
    
    func testCurveTypeCodable() {
        for curveType in CurveType.allCases {
            assertCodableRoundTrip(curveType)
        }
    }
    
    // MARK: - BezierControlPoint Tests
    
    func testBezierControlPointInitialization() {
        let point = BezierControlPoint(beatOffset: 0.5, valueOffset: 0.1)
        XCTAssertEqual(point.beatOffset, 0.5)
        XCTAssertEqual(point.valueOffset, 0.1)
    }
    
    func testBezierControlPointDefaultValues() {
        let point = BezierControlPoint()
        XCTAssertEqual(point.beatOffset, 0.0)
        XCTAssertEqual(point.valueOffset, 0.0)
    }
    
    func testBezierControlPointAbsolutePosition() {
        let controlPoint = BezierControlPoint(beatOffset: 1.0, valueOffset: 0.2)
        let reference = (beat: 4.0, value: Float(0.5))
        
        let absolute = controlPoint.absolutePosition(from: reference)
        
        XCTAssertEqual(absolute.beat, 5.0)
        XCTAssertEqual(absolute.value, 0.7)
    }
    
    func testBezierControlPointValueClamping() {
        let controlPoint = BezierControlPoint(beatOffset: 0, valueOffset: 0.8)
        let reference = (beat: 0.0, value: Float(0.5))
        
        let absolute = controlPoint.absolutePosition(from: reference)
        
        // 0.5 + 0.8 = 1.3, should clamp to 1.0
        XCTAssertEqual(absolute.value, 1.0)
    }
    
    func testBezierControlPointCodable() {
        let point = BezierControlPoint(beatOffset: 2.5, valueOffset: -0.15)
        assertCodableRoundTrip(point)
    }
    
    // MARK: - AutomationPoint Tests
    
    func testAutomationPointInitialization() {
        let point = AutomationPoint(beat: 4.0, value: 0.75, curve: .smooth)
        
        XCTAssertEqual(point.beat, 4.0)
        XCTAssertEqual(point.value, 0.75)
        XCTAssertEqual(point.curve, .smooth)
        XCTAssertEqual(point.tension, 0.0)
        XCTAssertNil(point.controlPointOut)
        XCTAssertNil(point.controlPointIn)
    }
    
    func testAutomationPointValueClamping() {
        let tooHigh = AutomationPoint(beat: 0, value: 1.5)
        XCTAssertEqual(tooHigh.value, 1.0)
        
        let tooLow = AutomationPoint(beat: 0, value: -0.5)
        XCTAssertEqual(tooLow.value, 0.0)
    }
    
    func testAutomationPointTensionClamping() {
        let highTension = AutomationPoint(beat: 0, value: 0.5, tension: 2.0)
        XCTAssertEqual(highTension.tension, 1.0)
        
        let lowTension = AutomationPoint(beat: 0, value: 0.5, tension: -2.0)
        XCTAssertEqual(lowTension.tension, -1.0)
    }
    
    func testAutomationPointUsesBezier() {
        let withoutBezier = AutomationPoint(beat: 0, value: 0.5)
        XCTAssertFalse(withoutBezier.usesBezier)
        
        let withOutControl = AutomationPoint(
            beat: 0,
            value: 0.5,
            controlPointOut: BezierControlPoint(beatOffset: 0.5, valueOffset: 0.1)
        )
        XCTAssertTrue(withOutControl.usesBezier)
        
        let withInControl = AutomationPoint(
            beat: 0,
            value: 0.5,
            controlPointIn: BezierControlPoint(beatOffset: -0.5, valueOffset: -0.1)
        )
        XCTAssertTrue(withInControl.usesBezier)
    }
    
    func testAutomationPointCodable() {
        let point = AutomationPoint(
            beat: 8.0,
            value: 0.6,
            curve: .sCurve,
            tension: 0.5,
            controlPointOut: BezierControlPoint(beatOffset: 1.0, valueOffset: 0.1)
        )
        assertCodableRoundTrip(point)
    }
    
    // MARK: - AutomationParameter Tests
    
    func testAutomationParameterDefaultValues() {
        XCTAssertEqual(AutomationParameter.volume.defaultValue, 0.8)
        XCTAssertEqual(AutomationParameter.pan.defaultValue, 0.5)  // Center
        XCTAssertEqual(AutomationParameter.pitchBend.defaultValue, 0.5)  // Center
    }
    
    func testAutomationParameterCCNumbers() {
        XCTAssertEqual(AutomationParameter.midiCC1.ccNumber, 1)
        XCTAssertEqual(AutomationParameter.midiCC7.ccNumber, 7)
        XCTAssertEqual(AutomationParameter.midiCC64.ccNumber, 64)
        XCTAssertNil(AutomationParameter.volume.ccNumber)
        XCTAssertNil(AutomationParameter.pan.ccNumber)
    }
    
    func testAutomationParameterShortNames() {
        XCTAssertEqual(AutomationParameter.volume.shortName, "Vol")
        XCTAssertEqual(AutomationParameter.pan.shortName, "Pan")
        XCTAssertEqual(AutomationParameter.midiCC1.shortName, "Mod")
        XCTAssertEqual(AutomationParameter.pitchBend.shortName, "Bend")
    }
    
    func testAutomationParameterIsMixerParameter() {
        XCTAssertTrue(AutomationParameter.volume.isMixerParameter)
        XCTAssertTrue(AutomationParameter.pan.isMixerParameter)
        XCTAssertTrue(AutomationParameter.eqLow.isMixerParameter)
        XCTAssertFalse(AutomationParameter.midiCC1.isMixerParameter)
        XCTAssertFalse(AutomationParameter.pitchBend.isMixerParameter)
    }
    
    func testAutomationParameterCategories() {
        XCTAssertEqual(AutomationParameter.mixerParameters.count, 5)
        XCTAssertTrue(AutomationParameter.mixerParameters.contains(.volume))
        
        XCTAssertEqual(AutomationParameter.midiCCParameters.count, 6)
        XCTAssertTrue(AutomationParameter.midiCCParameters.contains(.midiCC1))
        
        XCTAssertEqual(AutomationParameter.synthParameters.count, 4)
        XCTAssertTrue(AutomationParameter.synthParameters.contains(.synthCutoff))
    }
    
    func testAutomationParameterCodable() {
        for param in AutomationParameter.allCases {
            assertCodableRoundTrip(param)
        }
    }
    
    // MARK: - AutomationLane Tests
    
    func testAutomationLaneInitialization() {
        let lane = AutomationLane(parameter: .volume)
        
        XCTAssertEqual(lane.parameter, .volume)
        XCTAssertTrue(lane.points.isEmpty)
        XCTAssertTrue(lane.isVisible)
        XCTAssertFalse(lane.isLocked)
        XCTAssertEqual(lane.height, 60)
    }
    
    func testAutomationLaneAddPoint() {
        var lane = AutomationLane(parameter: .volume)
        
        lane.addPoint(atBeat: 4.0, value: 0.5)
        
        XCTAssertEqual(lane.points.count, 1)
        XCTAssertEqual(lane.points.first?.beat, 4.0)
        XCTAssertEqual(lane.points.first?.value, 0.5)
    }
    
    func testAutomationLaneRemovePoint() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 0, value: 0.5)
        lane.addPoint(atBeat: 4.0, value: 0.8)
        
        let pointId = lane.points.first!.id
        lane.removePoint(pointId)
        
        XCTAssertEqual(lane.points.count, 1)
    }
    
    func testAutomationLaneUpdatePoint() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 4.0, value: 0.5)
        
        let pointId = lane.points.first!.id
        lane.updatePoint(pointId, beat: 8.0, value: 0.9)
        
        XCTAssertEqual(lane.points.first?.beat, 8.0)
        XCTAssertEqual(lane.points.first?.value, 0.9)
    }
    
    func testAutomationLaneClearPoints() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 0, value: 0.5)
        lane.addPoint(atBeat: 4.0, value: 0.8)
        lane.addPoint(atBeat: 8.0, value: 0.3)
        
        lane.clearPoints()
        
        XCTAssertTrue(lane.points.isEmpty)
    }
    
    func testAutomationLaneSortedPoints() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 8.0, value: 0.3)
        lane.addPoint(atBeat: 0, value: 0.5)
        lane.addPoint(atBeat: 4.0, value: 0.8)
        
        let sorted = lane.sortedPoints
        
        XCTAssertEqual(sorted[0].beat, 0.0)
        XCTAssertEqual(sorted[1].beat, 4.0)
        XCTAssertEqual(sorted[2].beat, 8.0)
    }
    
    // MARK: - Automation Interpolation Tests
    
    func testAutomationLaneValueAtBeatEmpty() {
        let lane = AutomationLane(parameter: .volume)
        
        // Should return default value when no points
        XCTAssertEqual(lane.value(atBeat: 4.0), AutomationParameter.volume.defaultValue)
    }
    
    func testAutomationLaneValueBeforeFirstPoint() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 4.0, value: 0.5)
        
        // Before first point should return first point's value
        XCTAssertEqual(lane.value(atBeat: 0), 0.5)
        XCTAssertEqual(lane.value(atBeat: 2.0), 0.5)
    }
    
    func testAutomationLaneValueAfterLastPoint() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 4.0, value: 0.5)
        
        // After last point should return last point's value
        XCTAssertEqual(lane.value(atBeat: 8.0), 0.5)
        XCTAssertEqual(lane.value(atBeat: 100.0), 0.5)
    }
    
    func testAutomationLaneLinearInterpolation() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .linear))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .linear))
        
        // At midpoint should be 0.5
        assertApproximatelyEqual(lane.value(atBeat: 2.0), 0.5)
        
        // At 1/4 should be 0.25
        assertApproximatelyEqual(lane.value(atBeat: 1.0), 0.25)
        
        // At 3/4 should be 0.75
        assertApproximatelyEqual(lane.value(atBeat: 3.0), 0.75)
    }
    
    func testAutomationLaneStepInterpolation() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.2, curve: .step))
        lane.points.append(AutomationPoint(beat: 4.0, value: 0.8, curve: .step))
        
        // Step should hold the first value until the next point
        XCTAssertEqual(lane.value(atBeat: 0), 0.2)
        XCTAssertEqual(lane.value(atBeat: 2.0), 0.2)
        XCTAssertEqual(lane.value(atBeat: 3.9), 0.2)
        XCTAssertEqual(lane.value(atBeat: 4.0), 0.8)
    }
    
    func testAutomationLaneSmoothInterpolation() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .smooth))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .smooth))
        
        let midValue = lane.value(atBeat: 2.0)
        
        // Smooth curve at midpoint should be close to 0.5 but with S-curve characteristics
        assertApproximatelyEqual(midValue, 0.5, tolerance: 0.05)
    }
    
    func testAutomationLaneExponentialInterpolation() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .exponential))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .exponential))
        
        let quarterValue = lane.value(atBeat: 1.0)
        let midValue = lane.value(atBeat: 2.0)
        
        // Exponential: slow start, fast end
        // Value at 1/4 should be less than 0.25 (linear would be 0.25)
        XCTAssertLessThan(quarterValue, 0.25)
        
        // Value at midpoint should be less than 0.5
        XCTAssertLessThan(midValue, 0.5)
    }
    
    func testAutomationLaneLogarithmicInterpolation() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .logarithmic))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .logarithmic))
        
        let quarterValue = lane.value(atBeat: 1.0)
        let midValue = lane.value(atBeat: 2.0)
        
        // Logarithmic: fast start, slow end
        // Value at 1/4 should be greater than 0.25 (linear would be 0.25)
        XCTAssertGreaterThan(quarterValue, 0.25)
        
        // Value at midpoint should be greater than 0.5
        XCTAssertGreaterThan(midValue, 0.5)
    }
    
    func testAutomationLaneCodable() {
        var lane = AutomationLane(parameter: .pan)
        lane.addPoint(atBeat: 0, value: 0.5, curve: .smooth)
        lane.addPoint(atBeat: 4.0, value: 0.0, curve: .linear)
        lane.addPoint(atBeat: 8.0, value: 1.0, curve: .step)
        
        assertCodableRoundTrip(lane)
    }
    
    // MARK: - TrackAutomationData Tests
    
    func testTrackAutomationDataInitialization() {
        let data = TrackAutomationData()
        
        XCTAssertTrue(data.lanes.isEmpty)
        XCTAssertEqual(data.mode, .read)
        XCTAssertFalse(data.isExpanded)
    }
    
    func testTrackAutomationDataAddLane() {
        var data = TrackAutomationData()
        
        data.addLane(for: .volume)
        data.addLane(for: .pan)
        
        XCTAssertEqual(data.lanes.count, 2)
    }
    
    func testTrackAutomationDataAddLaneNoDuplicates() {
        var data = TrackAutomationData()
        
        data.addLane(for: .volume)
        data.addLane(for: .volume)  // Should be ignored
        
        XCTAssertEqual(data.lanes.count, 1)
    }
    
    func testTrackAutomationDataRemoveLane() {
        var data = TrackAutomationData()
        data.addLane(for: .volume)
        data.addLane(for: .pan)
        
        data.removeLane(for: .volume)
        
        XCTAssertEqual(data.lanes.count, 1)
        XCTAssertNil(data.lane(for: .volume))
        XCTAssertNotNil(data.lane(for: .pan))
    }
    
    func testTrackAutomationDataGetLane() {
        var data = TrackAutomationData()
        data.addLane(for: .volume)
        
        let lane = data.lane(for: .volume)
        XCTAssertNotNil(lane)
        XCTAssertEqual(lane?.parameter, .volume)
        
        let missingLane = data.lane(for: .pan)
        XCTAssertNil(missingLane)
    }
    
    func testTrackAutomationDataValueForParameter() {
        var data = TrackAutomationData(mode: .read)
        data.addLane(for: .volume)
        
        // Add point to the lane
        if var lane = data.lane(for: .volume) {
            lane.addPoint(atBeat: 0, value: 0.5)
            data.lanes = [lane]
        }
        
        let value = data.value(for: .volume, atBeat: 4.0)
        XCTAssertEqual(value, 0.5)
    }
    
    func testTrackAutomationDataValueWhenModeOff() {
        var data = TrackAutomationData(mode: .off)
        data.addLane(for: .volume)
        
        // When mode is off, should return nil (automation not read)
        let value = data.value(for: .volume, atBeat: 4.0)
        XCTAssertNil(value)
    }
    
    func testTrackAutomationDataCodable() {
        var data = TrackAutomationData(mode: .touch, isExpanded: true)
        data.addLane(for: .volume)
        data.addLane(for: .pan)
        
        assertCodableRoundTrip(data)
    }
    
    // MARK: - Performance Tests
    
    func testAutomationInterpolationPerformance() {
        var lane = AutomationLane(parameter: .volume)
        
        // Create 100 automation points
        for i in 0..<100 {
            lane.addPoint(atBeat: Double(i), value: Float.random(in: 0...1))
        }
        
        measure {
            // Query 1000 random positions
            for i in 0..<1000 {
                _ = lane.value(atBeat: Double(i % 100) + Double.random(in: 0..<1))
            }
        }
    }
    
    func testAutomationPointCreationPerformance() {
        measure {
            for i in 0..<1000 {
                _ = AutomationPoint(beat: Double(i), value: Float(i % 100) / 100.0)
            }
        }
    }
    
    // MARK: - AutomationRecorder mergePoints (beat-based API)
    
    @MainActor
    func testMergePointsTouchLatchReplacesInBeatRange() {
        var existing: [AutomationPoint] = [
            AutomationPoint(beat: 0, value: 0.0, curve: .linear),
            AutomationPoint(beat: 4, value: 0.5, curve: .linear),
            AutomationPoint(beat: 8, value: 0.5, curve: .linear),
            AutomationPoint(beat: 12, value: 1.0, curve: .linear)
        ]
        let recorded: [AutomationPoint] = [
            AutomationPoint(beat: 5, value: 0.8, curve: .linear),
            AutomationPoint(beat: 7, value: 0.2, curve: .linear)
        ]
        
        AutomationRecorder.mergePoints(
            recorded: recorded,
            into: &existing,
            startBeat: 4,
            endBeat: 8,
            mode: .touch
        )
        
        // Points in [4, 8] replaced; 0 and 12 kept
        let beats = existing.map(\.beat)
        XCTAssertTrue(beats.contains(0))
        XCTAssertTrue(beats.contains(12))
        XCTAssertTrue(beats.contains(5))
        XCTAssertTrue(beats.contains(7))
        XCTAssertFalse(beats.contains(4))
        XCTAssertFalse(beats.contains(8))
        XCTAssertEqual(existing.count, 4)
    }
    
    @MainActor
    func testMergePointsWriteReplacesFromStartBeat() {
        var existing: [AutomationPoint] = [
            AutomationPoint(beat: 0, value: 0.0, curve: .linear),
            AutomationPoint(beat: 4, value: 0.5, curve: .linear),
            AutomationPoint(beat: 8, value: 1.0, curve: .linear)
        ]
        let recorded: [AutomationPoint] = [
            AutomationPoint(beat: 4, value: 0.7, curve: .linear),
            AutomationPoint(beat: 6, value: 0.3, curve: .linear)
        ]
        
        AutomationRecorder.mergePoints(
            recorded: recorded,
            into: &existing,
            startBeat: 4,
            endBeat: 6,
            mode: .write
        )
        
        // Write removes points at or after startBeat (4, 8), keeps 0, then appends recorded
        let beats = existing.map(\.beat)
        XCTAssertTrue(beats.contains(0))
        XCTAssertTrue(beats.contains(4))
        XCTAssertTrue(beats.contains(6))
        XCTAssertFalse(beats.contains(8))
        XCTAssertEqual(existing.count, 3)
    }
}
