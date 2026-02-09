//
//  UndoService.swift
//  Stori
//
//  Centralized undo/redo service for the DAW.
//  Provides a clean API for registering undoable operations across the app.
//

import Foundation
import SwiftUI

// MARK: - Undo Service

/// Centralized service for managing undo/redo operations.
/// Wraps the native UndoManager with a cleaner API for DAW operations.
@MainActor
@Observable
class UndoService {
    
    // MARK: - Singleton
    
    static let shared = UndoService()
    
    // MARK: - Properties
    
    /// The underlying UndoManager
    @ObservationIgnored
    let undoManager = UndoManager()
    
    /// Whether undo is available
    var canUndo: Bool {
        undoManager.canUndo
    }
    
    /// Whether redo is available
    var canRedo: Bool {
        undoManager.canRedo
    }
    
    /// Name of the current undo action
    var undoActionName: String? {
        undoManager.canUndo ? undoManager.undoActionName : nil
    }
    
    /// Name of the current redo action
    var redoActionName: String? {
        undoManager.canRedo ? undoManager.redoActionName : nil
    }
    
    /// Number of pending undo actions (for UI indicators)
    private(set) var undoCount: Int = 0
    
    // MARK: - Undo Groups
    
    /// Whether we're currently in an undo group
    private var isGrouping: Bool = false
    
    // MARK: - Initialization
    
    init() {
        // Configure undo manager
        undoManager.levelsOfUndo = 100  // Maximum undo steps
        undoManager.groupsByEvent = true
    }
    
    
    // MARK: - Core Undo API
    
    /// Register an undoable operation with automatic redo support.
    /// - Parameters:
    ///   - actionName: Human-readable name for the action (shown in Edit menu)
    ///   - undo: Closure to execute when undoing
    ///   - redo: Closure to execute when redoing
    func registerUndo(actionName: String, undo: @escaping () -> Void, redo: @escaping () -> Void) {
        undoManager.registerUndo(withTarget: self) { [weak self] _ in
            undo()
            // Re-register for redo
            self?.undoManager.registerUndo(withTarget: self ?? UndoService.shared) { _ in
                redo()
            }
        }
        undoManager.setActionName(actionName)
        undoCount += 1
    }
    
    /// Perform undo
    func undo() {
        guard canUndo else { return }
        undoManager.undo()
        undoCount = max(0, undoCount - 1)
    }
    
    /// Perform redo
    func redo() {
        guard canRedo else { return }
        undoManager.redo()
        undoCount += 1
    }
    
    /// Clear all undo/redo history (e.g., when loading a new project)
    func clearHistory() {
        undoManager.removeAllActions()
        undoCount = 0
    }
    
    // MARK: - Grouped Operations
    
    /// Begin a group of related operations that should undo together.
    /// Must be paired with endGroup().
    func beginGroup(named name: String) {
        undoManager.beginUndoGrouping()
        undoManager.setActionName(name)
        isGrouping = true
    }
    
    /// End a group of related operations.
    func endGroup() {
        guard isGrouping else { return }
        undoManager.endUndoGrouping()
        isGrouping = false
        undoCount += 1
    }
    
    /// Perform a block of operations as a single undoable group.
    func withGroup(named name: String, _ operations: () -> Void) {
        beginGroup(named: name)
        operations()
        endGroup()
    }
    
    // MARK: - Cleanup
}

// MARK: - Track Operations

extension UndoService {
    
