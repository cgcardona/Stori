//
//  TrackHeaderManager.swift
//  TellUrStoriDAW
//
//  State management for professional track headers with AudioEngine synchronization
//

import SwiftUI
import Foundation

@MainActor
class TrackHeaderManager: ObservableObject {
    // MARK: - Published Properties
    @Published var tracks: [TrackHeaderModel] = []
    @Published var selectedTrackIDs: Set<UUID> = []
    @Published var trackHeights: [UUID: CGFloat] = [:]
    @Published var trackColors: [UUID: TrackColor] = [:]
    @Published var isReordering = false
    @Published var draggedTrackID: UUID?
    
    // MARK: - Dependencies
    private weak var audioEngine: AudioEngine?
    weak var projectManager: ProjectManager?
    
    // MARK: - Constants
    private let defaultTrackHeight: CGFloat = 80
    private let minTrackHeight: CGFloat = 40
    private let maxTrackHeight: CGFloat = 200
    
    // MARK: - Initialization
    init() {
        setupDefaultColors()
    }
    
    // MARK: - Dependency Injection
    func configure(audioEngine: AudioEngine, projectManager: ProjectManager) {
        self.audioEngine = audioEngine
        self.projectManager = projectManager
        syncWithProject()
    }
    
    // MARK: - Track Management
    func addTrack(name: String = "New Track", type: TrackType = .audio) {
        let availableColors = TrackColor.allCases
        let usedColors = Set(tracks.map { $0.color })
        let nextColor = availableColors.first { !usedColors.contains($0) } ?? .blue
        
        let track = TrackHeaderModel(
            name: name,
            trackType: type,
            color: nextColor,
            trackNumber: tracks.count + 1
        )
        
        tracks.append(track)
        trackHeights[track.id] = defaultTrackHeight
        trackColors[track.id] = nextColor
        
        // Sync with AudioEngine and ProjectManager
        createAudioTrack(from: track)
    }
    
    func removeTrack(id: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        
        tracks.remove(at: index)
        trackHeights.removeValue(forKey: id)
        trackColors.removeValue(forKey: id)
        selectedTrackIDs.remove(id)
        
        // Update track numbers
        updateTrackNumbers()
        
        // Sync with backend
        audioEngine?.removeTrack(trackId: id)
        projectManager?.removeTrack(id)
    }
    
    func duplicateTrack(id: UUID) {
        guard let originalTrack = tracks.first(where: { $0.id == id }) else { return }
        
        var duplicatedTrack = originalTrack
        duplicatedTrack.id = UUID()
        duplicatedTrack.name = "\(originalTrack.name) Copy"
        duplicatedTrack.trackNumber = tracks.count + 1
        
        tracks.append(duplicatedTrack)
        trackHeights[duplicatedTrack.id] = trackHeights[id] ?? defaultTrackHeight
        trackColors[duplicatedTrack.id] = originalTrack.color
        
        // Sync with backend
        createAudioTrack(from: duplicatedTrack)
    }
    
    // MARK: - Track Reordering
    func moveTrack(from sourceIndices: IndexSet, to destination: Int) {
        isReordering = true
        tracks.move(fromOffsets: sourceIndices, toOffset: destination)
        updateTrackNumbers()
        isReordering = false
        
        // Sync with backend
        syncTrackOrderWithBackend()
    }
    
    func handleTrackDragStart(trackID: UUID) {
        draggedTrackID = trackID
        isReordering = true
    }
    
    func handleTrackDragEnd() {
        draggedTrackID = nil
        isReordering = false
    }
    
