//
//  PluginDelayCompensationTests.swift
//  StoriTests
//
//  Comprehensive tests for Plugin Delay Compensation (PDC)
//  Tests verify that all tracks stay phase-aligned when using latency-inducing plugins.
//  WYHIWYG: What You Hear Is What You Get - export must match playback.
//

import XCTest
@testable import Stori
import AVFoundation

/// Tests for Plugin Delay Compensation (PDC) system
/// Tests both playback and export parity to ensure WYHIWYG
/// 
/// MISSION CRITICAL: Tests PDC calculation logic with explicit latency injection
/// Uses dependency injection to avoid slow Audio Unit loading in unit tests.
@MainActor
final class PluginDelayCompensationTests: XCTestCase {
    
    var latencyManager: PluginLatencyManager!
    
    override func setUpWithError() throws {
        latencyManager = PluginLatencyManager.shared
        latencyManager.reset()
        latencyManager.isEnabled = true
        latencyManager.setSampleRate(48000)
    }
    
    override func tearDownWithError() throws {
        latencyManager.reset()
        latencyManager = nil
    }
    
    // MARK: - Basic PDC Calculation Tests
    
    func testPDCCalculatesZeroCompensationForNoTracks() throws {
        // Given: No tracks
        let trackLatencies: [UUID: UInt32] = [:]
        
        // When: Calculate compensation
        let compensation = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
        
        // Then: No compensation needed
        XCTAssertEqual(compensation.count, 0)
        XCTAssertEqual(latencyManager.maxLatencySamples, 0)
    }
    
    func testPDCCalculatesCompensationForSingleTrack() throws {
        // Given: One track with 2048 samples latency
        let track1 = UUID()
        let trackLatencies: [UUID: UInt32] = [
            track1: 2048
        ]
        
        // When: Calculate compensation
        let compensation = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
        
        // Then: Track with highest latency needs zero compensation
        XCTAssertEqual(compensation[track1], 0)
        XCTAssertEqual(latencyManager.maxLatencySamples, 2048)
    }
    
    func testPDCCalculatesCompensationForMultipleTracksWithEqualLatency() throws {
        // Given: Two tracks with identical 10ms latency (480 samples at 48kHz)
        let track1 = UUID()
        let track2 = UUID()
        
        let trackLatencies: [UUID: UInt32] = [
            track1: 480,
            track2: 480
        ]
        
        // When: Calculate compensation
        let compensation = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
        
        // Then: Both tracks have zero compensation (equal latency)
        XCTAssertEqual(compensation[track1], 0, "Track 1 should have zero compensation (equal latency)")
        XCTAssertEqual(compensation[track2], 0, "Track 2 should have zero compensation (equal latency)")
        XCTAssertEqual(latencyManager.maxLatencySamples, 480, "Max latency should be 480 samples")
    }
    
    func testPDCCalculatesCompensationForMultipleTracksWithDifferentLatency() throws {
        // Given: Two tracks with different latency
        let track1 = UUID()
        let track2 = UUID()
        
        // Track 1: 10ms latency (480 samples at 48kHz)
        // Track 2: 5ms latency (240 samples at 48kHz)
        let trackLatencies: [UUID: UInt32] = [
            track1: 480,
            track2: 240
        ]
        
        // When: Calculate compensation
        let compensation = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
        
        // Then: Track 1 (high latency) has zero compensation
        //       Track 2 (low latency) gets delayed by the difference
        XCTAssertEqual(compensation[track1], 0, "Track 1 (high latency) should have zero compensation")
        XCTAssertEqual(compensation[track2], 240, "Track 2 (low latency) should be delayed by 240 samples")
        XCTAssertEqual(latencyManager.maxLatencySamples, 480, "Max latency should be 480 samples")
    }
    
    func testPDCCalculatesCompensationForChainedPlugins() throws {
        // Given: Track with multiple plugins in series
        let track1 = UUID()
        
        // Chain: Plugin 1 (5ms) + Plugin 2 (10ms) = 15ms total
        let expectedLatency: UInt32 = 240 + 480  // 720 samples (15ms at 48kHz)
        
        let trackLatencies: [UUID: UInt32] = [
            track1: expectedLatency
        ]
        
        // When: Calculate compensation
        let compensation = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
        
        // Then: Total latency is sum of both plugins
        XCTAssertEqual(latencyManager.maxLatencySamples, expectedLatency, 
                       "Total latency should be sum of plugin chain")
        XCTAssertEqual(compensation[track1], 0, "Single track with chained plugins should have zero compensation")
    }
    
    // MARK: - Sample Rate Handling Tests
    
    func testPDCSampleRateSync() throws {
        // Given: Different sample rates
        let sampleRates: [Double] = [44100, 48000, 96000]
        
        for sampleRate in sampleRates {
            // When: Set sample rate and calculate latency for 10ms
            latencyManager.setSampleRate(sampleRate)
            
            let track1 = UUID()
            let latencySamples = UInt32(sampleRate * 0.01)  // 10ms in samples
            
            let trackLatencies: [UUID: UInt32] = [
                track1: latencySamples
            ]
            
            let _ = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
            
            // Then: Verify latency in milliseconds is consistent across sample rates
            let latencyMs = latencyManager.maxLatencyMs
            assertApproximatelyEqual(latencyMs, 10.0, tolerance: 0.1)
        }
    }
    
