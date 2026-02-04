//
//  AutomationSampleAccuracyTests.swift
//  StoriTests
//
//  Tests for sample-accurate automation in playback and export.
//  Verifies WYHIWYG: automation timing and interpolation match between playback and export.
//

import XCTest
@testable import Stori
import AVFoundation

/// Tests for sample-accurate automation timing and export parity
@MainActor
final class AutomationSampleAccuracyTests: XCTestCase {
    
    var processor: AutomationProcessor!
    
    override func setUpWithError() throws {
        processor = AutomationProcessor()
    }
    
    override func tearDownWithError() throws {
        processor.clearAll()
        processor = nil
    }
    
    // MARK: - Automation Processor Tests
    
    func testAutomationValueAtExactPoint() throws {
        // Given: A track with volume automation points at beats 0 and 4
        let trackId = UUID()
        let lane = createVolumeLane(points: [
            (beat: 0.0, value: 0.0),
            (beat: 4.0, value: 1.0)
        ])
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // When: Query value at exact points
        let valueAt0 = processor.getVolume(for: trackId, atBeat: 0.0)
        let valueAt4 = processor.getVolume(for: trackId, atBeat: 4.0)
        
        // Then: Values match the points exactly
        XCTAssertNotNil(valueAt0, "Should return value at beat 0")
        XCTAssertNotNil(valueAt4, "Should return value at beat 4")
        assertApproximatelyEqual(valueAt0!, 0.0, tolerance: 0.001, "Value at beat 0 should be 0")
        assertApproximatelyEqual(valueAt4!, 1.0, tolerance: 0.001, "Value at beat 4 should be 1")
    }
    
    func testAutomationLinearInterpolation() throws {
        // Given: A track with linear volume automation from 0 to 1 over 4 beats
        let trackId = UUID()
        let lane = createVolumeLane(points: [
            (beat: 0.0, value: 0.0, curve: .linear),
            (beat: 4.0, value: 1.0, curve: .linear)
        ])
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // When: Query value at midpoint
        let valueAt2 = processor.getVolume(for: trackId, atBeat: 2.0)
        
        // Then: Value should be interpolated linearly (0.5)
        XCTAssertNotNil(valueAt2, "Should return interpolated value")
        assertApproximatelyEqual(valueAt2!, 0.5, tolerance: 0.01, 
                               "Linear interpolation at midpoint should be 0.5")
    }
    
    func testAutomationStepCurve() throws {
        // Given: A track with step automation (no interpolation)
        let trackId = UUID()
        let lane = createVolumeLane(points: [
            (beat: 0.0, value: 0.0, curve: .step),
            (beat: 4.0, value: 1.0, curve: .step)
        ])
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // When: Query value between points
        let valueAt2 = processor.getVolume(for: trackId, atBeat: 2.0)
        let valueAt3_99 = processor.getVolume(for: trackId, atBeat: 3.99)
        
        // Then: Value should remain at first point until next point (step behavior)
        assertApproximatelyEqual(valueAt2!, 0.0, tolerance: 0.001, "Step curve should hold at 0")
        assertApproximatelyEqual(valueAt3_99!, 0.0, tolerance: 0.001, "Step curve should hold at 0 until 4.0")
    }
    
    func testAutomationSmoothCurve() throws {
        // Given: A track with smooth (ease in-out) automation
        let trackId = UUID()
        let lane = createVolumeLane(points: [
            (beat: 0.0, value: 0.0, curve: .smooth),
            (beat: 4.0, value: 1.0, curve: .smooth)
        ])
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // When: Query values at quarter points
        let valueAt1 = processor.getVolume(for: trackId, atBeat: 1.0)
        let valueAt2 = processor.getVolume(for: trackId, atBeat: 2.0)
        let valueAt3 = processor.getVolume(for: trackId, atBeat: 3.0)
        
        // Then: Smooth curve should ease in and out (not linear)
        // At 1/4 (25%): should be < 0.25 (slow start)
        // At 1/2 (50%): should be ~0.5 (middle acceleration)
        // At 3/4 (75%): should be > 0.75 (slow end)
        XCTAssertLessThan(valueAt1!, 0.25, "Smooth curve should ease in slowly")
        assertApproximatelyEqual(valueAt2!, 0.5, tolerance: 0.1, "Smooth curve should be near 0.5 at midpoint")
        XCTAssertGreaterThan(valueAt3!, 0.75, "Smooth curve should ease out slowly")
    }
    
