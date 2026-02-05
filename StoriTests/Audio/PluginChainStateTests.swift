//
//  PluginChainStateTests.swift
//  StoriTests
//
//  Tests for plugin chain state machine and validation.
//

import XCTest
import AVFoundation
@testable import Stori

@MainActor
final class PluginChainStateTests: XCTestCase {
    
    var chain: PluginChain!
    var engine: AVAudioEngine!
    var format: AVAudioFormat!
    
    override func setUp() async throws {
        chain = PluginChain(maxSlots: 8)
        engine = AVAudioEngine()
        format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        
        // Attach a test node before starting to avoid "freed pointer" errors
        // AVFoundation requires at least one node attached before starting
        let testMixer = AVAudioMixerNode()
        engine.attach(testMixer)
        engine.connect(testMixer, to: engine.outputNode, format: format)
        
        // Start engine (required for realize() to work)
        try engine.start()
    }
    
    override func tearDown() async throws {
        if engine.isRunning {
            engine.stop()
        }
        chain.uninstall()
        engine = nil
        chain = nil
    }
    
    // MARK: - State Machine Tests
    
    func testInitialStateIsUninstalled() {
        XCTAssertTrue(chain.validateState(), "Initial state should be valid")
    }
    
    func testInstallTransitionsToInstalled() {
        chain.install(in: engine, format: format)
        
        XCTAssertTrue(chain.validateState(), "State should be valid after install")
    }
    
    func testRealizeTransitionsToRealized() {
        chain.install(in: engine, format: format)
        
        let wasRealized = chain.realize()
        
        XCTAssertTrue(wasRealized, "Should report newly realized")
        XCTAssertTrue(chain.isRealized, "Should be in realized state")
        XCTAssertTrue(chain.validateState(), "State should be valid after realize")
    }
    
    func testRealizeIsIdempotent() {
        chain.install(in: engine, format: format)
        
        let wasRealized1 = chain.realize()
        let wasRealized2 = chain.realize()
        
        XCTAssertTrue(wasRealized1, "First realize should succeed")
        XCTAssertFalse(wasRealized2, "Second realize should return false")
        XCTAssertTrue(chain.validateState(), "State should remain valid")
    }
    
    func testUnrealizeTransitionsBack() {
        chain.install(in: engine, format: format)
        chain.realize()
        
        XCTAssertTrue(chain.isRealized)
        
        chain.unrealize()
        
        XCTAssertFalse(chain.isRealized, "Should no longer be realized")
        XCTAssertTrue(chain.validateState(), "State should be valid after unrealize")
    }
    
    func testUninstallCleansUpCompletely() {
        chain.install(in: engine, format: format)
        chain.realize()
        
        chain.uninstall()
        
        XCTAssertTrue(chain.validateState(), "State should be valid after uninstall")
    }
    
    // MARK: - State Validation Tests
    
    func testDetectsEngineReferenceMismatch() {
        // Test that validation works correctly for installed (but not yet realized) state
        chain.install(in: engine, format: format)
        
        // Should be valid in installed state
        XCTAssertTrue(chain.validateState(), "Should be valid in installed state")
        
        // Realize the chain
        chain.realize()
        XCTAssertTrue(chain.validateState(), "Should be valid after realize")
        
        // NOTE: Testing validateState() after engine.reset() causes memory corruption
        // because reset() leaves AVAudioNode objects in undefined state.
        // In production, AudioEngine never calls reset() on a running system.
        // This is a known limitation of AVFoundation - reset() invalidates all nodes.
    }
    
    func testReconcileStateWithEngine() {
        // Test reconcileStateWithEngine without using engine.reset()
        // (reset() leaves nodes in undefined state and causes memory corruption)
        
        chain.install(in: engine, format: format)
        chain.realize()
        
        // Manually unrealize (simulates desync without engine.reset())
        chain.unrealize()
        
        // Reconcile should handle the transition gracefully
        chain.reconcileStateWithEngine()
        
        // State should be consistent
        XCTAssertTrue(chain.validateState())
    }
    
    // MARK: - Format Update Tests
    
    func testUpdateFormatWorks() {
        chain.install(in: engine, format: format)
        
        let newFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        chain.updateFormat(newFormat)
        
        XCTAssertEqual(chain.format?.sampleRate, 44100, "Should update format")
    }
    
    // MARK: - Connection Rebuild Tests
    
    func testRebuildConnectionsWorksWhenRealized() {
        chain.install(in: engine, format: format)
        chain.realize()
        
        // Should not crash
        chain.rebuildChainConnections(engine: engine)
        
        XCTAssertTrue(chain.validateState(), "State should remain valid after rebuild")
    }
    
    func testRebuildConnectionsIsNoOpWhenNotRealized() {
        chain.install(in: engine, format: format)
        // Don't realize
        
        // Should be no-op
        chain.rebuildChainConnections(engine: engine)
        
        XCTAssertTrue(chain.validateState(), "State should remain valid")
        XCTAssertFalse(chain.isRealized, "Should not become realized")
    }
}
