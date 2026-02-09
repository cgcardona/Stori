//
//  ExportSmokeTests.swift
//  StoriUITests
//
//  Smoke tests for the export workflow.
//  Verifies the export dialog opens, settings can be configured, and export can be triggered.
//

import XCTest

final class ExportSmokeTests: StoriUITestCase {

    // MARK: - Test: Open Export Dialog

    /// Verify the export dialog can be opened via keyboard shortcut.
    func testOpenExportDialog() throws {
        // Export shortcut: ⌘E
        typeShortcut("e", modifiers: [.command])

        // Wait for the export dialog to appear
        assertExists(AccessibilityID.Export.dialog, timeout: 5,
                     message: "Export dialog should appear via ⌘⇧E")

        // Verify the confirm and cancel buttons are present
        assertExists(AccessibilityID.Export.dialogConfirm, timeout: 3,
                     message: "Export confirm button should be present")
        assertExists(AccessibilityID.Export.dialogCancel, timeout: 3,
                     message: "Export cancel button should be present")

        captureScreenshot(name: "Export-DialogOpen")

        // Cancel out
        tap(AccessibilityID.Export.dialogCancel)
        assertNotExists(AccessibilityID.Export.dialog, timeout: 3)
    }

    // MARK: - Test: Cancel Export

    /// Open and cancel the export dialog — verify clean dismissal.
    func testCancelExport() throws {
        typeShortcut("e", modifiers: [.command])
        assertExists(AccessibilityID.Export.dialog, timeout: 5)

        tap(AccessibilityID.Export.dialogCancel)
        assertNotExists(AccessibilityID.Export.dialog, timeout: 3)

        // App should still be responsive after cancelling
        assertExists("transport_play", timeout: 3,
                     message: "App should remain responsive after cancelling export")

        captureScreenshot(name: "Export-Cancelled")
    }

    // MARK: - Test: Full Export Flow (with track content)

    /// Complete workflow: Create a track → Trigger export → Verify dialog appears.
    /// We don't actually wait for the full export to complete in smoke tests
    /// (that's the audio regression harness's job), but we verify the UI workflow.
    func testExportWorkflowWithTrack() throws {
        // Create an audio track to ensure there's content to export
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeAudio)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)

        // Open export dialog
        typeShortcut("e", modifiers: [.command])
        assertExists(AccessibilityID.Export.dialog, timeout: 5)

        // The Export button should exist (may be disabled if filename is empty)
        let exportButton = element(AccessibilityID.Export.dialogConfirm)
        XCTAssertTrue(exportButton.exists, "Export confirm button should exist")

        captureScreenshot(name: "Export-WorkflowWithTrack")

        // Cancel — don't actually export in smoke test
        tap(AccessibilityID.Export.dialogCancel)
    }
}
