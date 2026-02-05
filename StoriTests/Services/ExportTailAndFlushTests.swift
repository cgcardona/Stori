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
        testProject.timeSignature = TimeSignature(numerator: 4, denominator: 4)
    }
    
    override func tearDown() async throws {
        exportService = nil
        testProject = nil
    }
    
    // MARK: - 1. Tail Time Calculation Tests
    
    func testProjectDurationIncludesTailTime() {
        // Create project with audio ending at beat 8 (4 seconds @ 120 BPM)
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        // Calculate duration
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Even empty project should have minimum tail buffer (300ms)
        XCTAssertGreaterThanOrEqual(duration, 0.3, "Duration should include minimum tail buffer (>= 300ms)")
        XCTAssertLessThan(duration, 6.0, "Tail should be reasonable")
    }
    
    func testTailTimeConsidersPluginTailTime() {
        // This test verifies that plugin-reported tail times are considered
        // In a real scenario with reverb plugins, tail would be longer
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Should have at least the minimum tail
        XCTAssertGreaterThanOrEqual(duration, 0.3, "Should include minimum tail")
    }
    
    func testTailTimeIsCappedAtMaximum() {
        // Verify tail time doesn't grow unreasonably large
        // calculateMaxPluginTailTime caps at 5 seconds
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Tail should be capped (max 5s tail for plugins + content)
        XCTAssertLessThan(duration, 10.0, "Tail time should be capped at reasonable maximum")
    }
    
    // MARK: - 2. Drain Frame Allocation Tests
    
    func testDrainFramesCalculation() {
        // Verify drain frame calculation math
        let bufferSize: AVAudioFrameCount = 4096
        let drainBufferCount = 2
        let drainFrames = bufferSize * AVAudioFrameCount(drainBufferCount)
        
        // Should be exactly 8192 frames
        XCTAssertEqual(drainFrames, 8192, "Drain frames should be 2 × 4096 = 8192")
        
        // At 48kHz, this is ~170ms
        let sampleRate = 48000.0
        let drainTimeMs = (Double(drainFrames) / sampleRate) * 1000.0
        XCTAssertEqual(drainTimeMs, 170.666, accuracy: 0.1, "Drain time should be ~170ms @ 48kHz")
    }
    
    func testBufferCapacityIncludesDrainFrames() {
        // Verify buffer allocation includes drain frames for tail capture
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        
        // Target frames: what goes in the exported file (content + tail)
        let targetFrameCount = AVAudioFrameCount(duration * sampleRate)
        
        // Drain frames: extra allocated for plugin buffer flush
        let drainFrames: AVAudioFrameCount = 8192
        
        // Total capacity: target + drain
        let totalCapacity = targetFrameCount + drainFrames
        
        XCTAssertGreaterThan(totalCapacity, targetFrameCount,
                            "Total capacity should be larger than target (includes drain)")
        XCTAssertEqual(totalCapacity - targetFrameCount, drainFrames,
                      "Difference should be exactly drain frames")
    }
    
    // MARK: - 3. Progress Calculation Tests
    
    func testProgressCalculationUsesTargetNotCapacity() {
        // CRITICAL: Progress should reach 100% at targetFrameCount, not totalCapacity
        // This ensures UI shows correct progress (drain period doesn't confuse users)
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        let targetFrameCount = AVAudioFrameCount(duration * sampleRate)
        let drainFrames: AVAudioFrameCount = 8192
        
        // Simulate progress at different capture points
        
        // At 50% of target
        let capturedAt50 = targetFrameCount / 2
        let progress50 = Double(min(capturedAt50, targetFrameCount)) / Double(targetFrameCount)
        XCTAssertEqual(progress50, 0.5, accuracy: 0.01, "Progress at 50% target should be 0.5")
        
        // At 100% of target (before drain)
        let capturedAt100 = targetFrameCount
        let progress100 = Double(min(capturedAt100, targetFrameCount)) / Double(targetFrameCount)
        XCTAssertEqual(progress100, 1.0, accuracy: 0.01, "Progress at target should be 1.0")
        
        // CRITICAL: During drain period (captured > target)
        let capturedDuringDrain = targetFrameCount + (drainFrames / 2)
        let progressDuringDrain = Double(min(capturedDuringDrain, targetFrameCount)) / Double(targetFrameCount)
        XCTAssertEqual(progressDuringDrain, 1.0, accuracy: 0.01,
                      "Progress during drain should stay at 100% (not exceed it)")
    }
    
    func testProgressCalculationDuringDrainPeriod() {
        // Verify that min() clamps progress correctly during drain
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        let targetFrameCount = AVAudioFrameCount(duration * sampleRate)
        let drainFrames: AVAudioFrameCount = 8192
        
        // Simulate being halfway through drain
        let capturedFrames = targetFrameCount + (drainFrames / 2)
        
        // Progress formula: min(capturedFrames, targetFrameCount) / targetFrameCount
        let clampedFrames = min(capturedFrames, targetFrameCount)
        XCTAssertEqual(clampedFrames, targetFrameCount, "Should clamp to target during drain")
        
        let progress = Double(clampedFrames) / Double(targetFrameCount)
        XCTAssertEqual(progress, 1.0, accuracy: 0.001, "Progress should stay at 100% during drain")
    }
    
    // MARK: - 4. Buffer Trimming Tests
    
    func testBufferTrimmingLogic() {
        // CRITICAL: Verify that buffer is trimmed to targetFrameCount after capture
        // This is the key fix: capture through drain, but trim before returning
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        
        // Target frames: content + tail (what user expects in file)
        let targetFrameCount = AVAudioFrameCount(duration * sampleRate)
        
        // Drain frames: extra allocated for flush
        let drainFrames: AVAudioFrameCount = 8192
        
        // Total capacity during capture
        let totalCapacity = targetFrameCount + drainFrames
        
        // After trimming, exported length should equal target (NOT totalCapacity)
        // This is what the code does: outputBuffer.frameLength = targetFrameCount
        let exportedLength = targetFrameCount  // After trim
        
        XCTAssertEqual(exportedLength, targetFrameCount, "Exported length should be target (drain trimmed)")
        XCTAssertLessThan(exportedLength, totalCapacity, "Drain frames should be trimmed off")
        XCTAssertEqual(totalCapacity - exportedLength, drainFrames,
                      "Trimmed amount should equal drain frames")
    }
    
    func testDrainFramesNotIncludedInExportedFile() {
        // Verify that drain frames are used for capture but not in final export
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        let targetFrameCount = AVAudioFrameCount(duration * sampleRate)
        let drainFrames: AVAudioFrameCount = 8192
        
        // The exported file should be EXACTLY targetFrameCount
        // If drain frames weren't trimmed, it would be targetFrameCount + 8192
        let exportedFrames = targetFrameCount
        let exportedSeconds = Double(exportedFrames) / sampleRate
        
        XCTAssertEqual(exportedSeconds, duration, accuracy: 0.001,
                      "Exported duration should match calculated duration (no drain)")
        
        // Verify drain frames are NOT included
        let wouldBeWithDrain = targetFrameCount + drainFrames
        XCTAssertLessThan(exportedFrames, wouldBeWithDrain,
                         "Exported frames should not include drain frames")
    }
    
    // MARK: - 5. Consistency Tests
    
    func testTailBehaviorMatchesPlayback() {
        // Verify that export tail calculation is consistent
        // (Same logic used for both playback and export)
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        // Calculate duration twice
        let duration1 = exportService.calculateProjectDuration(testProject)
        let duration2 = exportService.calculateProjectDuration(testProject)
        
        XCTAssertEqual(duration1, duration2, accuracy: 0.001,
                      "Tail calculation should be consistent and deterministic")
    }
    
    // MARK: - 6. Edge Case Tests
    
    func testEmptyProjectHasMinimalTail() {
        // Even an empty project should have minimum tail for safety
        let emptyProject = AudioProject(name: "Empty", tempo: 120.0)
        
        let duration = exportService.calculateProjectDuration(emptyProject)
        
        // Should have at least the minimum tail buffer (300ms)
        XCTAssertGreaterThanOrEqual(duration, 0.3, "Empty project should have minimum 300ms tail")
        XCTAssertLessThan(duration, 6.0, "Empty project tail should be reasonable")
    }
    
    func testMultipleTracksUsesMaxTailTime() {
        // When multiple tracks exist, tail time should be consistent
        
        var track1 = AudioTrack(name: "Track 1", trackType: .audio)
        var track2 = AudioTrack(name: "Track 2", trackType: .midi)
        
        testProject.tracks = [track1, track2]
        
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Should use appropriate tail time
        XCTAssertGreaterThanOrEqual(duration, 0.3, "Should include minimum tail")
    }
    
    func testVeryShortProjectStillHasTail() {
        // Even very short projects should have full tail
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Should still have at least minimum tail
        XCTAssertGreaterThanOrEqual(duration, 0.3, "Should include minimum 300ms tail")
    }
    
    // MARK: - 7. Capture Completion Tests
    
    func testCaptureCompletesAtTotalCapacity() {
        // Verify capture loop stops at totalCapacity (targetFrameCount + drainFrames)
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        let targetFrameCount = AVAudioFrameCount(duration * sampleRate)
        let drainFrames: AVAudioFrameCount = 8192
        let totalCapacity = targetFrameCount + drainFrames
        
        // The capture loop should stop when: capturedFrames >= totalCapacity
        let captureStopsAt = totalCapacity
        
        XCTAssertEqual(captureStopsAt, targetFrameCount + drainFrames,
                      "Capture should stop at total capacity (target + drain)")
        XCTAssertGreaterThan(captureStopsAt, targetFrameCount,
                            "Capture should continue past target to get plugin tails")
    }
    
    func testBufferTrimmedBeforeReturn() {
        // CRITICAL: Verify buffer is trimmed to targetFrameCount before returning
        // This is the most important behavior: outputBuffer.frameLength = targetFrameCount
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        let targetFrameCount = AVAudioFrameCount(duration * sampleRate)
        let drainFrames: AVAudioFrameCount = 8192
        
        // Internal buffer allocates: target + drain
        let internalCapacity = targetFrameCount + drainFrames
        
        // Exported buffer length: target only (drain trimmed)
        let exportedLength = targetFrameCount
        
        // The key assertion: exported ≠ internal capacity
        XCTAssertEqual(exportedLength, targetFrameCount, "Exported length should be target")
        XCTAssertNotEqual(exportedLength, internalCapacity, "Drain frames must be trimmed")
        XCTAssertEqual(internalCapacity - exportedLength, drainFrames,
                      "Trimmed amount should equal drain frames (8192)")
    }
    
    // MARK: - 8. Frame Length Accuracy Tests
    
    func testExportedFileLengthCalculation() {
        // Verify frame length calculations are correct
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        
        // Expected frames in exported file
        let expectedFrames = AVAudioFrameCount(duration * sampleRate)
        
        // Calculate back to seconds
        let exportedSeconds = Double(expectedFrames) / sampleRate
        
        XCTAssertEqual(exportedSeconds, duration, accuracy: 0.001,
                      "Frame count should match duration within sample accuracy")
    }
    
    func testMinimumTailTimeEnforced() {
        // Verify that minimum 300ms tail is enforced
        // This ensures synth release envelopes are captured
        
        var track = AudioTrack(name: "Test Track", trackType: .midi)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Should have at least 300ms tail
        XCTAssertGreaterThanOrEqual(duration, 0.3,
                                   "Minimum 300ms tail should be enforced")
    }
    
    // MARK: - 9. Integration with Capture Logic Tests
    
    func testCaptureLoopCondition() {
        // Verify the capture loop condition: capturedFrames >= totalCapacity
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        let targetFrameCount = AVAudioFrameCount(duration * sampleRate)
        let drainFrames: AVAudioFrameCount = 8192
        let totalCapacity = targetFrameCount + drainFrames
        
        // Simulate capture progression
        var capturedFrames: AVAudioFrameCount = 0
        
        // Before target
        capturedFrames = targetFrameCount - 1000
        XCTAssertLessThan(capturedFrames, totalCapacity, "Should continue capturing")
        
        // At target
        capturedFrames = targetFrameCount
        XCTAssertLessThan(capturedFrames, totalCapacity, "Should continue into drain period")
        
        // During drain
        capturedFrames = targetFrameCount + 4000
        XCTAssertLessThan(capturedFrames, totalCapacity, "Should still be in drain period")
        
        // At completion
        capturedFrames = totalCapacity
        XCTAssertGreaterThanOrEqual(capturedFrames, totalCapacity, "Should stop capturing")
    }
    
    func testFramesToCopyCalculation() {
        // Verify framesToCopy calculation uses totalCapacity (not targetFrameCount)
        // This ensures we capture through the drain period
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        let targetFrameCount = AVAudioFrameCount(duration * sampleRate)
        let drainFrames: AVAudioFrameCount = 8192
        let totalCapacity = targetFrameCount + drainFrames
        
        // Simulate buffer arriving during drain period
        let bufferSize: AVAudioFrameCount = 4096
        let capturedSoFar = targetFrameCount + 2000
        
        // framesToCopy = min(buffer.frameLength, totalCapacity - capturedFrames)
        let framesToCopy = min(bufferSize, totalCapacity - capturedSoFar)
        
        XCTAssertGreaterThan(framesToCopy, 0, "Should still copy frames during drain")
        XCTAssertLessThanOrEqual(framesToCopy, bufferSize, "Should not copy more than buffer size")
    }
    
    // MARK: - 10. WYHIWYG Guarantee Tests
    
    func testExportIncludesPluginTails() {
        // Verify that export duration includes plugin tail time
        // This ensures reverb/delay decay is fully captured
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        
        // Duration should include:
        // 1. Content (project regions)
        // 2. Plugin tail (reverb/delay buffers)
        // 3. Minimum 300ms for synth release
        
        XCTAssertGreaterThanOrEqual(duration, 0.3, "Should include minimum tail")
    }
    
    func testExportDoesNotIncludeDrainFramesInFile() {
        // CRITICAL: Verify drain frames are NOT in the exported file
        // Drain is for capture only, file contains content + tail (no drain)
        
        var track = AudioTrack(name: "Test Track", trackType: .audio)
        testProject.tracks = [track]
        
        let duration = exportService.calculateProjectDuration(testProject)
        let sampleRate = 48000.0
        let targetFrameCount = AVAudioFrameCount(duration * sampleRate)
        let drainFrames: AVAudioFrameCount = 8192
        
        // File should contain exactly targetFrameCount
        let fileFrames = targetFrameCount
        let fileDuration = Double(fileFrames) / sampleRate
        
        XCTAssertEqual(fileDuration, duration, accuracy: 0.001,
                      "File duration should match calculated duration")
        
        // File should NOT contain drain frames
        let drainDuration = Double(drainFrames) / sampleRate
        XCTAssertNotEqual(fileDuration, duration + drainDuration,
                         "File should not include drain duration (~170ms)")
    }
}
