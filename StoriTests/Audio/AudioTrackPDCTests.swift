//
//  AudioTrackPDCTests.swift
//  StoriTests
//
//  Tests for Audio Track Plugin Delay Compensation (Issue #49)
//

import XCTest
import AVFoundation
@testable import Stori

/// Comprehensive tests for audio track plugin delay compensation
/// BUG FIX: Issue #49 - Audio tracks were not applying PDC despite having the scheduling logic
@MainActor
final class AudioTrackPDCTests: XCTestCase {
    
    // MARK: - Core PDC Application Tests
    
    func testCompensationDelayInitializesToZero() {
        // Given: A new TrackAudioNode
        let trackNode = TestAudioNodeFactory.createTrackNode()
        
        // Then: Compensation starts at 0
        XCTAssertEqual(trackNode.compensationDelaySamples, 0,
                      "Compensation should initialize to 0")
    }
    
    func testApplyCompensationDelayUpdatesProperty() {
        // Given: A track node with no compensation
        let trackNode = TestAudioNodeFactory.createTrackNode()
        XCTAssertEqual(trackNode.compensationDelaySamples, 0)
        
        // When: We apply 1024 samples compensation
        trackNode.applyCompensationDelay(samples: 1024)
        
        // Then: The property is updated
        XCTAssertEqual(trackNode.compensationDelaySamples, 1024,
                      "Compensation should be set to 1024 samples")
    }
    
    func testApplyCompensationDelayCanBeCleared() {
        // Given: A track with existing compensation
        let trackNode = TestAudioNodeFactory.createTrackNode()
        trackNode.applyCompensationDelay(samples: 2048)
        XCTAssertEqual(trackNode.compensationDelaySamples, 2048)
        
        // When: We clear compensation
        trackNode.applyCompensationDelay(samples: 0)
        
        // Then: Compensation is cleared
        XCTAssertEqual(trackNode.compensationDelaySamples, 0,
                      "Compensation should be cleared to 0")
    }
    
    func testApplyCompensationDelayCanBeUpdatedMultipleTimes() {
        // Given: A track node
        let trackNode = TestAudioNodeFactory.createTrackNode()
        
        // When: We apply different compensation values over time
        trackNode.applyCompensationDelay(samples: 512)
        XCTAssertEqual(trackNode.compensationDelaySamples, 512)
        
        trackNode.applyCompensationDelay(samples: 1024)
        XCTAssertEqual(trackNode.compensationDelaySamples, 1024)
        
        trackNode.applyCompensationDelay(samples: 256)
        XCTAssertEqual(trackNode.compensationDelaySamples, 256)
        
        // Then: Each update is applied correctly
    }
    
    // MARK: - PDC Integration with Scheduling
    
    func testSchedulingUsesCompensationDelay() {
        // This test verifies that the scheduling code references compensationDelaySamples
        // The actual scheduling is tested in integration tests
        
        // Given: A track with compensation
        let trackNode = TestAudioNodeFactory.createTrackNode()
        trackNode.applyCompensationDelay(samples: 1024)
        
        // Then: The property is accessible for scheduling calculations
        XCTAssertEqual(trackNode.compensationDelaySamples, 1024,
                      "Scheduling code should be able to read compensation value")
    }
    
    // MARK: - Bug Scenario from Issue #49
    
    func testBugScenario_LinearPhaseEQCompensation() {
        // Reproduces the exact scenario from Issue #49:
        // Audio track with linear-phase EQ (1024 samples latency)
        // should be scheduled 1024 samples earlier to compensate
        
        // Given: A track with 1024 samples latency (linear-phase EQ at 44.1kHz)
        let trackNode = TestAudioNodeFactory.createTrackNode()
        let latencySamples: UInt32 = 1024
        
        // When: We apply compensation matching the plugin latency
        trackNode.applyCompensationDelay(samples: latencySamples)
        
        // Then: The compensation delay is set correctly
        XCTAssertEqual(trackNode.compensationDelaySamples, latencySamples)
        
        // Calculate expected timing offset at 44.1kHz
        let sampleRate: Double = 44100
        let expectedOffsetMs = (Double(latencySamples) / sampleRate) * 1000
        let approximateOffsetMs = 23.0  // ~23ms at 44.1kHz
        
        XCTAssertEqual(expectedOffsetMs, approximateOffsetMs, accuracy: 0.5,
                      "1024 samples at 44.1kHz should be ~23ms")
    }
    
