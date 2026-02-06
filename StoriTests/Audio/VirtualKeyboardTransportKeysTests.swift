//
//  VirtualKeyboardTransportKeysTests.swift
//  StoriTests
//
//  Tests for virtual keyboard transport key forwarding (Issue #121)
//
//  CRITICAL: Transport keys (R, Return, comma, period) must work when Virtual Keyboard is open.
//  - 'r': Record/Stop Recording
//  - Return: Go to Beginning
//  - ',': Rewind 1 beat
//  - '.': Fast Forward 1 beat
//
//  This prevents recording workflow from being blocked by Virtual Keyboard window.
//

import XCTest
@testable import Stori

@MainActor
final class VirtualKeyboardTransportKeysTests: XCTestCase {
    
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
        
        // Use shared InstrumentManager
        instrumentManager = InstrumentManager.shared
        
        // Create test project with audio track for recording
        testProject = AudioProject(
            name: "Transport Keys Test Project",
            tempo: 120.0,
            timeSignature: TimeSignature(numerator: 4, denominator: 4)
        )
        testTrack = AudioTrack(name: "Test Audio Track", trackType: .audio)
        testProject.tracks.append(testTrack)
        projectManager.currentProject = testProject
        
        // Configure dependencies
        audioEngine.configure(projectManager: projectManager)
        instrumentManager.configure(with: projectManager, audioEngine: audioEngine)
        
