//
//  SandboxedPluginHost.swift
//  Stori
//
//  Provides out-of-process plugin hosting for crash isolation.
//  Audio Units v3 support running in a separate process to protect
//  the host DAW from plugin crashes.
//

import Foundation
import AVFoundation
import AudioToolbox

// MARK: - Sandboxed Plugin Host

/// Manages out-of-process plugin instantiation for crash isolation
@MainActor
class SandboxedPluginHost {
    
    // MARK: - Singleton
    
    static let shared = SandboxedPluginHost()
    
    // MARK: - Types
    
    /// Plugin hosting mode
    enum HostingMode: String, CaseIterable {
        case inProcess      // Fast, but crash affects host
        case outOfProcess   // Slower startup, but crash-isolated
        
        var displayName: String {
            switch self {
            case .inProcess: return "In-Process (Fast)"
            case .outOfProcess: return "Sandboxed (Safe)"
            }
        }
        
        var description: String {
            switch self {
            case .inProcess:
                return "Plugin runs in the same process. Fastest performance but a crash will affect the DAW."
            case .outOfProcess:
                return "Plugin runs in a separate process. Slightly slower but isolated from the DAW."
            }
        }
    }
    
    // MARK: - Properties
    
    /// Default hosting mode for new plugins
    var defaultMode: HostingMode = .inProcess
    
    /// Plugins that should always run sandboxed (user preference or crash history)
    private var forceSandboxed: Set<String> = []
    
    /// Plugins known to not support out-of-process
    private var cannotSandbox: Set<String> = []
    
    // MARK: - Initialization
    
    private init() {
        loadPreferences()
    }
    
    // MARK: - Plugin Instantiation
    
    /// Instantiate a plugin with the specified hosting mode
    func instantiate(_ descriptor: PluginDescriptor, mode: HostingMode) async throws -> AVAudioUnit {
        let options: AudioComponentInstantiationOptions
        
        switch mode {
        case .inProcess:
            options = []
        case .outOfProcess:
            options = .loadOutOfProcess
        }
        
        let audioUnit = try await AVAudioUnit.instantiate(
            with: descriptor.componentDescription.audioComponentDescription,
            options: options
        )
        
        return audioUnit
    }
    
    /// Instantiate with automatic mode selection based on plugin history
    func instantiateWithAutoMode(_ descriptor: PluginDescriptor) async throws -> AVAudioUnit {
        let mode = recommendedMode(for: descriptor)
        return try await instantiate(descriptor, mode: mode)
    }
    
    /// Get the recommended hosting mode for a plugin
    func recommendedMode(for descriptor: PluginDescriptor) -> HostingMode {
        let identifier = descriptor.identifier
        
        // Force sandboxed for plugins with crash history
        if forceSandboxed.contains(identifier) {
            return .outOfProcess
        }
        
        // Some plugins don't support out-of-process
        if cannotSandbox.contains(identifier) {
            return .inProcess
        }
        
        return defaultMode
    }
    
    // MARK: - Plugin Capability Checking
    
    /// Check if a plugin likely supports out-of-process hosting
    func supportsOutOfProcess(_ descriptor: PluginDescriptor) -> Bool {
        // AU v3 plugins generally support out-of-process
        // AU v2 plugins wrapped by Apple may have limitations
        
        var desc = descriptor.componentDescription.audioComponentDescription
        guard let component = AudioComponentFindNext(nil, &desc) else {
            return false
        }
        
        // Check component version - AU v3 is more likely to support sandboxing
        var version: UInt32 = 0
        let status = AudioComponentGetVersion(component, &version)
        
        if status == noErr {
            // Version is encoded as 0xMMMMmmPP (major.minor.patch)
            // AU v3 components tend to work better with out-of-process
            return true
        }
        
        return true // Assume support unless proven otherwise
    }
    
    // MARK: - Crash History Management
    
    /// Mark a plugin to always run sandboxed (after crash)
    func markForSandboxing(_ descriptor: PluginDescriptor) {
        forceSandboxed.insert(descriptor.identifier)
        savePreferences()
    }
    
    /// Remove sandboxing requirement for a plugin
    func removeSandboxRequirement(_ descriptor: PluginDescriptor) {
        forceSandboxed.remove(descriptor.identifier)
        savePreferences()
    }
    
    /// Mark a plugin as not supporting out-of-process
    func markAsUnsandboxable(_ descriptor: PluginDescriptor) {
        cannotSandbox.insert(descriptor.identifier)
        savePreferences()
    }
    
    // MARK: - Persistence
    
    private func loadPreferences() {
        let defaults = UserDefaults.standard
        
        if let sandboxed = defaults.stringArray(forKey: "plugin.forceSandboxed") {
            forceSandboxed = Set(sandboxed)
        }
        
        if let unsupported = defaults.stringArray(forKey: "plugin.cannotSandbox") {
            cannotSandbox = Set(unsupported)
        }
        
        if let modeString = defaults.string(forKey: "plugin.defaultMode"),
           let mode = HostingMode(rawValue: modeString) {
            defaultMode = mode
        }
    }
    
    private func savePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(Array(forceSandboxed), forKey: "plugin.forceSandboxed")
        defaults.set(Array(cannotSandbox), forKey: "plugin.cannotSandbox")
        defaults.set(defaultMode.rawValue, forKey: "plugin.defaultMode")
    }
    
    // No async resources owned.
    // No deinit required.
}

// MARK: - PluginDescriptor Extension

extension PluginDescriptor {
    /// Unique identifier string for the plugin
    var identifier: String {
        return "\(manufacturer).\(name)"
    }
}