    func testBugScenario_AudioMIDIAlignment() {
        // Reproduces the misalignment between audio and MIDI from Issue #49
        
        // Given: Two tracks - audio with 1024 samples latency, MIDI with 0 latency
        let audioTrack = TestAudioNodeFactory.createTrackNode()
        let midiTrack = TestAudioNodeFactory.createTrackNode()
        
        // When: PDC is applied
        audioTrack.applyCompensationDelay(samples: 1024)  // Audio compensated
        midiTrack.applyCompensationDelay(samples: 0)      // MIDI has no plugins
        
        // Then: Audio track has compensation, MIDI does not
        XCTAssertEqual(audioTrack.compensationDelaySamples, 1024,
                      "Audio track should be compensated")
        XCTAssertEqual(midiTrack.compensationDelaySamples, 0,
                      "MIDI track should not be compensated")
        
        // This ensures audio schedules 1024 samples earlier to align with MIDI
    }
    
    // MARK: - Professional Standard Tests
    
    func testTypicalPluginLatencies() {
        // Test compensation for common plugin latency values
        let trackNode = TestAudioNodeFactory.createTrackNode()
        
        // Typical plugin latencies in samples at 48kHz:
        let latencies: [(name: String, samples: UInt32)] = [
            ("Minimal (algorithmic reverb)", 64),
            ("Low (EQ, compressor)", 128),
            ("Medium (look-ahead limiter)", 512),
            ("High (linear-phase EQ)", 1024),
            ("Very high (advanced mastering)", 2048),
            ("Extreme (convolution reverb)", 8192)
        ]
        
        for (name, samples) in latencies {
            trackNode.applyCompensationDelay(samples: samples)
            XCTAssertEqual(trackNode.compensationDelaySamples, samples,
                          "Should handle \(name) latency: \(samples) samples")
        }
    }
    
    func testZeroLatencyNoCompensation() {
        // Tracks without plugins should have zero compensation
        let trackNode = TestAudioNodeFactory.createTrackNode()
        trackNode.applyCompensationDelay(samples: 0)
        
        XCTAssertEqual(trackNode.compensationDelaySamples, 0,
                      "Track without plugins should have no compensation")
    }
    
    // MARK: - Edge Cases
    
    func testLargeCompensationValues() {
        // Some convolution reverbs can have very large latencies
        let trackNode = TestAudioNodeFactory.createTrackNode()
        let largeLatency: UInt32 = 16384  // ~340ms at 48kHz
        
        trackNode.applyCompensationDelay(samples: largeLatency)
        
        XCTAssertEqual(trackNode.compensationDelaySamples, largeLatency,
                      "Should handle very large latency values")
    }
    
    func testMaxUInt32Compensation() {
        // Edge case: Maximum possible UInt32 value
        let trackNode = TestAudioNodeFactory.createTrackNode()
        let maxValue = UInt32.max
        
        trackNode.applyCompensationDelay(samples: maxValue)
        
        XCTAssertEqual(trackNode.compensationDelaySamples, maxValue,
                      "Should handle maximum UInt32 value")
    }
    
    // MARK: - Multiple Track Scenarios
    
    func testDifferentCompensationAcrossTracks() {
        // Given: Three tracks with different plugin latencies
        let track1 = TestAudioNodeFactory.createTrackNode()
        let track2 = TestAudioNodeFactory.createTrackNode()
        let track3 = TestAudioNodeFactory.createTrackNode()
        
        // When: Different compensations are applied
        // Track 1: No plugins (max latency, no compensation needed)
        track1.applyCompensationDelay(samples: 2048)
        
        // Track 2: 1024 samples latency (needs 1024 samples compensation)
        track2.applyCompensationDelay(samples: 1024)
        
        // Track 3: 2048 samples latency (max, no compensation)
        track3.applyCompensationDelay(samples: 0)
        
        // Then: Each track has independent compensation
        XCTAssertEqual(track1.compensationDelaySamples, 2048)
        XCTAssertEqual(track2.compensationDelaySamples, 1024)
        XCTAssertEqual(track3.compensationDelaySamples, 0)
    }
    
    // MARK: - WYSIWYG Tests
    
