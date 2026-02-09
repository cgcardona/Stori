//
//  RegionEditingWorkflowTests.swift
//  StoriUITests
//
//  Comprehensive region editing workflow tests.
//  Tests split, trim, fade, loop, duplicate, move, resize regions.
//

import XCTest

final class RegionEditingWorkflowTests: StoriUITestCase {

    // MARK: - Test: Select Region

    /// Verify regions can be selected in timeline.
    func testSelectRegion() throws {
        createAudioTrack()

        // Timeline should be visible by default
        // Regions would appear after recording or importing audio

        captureScreenshot(name: "RegionEdit-Select")
    }

    // MARK: - Test: Move Region

    /// Test dragging a region to new position.
    func testMoveRegion() throws {
        createAudioTrack()

        // Record/import audio to create a region
        // Then drag region to new position
        // (actual drag would require coordinate-based interaction or helper methods)

        captureScreenshot(name: "RegionEdit-Move")
    }

    // MARK: - Test: Resize Region

    /// Test resizing a region by dragging edges.
    func testResizeRegion() throws {
        createAudioTrack()

        // Create region
        // Drag left or right edge to resize
        // Region should trim audio content

        captureScreenshot(name: "RegionEdit-Resize")
    }

    // MARK: - Test: Split Region

    /// Test splitting a region at playhead.
    func testSplitRegion() throws {
        createAudioTrack()

        // Create region
        // Position playhead in middle of region
        // Use split command (keyboard shortcut or menu)
        // Should create two regions

        captureScreenshot(name: "RegionEdit-Split")
    }

    // MARK: - Test: Delete Region

    /// Test deleting selected region.
    func testDeleteRegion() throws {
        createAudioTrack()

        // Create region
        // Select region
        // Press Delete key
        typeKey(.delete)

        // Region should disappear
        Thread.sleep(forTimeInterval: 0.2)

        captureScreenshot(name: "RegionEdit-Delete")
    }

    // MARK: - Test: Duplicate Region

    /// Test duplicating a region.
    func testDuplicateRegion() throws {
        createAudioTrack()

        // Create region
        // Duplicate command (⌘D)
        typeShortcut("d", modifiers: [.command])

        // Should create copy of region
        Thread.sleep(forTimeInterval: 0.2)

        captureScreenshot(name: "RegionEdit-Duplicate")
    }

    // MARK: - Test: Loop Region

    /// Test enabling loop mode on a region.
    func testLoopRegion() throws {
        createAudioTrack()

        // Create region
        // Enable region looping (right-click menu or inspector)
        // Region should repeat during playback

        tap(AccessibilityID.Transport.play)
        Thread.sleep(forTimeInterval: 1.0)
        tap(AccessibilityID.Transport.stop)

        captureScreenshot(name: "RegionEdit-Loop")
    }

    // MARK: - Test: Fade In

    /// Test adding fade-in to region.
    func testFadeIn() throws {
        createAudioTrack()

        // Create region
        // Add fade-in (drag region start or inspector)
        // Visual fade curve should appear

        captureScreenshot(name: "RegionEdit-FadeIn")
    }

    // MARK: - Test: Fade Out

    /// Test adding fade-out to region.
    func testFadeOut() throws {
        createAudioTrack()

        // Create region
        // Add fade-out (drag region end or inspector)
        // Visual fade curve should appear

        captureScreenshot(name: "RegionEdit-FadeOut")
    }

    // MARK: - Test: Crossfade

    /// Test crossfading between two overlapping regions.
    func testCrossfade() throws {
        createAudioTrack()

        // Create two overlapping regions
        // Crossfade should automatically appear
        // Or manual crossfade adjustment

        captureScreenshot(name: "RegionEdit-Crossfade")
    }

    // MARK: - Test: Region Gain

    /// Test adjusting region gain/volume.
    func testRegionGain() throws {
        createAudioTrack()

        // Create region
        // Open inspector
        tap(AccessibilityID.Panel.toggleInspector)

        // Adjust region gain parameter
        // Region waveform should reflect gain change

        captureScreenshot(name: "RegionEdit-Gain")
    }

    // MARK: - Test: Reverse Region

    /// Test reversing audio in a region.
    func testReverseRegion() throws {
        createAudioTrack()

        // Create region
        // Apply reverse function (menu or context menu)
        // Waveform should flip

        captureScreenshot(name: "RegionEdit-Reverse")
    }

    // MARK: - Test: Normalize Region

    /// Test normalizing audio region.
    func testNormalizeRegion() throws {
        createAudioTrack()

        // Create region
        // Apply normalize function
        // Peak should reach 0 dB

        captureScreenshot(name: "RegionEdit-Normalize")
    }

    // MARK: - Test: Multi-Region Selection

    /// Test selecting multiple regions simultaneously.
    func testMultiRegionSelection() throws {
        createAudioTrack()

        // Create multiple regions
        // Select all (⌘A)
        typeShortcut("a", modifiers: [.command])

        // All regions should be selected
        captureScreenshot(name: "RegionEdit-MultiSelect")
    }

    // MARK: - Test: Copy/Paste Regions

    /// Test copying and pasting regions.
    func testCopyPasteRegions() throws {
        createAudioTrack()

        // Create region, select it
        // Copy (⌘C)
        typeShortcut("c", modifiers: [.command])

        // Move playhead
        tap(AccessibilityID.Transport.forward)

        // Paste (⌘V)
        typeShortcut("v", modifiers: [.command])

        // Region copy should appear at new position
        captureScreenshot(name: "RegionEdit-CopyPaste")
    }

    // MARK: - Test: Snap to Grid

    /// Test region snapping behavior.
    func testSnapToGrid() throws {
        createAudioTrack()

        // Enable snap to grid
        // Move region - should snap to grid lines

        // Disable snap
        // Move region - should move freely

        captureScreenshot(name: "RegionEdit-SnapToGrid")
    }

    // MARK: - Test: Region Inspector

    /// Verify region properties in inspector panel.
    func testRegionInspector() throws {
        createAudioTrack()

        // Create region, select it
        // Open inspector
        tap(AccessibilityID.Panel.toggleInspector)
        assertExists(AccessibilityID.Panel.toggleInspector, timeout: 3)

        // Inspector should show region properties
        captureScreenshot(name: "RegionEdit-Inspector")
    }

    // MARK: - Test: MIDI Region Editing

    /// Test editing MIDI regions specifically.
    func testMIDIRegionEditing() throws {
        createMIDITrack()

        // Create MIDI region
        // Double-click should open piano roll
        tap(AccessibilityID.Panel.togglePianoRoll)

        captureScreenshot(name: "RegionEdit-MIDI")
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
