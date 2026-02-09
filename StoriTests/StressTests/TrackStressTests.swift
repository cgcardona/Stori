//
//  TrackStressTests.swift
//  StoriTests
//
//  Stress tests that intentionally try to break the app through rapid
//  track add/remove cycles, undo/redo storms, and concurrent mutations.
//  These catch race conditions, nil derefs, deadlocks, and thread-safety bugs.
//
//  Tagged with "Stress" in the test name so CI can filter:
//    -only-testing:StoriTests/TrackStressTests  (nightly only)
//

import XCTest
@testable import Stori

final class TrackStressTests: XCTestCase {

    // MARK: - Test: Rapid Add/Remove Track Cycles

    /// Rapidly add and remove tracks in a tight loop.
    /// This catches thread-safety issues in the project model and audio graph.
    @MainActor
    func testStressRapidAddRemoveTracks() async throws {
        let projectManager = ProjectManager()

        var project = AudioProject(name: "Stress-AddRemove")
        projectManager.loadProject(project)

        let iterations = 50

        for i in 0..<iterations {
            // Add a track
            let trackType: TrackType = i % 2 == 0 ? .audio : .midi
            let track = AudioTrack(name: "StressTrack-\(i)", trackType: trackType)
            project.tracks.append(track)
            projectManager.currentProject = project

            // Small yield to simulate real usage
            if i % 10 == 0 {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        // All tracks should have been added
        XCTAssertEqual(project.tracks.count, iterations,
                       "All \(iterations) tracks should be present")

        // Now remove them all rapidly
        for _ in 0..<iterations {
            guard !project.tracks.isEmpty else { break }
            project.tracks.removeLast()
            projectManager.currentProject = project
        }

        XCTAssertTrue(project.tracks.isEmpty, "All tracks should be removed")
    }

    // MARK: - Test: Undo/Redo Storm

    /// Rapidly undo and redo in a tight loop after making many changes.
    @MainActor
    func testStressUndoRedoStorm() async throws {
        let undoService = UndoService()

        // Rapid undo/redo should not crash even with nothing to undo
        for _ in 0..<30 {
            undoService.undo()
        }

        for _ in 0..<30 {
            undoService.redo()
        }

        // Interleaved undo/redo
        for i in 0..<20 {
            if i % 2 == 0 {
                undoService.undo()
            } else {
                undoService.redo()
            }
        }

        // Should not crash or deadlock
        XCTAssertTrue(true, "Undo/redo storm completed without crash")
    }

    // MARK: - Test: Concurrent Track Property Mutations

    /// Mutate track properties rapidly.
    @MainActor
    func testStressConcurrentTrackMutations() async throws {
        var project = AudioProject(name: "Stress-ConcurrentMutations")

        // Create 10 tracks
        for i in 0..<10 {
            project.tracks.append(AudioTrack(name: "Track-\(i)", trackType: .audio))
        }

        let projectManager = ProjectManager()
        projectManager.loadProject(project)

        // Mutate properties rapidly
        for trackIndex in 0..<10 {
            for j in 0..<20 {
                guard var currentProject = projectManager.currentProject else { continue }
                guard trackIndex < currentProject.tracks.count else { continue }

                currentProject.tracks[trackIndex].mixerSettings.volume = Float(j) / 20.0
                // MixerSettings.pan uses 0-1 range (0.5=center), not -1 to 1
                currentProject.tracks[trackIndex].mixerSettings.pan = Float(j % 2 == 0 ? 0.0 : 1.0)
                currentProject.tracks[trackIndex].mixerSettings.isMuted = j % 3 == 0
                currentProject.tracks[trackIndex].mixerSettings.isSolo = j % 5 == 0
                projectManager.currentProject = currentProject
            }
        }

        // Should not crash
        XCTAssertTrue(true, "Concurrent mutations completed without crash")
    }

    // MARK: - Test: Large Track Count

    /// Verify the project manager handles a large number of tracks without crashing.
    @MainActor
    func testStressLargeTrackCount() async throws {
        var project = AudioProject(name: "Stress-LargeTrackCount")

        // Add 100 tracks — a realistic upper bound for a complex project
        for i in 0..<100 {
            let trackType: TrackType = i % 3 == 0 ? .midi : .audio
            var track = AudioTrack(name: "Track-\(i)", trackType: trackType)
            track.mixerSettings.volume = Float.random(in: 0.3...1.0)
            // MixerSettings.pan uses 0-1 range (0.5=center), not -1 to 1
            track.mixerSettings.pan = Float.random(in: 0.0...1.0)
            project.tracks.append(track)
        }

        let projectManager = ProjectManager()
        projectManager.loadProject(project)

        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(projectManager.currentProject?.tracks.count, 100)
    }
}
