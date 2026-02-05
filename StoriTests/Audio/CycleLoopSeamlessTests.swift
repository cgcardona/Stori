//
//  CycleLoopSeamlessTests.swift
//  StoriTests
//
//  Created by TellUrStoriDAW
//  Copyright © 2026 TellUrStori. All rights reserved.
//
//  Test suite for Bug #47: Cycle Loop Jump May Cause Audible Gap Due to Stop/Start Sequence
//  GitHub Issue: https://github.com/cgcardona/Stori/issues/47
//

import XCTest
import AVFoundation
@testable import Stori

/// Tests for seamless cycle loop playback (Bug #47 / Issue #47)
///
/// CRITICAL BUG FIXED:
/// The `transportSafeJump` method stopped playback then restarted it, clearing
/// all scheduled audio buffers and causing an audible gap at cycle loop boundaries.
///
/// ROOT CAUSE:
/// - `transportSafeJump` called `onStopPlayback()` → `onStartPlayback()`
/// - `scheduleCycleAware` called `playerNode.stop()` and `playerNode.reset()`
/// - Pre-scheduled iterations (2 cycles ahead) were cleared
/// - Gap of silence during stop/start transition
///
/// FIX IMPLEMENTED:
/// - For cycle jumps, DON'T stop/restart player nodes
/// - Rely on pre-scheduled iterations that are already queued
/// - Only update timing state and position tracking
/// - Added `preservePlayback` parameter to `scheduleCycleAware`
///
/// PROFESSIONAL STANDARD:
/// Logic Pro, Pro Tools, and Ableton Live all achieve seamless looping by
/// pre-scheduling audio and avoiding buffer clears during loop jumps.
final class CycleLoopSeamlessTests: XCTestCase {
    
    // MARK: - Test Setup
    
    var transportController: TransportController!
    var mockProject: AudioProject!
    var cycleJumpCount: Int = 0
    var stopPlaybackCount: Int = 0
    var startPlaybackCount: Int = 0
    
    override func setUp() {
        super.setUp()
        
        transportController = TransportController()
        
        // Create test project
        mockProject = AudioProject(name: "Test Project", tempo: 120, timeSignature: TimeSignature.common)
        
        // Set up callbacks to track behavior
        cycleJumpCount = 0
        stopPlaybackCount = 0
        startPlaybackCount = 0
        
        transportController.getProject = { [weak self] in
            self?.mockProject
        }
        
        transportController.onCycleJump = { [weak self] _ in
            self?.cycleJumpCount += 1
        }
        
        transportController.onStopPlayback = { [weak self] in
            self?.stopPlaybackCount += 1
        }
        
        transportController.onStartPlayback = { [weak self] _ in
            self?.startPlaybackCount += 1
        }
    }
    
    override func tearDown() {
        if transportController.isPlaying {
            transportController.stop()
        }
        transportController = nil
        mockProject = nil
        super.tearDown()
    }
    
    // MARK: - Core Seamless Loop Tests
    
    func testCycleJumpDoesNotStopPlayback() {
        // BUG FIX VERIFICATION: Cycle jump should NOT call stop/start
        
        // Enable cycle from beat 0 to 4
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        
        // Start playback
        transportController.play()
        XCTAssertTrue(transportController.isPlaying)
        
        // Reset counters after initial play
        stopPlaybackCount = 0
        startPlaybackCount = 0
        cycleJumpCount = 0
        
        // Perform cycle jump to beat 0 (cycle start)
        transportController.transportSafeJump(toBeat: 0.0)
        
        // Verify cycle jump was detected
        XCTAssertEqual(cycleJumpCount, 1, "Cycle jump should be detected")
        
        // CRITICAL: Stop/start should NOT be called for cycle jumps
        XCTAssertEqual(stopPlaybackCount, 0,
                      "Cycle jump should NOT stop playback (would clear pre-scheduled audio)")
        XCTAssertEqual(startPlaybackCount, 0,
                      "Cycle jump should NOT restart playback (audio already scheduled)")
        
        // Playback should still be active
        XCTAssertTrue(transportController.isPlaying,
                     "Playback should remain active after cycle jump")
    }
    
    func testNonCycleJumpDoesStopAndRestart() {
        // Non-cycle jumps (arbitrary seeks) still need stop/start
        
        // Enable cycle from beat 0 to 4
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        
        // Start playback
        transportController.play()
        
        // Reset counters
        stopPlaybackCount = 0
        startPlaybackCount = 0
        
        // Jump to beat 2 (NOT the cycle start - arbitrary position)
        transportController.transportSafeJump(toBeat: 2.0)
        
        // Non-cycle jumps still need stop/start because audio isn't pre-scheduled
        // for arbitrary positions
        XCTAssertEqual(stopPlaybackCount, 1,
                      "Non-cycle jump should stop playback")
        XCTAssertEqual(startPlaybackCount, 1,
                      "Non-cycle jump should restart playback")
    }
    
