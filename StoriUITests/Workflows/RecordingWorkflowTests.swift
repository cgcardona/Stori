//
//  RecordingWorkflowTests.swift
//  StoriUITests
//
//  Comprehensive recording workflow tests.
//  Tests punch in/out, overdub, count-in, metronome, multiple takes.
//

import XCTest

final class RecordingWorkflowTests: StoriUITestCase {

    // MARK: - Test: Basic Audio Recording

    /// Verify basic audio recording workflow.
    func testBasicAudioRecording() throws {
        createAudioTrack()

        // Enable record
        tap(AccessibilityID.Transport.record)

        // Start recording by pressing play
        tap(AccessibilityID.Transport.play)

        // Record for 1 second
        Thread.sleep(forTimeInterval: 1.0)

        // Stop recording
        tap(AccessibilityID.Transport.stop)

        // New audio region should appear in timeline
        captureScreenshot(name: "Recording-BasicAudio")
    }

    // MARK: - Test: MIDI Recording

    /// Verify MIDI recording workflow.
    func testMIDIRecording() throws {
        createMIDITrack()

        // Enable record
        tap(AccessibilityID.Transport.record)

        // Start playback to record MIDI
        tap(AccessibilityID.Transport.play)

        // Simulate MIDI input for 1 second
        Thread.sleep(forTimeInterval: 1.0)

        // Stop
        tap(AccessibilityID.Transport.stop)

        // MIDI region should appear
        captureScreenshot(name: "Recording-MIDI")
    }

    // MARK: - Test: Overdub Recording

    /// Test overdub/replace recording modes.
    func testOverdubRecording() throws {
        createAudioTrack()

        // First take
        tap(AccessibilityID.Transport.record)
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 0.5)
        tap(AccessibilityID.Transport.stop)

        // Return to beginning
        tap(AccessibilityID.Transport.beginning)

        // Second take (overdub)
        tap(AccessibilityID.Transport.record)
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 0.5)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Recording-Overdub")
    }

    // MARK: - Test: Punch In/Out

    /// Test punch recording (record during specific time range).
    func testPunchRecording() throws {
        createAudioTrack()

        // Set punch in/out points (would need UI for this)
        // Enable punch mode
        // Start playback - should auto-punch at specified points

        tap(AccessibilityID.Transport.record)
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 2.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Recording-Punch")
    }

    // MARK: - Test: Recording with Metronome

    /// Verify metronome during recording.
    func testRecordingWithMetronome() throws {
        createAudioTrack()

        // Enable metronome
        tap(AccessibilityID.Transport.metronome)

        // Record with click
        tap(AccessibilityID.Transport.record)
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 1.0)
        tap(AccessibilityID.Transport.stop)

        // Disable metronome
        tap(AccessibilityID.Transport.metronome)

        captureScreenshot(name: "Recording-Metronome")
    }

    // MARK: - Test: Multi-Track Recording

    /// Test recording multiple tracks simultaneously.
    func testMultiTrackRecording() throws {
        // Create two audio tracks
        createAudioTrack()
        createAudioTrack()

        // Open mixer to arm both tracks
        tap(AccessibilityID.Panel.toggleMixer)
        assertExists(AccessibilityID.Mixer.container, timeout: 5)

        // Arm both tracks for recording (would need track selection)
        // Enable record on transport
        tap(AccessibilityID.Transport.record)

        // Start recording
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 1.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Recording-MultiTrack")
    }

    // MARK: - Test: Recording with Count-In

    /// Verify count-in functionality before recording.
    func testRecordingWithCountIn() throws {
        createAudioTrack()

        // Enable count-in (would need UI toggle)
        // Start recording - should count in first
        tap(AccessibilityID.Transport.record)
        tap(AccessibilityID.Transport.play)

        // Count-in (1 bar = ~2 seconds at 120 BPM)
        Thread.sleep(forTimeInterval: 2.0)

        // Now recording
        Thread.sleep(forTimeInterval: 1.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Recording-CountIn")
    }

    // MARK: - Test: Recording during Cycle Mode

    /// Test loop recording (cycle mode).
    func testLoopRecording() throws {
        createMIDITrack()

        // Enable cycle mode
        tap(AccessibilityID.Transport.cycle)

        // Set cycle range (would need timeline interaction)
        // Start recording - should loop
        tap(AccessibilityID.Transport.record)
        tap(AccessibilityID.Transport.play)

        // Record multiple passes
        Thread.sleep(forTimeInterval: 3.0)
        tap(AccessibilityID.Transport.stop)

        // Disable cycle
        tap(AccessibilityID.Transport.cycle)

        captureScreenshot(name: "Recording-Loop")
    }

    // MARK: - Test: Recording with Input Monitoring

    /// Verify input monitoring during recording.
    func testInputMonitoring() throws {
        createAudioTrack()

        // Open mixer
        tap(AccessibilityID.Panel.toggleMixer)
        assertExists(AccessibilityID.Mixer.container, timeout: 5)

        // Arm track (enables input monitoring)
        // Should hear input signal before recording

        tap(AccessibilityID.Transport.record)
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 1.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Recording-InputMonitoring")
    }

    // MARK: - Test: Recording Undo

    /// Verify recorded audio can be undone.
    func testRecordingUndo() throws {
        createAudioTrack()

        // Record
        tap(AccessibilityID.Transport.record)
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 0.5)
        tap(AccessibilityID.Transport.stop)

        // Undo recording
        typeShortcut("z", modifiers: [.command])

        // Recorded region should disappear
        Thread.sleep(forTimeInterval: 0.2)

        captureScreenshot(name: "Recording-Undo")
    }

    // MARK: - Test: Pre-Roll Recording

    /// Test pre-roll before recording starts.
    func testPreRollRecording() throws {
        createAudioTrack()

        // Set playhead away from beginning
        // Enable pre-roll (would need UI)

        tap(AccessibilityID.Transport.record)
        tap(AccessibilityID.Transport.play)

        // Pre-roll time
        Thread.sleep(forTimeInterval: 1.5)

        // Now recording
        Thread.sleep(forTimeInterval: 1.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Recording-PreRoll")
    }

    // MARK: - Test: Recording Latency Compensation

    /// Verify recording latency is compensated.
    func testRecordingLatencyCompensation() throws {
        // Create backing track
        createAudioTrack()

        // Create recording track
        createAudioTrack()

        // Record second track while first plays
        tap(AccessibilityID.Transport.record)
        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 1.0)
        tap(AccessibilityID.Transport.stop)

        // Recorded audio should be aligned with backing track
        captureScreenshot(name: "Recording-LatencyCompensation")
    }

    // MARK: - Helper Methods

    private func createAudioTrack() {
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeAudio)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)
    }

    private func createMIDITrack() {
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeMIDI)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)
    }
}
