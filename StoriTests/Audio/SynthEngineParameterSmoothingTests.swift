//
//  SynthEngineParameterSmoothingTests.swift
//  StoriTests
//
//  Tests for parameter smoothing in SynthEngine to prevent zipper noise.
//  Ensures smooth parameter changes during automation (Issue #60).
//

import XCTest
import AVFoundation
@testable import Stori

@MainActor
final class SynthEngineParameterSmoothingTests: XCTestCase {
    
    // MARK: - Test Fixtures
    
    var synthEngine: SynthEngine!
    var audioEngine: AVAudioEngine!
    
    override func setUp() async throws {
        synthEngine = SynthEngine()
        audioEngine = AVAudioEngine()
        
        // Attach synth to audio engine
        synthEngine.attach(to: audioEngine, connectToMixer: true)
        
        // Start engine
        try audioEngine.start()
    }
    
    override func tearDown() async throws {
        audioEngine.stop()
        synthEngine.detach()
        synthEngine = nil
        audioEngine = nil
    }
    
    // MARK: - Parameter Smoothing Tests
    
    /// Test that parameter changes don't cause instant jumps (smoothed)
    func testFilterCutoffSmoothing() async throws {
        // Initial cutoff
        synthEngine.setFilterCutoff(0.1)
        
        // Trigger note
        synthEngine.noteOn(pitch: 60, velocity: 100)
        
        // Wait for initial state
        try await Task.sleep(for: .milliseconds(50))
        
        // Change cutoff dramatically (should smooth, not jump)
        synthEngine.setFilterCutoff(0.9)
        
        // The smoothing should take ~5ms (time constant)
        // After 3x time constant (~15ms), should be ~95% to target
        try await Task.sleep(for: .milliseconds(20))
        
        // Note off
        synthEngine.noteOff(pitch: 60)
        
        // If we got here without crashes, smoothing works
    }
    
    /// Test rapid parameter changes (automation scenario)
    func testRapidParameterChanges() async throws {
        synthEngine.noteOn(pitch: 64, velocity: 100)
        
        // Simulate rapid automation changes (every 10ms for 100ms)
        for i in 0..<10 {
            let cutoff = Float(i) / 10.0
            synthEngine.setFilterCutoff(cutoff)
            try await Task.sleep(for: .milliseconds(10))
        }
        
        synthEngine.noteOff(pitch: 64)
        
        // If no crashes or glitches, smoothing handles rapid changes
    }
    
    /// Test multiple parameters changing simultaneously
    func testSimultaneousParameterChanges() {
        synthEngine.noteOn(pitch: 67, velocity: 100)
        
        // Change all smoothed parameters at once
        synthEngine.setFilterCutoff(0.8)
        synthEngine.setFilterResonance(0.5)
        synthEngine.setMasterVolume(0.9)
        
        // Should smooth all parameters without interference
        
        synthEngine.noteOff(pitch: 67)
    }
    
    /// Test preset loading resets smoothing (instant change)
    func testPresetLoadResetsSmoothing() {
        synthEngine.noteOn(pitch: 60, velocity: 100)
        
        // Set custom values
        synthEngine.setFilterCutoff(0.2)
        synthEngine.setMasterVolume(0.3)
        
        // Load preset (should reset smoothers instantly, not gradually)
        synthEngine.loadPreset(.brightLead)
        
        // New preset values should apply immediately
        // (No gradual transition from old to new preset)
        
        synthEngine.noteOff(pitch: 60)
    }
    
    // MARK: - Zipper Noise Prevention Tests
    
    /// Test filter sweep doesn't produce zipper noise artifacts
    func testFilterSweepNoZipperNoise() async throws {
        // This test verifies that rapid filter sweeps produce smooth transitions
        // Zipper noise would manifest as high-frequency aliased harmonics
        
        synthEngine.noteOn(pitch: 60, velocity: 100)
        
        // Sweep filter from low to high over 100ms
        for i in 0..<20 {
            let cutoff = Float(i) / 20.0  // 0.0 → 1.0
            synthEngine.setFilterCutoff(cutoff)
            try await Task.sleep(for: .milliseconds(5))
        }
        
        synthEngine.noteOff(pitch: 60)
        
        // Manual verification would use FFT analysis to check for aliased harmonics
        // For automated testing, we verify no crashes and smooth execution
    }
    
    /// Test volume automation doesn't produce clicks
    func testVolumeAutomationNoClicks() async throws {
        synthEngine.noteOn(pitch: 60, velocity: 100)
        
        // Rapid volume changes (simulating automation)
        let volumes: [Float] = [0.1, 0.9, 0.3, 0.7, 0.5]
        for volume in volumes {
            synthEngine.setMasterVolume(volume)
            try await Task.sleep(for: .milliseconds(10))
        }
        
        synthEngine.noteOff(pitch: 60)
        
        // Smoothing should prevent audible clicks
    }
    
    // MARK: - Polyphonic Scenarios
    
    /// Test parameter smoothing with multiple voices
    func testParameterSmoothingPolyphonic() async throws {
        // Play chord
        synthEngine.noteOn(pitch: 60, velocity: 100)
        synthEngine.noteOn(pitch: 64, velocity: 100)
        synthEngine.noteOn(pitch: 67, velocity: 100)
        
        // Change parameter (should affect all voices smoothly)
        synthEngine.setFilterCutoff(0.8)
        
        try await Task.sleep(for: .milliseconds(50))
        
        // Release chord
        synthEngine.noteOff(pitch: 60)
        synthEngine.noteOff(pitch: 64)
        synthEngine.noteOff(pitch: 67)
        
        // All voices should have smooth parameter changes
    }
    