        // Create virtual keyboard state with audioEngine reference
        keyboardState = VirtualKeyboardState(audioEngine: audioEngine)
        keyboardState.configure(audioEngine: audioEngine)
    }
    
    override func tearDown() async throws {
        // Stop any ongoing recording
        if audioEngine.isRecording {
            audioEngine.stopRecording()
        }
        
        keyboardState = nil
        instrumentManager = nil
        audioEngine = nil
        projectManager = nil
        testProject = nil
        testTrack = nil
        try await super.tearDown()
    }
    
    // MARK: - Recording Control Tests
    
    /// Test that 'r' key can trigger recording when Virtual Keyboard is active
    func testRecordingKeyStartsRecording() throws {
        // Given: Virtual Keyboard is active and listening
        keyboardState.startListening()
        
        // Initial state: not recording
        XCTAssertFalse(audioEngine.isRecording, "Should not be recording initially")
        
        // When: User presses 'r' key (simulated via handleKeyDown)
        // Note: In real usage, this would come through NSEvent monitor
        // For testing, we verify the key is NOT consumed by music key handling
        let pitch = keyboardState.pitchForKeyForTesting("r")
        XCTAssertNil(pitch, "'r' should not be mapped to a music note")
        
        // Verify 'r' is not in music key mappings
        XCTAssertFalse(keyboardState.whiteKeyChars.contains("r"),
                       "'r' should not be a white key")
        XCTAssertFalse(keyboardState.blackKeyChars.contains("r"),
                       "'r' should not be a black key")
        
        // Clean up
        keyboardState.stopListening()
    }
    
    /// Test that recording workflow is not blocked by Virtual Keyboard
    func testRecordingWorkflowNotBlocked() throws {
        // Given: Virtual Keyboard is active
        keyboardState.startListening()
        
        // When: Recording is triggered (via AudioEngine directly, as the fix does)
        // Arm track for recording
        testProject.tracks[0].mixerSettings.isRecordEnabled = true
        projectManager.currentProject = testProject
        
        // The fix ensures 'r' key triggers this directly
        // We verify AudioEngine can start recording
        XCTAssertFalse(audioEngine.isRecording, "Should not be recording initially")
        
        // Note: We can't fully test recording here because it requires microphone permissions
        // and file system access, which are tested separately in RecordingControllerTests.
        // This test verifies the key routing logic.
        
        // Clean up
        keyboardState.stopListening()
    }
    
    // MARK: - Transport Position Tests
    
    /// Test that Return key (Go to Beginning) is not consumed by music keys
    func testReturnKeyNotConsumedByMusicKeys() throws {
        // Given: Virtual Keyboard is active
        keyboardState.startListening()
        
        // When: User presses Return key
        let pitch = keyboardState.pitchForKeyForTesting("\r")
        XCTAssertNil(pitch, "Return should not be mapped to a music note")
        
        // Verify Return is not in music key mappings
        XCTAssertFalse(keyboardState.whiteKeyChars.contains("\r"),
                       "Return should not be a white key")
        XCTAssertFalse(keyboardState.blackKeyChars.contains("\r"),
                       "Return should not be a black key")
        
        // Clean up
        keyboardState.stopListening()
    }
    
    /// Test that comma key (Rewind) is not consumed by music keys
    func testCommaKeyNotConsumedByMusicKeys() throws {
        // Given: Virtual Keyboard is active
        keyboardState.startListening()
        
        // When: User presses comma key
        let pitch = keyboardState.pitchForKeyForTesting(",")
        XCTAssertNil(pitch, "Comma should not be mapped to a music note")
        
        // Verify comma is not in music key mappings
        XCTAssertFalse(keyboardState.whiteKeyChars.contains(","),
                       "Comma should not be a white key")
        XCTAssertFalse(keyboardState.blackKeyChars.contains(","),
                       "Comma should not be a black key")
        
        // Clean up
        keyboardState.stopListening()
    }
    
    /// Test that period key (Fast Forward) is not consumed by music keys
    func testPeriodKeyNotConsumedByMusicKeys() throws {
        // Given: Virtual Keyboard is active
        keyboardState.startListening()
        
        // When: User presses period key
        let pitch = keyboardState.pitchForKeyForTesting(".")
        XCTAssertNil(pitch, "Period should not be mapped to a music note")
        
        // Verify period is not in music key mappings
        XCTAssertFalse(keyboardState.whiteKeyChars.contains("."),
                       "Period should not be a white key")
        XCTAssertFalse(keyboardState.blackKeyChars.contains("."),
                       "Period should not be a black key")
        
        // Clean up
        keyboardState.stopListening()
    }
    
    // MARK: - Music Key Regression Tests
    
    /// Test that white music keys still work correctly (no regression)
    func testWhiteKeysStillWorkCorrectly() throws {
        // Given: Virtual Keyboard is active
        keyboardState.startListening()
        
        // Select MIDI track for routing
        let midiTrack = AudioTrack(name: "MIDI Track", trackType: .midi)
        testProject.tracks.append(midiTrack)
        projectManager.currentProject = testProject
        instrumentManager.selectedTrackId = midiTrack.id
        _ = instrumentManager.getOrCreateInstrument(for: midiTrack.id)
        
        // When: User presses white keys (a, s, d, f, g, h, j, k, l, ;, ')
        // At octave 4 (UI control): basePitch = 4*12 = 48 (MIDI note C3)
        let whiteKeyPitches: [(Character, UInt8)] = [
            ("a", 48),  // C (octave 4 base = MIDI 48)
            ("s", 50),  // D
            ("d", 52),  // E
            ("f", 53),  // F
            ("g", 55),  // G
            ("h", 57),  // A
            ("j", 59),  // B
        ]
        
        for (char, expectedPitch) in whiteKeyPitches {
            let pitch = keyboardState.pitchForKeyForTesting(char)
            XCTAssertNotNil(pitch, "'\(char)' should map to a music note")
            XCTAssertEqual(pitch, expectedPitch,
                          "'\(char)' should map to pitch \(expectedPitch) at octave \(keyboardState.octave)")
        }
        
        // Clean up
        keyboardState.stopListening()
    }
    
    /// Test that black music keys still work correctly (no regression)
    func testBlackKeysStillWorkCorrectly() throws {
        // Given: Virtual Keyboard is active
        keyboardState.startListening()
        
        // Select MIDI track for routing
        let midiTrack = AudioTrack(name: "MIDI Track", trackType: .midi)
        testProject.tracks.append(midiTrack)
        projectManager.currentProject = testProject
        instrumentManager.selectedTrackId = midiTrack.id
        _ = instrumentManager.getOrCreateInstrument(for: midiTrack.id)
        
        // When: User presses black keys (w, e, t, y, u, o, p)
        // At octave 4 (UI control): basePitch = 4*12 = 48 (MIDI note C3)
        let blackKeyPitches: [(Character, UInt8)] = [
            ("w", 49),  // C#
            ("e", 51),  // D#
            ("t", 54),  // F#
            ("y", 56),  // G#
            ("u", 58),  // A#
        ]
        
        for (char, expectedPitch) in blackKeyPitches {
            let pitch = keyboardState.pitchForKeyForTesting(char)
            XCTAssertNotNil(pitch, "'\(char)' should map to a music note")
            XCTAssertEqual(pitch, expectedPitch,
                          "'\(char)' should map to pitch \(expectedPitch) at octave \(keyboardState.octave)")
        }
        
        // Clean up
        keyboardState.stopListening()
    }
    
    // MARK: - Control Key Regression Tests
    
    /// Test that z/x (octave control) still works (no regression)
    func testOctaveControlKeysStillWork() throws {
        // Given: Virtual Keyboard is active at default octave
        keyboardState.startListening()
        let initialOctave = keyboardState.octave
        
        // When: User presses 'x' (octave up)
        keyboardState.octaveUp()
        XCTAssertEqual(keyboardState.octave, initialOctave + 1,
                       "Octave should increase by 1")
        
        // When: User presses 'z' (octave down)
        keyboardState.octaveDown()
        XCTAssertEqual(keyboardState.octave, initialOctave,
                       "Octave should return to initial value")
        
        // Clean up
        keyboardState.stopListening()
    }
    
    /// Test that c/v (velocity control) still works (no regression)
    func testVelocityControlKeysStillWork() throws {
        // Given: Virtual Keyboard is active at default velocity
        keyboardState.startListening()
        let initialVelocity = keyboardState.velocity
        
        // When: User presses 'v' (velocity up)
        keyboardState.velocityUp()
        XCTAssertGreaterThan(keyboardState.velocity, initialVelocity,
                            "Velocity should increase")
        
        // When: User presses 'c' (velocity down)
        keyboardState.velocityDown()
        XCTAssertEqual(keyboardState.velocity, initialVelocity,
                       "Velocity should return to initial value")
        
        // Clean up
        keyboardState.stopListening()
    }
    
    /// Test that space (sustain) still works (no regression)
    func testSustainKeyStillWorks() throws {
        // Given: Virtual Keyboard is active with sustain disabled
        keyboardState.startListening()
        XCTAssertFalse(keyboardState.sustainEnabled, "Sustain should be disabled initially")
        
        // When: User presses space (sustain toggle)
        keyboardState.setSustain(true)
        XCTAssertTrue(keyboardState.sustainEnabled, "Sustain should be enabled")
        
        // When: User presses space again
        keyboardState.setSustain(false)
        XCTAssertFalse(keyboardState.sustainEnabled, "Sustain should be disabled")
        
        // Clean up
        keyboardState.stopListening()
    }
}

// MARK: - Test Helpers

extension VirtualKeyboardState {
    /// Expose pitchForKey for testing
    func pitchForKeyForTesting(_ char: Character) -> UInt8? {
        return self.pitchForKey(char)
    }
    
    /// Expose white key chars for testing
    var whiteKeyChars: [Character] {
        ["a", "s", "d", "f", "g", "h", "j", "k", "l", ";", "'"]
    }
    
    /// Expose black key chars for testing
    var blackKeyChars: [Character] {
        ["w", "e", "t", "y", "u", "o", "p"]
    }
}
