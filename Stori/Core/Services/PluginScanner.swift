//
//  PluginScanner.swift
//  Stori
//
//  Discovers and catalogs Audio Unit plugins installed on the system.
//

import Foundation
import AVFoundation
import AudioToolbox
import CoreAudioKit
import Observation

// MARK: - Plugin Scanner

/// Scans for and catalogs all Audio Unit plugins installed on the system
@MainActor
@Observable
class PluginScanner {
    
    // MARK: - Observable Properties
    
    var discoveredPlugins: [PluginDescriptor] = []
    var isScanning: Bool = false
    var scanProgress: Double = 0.0
    var lastScanDate: Date?
    var scanError: String?
    
    // MARK: - Computed Properties
    
    /// All effect plugins
    var effectPlugins: [PluginDescriptor] {
        discoveredPlugins.filter { $0.category == .effect }
    }
    
    /// All instrument plugins
    var instrumentPlugins: [PluginDescriptor] {
        discoveredPlugins.filter { $0.category == .instrument }
    }
    
    /// All MIDI effect plugins
    var midiEffectPlugins: [PluginDescriptor] {
        discoveredPlugins.filter { $0.category == .midiEffect }
    }
    
    /// All generator plugins
    var generatorPlugins: [PluginDescriptor] {
        discoveredPlugins.filter { $0.category == .generator }
    }
    
    /// All unique manufacturers
    var manufacturers: [String] {
        Array(Set(discoveredPlugins.map(\.manufacturer))).sorted()
    }
    
    // MARK: - Private Properties
    
    @ObservationIgnored
    private let cacheURL: URL
    @ObservationIgnored
    private var validatedPlugins: Set<UUID> = []
    
    // MARK: - Initialization
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cacheDir = appSupport.appendingPathComponent("Stori")
        self.cacheURL = cacheDir.appendingPathComponent("PluginCache.json")
        
        // Ensure cache directory exists
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    nonisolated deinit {}

    // MARK: - Public Methods
    
    /// Scan for all installed Audio Units
    func scanForPlugins() async {
        isScanning = true
        scanProgress = 0.0
        scanError = nil
        discoveredPlugins.removeAll()
        
        
        // Scan effects (aufx)
        await scanAudioUnitType(kAudioUnitType_Effect, category: .effect, auType: .aufx)
        scanProgress = 0.25
        
        // Scan instruments (aumu)
        await scanAudioUnitType(kAudioUnitType_MusicDevice, category: .instrument, auType: .aumu)
        scanProgress = 0.50
        
        // Scan MIDI effects (aumf)
        await scanAudioUnitType(kAudioUnitType_MusicEffect, category: .midiEffect, auType: .aumf)
        scanProgress = 0.75
        
        // Scan generators (augn)
        await scanAudioUnitType(kAudioUnitType_Generator, category: .generator, auType: .augn)
        scanProgress = 1.0
        
        // Sort by name
        discoveredPlugins.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        
        // Cache results
        await cachePluginList()
        
        lastScanDate = Date()
        isScanning = false
        
    }
    
    /// Load cached plugin list (fast startup)
    func loadCachedPlugins() async {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else {
            return
        }
        
        do {
            let data = try Data(contentsOf: cacheURL)
            let cache = try JSONDecoder().decode(PluginCache.self, from: data)
            discoveredPlugins = cache.plugins
            lastScanDate = cache.scanDate
        } catch {
            scanError = "Failed to load plugin cache"
        }
    }
    
    /// Find a plugin by its ID
    func plugin(withId id: UUID) -> PluginDescriptor? {
        discoveredPlugins.first { $0.id == id }
    }
    
    /// Search plugins by name or manufacturer
    func search(query: String, category: PluginDescriptor.PluginCategory? = nil, manufacturer: String? = nil) -> [PluginDescriptor] {
        discoveredPlugins.filter { plugin in
            let matchesQuery = query.isEmpty ||
                plugin.name.localizedCaseInsensitiveContains(query) ||
                plugin.manufacturer.localizedCaseInsensitiveContains(query)
            let matchesCategory = category == nil || plugin.category == category
            let matchesManufacturer = manufacturer == nil || plugin.manufacturer == manufacturer
            return matchesQuery && matchesCategory && matchesManufacturer
        }
    }
    
    // MARK: - Private Methods
    
    private func scanAudioUnitType(_ type: UInt32, category: PluginDescriptor.PluginCategory, auType: PluginDescriptor.AUType) async {
        var desc = AudioComponentDescription(
            componentType: type,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        var component: AudioComponent? = AudioComponentFindNext(nil, &desc)
        
        while let comp = component {
            if let plugin = createPluginDescriptor(from: comp, category: category, auType: auType) {
                discoveredPlugins.append(plugin)
            }
            component = AudioComponentFindNext(comp, &desc)
        }
    }
    
    private func createPluginDescriptor(from component: AudioComponent, category: PluginDescriptor.PluginCategory, auType: PluginDescriptor.AUType) -> PluginDescriptor? {
        var desc = AudioComponentDescription()
        let descStatus = AudioComponentGetDescription(component, &desc)
        guard descStatus == noErr else { return nil }
        
        // Get plugin name
        var nameRef: Unmanaged<CFString>?
        let nameStatus = AudioComponentCopyName(component, &nameRef)
        guard nameStatus == noErr else { return nil }
        
        let fullName = nameRef?.takeRetainedValue() as String? ?? "Unknown"
        
        // Parse "Manufacturer: Plugin Name" format (Apple's standard naming)
        let parts = fullName.split(separator: ":", maxSplits: 1)
        let manufacturer: String
        let name: String
        
        if parts.count > 1 {
            manufacturer = Self.sanitizePluginName(String(parts[0]).trimmingCharacters(in: .whitespaces))
            name = Self.sanitizePluginName(String(parts[1]).trimmingCharacters(in: .whitespaces))
        } else {
            manufacturer = "Unknown"
            name = Self.sanitizePluginName(fullName)
        }
        // Get version
        var version: UInt32 = 0
        AudioComponentGetVersion(component, &version)
        let versionString = "\(version >> 16).\((version >> 8) & 0xFF).\(version & 0xFF)"
        
        // Create codable component description
        let codableDesc = AudioComponentDescriptionCodable(from: desc)
        
        return PluginDescriptor(
            id: UUID(),
            name: name,
            manufacturer: manufacturer,
            version: versionString,
            category: category,
            componentDescription: codableDesc,
            auType: auType,
            supportsPresets: true,  // Most AUs support presets
            hasCustomUI: true,      // Determined during instantiation
            inputChannels: 2,       // Default stereo, determined during instantiation
            outputChannels: 2,      // Default stereo, determined during instantiation
            latencySamples: 0       // Determined during instantiation
        )
    }
    
    private static func sanitizePluginName(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-")
        s = s.replacingOccurrences(of: "\\", with: "-")
        s = s.replacingOccurrences(of: "..", with: "")
        if s.count > 100 { s = String(s.prefix(100)) }
        return s
    }

    private func cachePluginList() async {
        do {
            let cache = PluginCache(plugins: discoveredPlugins, scanDate: Date())
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL)
        } catch {
        }
    }
    
    // MARK: - Cleanup
}

// MARK: - Cache Model

private struct PluginCache: Codable {
    let plugins: [PluginDescriptor]
    let scanDate: Date
}
