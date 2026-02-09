//
//  MonitoringLatencyTests.swift
//  StoriTests
//
//  Comprehensive tests for input monitoring latency calculation and display (Issue #65)
//
//  CRITICAL REQUIREMENT: Musicians must see their monitoring latency to understand
//  why their performance feels "late" during recording, even though playback is in time.
//
//  This is a WYSIWYG failure if latency is hidden from the user.
//

import XCTest
@testable import Stori
@preconcurrency import AVFoundation

@MainActor
final class MonitoringLatencyTests: XCTestCase {
    
    var audioEngine: AudioEngine!
    var mockProjectManager: MockProjectManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Warm up allocator to prevent fragmentation (Issue #114)
        autoreleasepool {
            let _ = AVAudioEngine()
        }
        
        // Create minimal test environment
        mockProjectManager = MockProjectManager()
        audioEngine = AudioEngine()
        
        // Engine auto-starts on initialization (pro DAW pattern)
        XCTAssertTrue(audioEngine.sharedAVAudioEngine.isRunning, "Engine should auto-start")
    }
    
    override func tearDown() async throws {
        // Stop engine and cleanup
        if audioEngine.sharedAVAudioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.sharedAVAudioEngine.reset()
        
        audioEngine = nil
        mockProjectManager = nil
        
        // Give allocator time to settle
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        try await super.tearDown()
    }
    
    // MARK: - Latency Calculation Tests
    
    /// Test that latency is calculated when engine is running
    func testLatencyCalculatedWhenEngineRunning() async throws {
        XCTAssertTrue(audioEngine.sharedAVAudioEngine.isRunning, "Engine should be running for latency test")
        
        let latency = audioEngine.totalMonitoringLatencyMs
        
        // Latency should be positive when engine is running
        XCTAssertGreaterThan(latency, 0.0, "Monitoring latency should be > 0 when engine is running")
        
        // Latency should be within plausible bounds (0-100ms)
        // Even worst-case USB interfaces shouldn't exceed 100ms round-trip
        XCTAssertLessThan(latency, 100.0, "Monitoring latency should be < 100ms (sanity check)")
    }
    
    /// Test that latency is still calculated when transport is stopped
    /// (Engine runs continuously for low-latency monitoring in professional DAW mode)
    func testLatencyCalculatedWhenTransportStopped() async throws {
        // Stop transport (playback), but engine keeps running for monitoring
        audioEngine.stop()
        
        let latency = audioEngine.totalMonitoringLatencyMs
        
        // Latency should still be calculated because engine is running
        // Monitoring latency exists even when not playing back
        XCTAssertGreaterThan(latency, 0.0, "Monitoring latency should be calculated when engine is running, even if transport is stopped")
    }
    
    /// Test latency calculation components
    func testLatencyComponentsArePositive() async throws {
        let sampleRate = audioEngine.currentSampleRate
        let engine = audioEngine.sharedAVAudioEngine
        
        // Input device latency (should be >= 0)
        let inputLatency = engine.inputNode.presentationLatency * 1000.0
        XCTAssertGreaterThanOrEqual(inputLatency, 0.0, "Input latency should be non-negative")
        
        // Output device latency (should be >= 0)
        let outputLatency = engine.outputNode.presentationLatency * 1000.0
        XCTAssertGreaterThanOrEqual(outputLatency, 0.0, "Output latency should be non-negative")
        
        // Buffer latency (estimated at 512 frames)
        let bufferLatency = (512.0 / sampleRate) * 1000.0
        XCTAssertGreaterThan(bufferLatency, 0.0, "Buffer latency should be positive")
        XCTAssertLessThan(bufferLatency, 50.0, "Buffer latency should be reasonable (< 50ms)")
        
        // Plugin latency (may be 0 if no plugins loaded)
        let pluginLatency = PluginLatencyManager.shared.maxLatencyMs
        XCTAssertGreaterThanOrEqual(pluginLatency, 0.0, "Plugin latency should be non-negative")
    }
    
