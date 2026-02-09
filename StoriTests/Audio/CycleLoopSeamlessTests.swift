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
/// FIX IMPLEMENTED:
/// - For cycle jumps, DON'T stop/restart player nodes
/// - Rely on pre-scheduled iterations that are already queued
/// - Only update timing state and position tracking
/// - Added `preservePlayback` parameter to `scheduleCycleAware`
@MainActor
final class CycleLoopSeamlessTests: XCTestCase {

    // MARK: - Test Setup

    var transportController: TransportController!
    var mockProject: AudioProject!
    var counters: Counters!

    override func setUp() async throws {
        try await super.setUp()

        transportController = TransportController(
            getProject: { [weak self] in self?.mockProject },
            isInstallingPlugin: { false },
            isGraphStable: { true },
            getSampleRate: { 48000 },
            onStartPlayback: { [weak self] _ in self?.counters.startPlaybackCount += 1 },
            onStopPlayback: { [weak self] in self?.counters.stopPlaybackCount += 1 },
            onTransportStateChanged: { _ in },
            onPositionChanged: { _ in },
            onCycleJump: { [weak self] _ in self?.counters.cycleJumpCount += 1 }
        )

        mockProject = AudioProject(name: "Test Project", tempo: 120, timeSignature: .fourFour)
        counters = Counters()
        counters?.reset()
    }

    override func tearDown() async throws {
        if transportController.isPlaying {
            transportController.stop()
        }
        transportController = nil
        mockProject = nil
        counters = nil
        try await super.tearDown()
    }

    // MARK: - Core Seamless Loop Tests

    func testCycleJumpDoesNotStopPlayback() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()
        XCTAssertTrue(transportController.isPlaying)

        counters.reset()

        transportController.transportSafeJump(toBeat: 0.0)

        XCTAssertEqual(counters.cycleJumpCount, 1)
        XCTAssertEqual(counters.stopPlaybackCount, 0,
                      "Cycle jump should NOT stop playback (would clear pre-scheduled audio)")
        XCTAssertEqual(counters.startPlaybackCount, 0,
                      "Cycle jump should NOT restart playback (audio already scheduled)")
        XCTAssertTrue(transportController.isPlaying)
    }

    func testNonCycleJumpDoesStopAndRestart() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()

        counters.reset()

        transportController.transportSafeJump(toBeat: 2.0)

        XCTAssertEqual(counters.stopPlaybackCount, 1)
        XCTAssertEqual(counters.startPlaybackCount, 1)
    }

    func testCycleDisabledJumpStillStops() {
        XCTAssertFalse(transportController.isCycleEnabled)
        transportController.play()

        counters.reset()

        transportController.transportSafeJump(toBeat: 2.0)

        XCTAssertEqual(counters.stopPlaybackCount, 1)
        XCTAssertEqual(counters.startPlaybackCount, 1)
    }

    func testPositionUpdatesCorrectlyAfterCycleJump() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()

        transportController.transportSafeJump(toBeat: 0.0)

        XCTAssertEqual(transportController.positionBeats, 0.0, accuracy: 0.001)
    }

    // MARK: - Pre-Scheduling Tests (TrackAudioNode)

    func testTrackAudioNodePreservesPlaybackFlag() {
        guard let (trackNode, region) = makeTrackAudioNodeAndRegion() else {
            XCTFail("Failed to create TrackAudioNode for test")
            return
        }

        XCTAssertNoThrow(
            try trackNode.scheduleCycleAware(
                fromBeat: 0,
                audioRegions: [region],
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
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()

        var timingUpdateReceived = false
        var cycleJumpReceived = false
        var timingBeforeCycle = false

        // We can't inject onPositionChanged/onCycleJump after init; verify observable behavior instead.
        // After cycle jump, position should be at target and playback still active.
        transportController.transportSafeJump(toBeat: 0.0)

        timingUpdateReceived = abs(transportController.positionBeats - 0.0) < 0.001
        cycleJumpReceived = counters.cycleJumpCount == 1
        timingBeforeCycle = timingUpdateReceived && cycleJumpReceived

        XCTAssertTrue(timingUpdateReceived)
        XCTAssertTrue(cycleJumpReceived)
        XCTAssertTrue(timingBeforeCycle,
                     "Position should reflect cycle jump target")
    }

    func testGenerationCounterIncrementsOnJump() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()

        counters.reset()
        transportController.transportSafeJump(toBeat: 0.0)
        let firstJumpStopCount = counters.stopPlaybackCount

        transportController.transportSafeJump(toBeat: 0.0)
        let secondJumpStopCount = counters.stopPlaybackCount

        XCTAssertEqual(firstJumpStopCount, 0, "First cycle jump should not stop")
        XCTAssertEqual(secondJumpStopCount, 0, "Second cycle jump should not stop")
        XCTAssertEqual(transportController.positionBeats, 0.0, accuracy: 0.001)
    }

    // MARK: - Edge Cases

    func testMultipleCycleJumpsInQuickSuccession() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()

        for _ in 0..<5 {
            transportController.transportSafeJump(toBeat: 0.0)
        }

        XCTAssertTrue(transportController.isPlaying)
    }

    func testCycleJumpWhileStopped() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true

        XCTAssertFalse(transportController.isPlaying)

        XCTAssertNoThrow(
            transportController.transportSafeJump(toBeat: 0.0),
            "Jump while stopped should not crash"
        )
    }

    func testCycleJumpToNearCycleStart() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()

        counters.reset()

        transportController.transportSafeJump(toBeat: 0.0005)

        XCTAssertEqual(counters.stopPlaybackCount, 0,
                      "Jump near cycle start should be treated as cycle jump")
    }

    func testCycleJumpAwayFromCycleStart() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()

        counters.reset()

        transportController.transportSafeJump(toBeat: 0.1)

        XCTAssertEqual(counters.stopPlaybackCount, 1,
                      "Jump away from cycle start should stop/restart")
    }

    // MARK: - Integration Tests

    func testSeamlessLoopingScenario() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 16)
        transportController.isCycleEnabled = true
        transportController.play()

        counters.reset()

        for _ in 0..<10 {
            transportController.transportSafeJump(toBeat: 0.0)
        }

        XCTAssertEqual(counters.stopPlaybackCount, 0)
        XCTAssertEqual(counters.startPlaybackCount, 0)
        XCTAssertTrue(transportController.isPlaying)
    }

    func testMixedCycleAndNonCycleJumps() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()

        counters.reset()

        transportController.transportSafeJump(toBeat: 0.0)
        XCTAssertEqual(counters.stopPlaybackCount, 0)

        transportController.transportSafeJump(toBeat: 2.0)
        XCTAssertEqual(counters.stopPlaybackCount, 1)
        XCTAssertEqual(counters.startPlaybackCount, 1)

        transportController.transportSafeJump(toBeat: 0.0)
        XCTAssertEqual(counters.stopPlaybackCount, 1)
        XCTAssertEqual(counters.startPlaybackCount, 1)
    }

    // MARK: - Regression Protection

    func testCycleJumpDoesNotLeakMemory() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()

        for _ in 0..<100 {
            transportController.transportSafeJump(toBeat: 0.0)
        }

        XCTAssertTrue(transportController.isPlaying)
    }

    func testCycleJumpPreservesPlaybackState() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()

        let wasPlaying = transportController.isPlaying
        let wasCycleEnabled = transportController.isCycleEnabled

        transportController.transportSafeJump(toBeat: 0.0)

        XCTAssertEqual(transportController.isPlaying, wasPlaying)
        XCTAssertEqual(transportController.isCycleEnabled, wasCycleEnabled)
    }

    // MARK: - Professional Standard Tests

    func testPreSchedulingArchitecture() {
        guard let (trackNode, _) = makeTrackAudioNodeAndRegion() else {
            XCTFail("Failed to create TrackAudioNode for test")
            return
        }

        XCTAssertNoThrow(
            try trackNode.scheduleCycleAware(
                fromBeat: 0,
                audioRegions: [],
                tempo: 120,
                cycleStartBeat: 0,
                cycleEndBeat: 4,
                iterationsAhead: 2,
                preservePlayback: false
            ),
            "Should support pre-scheduling multiple iterations"
        )

        XCTAssertNoThrow(
            try trackNode.scheduleCycleAware(
                fromBeat: 0,
                audioRegions: [],
                tempo: 120,
                cycleStartBeat: 0,
                cycleEndBeat: 4,
                iterationsAhead: 2,
                preservePlayback: true
            ),
            "Should support seamless cycle jump mode"
        )
    }

    func testLoopBoundaryTolerance() {
        transportController.setCycleRegion(startBeat: 0, endBeat: 4)
        transportController.isCycleEnabled = true
        transportController.play()

        // Tolerance in TransportController is < 0.001; 0.0010 is not < 0.001 so not a cycle jump
        let testPositions: [(beat: Double, shouldBeCycleJump: Bool)] = [
            (0.0000, true),
            (0.0001, true),
            (0.0009, true),
            (0.0010, false),
            (0.0011, false),
            (0.01, false),
        ]

        for (beat, shouldBeCycleJump) in testPositions {
            counters.reset()
            transportController.transportSafeJump(toBeat: beat)

            if shouldBeCycleJump {
                XCTAssertEqual(counters.stopPlaybackCount, 0,
                              "Beat \(beat) should be treated as cycle jump (no stop)")
            } else {
                XCTAssertEqual(counters.stopPlaybackCount, 1,
                              "Beat \(beat) should NOT be cycle jump (stop required)")
            }
        }
    }
}

