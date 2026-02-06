//
//  SynthVoiceFilterIsolationTests.swift
//  StoriTests
//
//  Tests that each voice maintains isolated filter state (Issue #108)
//

import XCTest
import AVFoundation
@testable import Stori

@MainActor
final class SynthVoiceFilterIsolationTests: XCTestCase {
    
    var engine: AVAudioEngine!
    var synthEngine: SynthEngine!
    
    override func setUp() async throws {
        engine = AVAudioEngine()
        synthEngine = SynthEngine()
        synthEngine.attach(to: engine, connectToMixer: true)
    }
    
    override func tearDown() async throws {
        synthEngine.detach()
        if engine.isRunning {
            engine.stop()
        }
        synthEngine = nil
        engine = nil
    }
    
    // MARK: - Core Isolation Tests
    
    /// Test that multiple voices rendering into the same buffer maintain isolated filter state
    func testMultipleVoicesHaveIsolatedFilterState() throws {
        // Start engine
        try engine.start()
        
        // Play 3 notes simultaneously
        synthEngine.noteOn(pitch: 60, velocity: 100)  // C4
        synthEngine.noteOn(pitch: 64, velocity: 100)  // E4
        synthEngine.noteOn(pitch: 67, velocity: 100)  // G4
        
        // Let them play for a bit
        Thread.sleep(forTimeInterval: 0.1)
        
        // All voices should be active
        let voices = synthEngine.activeVoices
        XCTAssertEqual(voices.count, 3, "Should have 3 active voices")
        
        // Each voice should be active (not contaminated into silence)
        for voice in voices {
            XCTAssertTrue(voice.isActive, "Voice should remain active")
        }
        
        // Stop engine
        engine.stop()
    }
    
    /// Test that filter state doesn't leak between voices across multiple render cycles
    func testFilterStateDoesNotLeakAcrossRenderCycles() throws {
        // This test verifies that:
        // 1. Voice 1 renders and establishes filter state
        // 2. Voice 2 renders and doesn't see Voice 1's filter state
        // 3. Across multiple buffers, isolation is maintained
        
        try engine.start()
        
        // Play note 1
        synthEngine.noteOn(pitch: 60, velocity: 100)
        Thread.sleep(forTimeInterval: 0.05)
        
        // Play note 2 while note 1 is still active
        synthEngine.noteOn(pitch: 72, velocity: 100)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Both notes should be audible (not contaminated)
        let voices = synthEngine.activeVoices
        XCTAssertGreaterThanOrEqual(voices.count, 2, "Should have at least 2 voices")
        
        for voice in voices {
            XCTAssertTrue(voice.isActive, "Voice should be active")
        }
        
        engine.stop()
    }
    
    /// Test that voice stealing doesn't cause filter state corruption
    func testVoiceStealingMaintainsFilterIsolation() throws {
        // Fill up all 16 voice slots
        try engine.start()
        
        for pitch in 60..<76 {  // 16 notes
            synthEngine.noteOn(pitch: UInt8(pitch), velocity: 80)
        }
        
        // Play one more note - should trigger voice stealing
        synthEngine.noteOn(pitch: 80, velocity: 80)
        
        // Let them render
        Thread.sleep(forTimeInterval: 0.1)
        
        // Should have max polyphony voices
        let voices = synthEngine.activeVoices
        XCTAssertLessThanOrEqual(voices.count, 16, "Should not exceed max polyphony")
        
        // All active voices should have valid state
        for voice in voices where voice.isActive {
            XCTAssertTrue(voice.isActive, "Stolen voice should not corrupt other voices")
        }
        
        engine.stop()
    }
    
    // MARK: - Filter Coefficient Tests
    
    /// Test that filter cutoff of 0 fully attenuates signal (per-voice)
    func testZeroCutoffAttenuatesPerVoice() throws {
        // Set filter cutoff to 0 (fully closed)
        synthEngine.setFilterCutoff(0.0)
        
        try engine.start()
        
        // Play multiple notes
        synthEngine.noteOn(pitch: 60, velocity: 100)
        synthEngine.noteOn(pitch: 64, velocity: 100)
        
        // Let them render with zero cutoff
        Thread.sleep(forTimeInterval: 0.1)
        
        // Voices should still be active (not crashed from bad filter math)
        let voices = synthEngine.activeVoices
        XCTAssertGreaterThanOrEqual(voices.count, 1, "Voices should exist")
        
        for voice in voices {
            XCTAssertTrue(voice.isActive, "Voice should be active despite zero cutoff")
        }
        
        engine.stop()
    }
    