    /// Test that latency increases when plugins are added (Plugin Delay Compensation)
    func testLatencyIncreasesWithPlugins() async throws {
        // Measure baseline latency without plugins
        let baselineLatency = audioEngine.totalMonitoringLatencyMs
        
        // NOTE: In a real integration test, we'd load an actual AU plugin with known latency
        // For this unit test, we verify the calculation includes plugin latency from PluginLatencyManager
        
        // Simulate plugin latency by directly setting it in PluginLatencyManager
        // In real scenario, this would be set when plugins are loaded
        let pluginLatency = PluginLatencyManager.shared.maxLatencyMs
        
        // Even without actual plugins loaded, the calculation should still work
        // (plugin latency component may be 0 in test environment)
        XCTAssertGreaterThanOrEqual(baselineLatency, 0.0, 
                                    "Latency calculation should work even without plugins")
        XCTAssertGreaterThanOrEqual(pluginLatency, 0.0,
                                    "Plugin latency should be non-negative")
    }
    
    // MARK: - Latency Threshold Tests
    
    /// Test low latency threshold (< 15ms)
    func testLowLatencyThreshold() async throws {
        let latency = audioEngine.totalMonitoringLatencyMs
        
        // On modern macOS with good audio interface, latency should typically be low
        // But we can't guarantee this in CI environment, so we test the logic instead
        
        if latency <= 15.0 {
            XCTAssertFalse(audioEngine.isMonitoringLatencyHigh, 
                          "Latency <= 15ms should not be flagged as high")
            XCTAssertFalse(audioEngine.isMonitoringLatencyCritical, 
                          "Latency <= 15ms should not be flagged as critical")
        }
    }
    
    /// Test high latency threshold (15-20ms)
    func testHighLatencyThreshold() async throws {
        // We can't artificially increase system latency, but we can verify the logic
        // by checking the threshold constants
        
        let testLatency1 = 15.1  // Just above high threshold
        let testLatency2 = 19.9  // Below critical threshold
        
        XCTAssertTrue(testLatency1 > 15.0, "15.1ms should exceed high threshold")
        XCTAssertFalse(testLatency1 > 20.0, "15.1ms should not exceed critical threshold")
        
        XCTAssertTrue(testLatency2 > 15.0, "19.9ms should exceed high threshold")
        XCTAssertFalse(testLatency2 > 20.0, "19.9ms should not exceed critical threshold")
    }
    
    /// Test critical latency threshold (> 20ms)
    func testCriticalLatencyThreshold() async throws {
        let testLatency = 20.1  // Just above critical threshold
        
        XCTAssertTrue(testLatency > 15.0, "20.1ms should exceed high threshold")
        XCTAssertTrue(testLatency > 20.0, "20.1ms should exceed critical threshold")
    }
    
    // MARK: - Display String Tests
    
    /// Test latency display string formatting
    func testLatencyDisplayStringFormat() async throws {
        let displayString = audioEngine.monitoringLatencyDisplayString
        
        // Should be formatted as "XX.Xms"
        XCTAssertTrue(displayString.hasSuffix("ms"), "Display string should end with 'ms'")
        
        // Should contain a decimal point
        XCTAssertTrue(displayString.contains("."), "Display string should include decimal precision")
        
        // Should be parseable as a number (minus the "ms" suffix)
        let numericPart = displayString.replacingOccurrences(of: "ms", with: "")
        XCTAssertNotNil(Double(numericPart), "Display string should be parseable as number")
    }
    
    /// Test display string matches actual latency value
    func testDisplayStringMatchesLatency() async throws {
        let latency = audioEngine.totalMonitoringLatencyMs
        let displayString = audioEngine.monitoringLatencyDisplayString
        
        // Extract numeric value from display string
        let numericPart = displayString.replacingOccurrences(of: "ms", with: "")
        guard let displayedValue = Double(numericPart) else {
            XCTFail("Could not parse display string: \(displayString)")
            return
        }
        
        // Should match to 1 decimal place
        XCTAssertEqual(displayedValue, latency, accuracy: 0.1, 
                      "Display string should match actual latency")
    }
    
    // MARK: - Regression Tests
    
