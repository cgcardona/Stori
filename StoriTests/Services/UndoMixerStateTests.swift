//
//  UndoMixerStateTests.swift
//  StoriTests
//
//  Comprehensive tests for undo/redo of mixer state changes (Issue #71).
//  Verifies that both project model AND audio engine state are synchronized during undo/redo.
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class UndoMixerStateTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var projectManager: ProjectManager!
    private var audioEngine: AudioEngine!
    private var undoService: UndoService!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        projectManager = ProjectManager()
        audioEngine = AudioEngine()
        undoService = UndoService.shared
        undoService.clearHistory()
        
        // Create test project with tracks
        var project = AudioProject(name: "Undo Test")
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio))
        project.addTrack(AudioTrack(name: "Track 2", trackType: .midi))
        projectManager.currentProject = project
        
        // Load project into audio engine
        audioEngine.loadProject(project)
    }
    
    override func tearDown() async throws {
        audioEngine.cleanup()
        audioEngine = nil
        projectManager = nil
        undoService.clearHistory()
        try await super.tearDown()
    }
    
    // MARK: - Volume Undo Tests (Issue #71 - Core Bug)
    
    func testUndoVolumeChangeRestoresAudioEngineState() {
        guard let trackId = projectManager.currentProject?.tracks.first?.id else {
            XCTFail("No tracks in project")
            return
        }
        
        let oldVolume: Float = 0.8
        let newVolume: Float = 0.5
        
        // Set initial volume
        audioEngine.updateTrackVolume(trackId: trackId, volume: oldVolume)
        
        // Verify initial state
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), oldVolume, accuracy: 0.01)
        
        // Change volume and register undo
        undoService.registerVolumeChange(
            trackId,
            from: oldVolume,
            to: newVolume,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        audioEngine.updateTrackVolume(trackId: trackId, volume: newVolume)
        
        // Verify changed state
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), newVolume, accuracy: 0.01)
        XCTAssertEqual(projectManager.currentProject?.tracks.first?.mixerSettings.volume, newVolume, accuracy: 0.01)
        
        // **CRITICAL TEST**: Undo should restore BOTH model AND audio engine
        undoService.undo()
        
        // Assert audio engine state restored (fixes Issue #71)
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), oldVolume, accuracy: 0.01,
                      "Undo failed to restore audio engine volume - Issue #71")
        
        // Assert model state restored
        XCTAssertEqual(projectManager.currentProject?.tracks.first?.mixerSettings.volume, oldVolume, accuracy: 0.01,
                      "Undo failed to restore project model volume")
    }
    
    func testRedoVolumeChangeRestoresAudioEngineState() {
        guard let trackId = projectManager.currentProject?.tracks.first?.id else {
            XCTFail("No tracks in project")
            return
        }
        
        let oldVolume: Float = 0.8
        let newVolume: Float = 0.5
        
        // Setup and register change
        audioEngine.updateTrackVolume(trackId: trackId, volume: oldVolume)
        undoService.registerVolumeChange(
            trackId,
            from: oldVolume,
            to: newVolume,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        audioEngine.updateTrackVolume(trackId: trackId, volume: newVolume)
        
        // Undo
        undoService.undo()
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), oldVolume, accuracy: 0.01)
        
        // **CRITICAL TEST**: Redo should restore BOTH model AND audio engine
        undoService.redo()
        
        // Assert audio engine state restored (fixes Issue #71)
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), newVolume, accuracy: 0.01,
                      "Redo failed to restore audio engine volume - Issue #71")
        
        // Assert model state restored
        XCTAssertEqual(projectManager.currentProject?.tracks.first?.mixerSettings.volume, newVolume, accuracy: 0.01,
                      "Redo failed to restore project model volume")
    }
    
    // MARK: - Pan Undo Tests
    
    func testUndoPanChangeRestoresAudioEngineState() {
        guard let trackId = projectManager.currentProject?.tracks.first?.id else {
            XCTFail("No tracks in project")
            return
        }
        
        let oldPan: Float = 0.0
        let newPan: Float = -0.5
        
        audioEngine.updateTrackPan(trackId: trackId, pan: oldPan)
        
        undoService.registerPanChange(
            trackId,
            from: oldPan,
            to: newPan,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        audioEngine.updateTrackPan(trackId: trackId, pan: newPan)
        
        XCTAssertEqual(audioEngine.getTrackPan(trackId: trackId), newPan, accuracy: 0.01)
        
        // Undo
        undoService.undo()
        
        XCTAssertEqual(audioEngine.getTrackPan(trackId: trackId), oldPan, accuracy: 0.01,
                      "Undo failed to restore audio engine pan - Issue #71")
        XCTAssertEqual(projectManager.currentProject?.tracks.first?.mixerSettings.pan, oldPan, accuracy: 0.01)
    }
    
    // MARK: - Mute Undo Tests
    
    func testUndoMuteToggleRestoresAudioEngineState() {
        guard let trackId = projectManager.currentProject?.tracks.first?.id else {
            XCTFail("No tracks in project")
            return
        }
        
        let wasMuted = false
        let newMuted = true
        
        audioEngine.updateTrackMute(trackId: trackId, isMuted: wasMuted)
        
        undoService.registerMuteToggle(
            trackId,
            wasMuted: wasMuted,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        audioEngine.updateTrackMute(trackId: trackId, isMuted: newMuted)
        
        XCTAssertTrue(audioEngine.getTrackMute(trackId: trackId))
        
        // Undo
        undoService.undo()
        
        XCTAssertFalse(audioEngine.getTrackMute(trackId: trackId),
                       "Undo failed to restore audio engine mute state - Issue #71")
        XCTAssertFalse(projectManager.currentProject?.tracks.first?.mixerSettings.isMuted ?? true)
    }
    
    // MARK: - Solo Undo Tests
    
    func testUndoSoloToggleRestoresAudioEngineState() {
        guard let trackId = projectManager.currentProject?.tracks.first?.id else {
            XCTFail("No tracks in project")
            return
        }
        
        let wasSolo = false
        let newSolo = true
        
        audioEngine.updateTrackSolo(trackId: trackId, isSolo: wasSolo)
        
        undoService.registerSoloToggle(
            trackId,
            wasSolo: wasSolo,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        audioEngine.updateTrackSolo(trackId: trackId, isSolo: newSolo)
        
        XCTAssertTrue(audioEngine.getTrackSolo(trackId: trackId))
        
        // Undo
        undoService.undo()
        
        XCTAssertFalse(audioEngine.getTrackSolo(trackId: trackId),
                       "Undo failed to restore audio engine solo state - Issue #71")
        XCTAssertFalse(projectManager.currentProject?.tracks.first?.mixerSettings.isSolo ?? true)
    }
    
    // MARK: - Multiple Undo/Redo Tests
    
    func testMultipleUndoRedoMaintainsSynchronization() {
        guard let trackId = projectManager.currentProject?.tracks.first?.id else {
            XCTFail("No tracks in project")
            return
        }
        
        let volumes: [Float] = [0.8, 0.6, 0.4, 0.2]
        
        // Apply multiple volume changes
        for i in 0..<(volumes.count - 1) {
            undoService.registerVolumeChange(
                trackId,
                from: volumes[i],
                to: volumes[i + 1],
                projectManager: projectManager,
                audioEngine: audioEngine
            )
            audioEngine.updateTrackVolume(trackId: trackId, volume: volumes[i + 1])
        }
        
        // Final volume should be 0.2
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), 0.2, accuracy: 0.01)
        
        // Undo all changes
        undoService.undo() // 0.2 -> 0.4
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), 0.4, accuracy: 0.01)
        
        undoService.undo() // 0.4 -> 0.6
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), 0.6, accuracy: 0.01)
        
        undoService.undo() // 0.6 -> 0.8
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), 0.8, accuracy: 0.01)
        
        // Redo all changes
        undoService.redo() // 0.8 -> 0.6
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), 0.6, accuracy: 0.01)
        
        undoService.redo() // 0.6 -> 0.4
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), 0.4, accuracy: 0.01)
        
        undoService.redo() // 0.4 -> 0.2
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), 0.2, accuracy: 0.01)
    }
    
    // MARK: - Mixed Operation Undo Tests
    
    func testUndoMixedMixerOperationsMaintainsSynchronization() {
        guard let trackId = projectManager.currentProject?.tracks.first?.id else {
            XCTFail("No tracks in project")
            return
        }
        
        // Volume change
        undoService.registerVolumeChange(
            trackId,
            from: 0.8,
            to: 0.5,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        audioEngine.updateTrackVolume(trackId: trackId, volume: 0.5)
        
        // Pan change
        undoService.registerPanChange(
            trackId,
            from: 0.0,
            to: -0.5,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        audioEngine.updateTrackPan(trackId: trackId, pan: -0.5)
        
        // Mute toggle
        undoService.registerMuteToggle(
            trackId,
            wasMuted: false,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        audioEngine.updateTrackMute(trackId: trackId, isMuted: true)
        
        // Verify final state
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), 0.5, accuracy: 0.01)
        XCTAssertEqual(audioEngine.getTrackPan(trackId: trackId), -0.5, accuracy: 0.01)
        XCTAssertTrue(audioEngine.getTrackMute(trackId: trackId))
        
        // Undo mute
        undoService.undo()
        XCTAssertFalse(audioEngine.getTrackMute(trackId: trackId))
        
        // Undo pan
        undoService.undo()
        XCTAssertEqual(audioEngine.getTrackPan(trackId: trackId), 0.0, accuracy: 0.01)
        
        // Undo volume
        undoService.undo()
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), 0.8, accuracy: 0.01)
    }
    
    // MARK: - Edge Case Tests
    
    func testUndoWithNoAudioEngineDoesNotCrash() {
        guard let trackId = projectManager.currentProject?.tracks.first?.id else {
            XCTFail("No tracks in project")
            return
        }
        
        // Register undo without audio engine
        undoService.registerVolumeChange(
            trackId,
            from: 0.8,
            to: 0.5,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        
        // Destroy audio engine (weak reference becomes nil)
        audioEngine.cleanup()
        audioEngine = nil
        
        // Undo should not crash
        undoService.undo()
        
        // Model should still be updated
        XCTAssertEqual(projectManager.currentProject?.tracks.first?.mixerSettings.volume, 0.8, accuracy: 0.01)
    }
    
    func testUndoAfterProjectReloadMaintainsSynchronization() {
        guard let trackId = projectManager.currentProject?.tracks.first?.id else {
            XCTFail("No tracks in project")
            return
        }
        
        // Register volume change
        undoService.registerVolumeChange(
            trackId,
            from: 0.8,
            to: 0.5,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        audioEngine.updateTrackVolume(trackId: trackId, volume: 0.5)
        
        // Reload project (simulates save/load)
        if let project = projectManager.currentProject {
            audioEngine.loadProject(project)
        }
        
        // Undo should still work after reload
        undoService.undo()
        
        XCTAssertEqual(audioEngine.getTrackVolume(trackId: trackId), 0.8, accuracy: 0.01)
    }
}
