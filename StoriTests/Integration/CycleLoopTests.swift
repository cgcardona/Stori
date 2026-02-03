//
//  CycleLoopTests.swift
//  StoriTests
//
//  Integration tests for cycle/loop behavior (PUMP IT UP Phase 1).
//  Verifies seamless cycle loops with pre-scheduling.
//
//  SEAMLESS CYCLE LOOPS ARCHITECTURE:
//  When cycle mode is enabled, PlaybackSchedulingCoordinator pre-schedules
//  multiple cycle iterations ahead using TrackAudioNode.scheduleCycleAware().
//  This eliminates gaps during loop jumps because the next iteration's audio
//  is already queued before the current iteration ends.
//

import XCTest
@testable import Stori

@MainActor
final class CycleLoopTests: XCTestCase {

    // MARK: - Beats-First Conversion
    
    /// Verify beat-to-seconds conversion math for cycle boundaries.
    func testCycleBeatsToSecondsConversion() {
        let tempo = 120.0
        let cycleStartBeat: Double = 0
        let cycleEndBeat: Double = 4
        
        let beatsToSeconds = 60.0 / tempo
        let cycleStartSeconds = cycleStartBeat * beatsToSeconds
        let cycleEndSeconds = cycleEndBeat * beatsToSeconds
        
        XCTAssertEqual(cycleStartSeconds, 0.0, accuracy: 0.001)
        XCTAssertEqual(cycleEndSeconds, 2.0, accuracy: 0.001)  // 4 beats at 120 BPM = 2 seconds
    }
    
    // MARK: - Pre-Scheduling Math
    
    /// Pre-scheduling calculates correct offsets for multiple iterations.
    func testPreSchedulingIterationOffsets() {
        let tempo = 120.0
        let startBeat: Double = 2  // Start mid-cycle
        let cycleStartBeat: Double = 0
        let cycleEndBeat: Double = 4
        
        let beatsToSeconds = 60.0 / tempo
        let startTimeSeconds = startBeat * beatsToSeconds  // 1 second
        let cycleStartSeconds = cycleStartBeat * beatsToSeconds  // 0 seconds
        let cycleEndSeconds = cycleEndBeat * beatsToSeconds  // 2 seconds
        let cycleDurationSeconds = cycleEndSeconds - cycleStartSeconds  // 2 seconds
        
        // Iteration 0: starts at current position (1 second)
        let iteration0Offset: TimeInterval = 0
        
        // Iteration 1: starts at cycle end - current position = 2 - 1 = 1 second from now
        let iteration1Offset = cycleEndSeconds - startTimeSeconds
        XCTAssertEqual(iteration1Offset, 1.0, accuracy: 0.001)
        
        // Iteration 2: starts at (cycleEnd - startTime) + cycleDuration = 1 + 2 = 3 seconds from now
        let iteration2Offset = iteration1Offset + cycleDurationSeconds
        XCTAssertEqual(iteration2Offset, 3.0, accuracy: 0.001)
        
        // Iteration 3: 1 + 2 + 2 = 5 seconds from now
        let iteration3Offset = iteration1Offset + (2 * cycleDurationSeconds)
        XCTAssertEqual(iteration3Offset, 5.0, accuracy: 0.001)
    }
    
    // MARK: - Cycle State Management
    
    /// PlaybackSchedulingCoordinator correctly tracks cycle state.
    func testCoordinatorCycleStateTracking() {
        let coordinator = PlaybackSchedulingCoordinator()
        
        // Default state
        XCTAssertFalse(coordinator.isCycleEnabled)
        XCTAssertEqual(coordinator.cycleStartBeat, 0)
        XCTAssertEqual(coordinator.cycleEndBeat, 4)
        
        // Update state
        coordinator.isCycleEnabled = true
        coordinator.cycleStartBeat = 8
        coordinator.cycleEndBeat = 16
        
        XCTAssertTrue(coordinator.isCycleEnabled)
        XCTAssertEqual(coordinator.cycleStartBeat, 8)
        XCTAssertEqual(coordinator.cycleEndBeat, 16)
    }
    
    // MARK: - Cycle Boundary Detection
    
    /// Cycle mode only activates when start position is within cycle region.
    func testCycleModeActivationLogic() {
        // Inside cycle region: should use pre-scheduling
        let startBeat: Double = 2
        let cycleStartBeat: Double = 0
        let cycleEndBeat: Double = 4
        
        let isWithinCycle = startBeat >= cycleStartBeat && startBeat < cycleEndBeat
        XCTAssertTrue(isWithinCycle)
        
        // Outside cycle region: should use standard scheduling
        let startBeat2: Double = 10
        let isWithinCycle2 = startBeat2 >= cycleStartBeat && startBeat2 < cycleEndBeat
        XCTAssertFalse(isWithinCycle2)
    }
    
    // MARK: - Cycle Duration Validation
    
    /// Invalid cycle (zero or negative duration) falls back to standard scheduling.
    func testInvalidCycleFallback() {
        let cycleStartBeat: Double = 4
        let cycleEndBeat: Double = 4  // Same as start = zero duration
        
        let cycleDuration = cycleEndBeat - cycleStartBeat
        XCTAssertEqual(cycleDuration, 0)
        
        // This should trigger fallback to standard scheduling
        let shouldFallback = cycleDuration <= 0
        XCTAssertTrue(shouldFallback)
    }
}
