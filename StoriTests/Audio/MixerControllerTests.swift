//
//  MixerControllerTests.swift
//  StoriTests
//
//  Unit tests for MixerController - Track/bus mixing functionality
//

import XCTest
@testable import Stori
import AVFoundation

/// Reference-type project holder for tests so getProject/setProject share the same storage.
private final class ProjectRef {
    var project: AudioProject
    init(_ project: AudioProject) { self.project = project }
}

/// No-op instrument manager for testing MixerController without InstrumentManager.shared side effects.
@MainActor
private final class NoopInstrumentManager: MixerInstrumentManaging {
    func setVolume(_ volume: Float, forTrack trackId: UUID) {}
    func setPan(_ pan: Float, forTrack trackId: UUID) {}
    func setMuted(_ muted: Bool, forTrack trackId: UUID) {}
}

final class MixerControllerTests: XCTestCase {
    
    // MARK: - Volume Tests
    
    func testMixerSettingsVolumeRange() {
        var settings = MixerSettings()
        
        settings.volume = 1.0
        XCTAssertEqual(settings.volume, 1.0)
        
        settings.volume = 0.0
        XCTAssertEqual(settings.volume, 0.0)
        
        settings.volume = 0.5
        XCTAssertEqual(settings.volume, 0.5)
    }
    
    func testVolumeDecibelConversion() {
        // Linear to dB conversion: dB = 20 * log10(linear)
        let linearUnity: Float = 1.0
        let linearHalf: Float = 0.5
        let linearZero: Float = 0.0
        
        let dbUnity = 20 * log10(linearUnity)
        let dbHalf = 20 * log10(linearHalf)
        
        assertApproximatelyEqual(dbUnity, 0.0)      // 1.0 linear = 0 dB
        assertApproximatelyEqual(dbHalf, -6.02, tolerance: 0.1)  // 0.5 linear ≈ -6 dB
        XCTAssertEqual(linearZero, 0.0)  // Zero stays zero (avoid -infinity)
    }
    
    func testDecibelToLinearConversion() {
        // dB to linear: linear = 10^(dB/20)
        let dbUnity: Float = 0.0
        let dbMinus6: Float = -6.0
        let dbMinus12: Float = -12.0
        
        let linearUnity = pow(10, dbUnity / 20)
        let linearMinus6 = pow(10, dbMinus6 / 20)
        let linearMinus12 = pow(10, dbMinus12 / 20)
        
        assertApproximatelyEqual(linearUnity, 1.0)
        assertApproximatelyEqual(linearMinus6, 0.501, tolerance: 0.01)  // ≈ 0.5
        assertApproximatelyEqual(linearMinus12, 0.251, tolerance: 0.01)  // ≈ 0.25
    }
    
    // MARK: - Pan Tests
    
    func testMixerSettingsPanRange() {
        var settings = MixerSettings()
        
        // Pan is stored as 0-1 (0.5 = center)
        settings.pan = 0.0   // Full left
        XCTAssertEqual(settings.pan, 0.0)
        
        settings.pan = 0.5   // Center
        XCTAssertEqual(settings.pan, 0.5)
        
        settings.pan = 1.0   // Full right
        XCTAssertEqual(settings.pan, 1.0)
    }
    
    func testPanLawConstantPower() {
        // Constant power pan law: leftGain = cos(pan * π/2), rightGain = sin(pan * π/2)
        // This maintains constant perceived loudness across the stereo field
        
        let panCenter: Float = 0.5
        let panLeft: Float = 0.0
        let panRight: Float = 1.0
        
        // Convert 0-1 pan to radians (0 = full left, 1 = full right)
        func panGains(_ pan: Float) -> (left: Float, right: Float) {
            let angle = pan * Float.pi / 2
            return (cos(angle), sin(angle))
        }
        
        let centerGains = panGains(panCenter)
        let leftGains = panGains(panLeft)
        let rightGains = panGains(panRight)
        
        // Center: both channels equal (≈ 0.707)
        assertApproximatelyEqual(centerGains.left, 0.707, tolerance: 0.01)
        assertApproximatelyEqual(centerGains.right, 0.707, tolerance: 0.01)
        
        // Full left: left = 1, right = 0
        assertApproximatelyEqual(leftGains.left, 1.0)
        assertApproximatelyEqual(leftGains.right, 0.0, tolerance: 0.01)
        
        // Full right: left = 0, right = 1
        assertApproximatelyEqual(rightGains.left, 0.0, tolerance: 0.01)
        assertApproximatelyEqual(rightGains.right, 1.0)
    }
    
