//
//  PluginPresetManager.swift
//  Stori
//
//  Manages saving and loading of user presets for Audio Unit plugins.
//

import Foundation
import AVFoundation
import Observation

// MARK: - Plugin Preset Manager

@MainActor
@Observable
class PluginPresetManager {
    static let shared = PluginPresetManager()
    
    // MARK: - Observable Properties
    
    var userPresets: [UUID: [SavedPluginPreset]] = [:]
    var favoritePlugins: Set<UUID> = []
    var recentlyUsed: [UUID] = []
    
    // MARK: - Private Properties
    
    @ObservationIgnored
    private let presetsDirectory: URL
    @ObservationIgnored
    private let favoritesURL: URL
    @ObservationIgnored
    private let recentsURL: URL
    @ObservationIgnored
    private let maxRecent = 20
    
    // MARK: - Initialization
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let baseDir = appSupport.appendingPathComponent("Stori")
        
        self.presetsDirectory = baseDir.appendingPathComponent("Presets")
        self.favoritesURL = baseDir.appendingPathComponent("PluginFavorites.json")
        self.recentsURL = baseDir.appendingPathComponent("PluginRecents.json")
        
        // Create directories
        try? FileManager.default.createDirectory(at: presetsDirectory, withIntermediateDirectories: true)
        
        // Load saved data
        loadFavorites()
        loadRecents()
        loadAllPresets()
    }
    
    
    // MARK: - Preset Management
    
    /// Save a preset for a plugin
    func savePreset(for plugin: PluginInstance, named name: String) throws -> SavedPluginPreset {
        let presetData = try plugin.saveState()
        
        let presetId = UUID()
        let fileName = "\(presetId.uuidString).aupreset"
        let pluginDir = presetsDirectory.appendingPathComponent(plugin.descriptor.id.uuidString)
        let fileURL = pluginDir.appendingPathComponent(fileName)
        
        // Create plugin preset directory
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        
        // Write preset data
        try presetData.write(to: fileURL)
        
        let savedPreset = SavedPluginPreset(
            id: presetId,
            name: name,
            pluginId: plugin.descriptor.id,
            createdAt: Date(),
            filePath: fileName
        )
        
        // Update cache
        var presets = userPresets[plugin.descriptor.id] ?? []
        presets.append(savedPreset)
        userPresets[plugin.descriptor.id] = presets
        
        // Save metadata
        try savePresetMetadata(for: plugin.descriptor.id)
        
        
        return savedPreset
    }
    
    /// Load a saved preset into a plugin (async for non-blocking restore)
    func loadPreset(_ preset: SavedPluginPreset, into plugin: PluginInstance) async throws {
        let pluginDir = presetsDirectory.appendingPathComponent(preset.pluginId.uuidString)
        let fileURL = pluginDir.appendingPathComponent(preset.filePath)
        
        let data = try Data(contentsOf: fileURL)
        let restored = await plugin.restoreState(from: data)
        
        plugin.currentPresetName = preset.name
        
        if !restored {
            AppLogger.shared.warning("Preset '\(preset.name)' restoration incomplete for plugin", category: .audio)
        }
    }
    
    /// Delete a saved preset
    func deletePreset(_ preset: SavedPluginPreset) throws {
        let pluginDir = presetsDirectory.appendingPathComponent(preset.pluginId.uuidString)
        let fileURL = pluginDir.appendingPathComponent(preset.filePath)
        
        try FileManager.default.removeItem(at: fileURL)
        
        // Update cache
        var presets = userPresets[preset.pluginId] ?? []
        presets.removeAll { $0.id == preset.id }
        userPresets[preset.pluginId] = presets
        
        // Save metadata
        try savePresetMetadata(for: preset.pluginId)
        
    }
    
    /// Get all presets for a plugin
    func getPresets(for pluginId: UUID) -> [SavedPluginPreset] {
        return userPresets[pluginId] ?? []
    }
    
    /// Rename a preset
    func renamePreset(_ preset: SavedPluginPreset, to newName: String) throws {
        guard var presets = userPresets[preset.pluginId],
              let index = presets.firstIndex(where: { $0.id == preset.id }) else {
            return
        }
        
        let updatedPreset = SavedPluginPreset(
            id: preset.id,
            name: newName,
            pluginId: preset.pluginId,
            createdAt: preset.createdAt,
            filePath: preset.filePath
        )
        
        presets[index] = updatedPreset
        userPresets[preset.pluginId] = presets
        
        try savePresetMetadata(for: preset.pluginId)
    }
    
    // MARK: - Favorites
    
    /// Add a plugin to favorites
    func addToFavorites(_ pluginId: UUID) {
        favoritePlugins.insert(pluginId)
        saveFavorites()
    }
    
    /// Remove a plugin from favorites
    func removeFromFavorites(_ pluginId: UUID) {
        favoritePlugins.remove(pluginId)
        saveFavorites()
    }
    
    /// Check if a plugin is a favorite
    func isFavorite(_ pluginId: UUID) -> Bool {
        favoritePlugins.contains(pluginId)
    }
    
    /// Toggle favorite status
    func toggleFavorite(_ pluginId: UUID) {
        if favoritePlugins.contains(pluginId) {
            favoritePlugins.remove(pluginId)
        } else {
            favoritePlugins.insert(pluginId)
        }
        saveFavorites()
    }
    
    // MARK: - Recently Used
    
    /// Record that a plugin was used
    func recordUsage(_ pluginId: UUID) {
        recentlyUsed.removeAll { $0 == pluginId }
        recentlyUsed.insert(pluginId, at: 0)
        
        if recentlyUsed.count > maxRecent {
            recentlyUsed.removeLast()
        }
        
        saveRecents()
    }
    
    // MARK: - Persistence
    
    private func savePresetMetadata(for pluginId: UUID) throws {
        let presets = userPresets[pluginId] ?? []
        let pluginDir = presetsDirectory.appendingPathComponent(pluginId.uuidString)
        let metadataURL = pluginDir.appendingPathComponent("metadata.json")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(presets)
        try data.write(to: metadataURL)
    }
    
    private func loadAllPresets() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: presetsDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        
        for pluginDir in contents {
            guard pluginDir.hasDirectoryPath,
                  let pluginId = UUID(uuidString: pluginDir.lastPathComponent) else { continue }
            
            let metadataURL = pluginDir.appendingPathComponent("metadata.json")
            
            if let data = try? Data(contentsOf: metadataURL),
               let presets = try? JSONDecoder().decode([SavedPluginPreset].self, from: data) {
                userPresets[pluginId] = presets
            }
        }
    }
    
    private func saveFavorites() {
        do {
            let data = try JSONEncoder().encode(Array(favoritePlugins))
            try data.write(to: favoritesURL)
        } catch {
        }
    }
    
    private func loadFavorites() {
        guard let data = try? Data(contentsOf: favoritesURL),
              let favorites = try? JSONDecoder().decode([UUID].self, from: data) else { return }
        favoritePlugins = Set(favorites)
    }
    
    private func saveRecents() {
        do {
            let data = try JSONEncoder().encode(recentlyUsed)
            try data.write(to: recentsURL)
        } catch {
        }
    }
    
    private func loadRecents() {
        guard let data = try? Data(contentsOf: recentsURL),
              let recents = try? JSONDecoder().decode([UUID].self, from: data) else { return }
        recentlyUsed = recents
    }
    
    // MARK: - Cleanup
}
