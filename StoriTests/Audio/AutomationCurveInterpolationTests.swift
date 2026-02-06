//
//  AutomationCurveInterpolationTests.swift
//  StoriTests
//
//  Comprehensive tests for automation curve interpolation correctness.
//  Tests mathematical accuracy of all curve types (linear, exponential, logarithmic, S-curve, etc.)
//
//  REGRESSION TESTS for Issue #75:
//  Ensures automation curves correctly implement their mathematical shape.
//

import XCTest
@testable import Stori

final class AutomationCurveInterpolationTests: XCTestCase {
    
    // MARK: - Linear Interpolation Tests
    
    func testLinearInterpolationMidpoint() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .linear))
        lane.points.append(AutomationPoint(beat: 100, value: 100, curve: .linear))
        
        // At 50%: (0 + 100) / 2 = 50
        let result = lane.value(atBeat: 50)
        assertApproximatelyEqual(result, 0.5, tolerance: 0.001)
    }
    
    func testLinearInterpolationQuarterPoints() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .linear))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .linear))
        
        assertApproximatelyEqual(lane.value(atBeat: 0.0), 0.0, tolerance: 0.001)
        assertApproximatelyEqual(lane.value(atBeat: 1.0), 0.25, tolerance: 0.001)
        assertApproximatelyEqual(lane.value(atBeat: 2.0), 0.5, tolerance: 0.001)
        assertApproximatelyEqual(lane.value(atBeat: 3.0), 0.75, tolerance: 0.001)
        assertApproximatelyEqual(lane.value(atBeat: 4.0), 1.0, tolerance: 0.001)
    }
    
    // MARK: - Exponential Interpolation Tests (Slow Start, Fast End)
    
    func testExponentialInterpolationCharacteristics() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .exponential))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .exponential))
        
        let q1 = lane.value(atBeat: 1.0)  // 25% position
        let q2 = lane.value(atBeat: 2.0)  // 50% position
        let q3 = lane.value(atBeat: 3.0)  // 75% position
        
        // Exponential: slow start, fast end
        // Values should be below linear progression
        XCTAssertLessThan(q1, 0.25, "At 25% position, exponential should be < 0.25 (linear)")
        XCTAssertLessThan(q2, 0.5, "At 50% position, exponential should be < 0.5 (linear)")
        XCTAssertLessThan(q3, 0.75, "At 75% position, exponential should be < 0.75 (linear)")
        
        // Values should be in valid range
        XCTAssertGreaterThanOrEqual(q1, 0.0)
        XCTAssertLessThanOrEqual(q3, 1.0)
    }
    
    func testExponentialInterpolationMathematicalAccuracy() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .exponential))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .exponential))
        
        // Expected: value = t^2.5 (where t is normalized position)
        // At t=0.5: 0.5^2.5 ≈ 0.177
        let midValue = lane.value(atBeat: 2.0)
        assertApproximatelyEqual(midValue, 0.177, tolerance: 0.01, "Exponential midpoint should match t^2.5")
    }
    
    // MARK: - Logarithmic Interpolation Tests (Fast Start, Slow End)
    
    func testLogarithmicInterpolationCharacteristics() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .logarithmic))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .logarithmic))
        
        let q1 = lane.value(atBeat: 1.0)  // 25% position
        let q2 = lane.value(atBeat: 2.0)  // 50% position
        let q3 = lane.value(atBeat: 3.0)  // 75% position
        
        // Logarithmic: fast start, slow end
        // Values should be above linear progression
        XCTAssertGreaterThan(q1, 0.25, "At 25% position, logarithmic should be > 0.25 (linear)")
        XCTAssertGreaterThan(q2, 0.5, "At 50% position, logarithmic should be > 0.5 (linear)")
        XCTAssertGreaterThan(q3, 0.75, "At 75% position, logarithmic should be > 0.75 (linear)")
        
        // Values should be in valid range
        XCTAssertGreaterThanOrEqual(q1, 0.0)
        XCTAssertLessThanOrEqual(q3, 1.0)
    }
    
    func testLogarithmicInterpolationMathematicalAccuracy() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .logarithmic))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .logarithmic))
        
        // Expected: value = 1 - (1-t)^2.5
        // At t=0.5: 1 - 0.5^2.5 = 1 - 0.177 ≈ 0.823
        let midValue = lane.value(atBeat: 2.0)
        assertApproximatelyEqual(midValue, 0.823, tolerance: 0.01, "Logarithmic midpoint should match 1-(1-t)^2.5")
    }
    
    func testLogarithmicIsInverseOfExponential() {
        var expLane = AutomationLane(parameter: .volume)
        expLane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .exponential))
        expLane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .exponential))
        
        var logLane = AutomationLane(parameter: .volume)
        logLane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .logarithmic))
        logLane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .logarithmic))
        
        // At every point: exp(t) + log(t) should ≈ 1.0 (inverse curves)
        for beat in stride(from: 0.0, through: 4.0, by: 0.5) {
            let expValue = expLane.value(atBeat: beat)
            let logValue = logLane.value(atBeat: beat)
            assertApproximatelyEqual(expValue + logValue, 1.0, tolerance: 0.01, "Exp and Log should be inverse curves")
        }
    }
    
    // MARK: - S-Curve Interpolation Tests (Slow-Fast-Slow)
    
    func testSCurveInterpolationCharacteristics() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .sCurve))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .sCurve))
        
        let q1 = lane.value(atBeat: 1.0)  // 25% position
        let q2 = lane.value(atBeat: 2.0)  // 50% position
        let q3 = lane.value(atBeat: 3.0)  // 75% position
        
        // S-curve: slow start, fast middle, slow end
        XCTAssertLessThan(q1, 0.25, "At 25%, S-curve should be < 0.25 (slow start)")
        assertApproximatelyEqual(q2, 0.5, tolerance: 0.05, "At 50%, S-curve should be ≈ 0.5 (inflection point)")
        XCTAssertGreaterThan(q3, 0.75, "At 75%, S-curve should be > 0.75 (slow end)")
        
        // Values should be in valid range
        XCTAssertGreaterThanOrEqual(q1, 0.0)
        XCTAssertLessThanOrEqual(q3, 1.0)
    }
    
    func testSCurveSymmetry() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .sCurve))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .sCurve))
        
        // S-curve should be symmetric around midpoint
        let v25 = lane.value(atBeat: 1.0)  // 25%
        let v75 = lane.value(atBeat: 3.0)  // 75%
        
        // Symmetry: v(0.25) + v(0.75) should ≈ 1.0
        assertApproximatelyEqual(v25 + v75, 1.0, tolerance: 0.05, "S-curve should be symmetric")
    }
    
    func testSCurveNormalization() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .sCurve))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .sCurve))
        
        // CRITICAL: S-curve MUST reach exactly 0.0 at start and 1.0 at end
        let startValue = lane.value(atBeat: 0.0)
        let endValue = lane.value(atBeat: 4.0)
        
        assertApproximatelyEqual(startValue, 0.0, tolerance: 0.001, "S-curve must start at 0.0")
        assertApproximatelyEqual(endValue, 1.0, tolerance: 0.001, "S-curve must end at 1.0")
    }
    
    // MARK: - Smooth Curve Interpolation Tests (Ease In-Out)
    
    func testSmoothCurveInterpolationCharacteristics() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .smooth))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .smooth))
        
        let midValue = lane.value(atBeat: 2.0)
        
        // Smooth curve at midpoint should be close to 0.5 (symmetric ease in-out)
        assertApproximatelyEqual(midValue, 0.5, tolerance: 0.05, "Smooth curve midpoint should be ≈ 0.5")
    }
    
    // MARK: - Step Interpolation Tests (Hold Value)
    
    func testStepInterpolationHoldsValue() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.2, curve: .step))
        lane.points.append(AutomationPoint(beat: 4.0, value: 0.8, curve: .step))
        
        // Step holds first value until next point
        XCTAssertEqual(lane.value(atBeat: 0.0), 0.2)
        XCTAssertEqual(lane.value(atBeat: 1.0), 0.2)
        XCTAssertEqual(lane.value(atBeat: 2.0), 0.2)
        XCTAssertEqual(lane.value(atBeat: 3.999), 0.2)
        XCTAssertEqual(lane.value(atBeat: 4.0), 0.8)
    }
    
    // MARK: - AutomationProcessor Curve Tests (Real-Time Engine)
    
    func testProcessorLinearInterpolation() {
        let processor = AutomationProcessor()
        let trackId = UUID()
        
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .linear))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .linear))
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        let v0 = processor.getVolume(for: trackId, atBeat: 0.0)
        let v25 = processor.getVolume(for: trackId, atBeat: 1.0)
        let v50 = processor.getVolume(for: trackId, atBeat: 2.0)
        let v75 = processor.getVolume(for: trackId, atBeat: 3.0)
        let v100 = processor.getVolume(for: trackId, atBeat: 4.0)
        
        assertApproximatelyEqual(v0 ?? -1, 0.0, tolerance: 0.001)
        assertApproximatelyEqual(v25 ?? -1, 0.25, tolerance: 0.001)
        assertApproximatelyEqual(v50 ?? -1, 0.5, tolerance: 0.001)
        assertApproximatelyEqual(v75 ?? -1, 0.75, tolerance: 0.001)
        assertApproximatelyEqual(v100 ?? -1, 1.0, tolerance: 0.001)
    }
    
    func testProcessorExponentialInterpolation() {
        let processor = AutomationProcessor()
        let trackId = UUID()
        
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .exponential))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .exponential))
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        let v25 = processor.getVolume(for: trackId, atBeat: 1.0)!
        let v50 = processor.getVolume(for: trackId, atBeat: 2.0)!
        let v75 = processor.getVolume(for: trackId, atBeat: 3.0)!
        
        // Exponential: slow start, fast end
        XCTAssertLessThan(v25, 0.25)
        XCTAssertLessThan(v50, 0.5)
        XCTAssertLessThan(v75, 0.75)
    }
    
    func testProcessorLogarithmicInterpolation() {
        let processor = AutomationProcessor()
        let trackId = UUID()
        
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .logarithmic))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .logarithmic))
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        let v25 = processor.getVolume(for: trackId, atBeat: 1.0)!
        let v50 = processor.getVolume(for: trackId, atBeat: 2.0)!
        let v75 = processor.getVolume(for: trackId, atBeat: 3.0)!
        
        // Logarithmic: fast start, slow end
        XCTAssertGreaterThan(v25, 0.25)
        XCTAssertGreaterThan(v50, 0.5)
        XCTAssertGreaterThan(v75, 0.75)
    }
    
    func testProcessorSCurveInterpolation() {
        let processor = AutomationProcessor()
        let trackId = UUID()
        
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .sCurve))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .sCurve))
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        let v25 = processor.getVolume(for: trackId, atBeat: 1.0)!
        let v50 = processor.getVolume(for: trackId, atBeat: 2.0)!
        let v75 = processor.getVolume(for: trackId, atBeat: 3.0)!
        
        // S-curve: slow start, fast middle, slow end
        XCTAssertLessThan(v25, 0.25, "S-curve should be slow at start")
        assertApproximatelyEqual(v50, 0.5, tolerance: 0.05, "S-curve midpoint should be ≈ 0.5")
        XCTAssertGreaterThan(v75, 0.75, "S-curve should be slow at end")
    }
    
    func testProcessorSCurveNormalization() {
        let processor = AutomationProcessor()
        let trackId = UUID()
        
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .sCurve))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .sCurve))
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // CRITICAL FIX for Issue #75: S-curve MUST normalize to exact endpoints
        let startValue = processor.getVolume(for: trackId, atBeat: 0.0)!
        let endValue = processor.getVolume(for: trackId, atBeat: 4.0)!
        
        assertApproximatelyEqual(startValue, 0.0, tolerance: 0.001, "Processor S-curve must start at 0.0")
        assertApproximatelyEqual(endValue, 1.0, tolerance: 0.001, "Processor S-curve must end at 1.0")
    }
    
    // MARK: - Consistency Between AutomationLane and AutomationProcessor
    
    func testLaneAndProcessorProduceSameLinearValues() {
        let processor = AutomationProcessor()
        let trackId = UUID()
        
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .linear))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .linear))
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // Test at multiple points
        for beat in stride(from: 0.0, through: 4.0, by: 0.5) {
            let laneValue = lane.value(atBeat: beat)
            let processorValue = processor.getVolume(for: trackId, atBeat: beat)!
            
            assertApproximatelyEqual(laneValue, processorValue, tolerance: 0.001,
                                   "Lane and Processor must produce identical values at beat \(beat)")
        }
    }
    
    func testLaneAndProcessorProduceSameExponentialValues() {
        let processor = AutomationProcessor()
        let trackId = UUID()
        
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .exponential))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .exponential))
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        for beat in stride(from: 0.0, through: 4.0, by: 0.5) {
            let laneValue = lane.value(atBeat: beat)
            let processorValue = processor.getVolume(for: trackId, atBeat: beat)!
            
            assertApproximatelyEqual(laneValue, processorValue, tolerance: 0.01,
                                   "Lane and Processor exponential values must match at beat \(beat)")
        }
    }
    
    func testLaneAndProcessorProduceSameLogarithmicValues() {
        let processor = AutomationProcessor()
        let trackId = UUID()
        
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .logarithmic))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .logarithmic))
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        for beat in stride(from: 0.0, through: 4.0, by: 0.5) {
            let laneValue = lane.value(atBeat: beat)
            let processorValue = processor.getVolume(for: trackId, atBeat: beat)!
            
            assertApproximatelyEqual(laneValue, processorValue, tolerance: 0.01,
                                   "Lane and Processor logarithmic values must match at beat \(beat)")
        }
    }
    
    func testLaneAndProcessorProduceSameSCurveValues() {
        let processor = AutomationProcessor()
        let trackId = UUID()
        
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: .sCurve))
        lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: .sCurve))
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        for beat in stride(from: 0.0, through: 4.0, by: 0.5) {
            let laneValue = lane.value(atBeat: beat)
            let processorValue = processor.getVolume(for: trackId, atBeat: beat)!
            
            assertApproximatelyEqual(laneValue, processorValue, tolerance: 0.05,
                                   "Lane and Processor S-curve values must match at beat \(beat)")
        }
    }
    
    // MARK: - Edge Cases
    
    func testAllCurvesReachExactEndpoints() {
        let curveTypes: [CurveType] = [.linear, .smooth, .exponential, .logarithmic, .sCurve]
        
        for curveType in curveTypes {
            var lane = AutomationLane(parameter: .volume)
            lane.points.append(AutomationPoint(beat: 0, value: 0.0, curve: curveType))
            lane.points.append(AutomationPoint(beat: 4.0, value: 1.0, curve: curveType))
            
            let startValue = lane.value(atBeat: 0.0)
            let endValue = lane.value(atBeat: 4.0)
            
            assertApproximatelyEqual(startValue, 0.0, tolerance: 0.001,
                                   "\(curveType) must start at exactly 0.0")
            assertApproximatelyEqual(endValue, 1.0, tolerance: 0.001,
                                   "\(curveType) must end at exactly 1.0")
        }
    }
    
    func testCurvesWithNonZeroStartValue() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 0.3, curve: .exponential))
        lane.points.append(AutomationPoint(beat: 4.0, value: 0.8, curve: .exponential))
        
        let startValue = lane.value(atBeat: 0.0)
        let endValue = lane.value(atBeat: 4.0)
        let midValue = lane.value(atBeat: 2.0)
        
        assertApproximatelyEqual(startValue, 0.3, tolerance: 0.001)
        assertApproximatelyEqual(endValue, 0.8, tolerance: 0.001)
        XCTAssertGreaterThan(midValue, 0.3)
        XCTAssertLessThan(midValue, 0.8)
    }
    
    func testCurvesWithDecreasingValues() {
        var lane = AutomationLane(parameter: .volume)
        lane.points.append(AutomationPoint(beat: 0, value: 1.0, curve: .exponential))
        lane.points.append(AutomationPoint(beat: 4.0, value: 0.0, curve: .exponential))
        
        let startValue = lane.value(atBeat: 0.0)
        let midValue = lane.value(atBeat: 2.0)
        let endValue = lane.value(atBeat: 4.0)
        
        assertApproximatelyEqual(startValue, 1.0, tolerance: 0.001)
        assertApproximatelyEqual(endValue, 0.0, tolerance: 0.001)
        // Exponential fade-out: should stay high initially
        XCTAssertGreaterThan(midValue, 0.5)
    }
    
    // MARK: - Performance and Stability
    
    func testCurveInterpolationWithManyPoints() {
        var lane = AutomationLane(parameter: .volume)
        
        // Create automation with 100 points
        for i in 0..<100 {
            let beat = Double(i) * 4.0
            let value = Float(i % 2)  // Alternating 0 and 1
            lane.addPoint(atBeat: beat, value: value, curve: .sCurve)
        }
        
        // Query many intermediate positions
        for i in 0..<1000 {
            let beat = Double(i) * 0.4
            let value = lane.value(atBeat: beat)
            
            // All values must be in valid range
            XCTAssertGreaterThanOrEqual(value, 0.0)
            XCTAssertLessThanOrEqual(value, 1.0)
        }
    }
}
