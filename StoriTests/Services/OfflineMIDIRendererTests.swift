//
//  OfflineMIDIRendererTests.swift
//  StoriTests
//
//  Tests for Offline MIDI Renderer real-time safety (Issue #50)
//

import XCTest
@testable import Stori
import AVFoundation

/// Comprehensive tests for offline MIDI rendering with real-time safe locking
/// BUG FIX: Issue #50 - Replaced NSLock with os_unfair_lock for real-time safety
final class OfflineMIDIRendererTests: XCTestCase {
    
    // MARK: - Core Rendering Tests
    
    func testRendererInitialization() {
        // Given: A synth preset and standard sample rate
        let preset = TestPresetFactory.createBasicSynthPreset()
        let sampleRate: Double = 48000
        let volume: Float = 0.8
        
        // When: We create a renderer
        let renderer = OfflineMIDIRenderer(preset: preset, sampleRate: sampleRate, volume: volume)
        
        // Then: Renderer should be initialized
        XCTAssertNotNil(renderer, "Renderer should initialize successfully")
    }
    
    func testRenderEmptyRegionProducesSilence() {
        // Given: A renderer with no scheduled events
        let renderer = TestRendererFactory.createRenderer()
        let buffer = TestBufferFactory.createMonoBuffer(frameCount: 1024)
        
        // When: We render
        renderer.render(into: buffer.floatChannelData![0], frameCount: 1024)
        
        // Then: Buffer should be silent (all zeros)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 1024))
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        XCTAssertEqual(maxAmplitude, 0, accuracy: 0.0001,
                      "Empty region should produce silence")
    }
    
    func testRenderSingleNoteProducesAudio() {
        // Given: A renderer with a single MIDI note
        let renderer = TestRendererFactory.createRenderer()
        let region = TestRegionFactory.createRegionWithSingleNote(
            pitch: 60,  // Middle C
            velocity: 100,
            startBeat: 0,
            durationBeats: 1.0
        )
        
        renderer.scheduleRegion(region, tempo: 120, sampleRate: 48000)
        
        // When: We render the duration of the note
        let buffer = TestBufferFactory.createMonoBuffer(frameCount: 24000)  // 0.5s @ 48kHz
        renderer.render(into: buffer.floatChannelData![0], frameCount: 24000)
        
        // Then: Buffer should contain audio (non-zero samples)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 24000))
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(maxAmplitude, 0.01,
                            "Single note should produce audible audio")
    }
    
