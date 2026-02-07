//
//  ProjectManager.swift
//  Stori
//
//  Project management and persistence service
//

import Foundation
import SwiftUI
import Combine
import Observation

// MARK: - Transport Query Coordinator
/// Coordinates transport state queries to prevent double-resume of continuations
/// Thread-safe coordinator that can be called from any queue
final class TransportQueryCoordinator {
    private let lock = NSLock()
    private var hasResumed = false
    private let continuation: CheckedContinuation<Bool, Never>
    
    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }
    
    func resumeOnce(returning value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(returning: value)
    }
}

// MARK: - Project Errors
enum ProjectError: LocalizedError {
    case projectAlreadyExists(name: String)
    case projectNotFound(name: String)
    case invalidProjectName
    case noCurrentProject
    case invalidProjectFile
    case exportFailed(String)
    case fileTooLarge(Int, Int)  // (actual size, max size)
    
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
        case .fileTooLarge(let actual, let max):
            let actualMB = actual / 1_000_000
            let maxMB = max / 1_000_000
            return "Project file is too large (\(actualMB) MB). Maximum allowed size is \(maxMB) MB."
        }
    }
}

// MARK: - Project Manager
// PERFORMANCE: Using @Observable for fine-grained SwiftUI updates
// Only views reading specific properties re-render when those properties change
@Observable
@MainActor
class ProjectManager {
    
    // MARK: - Observable Properties
    var currentProject: AudioProject?
    var recentProjects: [AudioProject] = []
    var isLoading: Bool = false
    var errorMessage: String?
    var hasUnsavedChanges: Bool = false
    
    // MARK: - Private Properties (ignored for observation)
    @ObservationIgnored
    private let documentsDirectory: URL
    @ObservationIgnored
    private let projectsDirectory: URL
    @ObservationIgnored
    private let fileManager = FileManager.default
    
    /// PERFORMANCE: Debounced save task to coalesce rapid saves.
    /// Reduces I/O by ~90% during rapid editing (e.g., automation drawing).
    @ObservationIgnored
    private var saveDebounceTask: Task<Void, Never>?
    
    /// Debounce interval for saves (in milliseconds)
    @ObservationIgnored
    private let saveDebounceMs: UInt64 = 500
    
    
    // MARK: - Initialization
    init() {
        documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        projectsDirectory = documentsDirectory.appendingPathComponent("Stori/Projects")
        
        createProjectsDirectoryIfNeeded()
        loadRecentProjects()
        setupNotificationObservers()
    }
    
    nonisolated deinit {}
    
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
        
