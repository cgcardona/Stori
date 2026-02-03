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
}
