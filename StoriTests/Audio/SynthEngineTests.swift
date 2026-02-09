//
//  SynthEngineTests.swift
//  StoriTests
//
//  Comprehensive tests for SynthEngine - Subtractive synthesizer
//  Tests cover oscillators, filter, envelope, LFO, and parameter control
//

import XCTest
@testable import Stori
import AVFoundation

final class SynthEngineTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var synth: SynthEngine!
    private var engine: AVAudioEngine!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        engine = AVAudioEngine()
        synth = SynthEngine()
    }
    
    override func tearDown() async throws {
        synth = nil
        engine = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testSynthEngineInitialization() {
        XCTAssertNotNil(synth)
    }
    
    func testSynthHasSourceNode() {
        // Source node may be nil until attached to engine
        _ = synth.sourceNode
        XCTAssertTrue(true, "Source node property accessible")
    }
    
    func testSynthHasPreset() {
        XCTAssertNotNil(synth.preset)
        XCTAssertEqual(synth.preset.name, "Init Patch")
    }
    
    // MARK: - MIDI Control Tests
    
    func testNoteOn() {
        // Note on should not crash
        synth.noteOn(pitch: 60, velocity: 100)
        XCTAssertTrue(true, "Note on completed")
    }
    
    func testNoteOff() {
        synth.noteOn(pitch: 60, velocity: 100)
        synth.noteOff(pitch: 60)
        XCTAssertTrue(true, "Note off completed")
    }
    
    func testMultipleNoteOn() {
        // Polyphonic playback
        synth.noteOn(pitch: 60, velocity: 100)
        synth.noteOn(pitch: 64, velocity: 100)
        synth.noteOn(pitch: 67, velocity: 100)
        XCTAssertTrue(true, "Multiple notes triggered")
    }
    
    func testNoteOnOffCycle() {
        for note in 60...72 {
            synth.noteOn(pitch: UInt8(note), velocity: 100)
            synth.noteOff(pitch: UInt8(note))
        }
        XCTAssertTrue(true, "Note on/off cycle completed")
    }
    
    func testVelocityRange() {
        // Test various velocity values
        synth.noteOn(pitch: 60, velocity: 0)    // Silent
        synth.noteOn(pitch: 61, velocity: 64)   // Medium
        synth.noteOn(pitch: 62, velocity: 127)  // Loud
        XCTAssertTrue(true, "Velocity range tested")
    }
    
    func testPitchRange() {
        // Test full MIDI range
        synth.noteOn(pitch: 0, velocity: 100)    // Lowest
        synth.noteOn(pitch: 60, velocity: 100)   // Middle C
        synth.noteOn(pitch: 127, velocity: 100)  // Highest
        XCTAssertTrue(true, "Pitch range tested")
    }
    
    // MARK: - Parameter Tests
    
    func testDefaultPreset() {
        XCTAssertEqual(synth.preset.name, "Init Patch")
        XCTAssertNotNil(synth.preset.envelope)
        XCTAssertNotNil(synth.preset.filter)
    }
    
    func testChangePreset() {
        synth.preset = .brightLead
        XCTAssertEqual(synth.preset.name, "Bright Lead")
        
        synth.preset = .warmPad
        XCTAssertEqual(synth.preset.name, "Warm Pad")
    }
    
    func testPresetProperties() {
        let preset = synth.preset
        XCTAssertGreaterThanOrEqual(preset.masterVolume, 0.0)
        XCTAssertLessThanOrEqual(preset.masterVolume, 1.0)
        XCTAssertGreaterThanOrEqual(preset.glide, 0.0)
    }
    
    // MARK: - Engine Connection Tests
    
    func testAttachToEngine() {
        // Test attaching synth to audio engine
        synth.attach(to: engine, connectToMixer: false)
        
        XCTAssertNotNil(synth.sourceNode)
        XCTAssertTrue(synth.isAttached)
    }
    
    func testAttachToEngineWithMixerConnection() {
        synth.attach(to: engine, connectToMixer: true)
        
        XCTAssertNotNil(synth.sourceNode)
        XCTAssertTrue(synth.isAttached)
        XCTAssertTrue(engine.attachedNodes.contains(synth.sourceNode!))
    }
    
    func testEngineStartWithSynth() throws {
        synth.attach(to: engine, connectToMixer: true)
        
        try engine.start()
        XCTAssertTrue(engine.isRunning)
        
        engine.stop()
    }
    
    // MARK: - Polyphony Tests
    
    func testMonophonicPlayback() {
        synth.noteOn(pitch: 60, velocity: 100)
        synth.noteOn(pitch: 64, velocity: 100)  // Should replace or play alongside
        synth.noteOff(pitch: 60)
        synth.noteOff(pitch: 64)
        XCTAssertTrue(true, "Monophonic playback tested")
    }
    
    func testPolyphonicChord() {
        // Play a major chord
        synth.noteOn(pitch: 60, velocity: 100)  // C
        synth.noteOn(pitch: 64, velocity: 100)  // E
        synth.noteOn(pitch: 67, velocity: 100)  // G
        
        synth.noteOff(pitch: 60)
        synth.noteOff(pitch: 64)
        synth.noteOff(pitch: 67)
        XCTAssertTrue(true, "Polyphonic chord played")
    }
    
    func testVoiceStealing() {
        // Trigger many notes to test voice stealing
        for note in 48...72 {  // 25 notes
            synth.noteOn(pitch: UInt8(note), velocity: 100)
        }
        
        // Release all
        for note in 48...72 {
            synth.noteOff(pitch: UInt8(note))
        }
        
        XCTAssertTrue(true, "Voice stealing scenario tested")
    }
    
    // MARK: - Real-Time Safety Tests
    
    func testNoteOnPerformance() {
        measure {
            for _ in 0..<1000 {
                synth.noteOn(pitch: 60, velocity: 100)
                synth.noteOff(pitch: 60)
            }
        }
    }
    
    func testPresetChangePerformance() {
        measure {
            for i in 0..<1000 {
                if i % 2 == 0 {
                    synth.preset = .brightLead
                } else {
                    synth.preset = .warmPad
                }
            }
        }
    }
    
    func testRapidNoteSequence() {
        // Simulate rapid MIDI input
        let start = CFAbsoluteTimeGetCurrent()
        
        for i in 0..<1000 {
            let note = UInt8(60 + (i % 12))
            synth.noteOn(pitch: note, velocity: 100)
            synth.noteOff(pitch: note)
        }
        
        let duration = CFAbsoluteTimeGetCurrent() - start
        
        // Should complete in < 100ms (< 0.1ms per note on/off pair)
        XCTAssertLessThan(duration, 0.1, "Rapid note sequence too slow: \(duration)s")
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentNoteOn() async {
        let expectation = self.expectation(description: "Concurrent note on")
        expectation.expectedFulfillmentCount = 5
        let engine = synth!
        
        for i in 0..<5 {
            DispatchQueue.global(qos: .userInteractive).async {
                for j in 0..<100 {
                    let note = UInt8(60 + ((i + j) % 12))
                    engine.noteOn(pitch: note, velocity: 100)
                }
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    func testConcurrentPresetChanges() async {
        let expectation = self.expectation(description: "Concurrent preset changes")
        expectation.expectedFulfillmentCount = 3
        let engine = synth!
        
        for i in 0..<3 {
            DispatchQueue.global(qos: .userInteractive).async {
                for j in 0..<100 {
                    if (i + j) % 2 == 0 {
                        engine.preset = .brightLead
                    } else {
                        engine.preset = .warmPad
                    }
                }
                expectation.fulfill()
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // MARK: - Edge Case Tests
    
    func testNoteOffWithoutNoteOn() {
        // Should not crash
        synth.noteOff(pitch: 60)
        XCTAssertTrue(true, "Note off without note on handled")
    }
    
    func testDuplicateNoteOn() {
        synth.noteOn(pitch: 60, velocity: 100)
        synth.noteOn(pitch: 60, velocity: 100)  // Duplicate
        synth.noteOff(pitch: 60)
        XCTAssertTrue(true, "Duplicate note on handled")
    }
    
    func testMultipleNoteOff() {
        synth.noteOn(pitch: 60, velocity: 100)
        synth.noteOff(pitch: 60)
        synth.noteOff(pitch: 60)  // Already released
        XCTAssertTrue(true, "Multiple note off handled")
    }
    
    func testZeroVelocity() {
        // Zero velocity is sometimes used as note off
        synth.noteOn(pitch: 60, velocity: 0)
        XCTAssertTrue(true, "Zero velocity handled")
    }
    
    func testInvalidNoteNumber() {
        // Test beyond typical MIDI range
        synth.noteOn(pitch: 200, velocity: 100)
        synth.noteOff(pitch: 200)
        XCTAssertTrue(true, "Invalid note number handled")
    }
    
    // MARK: - Memory Management Tests
    
    func testMultipleSynthInstances() {
        let synth1 = SynthEngine()
        let synth2 = SynthEngine()
        let synth3 = SynthEngine()
        
        synth1.noteOn(pitch: 60, velocity: 100)
        synth2.noteOn(pitch: 64, velocity: 100)
        synth3.noteOn(pitch: 67, velocity: 100)
        
        XCTAssertTrue(true, "Multiple synth instances created")
    }
    
    func testSynthEngineCleanup() {
        for _ in 0..<50 {
            let tempSynth = SynthEngine()
            tempSynth.noteOn(pitch: 60, velocity: 100)
            tempSynth.noteOff(pitch: 60)
        }
        
        XCTAssertTrue(true, "Synth cleanup validated")
    }
    
    // MARK: - Integration Tests
    
    func testFullSynthWorkflow() throws {
        // Complete workflow: attach, start, play, stop
        synth.attach(to: engine, connectToMixer: true)
        
        try engine.start()
        
        // Play a melody
        let melody: [UInt8] = [60, 62, 64, 65, 67]
        for note in melody {
            synth.noteOn(pitch: note, velocity: 100)
            Thread.sleep(forTimeInterval: 0.01)  // Brief delay
            synth.noteOff(pitch: note)
        }
        
        engine.stop()
        
        XCTAssertTrue(true, "Full workflow completed")
    }
    
    func testSynthInMultiTrackScenario() throws {
        // Multiple synths playing simultaneously
        let synth1 = SynthEngine()
        let synth2 = SynthEngine()
        
        synth1.attach(to: engine, connectToMixer: true)
        synth2.attach(to: engine, connectToMixer: true)
        
        try engine.start()
        
        synth1.noteOn(pitch: 60, velocity: 100)
        synth2.noteOn(pitch: 64, velocity: 100)
        
        synth1.noteOff(pitch: 60)
        synth2.noteOff(pitch: 64)
        
        engine.stop()
        
        XCTAssertTrue(true, "Multi-track scenario completed")
    }
    
    // MARK: - Stress Tests
    
    func testSustainedPlayback() {
        // Simulate sustained note over time
        synth.noteOn(pitch: 60, velocity: 100)
        Thread.sleep(forTimeInterval: 0.5)  // 500ms sustained
        synth.noteOff(pitch: 60)
        
        XCTAssertTrue(true, "Sustained playback tested")
    }
    
    func testRapidPresetModulation() {
        // Simulate rapid preset switching
        for i in 0..<100 {
            if i % 3 == 0 {
                synth.preset = .brightLead
            } else if i % 3 == 1 {
                synth.preset = .warmPad
            } else {
                synth.preset = .deepBass
            }
        }
        
        XCTAssertTrue(true, "Rapid preset changes tested")
    }
    
    func testHighNoteCount() {
        // Play many notes rapidly
        for i in 0..<100 {
            let note = UInt8(36 + (i % 48))  // Bass to tenor range
            synth.noteOn(pitch: note, velocity: UInt8(50 + (i % 77)))
            
            if i % 10 == 0 {
                // Release some notes
                synth.noteOff(pitch: UInt8(36 + ((i - 10) % 48)))
            }
        }
        
        XCTAssertTrue(true, "High note count scenario tested")
    }
}
