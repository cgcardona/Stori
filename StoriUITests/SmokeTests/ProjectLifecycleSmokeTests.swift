//
//  ProjectLifecycleSmokeTests.swift
//  StoriUITests
//
//  Smoke tests for project lifecycle: New Project → Save → Verify.
//  These test the most fundamental DAW operation — managing projects.
//

import XCTest

final class ProjectLifecycleSmokeTests: StoriUITestCase {

    // MARK: - Test: New Project via Menu

    /// Verify the New Project workflow can be initiated.
    func testNewProjectViaMenu() throws {
        // Use File > New Project menu (⌘N)
        typeShortcut("n", modifiers: [.command])

        // Wait for the New Project sheet/dialog to appear
        // The new project view should show a text field for the project name
        Thread.sleep(forTimeInterval: 1)

        captureScreenshot(name: "ProjectLifecycle-NewProjectDialog")

        // Press Escape to dismiss (cancel)
        typeShortcut(XCUIKeyboardKey.escape.rawValue, modifiers: [])
        Thread.sleep(forTimeInterval: 0.5)

        // App should still be responsive
        assertExists("transport_play", timeout: 3)
    }

    // MARK: - Test: Save Project

    /// Verify save can be triggered via ⌘S without crashing.
    func testSaveProject() throws {
        // Trigger save — if no project exists, this should be a no-op or create one
        typeShortcut("s", modifiers: [.command])

        // Wait a moment for save operation
        Thread.sleep(forTimeInterval: 1)

        // App should remain responsive
        assertExists("transport_play", timeout: 3,
                     message: "App should remain responsive after save")

        captureScreenshot(name: "ProjectLifecycle-SaveProject")
    }

    // MARK: - Test: Full Lifecycle - New → Edit → Save

    /// Complete workflow: create a new project, add a track, save.
    func testNewProjectAddTrackSave() throws {
        // Step 1: The app may already have a default project open.
        // Add a MIDI track
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeMIDI)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)

        captureScreenshot(name: "ProjectLifecycle-AfterAddTrack")

        // Step 2: Save the project
        typeShortcut("s", modifiers: [.command])
        Thread.sleep(forTimeInterval: 1)

        // Step 3: Verify the app is still responsive
        assertExists("transport_play", timeout: 3)
        assertExists("transport_stop", timeout: 3)

        captureScreenshot(name: "ProjectLifecycle-AfterSave")
    }

    // MARK: - Test: Undo/Redo Basic

    /// Verify undo and redo don't crash.
    func testUndoRedo() throws {
        // Add a track to create an undoable action
        typeShortcut("n", modifiers: [.command, .shift])
        assertExists(AccessibilityID.Track.createDialog, timeout: 5)
        tap(AccessibilityID.Track.createDialogTypeAudio)
        tap(AccessibilityID.Track.createDialogConfirm)
        assertNotExists(AccessibilityID.Track.createDialog, timeout: 5)

        // Undo (⌘Z)
        typeShortcut("z", modifiers: [.command])
        Thread.sleep(forTimeInterval: 0.5)

        // Redo (⌘⇧Z)
        typeShortcut("z", modifiers: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)

        // App should remain stable
        assertExists("transport_play", timeout: 3)

        captureScreenshot(name: "ProjectLifecycle-UndoRedo")
    }
}
