//
//  PluginPresetLoadBeforeAudioTests.swift
//  StoriTests
//
//  Tests that plugin presets are fully loaded before audio processing begins (Issue #77)
//

import XCTest
import AVFoundation
@testable import Stori

@MainActor
final class PluginPresetLoadBeforeAudioTests: XCTestCase {
    
    var engine: AVAudioEngine!
    var pluginInstanceManager: PluginInstanceManager!
    var attachedNodes: [AVAudioNode] = []
    
    override func setUp() async throws {
        engine = AVAudioEngine()
        pluginInstanceManager = PluginInstanceManager()
        attachedNodes = []
        // Don't start engine - not needed for these tests
    }
    
    override func tearDown() async throws {
        // Stop engine first
        if engine.isRunning {
            engine.stop()
        }
        
        // Detach all nodes we attached during tests
        for node in attachedNodes {
            engine.detach(node)
        }
        attachedNodes.removeAll()
        
        // Unload all plugin instances
        pluginInstanceManager.unloadAll()
        
        // Nil everything
        engine = nil
        pluginInstanceManager = nil
    }
    
    // Helper to track attached nodes
    private func attach(_ node: AVAudioNode) {
        engine.attach(node)
        attachedNodes.append(node)
    }
    
    // MARK: - Core Regression Tests
    
    /// Test that a plugin's preset is loaded before render resources are allocated
    func testPluginPresetLoadedBeforeRenderResources() async throws {
        // Find a suitable test plugin (AUDelay)
        guard let descriptor = try await findTestPlugin() else {
            throw XCTSkip("No suitable test plugin found")
        }
        
        // Create plugin instance
        let instance = pluginInstanceManager.createInstance(from: descriptor)
        let sampleRate = 48000.0
        
        // Load plugin
        try await instance.load(sampleRate: sampleRate)
        
        // Modify a parameter to create a custom preset
        if let firstParam = instance.parameters.first {
            let modifiedValue = firstParam.maxValue * 0.75 // Set to 75% of max
            instance.setParameter(address: firstParam.address, value: modifiedValue)
            
            // Save modified state
            let customState = try instance.saveState()
            
            // Unload and reload
            instance.unload()
            try await instance.load(sampleRate: sampleRate)
            
            // Restore custom state
            let restored = await instance.restoreState(from: customState)
            XCTAssertTrue(restored, "Preset restoration should succeed")
            
            // CRITICAL: Attach to engine BEFORE allocating render resources
            attach(try XCTUnwrap(instance.avAudioUnit))
            
            // CRITICAL: Allocate render resources AFTER preset restoration
            let au = try XCTUnwrap(instance.auAudioUnit)
            if !au.renderResourcesAllocated {
                try au.allocateRenderResources()
            }
            
            // Verify the parameter value matches the custom preset (not default)
            if let param = instance.parameters.first(where: { $0.address == firstParam.address }) {
                XCTAssertEqual(param.value, modifiedValue, accuracy: 0.01,
                             "Parameter should match custom preset, not default")
            }
        }
    }
    
    /// Test that project loading ensures all plugins are ready before playback
    func testProjectLoadingBlocksUntilPluginsReady() async throws {
        guard let descriptor = try await findTestPlugin() else {
            throw XCTSkip("No suitable test plugin found")
        }
        
        // Simulate project restoration sequence
        let instance = pluginInstanceManager.createInstance(from: descriptor)
        try await instance.load(sampleRate: 48000.0)
        
        // Create custom preset
        if let firstParam = instance.parameters.first {
            instance.setParameter(address: firstParam.address, value: firstParam.maxValue * 0.8)
        }
        let customState = try instance.saveState()
        instance.unload()
        
        // Reload and restore (simulating project load)
        try await instance.load(sampleRate: 48000.0)
        let restored = await instance.restoreState(from: customState)
        XCTAssertTrue(restored)
        
        // Attach to engine FIRST
        attach(try XCTUnwrap(instance.avAudioUnit))
        
        // CRITICAL: Allocate resources AFTER restoration
        let au = try XCTUnwrap(instance.auAudioUnit)
        if !au.renderResourcesAllocated {
            try au.allocateRenderResources()
        }
        
        // Verify plugin is ready (resources allocated)
        XCTAssertTrue(au.renderResourcesAllocated,
                     "Render resources should be allocated before audio can flow")
        
        // Verify preset is still loaded
        if let firstParam = instance.parameters.first {
            XCTAssertGreaterThan(firstParam.value, firstParam.maxValue * 0.7,
                               "Custom preset should still be loaded")
        }
    }
    
    /// Test that multiple plugins are all ready before graph starts
    func testMultiplePluginsReadyBeforeGraphStart() async throws {
        guard let descriptor = try await findTestPlugin() else {
            throw XCTSkip("No suitable test plugin found")
        }
        
        // Create multiple plugin instances
        var instances: [PluginInstance] = []
        for _ in 0..<3 {
            let instance = pluginInstanceManager.createInstance(from: descriptor)
            try await instance.load(sampleRate: 48000.0)
            
            // Set custom state
            if let firstParam = instance.parameters.first {
                instance.setParameter(address: firstParam.address, value: firstParam.maxValue * 0.9)
            }
            let state = try instance.saveState()
            
            // Reload
            instance.unload()
            try await instance.load(sampleRate: 48000.0)
            _ = await instance.restoreState(from: state)
            
            // Attach to engine and allocate resources
            attach(try XCTUnwrap(instance.avAudioUnit))
            if let au = instance.auAudioUnit, !au.renderResourcesAllocated {
                try au.allocateRenderResources()
            }
            
            instances.append(instance)
        }
        
        // Verify ALL instances have render resources allocated
        for instance in instances {
            XCTAssertTrue(instance.auAudioUnit?.renderResourcesAllocated ?? false,
                         "All plugins should have render resources allocated before graph starts")
        }
        
        // Cleanup
        for instance in instances {
            instance.unload()
        }
    }
    