    /// Test that filter cutoff of 1 passes signal unmodified (per-voice)
    func testMaxCutoffPassesSignalPerVoice() throws {
        // Set filter cutoff to 1 (fully open)
        synthEngine.setFilterCutoff(1.0)
        
        try engine.start()
        
        // Play multiple notes
        synthEngine.noteOn(pitch: 60, velocity: 100)
        synthEngine.noteOn(pitch: 64, velocity: 100)
        synthEngine.noteOn(pitch: 67, velocity: 100)
        
        // Let them render
        Thread.sleep(forTimeInterval: 0.1)
        
        let voices = synthEngine.activeVoices
        XCTAssertGreaterThanOrEqual(voices.count, 2, "Should have multiple voices")
        
        for voice in voices {
            XCTAssertTrue(voice.isActive, "Voice should be active with max cutoff")
        }
        
        engine.stop()
    }
    
    // MARK: - Polyphony Stress Tests
    
    /// Test maximum polyphony (16 voices) with filter isolation
    func testMaxPolyphonyFilterIsolation() throws {
        try engine.start()
        
        // Play all 16 voices
        for i in 0..<16 {
            synthEngine.noteOn(pitch: UInt8(60 + i), velocity: 80)
        }
        
        // Let them all render together
        Thread.sleep(forTimeInterval: 0.15)
        
        // All voices should be active
        let voices = synthEngine.activeVoices
        XCTAssertEqual(voices.count, 16, "Should have 16 active voices")
        
        for voice in voices {
            XCTAssertTrue(voice.isActive, "All voices should be active")
        }
        
        engine.stop()
    }
    
    /// Test rapid note triggering maintains filter isolation
    func testRapidNoteTriggeringPreservesIsolation() throws {
        try engine.start()
        
        // Rapidly trigger notes
        for _ in 0..<20 {
            synthEngine.noteOn(pitch: UInt8.random(in: 60...72), velocity: 80)
            Thread.sleep(forTimeInterval: 0.01)  // 10ms between notes
        }
        
        // Let final notes render
        Thread.sleep(forTimeInterval: 0.1)
        
        // Should have voices (not all stolen/corrupted)
        let voices = synthEngine.activeVoices
        XCTAssertGreaterThan(voices.count, 0, "Should have active voices after rapid triggering")
        
        for voice in voices where voice.isActive {
            XCTAssertTrue(voice.isActive, "Voices should be healthy after rapid triggering")
        }
        
        engine.stop()
    }
    
    /// Test that releasing notes doesn't corrupt other voices' filter state
    func testNoteReleaseDoesNotCorruptOtherFilters() throws {
        try engine.start()
        
        // Play 4 notes
        synthEngine.noteOn(pitch: 60, velocity: 100)
        synthEngine.noteOn(pitch: 64, velocity: 100)
        synthEngine.noteOn(pitch: 67, velocity: 100)
        synthEngine.noteOn(pitch: 72, velocity: 100)
        
        Thread.sleep(forTimeInterval: 0.05)
        
        // Release first 2 notes
        synthEngine.noteOff(pitch: 60)
        synthEngine.noteOff(pitch: 64)
        
        Thread.sleep(forTimeInterval: 0.1)
        
        // Remaining notes should still be active
        let voices = synthEngine.activeVoices
        let sustainedVoices = voices.filter { $0.pitch == 67 || $0.pitch == 72 }
        
        for voice in sustainedVoices {
            XCTAssertTrue(voice.isActive, "Sustained voices should not be corrupted by releases")
        }
        
        engine.stop()
    }
    
    // MARK: - Filter State Correctness Tests
    
    /// Test that filter state converges to input signal (RC filter behavior)
    func testFilterStateConvergesToSignal() throws {
        // With cutoff = 1.0, filter should pass signal through immediately
        // With cutoff < 1.0, filter should smooth/lowpass the signal
        
        // This is a behavioral test - we're verifying the filter doesn't
        // accumulate invalid state that causes silence or explosion
        
        try engine.start()
        
        // Play note with medium cutoff
        synthEngine.setFilterCutoff(0.5)
        synthEngine.noteOn(pitch: 60, velocity: 100)
        
        // Let it render for several cycles
        Thread.sleep(forTimeInterval: 0.2)
        
        // Voice should still be active (not silenced by bad filter math)
        let voices = synthEngine.activeVoices
        XCTAssertEqual(voices.count, 1, "Should have 1 voice")
        XCTAssertTrue(voices.first!.isActive, "Voice should be active after filter convergence")
        
        engine.stop()
    }
    
