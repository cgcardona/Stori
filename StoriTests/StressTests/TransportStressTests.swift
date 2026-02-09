//
//  TransportStressTests.swift
//  StoriTests
//
//  Stress tests targeting the transport and audio engine under adversarial conditions.
//  These catch deadlocks, race conditions, and state machine bugs in the transport controller.
//

import XCTest
@testable import Stori

final class TransportStressTests: XCTestCase {

    // MARK: - Test: Rapid Play/Stop Cycling

    /// Rapidly toggle play/stop to catch state machine race conditions.
    @MainActor
    func testStressRapidPlayStop() async throws {
        let audioEngine = AudioEngine()
        var project = AudioProject(name: "Stress-PlayStop")
        var track = AudioTrack(name: "Test", trackType: .midi)
        var region = MIDIRegion(name: "Note")
        region.startBeat = 0
        region.durationBeats = 16
        region.notes.append(MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 16))
        track.midiRegions.append(region)
        project.tracks.append(track)
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(300))

        for _ in 0..<100 {
            audioEngine.play()
            audioEngine.stop()
        }

        // Verify engine is in a clean state
        XCTAssertFalse(audioEngine.isPlaying, "Engine should be stopped after rapid play/stop")
        XCTAssertFalse(audioEngine.isRecording, "Engine should not be recording")
    }

    // MARK: - Test: Scrub While Playing

    /// Seek to random positions while the engine is playing.
    @MainActor
    func testStressScrubWhilePlaying() async throws {
        let audioEngine = AudioEngine()
        var project = AudioProject(name: "Stress-ScrubPlaying")
        var track = AudioTrack(name: "Test", trackType: .midi)
        var region = MIDIRegion(name: "Note")
        region.startBeat = 0
        region.durationBeats = 100
        region.notes.append(MIDINote(pitch: 60, velocity: 80, startBeat: 0, durationBeats: 100))
        track.midiRegions.append(region)
        project.tracks.append(track)
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(300))

        audioEngine.play()

        // Rapidly seek to random positions while playing
        for i in 0..<50 {
            let beat = Double(i * 2)
            audioEngine.seek(toBeat: beat)
            try await Task.sleep(for: .milliseconds(20))
        }

        audioEngine.stop()

        // Engine should still be in a valid state
        XCTAssertFalse(audioEngine.isPlaying)
    }

    // MARK: - Test: Play/Pause/Seek Interleaved

    /// Interleave play, pause, and seek operations.
    @MainActor
    func testStressInterleavedTransportOps() async throws {
        let audioEngine = AudioEngine()
        var project = AudioProject(name: "Stress-Interleaved")
        var track = AudioTrack(name: "Test", trackType: .midi)
        var region = MIDIRegion(name: "Note")
        region.startBeat = 0
        region.durationBeats = 50
        region.notes.append(MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 50))
        track.midiRegions.append(region)
        project.tracks.append(track)
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(300))

        let operations: [() -> Void] = [
            { audioEngine.play() },
            { audioEngine.pause() },
            { audioEngine.stop() },
            { audioEngine.seek(toBeat: 10) },
            { audioEngine.seek(toBeat: 0) },
            { audioEngine.play() },
            { audioEngine.seek(toBeat: 25) },
            { audioEngine.stop() },
        ]

        // Run all operations rapidly
        for _ in 0..<10 {
            for op in operations {
                op()
            }
        }

        audioEngine.stop()
        XCTAssertFalse(audioEngine.isPlaying, "Should be stopped after stress test")
    }

    // MARK: - Test: Tempo Change During Playback

    /// Change tempo while playing — should not crash or produce timing errors.
    @MainActor
    func testStressTempoChangeDuringPlayback() async throws {
        let audioEngine = AudioEngine()
        var project = AudioProject(name: "Stress-TempoChange")
        project.tempo = 120

        var track = AudioTrack(name: "Test", trackType: .midi)
        var region = MIDIRegion(name: "Note")
        region.startBeat = 0
        region.durationBeats = 32
        region.notes.append(MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 32))
        track.midiRegions.append(region)
        project.tracks.append(track)
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(300))

        audioEngine.play()

        // Rapidly change tempo
        let tempos: [Double] = [60, 90, 120, 150, 180, 200, 100, 80, 140, 120]
        for tempo in tempos {
            project.tempo = tempo
            audioEngine.updateProjectData(project)
            try await Task.sleep(for: .milliseconds(50))
        }

        audioEngine.stop()
        XCTAssertFalse(audioEngine.isPlaying)
    }
}