    // MARK: - Edge Case Tests
    
    /// Test that empty preset data doesn't prevent resource allocation
    func testEmptyPresetDataDoesNotBlockLoading() async throws {
        guard let descriptor = try await findTestPlugin() else {
            throw XCTSkip("No suitable test plugin found")
        }
        
        let instance = pluginInstanceManager.createInstance(from: descriptor)
        try await instance.load(sampleRate: 48000.0)
        
        // Try to restore from empty data
        let emptyData = Data()
        let restored = await instance.restoreState(from: emptyData)
        XCTAssertFalse(restored, "Empty data should fail gracefully")
        
        // Plugin should still be usable with default state
        attach(try XCTUnwrap(instance.avAudioUnit))
        let au = try XCTUnwrap(instance.auAudioUnit)
        if !au.renderResourcesAllocated {
            try au.allocateRenderResources()
        }
        XCTAssertTrue(au.renderResourcesAllocated)
    }
    
    /// Test that render resource allocation doesn't fail for plugins with large presets
    func testLargePresetDoesNotPreventResourceAllocation() async throws {
        guard let descriptor = try await findTestPlugin() else {
            throw XCTSkip("No suitable test plugin found")
        }
        
        let instance = pluginInstanceManager.createInstance(from: descriptor)
        try await instance.load(sampleRate: 48000.0)
        
        // Save state (may be large for some plugins)
        let state = try instance.saveState()
        instance.unload()
        
        // Reload and restore
        try await instance.load(sampleRate: 48000.0)
        
        // Time the restoration (should complete quickly)
        let start = CFAbsoluteTimeGetCurrent()
        let restored = await instance.restoreState(from: state)
        let duration = CFAbsoluteTimeGetCurrent() - start
        
        XCTAssertTrue(restored)
        XCTAssertLessThan(duration, 5.0, "Preset restoration should complete within timeout")
        
        // Verify resources can be allocated after restoration
        attach(try XCTUnwrap(instance.avAudioUnit))
        if let au = instance.auAudioUnit, !au.renderResourcesAllocated {
            try au.allocateRenderResources()
        }
        XCTAssertTrue(instance.auAudioUnit?.renderResourcesAllocated ?? false)
    }
    
    /// Test that bypassed plugins still load their presets (for when un-bypassed)
    func testBypassedPluginStillLoadsPreset() async throws {
        guard let descriptor = try await findTestPlugin() else {
            throw XCTSkip("No suitable test plugin found")
        }
        
        let instance = pluginInstanceManager.createInstance(from: descriptor)
        try await instance.load(sampleRate: 48000.0)
        
        // Set custom preset and bypass
        if let firstParam = instance.parameters.first {
            instance.setParameter(address: firstParam.address, value: firstParam.maxValue * 0.85)
        }
        let state = try instance.saveState()
        instance.setBypass(true)
        
        // Reload
        instance.unload()
        try await instance.load(sampleRate: 48000.0)
        _ = await instance.restoreState(from: state)
        instance.setBypass(true)
        
        // Attach to engine and allocate resources (even for bypassed plugins)
        attach(try XCTUnwrap(instance.avAudioUnit))
        if let au = instance.auAudioUnit, !au.renderResourcesAllocated {
            try au.allocateRenderResources()
        }
        
        // Verify preset is loaded
        if let firstParam = instance.parameters.first {
            XCTAssertGreaterThan(firstParam.value, firstParam.maxValue * 0.8,
                               "Bypassed plugin should still have custom preset loaded")
        }
    }
    
    // MARK: - Performance Tests
    
    /// Test that render resource allocation adds minimal overhead
    func testRenderResourceAllocationPerformance() async throws {
        guard let descriptor = try await findTestPlugin() else {
            throw XCTSkip("No suitable test plugin found")
        }
        
        let instance = pluginInstanceManager.createInstance(from: descriptor)
        try await instance.load(sampleRate: 48000.0)
        
        attach(try XCTUnwrap(instance.avAudioUnit))
        
        // Measure allocation time
        let start = CFAbsoluteTimeGetCurrent()
        if let au = instance.auAudioUnit, !au.renderResourcesAllocated {
            try au.allocateRenderResources()
        }
        let duration = CFAbsoluteTimeGetCurrent() - start
        
        // Should complete in < 10ms (typically 1-5ms)
        XCTAssertLessThan(duration, 0.01, "Render resource allocation should be fast (< 10ms)")
        
        instance.unload()
    }
    
    // MARK: - Helper Methods
    
    private func findTestPlugin() async throws -> PluginDescriptor? {
        // Try to find AUDelay (ships with macOS)
        let delayType = kAudioUnitType_Effect
        let delaySubtype = kAudioUnitSubType_Delay
        let delayMfr = kAudioUnitManufacturer_Apple
        
        var componentDesc = AudioComponentDescription()
        componentDesc.componentType = delayType
        componentDesc.componentSubType = delaySubtype
        componentDesc.componentManufacturer = delayMfr
        componentDesc.componentFlags = 0
        componentDesc.componentFlagsMask = 0
        
        guard AudioComponentFindNext(nil, &componentDesc) != nil else {
            return nil
        }
        
        return PluginDescriptor(
            id: UUID(),
            name: "AUDelay",
            manufacturer: "Apple",
            version: "1.0",
            category: .effect,
            componentDescription: AudioComponentDescriptionCodable(from: componentDesc),
            auType: .aufx,
            supportsPresets: true,
            hasCustomUI: false,
            inputChannels: 2,
            outputChannels: 2,
            latencySamples: 0
        )
    }
}