        // REMOVED: Duplicate save observer - saves should only be triggered from MainDAWView
        // The .saveProject notification should only be handled by MainDAWView's handleSaveProject()
        // This prevents double-saving when user presses Cmd+S
    }
    
    /// Perform save with proper synchronization for plugin config saving
    /// Uses continuation to await AudioEngine's plugin config save completion
    /// This should be called from MainDAWView.handleSaveProject(), not via notification
    @MainActor
    func performSaveWithPluginSync() async {
        // Use continuation with timeout to wait for AudioEngine
        let updatedProject: AudioProject? = await withCheckedContinuation { (continuation: CheckedContinuation<AudioProject?, Never>) in
            // Track if we've already resumed (prevent double-resume)
            var hasResumed = false
            
            // Set up one-time observer for completion notification
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: .pluginConfigsSaved,
                object: nil,
                queue: .main
            ) { notification in
                // Guard against double-resume
                guard !hasResumed else { return }
                hasResumed = true
                
                // Remove observer immediately to prevent duplicate calls
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                
                // Get the updated project from the notification
                let project = notification.object as? AudioProject
                continuation.resume(returning: project)
            }
            
            // Set up timeout (5 seconds) to prevent hanging forever
            // Run on MainActor so hasResumed/observer/continuation are accessed on same queue as notification handler (no data race)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                
                // Guard against double-resume
                guard !hasResumed else { return }
                hasResumed = true
                
                // Remove observer on timeout
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                
                AppLogger.shared.warning(
                    "Plugin config save timeout (5s) - proceeding with current project state",
                    category: .project
                )
                
                // Resume with nil to indicate timeout
                continuation.resume(returning: nil)
            }
            
            // Post willSaveProject to trigger AudioEngine to save plugin configs
            NotificationCenter.default.post(name: .willSaveProject, object: nil)
        }
        
        // If we got an updated project from AudioEngine, use it
        if let project = updatedProject {
            currentProject = project
        }
        
        // Now save with the properly updated project
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    // MARK: - Directory Setup
    private func createProjectsDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: projectsDirectory.path) {
            do {
                try fileManager.createDirectory(at: projectsDirectory, withIntermediateDirectories: true)
            } catch {
                #if DEBUG
                print("⚠️ ProjectManager: Failed to create projects directory: \(error.localizedDescription)")
                #endif
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
        
        // Start with empty project - user can add tracks as needed
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    // MARK: - Security Constants
    
    /// Maximum allowed project file size (10 MB) — M-2: reduced from 100 MB for defense in depth
    /// SECURITY: Prevents memory exhaustion from malicious/corrupted files
    private static let maxProjectFileSize: Int = 10_000_000
    /// Maximum JSON nesting depth to prevent stack overflow / DoS from malicious project files.
    private static let maxJSONDepth = 20

    // MARK: - Project Loading
    func loadProject(_ project: AudioProject) {
        isLoading = true

        Task {
            do {
                // Load project data from file
                let projectURL = projectURL(for: project)

                // SECURITY: Check file size before loading to prevent memory exhaustion
                let attributes = try fileManager.attributesOfItem(atPath: projectURL.path)
                if let fileSize = attributes[.size] as? Int, fileSize > Self.maxProjectFileSize {
                    throw ProjectError.fileTooLarge(fileSize, Self.maxProjectFileSize)
                }

                let data = try Data(contentsOf: projectURL)
                // SECURITY: Validate JSON depth before decode to prevent DoS
                if let json = try? JSONSerialization.jsonObject(with: data),
                   !Self.validateJSONDepth(json, maxDepth: Self.maxJSONDepth) {
                    throw ProjectError.invalidProjectFile
                }

                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                var loadedProject: AudioProject
                do {
                    loadedProject = try decoder.decode(AudioProject.self, from: data)
                } catch {
                    if let repaired = Self.tryRepairProject(data: data) {
                        loadedProject = repaired
                        await MainActor.run {
                            NotificationCenter.default.post(
                                name: .projectRepaired,
                                object: nil,
                                userInfo: ["message": "Project was repaired automatically."]
                            )
                        }
                    } else {
                        throw error
                    }
                }
                
                // Log plugin configs from disk
                for track in loadedProject.tracks {
                    if !track.pluginConfigs.isEmpty {
                        for config in track.pluginConfigs {
                            let stateSize = config.fullState?.count ?? 0
                        }
                    }
                }
                
                // Validate track images (Phase 5)
                loadedProject = validateTrackImages(for: loadedProject)
                
                // Validate project image (Project-level tokenization)
                loadedProject = validateProjectImage(for: loadedProject)
                
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
    
    /// Attempt to repair slightly corrupted project data (e.g. date format issues). Returns nil if repair fails.
    private static func tryRepairProject(data: Data) -> AudioProject? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let date = try? container.decode(Date.self) { return date }
            guard let str = try? container.decode(String.self) else { return Date() }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: str) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: str) { return date }
            return Date()
        }
        return try? decoder.decode(AudioProject.self, from: data)
    }

    /// Returns true if JSON object has nesting depth <= maxDepth.
    private static func validateJSONDepth(_ obj: Any, maxDepth: Int, currentDepth: Int = 0) -> Bool {
        guard currentDepth <= maxDepth else { return false }
        if let dict = obj as? [String: Any] {
            for value in dict.values {
                if !validateJSONDepth(value, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                    return false
                }
            }
        } else if let array = obj as? [Any] {
            for item in array {
                if !validateJSONDepth(item, maxDepth: maxDepth, currentDepth: currentDepth + 1) {
                    return false
                }
            }
        }
        return true
    }

    func loadRecentProjects() {
        recentProjects.removeAll()
        
        do {
            let projectFiles = try fileManager.contentsOfDirectory(at: projectsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
            
            for file in projectFiles where file.pathExtension == "stori" {
                do {
                    let data = try Data(contentsOf: file)
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let project = try decoder.decode(AudioProject.self, from: data)
                    recentProjects.append(project)
                } catch {
                    // Log decoding errors to help debug project loading issues
                    print("⚠️ [ProjectManager] Failed to load project: \(file.lastPathComponent)")
                    print("   Error: \(error)")
                }
            }
            
            // Sort by modification date
            recentProjects.sort { $0.modifiedAt > $1.modifiedAt }
            
        } catch {
            #if DEBUG
            print("⚠️ ProjectManager: Failed to load recent projects: \(error.localizedDescription)")
            #endif
        }
    }
    
    func loadMostRecentProject() {
        loadRecentProjects()
        if let mostRecent = recentProjects.first {
            loadProject(mostRecent)
        }
    }
    
    // MARK: - Project Saving
    
    /// Schedules a debounced save. Multiple calls within 500ms are coalesced into one save.
    /// PERFORMANCE (Phase 3.4): Reduces I/O by ~90% during rapid editing.
    ///
    /// Use this for automatic saves triggered by model changes (e.g., automation edits).
    /// Use `saveCurrentProject()` for explicit user-triggered saves (Cmd+S).
    func scheduleSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(saveDebounceMs)))
            guard !Task.isCancelled else { return }
            self?.saveCurrentProject()
        }
    }
    
    /// Cancels any pending debounced save (e.g., when closing project).
    func cancelPendingSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
    }
    
    /// Immediately saves the current project (bypasses debounce).
    /// Use for explicit user-triggered saves (Cmd+S).
    ///
    /// **CRITICAL (Issue #63)**: This method ensures atomic snapshot of project state
    /// to prevent torn reads from concurrent playback updates.
    /// - Pauses transport if playing to capture consistent state
    /// - Resumes transport after snapshot is captured
    /// - Uses deep copy to isolate snapshot from ongoing mutations
    func saveCurrentProject() {
        // Cancel any pending debounced save to avoid duplicate
        cancelPendingSave()
        
        guard let project = currentProject else { return }
        
        // Log plugin configs being saved
        for track in project.tracks {
            if !track.pluginConfigs.isEmpty {
                for config in track.pluginConfigs {
                    let stateSize = config.fullState?.count ?? 0
                }
            }
        }
        
        Task { [weak self] in
            guard let self else { return }
            do {
                // CRITICAL (Issue #63): Request playback pause for consistent snapshot
                // The notification handler will coordinate with TransportController
                let wasPlayingBeforeSave = await self.getTransportPlayingState()
                if wasPlayingBeforeSave {
                    await self.pauseTransportForSave()
                }
                
                // Capture immutable snapshot AFTER transport is paused
                // This ensures playheadPosition, automation values, and plugin states are consistent
                let projectSnapshot = await self.captureProjectSnapshot()
                
                // Resume transport BEFORE encoding (encoding can take time, no need to block playback)
                if wasPlayingBeforeSave {
                    await self.resumeTransportAfterSave()
                }
                
                // Encode snapshot on background thread (I/O heavy, keep off main thread)
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(projectSnapshot)
                
                let projectURL = projectURL(for: projectSnapshot)
                try data.write(to: projectURL)
                
                await MainActor.run {
                    // Update the current project's modified date
                    var updatedProject = projectSnapshot
                    updatedProject.modifiedAt = Date()
                    currentProject = updatedProject
                    
                    addToRecentProjects(updatedProject)
                    
                    // Clear unsaved changes flag
                    hasUnsavedChanges = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to save project: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Save-Time Transport Coordination (Issue #63)
    
    /// Returns whether transport is currently playing
    private func getTransportPlayingState() async -> Bool {
        await withCheckedContinuation { continuation in
            let coordinator = TransportQueryCoordinator(continuation: continuation)
            
            // Set 100ms timeout to prevent hang if no transport exists
            // In normal operation, TransportController responds in < 1ms
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)
                coordinator.resumeOnce(returning: false)
            }
            
            // Post query notification with coordinator
            NotificationCenter.default.post(
                name: .queryTransportState,
                object: nil,
                userInfo: ["coordinator": coordinator]
            )
        }
    }
    
    /// Pause transport for consistent save snapshot
    /// Returns after transport has confirmed pause
    private func pauseTransportForSave() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Track if we've already resumed (prevent double-resume crash)
            var hasResumed = false
            
            var observer: NSObjectProtocol?
            observer = NotificationCenter.default.addObserver(
                forName: .transportPausedForSave,
                object: nil,
                queue: .main
            ) { _ in
                // Guard against double-resume
                guard !hasResumed else { return }
                hasResumed = true
                
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                continuation.resume()
            }
            
            // Set 100ms timeout to prevent hang if transport doesn't respond
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 100_000_000)
                
                // Guard against double-resume
                guard !hasResumed else { return }
                hasResumed = true
                
                if let obs = observer {
                    NotificationCenter.default.removeObserver(obs)
                }
                continuation.resume()
            }
            
            NotificationCenter.default.post(name: .pauseTransportForSave, object: nil)
        }
    }
    
    /// Resume transport after save snapshot captured
    private func resumeTransportAfterSave() async {
        NotificationCenter.default.post(name: .resumeTransportAfterSave, object: nil)
    }
    
    /// Capture immutable snapshot of current project
    /// This is a deep copy to isolate from concurrent mutations
    @MainActor
    private func captureProjectSnapshot() async -> AudioProject {
        guard var snapshot = currentProject else {
            // Should never happen (guard in saveCurrentProject prevents this)
            return AudioProject(name: "ERROR", tempo: 120)
        }
        
        // Deep copy critical mutable state
        // Swift struct copy is deep by default for value types
        // but we want to be explicit for clarity
        snapshot.modifiedAt = Date()
        
        return snapshot
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
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
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
            // Continue anyway - we'll save with the new name
        }
        
        // Update the project name and save
        project.name = trimmedName
        project.modifiedAt = Date()
        currentProject = project
        
        // Save with the new name
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
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
        // Generate a unique name to avoid conflicts
        var baseName = "\(project.name) Copy"
        var finalName = baseName
        var counter = 2
        
        // Keep incrementing counter until we find a unique name
        while projectExists(withName: finalName) {
            finalName = "\(baseName) \(counter)"
            counter += 1
        }
        
        var duplicatedProject = AudioProject(
            name: finalName,
            tempo: project.tempo,
            timeSignature: project.timeSignature,
            sampleRate: project.sampleRate,
            bufferSize: project.bufferSize
        )
        duplicatedProject.tracks = project.tracks
        
        // Save the duplicated project
        let originalProject = currentProject
        currentProject = duplicatedProject
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        currentProject = originalProject
    }
    
    // MARK: - Track Management
    /// Create a new audio track and return it
    @discardableResult
    func addTrack(name: String? = nil) -> AudioTrack? {
        guard var project = currentProject else { return nil }
        
        // Find the highest track number in existing track names to avoid duplicates
        let existingNumbers = project.tracks.compactMap { track -> Int? in
            // Extract number from names like "Track 1", "Track 2", etc.
            let components = track.name.components(separatedBy: " ")
            guard components.count >= 2, components[0] == "Track" else { return nil }
            return Int(components[1])
        }
        let trackNumber = (existingNumbers.max() ?? 0) + 1
        let trackName = name ?? "Track \(trackNumber)"
        let colors: [TrackColor] = [.blue, .red, .green, .yellow, .purple, .pink]
        let colorIndex = (trackNumber - 1) % colors.count
        
        let newTrack = AudioTrack(name: trackName, color: colors[colorIndex])
        project.addTrack(newTrack)
        
        currentProject = project
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Notify audio engine to create the track node
        // This would need to be done via a delegate or notification
        // For now, we'll handle this in the AudioEngine.addTrack method
        
        return newTrack
    }
    
    /// Create a new MIDI track and return it
    @discardableResult
    func addMIDITrack(name: String? = nil) -> AudioTrack? {
        guard var project = currentProject else { return nil }
        
        let midiTrackCount = project.tracks.filter { $0.isMIDITrack }.count
        let trackName = name ?? "MIDI Track \(midiTrackCount + 1)"
        
        // MIDI tracks get purple/teal color scheme
        let midiColors: [TrackColor] = [.purple, .teal, .indigo, .pink, .blue]
        let colorIndex = midiTrackCount % midiColors.count
        
        var newTrack = AudioTrack(
            name: trackName,
            trackType: .midi,
            color: midiColors[colorIndex],
            iconName: "pianokeys"
        )
        
        project.addTrack(newTrack)
        currentProject = project
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Create instrument for the track via InstrumentManager
        InstrumentManager.shared.trackAdded(newTrack)
        
        return newTrack
    }
    
    /// Create a new audio track with specific name and color, returns the track
    @discardableResult
    func addAudioTrack(name: String, color: TrackColor) -> AudioTrack? {
        guard var project = currentProject else { return nil }
        
        let newTrack = AudioTrack(
            name: name,
            trackType: .audio,
            color: color,
            iconName: "waveform"
        )
        
        project.addTrack(newTrack)
        currentProject = project
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        return newTrack
    }
    
    /// Move a track from one index to another
    func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard var project = currentProject else { return }
        guard sourceIndex >= 0 && sourceIndex < project.tracks.count else { return }
        guard destinationIndex >= 0 && destinationIndex <= project.tracks.count else { return }
        
        let track = project.tracks.remove(at: sourceIndex)
        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        project.tracks.insert(track, at: min(adjustedDestination, project.tracks.count))
        
        currentProject = project
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Post notification to update UI
        NotificationCenter.default.post(name: .projectUpdated, object: project)
    }
    
    func removeTrack(_ trackId: UUID) {
        guard var project = currentProject else { return }
        
        // Find the track to get its audio files and images before removal
        if let trackToRemove = project.tracks.first(where: { $0.id == trackId }) {
            // Clean up audio files associated with this track
            cleanupAudioFiles(for: trackToRemove)
            // Clean up image files associated with this track (Phase 5)
            cleanupTrackImages(for: trackToRemove, in: project)
        }
        
        project.removeTrack(withId: trackId)
        currentProject = project
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Notify InstrumentManager to remove the track's instrument
        InstrumentManager.shared.trackRemoved(trackId: trackId)
    }
    
    func updateTrack(_ track: AudioTrack) {
        guard var project = currentProject else { return }
        
        if let index = project.tracks.firstIndex(where: { $0.id == track.id }) {
            project.tracks[index] = track
            currentProject = project
            hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        }
    }
    
    // MARK: - Audio Region Management
    func addRegionToTrack(_ region: AudioRegion, trackId: UUID) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            project.tracks[trackIndex].addRegion(region)
            currentProject = project
            hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        }
    }
    
    func removeRegionFromTrack(_ regionId: UUID, trackId: UUID, audioEngine: AudioEngine? = nil) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
           let regionToRemove = project.tracks[trackIndex].regions.first(where: { $0.id == regionId }) {
            
            // Register undo action using centralized UndoService
            if let engine = audioEngine {
                UndoService.shared.registerDeleteAudioRegion(regionToRemove, from: trackId, projectManager: self, audioEngine: engine)
            }
            
            // Clean up audio file
            cleanupAudioFile(regionToRemove.audioFile)
            
            project.tracks[trackIndex].removeRegion(withId: regionId)
            currentProject = project
            hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
            
            // Reload audio engine to update graph
            if let engine = audioEngine {
                engine.loadProject(project)
                NotificationCenter.default.post(name: .projectUpdated, object: project)
            }
        }
    }
    
    
    // MARK: - MIDI Region Management
    
    /// Add a MIDI region to a track
    func addMIDIRegion(_ region: MIDIRegion, to trackId: UUID) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            project.tracks[trackIndex].addMIDIRegion(region)
            currentProject = project
            hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        }
    }
    
    /// Remove a MIDI region from a track
    func removeMIDIRegion(_ regionId: UUID, from trackId: UUID, audioEngine: AudioEngine? = nil) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
           let regionToRemove = project.tracks[trackIndex].midiRegions.first(where: { $0.id == regionId }) {
            
            // Register undo action using centralized UndoService
            if let engine = audioEngine {
                UndoService.shared.registerDeleteMIDIRegion(regionToRemove, from: trackId, projectManager: self, audioEngine: engine)
            }
            
            project.tracks[trackIndex].removeMIDIRegion(withId: regionId)
            currentProject = project
            hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
            
            // Reload audio engine to update graph
            if let engine = audioEngine {
                engine.loadProject(project)
                NotificationCenter.default.post(name: .projectUpdated, object: project)
            }
        }
    }
    
    /// Update a MIDI region on a track (e.g., after Piano Roll editing)
    func updateMIDIRegion(_ regionId: UUID, on trackId: UUID, notes: [MIDINote], controllerEvents: [MIDICCEvent]? = nil, pitchBendEvents: [MIDIPitchBendEvent]? = nil) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
           let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
            project.tracks[trackIndex].midiRegions[regionIndex].notes = notes
            
            // Also save CC and pitch bend events if provided
            if let ccEvents = controllerEvents {
                project.tracks[trackIndex].midiRegions[regionIndex].controllerEvents = ccEvents
            }
            if let pbEvents = pitchBendEvents {
                project.tracks[trackIndex].midiRegions[regionIndex].pitchBendEvents = pbEvents
            }
            
            currentProject = project
            hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        }
    }
    
    /// Round beat value to avoid floating-point precision issues at non-integer tempos
    /// At tempos like 99 BPM, seconds→beats→seconds conversion can introduce tiny errors
    /// (e.g., 3.9999999999999996 instead of 4.0) causing regions to start slightly early
    private func roundBeatValue(_ beats: Double) -> Double {
        // Round to nearest 1/1000th of a beat (more than enough precision for any practical use)
        return round(beats * 1000) / 1000
    }
    
    /// Move a MIDI region to a new start time on the same track
    func moveMIDIRegion(_ regionId: UUID, on trackId: UUID, to newStartBeat: Double) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
           let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) {
            // Round to avoid floating-point precision errors
            let roundedStartBeat = roundBeatValue(max(0, newStartBeat))
            project.tracks[trackIndex].midiRegions[regionIndex].startBeat = roundedStartBeat
            currentProject = project
            hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        }
    }
    
    /// Move a MIDI region to a different track
    func moveMIDIRegionToTrack(_ regionId: UUID, from sourceTrackId: UUID, to targetTrackId: UUID, newStartBeat: Double) {
        guard var project = currentProject else { return }
        
        guard let sourceIndex = project.tracks.firstIndex(where: { $0.id == sourceTrackId }),
              let regionIndex = project.tracks[sourceIndex].midiRegions.firstIndex(where: { $0.id == regionId }),
              let targetIndex = project.tracks.firstIndex(where: { $0.id == targetTrackId }) else {
            return
        }
        
        // Only allow moving to MIDI tracks
        guard project.tracks[targetIndex].isMIDITrack else {
            return
        }
        
        // Remove from source track
        var region = project.tracks[sourceIndex].midiRegions.remove(at: regionIndex)
        
        // Update start time with rounding to avoid floating-point precision errors
        region.startBeat = roundBeatValue(max(0, newStartBeat))
        
        // Add to target track
        project.tracks[targetIndex].midiRegions.append(region)
        
        currentProject = project
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    /// Duplicate a MIDI region on the same track at a new start time
    func duplicateMIDIRegion(_ regionId: UUID, on trackId: UUID, at newStartBeat: Double) {
        guard var project = currentProject else { return }
        
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) else {
            return
        }
        
        let originalRegion = project.tracks[trackIndex].midiRegions[regionIndex]
        
        // Create a new region with copied notes
        // Round startBeat to avoid floating-point precision errors
        var newRegion = MIDIRegion(
            name: "\(originalRegion.name) Copy",
            startBeat: roundBeatValue(max(0, newStartBeat)),
            durationBeats: originalRegion.durationBeats
        )
        newRegion.notes = originalRegion.notes
        
        project.tracks[trackIndex].midiRegions.append(newRegion)
        currentProject = project
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    /// Duplicate a MIDI region to a different track
    func duplicateMIDIRegionToTrack(_ regionId: UUID, from sourceTrackId: UUID, to targetTrackId: UUID, at newStartBeat: Double) {
        guard var project = currentProject else { return }
        
        guard let sourceIndex = project.tracks.firstIndex(where: { $0.id == sourceTrackId }),
              let regionIndex = project.tracks[sourceIndex].midiRegions.firstIndex(where: { $0.id == regionId }),
              let targetIndex = project.tracks.firstIndex(where: { $0.id == targetTrackId }) else {
            return
        }
        
        // Only allow duplicating to MIDI tracks
        guard project.tracks[targetIndex].isMIDITrack else {
            return
        }
        
        let originalRegion = project.tracks[sourceIndex].midiRegions[regionIndex]
        
        // Create a new region with copied notes
        // Round startBeat to avoid floating-point precision errors
        var newRegion = MIDIRegion(
            name: "\(originalRegion.name) Copy",
            startBeat: roundBeatValue(max(0, newStartBeat)),
            durationBeats: originalRegion.durationBeats
        )
        newRegion.notes = originalRegion.notes
        
        project.tracks[targetIndex].midiRegions.append(newRegion)
        currentProject = project
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    // MARK: - Region Splitting
    /// Split an audio region at a beat position (beats are source of truth)
    func splitRegionAtPosition(_ regionId: UUID, trackId: UUID, splitBeat: Double) {
        guard var project = currentProject else { return }
        
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) else {
            return
        }
        
        let originalRegion = project.tracks[trackIndex].regions[regionIndex]
        let tempo = project.tempo
        
        // Validate split position is within the region
        let regionEndBeat = originalRegion.endBeat
        guard splitBeat > originalRegion.startBeat && splitBeat < regionEndBeat else {
            return
        }
        
        // Calculate split parameters (all in beats)
        let beatsIntoRegion = splitBeat - originalRegion.startBeat
        let secondsIntoRegion = beatsIntoRegion * (60.0 / tempo) // For audio offset only (AV boundary)
        let leftDurationBeats = beatsIntoRegion
        let rightDurationBeats = originalRegion.durationBeats - beatsIntoRegion
        let rightOffset = originalRegion.offset + secondsIntoRegion
        
        
        // Create left region (original region modified)
        var leftRegion = originalRegion
        leftRegion.durationBeats = leftDurationBeats
        
        // Create right region (new region)
        let rightRegion = AudioRegion(
            audioFile: originalRegion.audioFile,
            startBeat: splitBeat,
            durationBeats: rightDurationBeats,
            tempo: tempo,
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
        hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
    }
    
    func updateRegion(_ region: AudioRegion, trackId: UUID) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
           let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == region.id }) {
            // 🐛 DEBUG: Log what we're saving
            
            project.tracks[trackIndex].regions[regionIndex] = region
            currentProject = project
            hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        }
    }
    
    // MARK: - Project Export
    func exportProject(format: AudioFileFormat, quality: ExportQuality = .high) async throws -> URL {
        guard let project = currentProject else {
            throw ProjectError.noCurrentProject
        }
        
        // Create export directory
        let exportDirectory = documentsDirectory.appendingPathComponent("Stori/Exports")
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
        return projectsDirectory.appendingPathComponent("\(sanitizedName).stori")
    }
    
    private func projectURL(for project: AudioProject) -> URL {
        return projectURL(for: project.name)
    }
    
    func projectExists(withName name: String) -> Bool {
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
        let oldTempo = project.tempo
        project.tempo = newTempo
        project.modifiedAt = Date()
        
        // CRITICAL: Update all audio regions for tempo change
        // Audio regions are time-locked (duration in seconds is constant),
        // but their beat representation must change with tempo
        for trackIndex in 0..<project.tracks.count {
            for regionIndex in 0..<project.tracks[trackIndex].regions.count {
                project.tracks[trackIndex].regions[regionIndex].updateForTempoChange(newTempo: newTempo)
            }
        }
        
        currentProject = project
        hasUnsavedChanges = true
        
        // Notify audio engine to resync timing references
        // This is critical to prevent MIDI/audio drift during playback
        NotificationCenter.default.post(name: .tempoChanged, object: newTempo)
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
        // Note: MIDI region names are computed from track name via data binding, no manual update needed
        
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

    func updateTrackIcon(_ trackId: UUID, _ iconName: String) {
        guard var project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }

        project.tracks[trackIndex].iconName = iconName
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
            color: duplicatedTrack.color,
            iconName: duplicatedTrack.iconName
        )
        // Copy regions, settings, and plugins
        duplicatedTrack.regions = project.tracks[trackIndex].regions
        duplicatedTrack.mixerSettings = project.tracks[trackIndex].mixerSettings
        duplicatedTrack.pluginConfigs = project.tracks[trackIndex].pluginConfigs
        
        project.tracks.insert(duplicatedTrack, at: trackIndex + 1)
        project.modifiedAt = Date()
        currentProject = project
        hasUnsavedChanges = true
    }
    
    // MARK: - Track Image Management (Phase 5)
    
    /// Set or update the image for a track
    func setTrackImage(_ trackId: UUID, imagePath: URL, imageGeneration: ImageGeneration) {
        guard var project = currentProject else { return }
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        // Create project images directory if needed
        let projectImagesDir = projectDirectory(for: project).appendingPathComponent("Images")
        let trackImagesDir = projectImagesDir.appendingPathComponent(trackId.uuidString)
        
        do {
            try fileManager.createDirectory(at: trackImagesDir, withIntermediateDirectories: true)
            
            // Copy image to project bundle
            let destinationFileName = "\(imageGeneration.id.uuidString).png"
            let destinationURL = trackImagesDir.appendingPathComponent(destinationFileName)
            
            // Remove existing file if it exists
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            
            // Copy the image file
            try fileManager.copyItem(at: imagePath, to: destinationURL)
            
            // Update track with relative path
            let relativePath = "Images/\(trackId.uuidString)/\(destinationFileName)"
            project.tracks[trackIndex].imageAssetPath = relativePath
            
            // Update image generation record with new path
            var updatedGeneration = imageGeneration
            updatedGeneration.imagePath = relativePath
            
            // Add to history (keep last 10)
            project.tracks[trackIndex].imageGenerations.append(updatedGeneration)
            if project.tracks[trackIndex].imageGenerations.count > 10 {
                project.tracks[trackIndex].imageGenerations.removeFirst()
            }
            
            project.modifiedAt = Date()
            currentProject = project
            hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
            
            
        } catch {
            errorMessage = "Failed to set track image: \(error.localizedDescription)"
        }
    }
    
    /// Get the full URL for a track's current image
    func getTrackImageURL(_ trackId: UUID) -> URL? {
        guard let project = currentProject,
              let track = project.tracks.first(where: { $0.id == trackId }),
              let imagePath = track.imageAssetPath else {
            return nil
        }
        
        return projectDirectory(for: project).appendingPathComponent(imagePath)
    }
    
    /// Validate and load track images when loading a project
    private func validateTrackImages(for project: AudioProject) -> AudioProject {
        var updatedProject = project
        let projectDir = projectDirectory(for: project)
        
        for (trackIndex, track) in project.tracks.enumerated() {
            // Check current image
            if let imagePath = track.imageAssetPath {
                let imageURL = projectDir.appendingPathComponent(imagePath)
                if !fileManager.fileExists(atPath: imageURL.path) {
                    updatedProject.tracks[trackIndex].imageAssetPath = nil
                }
            }
            
            // Validate image generation history
            let validGenerations = track.imageGenerations.filter { generation in
                let imageURL = projectDir.appendingPathComponent(generation.imagePath)
                return fileManager.fileExists(atPath: imageURL.path)
            }
            
            if validGenerations.count != track.imageGenerations.count {
                updatedProject.tracks[trackIndex].imageGenerations = validGenerations
            }
        }
        
        return updatedProject
    }
    
    /// Clean up image files when deleting a track
    private func cleanupTrackImages(for track: AudioTrack, in project: AudioProject) {
        guard !track.imageGenerations.isEmpty || track.imageAssetPath != nil else { return }
        
        let projectDir = projectDirectory(for: project)
        let trackImagesDir = projectDir.appendingPathComponent("Images/\(track.id.uuidString)")
        
        do {
            if fileManager.fileExists(atPath: trackImagesDir.path) {
                try fileManager.removeItem(at: trackImagesDir)
            }
        } catch {
        }
    }
    
    /// Get the project directory for a given project
    private func projectDirectory(for project: AudioProject) -> URL {
        let sanitizedName = sanitizeFileName(project.name)
        return projectsDirectory.appendingPathComponent("\(sanitizedName).stori_assets")
    }
    
    /// Create project directory structure
    private func createProjectDirectory(for project: AudioProject) throws {
        let projectDir = projectDirectory(for: project)
        try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
    }
    
    // MARK: - Project Image Management (Project-Level Tokenization)
    
    /// Set or update the project-level image for tokenization
    func setProjectImage(imagePath: URL) {
        guard var project = currentProject else { return }
        
        // Create project images directory if needed
        let projectDir = projectDirectory(for: project)
        let projectImagesDir = projectDir.appendingPathComponent("Images")
        
        do {
            try fileManager.createDirectory(at: projectImagesDir, withIntermediateDirectories: true)
            
            // Generate unique filename for project image
            let destinationFileName = "project_image_\(UUID().uuidString).png"
            let destinationURL = projectImagesDir.appendingPathComponent(destinationFileName)
            
            // Remove old project image if it exists
            if let oldImagePath = project.projectImageAssetPath {
                let oldImageURL = projectDir.appendingPathComponent(oldImagePath)
                if fileManager.fileExists(atPath: oldImageURL.path) {
                    try? fileManager.removeItem(at: oldImageURL)
                }
            }
            
            // Copy the new image file
            try fileManager.copyItem(at: imagePath, to: destinationURL)
            
            // Update project with relative path
            let relativePath = "Images/\(destinationFileName)"
            project.projectImageAssetPath = relativePath
            
            project.modifiedAt = Date()
            currentProject = project
            hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
            
            
        } catch {
            errorMessage = "Failed to set project image: \(error.localizedDescription)"
        }
    }
    
    /// Get the full URL for the project's current image
    func getProjectImageURL() -> URL? {
        guard let project = currentProject,
              let imagePath = project.projectImageAssetPath else {
            return nil
        }
        
        return projectDirectory(for: project).appendingPathComponent(imagePath)
    }
    
    /// Validate project image when loading a project
    private func validateProjectImage(for project: AudioProject) -> AudioProject {
        var updatedProject = project
        let projectDir = projectDirectory(for: project)
        
        // Check project image
        if let imagePath = project.projectImageAssetPath {
            let imageURL = projectDir.appendingPathComponent(imagePath)
            if !fileManager.fileExists(atPath: imageURL.path) {
                updatedProject.projectImageAssetPath = nil
            }
        }
        
        return updatedProject
    }
    
    // MARK: - Audio File Cleanup
    
    /// Clean up audio files associated with a specific track
    private func cleanupAudioFiles(for track: AudioTrack) {
        
        for region in track.regions {
            cleanupAudioFile(region.audioFile)
        }
    }
    
    /// Clean up audio files associated with an entire project
    private func cleanupAudioFiles(for project: AudioProject) {
        
        for track in project.tracks {
            cleanupAudioFiles(for: track)
        }
    }
    
    /// Clean up a specific audio file if it's a generated file
    private func cleanupAudioFile(_ audioFile: AudioFile) {
        let fileURL = audioFile.url
        
        // Only clean up generated audio files (those in the music-gen-service/generated_audio directory)
        if fileURL.path.contains("music-gen-service/generated_audio/") || 
           fileURL.path.contains("generated_audio/") {
            do {
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                } else {
                }
            } catch {
            }
        } else {
        }
    }
    
    /// Clean up ALL orphaned generated audio files (not referenced by any existing project)
    func cleanupOrphanedAudioFiles() {
        
        // Get all audio file URLs referenced by all projects
        var referencedFiles = Set<URL>()
        for project in recentProjects {
            for track in project.tracks {
                for region in track.regions {
                    referencedFiles.insert(region.audioFile.url)
                }
            }
        }
        
        // Also include current project if it's different
        if let currentProject = currentProject, !recentProjects.contains(where: { $0.id == currentProject.id }) {
            for track in currentProject.tracks {
                for region in track.regions {
                    referencedFiles.insert(region.audioFile.url)
                }
            }
        }
        
        
        var totalDeletedCount = 0
        var totalSkippedCount = 0
        
        // 1. Clean the app's temporary directory (downloaded files)
        let tempDirectory = FileManager.default.temporaryDirectory
        
        if fileManager.fileExists(atPath: tempDirectory.path) {
            
            do {
                let contents = try fileManager.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
                
                for fileURL in contents {
                    var isDirectory: ObjCBool = false
                    fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory)
                    if isDirectory.boolValue { continue }
                    
                    let filename = fileURL.lastPathComponent
                    guard fileURL.pathExtension.lowercased() == "wav" &&
                          (filename.hasPrefix("gen_") || filename.hasPrefix("effect_")) else {
                        continue
                    }
                    
                    if !referencedFiles.contains(fileURL) {
                        try? fileManager.removeItem(at: fileURL)
                        totalDeletedCount += 1
                    } else {
                        totalSkippedCount += 1
                    }
                }
            } catch {
            }
        }
        
    }
    
    // MARK: - Project Screenshot Management
    
    /// Capture a screenshot of the timeline view and save it as the project thumbnail
    func captureProjectScreenshot(from view: NSView?) {
        guard let project = currentProject else {
            return
        }
        
        guard let view = view else {
            return
        }
        
        
        Task { [weak self] in
            guard let self else { return }
            // Wait for view to be ready
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            
            // Verify view has reasonable dimensions (not still laying out)
            let viewReady = await MainActor.run {
                view.bounds.width > 100 && view.bounds.height > 100
            }
            
            guard viewReady else {
                // View not ready, schedule retry with longer delay
                try? await Task.sleep(nanoseconds: 500_000_000) // Additional 500ms
                
                let retryReady = await MainActor.run {
                    view.bounds.width > 100 && view.bounds.height > 100
                }
                guard retryReady else {
                    AppLogger.shared.warning("Project screenshot capture failed: view not ready", category: .services)
                    return
                }
                
                guard let screenshot = await self.captureViewScreenshot(view: view) else {
                    return
                }
                
                await self.saveProjectThumbnail(screenshot: screenshot, for: project)
                return
            }
            
            // Capture the view on the main thread
            guard let screenshot = await self.captureViewScreenshot(view: view) else {
                return
            }
            
            // Process and save on background thread
            await self.saveProjectThumbnail(screenshot: screenshot, for: project)
        }
    }
    
    /// Capture a view as an NSImage
    @MainActor
    private func captureViewScreenshot(view: NSView) -> NSImage? {
        
        guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return nil
        }
        
        view.cacheDisplay(in: view.bounds, to: bitmapRep)
        
        let image = NSImage(size: view.bounds.size)
        image.addRepresentation(bitmapRep)
        
        
        // Resize to thumbnail dimensions (280x140 to match card size)
        let resized = resizeImage(image, to: NSSize(width: 560, height: 280)) // 2x for retina
        
        return resized
    }
    
    /// Resize an image to a specific size
    private func resizeImage(_ image: NSImage, to size: NSSize) -> NSImage {
        let resizedImage = NSImage(size: size)
        resizedImage.lockFocus()
        
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: size),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy,
                   fraction: 1.0)
        
        resizedImage.unlockFocus()
        return resizedImage
    }
    
    /// Save the screenshot to the project directory
    private func saveProjectThumbnail(screenshot: NSImage, for project: AudioProject) async {
        let projectDir = projectDirectory(for: project)
        let thumbnailPath = projectDir.appendingPathComponent("thumbnail.png")
        
        
        // Create project directory if needed
        do {
            if !fileManager.fileExists(atPath: projectDir.path) {
                try fileManager.createDirectory(at: projectDir, withIntermediateDirectories: true)
            }
            
            // Convert to PNG data
            guard let tiffData = screenshot.tiffRepresentation else {
                return
            }
            
            guard let bitmapRep = NSBitmapImageRep(data: tiffData) else {
                return
            }
            
            guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
                return
            }
            
            
            // Write to file
            try pngData.write(to: thumbnailPath)
            
            
            // Update project file and recent projects array (DON'T update currentProject - not needed!)
            await MainActor.run {
                guard var updatedProject = currentProject else {
                    return
                }
                updatedProject.projectThumbnailPath = "thumbnail.png"
                
                
                // Write the project file directly (bypasses normal save flow)
                do {
                    let projectURL = projectsDirectory.appendingPathComponent("\(updatedProject.name).stori")
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(updatedProject)
                    try data.write(to: projectURL)
                    
                    // Update ONLY the in-memory recentProjects array so browser shows thumbnail
                    // DON'T update currentProject - it would trigger observers and cause another save!
                    if let index = recentProjects.firstIndex(where: { $0.id == updatedProject.id }) {
                        recentProjects[index] = updatedProject
                    }
                } catch {
                    #if DEBUG
                    print("⚠️ ProjectManager: Failed to save project thumbnail: \(error.localizedDescription)")
                    #endif
                }
            }
            
            
        } catch {
            #if DEBUG
            print("⚠️ ProjectManager: Failed to update project with thumbnail: \(error.localizedDescription)")
            #endif
        }
    }
    
    /// Get the full URL for a project's thumbnail
    func getProjectThumbnailURL(for project: AudioProject) -> URL? {
        guard let thumbnailPath = project.projectThumbnailPath else {
            // No logging here - this gets called on every render and floods the console
            return nil
        }
        
        let projectDir = projectDirectory(for: project)
        let thumbnailURL = projectDir.appendingPathComponent(thumbnailPath)
        
        // Check if file exists
        guard fileManager.fileExists(atPath: thumbnailURL.path) else {
            // Only log missing files for projects that claim to have thumbnails
            return nil
        }
        
        // Thumbnail found successfully (no log spam - this is the happy path)
        return thumbnailURL
    }
    
    // MARK: - Cleanup
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


