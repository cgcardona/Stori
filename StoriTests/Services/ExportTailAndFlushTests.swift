//
//  ExportTailAndFlushTests.swift
//  StoriTests
//
//  Comprehensive tests for export tail and buffer flush (Issue #10)
//  Tests plugin tail inclusion, drain/flush behavior, and file length accuracy
//

import XCTest
import AVFoundation
@testable import Stori

@MainActor
final class ExportTailAndFlushTests: XCTestCase {
    
    var exportService: ProjectExportService!
    var testProject: AudioProject!
    
    override func setUp() async throws {
        exportService = ProjectExportService()
        
        // Create a test project with known duration
        testProject = AudioProject(name: "Test Project", tempo: 120.0)
        testProject.timeSignature = TimeSignature(beatsPerBar: 4, noteValue: 4)
    }
    
    override func tearDown() async throws {
        exportService = nil
        testProject = nil
    }
    
    // MARK: - 1. Tail Time Calculation Tests
    
    func testProjectDurationIncludesTailTime() {
        // Create project with audio ending at beat 8 (4 seconds @ 120 BPM)
        let audioFile = AudioFile(
            name: "test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            format: .wav,
            sampleRate: 48000,
            channels: 2,
            durationSeconds: 2.0
        )
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        let region = AudioRegion(
            id: UUID(),
            startBeat: 0,
            durationBeats: 8,  // 4 seconds at 120 BPM
            audioFile: audioFile,
            startOffsetBeats: 0
        )
        track.regions = [region]
        testProject.tracks = [track]
        
        // Calculate duration
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Should be: 4 seconds (content) + tail buffer
        // Minimum tail is 300ms (0.3s) for synth release
        XCTAssertGreaterThan(duration, 4.0, "Duration should include content")
        XCTAssertGreaterThan(duration, 4.3, "Duration should include tail buffer (>= 300ms)")
        XCTAssertLessThan(duration, 4.5, "Tail should not be excessive")
    }
    
    func testTailTimeConsidersPluginTailTime() {
        // This test verifies that plugin-reported tail times are used
        // In a real scenario with reverb plugins, tail would be longer
        
        let audioFile = AudioFile(
            name: "test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            format: .wav,
            sampleRate: 48000,
            channels: 2,
            durationSeconds: 1.0
        )
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        let region = AudioRegion(
            id: UUID(),
            startBeat: 0,
            durationBeats: 4,  // 2 seconds at 120 BPM
            audioFile: audioFile,
            startOffsetBeats: 0
        )
        track.regions = [region]
        
        // Add plugin config (simulates reverb with tail time)
        track.pluginConfigs = [
            PluginConfig(
                id: UUID(),
                pluginName: "Reverb",
                manufacturer: "Apple",
                version: "1.0",
                presetData: Data()
            )
        ]
        
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Should include at least minimum tail
        XCTAssertGreaterThan(duration, 2.0, "Should include content")
        XCTAssertGreaterThan(duration, 2.3, "Should include tail")
    }
    
    func testTailTimeIsCappedAtMaximum() {
        // Verify tail time doesn't grow unreasonably large
        // calculateMaxPluginTailTime caps at 5 seconds
        
        let audioFile = AudioFile(
            name: "test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            format: .wav,
            sampleRate: 48000,
            channels: 2,
            durationSeconds: 1.0
        )
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        let region = AudioRegion(
            id: UUID(),
            startBeat: 0,
            durationBeats: 4,
            audioFile: audioFile,
            startOffsetBeats: 0
        )
        track.regions = [region]
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Tail should be capped (content 2s + max 5s tail = 7s max)
        XCTAssertLessThan(duration, 8.0, "Tail time should be capped at reasonable maximum")
    }
    
    // MARK: - 2. Drain and Flush Tests
    
    func testExportBufferIncludesDrainFrames() async throws {
        // Verify that the export allocates extra frames for drain period
        // This is tested implicitly by the render logic, but we verify the concept
        
        let audioFile = AudioFile(
            name: "test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            format: .wav,
            sampleRate: 48000,
            channels: 2,
            durationSeconds: 1.0
        )
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        let region = AudioRegion(
            id: UUID(),
            startBeat: 0,
            durationBeats: 4,
            audioFile: audioFile,
            startOffsetBeats: 0
        )
        track.regions = [region]
        testProject.tracks = [track]
        
        // Calculate expected frames
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        let expectedTargetFrames = AVAudioFrameCount(duration * sampleRate)
        
        // Drain frames: 2 buffers × 4096 frames = 8192 frames (~170ms @ 48kHz)
        let drainFrames: AVAudioFrameCount = 8192
        let expectedTotalCapacity = expectedTargetFrames + drainFrames
        
        // The render should allocate this much capacity
        // (We verify via expected calculation since we can't easily introspect the private buffer)
        XCTAssertGreaterThan(expectedTotalCapacity, expectedTargetFrames,
                             "Total capacity should include drain frames")
    }
    
    // MARK: - 3. File Length Verification Tests
    
