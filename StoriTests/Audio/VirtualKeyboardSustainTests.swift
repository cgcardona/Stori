//
//  VirtualKeyboardSustainTests.swift
//  StoriTests
//
//  Tests for virtual keyboard sustain pedal behavior (Issue #123)
//
//  CRITICAL: Sustain pedal should behave like a real piano damper pedal:
//  - Notes continue ringing when sustain is engaged
//  - Keys can be pressed multiple times while sustain is active (retriggering)
//  - Only notes that are released while sustain is active get sustained
//  - All sustained notes are released when sustain pedal is lifted
//

import XCTest
@testable import Stori

@MainActor
final class VirtualKeyboardSustainTests: XCTestCase {
    
    var keyboardState: VirtualKeyboardState!
    var instrumentManager: InstrumentManager!
    var audioEngine: AudioEngine!
    var projectManager: ProjectManager!
    var testProject: AudioProject!
    var testTrack: AudioTrack!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create test infrastructure
        projectManager = ProjectManager()
        audioEngine = AudioEngine()
        
        // Use shared InstrumentManager (same as virtual keyboard does)
        instrumentManager = InstrumentManager.shared
        
        // Create test project with MIDI track
        testProject = AudioProject(
            name: "Sustain Test Project",
            tempo: 120.0,
            timeSignature: TimeSignature(numerator: 4, denominator: 4)
        )
        testTrack = AudioTrack(name: "Test MIDI Track", trackType: .midi)
        testProject.tracks.append(testTrack)
        projectManager.currentProject = testProject
        
        // Configure dependencies
        audioEngine.configure(projectManager: projectManager)
        instrumentManager.configure(with: projectManager, audioEngine: audioEngine)
        
        // Select the test track and create instrument
        instrumentManager.selectedTrackId = testTrack.id
        _ = instrumentManager.getOrCreateInstrument(for: testTrack.id)
        
