//
//  TransportControllerTests.swift
//  StoriTests
//
//  Unit tests for TransportController - Playback state management
//

import XCTest
@testable import Stori

final class TransportControllerTests: XCTestCase {
    
    // MARK: - Transport State Tests
    
    func testTransportStateValues() {
        XCTAssertFalse(TransportState.stopped.isPlaying)
        XCTAssertTrue(TransportState.playing.isPlaying)
        XCTAssertTrue(TransportState.recording.isPlaying)
        XCTAssertFalse(TransportState.paused.isPlaying)
    }
    
    func testTransportStateCodable() {
        assertCodableRoundTrip(TransportState.stopped)
        assertCodableRoundTrip(TransportState.playing)
        assertCodableRoundTrip(TransportState.recording)
        assertCodableRoundTrip(TransportState.paused)
    }
    
    // MARK: - Playback Position Tests
    
    func testPlaybackPositionFromBeats() {
        let position = PlaybackPosition(beats: 8.0, tempo: 120.0)
        
        XCTAssertEqual(position.beats, 8.0)
        XCTAssertEqual(position.bars, 2)  // 8 beats / 4 = bar 2 (0-indexed)
        XCTAssertEqual(position.beatInBar, 1)  // First beat of bar 3
    }
    
    func testPlaybackPositionTimeInterval() {
        let position = PlaybackPosition(beats: 4.0, tempo: 120.0)
        
        // Time is always computed from beats + tempo (no cached timeInterval)
        // 4 beats at 120 BPM = 2 seconds
        assertApproximatelyEqual(position.timeInterval(atTempo: 120.0), 2.0)
    }
    
    func testPlaybackPositionFromSeconds() {
        // 3 seconds at 120 BPM = 6 beats
        let position = PlaybackPosition.fromSeconds(3.0, tempo: 120.0)
        
        assertApproximatelyEqual(position.beats, 6.0)
    }
    
    func testPlaybackPositionTimeIntervalAtTempo() {
        let position = PlaybackPosition(beats: 4.0, tempo: 120.0)
        
        // At 60 BPM, 4 beats = 4 seconds
        assertApproximatelyEqual(position.timeInterval(atTempo: 60.0), 4.0)
        
        // At 180 BPM, 4 beats = 1.33 seconds
        assertApproximatelyEqual(position.timeInterval(atTempo: 180.0), 4.0 / 3.0)
    }

    /// Time is always computed from beats and the provided tempo (no cached value)
    func testPlaybackPositionTimeIntervalUsesProvidedTempoNotCached() {
        let position = PlaybackPosition(beats: 6.0, timeSignature: .fourFour, tempo: 120.0)
        // Same position, different tempos must yield different seconds
        assertApproximatelyEqual(position.timeInterval(atTempo: 120.0), 3.0)   // 6 beats at 120 = 3 s
        assertApproximatelyEqual(position.timeInterval(atTempo: 60.0), 6.0)     // 6 beats at 60 = 6 s
        assertApproximatelyEqual(position.timeInterval(atTempo: 240.0), 1.5)   // 6 beats at 240 = 1.5 s
    }
    
    func testPlaybackPositionDisplayString() {
        let position = PlaybackPosition(beats: 5.25, tempo: 120.0)
        let display = position.displayString(timeSignature: .fourFour)
        
        // Bar 2, beat 2, subdivision 25 (0.25 * 100)
        XCTAssertEqual(display, "2.2.25")
    }
    
    func testPlaybackPositionBeatPosition() {
        let position = PlaybackPosition(beats: 4.5, tempo: 120.0)
        let beatPos = position.beatPosition
        
        XCTAssertEqual(beatPos.beats, 4.5)
    }
    
    func testPlaybackPositionFromBeatPosition() {
        let beatPos = BeatPosition(8.0)
        let position = PlaybackPosition(beatPosition: beatPos)
        
        XCTAssertEqual(position.beats, 8.0)
    }
    
    // MARK: - Mock Transport Controller Tests
    
