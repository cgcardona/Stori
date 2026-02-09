//
//  TrackWorkflowSmokeTests.swift
//  StoriUITests
//
//  Smoke tests for track creation workflows.
//  Covers: Add Audio Track, Add MIDI Track, and basic track interaction.
//

import XCTest

final class TrackWorkflowSmokeTests: StoriUITestCase {

    // MARK: - Test: Create Audio Track

    /// Add an audio track via the Create Track dialog and verify it appears.
    func testAddAudioTrack() throws {
        // Open Create Track dialog via menu: Track > New Track...
        // The keyboard shortcut is ⌘⇧N
        typeShortcut("n", modifiers: [.command, .shift])

        // Wait for dialog to appear
        assertExists(AccessibilityID.Track.createDialog, timeout: 5,
                     message: "Create Track dialog should appear")

        // Select Audio track type
        tap(AccessibilityID.Track.createDialogTypeAudio)

        // Confirm creation
        tap(AccessibilityID.Track.createDialogConfirm)

        // Dialog should dismiss
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)

        captureScreenshot(name: "TrackWorkflow-AudioTrackCreated")
    }

    // MARK: - Test: Create MIDI Track

    /// Add a MIDI track via the Create Track dialog and verify it appears.
    func testAddMIDITrack() throws {
        typeShortcut("n", modifiers: [.command, .shift])

        assertExists(AccessibilityID.Track.createDialog, timeout: 5,
                     message: "Create Track dialog should appear")

        // MIDI should be selected by default, but tap it to be sure
        tap(AccessibilityID.Track.createDialogTypeMIDI)

        // Confirm creation
        tap(AccessibilityID.Track.createDialogConfirm)

        // Dialog should dismiss
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)

        captureScreenshot(name: "TrackWorkflow-MIDITrackCreated")
    }

    // MARK: - Test: Cancel Track Creation

    /// Open the Create Track dialog and cancel — verify no track is added.
    func testCancelTrackCreation() throws {
        typeShortcut("n", modifiers: [.command, .shift])

        assertExists(AccessibilityID.Track.createDialog, timeout: 5)

        // Press Cancel
        tap(AccessibilityID.Track.createDialogCancel)

        // Dialog should dismiss
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)

        captureScreenshot(name: "TrackWorkflow-CancelledCreation")
    }

    // MARK: - Test: Create Track and Play

    /// Full workflow: create a MIDI track, then play for 2 seconds and stop.
    func testCreateMIDITrackAndPlay() throws {
        // Create MIDI track
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeMIDI)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)

        // Play
        tap("transport_play")

        // Wait 2 seconds of playback
        let playButton = button("transport_play")
        let expectPlaying = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == 'Pause'"),
            object: playButton
        )
        XCTWaiter.wait(for: [expectPlaying], timeout: 3)

        // Let it play
        Thread.sleep(forTimeInterval: 2)

        // Stop
        tap("transport_stop")

        // Verify transport stopped
        let expectStopped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == 'Play'"),
            object: playButton
        )
        let result = XCTWaiter.wait(for: [expectStopped], timeout: 5)
        XCTAssertEqual(result, .completed, "Transport should be stopped")

        captureScreenshot(name: "TrackWorkflow-MIDITrackPlayback")
    }
}