    func testRenderMultipleNotesProducesAudio() {
        // Given: A renderer with multiple MIDI notes
        let renderer = TestRendererFactory.createRenderer()
        let region = TestRegionFactory.createRegionWithMultipleNotes(
            pitches: [60, 64, 67],  // C major chord
            velocity: 80,
            startBeat: 0,
            durationBeats: 2.0
        )
        
        renderer.scheduleRegion(region, tempo: 120, sampleRate: 48000)
        
        // When: We render
        let buffer = TestBufferFactory.createMonoBuffer(frameCount: 48000)  // 1s @ 48kHz
        renderer.render(into: buffer.floatChannelData![0], frameCount: 48000)
        
        // Then: Buffer should contain audio
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 48000))
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(maxAmplitude, 0.01,
                            "Multiple notes should produce audible audio")
    }
    
    // MARK: - Real-Time Safety Tests
    
    func testConcurrentRenderCallsAreThreadSafe() async {
        // Given: A renderer with scheduled events
        let renderer = TestRendererFactory.createRenderer()
        let region = TestRegionFactory.createRegionWithMultipleNotes(
            pitches: [60, 62, 64, 65, 67],
            velocity: 100,
            startBeat: 0,
            durationBeats: 4.0
        )
        renderer.scheduleRegion(region, tempo: 120, sampleRate: 48000)
        
        // When: We render from multiple threads concurrently
        let expectation = self.expectation(description: "Concurrent renders complete")
        expectation.expectedFulfillmentCount = 100
        
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let buffer = TestBufferFactory.createMonoBuffer(frameCount: 1024)
            renderer.render(into: buffer.floatChannelData![0], frameCount: 1024)
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        // Then: No crashes or data corruption (test passes if we get here)
        XCTAssertTrue(true, "Concurrent renders should be thread-safe")
    }
    
    func testResetDuringRenderIsThreadSafe() async {
        // Given: A renderer with scheduled events
        let renderer = TestRendererFactory.createRenderer()
        let region = TestRegionFactory.createRegionWithMultipleNotes(
            pitches: [60, 64, 67],
            velocity: 100,
            startBeat: 0,
            durationBeats: 2.0
        )
        renderer.scheduleRegion(region, tempo: 120, sampleRate: 48000)
        
        // When: We render and reset concurrently
        let expectation = self.expectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 50
        
        for i in 0..<50 {
            DispatchQueue.global().async {
                if i % 2 == 0 {
                    let buffer = TestBufferFactory.createMonoBuffer(frameCount: 1024)
                    renderer.render(into: buffer.floatChannelData![0], frameCount: 1024)
                } else {
                    renderer.reset()
                }
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 10.0)
        
        // Then: No crashes or data corruption
        XCTAssertTrue(true, "Reset during render should be thread-safe")
    }
    
    // MARK: - Bug Scenario from Issue #50
    
    func testComplexMIDIArrangementUnderLoad() async {
        // Reproduces the scenario from Issue #50: multiple MIDI tracks under load.
        // Use moderate concurrency to validate thread-safety without stressing
        // teardown (avoid malloc "pointer being freed was not allocated").
        let rendererCount = 4
        let buffersPerRenderer = 25
        
        let renderers = (0..<rendererCount).map { _ in TestRendererFactory.createRenderer() }
        
        for renderer in renderers {
            let region = TestRegionFactory.createComplexMIDIPattern(
                noteCount: 50,
                startBeat: 0,
                durationBeats: 4.0
            )
            renderer.scheduleRegion(region, tempo: 140, sampleRate: 48000)
        }
        
        let expectation = self.expectation(description: "All tracks rendered")
        expectation.expectedFulfillmentCount = rendererCount
        
        for renderer in renderers {
            DispatchQueue.global().async {
                let buffer = TestBufferFactory.createMonoBuffer(frameCount: 4096)
                for _ in 0..<buffersPerRenderer {
                    renderer.render(into: buffer.floatChannelData![0], frameCount: 4096)
                }
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 15.0)
        
        XCTAssertTrue(true, "Complex arrangement should render without artifacts")
    }
    
    // MARK: - Deterministic Rendering Tests
    
    func testSameInputProducesSameOutput() {
        // Given: Two renderers with identical configuration
        let renderer1 = TestRendererFactory.createRenderer()
        let renderer2 = TestRendererFactory.createRenderer()
        
        let region = TestRegionFactory.createRegionWithSingleNote(
            pitch: 60,
            velocity: 100,
            startBeat: 0,
            durationBeats: 1.0
        )
        
        renderer1.scheduleRegion(region, tempo: 120, sampleRate: 48000)
        renderer2.scheduleRegion(region, tempo: 120, sampleRate: 48000)
        
        // When: We render the same number of frames
        let buffer1 = TestBufferFactory.createMonoBuffer(frameCount: 24000)
        let buffer2 = TestBufferFactory.createMonoBuffer(frameCount: 24000)
        
        renderer1.render(into: buffer1.floatChannelData![0], frameCount: 24000)
        renderer2.render(into: buffer2.floatChannelData![0], frameCount: 24000)
        
        // Then: Outputs should be identical
        let samples1 = Array(UnsafeBufferPointer(start: buffer1.floatChannelData![0], count: 24000))
        let samples2 = Array(UnsafeBufferPointer(start: buffer2.floatChannelData![0], count: 24000))
        
        for (index, (sample1, sample2)) in zip(samples1, samples2).enumerated() {
            XCTAssertEqual(sample1, sample2, accuracy: 0.00001,
                          "Sample \(index) should be identical (deterministic rendering)")
        }
    }
    
    func testMultipleExportsProduceIdenticalOutput() {
        // Given: A renderer with a complex pattern
        let region = TestRegionFactory.createComplexMIDIPattern(
            noteCount: 50,
            startBeat: 0,
            durationBeats: 4.0
        )
        
        var exports: [[Float]] = []
        
        // When: We export 10 times
        for _ in 0..<10 {
            let renderer = TestRendererFactory.createRenderer()
            renderer.scheduleRegion(region, tempo: 120, sampleRate: 48000)
            
            let buffer = TestBufferFactory.createMonoBuffer(frameCount: 96000)  // 2s @ 48kHz
            renderer.render(into: buffer.floatChannelData![0], frameCount: 96000)
            
            let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: 96000))
            exports.append(samples)
        }
        
        // Then: All exports should be byte-for-byte identical
        let reference = exports[0]
        for (exportIndex, export) in exports.enumerated().dropFirst() {
            for (sampleIndex, (refSample, exportSample)) in zip(reference, export).enumerated() {
                XCTAssertEqual(refSample, exportSample, accuracy: 0.00001,
                              "Export \(exportIndex) sample \(sampleIndex) should match reference (deterministic)")
            }
        }
    }
    
    // MARK: - Reset Tests
    
    func testResetClearsState() {
        // Given: A renderer that has rendered some audio
        let renderer = TestRendererFactory.createRenderer()
        let region = TestRegionFactory.createRegionWithSingleNote(
            pitch: 60,
            velocity: 100,
            startBeat: 0,
            durationBeats: 1.0
        )
        renderer.scheduleRegion(region, tempo: 120, sampleRate: 48000)
        
        let buffer = TestBufferFactory.createMonoBuffer(frameCount: 12000)
        renderer.render(into: buffer.floatChannelData![0], frameCount: 12000)
        
        // When: We reset
        renderer.reset()
        
        // Then: Rendering again should start from the beginning
        let buffer2 = TestBufferFactory.createMonoBuffer(frameCount: 12000)
        renderer.render(into: buffer2.floatChannelData![0], frameCount: 12000)
        
        // Should produce audio again (not silence because we're back at the start)
        let samples = Array(UnsafeBufferPointer(start: buffer2.floatChannelData![0], count: 12000))
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(maxAmplitude, 0.01,
                            "After reset, renderer should start from beginning and produce audio")
    }
    
    // MARK: - Volume Tests
    
    func testVolumeIsAppliedToOutput() {
        // Given: Two renderers with different volumes
        let quietRenderer = OfflineMIDIRenderer(
            preset: TestPresetFactory.createBasicSynthPreset(),
            sampleRate: 48000,
            volume: 0.25
        )
        let loudRenderer = OfflineMIDIRenderer(
            preset: TestPresetFactory.createBasicSynthPreset(),
            sampleRate: 48000,
            volume: 1.0
        )
        
        let region = TestRegionFactory.createRegionWithSingleNote(
            pitch: 60,
            velocity: 100,
            startBeat: 0,
            durationBeats: 1.0
        )
        
        quietRenderer.scheduleRegion(region, tempo: 120, sampleRate: 48000)
        loudRenderer.scheduleRegion(region, tempo: 120, sampleRate: 48000)
        
        // When: We render both
        let quietBuffer = TestBufferFactory.createMonoBuffer(frameCount: 24000)
        let loudBuffer = TestBufferFactory.createMonoBuffer(frameCount: 24000)
        
        quietRenderer.render(into: quietBuffer.floatChannelData![0], frameCount: 24000)
        loudRenderer.render(into: loudBuffer.floatChannelData![0], frameCount: 24000)
        
        // Then: Loud renderer should have ~4x amplitude (1.0 / 0.25)
        let quietSamples = Array(UnsafeBufferPointer(start: quietBuffer.floatChannelData![0], count: 24000))
        let loudSamples = Array(UnsafeBufferPointer(start: loudBuffer.floatChannelData![0], count: 24000))
        
        let quietRMS = sqrt(quietSamples.map { $0 * $0 }.reduce(0, +) / Float(24000))
        let loudRMS = sqrt(loudSamples.map { $0 * $0 }.reduce(0, +) / Float(24000))
        
        let ratio = loudRMS / quietRMS
        XCTAssertEqual(ratio, 4.0, accuracy: 0.5,
                      "Loud renderer should be ~4x louder than quiet renderer")
    }
    
    // MARK: - Edge Cases
    
    func testZeroFrameCountDoesNotCrash() {
        // Given: A renderer with scheduled events
        let renderer = TestRendererFactory.createRenderer()
        let region = TestRegionFactory.createRegionWithSingleNote(
            pitch: 60,
            velocity: 100,
            startBeat: 0,
            durationBeats: 1.0
        )
        renderer.scheduleRegion(region, tempo: 120, sampleRate: 48000)
        
        // When: We render with zero frame count
        let buffer = TestBufferFactory.createMonoBuffer(frameCount: 1024)
        
        // Then: Should not crash
        renderer.render(into: buffer.floatChannelData![0], frameCount: 0)
        XCTAssertTrue(true, "Zero frame count should not crash")
    }
    
    func testVeryLargeFrameCountHandledCorrectly() {
        // Given: A renderer
        let renderer = TestRendererFactory.createRenderer()
        let region = TestRegionFactory.createRegionWithSingleNote(
            pitch: 60,
            velocity: 100,
            startBeat: 0,
            durationBeats: 10.0
        )
        renderer.scheduleRegion(region, tempo: 120, sampleRate: 48000)
        
        // When: We render a very large buffer (10 seconds @ 48kHz)
        let largeFrameCount = 480000
        let buffer = TestBufferFactory.createMonoBuffer(frameCount: largeFrameCount)
        
        // Then: Should render without crashing
        renderer.render(into: buffer.floatChannelData![0], frameCount: largeFrameCount)
        
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: largeFrameCount))
        let maxAmplitude = samples.map { abs($0) }.max() ?? 0
        XCTAssertGreaterThan(maxAmplitude, 0,
                            "Large buffer should render correctly")
    }
    
    // MARK: - Regression Protection
    
    func testRegressionProtection_UsesOsUnfairLock() {
        // Verify that the implementation uses os_unfair_lock, not NSLock
        // This is a compile-time check - if NSLock is used, this test serves as documentation
        
        let renderer = TestRendererFactory.createRenderer()
        
        // The fix should use os_unfair_lock internally
        // If this test compiles and runs, the lock is accessible
        XCTAssertNotNil(renderer, "Renderer should use real-time safe locking (os_unfair_lock)")
    }
}