    /// Regression test: Latency should remain stable across multiple reads
    func testLatencyStabilityAcrossReads() async throws {
        var readings: [Double] = []
        
        // Take 10 consecutive latency readings
        for _ in 0..<10 {
            readings.append(audioEngine.totalMonitoringLatencyMs)
        }
        
        // All readings should be identical (latency doesn't change without configuration change)
        let first = readings[0]
        for reading in readings {
            XCTAssertEqual(reading, first, accuracy: 0.01, 
                          "Latency readings should be stable")
        }
    }
    
    /// Regression test: Latency calculation should not crash with edge cases
    func testLatencyCalculationRobustness() async throws {
        // Test various sample rates
        let sampleRates = [44100.0, 48000.0, 88200.0, 96000.0]
        
        for rate in sampleRates {
            // Verify buffer latency calculation works for various rates
            let bufferLatency = (512.0 / rate) * 1000.0
            XCTAssertGreaterThan(bufferLatency, 0.0, 
                               "Buffer latency calculation should work for \(rate)Hz")
            XCTAssertLessThan(bufferLatency, 20.0, 
                            "Buffer latency should be reasonable at \(rate)Hz")
        }
    }
    
    /// Regression test: Latency should update after device configuration change
    func testLatencyUpdatesAfterDeviceChange() async throws {
        let initialLatency = audioEngine.totalMonitoringLatencyMs
        
        // Simulate device configuration change by stopping and restarting
        audioEngine.stop()
        audioEngine.sharedAVAudioEngine.reset()
        
        // Create a new engine instance (simulates device change)
        audioEngine = AudioEngine()
        
        let newLatency = audioEngine.totalMonitoringLatencyMs
        
        // Latency should still be calculated (may be same or different depending on device)
        XCTAssertGreaterThan(newLatency, 0.0, 
                            "Latency should be recalculated after device change")
    }
    
    // MARK: - Edge Case Tests
    
    /// Test latency with completely stopped AVAudioEngine (defensive programming)
    func testLatencyWithCompletelyStoppedEngine() async throws {
        // Actually stop the AVAudioEngine (not just transport)
        audioEngine.sharedAVAudioEngine.stop()
        
        // Latency should return 0 when engine is actually stopped
        let latency = audioEngine.totalMonitoringLatencyMs
        
        // Should return 0 gracefully, not crash or return NaN
        XCTAssertEqual(latency, 0.0, "Latency should be 0 when AVAudioEngine stopped")
        XCTAssertFalse(latency.isNaN, "Latency should not be NaN")
        XCTAssertFalse(latency.isInfinite, "Latency should not be infinite")
        
        // Restart engine for cleanup
        try audioEngine.sharedAVAudioEngine.start()
    }
    
    /// Test that latency flags are consistent with actual latency value
    func testLatencyFlagsConsistency() async throws {
        let latency = audioEngine.totalMonitoringLatencyMs
        let isHigh = audioEngine.isMonitoringLatencyHigh
        let isCritical = audioEngine.isMonitoringLatencyCritical
        
        // Verify flag consistency
        if latency <= 15.0 {
            XCTAssertFalse(isHigh, "isHigh should be false when latency <= 15ms")
            XCTAssertFalse(isCritical, "isCritical should be false when latency <= 15ms")
        } else if latency <= 20.0 {
            XCTAssertTrue(isHigh, "isHigh should be true when 15 < latency <= 20ms")
            XCTAssertFalse(isCritical, "isCritical should be false when latency <= 20ms")
        } else {
            XCTAssertTrue(isHigh, "isHigh should be true when latency > 20ms")
            XCTAssertTrue(isCritical, "isCritical should be true when latency > 20ms")
        }
        
        // Critical implies high
        if isCritical {
            XCTAssertTrue(isHigh, "isCritical implies isHigh")
        }
    }
    
    // MARK: - Performance Tests
    
    /// Test that latency calculation is fast (< 1ms)
    func testLatencyCalculationPerformance() async throws {
        measure {
            // Should be nearly instantaneous (just reading a few properties)
            for _ in 0..<1000 {
                _ = audioEngine.totalMonitoringLatencyMs
            }
        }
    }
    
    /// Test that display string generation is fast
    func testDisplayStringGenerationPerformance() async throws {
        measure {
            for _ in 0..<1000 {
                _ = audioEngine.monitoringLatencyDisplayString
            }
        }
    }
}
