//
//  SaveBeforeCloseTests.swift
//  StoriTests
//
//  Integration tests for save-before-quit and save-before-new/open project (Issue #158).
//  Verifies SaveBeforeCloseCoordinator posts .newProject / .openProject when save completes.
//

import XCTest
@testable import Stori

final class SaveBeforeCloseTests: XCTestCase {

    // MARK: - Save then New Project

    /// When requestSaveThenNewProject is used and saveProjectCompleted is posted,
    /// the coordinator should post .newProject so the new-project flow continues.
    func testSaveBeforeCloseCoordinatorPostsNewProjectWhenSaveCompletes() {
        let expectNewProject = expectation(description: "newProject notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .newProject,
            object: nil,
            queue: .main
        ) { _ in
            expectNewProject.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        SaveBeforeCloseCoordinator.shared.requestSaveThenNewProject()
        NotificationCenter.default.post(
            name: .saveProjectCompleted,
            object: nil,
            userInfo: ["success": true]
        )

        wait(for: [expectNewProject], timeout: 2.0)
    }

    /// When requestSaveThenOpenProject is used and saveProjectCompleted is posted,
    /// the coordinator should post .openProject.
    func testSaveBeforeCloseCoordinatorPostsOpenProjectWhenSaveCompletes() {
        let expectOpenProject = expectation(description: "openProject notification")
        let observer = NotificationCenter.default.addObserver(
            forName: .openProject,
            object: nil,
            queue: .main
        ) { _ in
            expectOpenProject.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        SaveBeforeCloseCoordinator.shared.requestSaveThenOpenProject()
        NotificationCenter.default.post(
            name: .saveProjectCompleted,
            object: nil,
            userInfo: ["success": true]
        )

        wait(for: [expectOpenProject], timeout: 2.0)
    }

    /// saveProjectCompleted with success: false still triggers the follow-up action
    /// (e.g. new project sheet) so the user isn't stuck.
    func testSaveBeforeCloseCoordinatorPostsNewProjectEvenWhenSaveFails() {
        let expectNewProject = expectation(description: "newProject after save failed")
        let observer = NotificationCenter.default.addObserver(
            forName: .newProject,
            object: nil,
            queue: .main
        ) { _ in
            expectNewProject.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        SaveBeforeCloseCoordinator.shared.requestSaveThenNewProject()
        NotificationCenter.default.post(
            name: .saveProjectCompleted,
            object: nil,
            userInfo: ["success": false]
        )

        wait(for: [expectNewProject], timeout: 2.0)
    }
}