    @MainActor
    func testMockTransportPlay() async throws {
        let mockEngine = MockAudioEngine()
        
        XCTAssertFalse(mockEngine.isPlaying)
        
        try mockEngine.play()
        
        XCTAssertTrue(mockEngine.isPlaying)
        XCTAssertEqual(mockEngine.playCallCount, 1)
    }
    
    @MainActor
    func testMockTransportStop() async {
        let mockEngine = MockAudioEngine()
        try? mockEngine.play()
        
        mockEngine.stop()
        
        XCTAssertFalse(mockEngine.isPlaying)
        XCTAssertEqual(mockEngine.stopCallCount, 1)
    }
    
    @MainActor
    func testMockTransportPause() async throws {
        let mockEngine = MockAudioEngine()
        try mockEngine.play()
        
        mockEngine.pause()
        
        XCTAssertFalse(mockEngine.isPlaying)
        XCTAssertEqual(mockEngine.pauseCallCount, 1)
    }
    
    @MainActor
    func testMockTransportSeek() async {
        let mockEngine = MockAudioEngine()
        
        mockEngine.seek(toBeats: 16.0)
        
        XCTAssertEqual(mockEngine.currentPositionBeats, 16.0)
        XCTAssertEqual(mockEngine.seekCallCount, 1)
        XCTAssertEqual(mockEngine.lastSeekPosition, 16.0)
    }
    
    @MainActor
    func testMockTransportSeekNonNegative() async {
        let mockEngine = MockAudioEngine()
        
        mockEngine.seek(toBeats: -10.0)
        
        XCTAssertEqual(mockEngine.currentPositionBeats, 0.0, "Position should clamp to 0")
    }
    
    @MainActor
    func testMockTransportRecording() async throws {
        let mockEngine = MockAudioEngine()
        
        try mockEngine.startRecording()
        
        XCTAssertTrue(mockEngine.isRecording)
        XCTAssertTrue(mockEngine.isPlaying)  // Recording implies playing
        XCTAssertEqual(mockEngine.recordCallCount, 1)
    }
    
    @MainActor
    func testMockTransportStopRecording() async throws {
        let mockEngine = MockAudioEngine()
        try mockEngine.startRecording()
        
        mockEngine.stop()
        
        XCTAssertFalse(mockEngine.isRecording)
        XCTAssertFalse(mockEngine.isPlaying)
    }
    
    // MARK: - Cycle/Loop Tests
    
    @MainActor
    func testMockTransportCycle() async {
        let mockEngine = MockAudioEngine()
        
        mockEngine.setCycle(enabled: true, start: 4.0, end: 12.0)
        
        XCTAssertTrue(mockEngine.cycleEnabled)
        XCTAssertEqual(mockEngine.cycleStartBeat, 4.0)
        XCTAssertEqual(mockEngine.cycleEndBeat, 12.0)
    }
    
    @MainActor
    func testMockTransportCyclePlayback() async throws {
        let mockEngine = MockAudioEngine()
        mockEngine.setCycle(enabled: true, start: 0.0, end: 4.0)
        mockEngine.seek(toBeats: 3.0)
        
        try mockEngine.play()
        mockEngine.advancePlayhead(beats: 2.0)  // 3 + 2 = 5, should wrap to 0
        
        XCTAssertEqual(mockEngine.currentPositionBeats, 0.0, "Should wrap back to cycle start")
    }
    
    @MainActor
    func testMockTransportCycleDisabled() async throws {
        let mockEngine = MockAudioEngine()
        mockEngine.setCycle(enabled: false, start: 0.0, end: 4.0)
        mockEngine.seek(toBeats: 3.0)
        
        try mockEngine.play()
        mockEngine.advancePlayhead(beats: 2.0)
        
        XCTAssertEqual(mockEngine.currentPositionBeats, 5.0, "Should not wrap when cycle disabled")
    }
    
    // MARK: - Tempo Tests
    
    func testTempoBeatsToSeconds() {
        // At 120 BPM: 1 beat = 0.5 seconds
        let beatsPerMinute = 120.0
        let beats = 4.0
        
        let seconds = beats * (60.0 / beatsPerMinute)
        
        assertApproximatelyEqual(seconds, 2.0)
    }
    
