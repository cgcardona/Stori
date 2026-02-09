//
//  GoldenFileRegressionTests.swift
//  StoriTests
//
//  Golden file regression tests that compare offline renders against known-good references.
//  These catch subtle audio bugs: pan law changes, routing regressions, automation
//  application errors, tempo-map drift, and missing plugin tails.
//
//  Usage:
//    First run:   STORI_UPDATE_GOLDENS=1 xcodebuild test -only-testing:StoriTests/GoldenFileRegressionTests
//    Normal run:  xcodebuild test -only-testing:StoriTests/GoldenFileRegressionTests
//

import XCTest
import AVFoundation
@testable import Stori

final class GoldenFileRegressionTests: AudioRegressionTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = try createTempDirectory()
    }

    override func tearDown() async throws {
        if let tempDir {
            cleanupTempDirectory(tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - Test: Basic MIDI Render Stability

    /// Render a simple MIDI project and verify consistency across runs.
    /// This is the most fundamental golden test — if MIDI rendering changes,
    /// this will catch it.
    @MainActor
    func testBasicMIDIRenderGolden() async throws {
        var project = AudioProject(name: "Golden-BasicMIDI")
        var track = AudioTrack(name: "Piano", trackType: .midi)

        // Create a 4-bar MIDI sequence with different velocities
        var region = MIDIRegion(name: "TestSequence")
        region.startBeat = 0
        region.durationBeats = 16

        // C major scale ascending
        let pitches: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]
        for (i, pitch) in pitches.enumerated() {
            region.notes.append(MIDINote(
                pitch: pitch,
                velocity: UInt8(80 + i * 5),
                startBeat: Double(i * 2),
                durationBeats: 1.5
            ))
        }

        track.midiRegions.append(region)
        project.tracks.append(track)
        project.tempo = 120

        let exportService = ProjectExportService()
        let audioEngine = AudioEngine()
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(500))

        let exportURL = try await exportService.exportProjectMix(
            project: project,
            audioEngine: audioEngine
        )

        // Basic sanity checks
        try assertNotSilent(exportURL)
        let info = try analyzeAudioFile(at: exportURL)
        XCTAssertGreaterThan(info.duration, 4.0,
                             "8-note sequence at 120BPM should be at least 4 seconds")

        // Compare against golden (or create it on first run)
        try assertAudioMatchesGolden(rendered: exportURL, goldenName: "basic-midi")

        try? FileManager.default.removeItem(at: exportURL)
    }

    // MARK: - Test: Volume Automation Render

    /// Render a project with volume automation and verify the envelope is applied.
    @MainActor
    func testVolumeAutomationRenderGolden() async throws {
        var project = AudioProject(name: "Golden-VolumeAutomation")
        var track = AudioTrack(name: "AutomatedTrack", trackType: .midi)

        // Add a sustained note
        var region = MIDIRegion(name: "SustainedNote")
        region.startBeat = 0
        region.durationBeats = 8
        region.notes.append(MIDINote(
            pitch: 60,
            velocity: 100,
            startBeat: 0,
            durationBeats: 8
        ))
        track.midiRegions.append(region)

        // Add volume automation: fade in over 4 beats
        var automationLane = AutomationLane(parameter: .volume)
        automationLane.points = [
            AutomationPoint(beat: 0, value: 0),
            AutomationPoint(beat: 4, value: 1.0),
            AutomationPoint(beat: 8, value: 1.0)
        ]
        track.automationLanes.append(automationLane)

        project.tracks.append(track)
        project.tempo = 120

        let exportService = ProjectExportService()
        let audioEngine = AudioEngine()
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(500))

        let exportURL = try await exportService.exportProjectMix(
            project: project,
            audioEngine: audioEngine
        )

        try assertNotSilent(exportURL)

        // Compare against golden
        try assertAudioMatchesGolden(
            rendered: exportURL,
            goldenName: "volume-automation",
            tolerances: .default
        )

        try? FileManager.default.removeItem(at: exportURL)
    }

    // MARK: - Test: Pan Position Render

    /// Verify that pan position is correctly applied in offline render.
    @MainActor
    func testPanPositionRenderGolden() async throws {
        var project = AudioProject(name: "Golden-PanPosition")

        // Track panned hard left
        var leftTrack = AudioTrack(name: "Left", trackType: .midi)
        // MixerSettings.pan: 0-1 range (0.0=hard left, 0.5=center, 1.0=hard right)
        leftTrack.mixerSettings.pan = 0.0  // Hard left
        var leftRegion = MIDIRegion(name: "LeftNote")
        leftRegion.startBeat = 0
        leftRegion.durationBeats = 4
        leftRegion.notes.append(MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 4))
        leftTrack.midiRegions.append(leftRegion)

        // Track panned hard right
        var rightTrack = AudioTrack(name: "Right", trackType: .midi)
        rightTrack.mixerSettings.pan = 1.0  // Hard right
        var rightRegion = MIDIRegion(name: "RightNote")
        rightRegion.startBeat = 0
        rightRegion.durationBeats = 4
        rightRegion.notes.append(MIDINote(pitch: 72, velocity: 100, startBeat: 0, durationBeats: 4))
        rightTrack.midiRegions.append(rightRegion)

        project.tracks.append(leftTrack)
        project.tracks.append(rightTrack)
        project.tempo = 120

        let exportService = ProjectExportService()
        let audioEngine = AudioEngine()
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(500))

        let exportURL = try await exportService.exportProjectMix(
            project: project,
            audioEngine: audioEngine
        )

        try assertNotSilent(exportURL)

        // Verify stereo
        let info = try analyzeAudioFile(at: exportURL)
        XCTAssertEqual(info.channels, 2, "Pan test must produce stereo output")

        try assertAudioMatchesGolden(
            rendered: exportURL,
            goldenName: "pan-position",
            tolerances: .default
        )

        try? FileManager.default.removeItem(at: exportURL)
    }

    // MARK: - Test: Tempo Change Render

    /// Verify that different tempo values produce correct-duration exports.
    @MainActor
    func testTempoAffectsRenderDuration() async throws {
        // Same content at different tempos should produce different durations
        for tempo in [60.0, 120.0, 180.0] {
            var project = AudioProject(name: "Golden-Tempo-\(Int(tempo))")
            var track = AudioTrack(name: "Test", trackType: .midi)
            var region = MIDIRegion(name: "Note")
            region.startBeat = 0
            region.durationBeats = 4
            region.notes.append(MIDINote(
                pitch: 60,
                velocity: 100,
                startBeat: 0,
                durationBeats: 4
            ))
            track.midiRegions.append(region)
            project.tracks.append(track)
            project.tempo = tempo

            let exportService = ProjectExportService()
            let audioEngine = AudioEngine()
            audioEngine.loadProject(project)

            try await Task.sleep(for: .milliseconds(300))

            let exportURL = try await exportService.exportProjectMix(
                project: project,
                audioEngine: audioEngine
            )

            let info = try analyzeAudioFile(at: exportURL)
            let expectedDuration = (4.0 / tempo) * 60.0  // 4 beats at given tempo
            let delta = abs(info.duration - expectedDuration)

            // Allow some tolerance for tail time
            XCTAssertLessThan(delta, 1.0,
                              "At \(tempo) BPM, 4 beats should be ~\(expectedDuration)s, got \(info.duration)s")

            try? FileManager.default.removeItem(at: exportURL)
        }
    }

    // MARK: - Test: Muted Track Not in Export

    /// Verify that muted tracks are excluded from the mixdown.
    @MainActor
    func testMutedTrackExcludedFromExport() async throws {
        var project = AudioProject(name: "Golden-MutedTrack")

        // Active track with audio
        var activeTrack = AudioTrack(name: "Active", trackType: .midi)
        var activeRegion = MIDIRegion(name: "Active")
        activeRegion.startBeat = 0
        activeRegion.durationBeats = 4
        activeRegion.notes.append(MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 4))
        activeTrack.midiRegions.append(activeRegion)

        // Muted track
        var mutedTrack = AudioTrack(name: "Muted", trackType: .midi)
        mutedTrack.mixerSettings.isMuted = true
        var mutedRegion = MIDIRegion(name: "Muted")
        mutedRegion.startBeat = 0
        mutedRegion.durationBeats = 4
        mutedRegion.notes.append(MIDINote(pitch: 84, velocity: 127, startBeat: 0, durationBeats: 4))
        mutedTrack.midiRegions.append(mutedRegion)

        project.tracks.append(activeTrack)
        project.tracks.append(mutedTrack)
        project.tempo = 120

        let exportService = ProjectExportService()
        let audioEngine = AudioEngine()
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(500))

        // Export with muted track
        let mutedExportURL = try await exportService.exportProjectMix(
            project: project,
            audioEngine: audioEngine
        )

        // Export without muted track (remove it)
        project.tracks.removeAll { $0.name == "Muted" }
        audioEngine.loadProject(project)
        try await Task.sleep(for: .milliseconds(500))

        let soloExportURL = try await exportService.exportProjectMix(
            project: project,
            audioEngine: audioEngine
        )

        // Both exports should sound the same (muted track should not contribute)
        let mutedInfo = try analyzeAudioFile(at: mutedExportURL)
        let soloInfo = try analyzeAudioFile(at: soloExportURL)

        // RMS should be similar (muted track excluded)
        let rmsDelta = abs(mutedInfo.rms - soloInfo.rms)
        XCTAssertLessThan(rmsDelta, 0.01,
                          "Muted track should not affect export (RMS delta: \(rmsDelta))")

        try? FileManager.default.removeItem(at: mutedExportURL)
        try? FileManager.default.removeItem(at: soloExportURL)
    }
}
