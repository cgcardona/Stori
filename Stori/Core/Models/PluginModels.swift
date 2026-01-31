//
//  PluginModels.swift
//  Stori
//
//  Audio Unit plugin models for third-party plugin hosting.
//

import Foundation
import AVFoundation
import AudioToolbox

// MARK: - Plugin Descriptor

/// Represents a discovered Audio Unit plugin installed on the system
struct PluginDescriptor: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let manufacturer: String
    let version: String
    let category: PluginCategory
    let componentDescription: AudioComponentDescriptionCodable
    let auType: AUType
    let supportsPresets: Bool
    let hasCustomUI: Bool
    let inputChannels: Int
    let outputChannels: Int
    let latencySamples: Int
    
    /// Plugin categories
    enum PluginCategory: String, Codable, CaseIterable {
        case effect
        case instrument
        case midiEffect
        case generator
        case unknown
        
        var displayName: String {
            switch self {
            case .effect: return "Effect"
            case .instrument: return "Instrument"
            case .midiEffect: return "MIDI Effect"
            case .generator: return "Generator"
            case .unknown: return "Unknown"
            }
        }
    }
    
    /// Audio Unit types (four-character codes)
    enum AUType: String, Codable {
        case aufx  // Effect
        case aumu  // Music Device (Instrument)
        case aumf  // Music Effect (MIDI-controlled effect)
        case auou  // Output
        case augn  // Generator
        
        var displayName: String {
            switch self {
            case .aufx: return "Effect"
            case .aumu: return "Instrument"
            case .aumf: return "MIDI Effect"
            case .auou: return "Output"
            case .augn: return "Generator"
            }
        }
    }
}

// MARK: - Audio Component Description (Codable Wrapper)

/// Codable wrapper for AudioComponentDescription
struct AudioComponentDescriptionCodable: Codable, Hashable {
    let componentType: UInt32
    let componentSubType: UInt32
    let componentManufacturer: UInt32
    let componentFlags: UInt32
    let componentFlagsMask: UInt32
    
    /// Convert to native AudioComponentDescription
    var audioComponentDescription: AudioComponentDescription {
        AudioComponentDescription(
            componentType: componentType,
            componentSubType: componentSubType,
            componentManufacturer: componentManufacturer,
            componentFlags: componentFlags,
            componentFlagsMask: componentFlagsMask
        )
    }
    
    /// Create from native AudioComponentDescription
    init(from description: AudioComponentDescription) {
        self.componentType = description.componentType
        self.componentSubType = description.componentSubType
        self.componentManufacturer = description.componentManufacturer
        self.componentFlags = description.componentFlags
        self.componentFlagsMask = description.componentFlagsMask
    }
    
    /// Manual initializer for all fields
    init(componentType: UInt32, componentSubType: UInt32, componentManufacturer: UInt32, componentFlags: UInt32, componentFlagsMask: UInt32) {
        self.componentType = componentType
        self.componentSubType = componentSubType
        self.componentManufacturer = componentManufacturer
        self.componentFlags = componentFlags
        self.componentFlagsMask = componentFlagsMask
    }
}

// MARK: - Plugin Parameter

/// Represents a single plugin parameter exposed by an Audio Unit
struct PluginParameter: Identifiable {
    var id: UInt64 { address }
    let address: AUParameterAddress
    let name: String
    var value: AUValue
    let minValue: AUValue
    let maxValue: AUValue
    let unit: String
    let flags: AudioUnitParameterOptions
    
    /// Normalized value between 0 and 1
    var normalizedValue: Float {
        guard maxValue > minValue else { return 0 }
        return (value - minValue) / (maxValue - minValue)
    }
    
    /// Set value from normalized 0-1 range
    mutating func setNormalizedValue(_ normalized: Float) {
        value = minValue + (normalized * (maxValue - minValue))
    }
}

// MARK: - Plugin Errors

enum PluginError: Error, LocalizedError {
    case stateNotAvailable
    case invalidPresetData
    case instantiationFailed
    case formatMismatch
    case formatNegotiationFailed
    case pluginNotLoaded
    case parameterNotFound(AUParameterAddress)
    
    var errorDescription: String? {
        switch self {
        case .stateNotAvailable:
            return "Plugin state is not available"
        case .invalidPresetData:
            return "Invalid preset data format"
        case .instantiationFailed:
            return "Failed to instantiate plugin"
        case .formatMismatch:
            return "Audio format mismatch"
        case .formatNegotiationFailed:
            return "Plugin refused all available audio formats"
        case .pluginNotLoaded:
            return "Plugin is not loaded"
        case .parameterNotFound(let address):
            return "Parameter not found: \(address)"
        }
    }
}

// MARK: - Saved Preset

/// Represents a user-saved plugin preset
struct SavedPluginPreset: Identifiable, Codable {
    let id: UUID
    let name: String
    let pluginId: UUID
    let createdAt: Date
    let filePath: String
    
    init(id: UUID = UUID(), name: String, pluginId: UUID, createdAt: Date = Date(), filePath: String) {
        self.id = id
        self.name = name
        self.pluginId = pluginId
        self.createdAt = createdAt
        self.filePath = filePath
    }
}

// MARK: - Plugin Slot

/// Represents a plugin slot in a track or bus effect chain
struct PluginSlot: Identifiable, Codable {
    let id: UUID
    var pluginDescriptorId: UUID?
    var presetId: UUID?
    var isBypassed: Bool
    var parameters: [String: Float]  // Serializable parameter state
    
    init(id: UUID = UUID(), pluginDescriptorId: UUID? = nil, presetId: UUID? = nil, isBypassed: Bool = false, parameters: [String: Float] = [:]) {
        self.id = id
        self.pluginDescriptorId = pluginDescriptorId
        self.presetId = presetId
        self.isBypassed = isBypassed
        self.parameters = parameters
    }
    
    var isEmpty: Bool {
        pluginDescriptorId == nil
    }
}
