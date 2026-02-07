//
//  TrackDeletionTests.swift
//  StoriTests
//
//  Tests for Issue #122: App crash when deleting recorded MIDI track
//  Verifies that track deletion doesn't trigger unnecessary project reloads
//  and that MetronomeEngine handles graph mutations gracefully
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class TrackDeletionTests: XCTestCase {
    
    var projectManager: ProjectManager!
    var audioEngine: AudioEngine!
    var metronomeEngine: MetronomeEngine!
    
    override func setUp() async throws {
        projectManager = ProjectManager()
        audioEngine = AudioEngine()
        metronomeEngine = MetronomeEngine()
        
        // Install metronome into audio engine
        audioEngine.installMetronome(metronomeEngine)
        
        // Create test project
        try projectManager.createNewProject(name: "TrackDeletionTest", tempo: 120.0)
    }
    
    override func tearDown() async throws {
        audioEngine.stop()
        projectManager = nil
        audioEngine = nil
        metronomeEngine = nil
    }
    
    // MARK: - Track Deletion Tests
    
    /// Test that deleting a track doesn't trigger full project reload
    /// Issue #122: Track deletion was causing infinite "Loading Project..." spinner
    func testDeleteTrackDoesNotTriggerProjectReload() async throws {
        // Given: A project with multiple tracks
        guard var project = projectManager.currentProject else {
            XCTFail("No current project")
            return
        }
        
        let track1 = projectManager.addTrack(name: "Track 1")
        let track2 = projectManager.addMIDITrack(name: "MIDI Track 1")
        
        XCTAssertNotNil(track1)
        XCTAssertNotNil(track2)
        
        project = projectManager.currentProject!
        XCTAssertEqual(project.tracks.count, 2)
        
        let projectIdBeforeDelete = project.id
        let isGraphStableBefore = audioEngine.isGraphStable
        
        // When: We delete a track
        if let trackToDelete = track1 {
            projectManager.removeTrack(trackToDelete.id)
        }
        
        // Then: Project ID should remain the same (no project switch)
        let projectAfterDelete = projectManager.currentProject!
        XCTAssertEqual(projectAfterDelete.id, projectIdBeforeDelete, 
                      "Project ID should not change when deleting a track")
        
        // And: Graph should remain stable (no project reload triggered)
        // Note: In the fixed code, onChange only fires when project ID changes
        XCTAssertTrue(audioEngine.isGraphStable,
                      "Graph should remain stable after track deletion (no reload triggered)")
        
        // And: Track should be removed
        XCTAssertEqual(projectAfterDelete.tracks.count, 1)
        XCTAssertEqual(projectAfterDelete.tracks[0].name, "MIDI Track 1")
    }
    
    /// Test that deleting multiple tracks at once doesn't trigger project reload
    func testDeleteMultipleTracksDoesNotTriggerProjectReload() async throws {
        // Given: A project with multiple tracks
        let track1 = projectManager.addTrack(name: "Track 1")
        let track2 = projectManager.addTrack(name: "Track 2")
        let track3 = projectManager.addTrack(name: "Track 3")
        
        XCTAssertNotNil(track1)
        XCTAssertNotNil(track2)
        XCTAssertNotNil(track3)
        
        let project = projectManager.currentProject!
        XCTAssertEqual(project.tracks.count, 3)
        
        let projectIdBeforeDelete = project.id
        
        // When: We delete multiple tracks
        if let t1 = track1 { projectManager.removeTrack(t1.id) }
        if let t2 = track2 { projectManager.removeTrack(t2.id) }
        
        // Then: Project ID should remain the same
        let projectAfterDelete = projectManager.currentProject!
        XCTAssertEqual(projectAfterDelete.id, projectIdBeforeDelete)
        
        // And: Tracks should be removed
        XCTAssertEqual(projectAfterDelete.tracks.count, 1)
        XCTAssertEqual(projectAfterDelete.tracks[0].name, "Track 3")
    }
    
    /// Test that deleting a MIDI track with recorded data doesn't crash
    /// Issue #122: Deleting recorded MIDI track caused app crash
    func testDeleteMIDITrackWithRecordedData() async throws {
        // Given: A MIDI track with recorded data
        guard let midiTrack = projectManager.addMIDITrack(name: "Recorded MIDI") else {
            XCTFail("Failed to create MIDI track")
            return
        }
        
        // Add a MIDI region with notes (simulating recorded data)
        var region = MIDIRegion(name: "Recording", startBeat: 0, durationBeats: 4)
        region.notes = [
            MIDINote(pitch: 60, velocity: 80, startBeat: 0, durationBeats: 1),
            MIDINote(pitch: 64, velocity: 85, startBeat: 1, durationBeats: 1),
            MIDINote(pitch: 67, velocity: 90, startBeat: 2, durationBeats: 1),
        ]
        projectManager.addMIDIRegion(region, to: midiTrack.id)
        
        let projectBeforeDelete = projectManager.currentProject!
        XCTAssertEqual(projectBeforeDelete.tracks.count, 1)
        XCTAssertEqual(projectBeforeDelete.tracks[0].midiRegions.count, 1)
        XCTAssertEqual(projectBeforeDelete.tracks[0].midiRegions[0].notes.count, 3)
        
        // When: We delete the track (should not crash)
        projectManager.removeTrack(midiTrack.id)
        
        // Then: Track should be deleted without crash
        let projectAfterDelete = projectManager.currentProject!
        XCTAssertEqual(projectAfterDelete.tracks.count, 0)
    }
    
    // MARK: - Metronome Resilience Tests
    
    /// Test that MetronomeEngine.startPlaying() handles detached player node gracefully
    /// Issue #122: Crash occurred when metronome tried to play() on detached node
    func testMetronomeHandlesDetachedPlayerNode() async throws {
        // Given: Metronome is installed and engine is running
        audioEngine.play()
        
        // Give engine time to stabilize
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        XCTAssertTrue(audioEngine.engine.isRunning)
        
        metronomeEngine.isEnabled = true
        
        // When: We simulate a graph mutation by stopping and restarting engine
        // This can leave metronome's player node in a detached state
        audioEngine.engine.stop()
        
        // Try to start metronome while engine is stopped (should not crash)
        metronomeEngine.onTransportPlay()
        
        // Then: Metronome should gracefully handle the invalid state
        // No crash should occur - the guard clauses should prevent play() call
        XCTAssertTrue(true, "Metronome handled detached node gracefully")
    }
    
    /// Test that MetronomeEngine.preparePlayerNode() handles invalid state gracefully
    func testMetronomePrepareHandlesInvalidState() async throws {
        // Given: Metronome is installed but engine is not running
        audioEngine.engine.stop()
        
        // When: We try to prepare the player node (should not crash)
        metronomeEngine.preparePlayerNode()
        
        // Then: No crash should occur
        XCTAssertTrue(true, "Metronome handled invalid state gracefully")
    }
    
    /// Test that MetronomeEngine.performCountIn() handles graph mutations gracefully
    func testMetronomeCountInHandlesGraphMutations() async throws {
        // Given: Metronome is installed and enabled
        metronomeEngine.isEnabled = true
        metronomeEngine.countInEnabled = true
        metronomeEngine.countInBars = 1
        
        // When: Engine is not running and we try count-in (should not crash)
        audioEngine.stop()
        
        await metronomeEngine.performCountIn()
        
        // Then: No crash should occur
        XCTAssertTrue(true, "Count-in handled graph mutations gracefully")
    }
    
    // MARK: - Track Deletion During Playback Tests
    
    /// Test that deleting a track during playback doesn't crash
    /// This was part of Issue #122 - any key press after deletion caused crash
    func testDeleteTrackDuringPlayback() async throws {
        // Given: A project with tracks and playback running
        let track1 = projectManager.addTrack(name: "Track 1")
        let track2 = projectManager.addMIDITrack(name: "MIDI Track 1")
        
        XCTAssertNotNil(track1)
        XCTAssertNotNil(track2)
        
        audioEngine.play()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms for engine to stabilize
        
        // Enable metronome
        metronomeEngine.isEnabled = true
        metronomeEngine.onTransportPlay()
        
        // Give playback time to start
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Note: Transport state may not be .playing immediately in tests (no project loaded yet)
        // The important test is that deletion doesn't crash during any transport state
        
        // When: We delete a track during playback (should not crash)
        if let trackToDelete = track1 {
            projectManager.removeTrack(trackToDelete.id)
        }
        
        // Then: No crash should occur and playback should continue
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        let projectAfterDelete = projectManager.currentProject!
        XCTAssertEqual(projectAfterDelete.tracks.count, 1)
        
        // Stop playback
        audioEngine.stop()
    }
    
    /// Test that deleting a track during playback with metronome doesn't crash
    func testDeleteTrackDuringPlaybackWithMetronome() async throws {
        // Given: A project with playback and metronome running
        let track1 = projectManager.addMIDITrack(name: "MIDI Track 1")
        XCTAssertNotNil(track1)
        
        audioEngine.play()
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Enable metronome and start playback
        metronomeEngine.isEnabled = true
        audioEngine.play()
        metronomeEngine.onTransportPlay()
        
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms - let metronome start
        
        // When: We delete the track while metronome is clicking (should not crash)
        if let trackToDelete = track1 {
            projectManager.removeTrack(trackToDelete.id)
        }
        
        // Then: No crash should occur
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        XCTAssertEqual(projectManager.currentProject!.tracks.count, 0)
        
        // Metronome should still be running
        // Stop transport
        audioEngine.stop()
        metronomeEngine.onTransportStop()
    }
    
    // MARK: - Project ID Stability Tests
    
    /// Test that adding tracks doesn't change project ID
    func testAddTrackDoesNotChangeProjectId() async throws {
        // Given: A project
        let project = projectManager.currentProject!
        let projectIdBefore = project.id
        
        // When: We add a track
        _ = projectManager.addTrack(name: "New Track")
        
        // Then: Project ID should remain the same
        let projectIdAfter = projectManager.currentProject!.id
        XCTAssertEqual(projectIdBefore, projectIdAfter, 
                      "Project ID should not change when adding a track")
    }
    
    /// Test that modifying track properties doesn't change project ID
    func testModifyTrackDoesNotChangeProjectId() async throws {
        // Given: A project with a track
        guard let track = projectManager.addTrack(name: "Track 1") else {
            XCTFail("Failed to create track")
            return
        }
        
        let projectIdBefore = projectManager.currentProject!.id
        
        // When: We modify the track
        projectManager.updateTrackName(track.id, "Modified Track")
        projectManager.updateTrackColor(track.id, .red)
        
        // Then: Project ID should remain the same
        let projectIdAfter = projectManager.currentProject!.id
        XCTAssertEqual(projectIdBefore, projectIdAfter,
                      "Project ID should not change when modifying a track")
    }
}
