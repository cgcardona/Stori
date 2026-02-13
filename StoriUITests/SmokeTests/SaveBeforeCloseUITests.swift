//
//  SaveBeforeCloseUITests.swift
//  StoriUITests
//
//  Regression tests for save-before-quit and save-before-new-project (Issue #158).
//  Ensures the app prompts to save when quitting or opening a new project with unsaved changes.
//

import XCTest

final class SaveBeforeCloseUITests: StoriUITestCase {

    // MARK: - Helpers

    /// Create unsaved state by adding a track (no save). STORI_UI_TEST creates a project on launch.
    private func makeUnsavedChange() {
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeMIDI)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)
    }

    // MARK: - New Project with unsaved changes

    /// Regression (Issue #158): With unsaved changes, Cmd+N shows Save / Don't Save / Cancel dialog.
    func testNewProjectWithUnsavedChangesShowsSavePrompt() throws {
        makeUnsavedChange()
        typeShortcut("n", modifiers: [.command])
        Thread.sleep(forTimeInterval: 0.8)
        assertExists(
            AccessibilityID.Project.saveBeforeQuitDontSave,
            timeout: 3,
            message: "Save-before-new-project dialog should appear when there are unsaved changes"
        )
        assertExists(AccessibilityID.Project.saveBeforeQuitSave, timeout: 1)
        assertExists(AccessibilityID.Project.saveBeforeQuitCancel, timeout: 1)
    }

    /// With unsaved changes, choosing Don't Save on the prompt proceeds to New Project flow.
    func testNewProjectDonSaveProceedsToNewProjectSheet() throws {
        makeUnsavedChange()
        typeShortcut("n", modifiers: [.command])
        assertExists(AccessibilityID.Project.saveBeforeQuitDontSave, timeout: 3)
        tap(AccessibilityID.Project.saveBeforeQuitDontSave)
        Thread.sleep(forTimeInterval: 0.5)
        // New project sheet or standalone window should show (e.g. project name field or Create button)
        let hasNewProjectUI = app.textFields["project.name_field"].waitForExistence(timeout: 2)
            || app.buttons.matching(identifier: "Create Project").firstMatch.waitForExistence(timeout: 2)
        XCTAssertTrue(hasNewProjectUI, "After Don't Save, New Project UI should appear")
    }

    /// With unsaved changes, choosing Cancel on the prompt keeps current project (no new project sheet).
    func testNewProjectCancelKeepsCurrentProject() throws {
        makeUnsavedChange()
        typeShortcut("n", modifiers: [.command])
        assertExists(AccessibilityID.Project.saveBeforeQuitCancel, timeout: 3)
        tap(AccessibilityID.Project.saveBeforeQuitCancel)
        Thread.sleep(forTimeInterval: 0.3)
        assertExists("transport_play", timeout: 2, message: "App should still show DAW after Cancel")
    }

    // MARK: - Quit with unsaved changes

    /// Regression (Issue #158): With unsaved changes, Cmd+Q shows Save / Don't Save / Cancel dialog.
    func testQuitWithUnsavedChangesShowsSavePrompt() throws {
        makeUnsavedChange()
        typeShortcut("q", modifiers: [.command])
        Thread.sleep(forTimeInterval: 0.8)
        assertExists(
            AccessibilityID.Project.saveBeforeQuitDontSave,
            timeout: 3,
            message: "Save-before-quit dialog should appear when there are unsaved changes"
        )
        assertExists(AccessibilityID.Project.saveBeforeQuitSave, timeout: 1)
        assertExists(AccessibilityID.Project.saveBeforeQuitCancel, timeout: 1)
    }

    /// With unsaved changes, choosing Cancel on quit keeps the app running.
    func testQuitCancelKeepsAppRunning() throws {
        makeUnsavedChange()
        typeShortcut("q", modifiers: [.command])
        assertExists(AccessibilityID.Project.saveBeforeQuitCancel, timeout: 3)
        tap(AccessibilityID.Project.saveBeforeQuitCancel)
        Thread.sleep(forTimeInterval: 0.3)
        assertExists("transport_play", timeout: 2, message: "App should still be running after Cancel")
    }
}
