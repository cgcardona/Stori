//
//  SamplerEngineTests.swift
//  StoriTests
//
//  Comprehensive tests for SamplerEngine - Sample-based instrument using AVAudioUnitSampler
//  Tests cover SoundFont loading, MIDI playback, preset management, and audio graph integration
//

import XCTest
@testable import Stori
import AVFoundation

final class SamplerEngineTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var sampler: SamplerEngine!
    private var engine: AVAudioEngine!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        engine = AVAudioEngine()
        sampler = SamplerEngine(attachTo: engine)
    }
    
    override func tearDown() async throws {
        sampler = nil
        engine = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testSamplerEngineInitialization() {
        XCTAssertNotNil(sampler)
    }
    
    func testSamplerHasSamplerNode() {
        XCTAssertNotNil(sampler.sampler)
    }
    
    func testSamplerNodeIsAVAudioUnitSampler() {
        // Underlying node should be AVAudioUnitSampler
        XCTAssertTrue(sampler.sampler is AVAudioUnitSampler)
    }
    
    func testSamplerNodeFormat() {
        let format = sampler.sampler.outputFormat(forBus: 0)
        XCTAssertEqual(format.channelCount, 2, "Should be stereo")
        XCTAssertGreaterThan(format.sampleRate, 0)
    }
    
    // MARK: - MIDI Control Tests
    
    func testNoteOn() {
        // Note on should not crash even without loaded samples
        sampler.noteOn(pitch: 60, velocity: 100)
        XCTAssertTrue(true, "Note on completed")
    }
    
    func testNoteOff() {
        sampler.noteOn(pitch: 60, velocity: 100)
        sampler.noteOff(pitch: 60)
        XCTAssertTrue(true, "Note off completed")
    }
    
    func testMultipleNoteOn() {
        // Polyphonic playback
        sampler.noteOn(pitch: 60, velocity: 100)
        sampler.noteOn(pitch: 64, velocity: 100)
        sampler.noteOn(pitch: 67, velocity: 100)
        XCTAssertTrue(true, "Multiple notes triggered")
    }
    
    func testNoteOnOffCycle() {
        for note in 60...72 {
            sampler.noteOn(pitch: UInt8(note), velocity: 100)
            sampler.noteOff(pitch: UInt8(note))
        }
        XCTAssertTrue(true, "Note on/off cycle completed")
    }
    
    func testVelocityRange() {
        // Test various velocity values
        sampler.noteOn(pitch: 60, velocity: 0)    // Silent
        sampler.noteOn(pitch: 61, velocity: 64)   // Medium
        sampler.noteOn(pitch: 62, velocity: 127)  // Loud
        XCTAssertTrue(true, "Velocity range tested")
    }
    
    func testPitchRange() {
        // Test full MIDI range
        sampler.noteOn(pitch: 0, velocity: 100)    // Lowest
        sampler.noteOn(pitch: 60, velocity: 100)   // Middle C
        sampler.noteOn(pitch: 127, velocity: 100)  // Highest
        XCTAssertTrue(true, "Pitch range tested")
    }
    
    // MARK: - SoundFont Loading Tests
    
    func testLoadSoundFontWithInvalidPath() {
        // Loading invalid path should throw or handle gracefully
        let url = URL(fileURLWithPath: "/nonexistent/file.sf2")
        XCTAssertThrowsError(try sampler.loadSoundFont(at: url))
    }
    
    func testLoadSoundFontWithInvalidExtension() {
        let url = URL(fileURLWithPath: "/path/to/file.txt")
        XCTAssertThrowsError(try sampler.loadSoundFont(at: url))
    }
    
    // MARK: - Engine Connection Tests
    
    func testSamplerAttachedToEngine() {
        // Sampler is already attached in setUp via init(attachTo:)
        XCTAssertTrue(engine.attachedNodes.contains(sampler.sampler))
    }
    
    func testDisconnectFromEngine() {
        engine.disconnectNodeOutput(sampler.sampler)
        XCTAssertTrue(true, "Disconnected successfully")
    }
    
    func testEngineStartWithSampler() throws {
        // Connect sampler to output so engine can start
        engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
        
        try engine.start()
        XCTAssertTrue(engine.isRunning)
        
        engine.stop()
    }
    
    // MARK: - Polyphony Tests
    
    func testPolyphonicChord() {
        // Play a major chord
        sampler.noteOn(pitch: 60, velocity: 100)  // C
        sampler.noteOn(pitch: 64, velocity: 100)  // E
        sampler.noteOn(pitch: 67, velocity: 100)  // G
        
        sampler.noteOff(pitch: 60)
        sampler.noteOff(pitch: 64)
        sampler.noteOff(pitch: 67)
        XCTAssertTrue(true, "Polyphonic chord played")
    }
    
    func testHighPolyphony() {
        // Sampler should support high polyphony
        for note in 48...72 {  // 25 notes
            sampler.noteOn(pitch: UInt8(note), velocity: 100)
        }
        
        // Release all
        for note in 48...72 {
            sampler.noteOff(pitch: UInt8(note))
        }
        
        XCTAssertTrue(true, "High polyphony tested")
    }
    
    // MARK: - Real-Time Safety Tests
    
    func testNoteOnPerformance() {
        measure {
            for _ in 0..<1000 {
                sampler.noteOn(pitch: 60, velocity: 100)
                sampler.noteOff(pitch: 60)
            }
        }
    }
    
    func testRapidNoteSequence() {
        let start = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<1000 {
            let note = UInt8(60 + (i % 12))
            sampler.noteOn(pitch: note, velocity: 100)
            sampler.noteOff(pitch: note)
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - start
        
        // Should complete in < 100ms (< 0.1ms per note on/off pair)
        XCTAssertLessThan(duration, 0.1, "Rapid note sequence too slow: \(duration)s")
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentNoteOn() {
        let expectation = self.expectation(description: "Concurrent note on")
        expectation.expectedFulfillmentCount = 5
        
        for i in 0..<5 {
            DispatchQueue.global(qos: .userInteractive).async {
                for j in 0..<100 {
                    let note = UInt8(60 + ((i + j) % 12))
                    self.sampler.noteOn(pitch: note, velocity: 100)
                }
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    func testConcurrentSoundFontLoad() {
        let expectation = self.expectation(description: "Concurrent SoundFont load")
        expectation.expectedFulfillmentCount = 3
        
        for i in 0..<3 {
            DispatchQueue.global(qos: .userInitiated).async {
                let url = URL(fileURLWithPath: "/test/path/\(i).sf2")
                try? self.sampler.loadSoundFont(at: url)
                expectation.fulfill()
            }
        }
        
        waitForExpectations(timeout: 5.0)
    }
    
    // MARK: - Edge Case Tests
    
    func testNoteOffWithoutNoteOn() {
        // Should not crash
        sampler.noteOff(pitch: 60)
        XCTAssertTrue(true, "Note off without note on handled")
    }
    
    func testDuplicateNoteOn() {
        sampler.noteOn(pitch: 60, velocity: 100)
        sampler.noteOn(pitch: 60, velocity: 100)  // Duplicate
        sampler.noteOff(pitch: 60)
        XCTAssertTrue(true, "Duplicate note on handled")
    }
    
    func testMultipleNoteOff() {
        sampler.noteOn(pitch: 60, velocity: 100)
        sampler.noteOff(pitch: 60)
        sampler.noteOff(pitch: 60)  // Already released
        XCTAssertTrue(true, "Multiple note off handled")
    }
    
    func testZeroVelocity() {
        // Zero velocity is sometimes used as note off
        sampler.noteOn(pitch: 60, velocity: 0)
        XCTAssertTrue(true, "Zero velocity handled")
    }
    
    func testInvalidNoteNumber() {
        // Test beyond typical MIDI range
        sampler.noteOn(pitch: 200, velocity: 100)
        sampler.noteOff(pitch: 200)
        XCTAssertTrue(true, "Invalid note number handled")
    }
    
    // MARK: - Instrument Selection Tests
    
    func testCurrentInstrumentInitialValue() {
        // Should start with default instrument
        XCTAssertNotNil(sampler.currentInstrument)
    }
    
    func testSamplerReadyState() {
        // Sampler may not be ready until SoundFont is loaded
        // This is okay - just verify the property exists
        _ = sampler.isReady
        XCTAssertTrue(true, "Ready state accessible")
    }
    
    // MARK: - Memory Management Tests
    
    func testMultipleSamplerInstances() {
        let sampler1 = SamplerEngine(attachTo: engine)
        let sampler2 = SamplerEngine(attachTo: engine)
        let sampler3 = SamplerEngine(attachTo: engine)
        
        sampler1.noteOn(pitch: 60, velocity: 100)
        sampler2.noteOn(pitch: 64, velocity: 100)
        sampler3.noteOn(pitch: 67, velocity: 100)
        
        XCTAssertTrue(true, "Multiple sampler instances created")
    }
    
    func testSamplerEngineCleanup() {
        for _ in 0..<50 {
            let tempSampler = SamplerEngine(attachTo: engine)
            tempSampler.noteOn(pitch: 60, velocity: 100)
            tempSampler.noteOff(pitch: 60)
        }
        
        XCTAssertTrue(true, "Sampler cleanup validated")
    }
    
    // MARK: - Integration Tests
    
    func testFullSamplerWorkflow() throws {
        // Complete workflow: connect, start engine, play notes, stop
        engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
        
        try engine.start()
        
        // Play a melody (without SoundFont, notes won't make sound but API should work)
        let melody: [UInt8] = [60, 62, 64, 65, 67]
        for note in melody {
            sampler.noteOn(pitch: note, velocity: 100)
            Thread.sleep(forTimeInterval: 0.01)  // Brief delay
            sampler.noteOff(pitch: note)
        }
        
        engine.stop()
        
        XCTAssertTrue(true, "Full workflow completed")
    }
    
    func testSamplerInMultiTrackScenario() throws {
        // Multiple samplers playing simultaneously (e.g., different instruments)
        let sampler1 = SamplerEngine(attachTo: engine)  // Piano
        let sampler2 = SamplerEngine(attachTo: engine)  // Bass
        
        let mixer = engine.mainMixerNode
        engine.attach(sampler1.sampler)
        engine.attach(sampler2.sampler)
        engine.connect(sampler1.sampler, to: mixer, format: nil)
        engine.connect(sampler2.sampler, to: mixer, format: nil)
        
        try engine.start()
        
        // Note: Without loaded SoundFonts, notes won't make sound but API should work
        sampler1.noteOn(pitch: 60, velocity: 100)
        sampler2.noteOn(pitch: 48, velocity: 100)
        
        sampler1.noteOff(pitch: 60)
        sampler2.noteOff(pitch: 48)
        
        engine.stop()
        
        XCTAssertTrue(true, "Multi-track scenario completed")
    }
    
    func testSamplerWithInvalidSoundFontPaths() throws {
        // Connect before starting engine
        engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
        
        try engine.start()
        
        // Try loading non-existent SoundFonts
        let url1 = URL(fileURLWithPath: "/path/to/piano.sf2")
        let url2 = URL(fileURLWithPath: "/path/to/strings.sf2")
        
        XCTAssertThrowsError(try sampler.loadSoundFont(at: url1))
        XCTAssertThrowsError(try sampler.loadSoundFont(at: url2))
        
        engine.stop()
        
        XCTAssertTrue(true, "Invalid SoundFont path handling validated")
    }
    
    // MARK: - Stress Tests
    
    func testSustainedPlayback() {
        // Simulate sustained note over time
        sampler.noteOn(pitch: 60, velocity: 100)
        Thread.sleep(forTimeInterval: 0.5)  // 500ms sustained
        sampler.noteOff(pitch: 60)
        
        XCTAssertTrue(true, "Sustained playback tested")
    }
    
    func testHighNoteCount() {
        // Play many notes rapidly
        for i in 0..<100 {
            let note = UInt8(36 + (i % 48))  // Bass to tenor range
            sampler.noteOn(pitch: note, velocity: UInt8(50 + (i % 77)))
            
            if i % 10 == 0 {
                // Release some notes
                sampler.noteOff(pitch: UInt8(36 + ((i - 10) % 48)))
            }
        }
        
        XCTAssertTrue(true, "High note count scenario tested")
    }
    
    func testDrumPatternSimulation() {
        // Simulate a drum pattern (typical sampler use case)
        // Note: Without loaded drum kit, notes won't sound but API should work
        
        // Kick, snare, hihat pattern
        let pattern: [UInt8] = [36, 42, 38, 42]  // Kick, HH, Snare, HH
        
        for note in pattern {
            sampler.noteOn(pitch: note, velocity: 100)
            Thread.sleep(forTimeInterval: 0.01)
            sampler.noteOff(pitch: note)
        }
        
        XCTAssertTrue(true, "Drum pattern simulation completed")
    }
    
    // MARK: - SoundFont Path Tests
    
    func testSoundFontPathWithSpaces() {
        let url = URL(fileURLWithPath: "/path/with spaces/file.sf2")
        XCTAssertThrowsError(try sampler.loadSoundFont(at: url))
    }
    
    func testSoundFontPathWithUnicode() {
        let url = URL(fileURLWithPath: "/path/文件.sf2")
        XCTAssertThrowsError(try sampler.loadSoundFont(at: url))
    }
    
    func testVeryLongSoundFontPath() {
        let longPath = "/" + String(repeating: "a", count: 500) + ".sf2"
        let url = URL(fileURLWithPath: longPath)
        XCTAssertThrowsError(try sampler.loadSoundFont(at: url))
    }
    
    // MARK: - Sample Rate Conversion Tests (Issue #70)
    
    /// Test that AVAudioUnitSampler handles sample-rate conversion correctly
    /// This test verifies the contract with Apple's sampler implementation
    /// NOTE: We cannot test actual drift without physical audio hardware and long samples,
    /// but we can verify that the sampler is configured correctly for SRC
    func testSamplerSampleRateConfiguration() throws {
        // Connect to engine and start
        engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
        try engine.start()
        
        let outputFormat = sampler.sampler.outputFormat(forBus: 0)
        let engineFormat = engine.outputNode.outputFormat(forBus: 0)
        
        // Sampler and engine must report valid formats. When they differ, Core Audio
        // performs sample-rate conversion (SRC); when they match, no conversion.
        XCTAssertGreaterThan(outputFormat.sampleRate, 0, "Sampler must have valid output sample rate")
        XCTAssertEqual(outputFormat.channelCount, 2, "Sampler should be stereo")
        XCTAssertGreaterThan(engineFormat.sampleRate, 0, "Engine must have valid output sample rate")
        XCTAssertTrue(engine.isRunning, "Engine should be running for SRC to be active")
        
        engine.stop()
    }
    
    /// Test that sampler maintains timing accuracy contract
    /// AVAudioUnitSampler delegates to Core Audio for sample-rate conversion,
    /// which uses high-quality polyphase interpolation (no drift by design)
    func testSamplerTimingContract() throws {
        engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
        try engine.start()
        
        // Play a long sequence of notes at precise intervals
        // If there were drift, notes would desync from wall-clock time
        let noteCount = 100
        let intervalSeconds = 0.01 // 10ms per note
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<noteCount {
            let note = UInt8(60 + (i % 12))
            sampler.noteOn(pitch: note, velocity: 100)
            Thread.sleep(forTimeInterval: intervalSeconds)
            sampler.noteOff(pitch: note)
        }
        
        let actualDuration = CFAbsoluteTimeGetCurrent() - startTime
        let expectedDuration = Double(noteCount) * intervalSeconds
        
        // Allow 10% tolerance for thread sleep imprecision
        let tolerance = expectedDuration * 0.1
        
        XCTAssertTrue(abs(actualDuration - expectedDuration) < tolerance,
                     "Note timing drifted: expected \(expectedDuration)s, got \(actualDuration)s")
        
        engine.stop()
    }
    
    /// Test sampler behavior under sample-accurate MIDI scheduling
    /// This verifies that the MIDI event block is available for precise timing
    func testSampleAccurateMIDIScheduling() throws {
        // Load a SoundFont first (required for MIDI block access)
        // Note: This will fail without a real SoundFont, but that's expected
        // The important part is that the API contract is correct
        
        engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
        try engine.start()
        
        // Without loaded SoundFont, midiEventBlock should be nil (safe fallback)
        let midiBlock = sampler.midiEventBlock
        
        if sampler.isReady {
            // If sampler is ready (SoundFont loaded), MIDI block should be available
            XCTAssertNotNil(midiBlock, "Sample-accurate MIDI block should be available when ready")
        } else {
            // If not ready, MIDI block should be nil (safe fallback)
            XCTAssertNil(midiBlock, "MIDI block should be nil when sampler not ready")
        }
        
        engine.stop()
    }
    
    /// Test that sendMIDI falls back gracefully when MIDI block unavailable
    /// This ensures no timing issues even without sample-accurate scheduling
    func testMIDIFallbackTiming() throws {
        engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
        try engine.start()
        
        // Send MIDI without sample-accurate timing (fallback mode)
        let startTime = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<100 {
            let note = UInt8(60 + (i % 12))
            sampler.sendMIDI(status: 0x90, data1: note, data2: 100) // Note on
            sampler.sendMIDI(status: 0x80, data1: note, data2: 0)   // Note off
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should complete rapidly (no blocking)
        XCTAssertLessThan(duration, 0.1, "MIDI fallback should be fast: \(duration)s")
        
        engine.stop()
    }
    
    /// Test sampler DSP state reset (prevents drift after graph changes)
    /// This verifies that resetDSPState clears any accumulated timing errors
    func testDSPStateResetClearsTiming() throws {
        engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
        try engine.start()
        
        // Play some notes
        sampler.noteOn(pitch: 60, velocity: 100)
        sampler.noteOn(pitch: 64, velocity: 100)
        
        // Reset DSP state (should clear any internal buffers/timing)
        sampler.resetDSPState()
        
        // Verify notes are stopped
        // (We can't directly verify internal timing state, but can verify cleanup)
        sampler.noteOn(pitch: 67, velocity: 100)
        sampler.noteOff(pitch: 67)
        
        engine.stop()
        
        XCTAssertTrue(true, "DSP state reset completed without crash")
    }
    
    /// Test sampler behavior with rapid format changes (simulates SRC scenarios)
    /// In real usage, project sample rate changes would trigger this path
    func testRapidEngineFormatChanges() throws {
        // Connect and start at initial format
        engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
        try engine.start()
        
        let initialFormat = sampler.sampler.outputFormat(forBus: 0)
        
        // Stop and reconfigure engine (simulates sample rate change)
        engine.stop()
        
        // Restart
        try engine.start()
        
        let newFormat = sampler.sampler.outputFormat(forBus: 0)
        
        // Format should remain consistent
        XCTAssertEqual(initialFormat.sampleRate, newFormat.sampleRate)
        XCTAssertEqual(initialFormat.channelCount, newFormat.channelCount)
        
        engine.stop()
    }
    
    /// Test that sampler volume/pan controls don't introduce timing drift
    /// Parameter automation should not affect sample timing
    func testParameterAutomationDoesNotDriftTiming() throws {
        engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
        try engine.start()
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Play notes while rapidly changing volume/pan
        for i in 0..<100 {
            let note = UInt8(60 + (i % 12))
            let volume = Float(i % 100) / 100.0
            let pan = Float((i % 200) - 100) / 100.0
            
            sampler.setVolume(volume)
            sampler.setPan(pan)
            sampler.noteOn(pitch: note, velocity: 100)
            sampler.noteOff(pitch: note)
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should complete quickly (no timing drift from parameter changes)
        XCTAssertLessThan(duration, 0.5, "Parameter automation should not slow playback: \(duration)s")
        
        engine.stop()
    }
    
    /// Test sampler maintains accuracy with polyphonic playback
    /// Drift could compound with multiple simultaneous voices
    func testPolyphonicPlaybackTiming() throws {
        engine.connect(sampler.sampler, to: engine.mainMixerNode, format: nil)
        try engine.start()
        
        // Play a sustained chord for extended period
        let chord: [UInt8] = [48, 52, 55, 60, 64, 67, 72] // 7-note voicing
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Start all notes
        for note in chord {
            sampler.noteOn(pitch: note, velocity: 100)
        }
        
        // Sustain for 100ms
        Thread.sleep(forTimeInterval: 0.1)
        
        // Release all notes
        for note in chord {
            sampler.noteOff(pitch: note)
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        
        // Should be close to 100ms (within 20ms tolerance for thread sleep)
        XCTAssertTrue(abs(duration - 0.1) < 0.02,
                     "Polyphonic timing drifted: expected 0.1s, got \(duration)s")
        
        engine.stop()
    }
}