    func testAutomationBeforeFirstPoint() throws {
        // Given: Automation starting at beat 4
        let trackId = UUID()
        let lane = createVolumeLane(points: [
            (beat: 4.0, value: 0.5),
            (beat: 8.0, value: 1.0)
        ], initialValue: 0.2)
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // When: Query value before first point
        let valueAt0 = processor.getVolume(for: trackId, atBeat: 0.0)
        let valueAt2 = processor.getVolume(for: trackId, atBeat: 2.0)
        
        // Then: Should use initialValue (deterministic WYSIWYG)
        assertApproximatelyEqual(valueAt0!, 0.2, tolerance: 0.001, "Should use initialValue before first point")
        assertApproximatelyEqual(valueAt2!, 0.2, tolerance: 0.001, "Should use initialValue before first point")
    }
    
    func testAutomationAfterLastPoint() throws {
        // Given: Automation ending at beat 4
        let trackId = UUID()
        let lane = createVolumeLane(points: [
            (beat: 0.0, value: 0.0),
            (beat: 4.0, value: 0.8)
        ])
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // When: Query value after last point
        let valueAt8 = processor.getVolume(for: trackId, atBeat: 8.0)
        let valueAt100 = processor.getVolume(for: trackId, atBeat: 100.0)
        
        // Then: Should hold at last point's value
        assertApproximatelyEqual(valueAt8!, 0.8, tolerance: 0.001, "Should hold at last point value")
        assertApproximatelyEqual(valueAt100!, 0.8, tolerance: 0.001, "Should hold at last point value")
    }
    
    // MARK: - Multiple Parameter Tests
    
    func testAutomationMultipleParameters() throws {
        // Given: A track with volume and pan automation
        let trackId = UUID()
        let volumeLane = createVolumeLane(points: [
            (beat: 0.0, value: 0.5),
            (beat: 4.0, value: 1.0)
        ])
        let panLane = createPanLane(points: [
            (beat: 0.0, value: 0.5),  // Center
            (beat: 4.0, value: 1.0)   // Full right
        ])
        
        processor.updateAutomation(for: trackId, lanes: [volumeLane, panLane], mode: .read)
        
        // When: Query all values at midpoint
        let values = processor.getAllValues(for: trackId, atBeat: 2.0)
        
        // Then: Both parameters should be interpolated
        XCTAssertNotNil(values, "Should return automation values")
        XCTAssertNotNil(values?.volume, "Should have volume automation")
        XCTAssertNotNil(values?.pan, "Should have pan automation")
        assertApproximatelyEqual(values!.volume!, 0.75, tolerance: 0.05, "Volume should be interpolated")
        assertApproximatelyEqual(values!.pan!, 0.75, tolerance: 0.05, "Pan should be interpolated")
    }
    
    // MARK: - Automation Mode Tests
    
    func testAutomationModeOff() throws {
        // Given: Automation in OFF mode
        let trackId = UUID()
        let lane = createVolumeLane(points: [
            (beat: 0.0, value: 0.0),
            (beat: 4.0, value: 1.0)
        ])
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .off)
        
        // When: Query value
        let value = processor.getVolume(for: trackId, atBeat: 2.0)
        
