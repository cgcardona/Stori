//
//  ServiceValidation.swift
//  Stori
//
//  Design validation and smoke tests for core services.
//  Run these during development to verify service behavior.
//
//  Usage: Call ServiceValidation.runAll() from a debug menu or console.
//

import Foundation
import AVFoundation

// MARK: - Service Validation

/// Validates the design and behavior of core services.
/// Not intended for production - use for development verification.
@MainActor
struct ServiceValidation {
    
    // MARK: - Run All Validations
    
    /// Run all service validations and log results.
    static func runAll() async {
        
        var passed = 0
        var failed = 0
        
        // UndoService
        if validateUndoService() { passed += 1 } else { failed += 1 }
        
        // PluginGreylist
        if validatePluginGreylist() { passed += 1 } else { failed += 1 }
        
        // PluginLatencyManager
        if validatePluginLatencyManager() { passed += 1 } else { failed += 1 }
        
        // AudioFileReferenceManager
        if validateAudioFileReferenceManager() { passed += 1 } else { failed += 1 }
        
        // Automation Curve Types
        if validateAutomationCurves() { passed += 1 } else { failed += 1 }
        
        // Clip Effects
        if validateClipEffects() { passed += 1 } else { failed += 1 }
        
    }
    
    // MARK: - UndoService Validation
    
    private static func validateUndoService() -> Bool {
        
        let service = UndoService.shared
        
        // Test 1: Initial state
        guard !service.canUndo else {
            return false
        }
        
        // Test 2: Register an undo
        var testValue = 0
        service.registerUndo(actionName: "Test Action") {
            testValue = 0
        } redo: {
            testValue = 1
        }
        testValue = 1
        
        guard service.canUndo else {
            return false
        }
        
        // Test 3: Perform undo
        service.undo()
        guard testValue == 0 else {
            return false
        }
        
        // Clean up
        service.clearHistory()
        
        return true
    }
    
    // MARK: - PluginGreylist Validation
    
    private static func validatePluginGreylist() -> Bool {
        
        // Test: Singleton exists and is accessible
        let greylist = PluginGreylist.shared
        
        // Verify the service is initialized (accessing it doesn't crash)
        _ = greylist
        
        return true
    }
    
    // MARK: - PluginLatencyManager Validation
    
    private static func validatePluginLatencyManager() -> Bool {
        
        let manager = PluginLatencyManager.shared
        
        // Test 1: Initial state
        manager.reset()
        guard manager.maxLatencySamples == 0 else {
            return false
        }
        
        // Test 2: PDC can be enabled/disabled
        manager.isEnabled = false
        guard !manager.isEnabled else {
            return false
        }
        manager.isEnabled = true
        
        // Test 3: Sample rate can be set
        manager.setSampleRate(48000)
        
        return true
    }
    
    // MARK: - AudioFileReferenceManager Validation
    
    private static func validateAudioFileReferenceManager() -> Bool {
        
        let manager = AudioFileReferenceManager.shared
        
        // Test 1: Relative path detection
        guard manager.isRelativePath("Audio/file.wav") else {
            return false
        }
        
        // Test 2: Absolute path detection
        guard !manager.isRelativePath("/Users/test/file.wav") else {
            return false
        }
        
        return true
    }
    
    // MARK: - Automation Curves Validation
    
    private static func validateAutomationCurves() -> Bool {
        
        // Test all curve types exist and have icons
        for curveType in CurveType.allCases {
            guard !curveType.icon.isEmpty else {
                return false
            }
        }
        
        // Test Bezier control point
        let controlPoint = BezierControlPoint(beatOffset: 0.5, valueOffset: 0.1)
        let absolutePos = controlPoint.absolutePosition(from: (beat: 1.0, value: 0.5))
        guard absolutePos.beat == 1.5 && absolutePos.value == 0.6 else {
            return false
        }
        
        // Test automation point with tension
        let point = AutomationPoint(beat: 0, value: 0.5, curve: .smooth, tension: 0.5)
        guard point.tension == 0.5 else {
            return false
        }
        
        return true
    }
    
    // MARK: - Clip Effects Validation
    
    private static func validateClipEffects() -> Bool {
        
        // Test clip effect creation
        let effect = ClipEffect(effectType: .pitchShift(semitones: 2.0))
        guard effect.isEnabled && !effect.isBypassed else {
            return false
        }
        
        // Test display name
        guard effect.effectType.displayName.contains("Pitch Shift") else {
            return false
        }
        
        // Test all effect types have icons
        let testTypes: [ClipEffectType] = [
            .pitchShift(semitones: 0),
            .timeStretch(ratio: 1.0),
            .gain(dB: 0),
            .highPassFilter(frequencyHz: 100),
            .lowPassFilter(frequencyHz: 20000),
            .polarityInvert,
            .reverse
        ]
        
        for effectType in testTypes {
            guard !effectType.iconName.isEmpty else {
                return false
            }
        }
        
        // Test region with clip effects
        let audioFile = AudioFile(
            name: "test.wav",
            url: URL(fileURLWithPath: "/tmp/test.wav"),
            duration: 10.0,
            sampleRate: 48000,
            channels: 2,
            fileSize: 1000,
            format: .wav
        )
        
        var region = AudioRegion(audioFile: audioFile)
        guard !region.hasActiveClipEffects else {
            return false
        }
        
        region.clipEffects.append(effect)
        guard region.hasActiveClipEffects else {
            return false
        }
        
        return true
    }
}

// MARK: - Debug Menu Integration

extension ServiceValidation {
    /// Add to app's debug menu
    static var debugMenuAction: String {
        "Validate Services"
    }
}