    /// Register undo for adding a track
    func registerAddTrack(_ track: AudioTrack, projectManager: ProjectManager, audioEngine: AudioEngine) {
        let trackCopy = track
        
        registerUndo(actionName: "Add Track") { [weak projectManager, weak audioEngine] in
            // Undo: Remove the track
            guard var project = projectManager?.currentProject else { return }
            project.tracks.removeAll { $0.id == trackCopy.id }
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
            InstrumentManager.shared.trackRemoved(trackId: trackCopy.id)
        } redo: { [weak projectManager, weak audioEngine] in
            // Redo: Add the track back
            guard var project = projectManager?.currentProject else { return }
            project.tracks.append(trackCopy)
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
    
    /// Register undo for deleting a track
    func registerDeleteTrack(_ track: AudioTrack, at index: Int, projectManager: ProjectManager, audioEngine: AudioEngine) {
        let trackCopy = track
        let deletedIndex = index
        
        registerUndo(actionName: "Delete Track") { [weak projectManager, weak audioEngine] in
            // Undo: Restore the track
            guard var project = projectManager?.currentProject else { return }
            project.tracks.insert(trackCopy, at: min(deletedIndex, project.tracks.count))
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            
            // Reload audio engine to add the track back
            audioEngine?.loadProject(project)
            
            // Notify that project updated
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        } redo: { [weak projectManager, weak audioEngine] in
            // Redo: Delete again
            guard var project = projectManager?.currentProject else { return }
            project.tracks.removeAll { $0.id == trackCopy.id }
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            
            // Reload audio engine to remove the track
            audioEngine?.loadProject(project)
            
            // Notify that project updated
            NotificationCenter.default.post(name: .projectUpdated, object: project)
            
            // Notify InstrumentManager to remove the track's instrument
            InstrumentManager.shared.trackRemoved(trackId: trackCopy.id)
        }
    }
    
    /// Register undo for renaming a track
    func registerRenameTrack(_ trackId: UUID, oldName: String, newName: String, projectManager: ProjectManager) {
        registerUndo(actionName: "Rename Track") { [weak projectManager] in
            // Undo: Restore old name
            if let index = projectManager?.currentProject?.tracks.firstIndex(where: { $0.id == trackId }) {
                projectManager?.currentProject?.tracks[index].name = oldName
            }
        } redo: { [weak projectManager] in
            // Redo: Apply new name
            if let index = projectManager?.currentProject?.tracks.firstIndex(where: { $0.id == trackId }) {
                projectManager?.currentProject?.tracks[index].name = newName
            }
        }
    }
    
    /// Register undo for moving/reordering a track
    func registerMoveTrack(from sourceIndex: Int, to destIndex: Int, projectManager: ProjectManager, audioEngine: AudioEngine) {
        registerUndo(actionName: "Move Track") { [weak projectManager, weak audioEngine] in
            // Undo: Move back to original position
            guard var project = projectManager?.currentProject,
                  destIndex < project.tracks.count else { return }
            let track = project.tracks.remove(at: destIndex)
            project.tracks.insert(track, at: sourceIndex)
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        } redo: { [weak projectManager, weak audioEngine] in
            // Redo: Move to new position again
            guard var project = projectManager?.currentProject,
                  sourceIndex < project.tracks.count else { return }
            let track = project.tracks.remove(at: sourceIndex)
            project.tracks.insert(track, at: destIndex)
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
    
    /// Register undo for duplicating a track
    func registerDuplicateTrack(_ originalTrack: AudioTrack, duplicatedTrack: AudioTrack, at index: Int, projectManager: ProjectManager, audioEngine: AudioEngine) {
        let duplicatedCopy = duplicatedTrack
        
        registerUndo(actionName: "Duplicate Track") { [weak projectManager, weak audioEngine] in
            // Undo: Remove the duplicated track
            guard var project = projectManager?.currentProject else { return }
            project.tracks.removeAll { $0.id == duplicatedCopy.id }
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
            InstrumentManager.shared.trackRemoved(trackId: duplicatedCopy.id)
        } redo: { [weak projectManager, weak audioEngine] in
            // Redo: Add the duplicated track back
            guard var project = projectManager?.currentProject else { return }
            project.tracks.insert(duplicatedCopy, at: min(index, project.tracks.count))
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
    
    /// Register undo for track color change
    func registerTrackColorChange(_ trackId: UUID, from oldColor: TrackColor, to newColor: TrackColor, projectManager: ProjectManager) {
        registerUndo(actionName: "Change Track Color") { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let index = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[index].color = oldColor
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        } redo: { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let index = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[index].color = newColor
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
    
    /// Register undo for track icon change
    func registerTrackIconChange(_ trackId: UUID, from oldIcon: String, to newIcon: String, projectManager: ProjectManager) {
        registerUndo(actionName: "Change Track Icon") { [weak projectManager] in
            projectManager?.updateTrackIcon(trackId, oldIcon)
            projectManager?.hasUnsavedChanges = true
        } redo: { [weak projectManager] in
            projectManager?.updateTrackIcon(trackId, newIcon)
            projectManager?.hasUnsavedChanges = true
        }
    }
}

// MARK: - Region Operations

extension UndoService {
    
    /// Register undo for adding an audio region
    func registerAddAudioRegion(_ region: AudioRegion, to trackId: UUID, projectManager: ProjectManager, audioEngine: AudioEngine) {
        let regionCopy = region
        
        registerUndo(actionName: "Add Audio Region") { [weak projectManager, weak audioEngine] in
            // Undo: Remove the region
            guard var project = projectManager?.currentProject,
                  let index = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[index].regions.removeAll { $0.id == regionCopy.id }
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        } redo: { [weak projectManager, weak audioEngine] in
            // Redo: Add the region back
            guard var project = projectManager?.currentProject,
                  let index = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[index].regions.append(regionCopy)
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
    
    /// Register undo for deleting an audio region
    func registerDeleteAudioRegion(_ region: AudioRegion, from trackId: UUID, projectManager: ProjectManager, audioEngine: AudioEngine) {
        let regionCopy = region
        
        registerUndo(actionName: "Delete Audio Region") { [weak projectManager, weak audioEngine] in
            // Undo: Restore the region
            guard var project = projectManager?.currentProject,
                  let index = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[index].regions.append(regionCopy)
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        } redo: { [weak projectManager, weak audioEngine] in
            // Redo: Delete again
            guard var project = projectManager?.currentProject,
                  let index = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[index].regions.removeAll { $0.id == regionCopy.id }
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
    
    /// Register undo for moving a region
    func registerMoveRegion(_ regionId: UUID, in trackId: UUID, from oldStartBeat: Double, to newStartBeat: Double, projectManager: ProjectManager) {
        registerUndo(actionName: "Move Region") { [weak projectManager] in
            // Undo: Restore original position
            if let trackIndex = projectManager?.currentProject?.tracks.firstIndex(where: { $0.id == trackId }),
               let regionIndex = projectManager?.currentProject?.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                projectManager?.currentProject?.tracks[trackIndex].regions[regionIndex].startBeat = oldStartBeat
            }
        } redo: { [weak projectManager] in
            // Redo: Apply new position
            if let trackIndex = projectManager?.currentProject?.tracks.firstIndex(where: { $0.id == trackId }),
               let regionIndex = projectManager?.currentProject?.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                projectManager?.currentProject?.tracks[trackIndex].regions[regionIndex].startBeat = newStartBeat
            }
        }
    }
    
    /// Register undo for resizing a region
    func registerResizeRegion(_ regionId: UUID, in trackId: UUID, oldStartBeat: Double, oldDurationBeats: Double, newStartBeat: Double, newDurationBeats: Double, projectManager: ProjectManager) {
        registerUndo(actionName: "Resize Region") { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) else { return }
            project.tracks[trackIndex].regions[regionIndex].startBeat = oldStartBeat
            project.tracks[trackIndex].regions[regionIndex].durationBeats = oldDurationBeats
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        } redo: { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) else { return }
            project.tracks[trackIndex].regions[regionIndex].startBeat = newStartBeat
            project.tracks[trackIndex].regions[regionIndex].durationBeats = newDurationBeats
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        }
    }
    
    /// Register undo for splitting a region
    func registerSplitRegion(originalRegion: AudioRegion, leftRegion: AudioRegion, rightRegion: AudioRegion, in trackId: UUID, projectManager: ProjectManager, audioEngine: AudioEngine) {
        let original = originalRegion
        let left = leftRegion
        let right = rightRegion
        
        registerUndo(actionName: "Split Region") { [weak projectManager, weak audioEngine] in
            // Undo: Remove split regions, restore original
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[trackIndex].regions.removeAll { $0.id == left.id || $0.id == right.id }
            project.tracks[trackIndex].regions.append(original)
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        } redo: { [weak projectManager, weak audioEngine] in
            // Redo: Remove original, add split regions
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[trackIndex].regions.removeAll { $0.id == original.id }
            project.tracks[trackIndex].regions.append(contentsOf: [left, right])
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
    
    /// Register undo for duplicating a region
    func registerDuplicateRegion(originalRegion: AudioRegion, duplicatedRegion: AudioRegion, in trackId: UUID, projectManager: ProjectManager, audioEngine: AudioEngine) {
        let duplicated = duplicatedRegion
        
        registerUndo(actionName: "Duplicate Region") { [weak projectManager, weak audioEngine] in
            // Undo: Remove the duplicated region
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[trackIndex].regions.removeAll { $0.id == duplicated.id }
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        } redo: { [weak projectManager, weak audioEngine] in
            // Redo: Add the duplicated region back
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[trackIndex].regions.append(duplicated)
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
}

// MARK: - Mixer Operations

extension UndoService {
    
    /// Register undo for volume change
    func registerVolumeChange(_ trackId: UUID, from oldVolume: Float, to newVolume: Float, projectManager: ProjectManager, audioEngine: AudioEngine) {
        registerUndo(actionName: "Change Volume") { [weak audioEngine] in
            // Undo: Restore old volume via audio engine (updates both model and audio - fixes Issue #71)
            audioEngine?.updateTrackVolume(trackId: trackId, volume: oldVolume)
        } redo: { [weak audioEngine] in
            // Redo: Apply new volume via audio engine (updates both model and audio - fixes Issue #71)
            audioEngine?.updateTrackVolume(trackId: trackId, volume: newVolume)
        }
    }
    
    /// Register undo for pan change
    func registerPanChange(_ trackId: UUID, from oldPan: Float, to newPan: Float, projectManager: ProjectManager, audioEngine: AudioEngine) {
        registerUndo(actionName: "Change Pan") { [weak audioEngine] in
            // Undo: Restore old pan via audio engine (updates both model and audio - fixes Issue #71)
            audioEngine?.updateTrackPan(trackId: trackId, pan: oldPan)
        } redo: { [weak audioEngine] in
            // Redo: Apply new pan via audio engine (updates both model and audio - fixes Issue #71)
            audioEngine?.updateTrackPan(trackId: trackId, pan: newPan)
        }
    }
    
    /// Register undo for mute toggle
    func registerMuteToggle(_ trackId: UUID, wasMuted: Bool, projectManager: ProjectManager, audioEngine: AudioEngine) {
        registerUndo(actionName: wasMuted ? "Unmute Track" : "Mute Track") { [weak audioEngine] in
            // Undo: Restore old mute state via audio engine (updates both model and audio - fixes Issue #71)
            audioEngine?.updateTrackMute(trackId: trackId, isMuted: wasMuted)
        } redo: { [weak audioEngine] in
            // Redo: Apply new mute state via audio engine (updates both model and audio - fixes Issue #71)
            audioEngine?.updateTrackMute(trackId: trackId, isMuted: !wasMuted)
        }
    }
    
    /// Register undo for solo toggle
    func registerSoloToggle(_ trackId: UUID, wasSolo: Bool, projectManager: ProjectManager, audioEngine: AudioEngine) {
        registerUndo(actionName: wasSolo ? "Unsolo Track" : "Solo Track") { [weak audioEngine] in
            // Undo: Restore old solo state via audio engine (updates both model and audio - fixes Issue #71)
            audioEngine?.updateTrackSolo(trackId: trackId, isSolo: wasSolo)
        } redo: { [weak audioEngine] in
            // Redo: Apply new solo state via audio engine (updates both model and audio - fixes Issue #71)
            audioEngine?.updateTrackSolo(trackId: trackId, isSolo: !wasSolo)
        }
    }
    
    /// Register undo for toggling plugin bypass (AU plugins use live audio engine state)
    func registerTogglePluginBypass(_ trackId: UUID, slotIndex: Int, wasBypassed: Bool, projectManager: ProjectManager, audioEngine: AudioEngine) {
        registerUndo(actionName: wasBypassed ? "Enable Plugin" : "Bypass Plugin") { [weak audioEngine] in
            // Undo: restore original bypass state
            audioEngine?.setPluginBypass(trackId: trackId, slot: slotIndex, bypassed: wasBypassed)
        } redo: { [weak audioEngine] in
            // Redo: toggle bypass state
            audioEngine?.setPluginBypass(trackId: trackId, slot: slotIndex, bypassed: !wasBypassed)
        }
    }
}

// MARK: - MIDI Operations

extension UndoService {
    
    /// Register undo for adding a MIDI region
    func registerAddMIDIRegion(_ region: MIDIRegion, to trackId: UUID, projectManager: ProjectManager, audioEngine: AudioEngine) {
        let regionCopy = region
        
        registerUndo(actionName: "Add MIDI Region") { [weak projectManager, weak audioEngine] in
            // Undo: Remove the region
            guard var project = projectManager?.currentProject,
                  let index = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[index].midiRegions.removeAll { $0.id == regionCopy.id }
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        } redo: { [weak projectManager, weak audioEngine] in
            // Redo: Add the region back
            guard var project = projectManager?.currentProject,
                  let index = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[index].midiRegions.append(regionCopy)
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
    
    /// Register undo for deleting a MIDI region
    func registerDeleteMIDIRegion(_ region: MIDIRegion, from trackId: UUID, projectManager: ProjectManager, audioEngine: AudioEngine) {
        let regionCopy = region
        
        registerUndo(actionName: "Delete MIDI Region") { [weak projectManager, weak audioEngine] in
            // Undo: Restore the region
            guard var project = projectManager?.currentProject,
                  let index = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[index].midiRegions.append(regionCopy)
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        } redo: { [weak projectManager, weak audioEngine] in
            // Redo: Delete again
            guard var project = projectManager?.currentProject,
                  let index = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[index].midiRegions.removeAll { $0.id == regionCopy.id }
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
    
    /// Register undo for adding MIDI notes
    func registerAddMIDINotes(_ notes: [MIDINote], to regionId: UUID, in trackId: UUID, projectManager: ProjectManager) {
        let notesCopy = notes
        
        registerUndo(actionName: notes.count == 1 ? "Add Note" : "Add Notes") { [weak projectManager] in
            // Undo: Remove the notes
            if let trackIndex = projectManager?.currentProject?.tracks.firstIndex(where: { $0.id == trackId }),
               let regionIndex = projectManager?.currentProject?.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                let noteIds = Set(notesCopy.map { $0.id })
                projectManager?.currentProject?.tracks[trackIndex].midiRegions[regionIndex].notes.removeAll { noteIds.contains($0.id) }
            }
        } redo: { [weak projectManager] in
            // Redo: Add the notes back
            if let trackIndex = projectManager?.currentProject?.tracks.firstIndex(where: { $0.id == trackId }),
               let regionIndex = projectManager?.currentProject?.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                projectManager?.currentProject?.tracks[trackIndex].midiRegions[regionIndex].notes.append(contentsOf: notesCopy)
            }
        }
    }
    
    /// Register undo for deleting MIDI notes
    func registerDeleteMIDINotes(_ notes: [MIDINote], from regionId: UUID, in trackId: UUID, projectManager: ProjectManager) {
        let notesCopy = notes
        
        registerUndo(actionName: notes.count == 1 ? "Delete Note" : "Delete Notes") { [weak projectManager] in
            // Undo: Restore the notes
            if let trackIndex = projectManager?.currentProject?.tracks.firstIndex(where: { $0.id == trackId }),
               let regionIndex = projectManager?.currentProject?.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                projectManager?.currentProject?.tracks[trackIndex].midiRegions[regionIndex].notes.append(contentsOf: notesCopy)
            }
        } redo: { [weak projectManager] in
            // Redo: Delete again
            if let trackIndex = projectManager?.currentProject?.tracks.firstIndex(where: { $0.id == trackId }),
               let regionIndex = projectManager?.currentProject?.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                let noteIds = Set(notesCopy.map { $0.id })
                projectManager?.currentProject?.tracks[trackIndex].midiRegions[regionIndex].notes.removeAll { noteIds.contains($0.id) }
            }
        }
    }
    
    /// Register undo for moving MIDI notes
    func registerMoveMIDINotes(_ originalNotes: [MIDINote], movedNotes: [MIDINote], in regionId: UUID, trackId: UUID, projectManager: ProjectManager) {
        let originalCopy = originalNotes
        let movedCopy = movedNotes
        let noteIds = Set(originalNotes.map { $0.id })
        
        registerUndo(actionName: "Move Notes") { [weak projectManager] in
            // Undo: Restore original positions
            if let trackIndex = projectManager?.currentProject?.tracks.firstIndex(where: { $0.id == trackId }),
               let regionIndex = projectManager?.currentProject?.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                var notes = projectManager?.currentProject?.tracks[trackIndex].midiRegions[regionIndex].notes ?? []
                notes.removeAll { noteIds.contains($0.id) }
                notes.append(contentsOf: originalCopy)
                projectManager?.currentProject?.tracks[trackIndex].midiRegions[regionIndex].notes = notes
            }
        } redo: { [weak projectManager] in
            // Redo: Apply moved positions
            if let trackIndex = projectManager?.currentProject?.tracks.firstIndex(where: { $0.id == trackId }),
               let regionIndex = projectManager?.currentProject?.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
                var notes = projectManager?.currentProject?.tracks[trackIndex].midiRegions[regionIndex].notes ?? []
                notes.removeAll { noteIds.contains($0.id) }
                notes.append(contentsOf: movedCopy)
                projectManager?.currentProject?.tracks[trackIndex].midiRegions[regionIndex].notes = notes
            }
        }
    }
    
    /// Register undo for duplicating a MIDI region
    func registerDuplicateMIDIRegion(originalRegion: MIDIRegion, duplicatedRegion: MIDIRegion, in trackId: UUID, projectManager: ProjectManager, audioEngine: AudioEngine) {
        let duplicated = duplicatedRegion
        
        registerUndo(actionName: "Duplicate MIDI Region") { [weak projectManager, weak audioEngine] in
            // Undo: Remove the duplicated region
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[trackIndex].midiRegions.removeAll { $0.id == duplicated.id }
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        } redo: { [weak projectManager, weak audioEngine] in
            // Redo: Add the duplicated region back
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            project.tracks[trackIndex].midiRegions.append(duplicated)
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.loadProject(project)
            NotificationCenter.default.post(name: .projectUpdated, object: project)
        }
    }
    
    /// Register undo for moving a MIDI region
    func registerMoveMIDIRegion(_ regionId: UUID, in trackId: UUID, from oldStartBeat: Double, to newStartBeat: Double, projectManager: ProjectManager) {
        registerUndo(actionName: "Move MIDI Region") { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) else { return }
            project.tracks[trackIndex].midiRegions[regionIndex].startBeat = oldStartBeat
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        } redo: { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) else { return }
            project.tracks[trackIndex].midiRegions[regionIndex].startBeat = newStartBeat
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        }
    }
}

// MARK: - Project Operations

extension UndoService {
    
    /// Register undo for tempo change
    func registerTempoChange(from oldTempo: Double, to newTempo: Double, projectManager: ProjectManager) {
        registerUndo(actionName: "Change Tempo") { [weak projectManager] in
            projectManager?.currentProject?.tempo = oldTempo
        } redo: { [weak projectManager] in
            projectManager?.currentProject?.tempo = newTempo
        }
    }
    
    /// Register undo for time signature change
    func registerTimeSignatureChange(from oldSig: TimeSignature, to newSig: TimeSignature, projectManager: ProjectManager) {
        registerUndo(actionName: "Change Time Signature") { [weak projectManager] in
            projectManager?.currentProject?.timeSignature = oldSig
        } redo: { [weak projectManager] in
            projectManager?.currentProject?.timeSignature = newSig
        }
    }
}

// MARK: - Step Sequencer Operations

extension UndoService {
    
    /// Register undo for toggling a step
    func registerToggleStep(laneId: UUID, step: Int, wasEnabled: Bool, oldVelocity: Float?, sequencer: SequencerEngine) {
        registerUndo(actionName: wasEnabled ? "Remove Step" : "Add Step") { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            if wasEnabled {
                // Was enabled, restore it
                sequencer.pattern.lanes[index].setStep(step, velocity: oldVelocity ?? 0.8)
            } else {
                // Was disabled, remove it
                sequencer.pattern.lanes[index].stepVelocities.removeValue(forKey: step)
            }
        } redo: { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            if wasEnabled {
                // Was enabled, now remove
                sequencer.pattern.lanes[index].stepVelocities.removeValue(forKey: step)
            } else {
                // Was disabled, now add
                sequencer.pattern.lanes[index].setStep(step, velocity: 0.8)
            }
        }
    }
    
    /// Register undo for step velocity change
    func registerStepVelocityChange(laneId: UUID, step: Int, oldVelocity: Float, newVelocity: Float, sequencer: SequencerEngine) {
        registerUndo(actionName: "Adjust Velocity") { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].setStep(step, velocity: oldVelocity)
        } redo: { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].setStep(step, velocity: newVelocity)
        }
    }
    
    /// Register undo for step probability change
    func registerStepProbabilityChange(laneId: UUID, step: Int, oldProbability: Float, newProbability: Float, sequencer: SequencerEngine) {
        registerUndo(actionName: "Adjust Probability") { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].stepProbabilities[step] = oldProbability
        } redo: { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].stepProbabilities[step] = newProbability
        }
    }
    
    /// Register undo for swing change
    func registerSwingChange(from oldSwing: Double, to newSwing: Double, sequencer: SequencerEngine) {
        registerUndo(actionName: "Change Swing") { [weak sequencer] in
            sequencer?.pattern.swing = oldSwing
        } redo: { [weak sequencer] in
            sequencer?.pattern.swing = newSwing
        }
    }
    
    /// Register undo for humanize velocity change
    func registerHumanizeVelocityChange(from oldValue: Double, to newValue: Double, sequencer: SequencerEngine) {
        registerUndo(actionName: "Change Humanize") { [weak sequencer] in
            sequencer?.pattern.humanizeVelocity = oldValue
        } redo: { [weak sequencer] in
            sequencer?.pattern.humanizeVelocity = newValue
        }
    }
    
    /// Register undo for humanize timing change
    func registerHumanizeTimingChange(from oldValue: Double, to newValue: Double, sequencer: SequencerEngine) {
        registerUndo(actionName: "Change Humanize Timing") { [weak sequencer] in
            sequencer?.pattern.humanizeTiming = oldValue
        } redo: { [weak sequencer] in
            sequencer?.pattern.humanizeTiming = newValue
        }
    }
    
    /// Register undo for pattern name change
    func registerPatternNameChange(from oldName: String, to newName: String, sequencer: SequencerEngine) {
        registerUndo(actionName: "Rename Pattern") { [weak sequencer] in
            sequencer?.pattern.name = oldName
        } redo: { [weak sequencer] in
            sequencer?.pattern.name = newName
        }
    }
    
    /// Register undo for pattern length change
    func registerPatternLengthChange(from oldLength: Int, to newLength: Int, sequencer: SequencerEngine) {
        registerUndo(actionName: "Change Pattern Length") { [weak sequencer] in
            sequencer?.pattern.steps = oldLength
        } redo: { [weak sequencer] in
            sequencer?.pattern.steps = newLength
        }
    }
    
    /// Register undo for lane mute toggle
    func registerLaneMuteToggle(laneId: UUID, wasMuted: Bool, sequencer: SequencerEngine) {
        registerUndo(actionName: wasMuted ? "Unmute Lane" : "Mute Lane") { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].isMuted = wasMuted
        } redo: { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].isMuted = !wasMuted
        }
    }
    
    /// Register undo for lane solo toggle
    func registerLaneSoloToggle(laneId: UUID, wasSolo: Bool, sequencer: SequencerEngine) {
        registerUndo(actionName: wasSolo ? "Unsolo Lane" : "Solo Lane") { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].isSolo = wasSolo
        } redo: { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].isSolo = !wasSolo
        }
    }
    