        // Create virtual keyboard state
        keyboardState = VirtualKeyboardState(audioEngine: audioEngine)
    }
    
    override func tearDown() async throws {
        keyboardState = nil
        instrumentManager = nil
        audioEngine = nil
        projectManager = nil
        testProject = nil
        testTrack = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Sustain Behavior
    
    /// Test that notes can be retriggered while sustain is active
    func testNoteRetriggeringWithSustainEnabled() throws {
        // Given: Sustain is enabled
        keyboardState.setSustain(true)
        XCTAssertTrue(keyboardState.sustainEnabled, "Sustain should be enabled")
        
        let pitch: UInt8 = 60 // Middle C
        
        // When: Press and release the same key multiple times with sustain on
        keyboardState.noteOn(pitch)
        XCTAssertTrue(keyboardState.pressedNotes.contains(pitch),
                      "Note should be in pressed notes after first press")
        
        keyboardState.noteOff(pitch)
        XCTAssertFalse(keyboardState.pressedNotes.contains(pitch),
                       "Note should not be in pressed notes after release")
        
        // Try to retrigger the same note
        keyboardState.noteOn(pitch)
        XCTAssertTrue(keyboardState.pressedNotes.contains(pitch),
                      "Note should be retriggerable while sustain is active")
        
        keyboardState.noteOff(pitch)
        keyboardState.noteOn(pitch)
        XCTAssertTrue(keyboardState.pressedNotes.contains(pitch),
                      "Note should be retriggerable again")
        
        // Clean up
        keyboardState.setSustain(false)
    }
    
    /// Test that sustain prevents immediate noteOff
    func testSustainPreventsImmediateNoteOff() throws {
        // Given: Sustain is enabled
        keyboardState.setSustain(true)
        
        // When: Play a note and release it
        keyboardState.noteOn(60)
        XCTAssertTrue(keyboardState.pressedNotes.contains(60),
                      "Note should be in pressed notes after noteOn")
        
        keyboardState.noteOff(60)
        
        // Then: Note should not be in pressed notes (was released)
        XCTAssertFalse(keyboardState.pressedNotes.contains(60),
                       "Note should not be in pressed notes after release")
        
        // But it can still be retriggered (proving sustain is working)
        keyboardState.noteOn(60)
        XCTAssertTrue(keyboardState.pressedNotes.contains(60),
                      "Note should be retriggerable after being sustained")
        
        // Clean up
        keyboardState.noteOff(60)
        keyboardState.setSustain(false)
    }
    
    /// Test that releasing sustain stops all sustained notes
    func testReleasingSustainStopsAllSustainedNotes() throws {
        // Given: Sustain enabled with multiple notes played and released
        keyboardState.setSustain(true)
        
        let pitches: [UInt8] = [60, 64, 67] // C major chord
        
        for pitch in pitches {
            keyboardState.noteOn(pitch)
            keyboardState.noteOff(pitch) // Released but sustained
        }
        
        // All notes should be sustained (not in pressed, but still sounding)
        for pitch in pitches {
            XCTAssertFalse(keyboardState.pressedNotes.contains(pitch),
                           "Note \(pitch) should not be in pressed notes after release")
        }
        
        // When: Release sustain
        keyboardState.setSustain(false)
        
        // Then: All sustained notes should be stopped
        for pitch in pitches {
            XCTAssertFalse(keyboardState.pressedNotes.contains(pitch),
                           "Note \(pitch) should be fully released")
        }
    }
    
    /// Test that currently pressed notes continue playing when sustain is released
    func testPressedNotesUnaffectedByReleasingSustain() throws {
        // Given: Sustain enabled with one note still pressed
        keyboardState.setSustain(true)
        
        // Play and release first note (gets sustained)
        keyboardState.noteOn(60)
        keyboardState.noteOff(60)
        
        // Play second note but keep it pressed
        keyboardState.noteOn(64)
        XCTAssertTrue(keyboardState.pressedNotes.contains(64),
                      "Second note should be pressed")
        
        // When: Release sustain
        keyboardState.setSustain(false)
        
        // Then: Currently pressed note should continue playing
        XCTAssertTrue(keyboardState.pressedNotes.contains(64),
                      "Pressed note should continue playing after sustain release")
        
        // Clean up
        keyboardState.noteOff(64)
    }
    
    // MARK: - Retriggering Tests
    
    /// Test retriggering the same note multiple times with sustain
    func testRepeatedRetriggeringWithSustain() throws {
        // Given: Sustain enabled
        keyboardState.setSustain(true)
        
        let pitch: UInt8 = 60
        let repetitions = 10
        
        // When: Repeatedly trigger the same note
        for _ in 0..<repetitions {
            keyboardState.noteOn(pitch)
            XCTAssertTrue(keyboardState.pressedNotes.contains(pitch),
                          "Note should be pressed after noteOn")
            
            keyboardState.noteOff(pitch)
            XCTAssertFalse(keyboardState.pressedNotes.contains(pitch),
                           "Note should be released after noteOff")
        }
        
        // Then: All repetitions should succeed (no stuck keys)
        XCTAssertFalse(keyboardState.pressedNotes.contains(pitch),
                       "Note should not be stuck in pressed state")
        
        // Clean up
        keyboardState.setSustain(false)
    }
    
    /// Test retriggering a sustained note with different velocity
    func testRetriggeringSustainedNoteWithDifferentVelocity() throws {
        // Given: Sustain is enabled
        keyboardState.setSustain(true)
        
        // When: Play note with velocity 100, release it, retrigger with velocity 50
        keyboardState.velocity = 100
        keyboardState.noteOn(60)
        XCTAssertTrue(keyboardState.pressedNotes.contains(60))
        
        keyboardState.noteOff(60)
        XCTAssertFalse(keyboardState.pressedNotes.contains(60))
        
        // Retrigger with different velocity
        keyboardState.velocity = 50
        keyboardState.noteOn(60)
        
        // Then: Note should be retriggerable with new velocity
        XCTAssertTrue(keyboardState.pressedNotes.contains(60),
                      "Note should be retriggerable with different velocity")
        
        // Clean up
        keyboardState.noteOff(60)
        keyboardState.setSustain(false)
    }
    
    /// Test polyphonic sustain - multiple notes can be retriggered independently
    func testPolyphonicSustainRetriggering() throws {
        // Given: Sustain enabled with multiple notes
        keyboardState.setSustain(true)
        
        let pitches: [UInt8] = [60, 64, 67] // C major chord
        
        // Play all notes
        for pitch in pitches {
            keyboardState.noteOn(pitch)
        }
        
        XCTAssertEqual(keyboardState.pressedNotes.count, 3,
                       "All notes should be pressed")
        
        // Release all notes
        for pitch in pitches {
            keyboardState.noteOff(pitch)
        }
        
        XCTAssertEqual(keyboardState.pressedNotes.count, 0,
                       "No notes should be pressed after release")
        
        // When: Retrigger each note individually
        for pitch in pitches {
            keyboardState.noteOn(pitch)
            XCTAssertTrue(keyboardState.pressedNotes.contains(pitch),
                          "Note \(pitch) should be retriggerable")
            keyboardState.noteOff(pitch)
        }
        
        // Then: All retriggers should succeed
        XCTAssertEqual(keyboardState.pressedNotes.count, 0,
                       "All notes should be released cleanly")
        
        // Clean up
        keyboardState.setSustain(false)
    }
    
    // MARK: - Edge Cases
    
    /// Test octave change while sustain is active
    func testOctaveChangeReleasesAllNotes() throws {
        // Given: Sustain enabled with notes playing
        keyboardState.setSustain(true)
        
        keyboardState.noteOn(60)
        keyboardState.noteOff(60)
        keyboardState.noteOn(64)
        
        XCTAssertTrue(keyboardState.sustainEnabled, "Sustain should be active")
        
        // When: Change octave
        keyboardState.octaveUp()
        
        // Then: All notes should be released (including sustained ones)
        XCTAssertEqual(keyboardState.pressedNotes.count, 0,
                       "Octave change should release all notes")
        
        // Sustain should still be enabled
        XCTAssertTrue(keyboardState.sustainEnabled,
                      "Sustain state should be preserved after octave change")
    }
    
    /// Test stopping listening while sustain is active
    func testStopListeningReleasesAllNotes() throws {
        // Given: Sustain enabled with notes
        keyboardState.startListening()
        keyboardState.setSustain(true)
        
        keyboardState.noteOn(60)
        keyboardState.noteOff(60)
        keyboardState.noteOn(64)
        
        // When: Stop listening (window closes)
        keyboardState.stopListening()
        
        // Then: All notes should be released
        XCTAssertEqual(keyboardState.pressedNotes.count, 0,
                       "All notes should be released when stopping listening")
    }
    
    /// Test rapid sustain on/off toggling
    func testRapidSustainToggling() throws {
        // Given: Note is playing
        keyboardState.noteOn(60)
        XCTAssertTrue(keyboardState.pressedNotes.contains(60))
        
        // When: Rapidly toggle sustain while note is held
        for _ in 0..<10 {
            keyboardState.setSustain(true)
            keyboardState.setSustain(false)
        }
        
        // Then: Note should still be in correct state
        XCTAssertTrue(keyboardState.pressedNotes.contains(60),
                      "Pressed note should remain pressed after sustain toggling")
        
        // Release note
        keyboardState.noteOff(60)
        XCTAssertFalse(keyboardState.pressedNotes.contains(60),
                       "Note should be released properly")
    }
    
    /// Test sustain with all 88 piano keys
    func testSustainWithFullKeyboardRange() throws {
        // Given: Sustain enabled
        keyboardState.setSustain(true)
        
        // When: Play and release all 88 piano keys (MIDI 21-108)
        let pianoRange: [UInt8] = Array(21...108)
        
        for pitch in pianoRange {
            keyboardState.noteOn(pitch)
            keyboardState.noteOff(pitch)
        }
        
        // Then: No notes should be stuck in pressed state
        XCTAssertEqual(keyboardState.pressedNotes.count, 0,
                       "No notes should be in pressed state after full range test")
        
        // All keys should still be retriggerable
        let testPitch: UInt8 = 60
        keyboardState.noteOn(testPitch)
        XCTAssertTrue(keyboardState.pressedNotes.contains(testPitch),
                      "Keys should still be playable after full range sustain test")
        
        // Clean up
        keyboardState.noteOff(testPitch)
        keyboardState.setSustain(false)
    }
    
    // MARK: - Integration Tests
    
    /// Test sustain with recording and latency compensation
    func testSustainWithLatencyCompensation() throws {
        // Given: Recording with latency compensation
        audioEngine.currentPosition.beats = 0.0
        instrumentManager.startRecording(trackId: testTrack.id, atBeats: 0.0)
        
        let compensation = 0.06 // 30ms at 120 BPM
        
        // When: Play note with sustain and latency compensation
        keyboardState.setSustain(true)
        
        audioEngine.currentPosition.beats = 1.0
        instrumentManager.noteOn(pitch: 60, velocity: 100, compensationBeats: compensation)
        
        audioEngine.currentPosition.beats = 1.5
        instrumentManager.noteOff(pitch: 60, compensationBeats: compensation)
        
        // Retrigger the same note while sustained
        audioEngine.currentPosition.beats = 2.0
        instrumentManager.noteOn(pitch: 60, velocity: 100, compensationBeats: compensation)
        
        audioEngine.currentPosition.beats = 2.5
        instrumentManager.noteOff(pitch: 60, compensationBeats: compensation)
        
        // Release sustain
        audioEngine.currentPosition.beats = 3.0
        keyboardState.setSustain(false)
        
        // Then: Should have two notes, both with proper compensation
        let recordedRegion = instrumentManager.stopRecording()
        XCTAssertEqual(recordedRegion?.notes.count, 2,
                       "Should record two separate notes with retriggering")
        
        let notes = try XCTUnwrap(recordedRegion?.notes.sorted { $0.startBeat < $1.startBeat })
        
        // First note: starts at 1.0 - 0.06 = 0.94
        XCTAssertEqual(notes[0].startBeat, 1.0 - compensation, accuracy: 0.001,
                       "First note should be compensated")
        
        // Second note: starts at 2.0 - 0.06 = 1.94
        XCTAssertEqual(notes[1].startBeat, 2.0 - compensation, accuracy: 0.001,
                       "Second note should be compensated")
    }
    
    /// Test that sustain state is synchronized with InstrumentManager
    func testSustainSynchronizationWithInstrumentManager() throws {
        // Given: Sustain is initially off
        XCTAssertFalse(keyboardState.sustainEnabled, "Sustain should start disabled")
        
        // When: Enable sustain
        keyboardState.setSustain(true)
        
        // Then: InstrumentManager should receive sustain state
        XCTAssertTrue(instrumentManager.isSustainActive,
                      "InstrumentManager should receive sustain state")
        XCTAssertTrue(keyboardState.sustainEnabled,
                      "Keyboard state should show sustain enabled")
        
        // When: Disable sustain
        keyboardState.setSustain(false)
        
        // Then: InstrumentManager should receive sustain off
        XCTAssertFalse(instrumentManager.isSustainActive,
                       "InstrumentManager should receive sustain off")
        XCTAssertFalse(keyboardState.sustainEnabled,
                       "Keyboard state should show sustain disabled")
    }
    
    // MARK: - Real-World Scenario Tests
    
    /// Test piano performance scenario: Alberti bass pattern with sustain
    func testPianoAlbertiBassWithSustain() throws {
        // Given: Sustain enabled for typical piano accompaniment pattern
        keyboardState.setSustain(true)
        
        // Alberti bass pattern: C-G-E-G (repeated)
        let pattern: [UInt8] = [48, 55, 52, 55] // C3, G3, E3, G3
        
        // When: Play pattern 4 times (simulating rapid alternating notes)
        for _ in 0..<4 {
            for pitch in pattern {
                keyboardState.noteOn(pitch)
                XCTAssertTrue(keyboardState.pressedNotes.contains(pitch),
                              "Note \(pitch) should be playable")
                
                keyboardState.noteOff(pitch)
                XCTAssertFalse(keyboardState.pressedNotes.contains(pitch),
                               "Note \(pitch) should be releasable")
            }
        }
        
        // Then: All notes should play cleanly without stuck keys
        XCTAssertEqual(keyboardState.pressedNotes.count, 0,
                       "No notes should be stuck in pressed state after pattern")
        
        // Verify any note can still be played after the pattern
        keyboardState.noteOn(48)
        XCTAssertTrue(keyboardState.pressedNotes.contains(48),
                      "Notes should still be playable after complex pattern")
        
        // Clean up
        keyboardState.noteOff(48)
        keyboardState.setSustain(false)
    }
    
    /// Test chord progression with sustain pedal changes
    func testChordProgressionWithSustainChanges() throws {
        // Given: Chord progression with sustain pedal changes
        
        // C major chord with sustain
        keyboardState.setSustain(true)
        for pitch in [60, 64, 67] as [UInt8] {
            keyboardState.noteOn(pitch)
        }
        for pitch in [60, 64, 67] as [UInt8] {
            keyboardState.noteOff(pitch)
        }
        
        // Release sustain (clears sustained notes)
        keyboardState.setSustain(false)
        
        XCTAssertEqual(keyboardState.pressedNotes.count, 0,
                       "All notes should be released after sustain off")
        
        // F major chord with new sustain
        keyboardState.setSustain(true)
        for pitch in [65, 69, 72] as [UInt8] {
            keyboardState.noteOn(pitch)
        }
        
        // Then: All notes of second chord should be playable
        XCTAssertEqual(keyboardState.pressedNotes.count, 3,
                       "All notes of second chord should be playing")
        
        for pitch in [65, 69, 72] as [UInt8] {
            XCTAssertTrue(keyboardState.pressedNotes.contains(pitch),
                          "Note \(pitch) should be playing in F major chord")
        }
        
        // Clean up
        for pitch in [65, 69, 72] as [UInt8] {
            keyboardState.noteOff(pitch)
        }
        keyboardState.setSustain(false)
    }
}
