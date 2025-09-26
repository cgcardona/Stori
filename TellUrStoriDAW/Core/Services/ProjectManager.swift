//
//  ProjectManager.swift
//  TellUrStoriDAW
//
//  Project management and persistence service
//

import Foundation
import SwiftUI
import Combine

// MARK: - Project Errors
enum ProjectError: LocalizedError {
    case projectAlreadyExists(name: String)
    case projectNotFound(name: String)
    case invalidProjectName
    case noCurrentProject
    case invalidProjectFile
    case exportFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .projectAlreadyExists(let name):
            return "A project named '\(name)' already exists. Please choose a different name."
        case .projectNotFound(let name):
            return "Project '\(name)' could not be found."
        case .invalidProjectName:
            return "Please enter a valid project name."
        case .noCurrentProject:
            return "No project is currently loaded"
        case .invalidProjectFile:
            return "The project file is invalid or corrupted"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }
}

// MARK: - Project Manager
@MainActor
class ProjectManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentProject: AudioProject?
    @Published var recentProjects: [AudioProject] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var hasUnsavedChanges: Bool = false
    
    // MARK: - Private Properties
    private let documentsDirectory: URL
    private let projectsDirectory: URL
    private let fileManager = FileManager.default
    
    // MARK: - Initialization
    init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        projectsDirectory = documentsDirectory.appendingPathComponent("TellUrStoriDAW/Projects")
        
        createProjectsDirectoryIfNeeded()
        loadRecentProjects()
        setupNotificationObservers()
    }
    
    // MARK: - Notification Observers
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: .projectUpdated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let updatedProject = notification.object as? AudioProject {
                Task { @MainActor in
                    self?.currentProject = updatedProject
                    self?.hasUnsavedChanges = true
                }
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .saveProject,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.saveCurrentProject()
            }
        }
    }
    
    // MARK: - Directory Setup
    private func createProjectsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: projectsDirectory.path) {
            do {
                try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
            } catch {
                print("Failed to create projects directory: \(error)")
            }
        }
    }
    
    // MARK: - Project Creation
    func createNewProject(name: String, tempo: Double = 120.0) throws {
        // Check if project with this name already exists
        if projectExists(withName: name) {
            throw ProjectError.projectAlreadyExists(name: name)
        }
        
        let project = AudioProject(name: name, tempo: tempo)
        currentProject = project
        
        // Add a default audio track
        var updatedProject = project
        let defaultTrack = AudioTrack(name: "Track 1", color: .blue)
        updatedProject.addTrack(defaultTrack)
        
        currentProject = updatedProject
        saveCurrentProject()
    }
    
    // MARK: - Project Loading
    func loadProject(_ project: AudioProject) {
        isLoading = true
        
        Task {
            do {
                // Load project data from file
                let projectURL = projectURL(for: project)
                let data = try Data(contentsOf: projectURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let loadedProject = try decoder.decode(AudioProject.self, from: data)
                
                await MainActor.run {
                    currentProject = loadedProject
                    isLoading = false
                    addToRecentProjects(loadedProject)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load project: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }
    
    func loadRecentProjects() {
        recentProjects.removeAll()
        
        do {
            let projectFiles = try fileManager.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            
            for file in projectFiles where file.pathExtension == "tellur" {
                do {
                    let data = try Data(contentsOf: file)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let project = try decoder.decode(AudioProject.self, from: data)
                    recentProjects.append(project)
                } catch {
                    print("Failed to load project file \(file.lastPathComponent): \(error)")
                    // Optionally delete corrupted files in development
                    #if DEBUG
                    try? FileManager.default.removeItem(at: file)
                    print("Removed corrupted project file: \(file.lastPathComponent)")
                    #endif
                }
            }
            
            // Sort by modification date
            recentProjects.sort { $0.modifiedAt > $1.modifiedAt }
            
        } catch {
            print("Failed to load recent projects: \(error)")
        }
    }
    
    func loadMostRecentProject() {
        loadRecentProjects()
        if let mostRecent = recentProjects.first {
            loadProject(mostRecent)
        }
    }
    
    // MARK: - Project Saving
    func saveCurrentProject() {
        guard let project = currentProject else { return }
        
        Task {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(project)
                
                let projectURL = projectURL(for: project)
                try data.write(to: projectURL)
                
                await MainActor.run {
                    // Update the current project's modified date
                    var updatedProject = project
                    updatedProject.modifiedAt = Date()
                    currentProject = updatedProject
                    
                    addToRecentProjects(updatedProject)
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save project: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func saveProjectAs(name: String) throws {
        guard var project = currentProject else { return }
        
        // Check if project with this name already exists
        if projectExists(withName: name) {
            throw ProjectError.projectAlreadyExists(name: name)
        }
        
        // Create new project with new ID and name
        project = AudioProject(
            name: name,
            tempo: project.tempo,
            timeSignature: project.timeSignature,
            sampleRate: project.sampleRate,
            bufferSize: project.bufferSize
        )
        project.tracks = currentProject?.tracks ?? []
        
        currentProject = project
        saveCurrentProject()
    }
    
    func renameCurrentProject(to newName: String) throws {
        guard var project = currentProject else {
            throw ProjectError.noCurrentProject
        }
        
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate the new name
        guard !trimmedName.isEmpty else {
            throw ProjectError.invalidProjectName
        }
        
        // Check if the name is actually different
        guard trimmedName != project.name else {
            return // No change needed
        }
        
        // Check if a project with this name already exists
        if projectExists(withName: trimmedName) {
            throw ProjectError.projectAlreadyExists(name: trimmedName)
        }
        
        // Delete the old project file
        let oldProjectURL = projectURL(for: project)
        do {
            try fileManager.removeItem(at: oldProjectURL)
        } catch {
            print("Warning: Could not delete old project file: \(error)")
            // Continue anyway - we'll save with the new name
        }
        
        // Update the project name and save
        project.name = trimmedName
        project.modifiedAt = Date()
        currentProject = project
        
        // Save with the new name
        saveCurrentProject()
        
        // Update recent projects list
        addToRecentProjects(project)
    }
    
    // MARK: - Project Management
    func deleteProject(_ project: AudioProject) {
        let projectURL = projectURL(for: project)
        
        // Clean up all audio files associated with this project
        cleanupAudioFiles(for: project)
        
        do {
            try fileManager.removeItem(at: projectURL)
            recentProjects.removeAll { $0.id == project.id }
            
            if currentProject?.id == project.id {
                currentProject = nil
            }
        } catch {
            errorMessage = "Failed to delete project: \(error.localizedDescription)"
        }
    }
    
    func duplicateProject(_ project: AudioProject) {
        var duplicatedProject = project
        duplicatedProject = AudioProject(
            name: "\(project.name) Copy",
            tempo: project.tempo,
            timeSignature: project.timeSignature,
            sampleRate: project.sampleRate,
            bufferSize: project.bufferSize
        )
        duplicatedProject.tracks = project.tracks
        
        // Save the duplicated project
        let originalProject = currentProject
        currentProject = duplicatedProject
        saveCurrentProject()
        currentProject = originalProject
    }
    
    // MARK: - Track Management
    func addTrack(name: String? = nil) {
        guard var project = currentProject else { return }
        
        let trackNumber = project.tracks.count + 1
        let trackName = name ?? "Track \(trackNumber)"
        let colors: [TrackColor] = [.blue, .red, .green, .yellow, .purple, .pink]
        let colorIndex = (trackNumber - 1) % colors.count
        
        let newTrack = AudioTrack(name: trackName, color: colors[colorIndex])
        project.addTrack(newTrack)
        
        currentProject = project
        saveCurrentProject()
        
        // Notify audio engine to create the track node
        // This would need to be done via a delegate or notification
        // For now, we'll handle this in the AudioEngine.addTrack method
    }
    
    func removeTrack(_ trackId: UUID) {
        guard var project = currentProject else { return }
        
        // Find the track to get its audio files before removal
        if let trackToRemove = project.tracks.first(where: { $0.id == trackId }) {
            // Clean up audio files associated with this track
            cleanupAudioFiles(for: trackToRemove)
        }
        
        project.removeTrack(withId: trackId)
        currentProject = project
        saveCurrentProject()
    }
    
    func updateTrack(_ track: AudioTrack) {
        guard var project = currentProject else { return }
        
        if let index = project.tracks.firstIndex(where: { $0.id == track.id }) {
            project.tracks[index] = track
            currentProject = project
            saveCurrentProject()
        }
    }
    
    // MARK: - Audio Region Management
    func addRegionToTrack(_ region: AudioRegion, trackId: UUID) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            project.tracks[trackIndex].addRegion(region)
            currentProject = project
            saveCurrentProject()
        }
    }
    
    func removeRegionFromTrack(_ regionId: UUID, trackId: UUID) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            // Find the region to clean up its audio file before removal
            if let regionToRemove = project.tracks[trackIndex].regions.first(where: { $0.id == regionId }) {
                cleanupAudioFile(regionToRemove.audioFile)
            }
            
            project.tracks[trackIndex].removeRegion(withId: regionId)
            currentProject = project
            saveCurrentProject()
        }
    }
    
    // MARK: - Region Splitting
    func splitRegionAtPosition(_ regionId: UUID, trackId: UUID, splitTime: TimeInterval) {
        guard var project = currentProject else { return }
        
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) else {
            print("❌ SPLIT: Could not find track or region")
            return
        }
        
        let originalRegion = project.tracks[trackIndex].regions[regionIndex]
        
        // Validate split position is within the region
        let regionEndTime = originalRegion.startTime + originalRegion.duration
        guard splitTime > originalRegion.startTime && splitTime < regionEndTime else {
            print("❌ SPLIT: Split time \(splitTime) is outside region bounds [\(originalRegion.startTime), \(regionEndTime)]")
            return
        }
        
        // Calculate split parameters
        let timeIntoRegion = splitTime - originalRegion.startTime
        let leftDuration = timeIntoRegion
        let rightDuration = originalRegion.duration - timeIntoRegion
        let rightOffset = originalRegion.offset + timeIntoRegion
        
        print("🔪 SPLIT: '\(originalRegion.audioFile.name)' at \(String(format: "%.2f", splitTime))s")
        print("   📊 Original: start=\(String(format: "%.2f", originalRegion.startTime))s, duration=\(String(format: "%.2f", originalRegion.duration))s, offset=\(String(format: "%.2f", originalRegion.offset))s")
        print("   ⬅️ Left: start=\(String(format: "%.2f", originalRegion.startTime))s, duration=\(String(format: "%.2f", leftDuration))s, offset=\(String(format: "%.2f", originalRegion.offset))s")
        print("   ➡️ Right: start=\(String(format: "%.2f", splitTime))s, duration=\(String(format: "%.2f", rightDuration))s, offset=\(String(format: "%.2f", rightOffset))s")
        
        // Create left region (original region modified)
        var leftRegion = originalRegion
        leftRegion.duration = leftDuration
        
        // Create right region (new region)
        let rightRegion = AudioRegion(
            audioFile: originalRegion.audioFile,
            startTime: splitTime,
            duration: rightDuration,
            fadeIn: 0, // Reset fades for split regions
            fadeOut: originalRegion.fadeOut,
            gain: originalRegion.gain,
            isLooped: originalRegion.isLooped,
            offset: rightOffset
        )
        
        // Replace original region with left region and add right region
        project.tracks[trackIndex].regions[regionIndex] = leftRegion
        project.tracks[trackIndex].addRegion(rightRegion)
        
        // Update project
        currentProject = project
        saveCurrentProject()
        
        print("✅ SPLIT: Created 2 regions from 1")
    }
    
    func updateRegion(_ region: AudioRegion, trackId: UUID) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
           let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == region.id }) {
            project.tracks[trackIndex].regions[regionIndex] = region
            currentProject = project
            saveCurrentProject()
        }
    }
    
    // MARK: - Project Export
    func exportProject(format: AudioFileFormat, quality: ExportQuality = .high) async throws -> URL {
        guard let project = currentProject else {
            throw ProjectError.noCurrentProject
        }
        
        // Create export directory
        let exportDirectory = documentsDirectory.appendingPathComponent("TellUrStoriDAW/Exports")
        if !fileManager.fileExists(atPath: exportDirectory.path) {
            try fileManager.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }
        
        // Generate export filename
        let timestamp = DateFormatter().string(from: Date())
        let filename = "\(project.name)_\(timestamp).\(format.rawValue)"
        let exportURL = exportDirectory.appendingPathComponent(filename)
        
        // TODO: Implement actual audio rendering and export
        // This would involve mixing all tracks and rendering to the specified format
        
        return exportURL
    }
    
    // MARK: - Helper Methods
    private func projectURL(for projectName: String) -> URL {
        let sanitizedName = sanitizeFileName(projectName)
        return projectsDirectory.appendingPathComponent("\(sanitizedName).tellur")
    }
    
    private func projectURL(for project: AudioProject) -> URL {
        return projectURL(for: project.name)
    }
    
    private func sanitizeFileName(_ name: String) -> String {
        // Remove or replace characters that aren't safe for file names
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalidChars).joined(separator: "_")
    }
    
    private func projectExists(withName name: String) -> Bool {
        let url = projectURL(for: name)
        return fileManager.fileExists(atPath: url.path)
    }
    
    private func addToRecentProjects(_ project: AudioProject) {
        // Remove existing entry if present
        recentProjects.removeAll { $0.id == project.id }
        
        // Add to beginning
        recentProjects.insert(project, at: 0)
        
        // Keep only the 10 most recent projects
        if recentProjects.count > 10 {
            recentProjects = Array(recentProjects.prefix(10))
        }
    }
    
    // MARK: - Project Property Updates
    func updateTempo(_ newTempo: Double) {
        guard var project = currentProject else { return }
        project.tempo = newTempo
        project.modifiedAt = Date()
        currentProject = project
        hasUnsavedChanges = true
    }
    
    func updateKeySignature(_ newKeySignature: String) {
        guard var project = currentProject else { return }
        project.keySignature = newKeySignature
        project.modifiedAt = Date()
        currentProject = project
        hasUnsavedChanges = true
    }
    
    func updateTimeSignature(_ newTimeSignature: TimeSignature) {
        guard var project = currentProject else { return }
        project.timeSignature = newTimeSignature
        project.modifiedAt = Date()
        currentProject = project
        hasUnsavedChanges = true
    }
    
    // MARK: - Unsaved Changes Management
    func markSaved() {
        hasUnsavedChanges = false
    }
    
    func markUnsaved() {
        hasUnsavedChanges = true
    }
    
    // MARK: - Track Management
    func updateTrackName(_ trackId: UUID, _ newName: String) {
        guard var project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].name = newName
        project.modifiedAt = Date()
        currentProject = project
        hasUnsavedChanges = true
    }
    
    func updateTrackColor(_ trackId: UUID, _ newColor: TrackColor) {
        guard var project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].color = newColor
        project.modifiedAt = Date()
        currentProject = project
        hasUnsavedChanges = true
    }
    
    func duplicateTrack(_ trackId: UUID) {
        guard var project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        var duplicatedTrack = project.tracks[trackIndex]
        duplicatedTrack = AudioTrack(
            name: "\(duplicatedTrack.name) Copy",
            trackType: duplicatedTrack.trackType,
            color: duplicatedTrack.color
        )
        // Copy regions and settings
        duplicatedTrack.regions = project.tracks[trackIndex].regions
        duplicatedTrack.mixerSettings = project.tracks[trackIndex].mixerSettings
        duplicatedTrack.effects = project.tracks[trackIndex].effects
        
        project.tracks.insert(duplicatedTrack, at: trackIndex + 1)
        project.modifiedAt = Date()
        currentProject = project
        hasUnsavedChanges = true
    }
    
    // MARK: - Audio File Cleanup
    
    /// Clean up audio files associated with a specific track
    private func cleanupAudioFiles(for track: AudioTrack) {
        print("🗑️ Cleaning up audio files for track: \(track.name)")
        
        for region in track.regions {
            cleanupAudioFile(region.audioFile)
        }
    }
    
    /// Clean up audio files associated with an entire project
    private func cleanupAudioFiles(for project: AudioProject) {
        print("🗑️ Cleaning up audio files for project: \(project.name)")
        
        for track in project.tracks {
            cleanupAudioFiles(for: track)
        }
    }
    
    /// Clean up a specific audio file if it's a generated file
    private func cleanupAudioFile(_ audioFile: AudioFile) {
        let fileURL = audioFile.url
        
        // Only clean up generated audio files (those in the musicgen-service/generated_audio directory)
        if fileURL.path.contains("musicgen-service/generated_audio/") {
            do {
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                    print("✅ Deleted generated audio file: \(fileURL.lastPathComponent)")
                } else {
                    print("⚠️ Generated audio file not found (already deleted?): \(fileURL.lastPathComponent)")
                }
            } catch {
                print("❌ Failed to delete generated audio file \(fileURL.lastPathComponent): \(error)")
            }
        } else {
            print("ℹ️ Skipping cleanup of non-generated audio file: \(fileURL.lastPathComponent)")
        }
    }
}

// MARK: - Export Quality
enum ExportQuality {
    case low
    case medium
    case high
    case lossless
    
    var sampleRate: Double {
        switch self {
        case .low: return 22050
        case .medium: return 44100
        case .high: return 48000
        case .lossless: return 96000
        }
    }
    
    var bitDepth: Int {
        switch self {
        case .low: return 16
        case .medium: return 16
        case .high: return 24
        case .lossless: return 32
        }
    }
}