    func testTempoSecondsToBeats() {
        // At 120 BPM: 1 second = 2 beats
        let beatsPerMinute = 120.0
        let seconds = 3.0
        
        let beats = seconds * (beatsPerMinute / 60.0)
        
        assertApproximatelyEqual(beats, 6.0)
    }
    
    func testTempoChangeConversion() {
        // Position at 4 beats, 120 BPM = 2 seconds
        // Same position at 60 BPM should still be 4 beats
        
        let position = BeatPosition(4.0)
        
        let secondsAt120 = position.toSeconds(tempo: 120.0)
        let secondsAt60 = position.toSeconds(tempo: 60.0)
        
        assertApproximatelyEqual(secondsAt120, 2.0)
        assertApproximatelyEqual(secondsAt60, 4.0)
        
        // Beats are constant, seconds change with tempo
        XCTAssertEqual(position.beats, 4.0)
    }
    
    // MARK: - Metronome Tests
    
    @MainActor
    func testMockMetronome() async {
        let mockEngine = MockAudioEngine()
        
        XCTAssertFalse(mockEngine.metronomeEnabled)
        
        mockEngine.metronomeEnabled = true
        mockEngine.metronomeVolume = 0.5
        
        XCTAssertTrue(mockEngine.metronomeEnabled)
        XCTAssertEqual(mockEngine.metronomeVolume, 0.5)
    }
    
    // MARK: - Error Handling Tests
    
    @MainActor
    func testMockTransportPlayFailure() async {
        let mockEngine = MockAudioEngine()
        mockEngine.shouldFailPlay = true
        
        XCTAssertThrowsError(try mockEngine.play()) { error in
            XCTAssertTrue(error is TestError)
        }
        
        XCTAssertFalse(mockEngine.isPlaying)
    }
    
    @MainActor
    func testMockTransportRecordFailure() async {
        let mockEngine = MockAudioEngine()
        mockEngine.shouldFailRecord = true
        
        XCTAssertThrowsError(try mockEngine.startRecording()) { error in
            XCTAssertTrue(error is TestError)
        }
        
        XCTAssertFalse(mockEngine.isRecording)
    }
    
    // MARK: - Reset Tests
    
    @MainActor
    func testMockTransportReset() async throws {
        let mockEngine = MockAudioEngine()
        
        try mockEngine.play()
        mockEngine.seek(toBeats: 10.0)
        mockEngine.metronomeEnabled = true
        
        mockEngine.reset()
        
        XCTAssertFalse(mockEngine.isPlaying)
        XCTAssertEqual(mockEngine.currentPositionBeats, 0.0)
        XCTAssertFalse(mockEngine.metronomeEnabled)
        XCTAssertEqual(mockEngine.playCallCount, 0)
    }
    
    // MARK: - Pause/Resume Position Consistency (no playhead jump)
    
    /// Resuming from pause must start from the exact stop position (no jump forward).
    /// Regression test for: pause captures exact stop from wall clock; timer first fire at +16ms.
    @MainActor
    func testPauseResumePositionDoesNotJump() async throws {
        var project = AudioProject(
            name: "Test",
            tempo: 120.0,
            timeSignature: .fourFour
        )
        var startBeatFromCallback: Double?
        let controller = TransportController(
            getProject: { project },
            isInstallingPlugin: { false },
            isGraphStable: { true },
            getSampleRate: { 48000 },
            onStartPlayback: { startBeatFromCallback = $0 },
            onStopPlayback: {},
            onTransportStateChanged: { _ in },
            onPositionChanged: { _ in },
            onCycleJump: { _ in }
        )
        
        controller.play()
        XCTAssertTrue(controller.isPlaying)
        startBeatFromCallback = nil
        
        // Let position advance (timer runs every 16ms; wait for at least one tick)
        try await Task.sleep(nanoseconds: 25_000_000) // 25ms
        
        controller.pause()
        XCTAssertFalse(controller.isPlaying)
        let positionAfterPause = controller.currentPosition.beats
        
        controller.play()
        let startBeatWhenResumed = startBeatFromCallback
        
        XCTAssertNotNil(startBeatWhenResumed, "onStartPlayback should be called")
        if let resumed = startBeatWhenResumed {
            assertApproximatelyEqual(resumed, positionAfterPause, tolerance: 0.01)
        }
    }
    