    /// Register undo for lane volume change
    func registerLaneVolumeChange(laneId: UUID, from oldVolume: Float, to newVolume: Float, sequencer: SequencerEngine) {
        registerUndo(actionName: "Change Lane Volume") { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].volume = oldVolume
        } redo: { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].volume = newVolume
        }
    }
    
    /// Register undo for clearing a lane
    func registerClearLane(laneId: UUID, oldStepVelocities: [Int: Float], oldStepProbabilities: [Int: Float], sequencer: SequencerEngine) {
        registerUndo(actionName: "Clear Lane") { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].stepVelocities = oldStepVelocities
            sequencer.pattern.lanes[index].stepProbabilities = oldStepProbabilities
        } redo: { [weak sequencer] in
            guard let sequencer = sequencer,
                  let index = sequencer.pattern.lanes.firstIndex(where: { $0.id == laneId }) else { return }
            sequencer.pattern.lanes[index].stepVelocities.removeAll()
            sequencer.pattern.lanes[index].stepProbabilities.removeAll()
        }
    }
    
    /// Register undo for clearing entire pattern
    func registerClearPattern(oldPattern: StepPattern, sequencer: SequencerEngine) {
        registerUndo(actionName: "Clear Pattern") { [weak sequencer] in
            sequencer?.pattern = oldPattern
        } redo: { [weak sequencer] in
            guard let sequencer = sequencer else { return }
            sequencer.pattern = StepPattern(
                id: UUID(),
                name: "New Pattern",
                steps: oldPattern.steps,
                lanes: SequencerLane.defaultDrumKit(),
                tempo: oldPattern.tempo,
                swing: 0.0,
                sourceFilename: nil
            )
        }
    }
}