    // MARK: - Track Properties
    func updateTrackName(id: UUID, name: String) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].name = name
        
        // Sync with backend
        syncTrackWithBackend(tracks[index])
    }
    
    func updateTrackColor(id: UUID, color: TrackColor) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].color = color
        trackColors[id] = color
        
        // Sync with backend
        syncTrackWithBackend(tracks[index])
    }
    
    func updateTrackHeight(id: UUID, height: CGFloat) {
        let clampedHeight = max(minTrackHeight, min(maxTrackHeight, height))
        trackHeights[id] = clampedHeight
    }
    
    // MARK: - Track Controls
    func toggleMute(id: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].isMuted.toggle()
        
        // Sync with AudioEngine
        audioEngine?.updateTrackMute(trackId: id, isMuted: tracks[index].isMuted)
        syncTrackWithBackend(tracks[index])
    }
    
    func toggleSolo(id: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        
        // Handle exclusive solo behavior
        if !tracks[index].isSolo {
            // If enabling solo, disable all other solos
            for i in tracks.indices {
                if tracks[i].id != id && tracks[i].isSolo {
                    tracks[i].isSolo = false
                    audioEngine?.updateTrackSolo(trackId: tracks[i].id, isSolo: false)
                }
            }
        }
        
        tracks[index].isSolo.toggle()
        
        // Sync with AudioEngine
        audioEngine?.updateTrackSolo(trackId: id, isSolo: tracks[index].isSolo)
        syncTrackWithBackend(tracks[index])
    }
    
    func toggleRecordEnable(id: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].isRecordEnabled.toggle()
        
        // Sync with backend
        syncTrackWithBackend(tracks[index])
    }
    
    func updateVolume(id: UUID, volume: Float) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].volume = volume
        
        // Sync with AudioEngine
        audioEngine?.updateTrackVolume(trackId: id, volume: volume)
        syncTrackWithBackend(tracks[index])
    }
    
    func updatePan(id: UUID, pan: Float) {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].pan = pan
        
        // Sync with AudioEngine
        audioEngine?.updateTrackPan(trackId: id, pan: pan)
        syncTrackWithBackend(tracks[index])
    }
    
    // MARK: - Selection Management
    func selectTrack(id: UUID, exclusive: Bool = true) {
        if exclusive {
            selectedTrackIDs = [id]
        } else {
            if selectedTrackIDs.contains(id) {
                selectedTrackIDs.remove(id)
            } else {
                selectedTrackIDs.insert(id)
            }
        }
    }
    
    func selectAllTracks() {
        selectedTrackIDs = Set(tracks.map { $0.id })
    }
    
    func deselectAllTracks() {
        selectedTrackIDs.removeAll()
    }
    
    // MARK: - Backend Synchronization
    func syncWithProject() {
        guard let projectManager = projectManager,
              let project = projectManager.currentProject else { return }
        
        // Convert AudioTracks to TrackHeaderModels
        tracks = project.tracks.map { audioTrack in
            TrackHeaderModel(from: audioTrack)
        }
        
        // Update track numbers
        updateTrackNumbers()
        
        // Initialize heights and colors
        for track in tracks {
            trackHeights[track.id] = defaultTrackHeight
            trackColors[track.id] = track.color
        }
    }
    
    private func createAudioTrack(from trackHeader: TrackHeaderModel) {
        let audioTrack = AudioTrack(
            name: trackHeader.name,
            trackType: trackHeader.trackType,
            color: trackHeader.color
        )
        
        // Update mixer settings
        var mixerSettings = audioTrack.mixerSettings
        mixerSettings.isMuted = trackHeader.isMuted
        mixerSettings.isSolo = trackHeader.isSolo
        mixerSettings.isRecordEnabled = trackHeader.isRecordEnabled
        mixerSettings.volume = trackHeader.volume
        mixerSettings.pan = trackHeader.pan
        
        var updatedTrack = audioTrack
        updatedTrack.mixerSettings = mixerSettings
        
        projectManager?.addTrack(name: updatedTrack.name)
    }
    
    private func syncTrackWithBackend(_ trackHeader: TrackHeaderModel) {
        guard let projectManager = projectManager,
              let project = projectManager.currentProject,
              let audioTrackIndex = project.tracks.firstIndex(where: { $0.id == trackHeader.id }) else { return }
        
        var audioTrack = project.tracks[audioTrackIndex]
        audioTrack.name = trackHeader.name
        audioTrack.color = trackHeader.color
        audioTrack.trackType = trackHeader.trackType
        
        // Update mixer settings
        audioTrack.mixerSettings.isMuted = trackHeader.isMuted
        audioTrack.mixerSettings.isSolo = trackHeader.isSolo
        audioTrack.mixerSettings.isRecordEnabled = trackHeader.isRecordEnabled
        audioTrack.mixerSettings.volume = trackHeader.volume
        audioTrack.mixerSettings.pan = trackHeader.pan
        
        projectManager.updateTrack(audioTrack)
    }
    
    private func syncTrackOrderWithBackend() {
        guard let projectManager = projectManager else { return }
        
        // Reorder tracks in project to match header order
        let reorderedAudioTracks = tracks.compactMap { trackHeader in
            projectManager.currentProject?.tracks.first { $0.id == trackHeader.id }
        }
        
        // Update project with reordered tracks
        if var project = projectManager.currentProject {
            project.tracks = reorderedAudioTracks
            projectManager.currentProject = project
            projectManager.saveCurrentProject()
        }
    }
    
    private func updateTrackNumbers() {
        for (index, _) in tracks.enumerated() {
            tracks[index].trackNumber = index + 1
        }
    }
    
    private func setupDefaultColors() {
        // Pre-populate color preferences if needed
    }
}

// MARK: - Track Header Model
struct TrackHeaderModel: Identifiable, Equatable {
    var id: UUID
    var name: String
    var trackType: TrackType
    var color: TrackColor
    var trackNumber: Int
    
    // Control states
    var isMuted: Bool = false
    var isSolo: Bool = false
    var isRecordEnabled: Bool = false
    var isFrozen: Bool = false
    
    // Audio parameters
    var volume: Float = 0.6 // Default to 60%
    var pan: Float = 0.0
    
    // UI states
    var isSelected: Bool = false
    var isExpanded: Bool = true
    
    init(
        name: String = "New Track",
        trackType: TrackType = .audio,
        color: TrackColor = .blue,
        trackNumber: Int = 1
    ) {
        self.id = UUID()
        self.name = name
        self.trackType = trackType
        self.color = color
        self.trackNumber = trackNumber
    }
    
    init(from audioTrack: AudioTrack) {
        self.id = audioTrack.id
        self.name = audioTrack.name
        self.trackType = audioTrack.trackType
        self.color = audioTrack.color
        self.trackNumber = 1 // Will be updated by manager
        
        // Copy mixer settings
        self.isMuted = audioTrack.mixerSettings.isMuted
        self.isSolo = audioTrack.mixerSettings.isSolo
        self.isRecordEnabled = audioTrack.mixerSettings.isRecordEnabled
        self.volume = audioTrack.mixerSettings.volume
        self.pan = audioTrack.mixerSettings.pan
        self.isFrozen = audioTrack.isFrozen
    }
    
    var typeIcon: String {
        switch trackType {
        case .audio:
            return "waveform"
        case .midi:
            return "pianokeys"
        case .instrument:
            return "music.note"
        case .bus:
            return "arrow.triangle.branch"
        }
    }
    
    var panDisplayText: String {
        if abs(pan) < 0.01 {
            return "C"
        } else if pan > 0 {
            return "R\(Int(pan * 100))"
        } else {
            return "L\(Int(abs(pan) * 100))"
        }
    }
    
    var volumeDisplayText: String {
        return "\(Int(volume * 100))%"
    }
}