    // MARK: - Mute/Solo Tests
    
    func testMuteState() {
        var settings = MixerSettings()
        
        XCTAssertFalse(settings.isMuted)
        
        settings.isMuted = true
        XCTAssertTrue(settings.isMuted)
    }
    
    func testSoloState() {
        var settings = MixerSettings()
        
        XCTAssertFalse(settings.isSolo)
        
        settings.isSolo = true
        XCTAssertTrue(settings.isSolo)
    }
    
    func testSoloSafe() {
        var settings = MixerSettings()
        
        XCTAssertFalse(settings.soloSafe)
        
        settings.soloSafe = true
        XCTAssertTrue(settings.soloSafe)
    }
    
    func testSoloLogic() {
        // Create multiple tracks
        var track1 = AudioTrack(name: "Track 1")
        var track2 = AudioTrack(name: "Track 2")
        var track3 = AudioTrack(name: "Track 3")
        
        // Solo track 1
        track1.mixerSettings.isSolo = true
        
        // Calculate effective mute states
        let anyTrackSoloed = track1.mixerSettings.isSolo || 
                             track2.mixerSettings.isSolo || 
                             track3.mixerSettings.isSolo
        
        func isEffectivelyMuted(_ track: AudioTrack) -> Bool {
            if track.mixerSettings.isMuted { return true }
            if anyTrackSoloed && !track.mixerSettings.isSolo && !track.mixerSettings.soloSafe {
                return true
            }
            return false
        }
        
        XCTAssertFalse(isEffectivelyMuted(track1), "Soloed track should not be muted")
        XCTAssertTrue(isEffectivelyMuted(track2), "Non-soloed track should be muted")
        XCTAssertTrue(isEffectivelyMuted(track3), "Non-soloed track should be muted")
    }
    
    func testSoloSafeLogic() {
        var track1 = AudioTrack(name: "Track 1")
        var track2 = AudioTrack(name: "Track 2")
        var reverbBus = AudioTrack(name: "Reverb Return", trackType: .bus)
        
        track1.mixerSettings.isSolo = true
        reverbBus.mixerSettings.soloSafe = true  // Reverb should always be audible
        
        let anyTrackSoloed = track1.mixerSettings.isSolo
        
        func isEffectivelyMuted(_ track: AudioTrack) -> Bool {
            if track.mixerSettings.isMuted { return true }
            if anyTrackSoloed && !track.mixerSettings.isSolo && !track.mixerSettings.soloSafe {
                return true
            }
            return false
        }
        
        XCTAssertFalse(isEffectivelyMuted(track1))
        XCTAssertTrue(isEffectivelyMuted(track2))
        XCTAssertFalse(isEffectivelyMuted(reverbBus), "Solo-safe track should not be muted")
    }
    
    // MARK: - EQ Tests
    
    func testEQDefaults() {
        let settings = MixerSettings()
        
        XCTAssertEqual(settings.lowEQ, 0.0)
        XCTAssertEqual(settings.midEQ, 0.0)
        XCTAssertEqual(settings.highEQ, 0.0)
        XCTAssertTrue(settings.eqEnabled)
    }
    
    func testEQBypass() {
        var settings = MixerSettings()
        settings.lowEQ = 6.0   // +6 dB
        settings.eqEnabled = false
        
        // When EQ is bypassed, gain should be flat regardless of EQ values
        XCTAssertFalse(settings.eqEnabled)
        XCTAssertEqual(settings.lowEQ, 6.0)  // Value preserved but not applied
    }
    
    // MARK: - Phase Invert Tests
    
    func testPhaseInvert() {
        var settings = MixerSettings()
        
        XCTAssertFalse(settings.phaseInverted)
        
        settings.phaseInverted = true
        XCTAssertTrue(settings.phaseInverted)
    }
    
    func testPhaseInvertEffect() {
        // Phase invert multiplies all samples by -1
        let inputSamples: [Float] = [0.5, -0.3, 0.8, -0.2]
        let phaseInverted = inputSamples.map { $0 * -1.0 }
        
        XCTAssertEqual(phaseInverted[0], -0.5)
        XCTAssertEqual(phaseInverted[1], 0.3)
        XCTAssertEqual(phaseInverted[2], -0.8)
        XCTAssertEqual(phaseInverted[3], 0.2)
    }
    