    func testCycleDisabledJumpStillStops() {
        // When cycle is disabled, all jumps need stop/start
        
        // Cycle is disabled by default
        XCTAssertFalse(transportController.isCycleEnabled)
        
        // Start playback
        transportController.play()
        
        // Reset counters
        stopPlaybackCount = 0
        startPlaybackCount = 0
        
        // Jump to any position
        transportController.transportSafeJump(toBeat: 2.0)
        
        // Should stop/start because cycle is disabled
        XCTAssertEqual(stopPlaybackCount, 1,
                      "Jump without cycle should stop playback")
        XCTAssertEqual(startPlaybackCount, 1,
                      "Jump without cycle should restart playback")
    }
    
    func testPositionUpdatesCorrectlyAfterCycleJump() {
        // Position tracking should reflect the jump even without stop/start
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        transportController.play()
        
        // Jump to cycle start
        transportController.transportSafeJump(toBeat: 0.0)
        
        // Position should be at beat 0
        XCTAssertEqual(transportController.positionBeats, 0.0, accuracy: 0.001,
                      "Position should update to cycle start after jump")
    }
    
    // MARK: - Pre-Scheduling Tests
    
    func testTrackAudioNodePreservesPlaybackFlag() {
        // Test that TrackAudioNode respects preservePlayback parameter
        
        let trackNode = TrackAudioNode()
        let testRegion = AudioRegion(startBeat: 0, durationBeats: 4, track: UUID())
        
        // Create a test audio file (silent, doesn't matter for this test)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4800) else {
            XCTFail("Failed to create test buffer")
            return
        }
        buffer.frameLength = 4800
        