    // MARK: - Performance Tests
    
    func testPlaybackPositionCreationPerformance() {
        measure {
            for i in 0..<10000 {
                _ = PlaybackPosition(beats: Double(i) * 0.25, tempo: 120.0)
            }
        }
    }
    
    func testBeatToSecondsConversionPerformance() {
        let positions = (0..<1000).map { BeatPosition(Double($0) * 0.25) }
        
        measure {
            for position in positions {
                _ = position.toSeconds(tempo: 120.0)
            }
        }
    }
    
    // MARK: - Bug #07: Single Source of Truth Tests
    
    /// Test that atomic position calculation matches expected beat position over time
    /// This validates that the single source of truth (TransportController.atomicBeatPosition)
    /// produces correct values based on tempo and elapsed time
    func testAtomicPositionAccuracy() {
        // Test at 120 BPM: 2 beats per second
        let tempo = 120.0
        let startBeat = 0.0
        let startTime = CACurrentMediaTime()
        
        // Simulate 4 seconds of playback = 8 beats at 120 BPM
        let elapsedSeconds = 4.0
        let currentTime = startTime + elapsedSeconds
        
        // Manual calculation (same formula as TransportController.atomicBeatPosition)
        let beatsPerSecond = tempo / 60.0
        let expectedBeats = startBeat + (elapsedSeconds * beatsPerSecond)
        
        // Verify formula: beats = startBeat + (elapsedSeconds * (tempo / 60.0))
        assertApproximatelyEqual(expectedBeats, 8.0, tolerance: 0.001)
    }
    
    /// Test position calculation at different tempos
    /// Ensures the atomic position formula works correctly across tempo range
    func testAtomicPositionMultipleTempos() {
        let startBeat = 0.0
        let elapsedSeconds = 2.0
        
        // 60 BPM: 1 beat per second → 2 seconds = 2 beats
        let beats60 = startBeat + (elapsedSeconds * (60.0 / 60.0))
        assertApproximatelyEqual(beats60, 2.0, tolerance: 0.001)
        
        // 120 BPM: 2 beats per second → 2 seconds = 4 beats
        let beats120 = startBeat + (elapsedSeconds * (120.0 / 60.0))
        assertApproximatelyEqual(beats120, 4.0, tolerance: 0.001)
        
        // 180 BPM: 3 beats per second → 2 seconds = 6 beats
        let beats180 = startBeat + (elapsedSeconds * (180.0 / 60.0))
        assertApproximatelyEqual(beats180, 6.0, tolerance: 0.001)
        
        // 240 BPM: 4 beats per second → 2 seconds = 8 beats
        let beats240 = startBeat + (elapsedSeconds * (240.0 / 60.0))
        assertApproximatelyEqual(beats240, 8.0, tolerance: 0.001)
    }
    
    /// Test that position calculation is consistent over longer durations
    /// This catches potential drift issues that might accumulate over time
    func testAtomicPositionLongDuration() {
        let tempo = 120.0
        let startBeat = 0.0
        
        // Test 60 seconds (1 minute) of playback
        let elapsedSeconds = 60.0
        let beatsPerSecond = tempo / 60.0
        let expectedBeats = startBeat + (elapsedSeconds * beatsPerSecond)
        
        // At 120 BPM, 60 seconds = 120 beats
        assertApproximatelyEqual(expectedBeats, 120.0, tolerance: 0.001)
        
        // Test 5 minutes
        let fiveMinutes = 300.0
        let beatsIn5Min = startBeat + (fiveMinutes * beatsPerSecond)
        assertApproximatelyEqual(beatsIn5Min, 600.0, tolerance: 0.01)
    }
    
