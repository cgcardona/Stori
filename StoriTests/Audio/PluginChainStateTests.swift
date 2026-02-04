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
        
        // Start engine
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
        chain.install(in: engine, format: format)
        chain.realize()
        
        // Simulate engine reset that detaches nodes
        engine.stop()
        engine.reset()
        
        // Chain thinks it's realized but mixers are actually detached
        // This would be caught by validateState()
        let isValid = chain.validateState()
        
        // After engine.reset(), nodes are detached so state should be invalid
        XCTAssertFalse(isValid, "Should detect desync after engine.reset()")
    }
    
    func testReconcileStateFixesDesync() {
        chain.install(in: engine, format: format)
        chain.realize()
        
        // Force desync
        engine.stop()
        engine.reset()
        
        // Should detect invalid state
        XCTAssertFalse(chain.validateState())
        
        // Reconcile
        chain.reconcileStateWithEngine()
        
        // State should now match reality (installed but not realized)
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
