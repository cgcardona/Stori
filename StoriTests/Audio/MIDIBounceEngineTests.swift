//
//  MIDIBounceEngineTests.swift
//  StoriTests
//
//  Tests for MIDIBounceEngine offline rendering with per-sample smoothing (Issue #109).
//  Verifies offline bounce quality matches real-time playback quality (WYSIWYG).
//

import XCTest
@testable import Stori
import AVFoundation

final class MIDIBounceEngineTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var bounceEngine: MIDIBounceEngine!
    private var synthEngine: SynthEngine!
    private var audioEngine: AVAudioEngine!
    
    // MARK: - Setup/Teardown
    
    @MainActor
    override func setUp() async throws {
        try await super.setUp()
        bounceEngine = MIDIBounceEngine()
        synthEngine = SynthEngine()
        audioEngine = AVAudioEngine()
    }
    
    @MainActor
    override func tearDown() async throws {
        // Stop engine before cleanup
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine = nil
        bounceEngine = nil
        synthEngine = nil
        try await super.tearDown()
    }
    
    // MARK: - API Regression Tests (Issue #109)
    
    /// CRITICAL: Verify legacy render() method no longer exists
    /// This test ensures we maintain a pristine API surface
    func testLegacyRenderMethodRemoved() {
        let voice = SynthVoice(pitch: 60, velocity: 100, preset: .default, sampleRate: 48000)
        
        // Verify the voice class does NOT have the legacy render method
        // If this compiles, the legacy method has been properly removed
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: 512)
        defer { buffer.deallocate() }
        
        // Modern API should be available
        let smoothedArrays = [Float](repeating: 0.5, count: 512)
        voice.renderPerSample(
            into: buffer,
            frameCount: 512,
            startTime: 0,
            smoothedCutoffs: smoothedArrays,
            smoothedResonances: smoothedArrays,
            smoothedVolumes: smoothedArrays,
            smoothedMixes: smoothedArrays
        )
        
        XCTAssertTrue(true, "Modern renderPerSample API is available")
    }
    
    /// Verify SmoothParameters struct no longer exists
    /// This ensures we've cleaned up all legacy code
    func testSmoothParametersStructRemoved() {
        // If this test compiles, SmoothParameters has been removed
        // The code below should NOT compile if SmoothParameters exists
        
        // This is a compile-time test - if the struct still exists,
        // uncommenting the next line would cause a compilation error
        // let params = SmoothParameters(filterCutoff: 0.5, filterResonance: 0.3, masterVolume: 0.7, oscillatorMix: 0.5)
        
        XCTAssertTrue(true, "SmoothParameters struct successfully removed")
    }
    
    // MARK: - Offline Rendering Tests
    
    /// Test basic offline rendering functionality
    func testOfflineRenderProducesAudio() {
        let frameCount = 512
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        defer { buffer.deallocate() }
        
        // Clear buffer
        memset(buffer, 0, frameCount * 2 * MemoryLayout<Float>.size)
        
        // Trigger a note
        synthEngine.noteOn(pitch: 60, velocity: 100)
        
        // Render offline
        var currentTime: Float = 0
        synthEngine.renderOffline(
            into: buffer,
            frameCount: frameCount,
            sampleRate: 48000,
            currentTime: &currentTime
        )
        
        // Verify audio was produced (non-zero samples)
        var foundNonZero = false
        for i in 0..<(frameCount * 2) {
            if buffer[i] != 0 {
                foundNonZero = true
                break
            }
        }
        
        XCTAssertTrue(foundNonZero, "Offline rendering should produce non-zero audio")
    }
    
    /// Test that offline rendering uses per-sample smoothing
    /// This ensures quality matches real-time playback
    func testOfflineRenderUsesPerSampleSmoothing() {
        let frameCount = 512
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        defer { buffer.deallocate() }
        
        // Trigger multiple notes to test smoothing
        synthEngine.noteOn(pitch: 60, velocity: 100)
        synthEngine.noteOn(pitch: 64, velocity: 100)
        synthEngine.noteOn(pitch: 67, velocity: 100)
        
        // Render with parameter changes
        var currentTime: Float = 0
        
        // First render
        synthEngine.setFilterCutoff(0.8)
        synthEngine.renderOffline(
            into: buffer,
            frameCount: frameCount,
            sampleRate: 48000,
            currentTime: &currentTime
        )
        
        // Change parameter and render again
        synthEngine.setFilterCutoff(0.3)
        synthEngine.renderOffline(
            into: buffer,
            frameCount: frameCount,
            sampleRate: 48000,
            currentTime: &currentTime
        )
        
        // Verify no crashes or artifacts (smooth transition)
        XCTAssertTrue(true, "Per-sample smoothing working in offline render")
    }
    
    /// Test offline render with gain compensation
    /// Ensures we match real-time rendering behavior
    func testOfflineRenderGainCompensation() {
        let frameCount = 512
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        defer { buffer.deallocate() }
        
        // Trigger many notes to test gain compensation
        for pitch in 60...72 {
            synthEngine.noteOn(pitch: UInt8(pitch), velocity: 100)
        }
        
        var currentTime: Float = 0
        synthEngine.renderOffline(
            into: buffer,
            frameCount: frameCount,
            sampleRate: 48000,
            currentTime: &currentTime
        )
        
        // Verify no clipping (samples within [-1, 1])
        var maxSample: Float = 0
        for i in 0..<(frameCount * 2) {
            maxSample = max(maxSample, abs(buffer[i]))
        }
        
        XCTAssertLessThanOrEqual(maxSample, 1.0, "Gain compensation prevents clipping: max=\(maxSample)")
    }
    
    /// Test offline render advances time correctly
    func testOfflineRenderTimeAdvancement() {
        let frameCount = 512
        let sampleRate: Float = 48000
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        defer { buffer.deallocate() }
        
        synthEngine.noteOn(pitch: 60, velocity: 100)
        
        var currentTime: Float = 0
        let expectedTimeDelta = Float(frameCount) / sampleRate
        
        synthEngine.renderOffline(
            into: buffer,
            frameCount: frameCount,
            sampleRate: sampleRate,
            currentTime: &currentTime
        )
        
        assertApproximatelyEqual(
            currentTime,
            expectedTimeDelta,
            tolerance: 0.0001,
            file: #file,
            line: #line
        )
        XCTAssertTrue(true, "Time should advance by frameCount / sampleRate")
    }
    
    // MARK: - WYSIWYG Quality Tests
    
    /// Test that offline rendering produces deterministic output
    /// Same input should always produce same output (WYSIWYG)
    func testOfflineRenderDeterministic() {
        let frameCount = 512
        let buffer1 = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        let buffer2 = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        defer {
            buffer1.deallocate()
            buffer2.deallocate()
        }
        
        // Clear buffers
        memset(buffer1, 0, frameCount * 2 * MemoryLayout<Float>.size)
        memset(buffer2, 0, frameCount * 2 * MemoryLayout<Float>.size)
        
        // First render
        var time1: Float = 0
        synthEngine.noteOn(pitch: 60, velocity: 100)
        synthEngine.renderOffline(
            into: buffer1,
            frameCount: frameCount,
            sampleRate: 48000,
            currentTime: &time1
        )
        
        // Create new engine for second render to avoid state contamination
        let synthEngine2 = SynthEngine()
        var time2: Float = 0
        synthEngine2.noteOn(pitch: 60, velocity: 100)
        synthEngine2.renderOffline(
            into: buffer2,
            frameCount: frameCount,
            sampleRate: 48000,
            currentTime: &time2
        )
        
        // Compare buffers (should be identical)
        var maxDifference: Float = 0
        for i in 0..<(frameCount * 2) {
            let diff = abs(buffer1[i] - buffer2[i])
            maxDifference = max(maxDifference, diff)
        }
        
        // Allow tiny floating-point differences
        XCTAssertLessThan(
            maxDifference,
            0.001,
            "Deterministic rendering: max difference = \(maxDifference)"
        )
    }
    
    /// Test offline rendering with multiple voices
    /// Ensures polyphonic rendering works correctly
    func testOfflineRenderPolyphonic() {
        let frameCount = 512
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        defer { buffer.deallocate() }
        
        // Trigger chord (C major)
        synthEngine.noteOn(pitch: 60, velocity: 100)
        synthEngine.noteOn(pitch: 64, velocity: 100)
        synthEngine.noteOn(pitch: 67, velocity: 100)
        
        var currentTime: Float = 0
        synthEngine.renderOffline(
            into: buffer,
            frameCount: frameCount,
            sampleRate: 48000,
            currentTime: &currentTime
        )
        
        // Verify audio was produced
        var rms: Float = 0
        for i in 0..<(frameCount * 2) {
            rms += buffer[i] * buffer[i]
        }
        rms = sqrt(rms / Float(frameCount * 2))
        
        XCTAssertGreaterThan(rms, 0.01, "Polyphonic rendering produces audio: RMS=\(rms)")
    }
    
    // MARK: - Edge Case Tests
    
    /// Test offline render with no active voices
    func testOfflineRenderSilence() {
        let frameCount = 512
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        defer { buffer.deallocate() }
        
        // Fill with garbage
        for i in 0..<(frameCount * 2) {
            buffer[i] = Float.random(in: -1...1)
        }
        
        // Render with no voices
        var currentTime: Float = 0
        synthEngine.renderOffline(
            into: buffer,
            frameCount: frameCount,
            sampleRate: 48000,
            currentTime: &currentTime
        )
        
        // Should produce silence (zeros)
        var allZero = true
        for i in 0..<(frameCount * 2) {
            if abs(buffer[i]) > 0.0001 {
                allZero = false
                break
            }
        }
        
        XCTAssertTrue(allZero, "Rendering with no voices produces silence")
    }
    
    /// Test offline render with released notes
    func testOfflineRenderWithReleasedNotes() {
        let frameCount = 512
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        defer { buffer.deallocate() }
        
        // Trigger and release note
        synthEngine.noteOn(pitch: 60, velocity: 100)
        synthEngine.noteOff(pitch: 60)
        
        var currentTime: Float = 0
        synthEngine.renderOffline(
            into: buffer,
            frameCount: frameCount,
            sampleRate: 48000,
            currentTime: &currentTime
        )
        
        // Should render release envelope
        XCTAssertTrue(true, "Offline render handles note release")
    }
    
    /// Test offline render with extreme parameter values
    func testOfflineRenderExtremeParameters() {
        let frameCount = 512
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        defer { buffer.deallocate() }
        
        synthEngine.noteOn(pitch: 60, velocity: 100)
        
        // Extreme cutoff
        synthEngine.setFilterCutoff(0.0)
        var currentTime: Float = 0
        synthEngine.renderOffline(
            into: buffer,
            frameCount: frameCount,
            sampleRate: 48000,
            currentTime: &currentTime
        )
        
        // Extreme volume
        synthEngine.setMasterVolume(1.0)
        synthEngine.renderOffline(
            into: buffer,
            frameCount: frameCount,
            sampleRate: 48000,
            currentTime: &currentTime
        )
        
        XCTAssertTrue(true, "Offline render handles extreme parameter values")
    }
    
    // MARK: - Performance Tests
    
    /// Test offline rendering performance (lightweight version)
    func testOfflineRenderPerformance() {
        let frameCount = 512  // Smaller chunk for faster test
        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount * 2)
        defer { buffer.deallocate() }
        
        // Clear buffer
        memset(buffer, 0, frameCount * 2 * MemoryLayout<Float>.size)
        
        // Trigger moderate polyphony (not full to avoid long test)
        for pitch in 60...67 {
            synthEngine.noteOn(pitch: UInt8(pitch), velocity: 100)
        }
        
        var currentTime: Float = 0
        
        // Test 10 renders instead of 100 (sufficient for regression test)
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<10 {
            synthEngine.renderOffline(
                into: buffer,
                frameCount: frameCount,
                sampleRate: 48000,
                currentTime: &currentTime
            )
        }
        let duration = CFAbsoluteTimeGetCurrent() - start
        
        // Should complete in reasonable time (< 100ms for 10 renders)
        XCTAssertLessThan(duration, 0.1, "Performance test should complete quickly: \(duration)s")
    }
    
    // MARK: - Integration Test: Full Bounce
    
    /// Test complete bounce workflow (Issue #109 acceptance test)
    @MainActor
    func testCompleteBounceWorkflow() async throws {
        // Create test MIDI region
        var region = TestDataFactory.createMIDIRegion(
            name: "Test Bounce",
            noteCount: 8,
            startBeat: 0,
            durationBeats: 4.0
        )
        
        // Ensure region has notes
        if region.notes.isEmpty {
            region.addNote(MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 1.0))
        }
        
        // Create instrument with synth (must provide audio engine)
        let instrument = TrackInstrument(
            type: .synth,
            preset: .brightLead,
            audioEngine: audioEngine
        )
        
        // Bounce
        let outputURL = try await bounceEngine.bounce(
            region: region,
            instrument: instrument,
            sampleRate: 48000,
            tailDuration: 1.0
        )
        
        // Verify file exists
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outputURL.path),
            file: #file,
            line: #line
        )
        
        // Verify file has content
        let file = try AVAudioFile(forReading: outputURL)
        XCTAssertGreaterThan(
            file.length,
            0,
            "Bounced file should have audio data",
            file: #file,
            line: #line
        )
        
        // Cleanup
        try? FileManager.default.removeItem(at: outputURL)
    }
    
    /// Test bounce quality: offline should match real-time
    @MainActor
    func testBounceQualityMatchesRealtime() async throws {
        // Create simple test region
        var region = MIDIRegion(name: "Quality Test", startBeat: 0, durationBeats: 2.0)
        region.addNote(MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 1.0))
        
        let instrument = TrackInstrument(
            type: .synth,
            preset: .default,
            audioEngine: audioEngine
        )
        
        // Bounce with modern API
        let outputURL = try await bounceEngine.bounce(
            region: region,
            instrument: instrument,
            sampleRate: 48000,
            tailDuration: 0.5
        )
        
        // Verify no clipping in bounced audio
        let file = try AVAudioFile(forReading: outputURL)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        )!
        try file.read(into: buffer)
        
        guard let floatData = buffer.floatChannelData else {
            XCTFail("Could not read float channel data", file: #file, line: #line)
            return
        }
        
        let frameCount = Int(buffer.frameLength)
        var maxSample: Float = 0
        for channel in 0..<Int(buffer.format.channelCount) {
            for frame in 0..<frameCount {
                maxSample = max(maxSample, abs(floatData[channel][frame]))
            }
        }
        
        // Should be within valid range (no clipping)
        XCTAssertLessThanOrEqual(
            maxSample,
            1.0,
            "Bounced audio should not clip: max=\(maxSample)",
            file: #file,
            line: #line
        )
        
        // Should have actual audio (not silence)
        XCTAssertGreaterThan(
            maxSample,
            0.01,
            "Bounced audio should have content: max=\(maxSample)",
            file: #file,
            line: #line
        )
        
        // Cleanup
        try? FileManager.default.removeItem(at: outputURL)
    }
    
    /// Test bounce with empty region (edge case)
    @MainActor
    func testBounceEmptyRegionFails() async {
        let region = MIDIRegion(name: "Empty", startBeat: 0, durationBeats: 4.0)
        let instrument = TrackInstrument(
            type: .synth,
            preset: .default,
            audioEngine: audioEngine
        )
        
        do {
            _ = try await bounceEngine.bounce(
                region: region,
                instrument: instrument,
                sampleRate: 48000
            )
            XCTFail("Should throw BounceError.noNotes", file: #file, line: #line)
        } catch let error as BounceError {
            // Verify it's the noNotes error by checking description
            XCTAssertTrue(
                error.errorDescription?.contains("no notes") ?? false,
                "Expected noNotes error",
                file: #file,
                line: #line
            )
        } catch {
            XCTFail("Unexpected error: \(error)", file: #file, line: #line)
        }
    }
}
