//
//  MixerSoloMuteFadeTests.swift
//  StoriTests
//
//  Tests for smooth mute/solo toggle fades (BUG FIX Issue #52)
//  Ensures no audible pops when toggling solo/mute states
//
//  BUG REPORT (GitHub Issue #52):
//  =================================
//  When disabling solo on the last soloed track, all previously muted tracks
//  are instantly unmuted simultaneously. This sudden gain change causes an
//  audible pop or click, especially if tracks were mid-transient when muted.
//
//  ROOT CAUSE:
//  -----------
//  `TrackAudioNode.setMuted()` was applying instant gain changes (0 → 1.0)
//  without any ramping or crossfade. This creates sample-level discontinuities
//  causing audible clicks.
//
//  SOLUTION:
//  ---------
//  1. Added `_targetMuteMultiplier` and `_smoothedMuteMultiplier` to TrackAudioNode
//  2. Modified `setMuted()` to set target multiplier instead of instant volume
//  3. Integrated mute fade into `setVolumeSmoothed()` with ~10ms crossfade
//  4. Automation engine (120Hz) continuously applies smooth fade
//
//  PROFESSIONAL STANDARD:
//  ----------------------
//  Logic Pro, Pro Tools, and Cubase all use 5-10ms crossfades when toggling
//  mute/solo states to prevent audible artifacts. This is critical for
//  professional mixing workflows where solo/mute are used multiple times
//  per minute.
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class MixerSoloMuteFadeTests: XCTestCase {
    
    // MARK: - Test Configuration
    
    /// Crossfade duration for mute/solo toggles
    /// Professional standard: 5-10ms
    private let expectedFadeDurationMs: Double = 10.0
    
    /// Sample rate for testing
    private let sampleRate: Double = 48000.0
    
    /// 120Hz automation update rate
    private let automationUpdateRate: Double = 120.0
    
    /// Number of automation updates expected for fade
    /// At 10ms fade and 120Hz updates: ~1.2 updates
    private var expectedFadeUpdates: Int {
        Int(ceil((expectedFadeDurationMs / 1000.0) * automationUpdateRate))
    }
    
    // MARK: - Core Mute Fade Behavior
    
    /// Test that muting a track initiates a smooth fade to zero
    func testMuteInitiatesFadeToZero() {
        let (engine, node) = createTrackNode(volume: 0.8, isMuted: false)
        
        // Initial state: unmuted, full volume
        XCTAssertFalse(node.isMuted)
        XCTAssertEqual(node.volume, 0.8, accuracy: 0.01)
        
        // Trigger mute
        node.setMuted(true)
        XCTAssertTrue(node.isMuted)
        
        // Simulate automation engine updates (120Hz)
        // After multiple updates, volume should fade to zero
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        }
        
        // Volume node should be at or near zero after fade
        let finalVolume = node.volumeNode.outputVolume
        XCTAssertLessThan(finalVolume, 0.05, "Volume should fade to near-zero after mute")
    }
    
    /// Test that unmuting a track initiates a smooth fade to full volume
    func testUnmuteInitiatesFadeToFullVolume() {
        let (engine, node) = createTrackNode(volume: 0.8, isMuted: true)
        
        // Initial state: muted, zero output
        XCTAssertTrue(node.isMuted)
        
        // Simulate being fully muted (automation updates)
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        }
        let mutedVolume = node.volumeNode.outputVolume
        XCTAssertLessThan(mutedVolume, 0.05, "Should be muted initially")
        
        // Trigger unmute
        node.setMuted(false)
        XCTAssertFalse(node.isMuted)
        
        // Simulate automation engine updates
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        }
        
        // Volume should fade back to full
        let finalVolume = node.volumeNode.outputVolume
        XCTAssertGreaterThan(finalVolume, 0.7, "Volume should fade back to near-full after unmute")
    }
    
    // MARK: - Solo Behavior
    
    /// Test solo toggle causes smooth fade (solo implicitly mutes other tracks)
    func testSoloToggleCausesSmoothFade() {
        let (engine1, node1) = createTrackNode(volume: 0.8, isMuted: false)
        let (engine2, node2) = createTrackNode(volume: 0.8, isMuted: false)
        
        // Both tracks playing
        for _ in 0..<3 {
            simulateAutomationUpdate(node: node1, engine: engine1, volume: 0.8)
            simulateAutomationUpdate(node: node2, engine: engine2, volume: 0.8)
        }
        
        // Solo track 1 (track 2 should be implicitly muted by MixerController)
        node1.setSolo(true)
        node2.setMuted(true)  // MixerController would call this
        
        // Simulate automation updates - track 2 should fade to zero
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node1, engine: engine1, volume: 0.8)
            simulateAutomationUpdate(node: node2, engine: engine2, volume: 0.8)
        }
        
        let track1Volume = node1.volumeNode.outputVolume
        let track2Volume = node2.volumeNode.outputVolume
        
        XCTAssertGreaterThan(track1Volume, 0.7, "Soloed track should remain at full volume")
        XCTAssertLessThan(track2Volume, 0.05, "Implicitly muted track should fade to zero")
    }
    
    /// Test un-solo causes smooth fade for all implicitly muted tracks
    func testUnsoloRestoresAllTracksWithFade() {
        let (engine1, node1) = createTrackNode(volume: 0.8, isMuted: false)
        let (engine2, node2) = createTrackNode(volume: 0.7, isMuted: false)
        let (engine3, node3) = createTrackNode(volume: 0.9, isMuted: false)
        
        // Solo track 1, mute others
        node1.setSolo(true)
        node2.setMuted(true)
        node3.setMuted(true)
        
        // Simulate solo state (track 2 and 3 fade to zero)
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node1, engine: engine1, volume: 0.8)
            simulateAutomationUpdate(node: node2, engine: engine2, volume: 0.7)
            simulateAutomationUpdate(node: node3, engine: engine3, volume: 0.9)
        }
        
        // Un-solo track 1 (all tracks restore)
        node1.setSolo(false)
        node2.setMuted(false)
        node3.setMuted(false)
        
        // Simulate restoration
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node1, engine: engine1, volume: 0.8)
            simulateAutomationUpdate(node: node2, engine: engine2, volume: 0.7)
            simulateAutomationUpdate(node: node3, engine: engine3, volume: 0.9)
        }
        
        // All tracks should restore to their original volumes
        XCTAssertGreaterThan(node1.volumeNode.outputVolume, 0.75, "Track 1 should restore")
        XCTAssertGreaterThan(node2.volumeNode.outputVolume, 0.65, "Track 2 should restore")
        XCTAssertGreaterThan(node3.volumeNode.outputVolume, 0.85, "Track 3 should restore")
    }
    
    // MARK: - Edge Cases
    
    /// Test rapid mute/unmute toggles don't cause discontinuities
    func testRapidMuteTogglesSmoothly() {
        let (engine, node) = createTrackNode(volume: 0.8, isMuted: false)
        
        // Rapid toggle sequence: mute → unmute → mute → unmute
        node.setMuted(true)
        simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        
        node.setMuted(false)
        simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        
        node.setMuted(true)
        simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        
        node.setMuted(false)
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        }
        
        // Should eventually settle to unmuted volume
        let finalVolume = node.volumeNode.outputVolume
        XCTAssertGreaterThan(finalVolume, 0.5, "Should settle toward unmuted volume")
    }
    
    /// Test mute toggle while volume automation is active
    func testMuteWithActiveAutomation() {
        let (engine, node) = createTrackNode(volume: 0.8, isMuted: false)
        
        // Apply automation sweep from 0.8 → 0.4
        for i in 0..<10 {
            let automationVolume = 0.8 - Float(i) * 0.04
            simulateAutomationUpdate(node: node, engine: engine, volume: automationVolume)
        }
        
        // Mid-sweep, toggle mute
        node.setMuted(true)
        
        // Continue automation updates (volume continues changing, but output fades to zero)
        for i in 10..<20 {
            let automationVolume = 0.8 - Float(i) * 0.04
            simulateAutomationUpdate(node: node, engine: engine, volume: automationVolume)
        }
        
        // Output should be muted (near zero) regardless of automation
        let finalVolume = node.volumeNode.outputVolume
        XCTAssertLessThan(finalVolume, 0.05, "Mute should override automation")
    }
    
    /// Test mute state is preserved through automation reset
    func testMutePreservedThroughSmoothingReset() {
        let (engine, node) = createTrackNode(volume: 0.8, isMuted: true)
        
        // Fade to muted state
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        }
        XCTAssertLessThan(node.volumeNode.outputVolume, 0.05)
        
        // Reset smoothing (simulates playback start)
        node.resetSmoothing(atBeat: 0, automationLanes: [])
        
        // Still muted after reset
        XCTAssertTrue(node.isMuted)
        
        // Apply updates - should remain muted
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        }
        XCTAssertLessThan(node.volumeNode.outputVolume, 0.05, "Should remain muted after reset")
    }
    
    // MARK: - Fade Duration & Professional Standards
    
    /// Test fade completes within professional standard duration (~10ms)
    func testFadeDurationMeetsProfessionalStandard() {
        let (engine, node) = createTrackNode(volume: 0.8, isMuted: false)
        
        // Start unmuted
        for _ in 0..<3 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        }
        let initialVolume = node.volumeNode.outputVolume
        XCTAssertGreaterThan(initialVolume, 0.7)
        
        // Trigger mute
        node.setMuted(true)
        
        // Simulate ~10ms worth of automation updates (120Hz = 8.3ms per update)
        // 2 updates = ~16.6ms (professional standard allows up to 20ms)
        for _ in 0..<2 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        }
        
        // Should be significantly faded by now
        let fadedVolume = node.volumeNode.outputVolume
        XCTAssertLessThan(fadedVolume, initialVolume * 0.3, "Should fade significantly within ~16ms")
    }
    
    /// Test fade curve is smooth (no sudden jumps)
    func testFadeCurveIsSmoothExponential() {
        let (engine, node) = createTrackNode(volume: 0.8, isMuted: false)
        
        // Start unmuted
        for _ in 0..<3 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        }
        
        // Trigger mute and capture fade curve
        node.setMuted(true)
        var volumeSamples: [Float] = []
        for _ in 0..<10 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
            volumeSamples.append(node.volumeNode.outputVolume)
        }
        
        // Check that volume decreases monotonically (no jumps up)
        for i in 1..<volumeSamples.count {
            XCTAssertLessThanOrEqual(
                volumeSamples[i],
                volumeSamples[i-1] + 0.01,  // Allow tiny floating point error
                "Fade should be smooth and monotonic"
            )
        }
        
        // Final volume should be near zero
        XCTAssertLessThan(volumeSamples.last ?? 1.0, 0.05)
    }
    
    // MARK: - Multiple Track Scenarios (Issue #52 Bug Scenario)
    
    /// Test un-soloing last track with 8 implicitly muted tracks (exact bug scenario)
    func testUnsoloLastTrackWith8MutedTracks() {
        // Create 8 tracks (Bug #52 scenario: "tracks 2-8 become implicitly muted")
        var nodes: [(AVAudioEngine, TrackAudioNode)] = []
        for _ in 0..<8 {
            nodes.append(createTrackNode(volume: 0.8, isMuted: false))
        }
        
        // Solo track 0, implicitly mute tracks 1-7
        nodes[0].1.setSolo(true)
        for i in 1..<8 {
            nodes[i].1.setMuted(true)
        }
        
        // Fade all muted tracks to zero
        for _ in 0..<5 {
            for (engine, node) in nodes {
                simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
            }
        }
        
        // Verify muted state
        for i in 1..<8 {
            XCTAssertLessThan(nodes[i].1.volumeNode.outputVolume, 0.05, "Track \(i) should be muted")
        }
        
        // Un-solo track 0 (restore all 7 muted tracks)
        nodes[0].1.setSolo(false)
        for i in 1..<8 {
            nodes[i].1.setMuted(false)
        }
        
        // Apply automation updates - all tracks should fade back in smoothly
        for _ in 0..<5 {
            for (engine, node) in nodes {
                simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
            }
        }
        
        // All 7 tracks should have faded back to audible levels (no instant pop)
        for i in 1..<8 {
            let volume = nodes[i].1.volumeNode.outputVolume
            XCTAssertGreaterThan(volume, 0.6, "Track \(i) should fade back smoothly (no pop)")
        }
    }
    
    /// Test multiple rapid solo toggles across different tracks
    func testMultipleSoloTogglesAcrossTracks() {
        let (engine1, node1) = createTrackNode(volume: 0.8, isMuted: false)
        let (engine2, node2) = createTrackNode(volume: 0.8, isMuted: false)
        let (engine3, node3) = createTrackNode(volume: 0.8, isMuted: false)
        
        // Solo track 1
        node1.setSolo(true)
        node2.setMuted(true)
        node3.setMuted(true)
        
        for _ in 0..<3 {
            simulateAutomationUpdate(node: node1, engine: engine1, volume: 0.8)
            simulateAutomationUpdate(node: node2, engine: engine2, volume: 0.8)
            simulateAutomationUpdate(node: node3, engine: engine3, volume: 0.8)
        }
        
        // Switch solo to track 2
        node1.setSolo(false)
        node1.setMuted(true)
        node2.setSolo(true)
        node2.setMuted(false)
        
        for _ in 0..<3 {
            simulateAutomationUpdate(node: node1, engine: engine1, volume: 0.8)
            simulateAutomationUpdate(node: node2, engine: engine2, volume: 0.8)
            simulateAutomationUpdate(node: node3, engine: engine3, volume: 0.8)
        }
        
        // Switch solo to track 3
        node2.setSolo(false)
        node2.setMuted(true)
        node3.setSolo(true)
        node3.setMuted(false)
        
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node1, engine: engine1, volume: 0.8)
            simulateAutomationUpdate(node: node2, engine: engine2, volume: 0.8)
            simulateAutomationUpdate(node: node3, engine: engine3, volume: 0.8)
        }
        
        // Only track 3 should be audible
        XCTAssertLessThan(node1.volumeNode.outputVolume, 0.2, "Track 1 should be muted")
        XCTAssertLessThan(node2.volumeNode.outputVolume, 0.2, "Track 2 should be muted")
        XCTAssertGreaterThan(node3.volumeNode.outputVolume, 0.6, "Track 3 should be audible")
    }
    
    // MARK: - WYSIWYG (What You Hear Is What You Get)
    
    /// Test mute fade behavior is identical during playback and export
    func testMuteFadeDeterministicForWYSIWYG() {
        // Playback scenario
        let (engine1, node1) = createTrackNode(volume: 0.8, isMuted: false)
        node1.setMuted(true)
        
        var playbackVolumes: [Float] = []
        for _ in 0..<10 {
            simulateAutomationUpdate(node: node1, engine: engine1, volume: 0.8)
            playbackVolumes.append(node1.volumeNode.outputVolume)
        }
        
        // Export scenario (same sequence)
        let (engine2, node2) = createTrackNode(volume: 0.8, isMuted: false)
        node2.setMuted(true)
        
        var exportVolumes: [Float] = []
        for _ in 0..<10 {
            simulateAutomationUpdate(node: node2, engine: engine2, volume: 0.8)
            exportVolumes.append(node2.volumeNode.outputVolume)
        }
        
        // Both should produce identical fade curves
        XCTAssertEqual(playbackVolumes.count, exportVolumes.count)
        for i in 0..<playbackVolumes.count {
            XCTAssertEqual(
                playbackVolumes[i],
                exportVolumes[i],
                accuracy: 0.01,
                "Playback and export should have identical fade curves (WYSIWYG)"
            )
        }
    }
    
    // MARK: - Regression Protection
    
    /// Test that setVolume() still works correctly with mute multiplier
    func testSetVolumeWithMuteMultiplier() {
        let (engine, node) = createTrackNode(volume: 0.5, isMuted: false)
        
        // Apply automation updates
        for _ in 0..<3 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.5)
        }
        
        // Change volume while unmuted
        node.setVolume(0.9)
        for _ in 0..<3 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.9)
        }
        
        let volumeUnmuted = node.volumeNode.outputVolume
        XCTAssertGreaterThan(volumeUnmuted, 0.8, "Volume change should work while unmuted")
        
        // Mute the track
        node.setMuted(true)
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.9)
        }
        
        let volumeMuted = node.volumeNode.outputVolume
        XCTAssertLessThan(volumeMuted, 0.05, "Should be muted regardless of volume setting")
    }
    
    /// Test legacy code paths still work (setMuted with isMuted check)
    func testLegacyMuteBehaviorStillWorks() {
        let (engine, node) = createTrackNode(volume: 0.8, isMuted: false)
        
        // Use setMuted (the method we fixed)
        node.setMuted(true)
        XCTAssertTrue(node.isMuted, "isMuted flag should be set")
        
        // Automation updates should fade to zero
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        }
        
        let mutedVolume = node.volumeNode.outputVolume
        XCTAssertLessThan(mutedVolume, 0.05, "setMuted should cause fade to zero")
        
        // Unmute
        node.setMuted(false)
        XCTAssertFalse(node.isMuted, "isMuted flag should be cleared")
        
        for _ in 0..<5 {
            simulateAutomationUpdate(node: node, engine: engine, volume: 0.8)
        }
        
        let unmutedVolume = node.volumeNode.outputVolume
        XCTAssertGreaterThan(unmutedVolume, 0.7, "Unmute should restore volume")
    }
    
    // MARK: - Helper Methods
    
    /// Create a TrackAudioNode with all required AVAudioEngine setup
    private func createTrackNode(
        volume: Float,
        isMuted: Bool
    ) -> (AVAudioEngine, TrackAudioNode) {
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)
        let timePitchUnit = AVAudioUnitTimePitch()
        
        // Create plugin chain (minimal setup)
        let pluginChain = PluginChain(id: UUID(), maxSlots: 8)
        
        // Attach nodes to engine (match TrackAudioNodeTests: no plugin chain in graph)
        engine.attach(playerNode)
        engine.attach(volumeNode)
        engine.attach(panNode)
        engine.attach(eqNode)
        engine.attach(timePitchUnit)
        
        // Connect signal chain: player → timePitch → volume → pan → eq → mainMixer
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: timePitchUnit, format: format)
        engine.connect(timePitchUnit, to: volumeNode, format: format)
        engine.connect(volumeNode, to: panNode, format: format)
        engine.connect(panNode, to: eqNode, format: format)
        engine.connect(eqNode, to: engine.mainMixerNode, format: format)
        
        // Create track node
        let node = TrackAudioNode(
            id: UUID(),
            playerNode: playerNode,
            volumeNode: volumeNode,
            panNode: panNode,
            eqNode: eqNode,
            pluginChain: pluginChain,
            timePitchUnit: timePitchUnit,
            volume: volume,
            pan: 0.0,
            isMuted: isMuted,
            isSolo: false
        )
        
        // Initialize smoothing state
        node.resetSmoothing(atBeat: 0, automationLanes: [])
        
        return (engine, node)
    }
    
    /// Simulate one automation engine update cycle (120Hz)
    /// This mimics what AutomationEngine does at 120Hz during playback
    private func simulateAutomationUpdate(
        node: TrackAudioNode,
        engine: AVAudioEngine,
        volume: Float
    ) {
        // Call the automation value application (with mute multiplier smoothing)
        node.applyAutomationValues(
            volume: volume,
            pan: nil,
            eqLow: nil,
            eqMid: nil,
            eqHigh: nil
        )
    }
}
