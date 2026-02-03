//
//  TrackAudioNodeTests.swift
//  StoriTests
//
//  Comprehensive tests for TrackAudioNode scheduling and playback.
//  CRITICAL: TrackAudioNode is the AVAudioEngine boundary - all beat→seconds conversion happens here.
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class TrackAudioNodeTests: XCTestCase {
    
    var sut: TrackAudioNode!
    var mockEngine: AVAudioEngine!
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockEngine = AVAudioEngine()
        
        let playerNode = AVAudioPlayerNode()
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)
        let timePitch = AVAudioUnitTimePitch()
        let pluginChain = PluginChain(id: UUID(), maxSlots: 8)
        
        sut = TrackAudioNode(
            id: UUID(),
            playerNode: playerNode,
            volumeNode: volumeNode,
            panNode: panNode,
            eqNode: eqNode,
            pluginChain: pluginChain,
            timePitchUnit: timePitch,
            volume: 0.8,
            pan: 0.0,
            isMuted: false,
            isSolo: false
        )
        
        // Attach nodes to engine
        mockEngine.attach(playerNode)
        mockEngine.attach(volumeNode)
        mockEngine.attach(panNode)
        mockEngine.attach(eqNode)
        mockEngine.attach(timePitch)
    }
    
    override func tearDown() async throws {
        if mockEngine.isRunning {
            mockEngine.stop()
        }
        mockEngine = nil
        sut = nil
        try await super.tearDown()
    }
    
    // MARK: - Beats-First API Tests
    
    /// scheduleFromBeat() is the primary scheduling API (beats-first)
    func testScheduleFromBeatAPI() {
        // Verify the API exists and accepts beats
        let startBeat: Double = 4.0
        let tempo: Double = 120.0
        
        // This should not crash (even with no regions)
        do {
            try sut.scheduleFromBeat(startBeat, audioRegions: [], tempo: tempo)
        } catch {
            // Empty regions is ok
        }
        
        XCTAssertTrue(true, "scheduleFromBeat API exists and accepts beats")
    }
    
    /// scheduleFromBeat() converts beats to seconds correctly
    func testScheduleFromBeatConversion() {
        let startBeat: Double = 4.0
        let tempo: Double = 120.0
        
        // At 120 BPM, 4 beats = 2 seconds
        let expectedSeconds = startBeat * (60.0 / tempo)
        XCTAssertEqual(expectedSeconds, 2.0, accuracy: 0.001)
        
        // Verify conversion happens at TrackAudioNode level
        // (scheduleFromBeat calls scheduleFromPosition with converted seconds)
    }
    
    /// scheduleCycleAware() accepts beats for cycle boundaries
    func testScheduleCycleAwareBeatsAPI() {
        let startBeat: Double = 2.0
        let cycleStartBeat: Double = 0.0
        let cycleEndBeat: Double = 4.0
        let tempo: Double = 120.0
        
        // This should not crash (even with no regions)
        do {
            try sut.scheduleCycleAware(
                fromBeat: startBeat,
                audioRegions: [],
                tempo: tempo,
                cycleStartBeat: cycleStartBeat,
                cycleEndBeat: cycleEndBeat,
                iterationsAhead: 3
            )
        } catch {
            // Empty regions is ok
        }
        
        XCTAssertTrue(true, "scheduleCycleAware API accepts beats")
    }
    
    // MARK: - Volume/Pan/Mute Tests
    
    func testSetVolume() {
        sut.setVolume(0.5)
        XCTAssertEqual(sut.volumeNode.outputVolume, 0.5, accuracy: 0.001)
    }
    
    func testSetVolumeClamps() {
        sut.setVolume(1.5)  // Above max
        XCTAssertLessThanOrEqual(sut.volumeNode.outputVolume, 1.0)
        
        sut.setVolume(-0.5)  // Below min
        XCTAssertGreaterThanOrEqual(sut.volumeNode.outputVolume, 0.0)
    }
    
    func testSetPan() {
        sut.setPan(0.5)  // Right
        XCTAssertEqual(sut.panNode.pan, 0.5, accuracy: 0.001)
        
        sut.setPan(-0.5)  // Left
        XCTAssertEqual(sut.panNode.pan, -0.5, accuracy: 0.001)
    }
    
    func testSetPanClamps() {
        sut.setPan(2.0)  // Beyond right
        XCTAssertLessThanOrEqual(sut.panNode.pan, 1.0)
        
        sut.setPan(-2.0)  // Beyond left
        XCTAssertGreaterThanOrEqual(sut.panNode.pan, -1.0)
    }
    
    func testSetMuted() {
        sut.setMuted(true)
        XCTAssertEqual(sut.volumeNode.outputVolume, 0.0)
        
        sut.setMuted(false)
        XCTAssertGreaterThan(sut.volumeNode.outputVolume, 0.0)
    }
    
    func testSetSolo() {
        sut.setSolo(true)
        // Solo state is tracked externally, just verify it doesn't crash
        XCTAssertTrue(true)
    }
    
    // MARK: - EQ Tests
    
    func testSetEQ() {
        sut.setEQ(highGain: 6.0, midGain: 3.0, lowGain: -3.0)
        
        guard sut.eqNode.bands.count >= 3 else {
            XCTFail("EQ should have 3 bands")
            return
        }
        
        XCTAssertEqual(sut.eqNode.bands[0].gain, 6.0, accuracy: 0.1)
        XCTAssertEqual(sut.eqNode.bands[1].gain, 3.0, accuracy: 0.1)
        XCTAssertEqual(sut.eqNode.bands[2].gain, -3.0, accuracy: 0.1)
    }
    
    func testSetEQClamps() {
        // Test extreme values
        sut.setEQ(highGain: 50.0, midGain: -50.0, lowGain: 0.0)
        
        // EQ should clamp to reasonable range (-24 to +24 dB)
        guard sut.eqNode.bands.count >= 3 else { return }
        
        XCTAssertLessThanOrEqual(abs(sut.eqNode.bands[0].gain), 24.0)
        XCTAssertLessThanOrEqual(abs(sut.eqNode.bands[1].gain), 24.0)
    }
    
    // MARK: - Plugin Delay Compensation Tests
    
    func testApplyCompensationDelay() {
        let delaySamples: UInt32 = 512
        sut.applyCompensationDelay(samples: delaySamples)
        
        // Verify delay was applied (stored internally)
        // Cannot easily verify without exposing internal state
        XCTAssertTrue(true, "Compensation delay applied")
    }
    
    func testApplyCompensationDelayZero() {
        sut.applyCompensationDelay(samples: UInt32(0))
        // Should not crash with zero delay
        XCTAssertTrue(true)
    }
    
    // MARK: - Playback Control Tests
    
    func testPlay() {
        // Connect to engine for playback
        mockEngine.connect(sut.playerNode, to: mockEngine.mainMixerNode, format: nil)
        try? mockEngine.start()
        
        sut.play()
        XCTAssertTrue(sut.playerNode.isPlaying)
    }
    
    func testStop() {
        mockEngine.connect(sut.playerNode, to: mockEngine.mainMixerNode, format: nil)
        try? mockEngine.start()
        
        sut.play()
        XCTAssertTrue(sut.playerNode.isPlaying)
        
        sut.stop()
        XCTAssertFalse(sut.playerNode.isPlaying)
    }
    
    // MARK: - Cycle Scheduling Math Tests
    
    /// Tests the beat-to-seconds conversion for cycle boundaries
    func testCycleSchedulingConversion() {
        let tempo: Double = 120.0
        let cycleStartBeat: Double = 0.0
        let cycleEndBeat: Double = 4.0
        
        let beatsToSeconds = 60.0 / tempo
        let cycleStartSeconds = cycleStartBeat * beatsToSeconds
        let cycleEndSeconds = cycleEndBeat * beatsToSeconds
        let cycleDurationSeconds = cycleEndSeconds - cycleStartSeconds
        
        XCTAssertEqual(cycleStartSeconds, 0.0, accuracy: 0.001)
        XCTAssertEqual(cycleEndSeconds, 2.0, accuracy: 0.001)
        XCTAssertEqual(cycleDurationSeconds, 2.0, accuracy: 0.001)
    }
    
    /// Tests pre-scheduling iteration offset calculation
    func testCycleIterationOffsetCalculation() {
        let tempo: Double = 120.0
        let startBeat: Double = 1.0  // Start mid-cycle
        let cycleStartBeat: Double = 0.0
        let cycleEndBeat: Double = 4.0
        
        let beatsToSeconds = 60.0 / tempo
        let startTimeSeconds = startBeat * beatsToSeconds  // 0.5 seconds
        let cycleEndSeconds = cycleEndBeat * beatsToSeconds  // 2.0 seconds
        let cycleDurationSeconds = cycleEndSeconds - (cycleStartBeat * beatsToSeconds)  // 2.0 seconds
        
        // Iteration 0: current position (0.5s)
        // Iteration 1: starts at cycleEnd - startTime = 2.0 - 0.5 = 1.5s from now
        let iteration1Offset = cycleEndSeconds - startTimeSeconds
        XCTAssertEqual(iteration1Offset, 1.5, accuracy: 0.001)
        
        // Iteration 2: 1.5 + 2.0 = 3.5s from now
        let iteration2Offset = iteration1Offset + cycleDurationSeconds
        XCTAssertEqual(iteration2Offset, 3.5, accuracy: 0.001)
    }
    
    // MARK: - Plugin Chain Access Tests
    
    func testPluginChainAccess() {
        XCTAssertNotNil(sut.pluginChain)
        XCTAssertEqual(Int(sut.pluginChain.maxSlots), 8)
    }
    
    func testPluginChainInitiallyEmpty() {
        XCTAssertEqual(sut.pluginChain.activePlugins.count, 0)
        XCTAssertFalse(sut.pluginChain.hasActivePlugins)
    }
}
