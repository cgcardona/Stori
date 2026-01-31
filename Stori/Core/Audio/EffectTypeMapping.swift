//
//  EffectTypeMapping.swift
//  Stori
//
//  Maps effect type strings to actual Apple AU plugin component codes
//  Used by AI Command Dispatcher for creating plugin configs
//

import Foundation

/// Maps effect type strings to Apple AU plugins
enum EffectTypeMapping {
    
    /// Convert effect type string to AU component codes
    static func auComponentForEffectType(_ effectType: String) -> (type: UInt32, subType: UInt32, name: String)? {
        switch effectType.lowercased() {
        case "reverb":
            return (
                type: 1635083896,      // 'aufx'
                subType: 1920361010,    // 'mvrb' - AUMatrixReverb
                name: "AUMatrixReverb"
            )
            
        case "delay":
            return (
                type: 1635083896,      // 'aufx'
                subType: 1684108385,    // 'dely' - AUDelay
                name: "AUDelay"
            )
            
        case "chorus":
            return (
                type: 1635083896,      // 'aufx'
                subType: 1684108385,    // 'dely' - AUDelay (chorus is delay-based)
                name: "AUDelay"
            )
            
        case "compressor":
            return (
                type: 1635083896,      // 'aufx'
                subType: 1684237673,    // 'dcmp' - AUDynamicsProcessor
                name: "AUDynamicsProcessor"
            )
            
        case "eq":
            return (
                type: 1635083896,      // 'aufx'
                subType: 1851942257,    // 'nbeq' - AUNBandEQ
                name: "AUNBandEQ"
            )
            
        case "distortion":
            return (
                type: 1635083896,      // 'aufx'
                subType: 1684632434,    // 'dist' - AUDistortion
                name: "AUDistortion"
            )
            
        case "filter":
            return (
                type: 1635083896,      // 'aufx'
                subType: 1718185076,    // 'filt' - AUFilter
                name: "AUFilter"
            )
            
        case "modulation":
            return (
                type: 1635083896,      // 'aufx'
                subType: 1684108385,    // 'dely' - AUDelay (modulation uses delay)
                name: "AUDelay"
            )
            
        default:
            return nil
        }
    }
    
    /// Create PluginConfiguration from effect type string
    static func createPluginConfig(effectType: String, slotIndex: Int) -> PluginConfiguration? {
        guard let mapping = auComponentForEffectType(effectType) else {
            return nil
        }
        
        let componentDesc = AudioComponentDescriptionCodable(
            componentType: mapping.type,
            componentSubType: mapping.subType,
            componentManufacturer: 1634758764,  // 'appl'
            componentFlags: 0,
            componentFlagsMask: 0
        )
        
        return PluginConfiguration(
            slotIndex: slotIndex,
            componentDescription: componentDesc,
            pluginName: mapping.name,
            manufacturerName: "Apple",
            isBypassed: false,
            fullState: nil
        )
    }
}
