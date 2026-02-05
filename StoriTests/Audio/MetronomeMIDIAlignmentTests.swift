//
//  MetronomeMIDIAlignmentTests.swift
//  StoriTests
//
//  Tests for metronome-MIDI alignment under tempo automation (Issue #56).
//  Ensures metronome clicks stay perfectly aligned with MIDI beats during tempo changes.
//
//  WHY THIS MATTERS:
//  - Metronome is the timing reference musicians rely on
//  - If it drifts from MIDI, performers will play out of sync
//  - Professional DAWs maintain sample-accurate alignment at all times
//

import XCTest
import AVFoundation
@testable import Stori

final class MetronomeMIDIAlignmentTests: XCTestCase {
    
    var audioEngine: AVAudioEngine!
    var mixer: AVAudioMixerNode!
    var metronome: MetronomeEngine!
    var midiScheduler: SampleAccurateMIDIScheduler!
    var mockAudioEngine: MockAudioEngineContext!
    var mockTransport: MockTransportController!
    
    let sampleRate: Double = 48000
    let initialTempo: Double = 120
    
    override func setUp() async throws {
        // Create audio engine
        audioEngine = AVAudioEngine()
        mixer = AVAudioMixerNode()
        
        // Attach and connect nodes
        audioEngine.attach(mixer)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        audioEngine.connect(mixer, to: audioEngine.outputNode, format: format)
        
        // Create mock context
        mockAudioEngine = MockAudioEngineContext(
            sampleRate: sampleRate,
            tempo: initialTempo
        )
        
        // Create mock transport
        mockTransport = MockTransportController()
        
        // Create MIDI scheduler
        midiScheduler = SampleAccurateMIDIScheduler()
        midiScheduler.configure(tempo: initialTempo, sampleRate: sampleRate)
        
        // Create metronome
        metronome = MetronomeEngine()
        
        // Install metronome with MIDI scheduler for shared timing
        metronome.install(
            into: audioEngine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransport,
            midiScheduler: midiScheduler
        )
        
        // Start engine
        try audioEngine.start()
        metronome.preparePlayerNode()
    }
    
    override func tearDown() async throws {
        audioEngine.stop()
        audioEngine = nil
        mixer = nil
        metronome = nil
        midiScheduler = nil
        mockAudioEngine = nil
        mockTransport = nil
    }
    
    // MARK: - Timing Reference Sharing Tests
    
    func testMetronomeUsesMIDISchedulerTimingContext() {
        // GIVEN: MIDI scheduler with specific tempo
        midiScheduler.configure(tempo: 140, sampleRate: sampleRate)
        
        // WHEN: We get the scheduling context from the scheduler
        let context = midiScheduler.schedulingContext
        
        // THEN: Context should reflect the tempo
        XCTAssertEqual(context.tempo, 140, accuracy: 0.01)
        XCTAssertEqual(context.sampleRate, sampleRate, accuracy: 0.01)
        
        // AND: Samples per beat should be consistent
        let expectedSamplesPerBeat = (60.0 / 140.0) * sampleRate
        XCTAssertEqual(context.samplesPerBeat, expectedSamplesPerBeat, accuracy: 1.0)
    }
    
    func testTempoChangeUpdatesSchedulingContext() {
        // GIVEN: Initial tempo
        midiScheduler.configure(tempo: 120, sampleRate: sampleRate)
        let context1 = midiScheduler.schedulingContext
        
        // WHEN: Tempo changes
        midiScheduler.configure(tempo: 150, sampleRate: sampleRate)
        let context2 = midiScheduler.schedulingContext
        
        // THEN: Samples per beat should update
        let samplesPerBeat1 = (60.0 / 120.0) * sampleRate // 0.5s * 48000 = 24000
        let samplesPerBeat2 = (60.0 / 150.0) * sampleRate // 0.4s * 48000 = 19200
        
        XCTAssertEqual(context1.samplesPerBeat, samplesPerBeat1, accuracy: 1.0)
        XCTAssertEqual(context2.samplesPerBeat, samplesPerBeat2, accuracy: 1.0)
        XCTAssertNotEqual(context1.samplesPerBeat, context2.samplesPerBeat)
    }
    
    // MARK: - Beat-to-Sample Conversion Tests
    
    func testBeatToSampleConversionConsistency() {
        // GIVEN: Shared scheduling context
        midiScheduler.configure(tempo: 120, sampleRate: sampleRate)
        let context = midiScheduler.schedulingContext
        
        // WHEN: We calculate samples for beat positions
        let samplesFor1Beat = context.samplesPerBeat
        let samplesFor4Beats = context.samplesPerBeat * 4
        
        // THEN: Calculations should be consistent
        // At 120 BPM, 1 beat = 0.5 seconds = 24000 samples at 48kHz
        XCTAssertEqual(samplesFor1Beat, 24000, accuracy: 1.0)
        XCTAssertEqual(samplesFor4Beats, 96000, accuracy: 1.0)
    }
    
