//
//  ProjectManager.swift
//  TellUrStoriDAW
//
//  Project management and persistence service
//

import Foundation
import SwiftUI
import Combine

// MARK: - Project Manager
@MainActor
class ProjectManager: ObservableObject {
    
    // MARK: - Published Properties
    @Published var currentProject: AudioProject?
    @Published var recentProjects: [AudioProject] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
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
    func createNewProject(name: String, tempo: Double = 120.0) {
        let project = AudioProject(name: name, tempo: tempo)
        currentProject = project
        
        // Add a default audio track
        var updatedProject = project
        let defaultTrack = AudioTrack(name: "Track 1", colorHex: "#3B82F6")
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
                let projectURL = projectURL(for: project.id)
                let data = try Data(contentsOf: projectURL)
                let loadedProject = try JSONDecoder().decode(AudioProject.self, from: data)
                
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
                    let project = try JSONDecoder().decode(AudioProject.self, from: data)
                    recentProjects.append(project)
                } catch {
                    print("Failed to load project file \(file.lastPathComponent): \(error)")
                }
            }
            
            // Sort by modification date
            recentProjects.sort { $0.modifiedAt > $1.modifiedAt }
            
        } catch {
            print("Failed to load recent projects: \(error)")
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
                
                let projectURL = projectURL(for: project.id)
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
    
    func saveProjectAs(name: String) {
        guard var project = currentProject else { return }
        
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
    
    // MARK: - Project Management
    func deleteProject(_ project: AudioProject) {
        let projectURL = projectURL(for: project.id)
        
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
        let colors = ["#3B82F6", "#EF4444", "#10B981", "#F59E0B", "#8B5CF6", "#EC4899"]
        let colorIndex = (trackNumber - 1) % colors.count
        
        let newTrack = AudioTrack(name: trackName, colorHex: colors[colorIndex])
        project.addTrack(newTrack)
        
        currentProject = project
        saveCurrentProject()
    }
    
    func removeTrack(_ trackId: UUID) {
        guard var project = currentProject else { return }
        
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
            project.tracks[trackIndex].removeRegion(withId: regionId)
            currentProject = project
            saveCurrentProject()
        }
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
    private func projectURL(for projectId: UUID) -> URL {
        return projectsDirectory.appendingPathComponent("\(projectId.uuidString).tellur")
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

// MARK: - Project Errors
enum ProjectError: LocalizedError {
    case noCurrentProject
    case invalidProjectFile
    case exportFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .noCurrentProject:
            return "No project is currently loaded"
        case .invalidProjectFile:
            return "The project file is invalid or corrupted"
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }
}