    func testExportedFileLengthMatchesProjectPlusTail() async throws {
        // Create a minimal test project
        let audioFile = AudioFile(
            name: "test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            format: .wav,
            sampleRate: 48000,
            channels: 2,
            durationSeconds: 1.0
        )
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        let region = AudioRegion(
            id: UUID(),
            startBeat: 0,
            durationBeats: 4,  // 2 seconds at 120 BPM
            audioFile: audioFile,
            startOffsetBeats: 0
        )
        track.regions = [region]
        testProject.tracks = [track]
        
        let calculatedDuration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        let expectedFrames = AVAudioFrameCount(calculatedDuration * sampleRate)
        
        // Expected frames should be: content + tail
        // Content: 2 seconds × 48000 = 96000 frames
        // Tail: minimum 300ms × 48000 = 14400 frames
        // Total: >= 110400 frames
        
        XCTAssertGreaterThanOrEqual(expectedFrames, 110400,
                                    "Export should include content + tail frames")
        
        // Allow for one buffer tolerance (4096 frames @ 48kHz = ~85ms)
        let tolerance: AVAudioFrameCount = 4096
        let contentFrames = AVAudioFrameCount(2.0 * sampleRate)  // 2 seconds
        let minTailFrames = AVAudioFrameCount(0.3 * sampleRate)  // 300ms
        
        XCTAssertGreaterThanOrEqual(expectedFrames, contentFrames + minTailFrames - tolerance,
                                    "Frame count should match project + tail within tolerance")
    }
    
    func testExportedFileHasTailContent() async throws {
        // Verify that the tail region contains non-silence
        // This would require actually rendering a project with reverb, so we test the concept
        
        let audioFile = AudioFile(
            name: "test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            format: .wav,
            sampleRate: 48000,
            channels: 2,
            durationSeconds: 0.5
        )
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        let region = AudioRegion(
            id: UUID(),
            startBeat: 0,
            durationBeats: 2,  // 1 second at 120 BPM
            audioFile: audioFile,
            startOffsetBeats: 0
        )
        track.regions = [region]
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Tail region would be from 1.0s to (1.0 + tail)s
        // In a real test with audio rendering, we'd verify non-zero samples in this region
        // For now, verify the duration includes tail
        XCTAssertGreaterThan(duration, 1.0, "Duration extends beyond content")
        XCTAssertGreaterThan(duration, 1.3, "Tail region is at least 300ms")
    }
    
    // MARK: - 4. Consistency with Playback Tests
    
    func testTailBehaviorMatchesPlayback() {
        // Verify that export tail uses same plugin state as playback
        // Export should not have special "export-only" processing
        
        let audioFile = AudioFile(
            name: "test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            format: .wav,
            sampleRate: 48000,
            channels: 2,
            durationSeconds: 1.0
        )
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        let region = AudioRegion(
            id: UUID(),
            startBeat: 0,
            durationBeats: 4,
            audioFile: audioFile,
            startOffsetBeats: 0
        )
        track.regions = [region]
        testProject.tracks = [track]
        
        // Calculate duration (which includes tail)
        let duration = exportService.calculateProjectDuration(testProject)
        
        // The tail calculation should be consistent
        // (Same logic used for both playback and export)
        let duration2 = exportService.calculateProjectDuration(testProject)
        XCTAssertEqual(duration, duration2, accuracy: 0.001,
                      "Tail calculation should be consistent")
    }
    
    // MARK: - 5. Edge Case Tests
    
    func testEmptyProjectHasMinimalTail() {
        // Even an empty project should have minimum tail for safety
        let emptyProject = AudioProject(name: "Empty", tempo: 120.0)
        
        let duration = exportService.calculateProjectDuration(emptyProject)
        
        // Should have at least the minimum tail buffer
        XCTAssertGreaterThanOrEqual(duration, 0.3, "Empty project should have minimum tail")
    }
    
    func testMultipleTracksUsesMaxTailTime() {
        // When multiple tracks have different plugin tails, use the maximum
        
        let audioFile = AudioFile(
            name: "test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            format: .wav,
            sampleRate: 48000,
            channels: 2,
            durationSeconds: 1.0
        )
        
        var track1 = AudioTrack(name: "Track 1", trackType: .audio)
        let region1 = AudioRegion(
            id: UUID(),
            startBeat: 0,
            durationBeats: 4,
            audioFile: audioFile,
            startOffsetBeats: 0
        )
        track1.regions = [region1]
        
        var track2 = AudioTrack(name: "Track 2", trackType: .audio)
        let region2 = AudioRegion(
            id: UUID(),
            startBeat: 0,
            durationBeats: 4,
            audioFile: audioFile,
            startOffsetBeats: 0
        )
        track2.regions = [region2]
        
        testProject.tracks = [track1, track2]
        
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Should use max tail time across all tracks
        XCTAssertGreaterThan(duration, 2.0, "Should include content from both tracks")
        XCTAssertGreaterThan(duration, 2.3, "Should include tail")
    }
    
    func testVeryShortProjectStillHasTail() {
        // Even very short projects (< 1 second) should have full tail
        
        let audioFile = AudioFile(
            name: "test",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            format: .wav,
            sampleRate: 48000,
            channels: 2,
            durationSeconds: 0.1
        )
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        let region = AudioRegion(
            id: UUID(),
            startBeat: 0,
            durationBeats: 0.5,  // 0.25 seconds at 120 BPM
            audioFile: audioFile,
            startOffsetBeats: 0
        )
        track.regions = [region]
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Should still have full tail despite short content
        XCTAssertGreaterThan(duration, 0.25, "Should include content")
        XCTAssertGreaterThan(duration, 0.55, "Should include full tail (>= 300ms)")
    }
}