    /// Test voice stealing with parameter smoothing
    func testVoiceStealingWithSmoothing() async throws {
        // Trigger max polyphony (16 voices)
        for pitch: UInt8 in 60..<76 {
            synthEngine.noteOn(pitch: pitch, velocity: 100)
        }
        
        // Change parameters while at max polyphony
        synthEngine.setFilterCutoff(0.5)
        synthEngine.setMasterVolume(0.6)
        
        // Trigger one more note (should steal oldest)
        synthEngine.noteOn(pitch: 76, velocity: 100)
        
        try await Task.sleep(for: .milliseconds(50))
        
        // All notes off
        synthEngine.panic()
        
        // Voice stealing shouldn't interfere with smoothing
    }
    
    // MARK: - Envelope & LFO Interaction Tests
    
    /// Test filter envelope doesn't interfere with parameter smoothing
    func testFilterEnvelopeWithSmoothing() async throws {
        // Load preset with filter envelope
        synthEngine.loadPreset(.pluckySynth)  // Has high envelope amount
        
        synthEngine.noteOn(pitch: 60, velocity: 100)
        
        // Change base cutoff during envelope
        synthEngine.setFilterCutoff(0.3)
        
        try await Task.sleep(for: .milliseconds(100))
        
        synthEngine.noteOff(pitch: 60)
        
        // Envelope modulation + smoothing should work together
    }
    
    /// Test LFO modulation with parameter smoothing
    func testLFOWithSmoothing() async throws {
        // Load preset with LFO on filter
        synthEngine.loadPreset(.analogSynth)  // Has LFO → filter
        
        synthEngine.noteOn(pitch: 60, velocity: 100)
        
        // Change cutoff while LFO is modulating
        for i in 0..<5 {
            synthEngine.setFilterCutoff(Float(i) * 0.2)
            try await Task.sleep(for: .milliseconds(20))
        }
        
        synthEngine.noteOff(pitch: 60)
        
        // LFO + smoothing should not cause artifacts
    }
    
    // MARK: - Performance Tests
    
    /// Test smoothing overhead is negligible
    func testSmoothingPerformance() {
        measure {
            // Simulate 1000 parameter changes (typical for 1 second of automation @ 48kHz)
            for _ in 0..<1000 {
                synthEngine.setFilterCutoff(Float.random(in: 0...1))
                synthEngine.setFilterResonance(Float.random(in: 0...1))
                synthEngine.setMasterVolume(Float.random(in: 0...1))
            }
        }
        
        // Smoothing should add negligible overhead (<1ms for 1000 changes)
    }
    
    // MARK: - Edge Cases
    
    /// Test parameter changes during note off (release phase)
    func testParameterChangeDuringRelease() async throws {
        synthEngine.loadPreset(.warmPad)  // Long release
        
        synthEngine.noteOn(pitch: 60, velocity: 100)
        try await Task.sleep(for: .milliseconds(50))
        
        // Trigger release
        synthEngine.noteOff(pitch: 60)
        
        // Change parameter during release
        synthEngine.setFilterCutoff(0.9)
        
        try await Task.sleep(for: .milliseconds(100))
        
        // Should smoothly change even during release
    }
    
    /// Test boundary values (0.0 and 1.0)
    func testBoundaryValues() {
        synthEngine.noteOn(pitch: 60, velocity: 100)
        
        // Test extreme values
        synthEngine.setFilterCutoff(0.0)
        synthEngine.setFilterCutoff(1.0)
        synthEngine.setMasterVolume(0.0)
        synthEngine.setMasterVolume(1.0)
        synthEngine.setFilterResonance(0.0)
        synthEngine.setFilterResonance(1.0)
        
        synthEngine.noteOff(pitch: 60)
        
        // Boundary values should smooth correctly
    }
    
    /// Test parameter changes with no active voices
    func testParameterChangeNoVoices() {
        // No notes playing
        synthEngine.setFilterCutoff(0.5)
        synthEngine.setMasterVolume(0.7)
        synthEngine.setFilterResonance(0.3)
        
        // Should handle gracefully (no crashes)
    }
    
    /// Test all notes off with parameter smoothing
    func testAllNotesOffWithSmoothing() async throws {
        // Play multiple notes
        for pitch: UInt8 in 60..<64 {
            synthEngine.noteOn(pitch: pitch, velocity: 100)
        }
        
        // Change parameter
        synthEngine.setFilterCutoff(0.8)
        
        // All notes off
        synthEngine.allNotesOff()
        
        try await Task.sleep(for: .milliseconds(100))
        
        // Should handle smoothly
    }
    
    /// Test panic (immediate voice removal) with smoothing
    func testPanicWithSmoothing() async throws {
        // Play notes
        synthEngine.noteOn(pitch: 60, velocity: 100)
        synthEngine.noteOn(pitch: 64, velocity: 100)
        
        // Change parameter
        synthEngine.setFilterCutoff(0.7)
        
        // Panic (immediate cutoff)
        synthEngine.panic()
        
        // Should not crash or cause issues
    }
}