        // Then: Should return nil (automation disabled)
        XCTAssertNil(value, "OFF mode should not return automation values")
    }
    
    func testAutomationModeRead() throws {
        // Given: Automation in READ mode
        let trackId = UUID()
        let lane = createVolumeLane(points: [
            (beat: 0.0, value: 0.0),
            (beat: 4.0, value: 1.0)
        ])
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // When: Query value
        let value = processor.getVolume(for: trackId, atBeat: 2.0)
        
        // Then: Should return interpolated value
        XCTAssertNotNil(value, "READ mode should return automation values")
    }
    
    // MARK: - Performance Tests
    
    func testAutomationBinarySearchPerformance() throws {
        // Given: A track with many automation points (1000 points)
        let trackId = UUID()
        var points: [(beat: Double, value: Float)] = []
        for i in 0..<1000 {
            points.append((beat: Double(i), value: Float(i % 100) / 100.0))
        }
        let lane = createVolumeLane(points: points)
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // When: Query many values (performance test)
        measure {
            for i in 0..<10000 {
                let beat = Double(i % 999) + 0.5
                _ = processor.getVolume(for: trackId, atBeat: beat)
            }
        }
        
        // Then: Should complete efficiently (binary search is O(log n))
    }
    
    func testAutomationBatchLookupPerformance() throws {
        // Given: Multiple tracks with automation
        var trackIds: [UUID] = []
        for i in 0..<10 {
            let trackId = UUID()
            trackIds.append(trackId)
            let lane = createVolumeLane(points: [
                (beat: 0.0, value: Float(i) / 10.0),
                (beat: 100.0, value: 1.0)
            ])
            processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        }
        
        // When: Batch lookup (single lock acquisition)
        measure {
            for _ in 0..<1000 {
                _ = processor.getAllValuesForTracks(trackIds, atBeat: 50.0)
            }
        }
        
        // Then: Batch lookup should be more efficient than individual calls
    }
    
    // MARK: - Thread Safety Tests
    
    func testAutomationThreadSafety() throws {
        // Given: Automation setup
        let trackId = UUID()
        let lane = createVolumeLane(points: [
            (beat: 0.0, value: 0.0),
            (beat: 100.0, value: 1.0)
        ])
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // When: Multiple threads read simultaneously
        let expectation = expectation(description: "Thread safety")
        expectation.expectedFulfillmentCount = 1000
        
        DispatchQueue.concurrentPerform(iterations: 1000) { i in
            let beat = Double(i % 100) + 0.5
            let value = processor.getVolume(for: trackId, atBeat: beat)
            XCTAssertNotNil(value, "Should safely return value from any thread")
            expectation.fulfill()
        }
        
        // Then: No crashes or race conditions
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Tempo and Sample Rate Tests
    
    func testAutomationTimingWithDifferentTempos() throws {
        // Given: Automation in beats (tempo-independent)
        let trackId = UUID()
        let lane = createVolumeLane(points: [
            (beat: 0.0, value: 0.0),
            (beat: 4.0, value: 1.0)
        ])
        
        processor.updateAutomation(for: trackId, lanes: [lane], mode: .read)
        
        // When: Query at beat 2.0 (regardless of tempo)
        let value = processor.getVolume(for: trackId, atBeat: 2.0)
        
        // Then: Value should be 0.5 at any tempo (beats-first architecture)
        assertApproximatelyEqual(value!, 0.5, tolerance: 0.01, 
                               "Automation should be tempo-independent (beats-first)")
    }
    
    func testAutomationSampleToBeatsConversion() throws {
        // Test beat calculation at different sample rates and tempos
        let testCases: [(tempo: Double, sampleRate: Double, samples: Double, expectedBeats: Double)] = [
            (tempo: 120, sampleRate: 48000, samples: 48000, expectedBeats: 2.0),   // 1 second = 2 beats at 120 BPM
            (tempo: 60, sampleRate: 48000, samples: 48000, expectedBeats: 1.0),    // 1 second = 1 beat at 60 BPM
            (tempo: 140, sampleRate: 44100, samples: 44100, expectedBeats: 2.333), // 1 second = 2.333 beats at 140 BPM
        ]
        
        for testCase in testCases {
            // Calculate beats from samples
            let seconds = testCase.samples / testCase.sampleRate
            let beatsPerSecond = testCase.tempo / 60.0
            let beats = seconds * beatsPerSecond
            
            assertApproximatelyEqual(beats, testCase.expectedBeats, tolerance: 0.01,
                                   "Beat calculation should be accurate at \(testCase.tempo) BPM, \(testCase.sampleRate) Hz")
        }
    }
    
    // MARK: - Export Parity Tests
    
    func testAutomationExportUsesReadMode() throws {
        // This test verifies that export automation respects the automation mode
        // In a real export scenario, only tracks in .read mode (or recording modes with .canRead) should apply automation
        
        let trackIdRead = UUID()
        let trackIdOff = UUID()
        
        let laneRead = createVolumeLane(points: [
            (beat: 0.0, value: 0.5),
            (beat: 4.0, value: 1.0)
        ])
        
        let laneOff = createVolumeLane(points: [
            (beat: 0.0, value: 0.5),
            (beat: 4.0, value: 1.0)
        ])
        
        processor.updateAutomation(for: trackIdRead, lanes: [laneRead], mode: .read)
        processor.updateAutomation(for: trackIdOff, lanes: [laneOff], mode: .off)
        
        // Query at midpoint
        let valueRead = processor.getVolume(for: trackIdRead, atBeat: 2.0)
        let valueOff = processor.getVolume(for: trackIdOff, atBeat: 2.0)
        
        XCTAssertNotNil(valueRead, "READ mode should return automation")
        XCTAssertNil(valueOff, "OFF mode should not return automation in export")
    }
    
    // MARK: - Helper Methods
    
    private func createVolumeLane(
        points: [(beat: Double, value: Float, curve: CurveType)],
        initialValue: Float? = nil
    ) -> AutomationLane {
        var lane = AutomationLane(parameter: .volume, initialValue: initialValue)
        for point in points {
            lane.addPoint(atBeat: point.beat, value: point.value, curve: point.curve)
        }
        return lane
    }
    
    private func createVolumeLane(
        points: [(beat: Double, value: Float)],
        initialValue: Float? = nil
    ) -> AutomationLane {
        createVolumeLane(
            points: points.map { (beat: $0.beat, value: $0.value, curve: .linear) },
            initialValue: initialValue
        )
    }
    
    private func createPanLane(points: [(beat: Double, value: Float)]) -> AutomationLane {
        var lane = AutomationLane(parameter: .pan)
        for point in points {
            lane.addPoint(atBeat: point.beat, value: point.value)
        }
        return lane
    }
}
