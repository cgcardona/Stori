//
//  StoriUITestsLaunchTests.swift
//  StoriUITests
//
//  Launch test that verifies the app starts and reaches the main DAW view.
//  This is the most basic sanity check — if this fails, nothing else matters.
//

import XCTest

final class StoriUITestsLaunchTests: StoriUITestCase {

    /// Verify the app launches and the main DAW window appears.
    func testAppLaunchesSuccessfully() throws {
        // The app should be running after setUp()
        XCTAssertTrue(app.windows.count > 0, "App should have at least one window")

        // The transport bar should be visible — it's always present in the DAW
        assertExists("transport_play", timeout: 15,
                     message: "Transport play button should appear on launch")
        assertExists("transport_stop",
                     message: "Transport stop button should appear on launch")

        // Capture a baseline screenshot
        captureScreenshot(name: "Launch-MainDAWView")
    }

    /// Verify all transport controls are present.
    func testTransportControlsPresent() throws {
        let transportButtons = [
            "transport_beginning",
            "transport_rewind",
            "transport_play",
            "transport_stop",
            "transport_record",
            "transport_forward",
            "transport_end",
            "transport_cycle",
            "transport_catch_playhead"
        ]

        for id in transportButtons {
            assertExists(id, timeout: 10,
                         message: "Transport button '\(id)' should be present")
        }
    }

    /// Verify panel toggle buttons are present.
    func testPanelToggleButtonsPresent() throws {
        let toggleButtons = [
            "toggle_mixer",
            "toggle_synthesizer",
            "toggle_piano_roll",
            "toggle_step_sequencer",
            "toggle_selection"
        ]

        for id in toggleButtons {
            assertExists(id, timeout: 10,
                         message: "Toggle button '\(id)' should be present")
        }
    }
}
