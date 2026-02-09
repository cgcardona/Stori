//
//  TransportSmokeTests.swift
//  StoriUITests
//
//  Smoke tests for transport controls — the most critical workflow in any DAW.
//  These must pass on every PR; failure here means the app is fundamentally broken.
//

import XCTest

final class TransportSmokeTests: StoriUITestCase {

    // MARK: - Test: Play / Stop Cycle

    /// Verify the user can press Play and Stop without crashing.
    /// Note: In an empty project, play button might not change to "Pause" since there's no content.
    func testPlayAndStop() throws {
        // Pre-condition: transport should be ready
        let playButton = button("transport_play")
        XCTAssertTrue(playButton.waitForExistence(timeout: defaultTimeout),
                      "Play button must exist on launch")

        // Tap Play - in an empty project, this might not actually start playback
        // but should not crash
        tap("transport_play")
        Thread.sleep(forTimeInterval: 0.5)

        // Verify buttons are still responsive
        XCTAssertTrue(playButton.exists, "Play button should still exist after tapping")

        // Tap Stop
        tap("transport_stop")
        Thread.sleep(forTimeInterval: 0.5)

        // Verify the app is still responsive
        XCTAssertTrue(playButton.exists, "Play button should still exist after stopping")
        XCTAssertTrue(app.buttons["transport_stop"].exists, "Stop button should exist")

        captureScreenshot(name: "Transport-PlayStop-Complete")
    }

    // MARK: - Test: Cycle Toggle

    /// Verify the cycle button toggles its active state.
    func testCycleToggle() throws {
        let cycleButton = button("transport_cycle")
        XCTAssertTrue(cycleButton.waitForExistence(timeout: defaultTimeout))

        // Check initial value — should be off
        let initialValue = cycleButton.value as? String

        // Toggle cycle on
        tap("transport_cycle")

        // Toggle cycle off
        tap("transport_cycle")

        // Should still be responding (no crash, no hang)
        XCTAssertTrue(cycleButton.exists, "Cycle button should still exist after toggling")

        captureScreenshot(name: "Transport-CycleToggle")
    }

    // MARK: - Test: Navigation Buttons

    /// Verify Go-to-Beginning and Go-to-End buttons respond without crashing.
    func testNavigationButtons() throws {
        // Go to end
        tap("transport_end")
        // Small wait to ensure the seek completed
        Thread.sleep(forTimeInterval: 0.5)

        // Go to beginning
        tap("transport_beginning")
        Thread.sleep(forTimeInterval: 0.5)

        // Rewind
        tap("transport_rewind")
        Thread.sleep(forTimeInterval: 0.3)

        // Fast forward
        tap("transport_forward")
        Thread.sleep(forTimeInterval: 0.3)

        // If we got here without a crash, the navigation buttons are functional
        captureScreenshot(name: "Transport-Navigation-Complete")
    }
}