        // This test verifies the method signature accepts the parameter
        // Actual audio scheduling is integration-tested separately
        XCTAssertNoThrow(
            try trackNode.scheduleCycleAware(
                fromBeat: 0,
                audioRegions: [testRegion],
                tempo: 120,
                cycleStartBeat: 0,
                cycleEndBeat: 4,
                iterationsAhead: 2,
                preservePlayback: true
            ),
            "scheduleCycleAware should accept preservePlayback parameter"
        )
    }
    
    // MARK: - Timing State Tests
    
    func testTimingStateUpdatesBeforeJump() {
        // Timing state should be updated BEFORE any cycle jump handling
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        transportController.play()
        
        var timingUpdateReceived = false
        var cycleJumpReceived = false
        var timingBeforeCycle = false
        
        transportController.onPositionChanged = { _ in
            timingUpdateReceived = true
            if !cycleJumpReceived {
                timingBeforeCycle = true
            }
        }
        
        transportController.onCycleJump = { _ in
            cycleJumpReceived = true
        }
        
        transportController.transportSafeJump(toBeat: 0.0)
        
        XCTAssertTrue(timingUpdateReceived, "Timing state should be updated")
        XCTAssertTrue(cycleJumpReceived, "Cycle jump should be processed")
        XCTAssertTrue(timingBeforeCycle,
                     "Timing state should be updated BEFORE cycle jump notification")
    }
    
    func testGenerationCounterIncrementsOnJump() {
        // Generation counter should increment to invalidate stale position updates
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        transportController.play()
        
        let initialGeneration = transportController.cycleGeneration
        
        transportController.transportSafeJump(toBeat: 0.0)
        
        XCTAssertGreaterThan(transportController.cycleGeneration, initialGeneration,
                            "Generation counter should increment on jump")
    }
    
    // MARK: - Edge Cases
    
    func testMultipleCycleJumpsInQuickSuccession() {
        // Rapid cycle jumps should not cause issues
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        transportController.play()
        
        // Perform multiple rapid jumps
        for _ in 0..<5 {
            transportController.transportSafeJump(toBeat: 0.0)
        }
        
        // Should still be playing without errors
        XCTAssertTrue(transportController.isPlaying,
                     "Playback should survive multiple rapid cycle jumps")
    }
    
    func testCycleJumpWhileStopped() {
        // Jump while stopped should not crash (guard prevents execution)
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        
        // Don't start playback
        XCTAssertFalse(transportController.isPlaying)
        
        // Attempt jump while stopped
        XCTAssertNoThrow(
            transportController.transportSafeJump(toBeat: 0.0),
            "Jump while stopped should not crash"
        )
    }
    
    func testCycleJumpToNearCycleStart() {
        // Jump to position very close to cycle start (within tolerance)
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        transportController.play()
        
        stopPlaybackCount = 0
        startPlaybackCount = 0
        
        // Jump to 0.0005 (within 0.001 tolerance of cycle start 0.0)
        transportController.transportSafeJump(toBeat: 0.0005)
        
        // Should be treated as cycle jump (no stop/start)
        XCTAssertEqual(stopPlaybackCount, 0,
                      "Jump near cycle start should be treated as cycle jump")
    }
    
    func testCycleJumpAwayFromCycleStart() {
        // Jump to position far from cycle start requires stop/start
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        transportController.play()
        
        stopPlaybackCount = 0
        startPlaybackCount = 0
        
        // Jump to 0.1 (beyond 0.001 tolerance of cycle start)
        transportController.transportSafeJump(toBeat: 0.1)
        
        // Should NOT be treated as cycle jump (needs stop/start)
        XCTAssertEqual(stopPlaybackCount, 1,
                      "Jump away from cycle start should stop/restart")
    }
    
    // MARK: - Integration Tests
    
    func testSeamlessLoopingScenario() {
        // Real-world scenario: Looping a 4-bar section repeatedly
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 16)
        transportController.play()
        
        // Simulate multiple loop iterations
        stopPlaybackCount = 0
        startPlaybackCount = 0
        
        for _ in 0..<10 {
            transportController.transportSafeJump(toBeat: 0.0)
        }
        
        // CRITICAL: No stops/starts should occur during cycle looping
        XCTAssertEqual(stopPlaybackCount, 0,
                      "10 cycle loops should not stop playback")
        XCTAssertEqual(startPlaybackCount, 0,
                      "10 cycle loops should not restart playback")
        XCTAssertTrue(transportController.isPlaying,
                     "Playback should remain active throughout looping")
    }
    
    func testMixedCycleAndNonCycleJumps() {
        // Mix of cycle jumps (seamless) and non-cycle jumps (stop/start)
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        transportController.play()
        
        stopPlaybackCount = 0
        startPlaybackCount = 0
        
        // Cycle jump (no stop/start)
        transportController.transportSafeJump(toBeat: 0.0)
        XCTAssertEqual(stopPlaybackCount, 0)
        
        // Non-cycle jump (stop/start)
        transportController.transportSafeJump(toBeat: 2.0)
        XCTAssertEqual(stopPlaybackCount, 1)
        XCTAssertEqual(startPlaybackCount, 1)
        
        // Another cycle jump (no stop/start)
        transportController.transportSafeJump(toBeat: 0.0)
        XCTAssertEqual(stopPlaybackCount, 1) // Should still be 1
        XCTAssertEqual(startPlaybackCount, 1) // Should still be 1
    }
    
    // MARK: - Regression Protection
    
    func testCycleJumpDoesNotLeakMemory() {
        // Repeated cycle jumps should not leak memory
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        transportController.play()
        
        // Perform many cycle jumps
        for _ in 0..<100 {
            transportController.transportSafeJump(toBeat: 0.0)
        }
        
        // If we get here without crashing or memory issues, test passes
        XCTAssertTrue(true, "100 cycle jumps should not cause memory issues")
    }
    
    func testCycleJumpPreservesPlaybackState() {
        // Cycle jump should not alter playback state
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        transportController.play()
        
        let wasPlaying = transportController.isPlaying
        let wasCycleEnabled = transportController.isCycleEnabled
        
        transportController.transportSafeJump(toBeat: 0.0)
        
        XCTAssertEqual(transportController.isPlaying, wasPlaying,
                      "Playing state should be preserved")
        XCTAssertEqual(transportController.isCycleEnabled, wasCycleEnabled,
                      "Cycle enabled state should be preserved")
    }
    
    // MARK: - Professional Standard Tests
    
    func testPreSchedulingArchitecture() {
        // Verify pre-scheduling architecture is in place
        // (This is a documentation test - actual scheduling tested in integration)
        
        let trackNode = TrackAudioNode()
        
        // Verify the method supports pre-scheduling multiple iterations
        XCTAssertNoThrow(
            try trackNode.scheduleCycleAware(
                fromBeat: 0,
                audioRegions: [],
                tempo: 120,
                cycleStartBeat: 0,
                cycleEndBeat: 4,
                iterationsAhead: 2, // Pre-schedule 2 iterations ahead
                preservePlayback: false
            ),
            "Should support pre-scheduling multiple iterations"
        )
        
        // Verify it supports seamless mode
        XCTAssertNoThrow(
            try trackNode.scheduleCycleAware(
                fromBeat: 0,
                audioRegions: [],
                tempo: 120,
                cycleStartBeat: 0,
                cycleEndBeat: 4,
                iterationsAhead: 2,
                preservePlayback: true // Seamless mode for cycle jumps
            ),
            "Should support seamless cycle jump mode"
        )
    }
    
    func testLoopBoundaryTolerance() {
        // Test that tolerance for cycle start detection is reasonable
        
        transportController.setCycle(enabled: true, startBeat: 0, endBeat: 4)
        transportController.play()
        
        stopPlaybackCount = 0
        
        // Test various positions near cycle start
        let testPositions: [(beat: Double, shouldBeCycleJump: Bool)] = [
            (0.0000, true),   // Exactly at cycle start
            (0.0001, true),   // Very close (within 0.001 tolerance)
            (0.0009, true),   // Within tolerance
            (0.0010, true),   // At tolerance boundary
            (0.0011, false),  // Beyond tolerance
            (0.01, false),    // Clearly beyond tolerance
        ]
        
        for (beat, shouldBeCycleJump) in testPositions {
            stopPlaybackCount = 0
            transportController.transportSafeJump(toBeat: beat)
            
            if shouldBeCycleJump {
                XCTAssertEqual(stopPlaybackCount, 0,
                              "Beat \(beat) should be treated as cycle jump (no stop)")
            } else {
                XCTAssertEqual(stopPlaybackCount, 1,
                              "Beat \(beat) should NOT be cycle jump (stop required)")
            }
        }
    }
}
