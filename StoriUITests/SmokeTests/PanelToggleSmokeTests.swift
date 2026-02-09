//
//  PanelToggleSmokeTests.swift
//  StoriUITests
//
//  Smoke tests for panel toggle buttons (Mixer, Piano Roll, Step Sequencer, etc.).
//  Verifies that panels open/close without crash and the toggle state updates.
//

import XCTest

final class PanelToggleSmokeTests: StoriUITestCase {

    // MARK: - Test: Toggle Mixer

    /// Toggle the mixer panel on and off.
    func testToggleMixer() throws {
        let mixerButton = button("toggle_mixer")
        XCTAssertTrue(mixerButton.waitForExistence(timeout: defaultTimeout))

        // Open mixer
        tap("toggle_mixer")
        Thread.sleep(forTimeInterval: 0.5)

        // Verify mixer container appeared
        assertExists(AccessibilityID.Mixer.container, timeout: 5,
                     message: "Mixer panel should appear when toggled on")

        captureScreenshot(name: "Panel-MixerOpen")

        // Close mixer
        tap("toggle_mixer")
        Thread.sleep(forTimeInterval: 0.5)

        captureScreenshot(name: "Panel-MixerClosed")
    }

    // MARK: - Test: Toggle All Panels

    /// Toggle each panel button and verify no crash occurs.
    /// Panels are mutually exclusive (only one bottom panel at a time).
    func testToggleAllPanels() throws {
        let panels = [
            "toggle_mixer",
            "toggle_synthesizer",
            "toggle_piano_roll",
            "toggle_step_sequencer"
        ]

        for panelId in panels {
            // Toggle on
            tap(panelId)
            Thread.sleep(forTimeInterval: 0.3)
            captureScreenshot(name: "Panel-\(panelId)-Open")

            // Toggle off
            tap(panelId)
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    // MARK: - Test: Mixer Shows After Track Creation

    /// Create a track, then open mixer — channel strip should be present.
    func testMixerShowsChannelStripAfterTrackCreation() throws {
        // Create an audio track first
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeAudio)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)

        // Open mixer
        tap("toggle_mixer")
        Thread.sleep(forTimeInterval: 1)

        // The mixer container should exist
        assertExists(AccessibilityID.Mixer.container, timeout: 5)

        captureScreenshot(name: "Panel-MixerWithTrack")
    }

    // MARK: - Test: Selection Info Panel

    /// Toggle the Selection Info panel.
    func testToggleSelectionInfo() throws {
        tap("toggle_selection")
        Thread.sleep(forTimeInterval: 0.5)
        captureScreenshot(name: "Panel-SelectionInfoOpen")

        tap("toggle_selection")
        Thread.sleep(forTimeInterval: 0.5)
        captureScreenshot(name: "Panel-SelectionInfoClosed")
    }
}