    // MARK: - Input/Output Trim Tests
    
    func testInputOutputTrim() {
        var settings = MixerSettings()
        
        XCTAssertEqual(settings.inputTrim, 0.0)
        XCTAssertEqual(settings.outputTrim, 0.0)
        
        settings.inputTrim = 6.0   // +6 dB
        settings.outputTrim = -3.0  // -3 dB
        
        XCTAssertEqual(settings.inputTrim, 6.0)
        XCTAssertEqual(settings.outputTrim, -3.0)
    }
    
    // MARK: - Track Send Tests
    
    func testTrackSendCreation() {
        let busId = UUID()
        let send = TrackSend(busId: busId, sendLevel: 0.5, isPreFader: true)
        
        XCTAssertEqual(send.busId, busId)
        XCTAssertEqual(send.sendLevel, 0.5)
        XCTAssertTrue(send.isPreFader)
        XCTAssertEqual(send.pan, 0.0)
        XCTAssertFalse(send.isMuted)
    }
    
    func testTrackSendPreVsPostFader() {
        let busId = UUID()
        
        let preFaderSend = TrackSend(busId: busId, sendLevel: 0.5, isPreFader: true)
        let postFaderSend = TrackSend(busId: busId, sendLevel: 0.5, isPreFader: false)
        
        // Pre-fader: send level is independent of track fader
        // Post-fader: send level is affected by track fader
        
        let trackVolume: Float = 0.8
        let preFaderOutput = preFaderSend.sendLevel  // 0.5 (unaffected)
        let postFaderOutput = postFaderSend.sendLevel * Double(trackVolume)  // 0.5 * 0.8 = 0.4
        
        assertApproximatelyEqual(Float(preFaderOutput), 0.5)
        assertApproximatelyEqual(Float(postFaderOutput), 0.4)
    }
    
    // MARK: - Bus Tests
    
    func testMixerBusCreation() {
        let bus = MixerBus(name: "Reverb", outputLevel: 0.6)
        
        XCTAssertEqual(bus.name, "Reverb")
        XCTAssertEqual(bus.outputLevel, 0.6)
        XCTAssertEqual(bus.inputLevel, 0.0)
        XCTAssertFalse(bus.isMuted)
        XCTAssertFalse(bus.isSolo)
    }
    
    // NOTE: testBusEffectChain removed - BusEffect type was deprecated
    // Bus effects are now handled via PluginChain
    
    // MARK: - Mock Audio Engine Mixer Tests
    
    @MainActor
    func testMockMixerVolume() async {
        let mockEngine = MockAudioEngine()
        let trackId = UUID()
        
        mockEngine.setTrackVolume(trackId, volume: 0.7)
        
        XCTAssertEqual(mockEngine.trackVolumes[trackId], 0.7)
    }
    
    @MainActor
    func testMockMixerPan() async {
        let mockEngine = MockAudioEngine()
        let trackId = UUID()
        
        mockEngine.setTrackPan(trackId, pan: -0.5)
        
        XCTAssertEqual(mockEngine.trackPans[trackId], -0.5)
    }
    
    @MainActor
    func testMockMixerMute() async {
        let mockEngine = MockAudioEngine()
        let trackId = UUID()
        
        mockEngine.setTrackMute(trackId, muted: true)
        
        XCTAssertTrue(mockEngine.trackMutes[trackId] ?? false)
    }
    
    @MainActor
    func testMockMixerSolo() async {
        let mockEngine = MockAudioEngine()
        let trackId = UUID()
        
        mockEngine.setTrackSolo(trackId, soloed: true)
        
        XCTAssertTrue(mockEngine.trackSolos[trackId] ?? false)
    }
    
    // MARK: - Metering Tests
    
    @MainActor
    func testMockMeteringWhenPlaying() async throws {
        let mockEngine = MockAudioEngine()
        let trackId = UUID()
        
        try mockEngine.play()
        
        let level = mockEngine.getTrackLevel(trackId)
        
        XCTAssertLessThanOrEqual(level, 0)  // dB levels are <= 0 for non-clipping
        XCTAssertGreaterThan(level, -Float.infinity)
    }
    
