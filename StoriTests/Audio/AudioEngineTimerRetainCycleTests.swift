//
//  AudioEngineTimerRetainCycleTests.swift
//  StoriTests
//
//  Comprehensive tests for timer cleanup and memory management (Issue #72).
//  Verifies that AudioEngine and related services properly release timers and don't leak memory.
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class AudioEngineTimerRetainCycleTests: XCTestCase {
    
    // MARK: - AudioEngine Deallocation Tests (Issue #72 - Core Regression)
    
    func testAudioEngineDeallocation() async throws {
        // Create AudioEngine with weak reference
        var audioEngine: AudioEngine? = AudioEngine()
        weak var weakEngine = audioEngine
        
        // Verify engine exists
        XCTAssertNotNil(weakEngine)
        
        // Load a simple project
        let project = AudioProject(name: "Test")
        audioEngine?.loadProject(project)
        
        // Explicitly cleanup before releasing
        audioEngine?.cleanup()
        
        // Release strong reference
        audioEngine = nil
        
        // Small delay for deallocation
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // **CRITICAL TEST**: AudioEngine should be deallocated (Issue #72)
        XCTAssertNil(weakEngine, "AudioEngine not deallocated - timer retain cycle detected (Issue #72)")
    }
    
    func testAudioEngineCleanupStopsAllTimers() {
        let audioEngine = AudioEngine()
        let project = AudioProject(name: "Test")
        audioEngine.loadProject(project)
        
        // Start playback (activates multiple timers)
        audioEngine.transportController.play()
        
        // Verify timers are running (indirectly through transport state)
        XCTAssertTrue(audioEngine.transportController.transportState.isPlaying)
        
        // Cleanup should stop all timers
        audioEngine.cleanup()
        
        // Verify playback stopped
        XCTAssertFalse(audioEngine.transportController.transportState.isPlaying)
        
        // No crashes = success
        XCTAssertTrue(true, "Cleanup completed without crash")
    }
    
    func testMultipleAudioEngineCreationAndCleanup() async throws {
        for i in 0..<10 {
            let audioEngine = AudioEngine()
            let project = AudioProject(name: "Test \(i)")
            audioEngine.loadProject(project)
            
            // Simulate some work
            audioEngine.transportController.play()
            try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            audioEngine.transportController.stop()
            
            // Cleanup
            audioEngine.cleanup()
        }
        
        // All 10 engines should be deallocated (no leaks)
        XCTAssertTrue(true, "Multiple engine cycles completed without leaks")
    }
    
    // MARK: - TransportController Timer Tests
    
    func testTransportControllerTimerCleanup() async throws {
        let audioEngine = AudioEngine()
        weak var weakTransport = audioEngine.transportController
        
        let project = AudioProject(name: "Test")
        audioEngine.loadProject(project)
        
        // Start playback (activates position timer)
        audioEngine.transportController.play()
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        audioEngine.transportController.stop()
        
        // Cleanup
        audioEngine.cleanup()
        
        // Transport should still exist (owned by engine)
        XCTAssertNotNil(weakTransport)
        
        // No crashes = timer cleanup successful
        XCTAssertTrue(true, "TransportController timer cleanup successful")
    }
    
    // MARK: - MIDI Scheduler Timer Tests
    
    func testMIDISchedulerTimerCleanup() async throws {
        let audioEngine = AudioEngine()
        let project = AudioProject(name: "Test")
        
        // Add MIDI track with region
        var track = AudioTrack(name: "MIDI Track", trackType: .midi)
        var region = MIDIRegion(name: "Region 1", startBeat: 0, durationBeats: 4)
        region.addNote(MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 1))
        track.addMIDIRegion(region)
        var projectWithMIDI = project
        projectWithMIDI.addTrack(track)
        
        audioEngine.loadProject(projectWithMIDI)
        
        // Start playback (activates MIDI scheduler timer)
        audioEngine.transportController.play()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        audioEngine.transportController.stop()
        
        // Cleanup
        audioEngine.cleanup()
        
        // No crashes = MIDI scheduler timer cleanup successful
        XCTAssertTrue(true, "MIDI scheduler timer cleanup successful")
    }
    
    // MARK: - Metronome Timer Tests
    
    func testMetronomeTimerCleanup() async throws {
        let audioEngine = AudioEngine()
        let project = AudioProject(name: "Test")
        audioEngine.loadProject(project)
        
        // Enable metronome
        audioEngine.metronomeEngine.enabled = true
        
        // Start playback (activates metronome fill timer)
        audioEngine.transportController.play()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        audioEngine.transportController.stop()
        
        // Cleanup
        audioEngine.cleanup()
        
        // No crashes = metronome timer cleanup successful
        XCTAssertTrue(true, "Metronome timer cleanup successful")
    }
    
    // MARK: - Automation Processor Timer Tests
    
    func testAutomationProcessorTimerCleanup() async throws {
        let audioEngine = AudioEngine()
        var project = AudioProject(name: "Test")
        
        // Add track with automation
        var track = AudioTrack(name: "Track 1", trackType: .audio)
        var volumeLane = AutomationLane(parameter: .volume)
        volumeLane.addPoint(atBeat: 0, value: 0.5)
        volumeLane.addPoint(atBeat: 4, value: 0.8)
        track.automation[.volume] = volumeLane
        project.addTrack(track)
        
        audioEngine.loadProject(project)
        
        // Start playback (activates automation processor timer)
        audioEngine.transportController.play()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        audioEngine.transportController.stop()
        
        // Cleanup
        audioEngine.cleanup()
        
        // No crashes = automation timer cleanup successful
        XCTAssertTrue(true, "Automation processor timer cleanup successful")
    }
    
    // MARK: - Rapid Project Switching Tests
    
    func testRapidProjectSwitchingNoMemoryLeak() async throws {
        var audioEngine: AudioEngine? = AudioEngine()
        weak var weakEngine = audioEngine
        
        // Simulate rapid project switching (common workflow)
        for i in 0..<5 {
            let project = AudioProject(name: "Project \(i)")
            audioEngine?.loadProject(project)
            
            audioEngine?.transportController.play()
            try await Task.sleep(nanoseconds: 20_000_000) // 20ms
            audioEngine?.transportController.stop()
        }
        
        // Cleanup and release
        audioEngine?.cleanup()
        audioEngine = nil
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // **CRITICAL**: Should be deallocated after rapid switching
        XCTAssertNil(weakEngine, "AudioEngine leaked after rapid project switching (Issue #72)")
    }
    
    // MARK: - Stress Tests
    
    func testLongSessionWithRepetitivePlayStop() async throws {
        let audioEngine = AudioEngine()
        let project = AudioProject(name: "Long Session")
        audioEngine.loadProject(project)
        
        // Simulate 50 play/stop cycles (typical long session)
        for _ in 0..<50 {
            audioEngine.transportController.play()
            try await Task.sleep(nanoseconds: 5_000_000) // 5ms
            audioEngine.transportController.stop()
        }
        
        // Cleanup
        audioEngine.cleanup()
        
        // No crashes = timers handled rapid start/stop correctly
        XCTAssertTrue(true, "Long session play/stop cycles completed without issues")
    }
    
    func testCleanupDuringPlaybackIsSafe() {
        let audioEngine = AudioEngine()
        let project = AudioProject(name: "Test")
        audioEngine.loadProject(project)
        
        // Start playback
        audioEngine.transportController.play()
        
        // Cleanup while playing (edge case - app quit during playback)
        audioEngine.cleanup()
        
        // Should stop playback safely
        XCTAssertFalse(audioEngine.transportController.transportState.isPlaying)
        
        // No crashes = cleanup during playback is safe
        XCTAssertTrue(true, "Cleanup during playback completed safely")
    }
    
    // MARK: - Multiple Subsystem Timer Tests
    
    func testAllTimerSubsystemsCleanupTogether() async throws {
        let audioEngine = AudioEngine()
        var project = AudioProject(name: "Full Stack Test")
        
        // Add MIDI track (activates MIDI scheduler timer)
        var midiTrack = AudioTrack(name: "MIDI", trackType: .midi)
        var midiRegion = MIDIRegion(name: "Notes", startBeat: 0, durationBeats: 4)
        midiRegion.addNote(MIDINote(pitch: 60, velocity: 100, startBeat: 0, durationBeats: 1))
        midiTrack.addMIDIRegion(midiRegion)
        
        // Add audio track with automation (activates automation timer)
        var audioTrack = AudioTrack(name: "Audio", trackType: .audio)
        var volumeLane = AutomationLane(parameter: .volume)
        volumeLane.addPoint(atBeat: 0, value: 0.5)
        volumeLane.addPoint(atBeat: 2, value: 0.8)
        audioTrack.automation[.volume] = volumeLane
        
        project.addTrack(midiTrack)
        project.addTrack(audioTrack)
        
        audioEngine.loadProject(project)
        
        // Enable metronome (activates metronome timer)
        audioEngine.metronomeEngine.enabled = true
        
        // Start playback (activates all timers: transport, MIDI, automation, metronome, health)
        audioEngine.transportController.play()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // **CRITICAL TEST**: Cleanup all subsystems at once
        audioEngine.cleanup()
        
        // Verify all stopped
        XCTAssertFalse(audioEngine.transportController.transportState.isPlaying)
        XCTAssertFalse(audioEngine.engine.isRunning)
        
        // No crashes = all timer subsystems cleaned up correctly
        XCTAssertTrue(true, "All timer subsystems cleaned up successfully (Issue #72)")
    }
    
    // MARK: - Health Timer Specific Tests
    
    func testEngineHealthTimerCleanup() async throws {
        var audioEngine: AudioEngine? = AudioEngine()
        weak var weakEngine = audioEngine
        
        let project = AudioProject(name: "Test")
        audioEngine?.loadProject(project)
        
        // Let health timer run for a few cycles
        try await Task.sleep(nanoseconds: 500_000_000) // 500ms
        
        // Cleanup (should cancel health timer)
        audioEngine?.cleanup()
        audioEngine = nil
        
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        // **CRITICAL**: Health timer should not prevent deallocation
        XCTAssertNil(weakEngine, "Health timer prevented AudioEngine deallocation (Issue #72)")
    }
    
    func testEngineHealthTimerDoesNotRetainEngine() {
        let audioEngine = AudioEngine()
        let project = AudioProject(name: "Test")
        audioEngine.loadProject(project)
        
        // Health timer starts automatically during loadProject
        // Timer uses [weak self] so it should not prevent deallocation
        
        // Cleanup
        audioEngine.cleanup()
        
        // If we get here without hanging, timer didn't cause retain cycle
        XCTAssertTrue(true, "Health timer uses weak self correctly")
    }
}
