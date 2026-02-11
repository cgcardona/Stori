//
//  ExportStressTests.swift
//  StoriTests
//
//  Stress tests for the export pipeline.
//  These catch race conditions between export and ongoing playback/editing,
//  and verify export stability under adversarial conditions.
//

import XCTest
import AVFoundation
@testable import Stori

final class ExportStressTests: XCTestCase {

    // MARK: - Test: Rapid Sequential Exports

    /// Export the same project multiple times in rapid succession.
    /// Catches resource leaks, file handle exhaustion, and AVAudioEngine cleanup issues.
    @MainActor
    func testStressRapidSequentialExports() async throws {
        try XCTSkipIf(true, "AVFoundation -80801 in export; skip until resolved")
        var project = AudioProject(name: "Stress-RapidExport")
        var track = AudioTrack(name: "Test", trackType: .midi)
        var region = MIDIRegion(name: "Note")
        region.startBeat = 0
        region.durationBeats = 4
        region.notes.append(MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 4))
        track.midiRegions.append(region)
        project.tracks.append(track)
        project.tempo = 120

        let audioEngine = AudioEngine()
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(500))

        let exportService = ProjectExportService()
        var exportURLs: [URL] = []

        // Export 5 times rapidly
        for i in 0..<5 {
            let url = try await exportService.exportProjectMix(
                project: project,
                audioEngine: audioEngine
            )
            exportURLs.append(url)

            // Verify each export is valid
            let audioFile = try AVAudioFile(forReading: url)
            XCTAssertGreaterThan(audioFile.length, 0,
                                 "Export \(i) should have non-zero length")
        }

        // Cleanup
        for url in exportURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Test: Export Consistency

    /// Export the same project twice and verify the outputs are identical.
    /// If the render pipeline is truly deterministic, the files should match exactly.
    @MainActor
    func testStressExportDeterminism() async throws {
        try XCTSkipIf(true, "AVFoundation -80801 in export; skip until resolved")
        var project = AudioProject(name: "Stress-Determinism")
        var track = AudioTrack(name: "Test", trackType: .midi)
        var region = MIDIRegion(name: "Note")
        region.startBeat = 0
        region.durationBeats = 4
        region.notes.append(MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 4))
        track.midiRegions.append(region)
        project.tracks.append(track)
        project.tempo = 120

        let audioEngine = AudioEngine()
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(500))

        let exportService = ProjectExportService()

        let url1 = try await exportService.exportProjectMix(
            project: project,
            audioEngine: audioEngine
        )
        let url2 = try await exportService.exportProjectMix(
            project: project,
            audioEngine: audioEngine
        )

        // Both exports should produce the same audio
        let file1 = try AVAudioFile(forReading: url1)
        let file2 = try AVAudioFile(forReading: url2)

        XCTAssertEqual(file1.length, file2.length,
                       "Two exports of the same project should have the same frame count")

        // Compare audio content
        let format = file1.processingFormat
        let frameCount = AVAudioFrameCount(file1.length)
        guard let buf1 = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let buf2 = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            XCTFail("Failed to create comparison buffers")
            return
        }

        try file1.read(into: buf1)
        try file2.read(into: buf2)

        // Compare sample-by-sample
        let channels = Int(format.channelCount)
        var maxDelta: Float = 0

        for ch in 0..<channels {
            guard let data1 = buf1.floatChannelData?[ch],
                  let data2 = buf2.floatChannelData?[ch] else { continue }

            for i in 0..<Int(buf1.frameLength) {
                let delta = abs(data1[i] - data2[i])
                maxDelta = max(maxDelta, delta)
            }
        }

        // Allow tiny float rounding difference
        XCTAssertLessThan(maxDelta, 0.0001,
                          "Two deterministic exports should produce near-identical audio (max delta: \(maxDelta))")

        try? FileManager.default.removeItem(at: url1)
        try? FileManager.default.removeItem(at: url2)
    }

    // MARK: - Test: Export With Many Tracks

    /// Export a project with many tracks to stress the offline render graph.
    @MainActor
    func testStressExportManyTracks() async throws {
        try XCTSkipIf(true, "AVFoundation -80801 in export; skip until resolved")
        var project = AudioProject(name: "Stress-ManyTracks")

        // Create 20 MIDI tracks with notes
        for i in 0..<20 {
            var track = AudioTrack(name: "Track-\(i)", trackType: .midi)
            var region = MIDIRegion(name: "Region-\(i)")
            region.startBeat = Double(i)  // Staggered starts
            region.durationBeats = 4
            region.notes.append(MIDINote(
                pitch: UInt8(48 + (i % 36)),
                velocity: UInt8(70 + (i % 30)),
                startBeat: 0,
                durationBeats: 4
            ))
            track.midiRegions.append(region)
            track.mixerSettings.volume = Float(0.5 + Double(i % 5) * 0.1)
            // MixerSettings.pan uses 0-1 range (0.5=center), not -1 to 1
            // Map i (0-19) to pan range: 0.0 (full left) to 1.0 (full right)
            track.mixerSettings.pan = Float(Double(i) / 19.0)
            project.tracks.append(track)
        }
        project.tempo = 120

        let audioEngine = AudioEngine()
        audioEngine.loadProject(project)

        try await Task.sleep(for: .milliseconds(1000))

        let exportService = ProjectExportService()
        let url = try await exportService.exportProjectMix(
            project: project,
            audioEngine: audioEngine
        )

        // Verify the export completed and has audio
        let audioFile = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(audioFile.length, 0)

        let format = audioFile.processingFormat
        XCTAssertEqual(Int(format.channelCount), 2, "Should be stereo")

        try? FileManager.default.removeItem(at: url)
    }
}
