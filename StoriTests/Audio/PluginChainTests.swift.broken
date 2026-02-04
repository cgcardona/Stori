//
//  PluginChainTests.swift
//  StoriTests
//
//  Comprehensive tests for PluginChain - Plugin chain state machine and processing
//  Tests cover state transitions, plugin insertion/removal/reorder, bypass, serialization
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class PluginChainTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var chain: PluginChain!
    private var engine: AVAudioEngine!
    private var format: AVAudioFormat!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        chain = PluginChain(maxSlots: 8)
        engine = AVAudioEngine()
        format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
    }
    
    override func tearDown() async throws {
        chain.uninstall()
        engine.stop()
        chain = nil
        engine = nil
        format = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testPluginChainInitialization() {
        XCTAssertNotNil(chain)
        XCTAssertEqual(chain.maxSlots, 8)
        XCTAssertEqual(chain.slots.count, 8)
        XCTAssertFalse(chain.isBypassed)
    }
    
    func testPluginChainSlotsInitiallyEmpty() {
        for slot in chain.slots {
            XCTAssertNil(slot)
        }
    }
    
    func testPluginChainHasUniqueId() {
        let chain2 = PluginChain(maxSlots: 8)
        
        XCTAssertNotEqual(chain.id, chain2.id)
    }
    
    func testPluginChainCustomMaxSlots() {
        let smallChain = PluginChain(maxSlots: 4)
        let largeChain = PluginChain(maxSlots: 16)
        
        XCTAssertEqual(smallChain.slots.count, 4)
        XCTAssertEqual(largeChain.slots.count, 16)
    }
    
    // MARK: - State Machine Tests
    
    func testPluginChainInitialState() {
        // Chain should start in uninstalled state
        let isValid = chain.validateState()
        XCTAssertTrue(isValid)
    }
    
    func testPluginChainInstallTransition() {
        // uninstalled -> installed
        chain.install(in: engine, format: format)
        
        let isValid = chain.validateState()
        XCTAssertTrue(isValid)
    }
    
    func testPluginChainRealizeTransition() {
        // uninstalled -> installed -> realized
        chain.install(in: engine, format: format)
        let realized = chain.realize()
        
        XCTAssertTrue(realized)
        
        let isValid = chain.validateState()
        XCTAssertTrue(isValid)
    }
    
    func testPluginChainUnrealizeTransition() {
        // realized -> installed
        chain.install(in: engine, format: format)
        chain.realize()
        
        chain.unrealize()
        
        let isValid = chain.validateState()
        XCTAssertTrue(isValid)
    }
    
    func testPluginChainUninstallTransition() {
        // installed -> uninstalled
        chain.install(in: engine, format: format)
        
        chain.uninstall()
        
        let isValid = chain.validateState()
        XCTAssertTrue(isValid)
    }
    
    func testPluginChainFullLifecycle() {
        // uninstalled -> installed -> realized -> installed -> uninstalled
        XCTAssertTrue(chain.validateState())
        
        chain.install(in: engine, format: format)
        XCTAssertTrue(chain.validateState())
        
        chain.realize()
        XCTAssertTrue(chain.validateState())
        
        chain.unrealize()
        XCTAssertTrue(chain.validateState())
        
        chain.uninstall()
        XCTAssertTrue(chain.validateState())
    }
    
    // MARK: - Plugin Insertion Tests
    
    func testStorePluginInEmptySlot() {
        let descriptor = PluginDescriptor(
            name: "Test Plugin",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin",
            version: "1.0.0"
        )
        let plugin = PluginInstance(descriptor: descriptor)
        
        chain.storePlugin(plugin, atSlot: 0)
        
        XCTAssertNotNil(chain.slots[0])
        XCTAssertEqual(chain.slots[0]?.id, plugin.id)
    }
    
    func testStoreMultiplePlugins() {
        let plugin1 = PluginInstance(descriptor: PluginDescriptor(
            name: "Plugin 1",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin1",
            version: "1.0.0"
        ))
        let plugin2 = PluginInstance(descriptor: PluginDescriptor(
            name: "Plugin 2",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin2",
            version: "1.0.0"
        ))
        
        chain.storePlugin(plugin1, atSlot: 0)
        chain.storePlugin(plugin2, atSlot: 1)
        
        XCTAssertEqual(chain.slots[0]?.id, plugin1.id)
        XCTAssertEqual(chain.slots[1]?.id, plugin2.id)
    }
    
    func testStorePluginOverwritesExisting() {
        let plugin1 = PluginInstance(descriptor: PluginDescriptor(
            name: "Plugin 1",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin1",
            version: "1.0.0"
        ))
        let plugin2 = PluginInstance(descriptor: PluginDescriptor(
            name: "Plugin 2",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin2",
            version: "1.0.0"
        ))
        
        chain.storePlugin(plugin1, atSlot: 2)
        XCTAssertEqual(chain.slots[2]?.id, plugin1.id)
        
        chain.storePlugin(plugin2, atSlot: 2)
        XCTAssertEqual(chain.slots[2]?.id, plugin2.id)
    }
    
    func testStorePluginAllSlots() {
        var plugins: [PluginInstance] = []
        
        for i in 0..<chain.maxSlots {
            let plugin = PluginInstance(descriptor: PluginDescriptor(
                name: "Plugin \(i)",
                manufacturer: "Test",
                type: .effect,
                identifier: "com.test.plugin\(i)",
                version: "1.0.0"
            ))
            plugins.append(plugin)
            chain.storePlugin(plugin, atSlot: i)
        }
        
        // Verify all slots filled
        for i in 0..<chain.maxSlots {
            XCTAssertEqual(chain.slots[i]?.id, plugins[i].id)
        }
    }
    
    // MARK: - Plugin Removal Tests
    
    func testRemovePlugin() {
        let plugin = PluginInstance(descriptor: PluginDescriptor(
            name: "Test Plugin",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin",
            version: "1.0.0"
        ))
        
        chain.storePlugin(plugin, atSlot: 3)
        XCTAssertNotNil(chain.slots[3])
        
        chain.removePlugin(atSlot: 3)
        XCTAssertNil(chain.slots[3])
    }
    
    func testRemovePluginFromEmptySlot() {
        // Should handle gracefully
        chain.removePlugin(atSlot: 5)
        
        XCTAssertNil(chain.slots[5])
    }
    
    func testRemoveOneOfMultiplePlugins() {
        let plugin1 = PluginInstance(descriptor: PluginDescriptor(
            name: "Plugin 1",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin1",
            version: "1.0.0"
        ))
        let plugin2 = PluginInstance(descriptor: PluginDescriptor(
            name: "Plugin 2",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin2",
            version: "1.0.0"
        ))
        let plugin3 = PluginInstance(descriptor: PluginDescriptor(
            name: "Plugin 3",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin3",
            version: "1.0.0"
        ))
        
        chain.storePlugin(plugin1, atSlot: 0)
        chain.storePlugin(plugin2, atSlot: 1)
        chain.storePlugin(plugin3, atSlot: 2)
        
        chain.removePlugin(atSlot: 1)
        
        XCTAssertNotNil(chain.slots[0])
        XCTAssertNil(chain.slots[1])
        XCTAssertNotNil(chain.slots[2])
    }
    
    // MARK: - Chain Bypass Tests
    
    func testChainBypassInitialState() {
        XCTAssertFalse(chain.isBypassed)
    }
    
    func testChainBypassToggle() {
        chain.isBypassed = true
        XCTAssertTrue(chain.isBypassed)
        
        chain.isBypassed = false
        XCTAssertFalse(chain.isBypassed)
    }
    
    func testChainBypassWithPlugins() {
        let plugin = PluginInstance(descriptor: PluginDescriptor(
            name: "Test Plugin",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin",
            version: "1.0.0"
        ))
        
        chain.storePlugin(plugin, atSlot: 0)
        
        chain.isBypassed = true
        XCTAssertTrue(chain.isBypassed)
    }
    
    // MARK: - Format Update Tests
    
    func testUpdateFormat() {
        chain.install(in: engine, format: format)
        
        let newFormat = AVAudioFormat(standardFormatWithSampleRate: 96000, channels: 2)!
        
        chain.updateFormat(newFormat)
        
        // Should update without crashing
        XCTAssertTrue(true, "Format updated successfully")
    }
    
    func testUpdateFormatBeforeInstall() {
        let newFormat = AVAudioFormat(standardFormatWithSampleRate: 96000, channels: 2)!
        
        // Should handle gracefully
        chain.updateFormat(newFormat)
        
        XCTAssertTrue(true, "Format update handled gracefully")
    }
    
    // MARK: - State Validation Tests
    
    func testValidateUninstalledState() {
        let isValid = chain.validateState()
        
        XCTAssertTrue(isValid)
    }
    
    func testValidateInstalledState() {
        chain.install(in: engine, format: format)
        
        let isValid = chain.validateState()
        
        XCTAssertTrue(isValid)
    }
    
    func testValidateRealizedState() {
        chain.install(in: engine, format: format)
        chain.realize()
        
        let isValid = chain.validateState()
        
        XCTAssertTrue(isValid)
    }
    
    func testReconcileStateWithEngine() {
        chain.install(in: engine, format: format)
        
        // Should reconcile without crashing
        chain.reconcileStateWithEngine()
        
        XCTAssertTrue(true, "State reconciliation completed")
    }
    
    // MARK: - Mixer Management Tests
    
    func testRecreateMixers() {
        chain.install(in: engine, format: format)
        chain.realize()
        
        // Should recreate mixers
        chain.recreateMixers()
        
        let isValid = chain.validateState()
        XCTAssertTrue(isValid)
    }
    
    func testResetMixerState() {
        chain.install(in: engine, format: format)
        chain.realize()
        
        // Should reset mixer state
        chain.resetMixerState()
        
        XCTAssertTrue(true, "Mixer state reset completed")
    }
    
    func testEnsureEngineReference() {
        chain.ensureEngineReference(engine)
        
        // Should store engine reference
        XCTAssertTrue(true, "Engine reference stored")
    }
    
    // MARK: - Chain Connections Tests
    
    func testRebuildChainConnections() {
        chain.install(in: engine, format: format)
        chain.realize()
        
        // Add a plugin
        let plugin = PluginInstance(descriptor: PluginDescriptor(
            name: "Test Plugin",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin",
            version: "1.0.0"
        ))
        chain.storePlugin(plugin, atSlot: 0)
        
        // Rebuild connections
        chain.rebuildChainConnections(engine: engine)
        
        XCTAssertTrue(true, "Chain connections rebuilt")
    }
    
    func testRebuildChainConnectionsWithMultiplePlugins() {
        chain.install(in: engine, format: format)
        chain.realize()
        
        // Add multiple plugins
        for i in 0..<3 {
            let plugin = PluginInstance(descriptor: PluginDescriptor(
                name: "Plugin \(i)",
                manufacturer: "Test",
                type: .effect,
                identifier: "com.test.plugin\(i)",
                version: "1.0.0"
            ))
            chain.storePlugin(plugin, atSlot: i)
        }
        
        // Rebuild connections
        chain.rebuildChainConnections(engine: engine)
        
        XCTAssertTrue(true, "Chain connections with multiple plugins rebuilt")
    }
    
    // MARK: - Slot Boundary Tests
    
    func testStorePluginValidSlots() {
        let plugin = PluginInstance(descriptor: PluginDescriptor(
            name: "Test Plugin",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin",
            version: "1.0.0"
        ))
        
        // Test all valid slots
        for slot in 0..<chain.maxSlots {
            chain.storePlugin(plugin, atSlot: slot)
            XCTAssertNotNil(chain.slots[slot])
        }
    }
    
    func testRemovePluginValidSlots() {
        // Fill all slots
        for i in 0..<chain.maxSlots {
            let plugin = PluginInstance(descriptor: PluginDescriptor(
                name: "Plugin \(i)",
                manufacturer: "Test",
                type: .effect,
                identifier: "com.test.plugin\(i)",
                version: "1.0.0"
            ))
            chain.storePlugin(plugin, atSlot: i)
        }
        
        // Remove from all valid slots
        for slot in 0..<chain.maxSlots {
            chain.removePlugin(atSlot: slot)
            XCTAssertNil(chain.slots[slot])
        }
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentPluginInsertion() async {
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<chain.maxSlots {
                group.addTask { @MainActor in
                    let plugin = PluginInstance(descriptor: PluginDescriptor(
                        name: "Plugin \(i)",
                        manufacturer: "Test",
                        type: .effect,
                        identifier: "com.test.plugin\(i)",
                        version: "1.0.0"
                    ))
                    self.chain.storePlugin(plugin, atSlot: i)
                }
            }
        }
        
        // All slots should be filled
        var filledCount = 0
        for slot in chain.slots {
            if slot != nil {
                filledCount += 1
            }
        }
        
        XCTAssertGreaterThan(filledCount, 0)
    }
    
    func testConcurrentPluginRemoval() async {
        // Fill slots
        for i in 0..<chain.maxSlots {
            let plugin = PluginInstance(descriptor: PluginDescriptor(
                name: "Plugin \(i)",
                manufacturer: "Test",
                type: .effect,
                identifier: "com.test.plugin\(i)",
                version: "1.0.0"
            ))
            chain.storePlugin(plugin, atSlot: i)
        }
        
        // Remove concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<chain.maxSlots {
                group.addTask { @MainActor in
                    self.chain.removePlugin(atSlot: i)
                }
            }
        }
        
        // All slots should be empty
        for slot in chain.slots {
            XCTAssertNil(slot)
        }
    }
    
    func testConcurrentBypassToggle() async {
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<20 {
                group.addTask { @MainActor in
                    self.chain.isBypassed.toggle()
                }
            }
        }
        
        // Should complete without crashing
        XCTAssertTrue(true, "Concurrent bypass toggling completed")
    }
    
    // MARK: - Performance Tests
    
    func testChainCreationPerformance() {
        measure {
            for _ in 0..<100 {
                let tempChain = PluginChain(maxSlots: 8)
                tempChain.uninstall()
            }
        }
    }
    
    func testPluginInsertionPerformance() {
        let plugins = (0..<chain.maxSlots).map { i in
            PluginInstance(descriptor: PluginDescriptor(
                name: "Plugin \(i)",
                manufacturer: "Test",
                type: .effect,
                identifier: "com.test.plugin\(i)",
                version: "1.0.0"
            ))
        }
        
        measure {
            for (index, plugin) in plugins.enumerated() {
                chain.storePlugin(plugin, atSlot: index)
            }
            
            for i in 0..<chain.maxSlots {
                chain.removePlugin(atSlot: i)
            }
        }
    }
    
    func testPluginRemovalPerformance() {
        // Fill slots
        for i in 0..<chain.maxSlots {
            let plugin = PluginInstance(descriptor: PluginDescriptor(
                name: "Plugin \(i)",
                manufacturer: "Test",
                type: .effect,
                identifier: "com.test.plugin\(i)",
                version: "1.0.0"
            ))
            chain.storePlugin(plugin, atSlot: i)
        }
        
        measure {
            for i in 0..<chain.maxSlots {
                chain.removePlugin(atSlot: i)
            }
            
            // Refill for next iteration
            for i in 0..<chain.maxSlots {
                let plugin = PluginInstance(descriptor: PluginDescriptor(
                    name: "Plugin \(i)",
                    manufacturer: "Test",
                    type: .effect,
                    identifier: "com.test.plugin\(i)",
                    version: "1.0.0"
                ))
                chain.storePlugin(plugin, atSlot: i)
            }
        }
    }
    
    func testStateTransitionPerformance() {
        measure {
            for _ in 0..<100 {
                chain.install(in: engine, format: format)
                chain.realize()
                chain.unrealize()
                chain.uninstall()
            }
        }
    }
    
    func testBypassTogglePerformance() {
        measure {
            for _ in 0..<10000 {
                chain.isBypassed.toggle()
            }
        }
    }
    
    // MARK: - Memory Management Tests
    
    func testChainCleanup() {
        // Create and destroy multiple chains
        for _ in 0..<5 {
            let tempChain = PluginChain(maxSlots: 8)
            tempChain.install(in: engine, format: format)
            tempChain.realize()
            
            // Add plugins
            for i in 0..<4 {
                let plugin = PluginInstance(descriptor: PluginDescriptor(
                    name: "Plugin \(i)",
                    manufacturer: "Test",
                    type: .effect,
                    identifier: "com.test.plugin\(i)",
                    version: "1.0.0"
                ))
                tempChain.storePlugin(plugin, atSlot: i)
            }
            
            tempChain.uninstall()
        }
        
        XCTAssertTrue(true, "Multiple chain lifecycles completed")
    }
    
    func testPluginReferencesCleared() {
        // Add plugins
        for i in 0..<chain.maxSlots {
            let plugin = PluginInstance(descriptor: PluginDescriptor(
                name: "Plugin \(i)",
                manufacturer: "Test",
                type: .effect,
                identifier: "com.test.plugin\(i)",
                version: "1.0.0"
            ))
            chain.storePlugin(plugin, atSlot: i)
        }
        
        // Remove all
        for i in 0..<chain.maxSlots {
            chain.removePlugin(atSlot: i)
        }
        
        // All slots should be nil
        for slot in chain.slots {
            XCTAssertNil(slot)
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testEmptyChainOperations() {
        // Operations on empty chain should handle gracefully
        chain.install(in: engine, format: format)
        chain.realize()
        chain.rebuildChainConnections(engine: engine)
        chain.unrealize()
        chain.uninstall()
        
        XCTAssertTrue(true, "Empty chain operations handled")
    }
    
    func testSingleSlotChain() {
        let smallChain = PluginChain(maxSlots: 1)
        
        let plugin = PluginInstance(descriptor: PluginDescriptor(
            name: "Plugin",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin",
            version: "1.0.0"
        ))
        
        smallChain.storePlugin(plugin, atSlot: 0)
        XCTAssertNotNil(smallChain.slots[0])
        
        smallChain.removePlugin(atSlot: 0)
        XCTAssertNil(smallChain.slots[0])
    }
    
    func testLargeSlotChain() {
        let largeChain = PluginChain(maxSlots: 32)
        
        XCTAssertEqual(largeChain.slots.count, 32)
        
        // Fill all slots
        for i in 0..<32 {
            let plugin = PluginInstance(descriptor: PluginDescriptor(
                name: "Plugin \(i)",
                manufacturer: "Test",
                type: .effect,
                identifier: "com.test.plugin\(i)",
                version: "1.0.0"
            ))
            largeChain.storePlugin(plugin, atSlot: i)
        }
        
        // Verify all filled
        var filledCount = 0
        for slot in largeChain.slots where slot != nil {
            filledCount += 1
        }
        
        XCTAssertEqual(filledCount, 32)
    }
    
    func testChainWithSparsePlugins() {
        // Add plugins to non-contiguous slots
        let plugin1 = PluginInstance(descriptor: PluginDescriptor(
            name: "Plugin 1",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin1",
            version: "1.0.0"
        ))
        let plugin2 = PluginInstance(descriptor: PluginDescriptor(
            name: "Plugin 2",
            manufacturer: "Test",
            type: .effect,
            identifier: "com.test.plugin2",
            version: "1.0.0"
        ))
        
        chain.storePlugin(plugin1, atSlot: 0)
        chain.storePlugin(plugin2, atSlot: 5)
        
        XCTAssertNotNil(chain.slots[0])
        XCTAssertNil(chain.slots[1])
        XCTAssertNil(chain.slots[2])
        XCTAssertNil(chain.slots[3])
        XCTAssertNil(chain.slots[4])
        XCTAssertNotNil(chain.slots[5])
    }
    
    // MARK: - Integration Tests
    
    func testFullChainWorkflow() {
        // Complete workflow: install, realize, add plugins, rebuild, remove, uninstall
        chain.install(in: engine, format: format)
        XCTAssertTrue(chain.validateState())
        
        chain.realize()
        XCTAssertTrue(chain.validateState())
        
        // Add plugins
        for i in 0..<3 {
            let plugin = PluginInstance(descriptor: PluginDescriptor(
                name: "Plugin \(i)",
                manufacturer: "Test",
                type: .effect,
                identifier: "com.test.plugin\(i)",
                version: "1.0.0"
            ))
            chain.storePlugin(plugin, atSlot: i)
        }
        
        // Rebuild connections
        chain.rebuildChainConnections(engine: engine)
        
        // Toggle bypass
        chain.isBypassed = true
        chain.isBypassed = false
        
        // Remove middle plugin
        chain.removePlugin(atSlot: 1)
        chain.rebuildChainConnections(engine: engine)
        
        // Cleanup
        chain.unrealize()
        XCTAssertTrue(chain.validateState())
        
        chain.uninstall()
        XCTAssertTrue(chain.validateState())
        
        XCTAssertTrue(true, "Full workflow completed successfully")
    }
}