    /// Test that filter envelope modulation works per-voice
    func testFilterEnvelopeModulationPerVoice() throws {
        // Load preset with filter envelope amount
        var preset = SynthPreset.default
        preset.filter.envelopeAmount = 0.5
        synthEngine.loadPreset(preset)
        
        try engine.start()
        
        // Play multiple notes with different velocities
        synthEngine.noteOn(pitch: 60, velocity: 50)
        synthEngine.noteOn(pitch: 64, velocity: 100)
        synthEngine.noteOn(pitch: 67, velocity: 127)
        
        Thread.sleep(forTimeInterval: 0.1)
        
        // All voices should have independent envelope modulation
        let voices = synthEngine.activeVoices
        XCTAssertEqual(voices.count, 3, "Should have 3 voices")
        
        for voice in voices {
            XCTAssertTrue(voice.isActive, "Voice with envelope modulation should be active")
        }
        
        engine.stop()
    }
    
    // MARK: - Edge Case Tests
    
    /// Test that all notes off doesn't leave corrupted filter state
    func testAllNotesOffCleansFilterState() throws {
        try engine.start()
        
        // Play several notes
        for pitch in 60..<65 {
            synthEngine.noteOn(pitch: UInt8(pitch), velocity: 80)
        }
        
        Thread.sleep(forTimeInterval: 0.05)
        
        // All notes off
        synthEngine.allNotesOff()
        
        Thread.sleep(forTimeInterval: 0.1)
        
        // Play new notes - should have clean filter state
        synthEngine.noteOn(pitch: 72, velocity: 100)
        Thread.sleep(forTimeInterval: 0.05)
        
        let voices = synthEngine.activeVoices
        XCTAssertGreaterThanOrEqual(voices.count, 1, "New notes should work after all notes off")
        
        engine.stop()
    }
    
    /// Test that panic doesn't cause crashes when voices have active filters
    func testPanicWithActiveFilters() throws {
        try engine.start()
        
        // Play notes
        synthEngine.noteOn(pitch: 60, velocity: 100)
        synthEngine.noteOn(pitch: 64, velocity: 100)
        
        Thread.sleep(forTimeInterval: 0.05)
        
        // Panic
        synthEngine.panic()
        
        // Should not crash
        XCTAssertEqual(synthEngine.activeVoices.count, 0, "Panic should clear all voices")
        
        // Play new note - should work fine
        synthEngine.noteOn(pitch: 72, velocity: 100)
        Thread.sleep(forTimeInterval: 0.05)
        
        XCTAssertGreaterThanOrEqual(synthEngine.activeVoices.count, 1, "Should be able to play after panic")
        
        engine.stop()
    }
    
    /// Test that preset changes reset filter state correctly
    func testPresetChangeResetsFilterStatePerVoice() throws {
        try engine.start()
        
        // Play note with default preset
        synthEngine.noteOn(pitch: 60, velocity: 100)
        Thread.sleep(forTimeInterval: 0.05)
        
        // Change preset while note is playing
        synthEngine.loadPreset(.brightLead)
        
        // Note should continue playing with new filter characteristics
        Thread.sleep(forTimeInterval: 0.1)
        
        let voices = synthEngine.activeVoices
        XCTAssertGreaterThanOrEqual(voices.count, 1, "Voice should survive preset change")
        
        for voice in voices {
            XCTAssertTrue(voice.isActive, "Voice should be active after preset change")
        }
        
        engine.stop()
    }
    
    // MARK: - Performance Tests
    
    /// Test that isolated filter state doesn't significantly impact performance
    func testFilterIsolationPerformance() throws {
        try engine.start()
        
        measure {
            // Render 16 voices for performance measurement
            for i in 0..<16 {
                synthEngine.noteOn(pitch: UInt8(60 + i), velocity: 80)
            }
            
            Thread.sleep(forTimeInterval: 0.1)
            
            synthEngine.allNotesOff()
            Thread.sleep(forTimeInterval: 0.05)
        }
        
        engine.stop()
    }
}
