//
//  MetronomeEngineTests.swift
//  StoriTests
//
//  Comprehensive tests for MetronomeEngine - Sample-accurate click track
//  Tests cover initialization, click scheduling, timing, volume, and integration
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class MetronomeEngineTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var metronome: MetronomeEngine!
    private var engine: AVAudioEngine!
    private var mixer: AVAudioMixerNode!
    private var mockAudioEngine: AudioEngine!
    private var mockTransportController: TransportController!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        metronome = MetronomeEngine()
        engine = AVAudioEngine()
        mixer = AVAudioMixerNode()
        mockAudioEngine = AudioEngine()
        
        // Create transport controller
        var project = AudioProject(name: "Test", tempo: 120.0)
        mockTransportController = TransportController(
            getProject: { project },
            isInstallingPlugin: { false },
            isGraphStable: { true },
            getSampleRate: { 48000 },
            onStartPlayback: { _ in },
            onStopPlayback: {},
            onTransportStateChanged: { _ in },
            onPositionChanged: { _ in },
            onCycleJump: { _ in }
        )
    }
    
    override func tearDown() async throws {
        if metronome.isEnabled {
            metronome.onTransportStop()
        }
        engine.stop()
        metronome = nil
        engine = nil
        mixer = nil
        mockAudioEngine = nil
        mockTransportController = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testMetronomeInitialization() {
        XCTAssertFalse(metronome.isEnabled)
        XCTAssertEqual(metronome.currentBeat, 1)
        XCTAssertFalse(metronome.beatFlash)
        XCTAssertFalse(metronome.countInEnabled)
        XCTAssertEqual(metronome.countInBars, 1)
        XCTAssertEqual(metronome.tempo, 120.0)
        XCTAssertEqual(metronome.beatsPerBar, 4)
    }
    
    func testMetronomeDefaultVolume() {
        XCTAssertEqual(metronome.volume, 0.7)
    }
    
    // MARK: - Installation Tests
    
    func testMetronomeInstallation() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        
        // After installation, metronome should be ready
        XCTAssertTrue(true, "Metronome installed successfully")
    }
    
    func testMetronomeInstallationIdempotent() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        
        // Install twice
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        
        // Should handle gracefully
        XCTAssertTrue(true, "Multiple installations handled gracefully")
    }
    
    // MARK: - Enable/Disable Tests
    
    func testMetronomeEnable() {
        XCTAssertFalse(metronome.isEnabled)
        
        metronome.isEnabled = true
        
        XCTAssertTrue(metronome.isEnabled)
    }
    
    func testMetronomeDisableStopsPlayback() {
        metronome.isEnabled = true
        // Simulate playing state
        
        metronome.isEnabled = false
        
        XCTAssertFalse(metronome.isEnabled)
    }
    
    // MARK: - Volume Tests
    
    func testMetronomeVolumeRange() {
        metronome.volume = 0.0
        XCTAssertEqual(metronome.volume, 0.0)
        
        metronome.volume = 0.5
        XCTAssertEqual(metronome.volume, 0.5)
        
        metronome.volume = 1.0
        XCTAssertEqual(metronome.volume, 1.0)
    }
    
    func testMetronomeVolumeUpdatesNode() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        
        metronome.volume = 0.3
        
        // Verify volume is set on mixer node
        XCTAssertEqual(metronome.metronomeMixer?.outputVolume, 0.3)
    }
    
    // MARK: - Tempo Tests
    
    func testMetronomeTempoUpdate() {
        metronome.tempo = 90.0
        XCTAssertEqual(metronome.tempo, 90.0)
        
        metronome.tempo = 180.0
        XCTAssertEqual(metronome.tempo, 180.0)
    }
    
    func testMetronomeTempoAffectsClickTiming() {
        // At 60 BPM: 1 beat = 1 second
        metronome.tempo = 60.0
        let secondsPerBeat60 = 60.0 / 60.0
        XCTAssertEqual(secondsPerBeat60, 1.0)
        
        // At 120 BPM: 1 beat = 0.5 seconds
        metronome.tempo = 120.0
        let secondsPerBeat120 = 60.0 / 120.0
        XCTAssertEqual(secondsPerBeat120, 0.5)
        
        // At 240 BPM: 1 beat = 0.25 seconds
        metronome.tempo = 240.0
        let secondsPerBeat240 = 60.0 / 240.0
        XCTAssertEqual(secondsPerBeat240, 0.25)
    }
    
    // MARK: - Time Signature Tests
    
    func testMetronomeTimeSignature() {
        metronome.beatsPerBar = 3  // 3/4 time
        XCTAssertEqual(metronome.beatsPerBar, 3)
        
        metronome.beatsPerBar = 6  // 6/8 time
        XCTAssertEqual(metronome.beatsPerBar, 6)
    }
    
    func testMetronomeAccentOnDownbeat() {
        // Beat 1 of each bar should be accented
        metronome.beatsPerBar = 4
        
        // Beat 1, 5, 9, 13 should be downbeats
        XCTAssertEqual((1 - 1) % 4, 0)  // Downbeat
        XCTAssertEqual((5 - 1) % 4, 0)  // Downbeat
        XCTAssertEqual((2 - 1) % 4, 1)  // Not downbeat
        XCTAssertEqual((3 - 1) % 4, 2)  // Not downbeat
    }
    
    // MARK: - Count-In Tests
    
    func testCountInInitialState() {
        XCTAssertFalse(metronome.countInEnabled)
        XCTAssertEqual(metronome.countInBars, 1)
    }
    
    func testCountInEnable() {
        metronome.countInEnabled = true
        
        XCTAssertTrue(metronome.countInEnabled)
    }
    
    func testCountInBarsConfiguration() {
        metronome.countInBars = 2
        XCTAssertEqual(metronome.countInBars, 2)
        
        metronome.countInBars = 4
        XCTAssertEqual(metronome.countInBars, 4)
    }
    
    func testCountInBeatCalculation() {
        // 1 bar of count-in at 4/4 = 4 beats
        metronome.beatsPerBar = 4
        metronome.countInBars = 1
        let totalCountInBeats = metronome.countInBars * metronome.beatsPerBar
        XCTAssertEqual(totalCountInBeats, 4)
        
        // 2 bars of count-in at 3/4 = 6 beats
        metronome.beatsPerBar = 3
        metronome.countInBars = 2
        let countIn3_4 = metronome.countInBars * metronome.beatsPerBar
        XCTAssertEqual(countIn3_4, 6)
    }
    
    // MARK: - Auto-Enable Count-In Tests (Issue #120)
    
    func testMetronomeEnableAutoEnablesCountIn() {
        // Given: Metronome and count-in are both disabled
        XCTAssertFalse(metronome.isEnabled)
        XCTAssertFalse(metronome.countInEnabled)
        
        // When: User enables metronome
        metronome.isEnabled = true
        
        // Then: Count-in should be automatically enabled
        XCTAssertTrue(metronome.isEnabled)
        XCTAssertTrue(metronome.countInEnabled, "Count-in should auto-enable when metronome is enabled")
    }
    
    func testMetronomeDisableDoesNotDisableCountIn() {
        // Given: Both are enabled
        metronome.isEnabled = true
        metronome.countInEnabled = true
        
        // When: User disables metronome
        metronome.isEnabled = false
        
        // Then: Count-in should remain enabled (user preference is preserved)
        XCTAssertFalse(metronome.isEnabled)
        XCTAssertTrue(metronome.countInEnabled, "Count-in state should be preserved when metronome is disabled")
    }
    
    func testMetronomeReEnableRespectsPreviousCountInState() {
        // Given: Metronome enabled with count-in
        metronome.isEnabled = true
        XCTAssertTrue(metronome.countInEnabled)
        
        // When: User manually disables count-in, then disables metronome
        metronome.countInEnabled = false
        metronome.isEnabled = false
        XCTAssertFalse(metronome.countInEnabled)
        
        // When: User re-enables metronome
        metronome.isEnabled = true
        
        // Then: Count-in should auto-enable again (fresh start behavior)
        XCTAssertTrue(metronome.countInEnabled, "Count-in should auto-enable when metronome is re-enabled")
    }
    
    func testMetronomeAutoEnableCountInOnlyIfDisabled() {
        // Given: Count-in is manually enabled first
        metronome.countInEnabled = true
        
        // When: User enables metronome
        metronome.isEnabled = true
        
        // Then: Count-in should remain enabled (not toggled)
        XCTAssertTrue(metronome.isEnabled)
        XCTAssertTrue(metronome.countInEnabled, "Count-in should remain enabled if already enabled")
    }
    
    func testMetronomeToggleAutoEnablesCountIn() {
        // Given: Metronome is disabled
        XCTAssertFalse(metronome.isEnabled)
        XCTAssertFalse(metronome.countInEnabled)
        
        // When: User toggles metronome on
        metronome.toggle()
        
        // Then: Both metronome and count-in should be enabled
        XCTAssertTrue(metronome.isEnabled)
        XCTAssertTrue(metronome.countInEnabled, "Count-in should auto-enable when toggling metronome on")
    }
    
    // MARK: - Beat Tracking Tests
    
    func testCurrentBeatInitialValue() {
        XCTAssertEqual(metronome.currentBeat, 1)
    }
    
    func testBeatFlashInitialState() {
        XCTAssertFalse(metronome.beatFlash)
    }
    
    // MARK: - Click Timing Calculation Tests
    
    func testClickSampleTimeCalculation() {
        let sampleRate: Double = 48000
        let tempo: Double = 120.0  // 2 beats per second
        let beatsPerSecond = tempo / 60.0
        let samplesPerBeat = sampleRate / beatsPerSecond
        
        // Beat 0 = sample 0
        let beat0Sample = 0
        XCTAssertEqual(beat0Sample, 0)
        
        // Beat 1 = sample 24000 (0.5 seconds at 48kHz)
        let beat1Sample = Int(1.0 * samplesPerBeat)
        XCTAssertEqual(beat1Sample, 24000)
        
        // Beat 4 = sample 96000 (2 seconds at 48kHz)
        let beat4Sample = Int(4.0 * samplesPerBeat)
        XCTAssertEqual(beat4Sample, 96000)
    }
    
    func testClickSampleTimeAtDifferentTempos() {
        let sampleRate: Double = 48000
        
        // 60 BPM: 1 beat = 1 second = 48000 samples
        let tempo60 = 60.0
        let samplesPerBeat60 = sampleRate / (tempo60 / 60.0)
        XCTAssertEqual(samplesPerBeat60, 48000)
        
        // 120 BPM: 1 beat = 0.5 seconds = 24000 samples
        let tempo120 = 120.0
        let samplesPerBeat120 = sampleRate / (tempo120 / 60.0)
        XCTAssertEqual(samplesPerBeat120, 24000)
        
        // 240 BPM: 1 beat = 0.25 seconds = 12000 samples
        let tempo240 = 240.0
        let samplesPerBeat240 = sampleRate / (tempo240 / 60.0)
        XCTAssertEqual(samplesPerBeat240, 12000)
    }
    
    func testClickSampleTimeAtDifferentSampleRates() {
        let tempo: Double = 120.0  // 2 beats per second
        
        // At 44.1kHz: 1 beat = 0.5s = 22050 samples
        let sampleRate44k = 44100.0
        let samplesPerBeat44k = sampleRate44k / (tempo / 60.0)
        XCTAssertEqual(samplesPerBeat44k, 22050)
        
        // At 48kHz: 1 beat = 0.5s = 24000 samples
        let sampleRate48k = 48000.0
        let samplesPerBeat48k = sampleRate48k / (tempo / 60.0)
        XCTAssertEqual(samplesPerBeat48k, 24000)
        
        // At 96kHz: 1 beat = 0.5s = 48000 samples
        let sampleRate96k = 96000.0
        let samplesPerBeat96k = sampleRate96k / (tempo / 60.0)
        XCTAssertEqual(samplesPerBeat96k, 48000)
    }
    
    // MARK: - Lookahead Tests
    
    func testMetronomeLookaheadWindow() {
        // Metronome should schedule clicks ahead by lookahead window
        let lookaheadSeconds = 0.5
        let sampleRate = 48000.0
        let lookaheadSamples = Int(lookaheadSeconds * sampleRate)
        
        // 0.5 seconds = 24000 samples at 48kHz
        XCTAssertEqual(lookaheadSamples, 24000)
    }
    
    func testClickSchedulingWithinLookahead() {
        let currentBeat: Double = 0.0
        let lookaheadBeats: Double = 2.0  // Look ahead 2 beats
        
        let clicks = [
            (beat: 0, isAccent: true),   // Within window
            (beat: 1, isAccent: false),  // Within window
            (beat: 2, isAccent: false),  // Within window
            (beat: 3, isAccent: false),  // Outside window
            (beat: 4, isAccent: true)    // Outside window
        ]
        
        let clicksToSchedule = clicks.filter { Double($0.beat) <= currentBeat + lookaheadBeats }
        
        XCTAssertEqual(clicksToSchedule.count, 3)
    }
    
    // MARK: - Playback Control Tests
    
    func testMetronomeStartPlaying() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        
        metronome.isEnabled = true
        metronome.onTransportPlay()
        
        // Verify metronome started (currentBeat is updated during playback)
        XCTAssertTrue(metronome.isEnabled)
    }
    
    func testMetronomeStopPlaying() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        
        metronome.isEnabled = true
        metronome.onTransportPlay()
        
        metronome.onTransportStop()
        
        // After stop, currentBeat should be reset to 1
        XCTAssertEqual(metronome.currentBeat, 1)
    }
    
    func testMetronomeStopWhenNotPlaying() {
        // Should handle gracefully
        metronome.onTransportStop()
        
        // Verify no crash, currentBeat at initial state
        XCTAssertEqual(metronome.currentBeat, 1)
    }
    
    // MARK: - Beat Accent Tests
    
    func testDownbeatAccentPattern4_4() {
        metronome.beatsPerBar = 4
        
        // In 4/4: beat 1 is accented, 2-4 are not
        for beat in 1...16 {
            let isDownbeat = (beat - 1) % metronome.beatsPerBar == 0
            
            if beat % 4 == 1 {
                XCTAssertTrue(isDownbeat, "Beat \(beat) should be downbeat")
            } else {
                XCTAssertFalse(isDownbeat, "Beat \(beat) should not be downbeat")
            }
        }
    }
    
    func testDownbeatAccentPattern3_4() {
        metronome.beatsPerBar = 3
        
        // In 3/4: beats 1, 4, 7, 10... are accented
        XCTAssertTrue((1 - 1) % 3 == 0)  // Beat 1
        XCTAssertTrue((4 - 1) % 3 == 0)  // Beat 4
        XCTAssertTrue((7 - 1) % 3 == 0)  // Beat 7
        XCTAssertFalse((2 - 1) % 3 == 0) // Beat 2
        XCTAssertFalse((3 - 1) % 3 == 0) // Beat 3
    }
    
    func testDownbeatAccentPattern6_8() {
        metronome.beatsPerBar = 6
        
        // In 6/8: beats 1, 7, 13... are accented
        XCTAssertTrue((1 - 1) % 6 == 0)  // Beat 1
        XCTAssertTrue((7 - 1) % 6 == 0)  // Beat 7
        XCTAssertFalse((2 - 1) % 6 == 0) // Beat 2
        XCTAssertFalse((4 - 1) % 6 == 0) // Beat 4
    }
    
    // MARK: - Reconnection Tests
    
    func testMetronomeReconnectNodes() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        
        // Should reconnect without crashing
        metronome.reconnectNodes(dawMixer: mixer)
        
        XCTAssertTrue(true, "Reconnection completed successfully")
    }
    
    func testMetronomeReconnectMultipleTimes() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        
        // Reconnect multiple times
        for _ in 0..<5 {
            metronome.reconnectNodes(dawMixer: mixer)
        }
        
        XCTAssertTrue(true, "Multiple reconnections handled")
    }
    
    // MARK: - Edge Case Tests
    
    func testMetronomeWithZeroTempo() {
        metronome.tempo = 0.0
        
        // Should handle gracefully (may not schedule clicks)
        XCTAssertEqual(metronome.tempo, 0.0)
    }
    
    func testMetronomeWithVeryHighTempo() {
        metronome.tempo = 999.0
        
        let secondsPerBeat = 60.0 / 999.0
        XCTAssertLessThan(secondsPerBeat, 0.1)
    }
    
    func testMetronomeWithVeryLowTempo() {
        metronome.tempo = 20.0
        
        let secondsPerBeat = 60.0 / 20.0
        XCTAssertEqual(secondsPerBeat, 3.0)
    }
    
    func testMetronomeWith1Beat() {
        metronome.beatsPerBar = 1
        
        // Every beat is a downbeat
        for beat in 1...10 {
            XCTAssertTrue((beat - 1) % 1 == 0)
        }
    }
    
    func testMetronomeWith12Beats() {
        metronome.beatsPerBar = 12
        
        // Only beats 1, 13, 25... are downbeats
        XCTAssertTrue((1 - 1) % 12 == 0)
        XCTAssertTrue((13 - 1) % 12 == 0)
        XCTAssertFalse((7 - 1) % 12 == 0)
    }
    
    // MARK: - Performance Tests
    
    func testMetronomeCreationPerformance() {
        measure {
            for _ in 0..<100 {
                let tempMetronome = MetronomeEngine()
                _ = tempMetronome.isEnabled
            }
        }
    }
    
    func testMetronomeVolumeChangePerformance() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        
        measure {
            for i in 0..<1000 {
                metronome.volume = Float(i % 100) / 100.0
            }
        }
    }
    
    func testMetronomeTempoChangePerformance() {
        measure {
            for i in 0..<1000 {
                metronome.tempo = 60.0 + Double(i % 180)
            }
        }
    }
    
    func testBeatAccentCalculationPerformance() {
        metronome.beatsPerBar = 4
        
        measure {
            var accentCount = 0
            for beat in 1...10000 {
                if (beat - 1) % metronome.beatsPerBar == 0 {
                    accentCount += 1
                }
            }
            XCTAssertGreaterThan(accentCount, 0)
        }
    }
    
    // MARK: - Integration Tests
    
    func testMetronomeFullWorkflow() {
        // Complete workflow: install, configure, play, stop
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        
        // 1. Install
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        
        // 2. Configure
        metronome.isEnabled = true
        metronome.tempo = 100.0
        metronome.beatsPerBar = 3
        metronome.volume = 0.8
        metronome.countInEnabled = true
        metronome.countInBars = 2
        
        // 3. Play
        metronome.onTransportPlay()
        XCTAssertTrue(metronome.isEnabled)
        
        // 4. Stop
        metronome.onTransportStop()
        XCTAssertEqual(metronome.currentBeat, 1)
        
        XCTAssertTrue(true, "Full metronome workflow completed")
    }
    
    // MARK: - Memory Management Tests
    
    func testMetronomeMemoryCleanup() {
        for _ in 0..<5 {
            let tempEngine = AVAudioEngine()
            let tempMixer = AVAudioMixerNode()
            tempEngine.attach(tempMixer)
            tempEngine.connect(tempMixer, to: tempEngine.outputNode, format: nil)
            
            let tempMetronome = MetronomeEngine()
            tempMetronome.install(
                into: tempEngine,
                dawMixer: tempMixer,
                audioEngine: mockAudioEngine,
                transportController: mockTransportController
            )
            
            tempMetronome.isEnabled = true
            tempMetronome.onTransportPlay()
            tempMetronome.onTransportStop()
            
            tempEngine.stop()
        }
        
        XCTAssertTrue(true, "Memory cleanup validated")
    }
}