// MARK: - Bus Send Operations

extension UndoService {
    
    /// Register undo for bus send level change
    func registerSendLevelChange(_ trackId: UUID, sendIndex: Int, busId: UUID, from oldLevel: Double, to newLevel: Double, projectManager: ProjectManager, audioEngine: AudioEngine) {
        registerUndo(actionName: "Change Send Level") { [weak projectManager, weak audioEngine] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  sendIndex < project.tracks[trackIndex].sends.count else { return }
            var send = project.tracks[trackIndex].sends[sendIndex]
            send = TrackSend(busId: send.busId, sendLevel: oldLevel, isPreFader: send.isPreFader, pan: send.pan, isMuted: send.isMuted)
            project.tracks[trackIndex].sends[sendIndex] = send
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.updateTrackSendLevel(trackId, busId: busId, level: oldLevel)
        } redo: { [weak projectManager, weak audioEngine] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  sendIndex < project.tracks[trackIndex].sends.count else { return }
            var send = project.tracks[trackIndex].sends[sendIndex]
            send = TrackSend(busId: send.busId, sendLevel: newLevel, isPreFader: send.isPreFader, pan: send.pan, isMuted: send.isMuted)
            project.tracks[trackIndex].sends[sendIndex] = send
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            audioEngine?.updateTrackSendLevel(trackId, busId: busId, level: newLevel)
        }
    }
    
