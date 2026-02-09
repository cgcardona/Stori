//
//  SilenceDetectionTests.swift
//  StoriTests
//
//  Audio regression tests that verify offline renders produce non-silent output.
//  These catch the most common export bug: silent exports due to routing errors,
//  disconnected nodes, or misconfigured gain staging.
//

import XCTest
import AVFoundation
@testable import Stori

final class SilenceDetectionTests: AudioRegressionTestCase {

    // MARK: - Test: Synthetic Sine Tone Render

    /// Create a project with a sine tone and verify the export is not silent.
    /// This is a self-contained test that doesn't need golden files.
    @MainActor
    func testSyntheticSineToneExportIsNotSilent() async throws {
        // Create a minimal project with a MIDI track
        var project = AudioProject(name: "SilenceTest-SineTone")
        var track = AudioTrack(name: "SineTone", trackType: .midi)

        // Add a MIDI region with a sustained note
        var midiRegion = MIDIRegion(name: "TestNote")
        midiRegion.startBeat = 0
        midiRegion.durationBeats = 4  // 4 beats = ~2 seconds at 120 BPM
        midiRegion.notes = [
            MIDINote(
                pitch: 60,  // Middle C
                velocity: 100,
                startBeat: 0,
                durationBeats: 4
            )
        ]
        track.midiRegions.append(midiRegion)
        project.tracks.append(track)
        project.tempo = 120

        // Export
        let exportService = ProjectExportService()
        let audioEngine = AudioEngine()
        audioEngine.loadProject(project)

        // Brief delay for engine setup
        try await Task.sleep(for: .milliseconds(500))

        let exportURL = try await exportService.exportProjectMix(
            project: project,
            audioEngine: audioEngine
        )

        // Verify
        try assertNotSilent(exportURL, threshold: 0.001)
        let info = try analyzeAudioFile(at: exportURL)
        XCTAssertGreaterThan(info.duration, 1.0, "Export should be at least 1 second long")
        XCTAssertEqual(info.channels, 2, "Export should be stereo")

        // Cleanup
        try? FileManager.default.removeItem(at: exportURL)
    }

    // MARK: - Test: Empty Project Export

    /// An empty project (no tracks) should produce a valid but silent file.
    @MainActor
    func testEmptyProjectExportIsSilent() async throws {
        let project = AudioProject(name: "SilenceTest-Empty")

        let exportService = ProjectExportService()
        let audioEngine = AudioEngine()
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(500))

        // Empty project should either throw or produce a very short/silent file
        do {
            let exportURL = try await exportService.exportProjectMix(
                project: project,
                audioEngine: audioEngine
            )

            let info = try analyzeAudioFile(at: exportURL)
            // An empty project should have near-zero RMS
            XCTAssertLessThan(info.rms, 0.001,
                              "Empty project should produce silent output")

            try? FileManager.default.removeItem(at: exportURL)
        } catch {
            // It's acceptable for empty project export to throw
            // as there's nothing to export
        }
    }

    // MARK: - Test: Audio Track With Region

    /// Create a project with an audio track containing a synthetic buffer,
    /// export, and verify the output contains audio.
    @MainActor
    func testAudioTrackExportIsNotSilent() async throws {
        // Create a synthetic WAV file
        let tempDir = try createTempDirectory()
        let syntheticWAV = tempDir.appendingPathComponent("test_audio.wav")

        // Generate a 2-second 440Hz sine wave
        try generateSineWAV(
            at: syntheticWAV,
            frequency: 440,
            duration: 2.0,
            sampleRate: 48000
        )

        // Create project with audio track
        var project = AudioProject(name: "SilenceTest-AudioTrack")
        var track = AudioTrack(name: "TestAudio", trackType: .audio)
        let fileSize = Int64((try? FileManager.default.attributesOfItem(atPath: syntheticWAV.path)[.size] as? Int64) ?? 0)
        let audioFile = AudioFile(
            name: "test_audio.wav",
            url: syntheticWAV,
            duration: 2.0,
            sampleRate: 48000,
            channels: 1,
            bitDepth: 24,
            fileSize: fileSize,
            format: .wav
        )
        let region = AudioRegion(
            audioFile: audioFile,
            startBeat: 0,
            durationBeats: 4
        )
        track.regions.append(region)
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

        // Cleanup
        cleanupTempDirectory(tempDir)
        try? FileManager.default.removeItem(at: exportURL)
    }

    // MARK: - Helpers

    /// Generate a WAV file containing a sine wave.
    private func generateSineWAV(
        at url: URL,
        frequency: Double,
        duration: Double,
        sampleRate: Double
    ) throws {
        let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: 1
        )!
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw TestError.invalidTestData("Failed to create buffer")
        }
        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData?[0] else {
            throw TestError.invalidTestData("No channel data")
        }

        for i in 0..<Int(frameCount) {
            let phase = 2.0 * Double.pi * frequency * Double(i) / sampleRate
            channelData[i] = Float(sin(phase)) * 0.5  // -6dB
        }

        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: format.settings
        )
        try audioFile.write(from: buffer)
    }
}
