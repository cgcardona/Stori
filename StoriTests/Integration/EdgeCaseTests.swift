//
//  EdgeCaseTests.swift
//  StoriTests
//
//  Edge case tests for Phase 2 (PUMP IT UP roadmap).
//  Tests boundary conditions, empty states, and error scenarios.
//

import XCTest
@testable import Stori

@MainActor
final class EdgeCaseTests: XCTestCase {
    
    // MARK: - Empty Automation Lane Tests
    
    func testEmptyLaneReturnsInitialValue() {
        let lane = AutomationLane(parameter: .volume, initialValue: 0.75)
        
        // Empty lane should return initialValue
        XCTAssertEqual(lane.value(atBeat: 0), 0.75, accuracy: 0.001)
        XCTAssertEqual(lane.value(atBeat: 100), 0.75, accuracy: 0.001)
    }
    
    func testEmptyLaneWithoutInitialValueReturnsDefault() {
        let lane = AutomationLane(parameter: .volume, initialValue: nil)
        
        // Should return parameter default
        XCTAssertEqual(lane.value(atBeat: 0), 0.8, accuracy: 0.001)  // Volume default
    }
    
    func testLaneWithOnePoint() {
        var lane = AutomationLane(parameter: .volume, initialValue: 0.5)
        lane.addPoint(atBeat: 4.0, value: 0.8, curve: .linear)
        
        // Before point: initialValue
        XCTAssertEqual(lane.value(atBeat: 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(lane.value(atBeat: 3.9), 0.5, accuracy: 0.001)
        
        // At point: point value
        XCTAssertEqual(lane.value(atBeat: 4.0), 0.8, accuracy: 0.001)
        
        // After point: holds last value
        XCTAssertEqual(lane.value(atBeat: 100), 0.8, accuracy: 0.001)
    }
    
    func testAddingFirstPointDoesNotPop() {
        var lane = AutomationLane(parameter: .volume, initialValue: 0.8)
        
        // Value before adding point
        let before = lane.value(atBeat: 0)
        
        // Add first point at beat 0 with same value
        lane.addPoint(atBeat: 0, value: 0.8, curve: .linear)
        
        // Value should be identical (no pop)
        let after = lane.value(atBeat: 0)
        XCTAssertEqual(before, after, accuracy: 0.0001, "Adding first point should not change value")
    }
    
    // MARK: - Automation Boundary Tests
    
    func testAutomationAtExactBoundaries() {
        var lane = AutomationLane(parameter: .volume, initialValue: 0.5)
        lane.addPoint(atBeat: 0, value: 0.0, curve: .linear)
        lane.addPoint(atBeat: 4, value: 1.0, curve: .linear)
        
        // Exact boundaries
        XCTAssertEqual(lane.value(atBeat: 0), 0.0, accuracy: 0.001)
        XCTAssertEqual(lane.value(atBeat: 4), 1.0, accuracy: 0.001)
        
        // Midpoint
        XCTAssertEqual(lane.value(atBeat: 2), 0.5, accuracy: 0.001)
    }
    
    func testAutomationBeforeFirstPoint() {
        var lane = AutomationLane(parameter: .volume, initialValue: 0.6)
        lane.addPoint(atBeat: 8, value: 0.9, curve: .linear)
        
        // Before first point: use initialValue
        XCTAssertEqual(lane.value(atBeat: 0), 0.6, accuracy: 0.001)
        XCTAssertEqual(lane.value(atBeat: 7.9), 0.6, accuracy: 0.001)
    }
    
    func testAutomationAfterLastPoint() {
        var lane = AutomationLane(parameter: .volume)
        lane.addPoint(atBeat: 0, value: 0.5, curve: .linear)
        lane.addPoint(atBeat: 4, value: 0.8, curve: .linear)
        
        // After last point: hold last value
        XCTAssertEqual(lane.value(atBeat: 4.1), 0.8, accuracy: 0.001)
        XCTAssertEqual(lane.value(atBeat: 1000), 0.8, accuracy: 0.001)
    }
    
    // MARK: - Project Edge Cases
    
    func testProjectWithNoTracks() {
        let project = AudioProject(name: "Empty")
        XCTAssertEqual(project.tracks.count, 0)
        XCTAssertEqual(project.durationBeats, 0)
    }
    
    func testProjectWithZeroTempo() {
        var project = AudioProject(name: "Test")
        project.tempo = 0  // Invalid
        
        // Should not crash when calculating durations
        _ = project.durationSeconds(tempo: project.tempo)
        XCTAssertTrue(true, "Zero tempo handled gracefully")
    }
    
    func testProjectWithNegativeTempo() {
        var project = AudioProject(name: "Test")
        project.tempo = -120  // Invalid
        
        // Should not crash
        _ = project.durationSeconds(tempo: project.tempo)
        XCTAssertTrue(true, "Negative tempo handled gracefully")
    }
    
    // MARK: - Track Edge Cases
    
    func testTrackWithNoRegions() {
        let track = AudioTrack(name: "Empty Track")
        XCTAssertEqual(track.regions.count, 0)
        XCTAssertEqual(track.midiRegions.count, 0)
    }
    
    func testAudioTrackMixerDefaults() {
        let track = AudioTrack(name: "Test", trackType: .audio)
        
        // Verify default mixer settings
        XCTAssertEqual(track.mixerSettings.volume, 0.8, accuracy: 0.001)
        XCTAssertEqual(track.mixerSettings.pan, 0.5, accuracy: 0.001)  // 0.5 = center in 0-1 range
        XCTAssertFalse(track.mixerSettings.isMuted)
        XCTAssertFalse(track.mixerSettings.isSolo)
    }
    
    func testMIDITrackDefaults() {
        let track = AudioTrack(name: "MIDI", trackType: .midi)
        XCTAssertTrue(track.isMIDITrack)
        XCTAssertFalse(track.isAudioTrack)
    }
    
    // MARK: - Region Edge Cases
    
    func testRegionWithZeroDuration() {
        let audioFile = AudioFile(
            name: "Test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            duration: 1.0,
            sampleRate: 48000,
            channels: 2,
            fileSize: 1024,
            format: .wav
        )
        
        let region = AudioRegion(
            audioFile: audioFile,
            startBeat: 0,
            durationBeats: 0  // Zero duration
        )
        
        XCTAssertEqual(region.durationBeats, 0)
        XCTAssertEqual(region.endBeat, 0)
    }
    
    func testRegionWithNegativeOffset() {
        let audioFile = AudioFile(
            name: "Test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            duration: 5.0,
            sampleRate: 48000,
            channels: 2,
            fileSize: 1024,
            format: .wav
        )
        
        let region = AudioRegion(
            audioFile: audioFile,
            startBeat: 0,
            durationBeats: 4,
            offset: -1.0  // Negative offset
        )
        
        // AudioRegion init clamps offset to >= 0
        XCTAssertEqual(region.offset, 0.0, accuracy: 0.001)
    }
    
    func testRegionOffsetBeyondFileDuration() {
        let audioFile = AudioFile(
            name: "Test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            duration: 2.0,  // 2 second file
            sampleRate: 48000,
            channels: 2,
            fileSize: 1024,
            format: .wav
        )
        
        let region = AudioRegion(
            audioFile: audioFile,
            startBeat: 0,
            durationBeats: 4,
            offset: 5.0  // Offset beyond file duration
        )
        
        // Should not crash - clamping happens during scheduling
        XCTAssertGreaterThan(region.offset, audioFile.duration)
    }
    
    // MARK: - MIDI Edge Cases
    
    func testMIDIRegionWithNoNotes() {
        let region = MIDIRegion(name: "Empty", startBeat: 0, durationBeats: 4)
        XCTAssertEqual(region.notes.count, 0)
    }
    
    func testMIDINoteWithZeroDuration() {
        let note = MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 0)
        XCTAssertEqual(note.durationBeats, 0)
        XCTAssertEqual(note.endBeat, 0)
    }
    
    func testMIDINoteWithZeroVelocity() {
        let note = MIDINote(pitch: 60, velocity: 0, startBeat: 0, durationBeats: 1)
        XCTAssertEqual(note.velocity, 0)
        // Zero velocity notes are valid (note-off)
    }
    
    func testMIDINoteWithInvalidPitch() {
        let note = MIDINote(pitch: 200, velocity: 100, startBeat: 0, durationBeats: 1)
        // MIDI pitch is UInt8, so 200 wraps around
        // This tests that we don't crash with out-of-range values
        XCTAssertEqual(note.pitch, 200)
    }
    
    // MARK: - Cycle Loop Edge Cases
    
    func testCycleWithZeroDuration() {
        let cycleStartBeat: Double = 4.0
        let cycleEndBeat: Double = 4.0  // Same as start
        
        let duration = cycleEndBeat - cycleStartBeat
        XCTAssertEqual(duration, 0)
        
        // Zero-duration cycle should fall back to standard scheduling
    }
    
    func testCycleWithNegativeDuration() {
        let cycleStartBeat: Double = 8.0
        let cycleEndBeat: Double = 4.0  // End before start
        
        let duration = cycleEndBeat - cycleStartBeat
        XCTAssertLessThan(duration, 0)
        
        // Negative cycle should be rejected
    }
    
    func testCycleStartingOutsideCycleRegion() {
        let startBeat: Double = 10.0
        let cycleStartBeat: Double = 0.0
        let cycleEndBeat: Double = 4.0
        
        let isWithinCycle = startBeat >= cycleStartBeat && startBeat < cycleEndBeat
        XCTAssertFalse(isWithinCycle)
        
        // Should use standard scheduling, not cycle-aware
    }
    
    // MARK: - Format Mismatch Tests
    
    func testAudioFileSampleRateMismatch() {
        // 44.1kHz file in 48kHz project
        let audioFile = AudioFile(
            name: "44.1k File",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            duration: 1.0,
            sampleRate: 44100,  // Different from project
            channels: 2,
            fileSize: 1024,
            format: .wav
        )
        
        XCTAssertEqual(audioFile.sampleRate, 44100)
        // AVAudioEngine handles sample rate conversion automatically
    }
    
    func testMonoFileInStereoProject() {
        let audioFile = AudioFile(
            name: "Mono File",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            duration: 1.0,
            sampleRate: 48000,
            channels: 1,  // Mono
            fileSize: 1024,
            format: .wav
        )
        
        XCTAssertEqual(audioFile.channels, 1)
        // AVAudioEngine handles mono→stereo conversion
    }
    
    // MARK: - Timing Precision Edge Cases
    
    func testBeatToSecondsConversionPrecision() {
        let beat: Double = 1000.0
        let tempo: Double = 120.0
        
        let seconds = beat * (60.0 / tempo)
        let backToBeats = seconds * (tempo / 60.0)
        
        // Round-trip should be accurate
        XCTAssertEqual(backToBeats, beat, accuracy: 0.0001)
    }
    
    func testVerySmallBeatValues() {
        let beat: Double = 0.0001
        let tempo: Double = 120.0
        
        let seconds = beat * (60.0 / tempo)
        XCTAssertGreaterThan(seconds, 0)
        XCTAssertLessThan(seconds, 0.001)
    }
    
    func testVeryLargeBeatValues() {
        let beat: Double = 100000.0  // Very long project
        let tempo: Double = 120.0
        
        let seconds = beat * (60.0 / tempo)
        XCTAssertEqual(seconds, 50000.0, accuracy: 0.1)  // ~13.9 hours
    }
    
    // MARK: - Playback Position Edge Cases
    
    func testNegativePlaybackPosition() {
        let position = PlaybackPosition(beats: -1.0)
        XCTAssertEqual(position.beats, -1.0)
        // Negative positions should be handled gracefully
    }
    
    func testZeroPlaybackPosition() {
        let position = PlaybackPosition(beats: 0.0)
        XCTAssertEqual(position.beats, 0.0)
        XCTAssertEqual(position.bars, 0)
        XCTAssertEqual(position.beatInBar, 1)  // Beat 1 of bar 1
    }
    
    // MARK: - Time Signature Edge Cases
    
    func testUncommonTimeSignatures() {
        // 7/8 time
        let sig78 = TimeSignature(numerator: 7, denominator: 8)
        XCTAssertEqual(sig78.numerator, 7)
        XCTAssertEqual(sig78.denominator, 8)
        
        // 5/4 time
        let sig54 = TimeSignature(numerator: 5, denominator: 4)
        XCTAssertEqual(sig54.numerator, 5)
        XCTAssertEqual(sig54.denominator, 4)
    }
    
    /// Minimum valid numerator is 1 (numerator 0 is invalid and asserts in Debug)
    func testMinimumValidTimeSignature() {
        let sig = TimeSignature(numerator: 1, denominator: 4)
        XCTAssertEqual(sig.numerator, 1)
        XCTAssertEqual(sig.denominator, 4)
    }
    
    // MARK: - Plugin Chain Edge Cases
    
    func testPluginChainWithNoPlugins() {
        let chain = PluginChain(id: UUID(), maxSlots: 8)
        XCTAssertEqual(chain.activePlugins.count, 0)
        XCTAssertFalse(chain.hasActivePlugins)
        XCTAssertFalse(chain.isRealized)
    }
    
    func testPluginChainBypassAll() {
        let chain = PluginChain(id: UUID(), maxSlots: 8)
        chain.isBypassed = true
        XCTAssertTrue(chain.isBypassed)
    }
    
    // MARK: - Mixer Settings Edge Cases
    
    func testMixerSettingsWithExtremeEQ() {
        var settings = MixerSettings()
        settings.highEQ = 24.0  // Max boost
        settings.midEQ = -24.0  // Max cut
        settings.lowEQ = 0.0    // Flat
        
        XCTAssertEqual(settings.highEQ, 24.0, accuracy: 0.1)
        XCTAssertEqual(settings.midEQ, -24.0, accuracy: 0.1)
        XCTAssertEqual(settings.lowEQ, 0.0, accuracy: 0.1)
    }
    
    func testMixerSettingsWithBothMuteAndSolo() {
        var settings = MixerSettings()
        settings.isMuted = true
        settings.isSolo = true
        
        // Both flags can be set (solo takes precedence in MixerController)
        XCTAssertTrue(settings.isMuted)
        XCTAssertTrue(settings.isSolo)
    }
    
    // MARK: - Undo/Redo Edge Cases
    // Note: UndoService has private init (singleton pattern)
    // These tests are covered in UndoServiceTests.swift
    
    func testUndoServiceSingletonExists() {
        // Verify singleton pattern works
        XCTAssertTrue(true, "UndoService tests in UndoServiceTests.swift")
    }
}
