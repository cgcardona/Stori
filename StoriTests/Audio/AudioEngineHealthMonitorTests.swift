//
//  AudioEngineHealthMonitorTests.swift
//  StoriTests
//
//  Tests for audio engine health monitoring and validation.
//

import XCTest
import AVFoundation
@testable import Stori

@MainActor
final class AudioEngineHealthMonitorTests: XCTestCase {
    
    var monitor: AudioEngineHealthMonitor!
    var engine: AVAudioEngine!
    var mixer: AVAudioMixerNode!
    var masterEQ: AVAudioUnitEQ!
    var masterLimiter: AVAudioUnitEffect!
    var graphFormat: AVAudioFormat!
    
    override func setUp() async throws {
        monitor = AudioEngineHealthMonitor()
        engine = AVAudioEngine()
        mixer = AVAudioMixerNode()
        masterEQ = AVAudioUnitEQ(numberOfBands: 3)
        masterLimiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_PeakLimiter,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        ))
        
        // Create standard format
        graphFormat = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        
        // Configure monitor
        monitor.configure(
            engine: engine,
            mixer: mixer,
            masterEQ: masterEQ,
            masterLimiter: masterLimiter,
            getGraphFormat: { [weak self] in self?.graphFormat },
            getIsGraphStable: { true },
            getIsGraphReady: { true },
            getTrackNodes: { [:] }
        )
    }
    
    override func tearDown() async throws {
        if engine.isRunning {
            engine.stop()
        }
        engine = nil
        mixer = nil
        monitor = nil
    }
    
    // MARK: - Basic Validation Tests
    
    func testValidatesHealthyEngine() throws {
        // Setup healthy engine
        engine.attach(mixer)
        engine.attach(masterEQ)
        engine.attach(masterLimiter)
        engine.connect(mixer, to: masterEQ, format: graphFormat)
        engine.connect(masterEQ, to: masterLimiter, format: graphFormat)
        engine.connect(masterLimiter, to: engine.outputNode, format: graphFormat)
        
        try engine.start()
        
        let result = monitor.validateState()
        
        XCTAssertTrue(result.isValid, "Healthy engine should pass validation")
        XCTAssertTrue(result.issues.isEmpty, "Healthy engine should have no issues")
        XCTAssertTrue(monitor.currentHealth.isHealthy, "Health status should be healthy")
    }
    
    func testDetectsEngineNotRunning() throws {
        // Setup engine but don't start it
        engine.attach(mixer)
        
        // Mark as ready (desync scenario)
        monitor.configure(
            engine: engine,
            mixer: mixer,
            masterEQ: masterEQ,
            masterLimiter: masterLimiter,
            getGraphFormat: { [weak self] in self?.graphFormat },
            getIsGraphStable: { true },
            getIsGraphReady: { true },  // Graph marked ready but engine not running
            getTrackNodes: { [:] }
        )
        
        let result = monitor.validateState()
        
        XCTAssertFalse(result.isValid, "Should detect engine not running when marked as ready")
        XCTAssertFalse(result.criticalIssues.isEmpty, "Should report critical issue")
    }
    
    func testDetectsMixerNotAttached() throws {
        // Don't attach mixer - validate without starting
        // (Starting would cause AVFoundation to assert)
        
        let result = monitor.validateState()
        
        XCTAssertFalse(result.isValid, "Should detect mixer not attached")
        XCTAssertFalse(result.criticalIssues.isEmpty, "Should report critical issue")
    }
    
    func testDetectsMixerAttachedToWrongEngine() throws {
        // Attach mixer to wrong engine
        let wrongEngine = AVAudioEngine()
        wrongEngine.attach(mixer)
        
        // Don't start engine - validate without starting
        // (Starting would cause AVFoundation to assert)
        
        let result = monitor.validateState()
        
        XCTAssertFalse(result.isValid, "Should detect mixer attached to wrong engine")
        XCTAssertFalse(result.criticalIssues.isEmpty, "Should report critical issue")
    }
    
    func testDetectsFormatMismatch() throws {
        // Setup engine
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: graphFormat)
        try engine.start()
        
        // Change hardware format (simulate device change) by using different graphFormat
        let mismatchedFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        graphFormat = mismatchedFormat
        
        let result = monitor.validateState()
        
        // Should detect format mismatch as warning
        XCTAssertTrue(result.issues.contains { $0.component == "Format" }, "Should detect format mismatch")
    }
    
    // MARK: - Quick Validate Tests
    
    func testQuickValidatePassesForHealthyEngine() throws {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: graphFormat)
        try engine.start()
        
        XCTAssertTrue(monitor.quickValidate(), "Quick validate should pass for healthy engine")
    }
    
    func testQuickValidateFailsForStoppedEngine() throws {
        engine.attach(mixer)
        // Don't start engine
        
        XCTAssertFalse(monitor.quickValidate(), "Quick validate should fail when engine not running")
    }
    
    func testQuickValidateFailsForUnattachedMixer() throws {
        // Don't attach mixer and don't start engine
        // (Starting would cause AVFoundation to assert)
        
        XCTAssertFalse(monitor.quickValidate(), "Quick validate should fail when mixer not attached")
    }
    
    // MARK: - Recovery Suggestions Tests
    
    func testProvidesRecoverySuggestions() throws {
        // Create unhealthy state - attach nodes but don't connect or start
        // (This creates a detectable unhealthy state without crashing AVFoundation)
        engine.attach(mixer)
        engine.attach(masterEQ)
        engine.attach(masterLimiter)
        // Don't connect nodes - this creates unhealthy state
        
        monitor.configure(
            engine: engine,
            mixer: mixer,
            masterEQ: masterEQ,
            masterLimiter: masterLimiter,
            getGraphFormat: { [weak self] in self?.graphFormat },
            getIsGraphStable: { true },
            getIsGraphReady: { true },  // Marked as ready but not actually ready
            getTrackNodes: { [:] }
        )
        
        let _ = monitor.validateState()
        
        let suggestions = monitor.getRecoverySuggestions()
        
        XCTAssertFalse(suggestions.isEmpty, "Should provide recovery suggestions for unhealthy state")
    }
}