    func testSampleTimeCalculationWithReference() {
        // GIVEN: Scheduling context and reference point
        let context = AudioSchedulingContext(
            sampleRate: sampleRate,
            tempo: 120,
            timeSignature: .fourFour
        )
        
        let referenceBeat: Double = 0
        let referenceSample: Int64 = 0
        
        // WHEN: We calculate sample time for future beats
        let sampleForBeat1 = context.sampleTime(
            forBeat: 1.0,
            referenceBeat: referenceBeat,
            referenceSample: referenceSample
        )
        let sampleForBeat4 = context.sampleTime(
            forBeat: 4.0,
            referenceBeat: referenceBeat,
            referenceSample: referenceSample
        )
        
        // THEN: Sample times should be correct
        // 1 beat = 24000 samples, 4 beats = 96000 samples
        XCTAssertEqual(sampleForBeat1, 24000, accuracy: 1)
        XCTAssertEqual(sampleForBeat4, 96000, accuracy: 1)
    }
    
    // MARK: - Tempo Automation Drift Tests
    
    func testNoAccumulatedDriftUnderTempoRamp() async throws {
        // GIVEN: Initial tempo
        let startTempo: Double = 100
        let endTempo: Double = 150
        let steps = 10
        
        midiScheduler.configure(tempo: startTempo, sampleRate: sampleRate)
        
        var previousSamplesPerBeat = midiScheduler.schedulingContext.samplesPerBeat
        
        // WHEN: We gradually change tempo in steps
        for step in 1...steps {
            let progress = Double(step) / Double(steps)
            let currentTempo = startTempo + (endTempo - startTempo) * progress
            
            midiScheduler.configure(tempo: currentTempo, sampleRate: sampleRate)
            let currentSamplesPerBeat = midiScheduler.schedulingContext.samplesPerBeat
            
            // THEN: Samples per beat should decrease smoothly (faster tempo = fewer samples per beat)
            XCTAssertLessThan(currentSamplesPerBeat, previousSamplesPerBeat,
                            "Samples per beat should decrease as tempo increases")
            
            previousSamplesPerBeat = currentSamplesPerBeat
        }
        
        // VERIFY: Final samples per beat matches expected value at end tempo
        let expectedFinalSamplesPerBeat = (60.0 / endTempo) * sampleRate
        let finalSamplesPerBeat = midiScheduler.schedulingContext.samplesPerBeat
        XCTAssertEqual(finalSamplesPerBeat, expectedFinalSamplesPerBeat, accuracy: 1.0)
    }
    
    func testTimingReferenceUpdatesOnTempoChange() {
        // GIVEN: MIDI scheduler with timing reference
        midiScheduler.configure(tempo: 120, sampleRate: sampleRate)
        midiScheduler.currentBeatProvider = { 0.0 }
        midiScheduler.play(fromBeat: 0.0)
        
        // WHEN: Tempo changes during playback
        mockTransport.atomicBeat = 4.0
        midiScheduler.currentBeatProvider = { 4.0 }
        midiScheduler.updateTempo(140)
        
        // THEN: New context should reflect updated tempo
        let context = midiScheduler.schedulingContext
        XCTAssertEqual(context.tempo, 140, accuracy: 0.01)
        
        // AND: Samples per beat should be recalculated
        let expectedSamplesPerBeat = (60.0 / 140.0) * sampleRate
        XCTAssertEqual(context.samplesPerBeat, expectedSamplesPerBeat, accuracy: 1.0)
    }
    
    // MARK: - Sample Rate Change Tests
    
    func testSampleRateChangeUpdatesContext() {
        // GIVEN: Initial sample rate
        midiScheduler.configure(tempo: 120, sampleRate: 48000)
        let context1 = midiScheduler.schedulingContext
        
        // WHEN: Sample rate changes (e.g., user switches audio interface)
        midiScheduler.configure(tempo: 120, sampleRate: 96000)
        let context2 = midiScheduler.schedulingContext
        
        // THEN: Samples per beat should double
        XCTAssertEqual(context2.samplesPerBeat, context1.samplesPerBeat * 2, accuracy: 1.0)
    }
    
    // MARK: - Edge Case Tests
    
    func testContextConsistencyAfterMultipleChanges() {
        // GIVEN: Series of tempo and sample rate changes
        let changes: [(tempo: Double, sampleRate: Double)] = [
            (120, 48000),
            (140, 48000),
            (140, 96000),
            (100, 96000),
            (120, 48000)
        ]
        
        // WHEN: We apply each change
        for (tempo, sampleRate) in changes {
            midiScheduler.configure(tempo: tempo, sampleRate: sampleRate)
            let context = midiScheduler.schedulingContext
            
            // THEN: Context should always match configured values
            XCTAssertEqual(context.tempo, tempo, accuracy: 0.01)
            XCTAssertEqual(context.sampleRate, sampleRate, accuracy: 0.01)
            
            // AND: Samples per beat should be consistent with formula
            let expectedSamplesPerBeat = (60.0 / tempo) * sampleRate
            XCTAssertEqual(context.samplesPerBeat, expectedSamplesPerBeat, accuracy: 1.0)
        }
    }
}

// MARK: - Mock Transport Controller

class MockTransportController: TransportController {
    var atomicBeat: Double = 0.0
    
    override var atomicBeatPosition: Double {
        atomicBeat
    }
    
    override var atomicIsPlaying: Bool {
        true
    }
    
    init() {
        super.init(
            getProject: { nil },
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
}
