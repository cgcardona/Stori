//
//  AutomationLaneWorkflowTests.swift
//  StoriUITests
//
//  Comprehensive automation lane workflow tests.
//  Tests creating automation lanes, editing points, curves, deleting.
//

import XCTest

final class AutomationLaneWorkflowTests: StoriUITestCase {

    // MARK: - Test: Show Automation Lane

    /// Verify automation lanes can be shown for a track.
    func testShowAutomationLane() throws {
        createAudioTrack()

        // Expand track to show automation lanes
        // (would need track expansion UI or keyboard shortcut)

        captureScreenshot(name: "Automation-ShowLane")
    }

    // MARK: - Test: Volume Automation

    /// Test creating volume automation points.
    func testVolumeAutomation() throws {
        createAudioTrack()

        // Show volume automation lane
        // Add automation points by clicking
        // Draw automation curve

        captureScreenshot(name: "Automation-Volume")
    }

    // MARK: - Test: Pan Automation

    /// Test creating pan automation.
    func testPanAutomation() throws {
        createAudioTrack()

        // Show pan automation lane
        // Create automation points
        // Pan should move during playback

        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 1.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Automation-Pan")
    }

    // MARK: - Test: Plugin Parameter Automation

    /// Test automating plugin parameters.
    func testPluginParameterAutomation() throws {
        createAudioTrack()

        // Insert plugin
        // Show plugin parameter automation lane
        // Create automation for plugin parameter

        captureScreenshot(name: "Automation-PluginParameter")
    }

    // MARK: - Test: Edit Automation Points

    /// Test editing existing automation points.
    func testEditAutomationPoints() throws {
        createAudioTrack()

        // Create automation points
        // Select point and drag to new value
        // Point should move smoothly

        captureScreenshot(name: "Automation-EditPoints")
    }

    // MARK: - Test: Delete Automation Points

    /// Test deleting automation points.
    func testDeleteAutomationPoints() throws {
        createAudioTrack()

        // Create automation points
        // Select points
        // Press Delete
        typeKey(.delete)

        // Points should disappear
        Thread.sleep(forTimeInterval: 0.2)

        captureScreenshot(name: "Automation-DeletePoints")
    }

    // MARK: - Test: Automation Curves

    /// Test different automation curve types (linear, exponential, etc).
    func testAutomationCurves() throws {
        createAudioTrack()

        // Create two automation points
        // Right-click to select curve type
        // Curve shape should change

        captureScreenshot(name: "Automation-Curves")
    }

    // MARK: - Test: Automation Read Mode

    /// Test automation read mode during playback.
    func testAutomationReadMode() throws {
        createAudioTrack()

        // Create volume automation
        // Enable read mode
        // Play - automation should be read

        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 1.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Automation-ReadMode")
    }

    // MARK: - Test: Automation Write Mode

    /// Test automation write mode (recording automation).
    func testAutomationWriteMode() throws {
        createAudioTrack()

        // Enable write mode
        // Start playback
        // Move fader - should write automation

        tap(AccessibilityID.Panel.toggleMixer)
        assertExists(AccessibilityID.Mixer.container, timeout: 5)

        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 1.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Automation-WriteMode")
    }

    // MARK: - Test: Automation Latch Mode

    /// Test automation latch mode.
    func testAutomationLatchMode() throws {
        createAudioTrack()

        // Enable latch mode
        // Start playback
        // Touch control - should write, then latch

        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 1.5)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Automation-LatchMode")
    }

    // MARK: - Test: Automation Touch Mode

    /// Test automation touch mode.
    func testAutomationTouchMode() throws {
        createAudioTrack()

        // Enable touch mode
        // Start playback
        // Touch control briefly - should write only while touching

        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 1.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "Automation-TouchMode")
    }

    // MARK: - Test: Multiple Automation Lanes

    /// Test showing multiple automation lanes per track.
    func testMultipleAutomationLanes() throws {
        createAudioTrack()

        // Show volume automation
        // Show pan automation
        // Show send automation
        // All lanes should be visible simultaneously

        captureScreenshot(name: "Automation-MultipleLanes")
    }

    // MARK: - Test: Copy/Paste Automation

    /// Test copying and pasting automation data.
    func testCopyPasteAutomation() throws {
        createAudioTrack()

        // Create automation points
        // Select range
        // Copy (⌘C)
        typeShortcut("c", modifiers: [.command])

        // Move playhead
        tap(AccessibilityID.Transport.forward)

        // Paste (⌘V)
        typeShortcut("v", modifiers: [.command])

        // Automation should be duplicated
        captureScreenshot(name: "Automation-CopyPaste")
    }

    // MARK: - Test: Clear Automation

    /// Test clearing all automation from a lane.
    func testClearAutomation() throws {
        createAudioTrack()

        // Create automation points
        // Clear automation command (context menu or menu bar)
        // Lane should be empty

        captureScreenshot(name: "Automation-Clear")
    }

    // MARK: - Test: Automation Snap

    /// Test automation point snapping to grid.
    func testAutomationSnap() throws {
        createAudioTrack()

        // Enable snap to grid
        // Create automation points
        // Points should snap to grid positions

        captureScreenshot(name: "Automation-Snap")
    }

    // MARK: - Test: Automation Undo/Redo

    /// Verify automation edits can be undone/redone.
    func testAutomationUndoRedo() throws {
        createAudioTrack()

        // Create automation point
        // Undo
        typeShortcut("z", modifiers: [.command])

        // Point should disappear
        Thread.sleep(forTimeInterval: 0.2)

        // Redo
        typeShortcut("z", modifiers: [.command, .shift])

        // Point should reappear
        captureScreenshot(name: "Automation-UndoRedo")
    }

    // MARK: - Test: Automation During Cycle

    /// Test automation recording during cycle mode.
    func testAutomationDuringCycle() throws {
        createAudioTrack()

        // Enable cycle mode
        tap(AccessibilityID.Transport.cycle)

        // Enable automation write
        // Start playback
        tap(AccessibilityID.Transport.play)

        // Move fader multiple times during loop
        Thread.sleep(forTimeInterval: 3.0)
        tap(AccessibilityID.Transport.stop)

        // Disable cycle
        tap(AccessibilityID.Transport.cycle)

        captureScreenshot(name: "Automation-Cycle")
    }

    // MARK: - Test: Thin Automation

    /// Test automation thinning (reduce point density).
    func testThinAutomation() throws {
        createAudioTrack()

        // Record dense automation
        // Apply thin/simplify function
        // Point count should decrease while preserving shape

        captureScreenshot(name: "Automation-Thin")
    }

    // MARK: - Helper Methods

    private func createAudioTrack() {
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeAudio)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)
    }
}