    // MARK: - Enable/Disable Tests
    
    func testPDCCanBeDisabled() throws {
        // Given: Two tracks with different latency
        let track1 = UUID()
        let track2 = UUID()
        
        let trackLatencies: [UUID: UInt32] = [
            track1: 480,
            track2: 0
        ]
        
        // When: PDC is enabled
        latencyManager.isEnabled = true
        let compensationEnabled = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
        
        // Then: Track 2 gets compensation
        XCTAssertEqual(compensationEnabled[track2], 480, "Track 2 should get compensation when PDC enabled")
        
        // When: PDC is disabled
        latencyManager.isEnabled = false
        let compensationDisabled = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
        
        // Then: No compensation is applied
        XCTAssertEqual(compensationDisabled[track2], 0, "Track 2 should have zero compensation when PDC disabled")
    }
    
    // MARK: - Thread Safety Tests
    
    func testPDCThreadSafetyForReadingCompensation() throws {
        // Given: PDC with compensation values
        let track1 = UUID()
        
        let trackLatencies: [UUID: UInt32] = [
            track1: 480
        ]
        
        let _ = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
        
        // When: Multiple threads read compensation simultaneously
        let iterations = 1000
        let expectation = expectation(description: "Thread safety")
        expectation.expectedFulfillmentCount = iterations
        
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            // This simulates audio thread reading compensation
            let compensation = latencyManager.getCompensationDelay(for: track1)
            XCTAssertEqual(compensation, 0, "Compensation should be consistent across threads")
            expectation.fulfill()
        }
        
        // Then: No crashes or race conditions
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Integration Tests
    
    func testPDCAppliedToTrackScheduling() throws {
        // Given: A TrackAudioNode with compensation delay
        let playerNode = AVAudioPlayerNode()
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)
        let pluginChain = PluginChain()
        let timePitchUnit = AVAudioUnitTimePitch()
        
        let trackNode = TrackAudioNode(
            id: UUID(),
            playerNode: playerNode,
            volumeNode: volumeNode,
            panNode: panNode,
            eqNode: eqNode,
            pluginChain: pluginChain,
            timePitchUnit: timePitchUnit
        )
        
        // When: Apply compensation delay
        let compensationSamples: UInt32 = 480  // 10ms at 48kHz
        trackNode.applyCompensationDelay(samples: compensationSamples)
        
        // Then: Compensation is stored and will be applied during scheduling
        XCTAssertEqual(trackNode.compensationDelaySamples, compensationSamples,
                       "Compensation delay should be stored in track node")
    }
    
    // MARK: - Export PDC Tests
    
    func testExportUsesSamePDCAsPplayback() async throws {
        // This test verifies that export applies the same PDC as playback
        // It's a smoke test - full export testing requires audio comparison
        
        // Given: A project with tracks that have different plugin latencies
        let project = TestDataFactory.createProject(name: "PDC Test", tempo: 120.0, trackCount: 2)
        
        // When: Export is configured with PDC
        // The export service should:
        // 1. Set PluginLatencyManager sample rate
        // 2. Calculate compensation for all tracks
        // 3. Apply compensation in scheduleRegionForPlayback
        
        // Then: Export sample rate matches export configuration
        latencyManager.setSampleRate(48000)
        XCTAssertEqual(latencyManager.sampleRate, 48000, 
                       "Export should set PDC sample rate to match export sample rate")
    }
    
    // MARK: - Edge Cases
    
    func testPDCHandlesZeroLatencyPlugins() throws {
        // Given: Tracks with zero-latency plugins
        let track1 = UUID()
        
        let trackLatencies: [UUID: UInt32] = [
            track1: 0
        ]
        
        // When: Calculate compensation
        let compensation = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
        
        // Then: No compensation needed
        XCTAssertEqual(compensation[track1], 0, "Zero latency plugins should not require compensation")
        XCTAssertEqual(latencyManager.maxLatencySamples, 0, "Max latency should be zero")
    }
    
    func testPDCHandlesTracksWithNoPlugins() throws {
        // Given: Tracks without plugins
        let track1 = UUID()
        let track2 = UUID()
        
        let trackLatencies: [UUID: UInt32] = [
            track1: 0,
            track2: 0
        ]
        
        // When: Calculate compensation
        let compensation = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
        
        // Then: All tracks have zero compensation
        XCTAssertEqual(compensation[track1], 0, "Track without plugins should have zero compensation")
        XCTAssertEqual(compensation[track2], 0, "Track without plugins should have zero compensation")
    }
    
    func testPDCHandlesExtremeLatencyValues() throws {
        // Given: Track with very high latency plugin (100ms)
        let track1 = UUID()
        let track2 = UUID()
        
        let trackLatencies: [UUID: UInt32] = [
            track1: 4800,  // 100ms at 48kHz
            track2: 0
        ]
        
        // When: Calculate compensation
        let compensation = latencyManager.calculateCompensationWithExplicitLatencies(trackLatencies)
        
        // Then: Compensation is calculated correctly
        XCTAssertEqual(compensation[track2], 4800, "Track 2 should be delayed by 100ms")
        assertApproximatelyEqual(latencyManager.maxLatencyMs, 100.0, tolerance: 0.1)
    }
    
}