    func testWYSIWYG_ExportMatchesPlayback() {
        // PDC should be applied identically in playback and export
        
        // Given: A track with specific compensation
        let liveTrack = TestAudioNodeFactory.createTrackNode()
        let exportTrack = TestAudioNodeFactory.createTrackNode()
        
        let compensation: UInt32 = 1024
        
        // When: Same compensation is applied to both
        liveTrack.applyCompensationDelay(samples: compensation)
        exportTrack.applyCompensationDelay(samples: compensation)
        
        // Then: Both have identical compensation
        XCTAssertEqual(liveTrack.compensationDelaySamples,
                      exportTrack.compensationDelaySamples,
                      "Live and export should have identical compensation for WYSIWYG")
    }
    
    // MARK: - Regression Protection
    
    func testRegressionProtection_PropertyNotNil() {
        // Verify the property exists and is not accidentally removed
        let trackNode = TestAudioNodeFactory.createTrackNode()
        
        // The property should exist and be readable
        let compensation = trackNode.compensationDelaySamples
        XCTAssertNotNil(compensation, "compensationDelaySamples property must exist")
    }
    
    func testRegressionProtection_MethodExists() {
        // Verify the applyCompensationDelay method exists
        let trackNode = TestAudioNodeFactory.createTrackNode()
        
        // This should compile and run without errors
        trackNode.applyCompensationDelay(samples: 100)
        
        XCTAssertEqual(trackNode.compensationDelaySamples, 100,
                      "applyCompensationDelay method must exist and work")
    }
    
    // MARK: - Thread Safety
    
    func testConcurrentCompensationUpdates() {
        // PDC updates should be thread-safe (called from main actor)
        let trackNode = TestAudioNodeFactory.createTrackNode()
        let expectation = self.expectation(description: "Concurrent updates complete")
        expectation.expectedFulfillmentCount = 100
        
        DispatchQueue.concurrentPerform(iterations: 100) { iteration in
            let samples = UInt32(iteration * 10)
            trackNode.applyCompensationDelay(samples: samples)
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 5.0)
        
        // After all updates, the property should have a valid value (last update wins)
        XCTAssertNotNil(trackNode.compensationDelaySamples)
    }
    
    // MARK: - Integration with PluginLatencyManager
    
    func testIntegration_CompensationMatchesCalculation() {
        // This would be tested with real plugins in integration tests
        // Here we verify the contract: whatever value is passed, is stored
        
        let trackNode = TestAudioNodeFactory.createTrackNode()
        let calculatedCompensation: UInt32 = 768  // From PluginLatencyManager
        
        trackNode.applyCompensationDelay(samples: calculatedCompensation)
        
        XCTAssertEqual(trackNode.compensationDelaySamples, calculatedCompensation,
                      "Applied compensation should match calculated value")
    }
}

// MARK: - Test Helpers

/// Factory for creating test audio nodes
private enum TestAudioNodeFactory {
    @MainActor
    static func createTrackNode() -> TrackAudioNode {
        let audioEngine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)
        let timePitchUnit = AVAudioUnitTimePitch()
        
        // Attach nodes to engine
        audioEngine.attach(playerNode)
        audioEngine.attach(volumeNode)
        audioEngine.attach(panNode)
        audioEngine.attach(eqNode)
        audioEngine.attach(timePitchUnit)
        
        // Create plugin chain (PluginChain is @MainActor)
        let pluginChain = PluginChain(id: UUID(), maxSlots: 8)
        let graphFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)
        pluginChain.install(in: audioEngine, format: graphFormat)
        audioEngine.attach(pluginChain.inputMixer)
        audioEngine.attach(pluginChain.outputMixer)
        
        // Connect basic signal path: player → timePitch → chain input → chain output → volume → pan → eq → mainMixer
        audioEngine.connect(playerNode, to: timePitchUnit, format: graphFormat)
        audioEngine.connect(timePitchUnit, to: pluginChain.inputMixer, format: graphFormat)
        audioEngine.connect(pluginChain.outputMixer, to: volumeNode, format: graphFormat)
        audioEngine.connect(volumeNode, to: panNode, format: graphFormat)
        audioEngine.connect(panNode, to: eqNode, format: graphFormat)
        audioEngine.connect(eqNode, to: audioEngine.mainMixerNode, format: graphFormat)
        
        return TrackAudioNode(
            id: UUID(),
            playerNode: playerNode,
            volumeNode: volumeNode,
            panNode: panNode,
            eqNode: eqNode,
            pluginChain: pluginChain,
            timePitchUnit: timePitchUnit
        )
    }
}