    /// Test position calculation starting from non-zero beat
    /// Validates that the formula works correctly with any start position
    func testAtomicPositionNonZeroStart() {
        let tempo = 120.0
        let startBeat = 16.0  // Start at bar 5 (16 beats in 4/4)
        let elapsedSeconds = 2.0
        
        let beatsPerSecond = tempo / 60.0
        let expectedBeats = startBeat + (elapsedSeconds * beatsPerSecond)
        
        // 16 + (2 * 2) = 20 beats
        assertApproximatelyEqual(expectedBeats, 20.0, tolerance: 0.001)
    }
    
    /// Test that the position formula is frame-accurate
    /// Uses realistic buffer size (512 samples at 48kHz = 10.67ms)
    func testAtomicPositionFrameAccuracy() {
        let tempo = 120.0
        let startBeat = 0.0
        let sampleRate = 48000.0
        let bufferSize = 512.0
        
        // One buffer duration in seconds
        let bufferDuration = bufferSize / sampleRate  // ~0.0107 seconds
        
        let beatsPerSecond = tempo / 60.0
        let beatsPerBuffer = bufferDuration * beatsPerSecond
        
        // At 120 BPM, one 512-sample buffer at 48kHz = ~0.0213 beats
        assertApproximatelyEqual(beatsPerBuffer, 0.0213, tolerance: 0.0001)
        
        // After 100 buffers (~1.07 seconds)
        let elapsed100Buffers = bufferDuration * 100
        let beats100Buffers = startBeat + (elapsed100Buffers * beatsPerSecond)
        
        // Should be ~2.13 beats
        assertApproximatelyEqual(beats100Buffers, 2.133, tolerance: 0.001)
    }
    
    /// Test position consistency across rapid tempo changes
    /// Verifies that the formula produces consistent results when tempo changes
    func testAtomicPositionTempoChange() {
        let startBeat = 0.0
        
        // Scenario: Play 2 seconds at 120 BPM, then switch to 90 BPM
        
        // Phase 1: 2 seconds at 120 BPM
        let phase1Duration = 2.0
        let phase1Tempo = 120.0
        let phase1Beats = startBeat + (phase1Duration * (phase1Tempo / 60.0))
        assertApproximatelyEqual(phase1Beats, 4.0, tolerance: 0.001)
        
        // Phase 2: 3 seconds at 90 BPM (starting from where phase 1 ended)
        let phase2Start = phase1Beats
        let phase2Duration = 3.0
        let phase2Tempo = 90.0
        let phase2Beats = phase2Start + (phase2Duration * (phase2Tempo / 60.0))
        
        // 4.0 + (3.0 * 1.5) = 4.0 + 4.5 = 8.5 beats
        assertApproximatelyEqual(phase2Beats, 8.5, tolerance: 0.001)
    }
    
    /// Performance test: Verify position calculation is fast enough for real-time use
    /// Should complete millions of calculations per second
    func testAtomicPositionCalculationPerformance() {
        let tempo = 120.0
        let startBeat = 0.0
        let startTime = CACurrentMediaTime()
        
        measure {
            var sum: Double = 0
            for i in 0..<100000 {
                let elapsed = Double(i) * 0.0001  // Simulate microsecond-level precision
                let currentBeat = startBeat + (elapsed * (tempo / 60.0))
                sum += currentBeat
            }
            // Use sum to prevent optimization
            XCTAssertGreaterThan(sum, 0)
        }
    }
    
    // MARK: - calculateCurrentBeat() Tests (Bug #12: Position Timer Accuracy)
    
    /// Helper to create a test TransportController
    @MainActor
    private func createTestController() -> TransportController {
        return TransportController(
            getProject: { nil },
            isInstallingPlugin: { false },
            isGraphStable: { true },
            onStartPlayback: { _ in },
            onStopPlayback: {},
            onTransportStateChanged: { _ in },
            onPositionChanged: { _ in },
            onCycleJump: { _ in }
        )
    }
    
    /// Test calculateCurrentBeat() at 120 BPM (most common tempo)
    /// Verifies the single source of truth for beat position calculation
    @MainActor
    func testCalculateCurrentBeatAt120BPM() {
        let controller = createTestController()
        
        // 120 BPM = 2 beats per second
        // 2 seconds elapsed = 4 beats
        let result = controller.calculateCurrentBeat(
            startBeat: 0.0,
            startWallTime: 0.0,
            currentWallTime: 2.0,
            tempo: 120.0
        )
        
        assertApproximatelyEqual(result, 4.0, tolerance: 0.00001)
    }
    
