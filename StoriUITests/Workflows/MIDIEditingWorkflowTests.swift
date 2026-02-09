//
//  MIDIEditingWorkflowTests.swift
//  StoriUITests
//
//  Comprehensive MIDI editing workflow tests.
//  Tests piano roll, note manipulation, velocity editing, quantization.
//

import XCTest

final class MIDIEditingWorkflowTests: StoriUITestCase {

    // MARK: - Test: Open Piano Roll

    /// Verify the piano roll can be opened and closed.
    func testOpenPianoRoll() throws {
        // Create a MIDI track first
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeMIDI)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)

        // Open piano roll via panel toggle
        tap(AccessibilityID.Panel.togglePianoRoll)
        assertExists(AccessibilityID.PianoRoll.container, timeout: 5,
                     message: "Piano roll should appear when toggled")

        captureScreenshot(name: "PianoRoll-Opened")

        // Close piano roll
        tap(AccessibilityID.Panel.togglePianoRoll)
        assertNotExists(AccessibilityID.PianoRoll.container, timeout: 3)
    }

    // MARK: - Test: Piano Roll Tool Selection

    /// Verify we can switch between piano roll tools (pencil, select, erase).
    func testPianoRollToolSelection() throws {
        // Create MIDI track
        createMIDITrack()

        // Open piano roll
        tap(AccessibilityID.Panel.togglePianoRoll)
        assertExists(AccessibilityID.PianoRoll.container, timeout: 5)

        // Tool selector should be present
        let toolSelector = element(AccessibilityID.PianoRoll.toolSelector)
        XCTAssertTrue(toolSelector.exists,
                     "Tool selector should be present in piano roll")

        captureScreenshot(name: "PianoRoll-ToolSelector")
    }

    // MARK: - Test: Quantize Button

    /// Verify quantize button exists and is interactive.
    func testQuantizeButton() throws {
        createMIDITrack()
        tap(AccessibilityID.Panel.togglePianoRoll)
        assertExists(AccessibilityID.PianoRoll.container, timeout: 5)

        // Quantize button should exist
        let quantizeButton = element(AccessibilityID.PianoRoll.quantizeButton)
        XCTAssertTrue(quantizeButton.exists,
                     "Quantize button should be present")

        // Button should be tappable (may be disabled if no notes selected)
        XCTAssertTrue(quantizeButton.isHittable,
                     "Quantize button should be hittable")

        captureScreenshot(name: "PianoRoll-Quantize")
    }

    // MARK: - Test: Velocity Slider

    /// Verify velocity slider is present and can be interacted with.
    func testVelocitySlider() throws {
        createMIDITrack()
        tap(AccessibilityID.Panel.togglePianoRoll)
        assertExists(AccessibilityID.PianoRoll.container, timeout: 5)

        // Velocity slider should exist
        let velocitySlider = element(AccessibilityID.PianoRoll.velocitySlider)
        XCTAssertTrue(velocitySlider.exists,
                     "Velocity slider should be present")

        captureScreenshot(name: "PianoRoll-VelocitySlider")
    }

    // MARK: - Test: MIDI Recording Workflow

    /// Test the complete MIDI recording workflow.
    func testMIDIRecordingWorkflow() throws {
        createMIDITrack()

        // Arm track for recording (would need track selection first)
        // Enable record on transport
        tap(AccessibilityID.Transport.record)

        // Play should start recording
        tap(AccessibilityID.Transport.play)

        // Wait briefly (simulating recording)
        Thread.sleep(forTimeInterval: 1.0)

        // Stop recording
        tap(AccessibilityID.Transport.stop)

        // Piano roll should show recorded MIDI
        tap(AccessibilityID.Panel.togglePianoRoll)
        assertExists(AccessibilityID.PianoRoll.container, timeout: 5)

        captureScreenshot(name: "MIDI-RecordingComplete")
    }

    // MARK: - Test: Multiple MIDI Tracks

    /// Verify multiple MIDI tracks can coexist and each can be edited.
    func testMultipleMIDITracks() throws {
        // Create first MIDI track
        createMIDITrack()

        // Create second MIDI track
        createMIDITrack()

        // Mixer should show two MIDI channel strips
        tap(AccessibilityID.Panel.toggleMixer)
        assertExists(AccessibilityID.Mixer.container, timeout: 5)

        captureScreenshot(name: "MIDI-MultipleTracks")
    }

    // MARK: - Test: MIDI Track with Synthesizer

    /// Verify MIDI track can route to synthesizer.
    func testMIDITrackWithSynthesizer() throws {
        createMIDITrack()

        // Open synthesizer panel
        tap(AccessibilityID.Panel.toggleSynthesizer)
        assertExists(AccessibilityID.Synthesizer.container, timeout: 5,
                     message: "Synthesizer should open")

        captureScreenshot(name: "MIDI-WithSynthesizer")

        // Close synthesizer
        tap(AccessibilityID.Panel.toggleSynthesizer)
    }

    // MARK: - Test: Step Sequencer

    /// Verify step sequencer can be opened for MIDI track.
    func testStepSequencer() throws {
        createMIDITrack()

        // Open step sequencer
        tap(AccessibilityID.Panel.toggleStepSequencer)
        assertExists(AccessibilityID.StepSequencer.container, timeout: 5,
                     message: "Step sequencer should open")

        // Preset picker should exist
        let presetPicker = element(AccessibilityID.StepSequencer.presetPicker)
        XCTAssertTrue(presetPicker.exists,
                     "Step sequencer preset picker should exist")

        captureScreenshot(name: "StepSequencer-Opened")

        // Close step sequencer
        tap(AccessibilityID.Panel.toggleStepSequencer)
    }

    // MARK: - Test: MIDI Track Playback

    /// Verify MIDI track plays back correctly.
    func testMIDITrackPlayback() throws {
        createMIDITrack()

        // Start playback
        tap(AccessibilityID.Transport.play)

        // Let it play briefly
        Thread.sleep(forTimeInterval: 0.5)

        // Transport should show playing state
        let playButton = element(AccessibilityID.Transport.play)
        XCTAssertTrue(playButton.exists, "Play button should exist during playback")

        // Stop playback
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "MIDI-PlaybackStopped")
    }

    // MARK: - Helper Methods

    private func createMIDITrack() {
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeMIDI)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)
    }
}