    /// Register undo for bus send pre-fader toggle
    func registerSendPreFaderChange(_ trackId: UUID, sendIndex: Int, busId: UUID, wasPreFader: Bool, projectManager: ProjectManager) {
        registerUndo(actionName: wasPreFader ? "Set Post-Fader" : "Set Pre-Fader") { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  sendIndex < project.tracks[trackIndex].sends.count else { return }
            var send = project.tracks[trackIndex].sends[sendIndex]
            send = TrackSend(busId: send.busId, sendLevel: send.sendLevel, isPreFader: wasPreFader, pan: send.pan, isMuted: send.isMuted)
            project.tracks[trackIndex].sends[sendIndex] = send
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        } redo: { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  sendIndex < project.tracks[trackIndex].sends.count else { return }
            var send = project.tracks[trackIndex].sends[sendIndex]
            send = TrackSend(busId: send.busId, sendLevel: send.sendLevel, isPreFader: !wasPreFader, pan: send.pan, isMuted: send.isMuted)
            project.tracks[trackIndex].sends[sendIndex] = send
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        }
    }
    
    /// Register undo for bus send mute toggle
    func registerSendMuteChange(_ trackId: UUID, sendIndex: Int, busId: UUID, wasMuted: Bool, projectManager: ProjectManager, audioEngine: AudioEngine) {
        registerUndo(actionName: wasMuted ? "Unmute Send" : "Mute Send") { [weak projectManager, weak audioEngine] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  sendIndex < project.tracks[trackIndex].sends.count else { return }
            let send = project.tracks[trackIndex].sends[sendIndex]
            let updatedSend = TrackSend(busId: send.busId, sendLevel: send.sendLevel, isPreFader: send.isPreFader, pan: send.pan, isMuted: wasMuted)
            project.tracks[trackIndex].sends[sendIndex] = updatedSend
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            // Restore audio state
            let effectiveLevel = wasMuted ? 0.0 : send.sendLevel
            audioEngine?.updateTrackSendLevel(trackId, busId: busId, level: effectiveLevel)
        } redo: { [weak projectManager, weak audioEngine] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  sendIndex < project.tracks[trackIndex].sends.count else { return }
            let send = project.tracks[trackIndex].sends[sendIndex]
            let updatedSend = TrackSend(busId: send.busId, sendLevel: send.sendLevel, isPreFader: send.isPreFader, pan: send.pan, isMuted: !wasMuted)
            project.tracks[trackIndex].sends[sendIndex] = updatedSend
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
            // Apply mute state
            let effectiveLevel = !wasMuted ? 0.0 : send.sendLevel
            audioEngine?.updateTrackSendLevel(trackId, busId: busId, level: effectiveLevel)
        }
    }
    
