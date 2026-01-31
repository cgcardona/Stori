//
//  AutomationProcessorTests.swift
//  StoriTests
//
//  Unit tests for automation playback and curve processing
//

import XCTest
@testable import Stori

final class AutomationProcessorTests: XCTestCase {
    
    // MARK: - Automation Lane Value Lookup Tests
    
    func testEmptyLaneReturnsDefault() {
        let lane = AutomationLane(parameter: .volume)
        
        let value = lane.value(atBeat: 4.0)
        
        XCTAssertEqual(value, AutomationParameter.volume.defaultValue)
    }
    
    func testSinglePointLane() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 4.0, value: 0.6)
        
        // Before point
        XCTAssertEqual(lane.value(atBeat: 0), 0.6)
        
        // At point
        XCTAssertEqual(lane.value(atBeat: 4.0), 0.6)
        
        // After point
        XCTAssertEqual(lane.value(atBeat: 8.0), 0.6)
    }
    
    func testLinearInterpolation() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .linear))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .linear))
        
        // Test interpolated values
        assertApproximatelyEqual(lane.value(atBeat: 0), 0.0)
        assertApproximatelyEqual(lane.value(atBeat: 1.0), 0.25)
        assertApproximatelyEqual(lane.value(atBeat: 2.0), 0.5)
        assertApproximatelyEqual(lane.value(atBeat: 3.0), 0.75)
        assertApproximatelyEqual(lane.value(atBeat: 4.0), 1.0)
    }
    
    func testStepInterpolation() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.2, curve: .step))
        lane.points.append(AutomationPoint(beat: 4.0, value: 0.8, curve: .step))
        
        // Step holds previous value until next point
        XCTAssertEqual(lane.value(atBeat: 0), 0.2)
        XCTAssertEqual(lane.value(atBeat: 1.0), 0.2)
        XCTAssertEqual(lane.value(atBeat: 3.9), 0.2)
        XCTAssertEqual(lane.value(atBeat: 4.0), 0.8)
    }
    
    func testMultipleSegments() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .linear))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .linear))
        lane.points.append(AutomationPoint(beat: 8.0, value: 0.5, curve: .linear))
        
        // First segment
        assertApproximatelyEqual(lane.value(atBeat: 2.0), 0.5)
        
        // Second segment
        assertApproximatelyEqual(lane.value(atBeat: 6.0), 0.75)  // Midpoint: 1.0 → 0.5
    }
    
    // MARK: - Curve Type Tests
    
    func testSmoothCurve() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .smooth))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .smooth))
        
        let midValue = lane.value(atBeat: 2.0)
        
        // Smooth curve at midpoint should be around 0.5
        assertApproximatelyEqual(midValue, 0.5, tolerance: 0.1)
    }
    
    func testExponentialCurve() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .exponential))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .exponential))
        
        let quarterValue = lane.value(atBeat: 1.0)
        let midValue = lane.value(atBeat: 2.0)
        
        // Exponential: slow start, fast end
        XCTAssertLessThan(quarterValue, 0.25)
        XCTAssertLessThan(midValue, 0.5)
    }
    
    func testLogarithmicCurve() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .logarithmic))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .logarithmic))
        
        let quarterValue = lane.value(atBeat: 1.0)
        let midValue = lane.value(atBeat: 2.0)
        
        // Logarithmic: fast start, slow end
        XCTAssertGreaterThan(quarterValue, 0.25)
        XCTAssertGreaterThan(midValue, 0.5)
    }
    
    func testSCurve() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .sCurve))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .sCurve))
        
        let quarterValue = lane.value(atBeat: 1.0)
        let midValue = lane.value(atBeat: 2.0)
        let threeQuarterValue = lane.value(atBeat: 3.0)
        
        // S-curve: slow start, fast middle, slow end
        XCTAssertLessThan(quarterValue, 0.25)
        assertApproximatelyEqual(midValue, 0.5, tolerance: 0.1)
        XCTAssertGreaterThan(threeQuarterValue, 0.75)
    }
    
    // MARK: - Tension Tests
    
    func testPositiveTension() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .linear, tension: 0.5))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .linear, tension: 0.0))
        
        let midValue = lane.value(atBeat: 2.0)
        
        // Positive tension affects curve shape
        // At minimum, value should be in valid range
        XCTAssertGreaterThanOrEqual(midValue, 0.0)
        XCTAssertLessThanOrEqual(midValue, 1.0)
    }
    
    func testNegativeTension() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .smooth, tension: -0.5))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .smooth, tension: 0.0))
        
        let midValue = lane.value(atBeat: 2.0)
        
        // Negative tension makes curve more linear
        assertApproximatelyEqual(midValue, 0.5, tolerance: 0.15)
    }
    
    // MARK: - Point Management Tests
    
    func testAddPoint() {
        var lane = AutomationLane(parameter: .volume)
        
        lane.addPoint(atBeat: 4.0, value: 0.7)
        
        XCTAssertEqual(lane.points.count, 1)
        XCTAssertEqual(lane.points.first?.beat, 4.0)
        XCTAssertEqual(lane.points.first?.value, 0.7)
    }
    
    func testRemovePoint() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 0, value: 0.5)
        lane.addPoint(atBeat: 4.0, value: 0.8)
        
        let pointId = lane.points.first!.id
        lane.removePoint(pointId)
        
        XCTAssertEqual(lane.points.count, 1)
    }
    
    func testUpdatePoint() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 4.0, value: 0.5)
        
        let pointId = lane.points.first!.id
        lane.updatePoint(pointId, beat: 8.0, value: 0.9)
        
        XCTAssertEqual(lane.points.first?.beat, 8.0)
        XCTAssertEqual(lane.points.first?.value, 0.9)
    }
    
    func testUpdatePointClampsValue() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 0, value: 0.5)
        
        let pointId = lane.points.first!.id
        lane.updatePoint(pointId, value: 1.5)  // Too high
        
        XCTAssertEqual(lane.points.first?.value, 1.0)  // Clamped
    }
    
    func testClearPoints() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 0, value: 0.5)
        lane.addPoint(atBeat: 4.0, value: 0.8)
        lane.addPoint(atBeat: 8.0, value: 0.3)
        
        lane.clearPoints()
        
        XCTAssertTrue(lane.points.isEmpty)
    }
    
    func testSortedPoints() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 8.0, value: 0.3)
        lane.addPoint(atBeat: 0, value: 0.5)
        lane.addPoint(atBeat: 4.0, value: 0.8)
        
        let sorted = lane.sortedPoints
        
        XCTAssertEqual(sorted[0].beat, 0.0)
        XCTAssertEqual(sorted[1].beat, 4.0)
        XCTAssertEqual(sorted[2].beat, 8.0)
    }
    
    // MARK: - Automation Mode Tests
    
    func testAutomationModeOff() {
        var data = TrackAutomationData(mode: .off)
        data.addLane(for: .volume)
        
        if var lane = data.lane(for: .volume) {
            lane.addPoint(atBeat: 0, value: 0.5)
            data.lanes = [lane]
        }
        
        // Mode off should not return values
        let value = data.value(for: .volume, atBeat: 4.0)
        XCTAssertNil(value)
    }
    
    func testAutomationModeRead() {
        var data = TrackAutomationData(mode: .read)
        data.addLane(for: .volume)
        
        if var lane = data.lane(for: .volume) {
            lane.addPoint(atBeat: 0, value: 0.5)
            data.lanes = [lane]
        }
        
        let value = data.value(for: .volume, atBeat: 4.0)
        XCTAssertEqual(value, 0.5)
    }
    
    func testAutomationModeTouch() {
        let mode = AutomationMode.touch
        
        XCTAssertTrue(mode.canRead)
        XCTAssertTrue(mode.canRecord)
    }
    
    func testAutomationModeLatch() {
        let mode = AutomationMode.latch
        
        XCTAssertTrue(mode.canRead)
        XCTAssertTrue(mode.canRecord)
    }
    
    func testAutomationModeWrite() {
        let mode = AutomationMode.write
        
        XCTAssertTrue(mode.canRead)
        XCTAssertTrue(mode.canRecord)
    }
    
    // MARK: - Multi-Parameter Tests
    
    func testMultipleParameterLanes() {
        var data = TrackAutomationData(mode: .read)
        data.addLane(for: .volume)
        data.addLane(for: .pan)
        
        // Add points to each lane
        if var volumeLane = data.lane(for: .volume) {
            volumeLane.addPoint(atBeat: 0, value: 0.5)
            volumeLane.addPoint(atBeat: 4.0, value: 1.0)
            
            if let index = data.lanes.firstIndex(where: { $0.parameter == .volume }) {
                data.lanes[index] = volumeLane
            }
        }
        
        if var panLane = data.lane(for: .pan) {
            panLane.addPoint(atBeat: 0, value: 0.0)  // Full left
            panLane.addPoint(atBeat: 4.0, value: 1.0)  // Full right
            
            if let index = data.lanes.firstIndex(where: { $0.parameter == .pan }) {
                data.lanes[index] = panLane
            }
        }
        
        // Read values at midpoint
        let volumeValue = data.value(for: .volume, atBeat: 2.0)
        let panValue = data.value(for: .pan, atBeat: 2.0)
        
        // Linear interpolation at midpoint
        assertApproximatelyEqual(volumeValue ?? 0, 0.75)  // 0.5 → 1.0
        assertApproximatelyEqual(panValue ?? 0, 0.5)      // 0.0 → 1.0
    }
    
    // MARK: - MIDI CC Parameter Tests
    
    func testMIDICCParameter() {
        var lane = AutomationLane(parameter: .midiCC1)
        lane.addPoint(atBeat: 0, value: 0.0)
        lane.addPoint(atBeat: 4.0, value: 1.0)
        
        let value = lane.value(atBeat: 2.0)
        
        // Convert to MIDI CC value (0-127)
        let ccValue = UInt8(value * 127)
        
        XCTAssertEqual(ccValue, 63)  // Approximately half
    }
    
    func testPitchBendParameter() {
        var lane = AutomationLane(parameter: .pitchBend)
        lane.addPoint(atBeat: 0, value: 0.5)  // Center
        lane.addPoint(atBeat: 4.0, value: 1.0)  // Max up
        
        let centerValue = lane.value(atBeat: 0)
        let maxValue = lane.value(atBeat: 4.0)
        
        XCTAssertEqual(centerValue, 0.5)
        XCTAssertEqual(maxValue, 1.0)
        
        // Convert to pitch bend value
        let pitchBendCenter = Int16((centerValue - 0.5) * 2 * Float(MIDIPitchBendEvent.maxUp))
        let pitchBendMax = Int16((maxValue - 0.5) * 2 * Float(MIDIPitchBendEvent.maxUp))
        
        XCTAssertEqual(pitchBendCenter, 0)
        XCTAssertEqual(pitchBendMax, MIDIPitchBendEvent.maxUp)
    }
    
    // MARK: - Edge Cases
    
    func testVeryClosePoints() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 4.0, value: 0.0)
        lane.addPoint(atBeat: 4.001, value: 1.0)
        
        // Should handle very close points without issues
        let value = lane.value(atBeat: 4.0005)
        
        XCTAssertTrue(value >= 0.0 && value <= 1.0)
    }
    
    func testNegativeBeatHandling() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 4.0, value: 0.5)
        
        // Negative beat should return first point value
        let value = lane.value(atBeat: -1.0)
        
        XCTAssertEqual(value, 0.5)
    }
    
    func testVeryLargeBeat() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 4.0, value: 0.5)
        
        // Very large beat should return last point value
        let value = lane.value(atBeat: 1000000.0)
        
        XCTAssertEqual(value, 0.5)
    }
    
    // MARK: - Performance Tests
    
    func testInterpolationPerformance() {
        var lane = AutomationLane(parameter: .volume)
        
        // Create many points
        for i in 0..<100 {
            lane.addPoint(atBeat: Double(i) * 4, value: Float.random(in: 0...1))
        }
        
        measure {
            for i in 0..<1000 {
                _ = lane.value(atBeat: Double(i % 400))
            }
        }
    }
    
    func testPointSortingPerformance() {
        var lane = AutomationLane(parameter: .volume)
        
        // Add points in random order
        for _ in 0..<100 {
            lane.addPoint(atBeat: Double.random(in: 0...1000), value: Float.random(in: 0...1))
        }
        
        measure {
            for _ in 0..<100 {
                _ = lane.sortedPoints
            }
        }
    }
}
