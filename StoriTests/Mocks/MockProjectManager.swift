//
//  MockProjectManager.swift
//  StoriTests
//
//  Mock implementation of ProjectManager for testing services that depend on it.
//

import Foundation
@testable import Stori

/// Mock ProjectManager for unit testing
/// Provides controllable behavior for testing services that depend on project management
@MainActor
final class MockProjectManager {
    // MARK: - Mock State
    
    var currentProject: AudioProject?
    var savedProjects: [UUID: AudioProject] = [:]
    var recentProjects: [RecentProject] = []
    
    // MARK: - Call Tracking
    
    var createProjectCallCount = 0
    var saveProjectCallCount = 0
    var loadProjectCallCount = 0
    var deleteProjectCallCount = 0
    
    var lastCreatedProjectName: String?
    var lastSavedProjectId: UUID?
    var lastLoadedProjectId: UUID?
    var lastDeletedProjectId: UUID?
    
    // MARK: - Error Simulation
    
    var shouldFailSave = false
    var shouldFailLoad = false
    var saveError: Error?
    var loadError: Error?
    
    // MARK: - Mock Methods
    
    func createProject(name: String, tempo: Double = 120.0) -> AudioProject {
        createProjectCallCount += 1
        lastCreatedProjectName = name
        
        let project = AudioProject(name: name, tempo: tempo)
        currentProject = project
        savedProjects[project.id] = project
        
        return project
    }
    
    func saveProject(_ project: AudioProject) throws {
        saveProjectCallCount += 1
        lastSavedProjectId = project.id
        
        if shouldFailSave {
            throw saveError ?? TestError.mockFailure("Save failed")
        }
        
        savedProjects[project.id] = project
    }
    
    func loadProject(id: UUID) throws -> AudioProject {
        loadProjectCallCount += 1
        lastLoadedProjectId = id
        
        if shouldFailLoad {
            throw loadError ?? TestError.mockFailure("Load failed")
        }
        
        guard let project = savedProjects[id] else {
            throw TestError.mockFailure("Project not found")
        }
        
        currentProject = project
        return project
    }
    
    func deleteProject(id: UUID) {
        deleteProjectCallCount += 1
        lastDeletedProjectId = id
        
        savedProjects.removeValue(forKey: id)
        if currentProject?.id == id {
            currentProject = nil
        }
    }
    
    // MARK: - Helper Methods
    
    func reset() {
        currentProject = nil
        savedProjects.removeAll()
        recentProjects.removeAll()
        
        createProjectCallCount = 0
        saveProjectCallCount = 0
        loadProjectCallCount = 0
        deleteProjectCallCount = 0
        
        lastCreatedProjectName = nil
        lastSavedProjectId = nil
        lastLoadedProjectId = nil
        lastDeletedProjectId = nil
        
        shouldFailSave = false
        shouldFailLoad = false
        saveError = nil
        loadError = nil
    }
    
    /// Populate with test projects
    func populateTestProjects(count: Int) {
        for i in 0..<count {
            let project = AudioProject(name: "Test Project \(i + 1)")
            savedProjects[project.id] = project
            
            recentProjects.append(RecentProject(
                id: project.id,
                name: project.name,
                path: "/tmp/test/\(project.id).stori",
                lastOpened: Date().addingTimeInterval(Double(-i * 3600))
            ))
        }
    }
}

/// Represents a recently opened project (matches real implementation)
struct RecentProject: Identifiable, Codable {
    let id: UUID
    var name: String
    var path: String
    var lastOpened: Date
}