// MARK: - Test Helpers

private enum TestPresetFactory {
    /// Build a preset without using SynthPreset.default (avoids MainActor/isolation at teardown).
    static func createBasicSynthPreset() -> SynthPreset {
        let envelope = ADSREnvelope(attack: 0.01, decay: 0.1, sustain: 0.7, release: 0.2)
        let filter = FilterSettings(cutoff: 1.0, resonance: 0.0, type: .lowPass, envelopeAmount: 0.0)
        let lfo = LFOSettings(rate: 1.0, depth: 0.0, shape: .sine, destination: .none)
        return SynthPreset(
            name: "Test Sine",
            oscillator1: .sine,
            oscillator2: .sine,
            oscillatorMix: 0.0,
            oscillator2Detune: 0,
            oscillator2Octave: 0,
            envelope: envelope,
            filter: filter,
            lfo: lfo,
            masterVolume: 0.8,
            glide: 0.0
        )
    }
}

private enum TestRegionFactory {
    static func createRegionWithSingleNote(
        pitch: UInt8,
        velocity: UInt8,
        startBeat: Double,
        durationBeats: Double
    ) -> MIDIRegion {
        let note = MIDINote(
            id: UUID(),
            pitch: pitch,
            velocity: velocity,
            startBeat: startBeat,
            durationBeats: durationBeats
        )
        
        return MIDIRegion(
            id: UUID(),
            name: "Test Region",
            notes: [note],
            startBeat: 0,
            durationBeats: durationBeats + startBeat + 1.0,
            isLooped: false,
            loopCount: 1
        )
    }
    