    /// Register undo for bus send pan change
    func registerSendPanChange(_ trackId: UUID, sendIndex: Int, busId: UUID, from oldPan: Float, to newPan: Float, projectManager: ProjectManager) {
        registerUndo(actionName: "Change Send Pan") { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  sendIndex < project.tracks[trackIndex].sends.count else { return }
            var send = project.tracks[trackIndex].sends[sendIndex]
            send = TrackSend(busId: send.busId, sendLevel: send.sendLevel, isPreFader: send.isPreFader, pan: oldPan, isMuted: send.isMuted)
            project.tracks[trackIndex].sends[sendIndex] = send
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        } redo: { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  sendIndex < project.tracks[trackIndex].sends.count else { return }
            var send = project.tracks[trackIndex].sends[sendIndex]
            send = TrackSend(busId: send.busId, sendLevel: send.sendLevel, isPreFader: send.isPreFader, pan: newPan, isMuted: send.isMuted)
            project.tracks[trackIndex].sends[sendIndex] = send
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        }
    }
}

// MARK: - Master Channel Operations

extension UndoService {
    
    /// Register undo for master volume change
    func registerMasterVolumeChange(from oldVolume: Double, to newVolume: Double, audioEngine: AudioEngine) {
        registerUndo(actionName: "Change Master Volume") { [weak audioEngine] in
            audioEngine?.masterVolume = oldVolume
        } redo: { [weak audioEngine] in
            audioEngine?.masterVolume = newVolume
        }
    }
}