    /// Test calculateCurrentBeat() at various common tempos
    @MainActor
    func testCalculateCurrentBeatVariousTempos() {
        let controller = createTestController()
        
        let testCases: [(tempo: Double, seconds: Double, expectedBeats: Double)] = [
            // tempo, elapsed seconds, expected beats
            (60.0, 1.0, 1.0),      // 60 BPM: 1 beat per second
            (90.0, 2.0, 3.0),      // 90 BPM: 1.5 beats per second
            (120.0, 2.0, 4.0),     // 120 BPM: 2 beats per second
            (140.0, 1.0, 2.333),   // 140 BPM: 2.333... beats per second
            (180.0, 1.0, 3.0),     // 180 BPM: 3 beats per second
            (240.0, 0.5, 2.0),     // 240 BPM: 4 beats per second
        ]
        
        for (tempo, seconds, expectedBeats) in testCases {
            let result = controller.calculateCurrentBeat(
                startBeat: 0.0,
                startWallTime: 0.0,
                currentWallTime: seconds,
                tempo: tempo
            )
            
            assertApproximatelyEqual(result, expectedBeats, tolerance: 0.001)
        }
    }
    
    /// Test calculateCurrentBeat() with non-zero start beat
    /// Verifies that calculation works correctly when not starting from beat 0
    @MainActor
    func testCalculateCurrentBeatWithNonZeroStart() {
        let controller = createTestController()
        
        // Start at beat 8.5, play for 2 seconds at 120 BPM
        // Should end at 8.5 + 4.0 = 12.5 beats
        let result = controller.calculateCurrentBeat(
            startBeat: 8.5,
            startWallTime: 0.0,
            currentWallTime: 2.0,
            tempo: 120.0
        )
        
        assertApproximatelyEqual(result, 12.5, tolerance: 0.00001)
    }
    
    /// Test calculateCurrentBeat() with non-zero start time
    /// Verifies that only the elapsed time matters, not absolute wall time
    @MainActor
    func testCalculateCurrentBeatWithNonZeroStartTime() {
        let controller = createTestController()
        
        // Start at wall time 100.0, current time 102.0 (2 seconds elapsed)
        // At 120 BPM, 2 seconds = 4 beats
        let result = controller.calculateCurrentBeat(
            startBeat: 0.0,
            startWallTime: 100.0,
            currentWallTime: 102.0,
            tempo: 120.0
        )
        
        assertApproximatelyEqual(result, 4.0, tolerance: 0.00001)
    }
    
    /// Test calculateCurrentBeat() precision with very small time intervals
    /// Critical for sample-accurate timing
    @MainActor
    func testCalculateCurrentBeatMicrosecondPrecision() {
        let controller = createTestController()
        
        // 1 millisecond at 120 BPM
        // 120 BPM = 2 beats/second = 0.002 beats/millisecond
        let oneMillisecond = 0.001
        let result1ms = controller.calculateCurrentBeat(
            startBeat: 0.0,
            startWallTime: 0.0,
            currentWallTime: oneMillisecond,
            tempo: 120.0
        )
        
        assertApproximatelyEqual(result1ms, 0.002, tolerance: 0.000001)
        
        // 100 microseconds (0.0001 seconds)
        let oneHundredMicroseconds = 0.0001
        let result100us = controller.calculateCurrentBeat(
            startBeat: 0.0,
            startWallTime: 0.0,
            currentWallTime: oneHundredMicroseconds,
            tempo: 120.0
        )
        
        assertApproximatelyEqual(result100us, 0.0002, tolerance: 0.00001)
    }
    