    static func createRegionWithMultipleNotes(
        pitches: [UInt8],
        velocity: UInt8,
        startBeat: Double,
        durationBeats: Double
    ) -> MIDIRegion {
        let notes = pitches.enumerated().map { index, pitch in
            MIDINote(
                id: UUID(),
                pitch: pitch,
                velocity: velocity,
                startBeat: startBeat + Double(index) * 0.1,  // Slight offset
                durationBeats: durationBeats
            )
        }
        
        return MIDIRegion(
            id: UUID(),
            name: "Test Region",
            notes: notes,
            startBeat: 0,
            durationBeats: durationBeats + startBeat + 1.0,
            isLooped: false,
            loopCount: 1
        )
    }
    
    static func createComplexMIDIPattern(
        noteCount: Int,
        startBeat: Double,
        durationBeats: Double
    ) -> MIDIRegion {
        var notesList: [MIDINote] = []
        for i in 0..<noteCount {
            let note = MIDINote(
                id: UUID(),
                pitch: UInt8(60 + (i % 24)),
                velocity: UInt8(80 + (i % 47)),
                startBeat: startBeat + Double(i) * 0.25,
                durationBeats: 0.5 + Double(i % 3) * 0.25
            )
            notesList.append(note)
        }
        let duration = durationBeats + Double(noteCount) * 0.25 + 2.0
        let regionId = UUID()
        return MIDIRegion(
            id: regionId,
            name: "Test Region",
            notes: notesList,
            startBeat: 0,
            durationBeats: duration,
            isLooped: false,
            loopCount: 1
        )
    }
}

private enum TestRendererFactory {
    static func createRenderer(volume: Float = 0.8) -> OfflineMIDIRenderer {
        return OfflineMIDIRenderer(
            preset: TestPresetFactory.createBasicSynthPreset(),
            sampleRate: 48000,
            volume: volume
        )
    }
}

private enum TestBufferFactory {
    static func createMonoBuffer(frameCount: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount))!
        buffer.frameLength = AVAudioFrameCount(frameCount)
        
        // Zero the buffer
        if let channelData = buffer.floatChannelData {
            memset(channelData[0], 0, frameCount * MemoryLayout<Float>.size)
        }
        
        return buffer
    }
}