// MARK: - Region Fade Operations

extension UndoService {
    
    /// Register undo for fade in change
    func registerFadeInChange(_ regionId: UUID, in trackId: UUID, from oldFade: TimeInterval, to newFade: TimeInterval, projectManager: ProjectManager) {
        registerUndo(actionName: "Change Fade In") { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) else { return }
            project.tracks[trackIndex].regions[regionIndex].fadeIn = oldFade
            project.modifiedAt = Date()
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        } redo: { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) else { return }
            project.tracks[trackIndex].regions[regionIndex].fadeIn = newFade
            project.modifiedAt = Date()
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        }
    }
    
    /// Register undo for fade out change
    func registerFadeOutChange(_ regionId: UUID, in trackId: UUID, from oldFade: TimeInterval, to newFade: TimeInterval, projectManager: ProjectManager) {
        registerUndo(actionName: "Change Fade Out") { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) else { return }
            project.tracks[trackIndex].regions[regionIndex].fadeOut = oldFade
            project.modifiedAt = Date()
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        } redo: { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) else { return }
            project.tracks[trackIndex].regions[regionIndex].fadeOut = newFade
            project.modifiedAt = Date()
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        }
    }
    
    /// Register undo for region gain change
    func registerRegionGainChange(_ regionId: UUID, in trackId: UUID, from oldGain: Float, to newGain: Float, projectManager: ProjectManager) {
        registerUndo(actionName: "Change Region Gain") { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) else { return }
            project.tracks[trackIndex].regions[regionIndex].gain = oldGain
            project.modifiedAt = Date()
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        } redo: { [weak projectManager] in
            guard var project = projectManager?.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
                  let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) else { return }
            project.tracks[trackIndex].regions[regionIndex].gain = newGain
            project.modifiedAt = Date()
            projectManager?.currentProject = project
            projectManager?.hasUnsavedChanges = true
        }
    }
}