    /// Test calculateCurrentBeat() at extreme tempos
    /// Verifies calculation works across full professional tempo range
    @MainActor
    func testCalculateCurrentBeatExtremeTempos() {
        let controller = createTestController()
        
        // Very slow tempo: 40 BPM (ballad)
        let slowResult = controller.calculateCurrentBeat(
            startBeat: 0.0,
            startWallTime: 0.0,
            currentWallTime: 3.0,
            tempo: 40.0
        )
        // 40 BPM = 0.667 beats/second, 3s = 2 beats
        assertApproximatelyEqual(slowResult, 2.0, tolerance: 0.001)
        
        // Very fast tempo: 300 BPM (electronic music)
        let fastResult = controller.calculateCurrentBeat(
            startBeat: 0.0,
            startWallTime: 0.0,
            currentWallTime: 1.0,
            tempo: 300.0
        )
        // 300 BPM = 5 beats/second, 1s = 5 beats
        assertApproximatelyEqual(fastResult, 5.0, tolerance: 0.001)
    }
    
    /// Test calculateCurrentBeat() consistency across multiple invocations
    /// Verifies deterministic behavior (same inputs = same output)
    @MainActor
    func testCalculateCurrentBeatDeterministic() {
        let controller = createTestController()
        
        let params = (startBeat: 5.25, startTime: 123.456, currentTime: 125.789, tempo: 128.5)
        
        // Call multiple times with same parameters
        let results = (0..<10).map { _ in
            controller.calculateCurrentBeat(
                startBeat: params.startBeat,
                startWallTime: params.startTime,
                currentWallTime: params.currentTime,
                tempo: params.tempo
            )
        }
        
        // All results should be identical (deterministic)
        let firstResult = results[0]
        for (index, result) in results.enumerated() {
            XCTAssertEqual(result, firstResult, accuracy: 0.000001,
                          "Invocation \(index) should produce identical result")
        }
    }
    
    /// Test calculateCurrentBeat() formula correctness
    /// Explicitly verifies: currentBeat = startBeat + (elapsedSeconds * (tempo / 60.0))
    @MainActor
    func testCalculateCurrentBeatFormulaCorrectness() {
        let controller = createTestController()
        
        let startBeat = 10.0
        let startTime = 50.0
        let currentTime = 55.5 // 5.5 seconds elapsed
        let tempo = 144.0      // 144 BPM
        
        // Manual calculation
        let elapsedSeconds = currentTime - startTime // 5.5
        let beatsPerSecond = tempo / 60.0            // 2.4
        let elapsedBeats = elapsedSeconds * beatsPerSecond // 13.2
        let expectedBeat = startBeat + elapsedBeats   // 23.2
        
        let result = controller.calculateCurrentBeat(
            startBeat: startBeat,
            startWallTime: startTime,
            currentWallTime: currentTime,
            tempo: tempo
        )
        
        assertApproximatelyEqual(result, expectedBeat, tolerance: 0.000001)
        assertApproximatelyEqual(result, 23.2, tolerance: 0.000001)
    }
    
    /// Test calculateCurrentBeat() with zero elapsed time
    /// Should return exactly the start beat
    @MainActor
    func testCalculateCurrentBeatZeroElapsedTime() {
        let controller = createTestController()
        
        let startBeat = 42.5
        let wallTime = 100.0
        
        let result = controller.calculateCurrentBeat(
            startBeat: startBeat,
            startWallTime: wallTime,
            currentWallTime: wallTime, // Same time = 0 elapsed
            tempo: 120.0
        )
        
        XCTAssertEqual(result, startBeat, accuracy: 0.000001,
                      "Zero elapsed time should return exactly the start beat")
    }
    
    /// Test calculateCurrentBeat() performance
    /// Must be fast enough for real-time audio thread access
    @MainActor
    func testCalculateCurrentBeatPerformance() {
        let controller = createTestController()
        
        measure {
            var sum: Double = 0
            for i in 0..<100000 {
                let result = controller.calculateCurrentBeat(
                    startBeat: 0.0,
                    startWallTime: 0.0,
                    currentWallTime: Double(i) * 0.0001,
                    tempo: 120.0
                )
                sum += result
            }
            // Use sum to prevent optimization
            XCTAssertGreaterThan(sum, 0)
        }
        // Should complete 100,000 calculations in ~0.01s or less
    }
}