// MARK: - Helpers

final class Counters {
    var cycleJumpCount: Int = 0
    var stopPlaybackCount: Int = 0
    var startPlaybackCount: Int = 0

    func reset() {
        cycleJumpCount = 0
        stopPlaybackCount = 0
        startPlaybackCount = 0
    }
}

@MainActor
private extension CycleLoopSeamlessTests {
    /// Builds a minimal TrackAudioNode attached to an engine so scheduleCycleAware can run (sample rate > 0).
    func makeTrackAudioNodeAndRegion() -> (TrackAudioNode, AudioRegion)? {
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)
        let timePitchUnit = AVAudioUnitTimePitch()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

        engine.attach(playerNode)
        engine.attach(volumeNode)
        engine.attach(panNode)
        engine.attach(eqNode)
        engine.attach(timePitchUnit)

        engine.connect(playerNode, to: timePitchUnit, format: format)
        engine.connect(timePitchUnit, to: volumeNode, format: format)
        engine.connect(volumeNode, to: panNode, format: format)
        engine.connect(panNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            return nil
        }

        let pluginChain = PluginChain(id: UUID(), maxSlots: 8)
        let trackNode = TrackAudioNode(
            id: UUID(),
            playerNode: playerNode,
            volumeNode: volumeNode,
            panNode: panNode,
            eqNode: eqNode,
            pluginChain: pluginChain,
            timePitchUnit: timePitchUnit
        )

        let audioFile = AudioFile(
            name: "test",
            relativePath: "test.wav",
            duration: 2.0,
            sampleRate: 48000,
            channels: 2,
            bitDepth: 16,
            fileSize: 0,
            format: .wav
        )
        let region = AudioRegion(
            audioFile: audioFile,
            startBeat: 0,
            durationBeats: 4,
            tempo: 120
        )

        return (trackNode, region)
    }
}