    @MainActor
    func testMockMeteringWhenStopped() async {
        let mockEngine = MockAudioEngine()
        let trackId = UUID()
        
        let level = mockEngine.getTrackLevel(trackId)
        
        XCTAssertEqual(level, -Float.infinity)
    }
    
    @MainActor
    func testMockMeteringMutedTrack() async throws {
        let mockEngine = MockAudioEngine()
        let trackId = UUID()
        
        mockEngine.setTrackMute(trackId, muted: true)
        try mockEngine.play()
        
        let level = mockEngine.getTrackLevel(trackId)
        
        XCTAssertEqual(level, -Float.infinity, "Muted track should show no level")
    }
    
    // MARK: - Audio Node Processing Tests
    
    func testMockAudioNodeVolume() {
        var node = MockAudioNode(id: UUID(), volume: 0.5)
        let input = TestAudioBuffers.sineWaveBuffer(
            frequency: 440,
            sampleRate: 48000,
            frameCount: 1024,
            amplitude: 1.0
        )
        
        let output = node.process(inputBuffer: input)
        
        // Output should be approximately half amplitude
        let inputPeak = TestAudioBuffers.peakLevel(input[0])
        let outputPeak = TestAudioBuffers.peakLevel(output[0])
        
        assertApproximatelyEqual(outputPeak, inputPeak * 0.5, tolerance: 0.01)
    }
    
    func testMockAudioNodeMute() {
        var node = MockAudioNode(id: UUID(), isMuted: true)
        let input = TestAudioBuffers.sineWaveBuffer(
            frequency: 440,
            sampleRate: 48000,
            frameCount: 1024,
            amplitude: 1.0
        )
        
        let output = node.process(inputBuffer: input)
        
        // Output should be silent
        let outputPeak = TestAudioBuffers.peakLevel(output[0])
        XCTAssertEqual(outputPeak, 0.0)
    }
    
    func testMockAudioNodeBypass() {
        var node = MockAudioNode(id: UUID(), isBypassed: true)
        let input = TestAudioBuffers.sineWaveBuffer(
            frequency: 440,
            sampleRate: 48000,
            frameCount: 1024,
            amplitude: 1.0
        )
        
        let output = node.process(inputBuffer: input)
        
        // Bypassed should also be silent (true bypass would pass through, but our mock zeros)
        let outputPeak = TestAudioBuffers.peakLevel(output[0])
        XCTAssertEqual(outputPeak, 0.0)
    }
    
    // MARK: - Track Index Cache
    
    @MainActor
    func testInvalidateTrackIndexCacheAllowsSubsequentUpdates() async {
        let engine = AVAudioEngine()
        let mixer = AVAudioMixerNode()
        let eq = AVAudioUnitEQ()
        engine.attach(mixer)
        engine.attach(eq)
        
        var project = AudioProject(name: "Test", tempo: 120)
        project.addTrack(AudioTrack(name: "T1", trackType: .audio, color: .blue))
        let trackId = project.tracks[0].id
        
        let holder = ProjectRef(project)
        
        // Use no-op instrument manager to avoid InstrumentManager.shared singleton side effects
        let controller = MixerController(
            getProject: { holder.project },
            setProject: { holder.project = $0 },
            getTrackNodes: { [:] },
            getMainMixer: { mixer },
            getMasterEQ: { eq },
            onReloadMIDIRegions: {},
            onSafeDisconnectTrackNode: { _ in },
            instrumentManager: NoopInstrumentManager()
        )
        
        controller.updateTrackVolume(trackId: trackId, volume: 0.5)
        XCTAssertEqual(holder.project.tracks.first?.mixerSettings.volume, 0.5, "First update should persist")
        
        controller.invalidateTrackIndexCache()
        controller.updateTrackVolume(trackId: trackId, volume: 0.7)
        XCTAssertEqual(holder.project.tracks.first?.mixerSettings.volume, 0.7, "Update after cache invalidation should persist")
    }
    
    // MARK: - Performance Tests
    
    func testMixerSettingsCreationPerformance() {
        measure {
            for _ in 0..<1000 {
                _ = MixerSettings()
            }
        }
    }
    
    func testPanCalculationPerformance() {
        measure {
            for i in 0..<10000 {
                let pan = Float(i % 100) / 100.0
                let angle = pan * Float.pi / 2
                _ = (cos(angle), sin(angle))
            }
        }
    }
}
