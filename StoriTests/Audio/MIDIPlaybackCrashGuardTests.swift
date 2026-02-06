//
//  MIDIPlaybackCrashGuardTests.swift
//  StoriTests
//
//  Tests for crash guards added to prevent the MIDI playback crash
//  when a user creates a new project, adds a MIDI track with a GM instrument,
//  enables the metronome, and presses play.
//
//  Guards tested:
//  1. SamplerEngine.midiEventBlock - guards against accessing scheduleMIDIEventBlock
//     on uninitialized/detached samplers
//  2. MetronomeEngine.startPlaying() - guards against player.stop()/play() on
//     detached nodes during graph mutations
//  3. ObjC exception bridge - converts NSException to Swift Error
//

import XCTest
@testable import Stori
import AVFoundation

// MARK: - SamplerEngine MIDI Block Safety Tests

final class SamplerEngineMIDIBlockSafetyTests: XCTestCase {
    
    private var engine: AVAudioEngine!
    
    override func setUp() async throws {
        try await super.setUp()
        engine = AVAudioEngine()
    }
    
    override func tearDown() async throws {
        engine?.stop()
        engine = nil
        try await super.tearDown()
    }
    
    // MARK: - midiEventBlock guard: isReady
    
    func testMIDIBlockReturnsNilWhenNotReady() {
        // Sampler created but no SoundFont loaded → isReady == false
        let sampler = SamplerEngine(attachTo: engine)
        XCTAssertFalse(sampler.isReady, "Sampler should not be ready without SoundFont")
        XCTAssertNil(sampler.midiEventBlock, "MIDI block must be nil when sampler is not ready")
    }
    
    // MARK: - midiEventBlock guard: sampler.engine != nil
    
    func testMIDIBlockReturnsNilWhenDetachedFromEngine() {
        // Create a sampler with deferred attachment — never attach
        let sampler = SamplerEngine(attachTo: engine, deferAttachment: true)
        XCTAssertNil(sampler.midiEventBlock, "MIDI block must be nil when sampler is detached")
    }
    
    // MARK: - sendMIDI gracefully handles nil block
    
    func testSendMIDIDoesNotCrashWithoutSoundFont() {
        let sampler = SamplerEngine(attachTo: engine)
        // Should fall through to the non-block path without crashing
        sampler.sendMIDI(status: 0x90, data1: 60, data2: 100)
        sampler.sendMIDI(status: 0x80, data1: 60, data2: 0)
        // If we get here without a crash, the guard worked
    }
    
    // MARK: - fullRenderReset with ObjC exception safety
    
    func testFullRenderResetDoesNotCrash() {
        let sampler = SamplerEngine(attachTo: engine)
        // Reset on an unloaded sampler should not crash
        sampler.fullRenderReset()
        // If we get here, the ObjC exception wrapper worked
    }
    
    // MARK: - noteOn guard (pre-existing isReady check)
    
    func testNoteOnGuardedByIsReady() {
        let sampler = SamplerEngine(attachTo: engine)
        XCTAssertFalse(sampler.isReady)
        // Should silently return without crashing
        sampler.noteOn(pitch: 60, velocity: 127)
    }
}

// MARK: - MetronomeEngine Safety Tests

@MainActor
final class MetronomeEngineSafetyTests: XCTestCase {
    
    private var metronome: MetronomeEngine!
    private var engine: AVAudioEngine!
    private var mixer: AVAudioMixerNode!
    private var mockAudioEngine: AudioEngine!
    private var mockTransportController: TransportController!
    
    override func setUp() async throws {
        try await super.setUp()
        metronome = MetronomeEngine()
        engine = AVAudioEngine()
        mixer = AVAudioMixerNode()
        mockAudioEngine = AudioEngine()
        
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
        engine?.stop()
        metronome = nil
        engine = nil
        mixer = nil
        mockAudioEngine = nil
        mockTransportController = nil
        try await super.tearDown()
    }
    
    // MARK: - onTransportPlay without installation
    
    func testTransportPlayWithoutInstallDoesNotCrash() {
        metronome.isEnabled = true
        // Not installed — onTransportPlay should silently return
        metronome.onTransportPlay()
        XCTAssertEqual(metronome.currentBeat, 1, "Beat should remain at default")
    }
    
    // MARK: - onTransportStop without installation
    
    func testTransportStopWithoutInstallDoesNotCrash() {
        metronome.onTransportStop()
        // Should not crash
    }
    
    // MARK: - preparePlayerNode without installation
    
    func testPreparePlayerNodeWithoutInstallDoesNotCrash() {
        metronome.preparePlayerNode()
        // Should silently return — no player node to prepare
    }
    
    // MARK: - Installed but engine not running
    
    func testTransportPlayWithEngineNotRunning() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        metronome.isEnabled = true
        
        // Engine not started — startPlaying should check engine.isRunning and bail
        metronome.onTransportPlay()
        // Should not crash
    }
    
    // MARK: - Installed and running, then stopped
    
    func testStopPlayingAfterEngineStopsDoesNotCrash() throws {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        
        metronome.install(
            into: engine,
            dawMixer: mixer,
            audioEngine: mockAudioEngine,
            transportController: mockTransportController
        )
        
        try engine.start()
        metronome.preparePlayerNode()
        metronome.isEnabled = true
        metronome.onTransportPlay()
        
        // Stop the engine while metronome is playing
        engine.stop()
        
        // Now stop the metronome — player node is detached from running engine
        metronome.onTransportStop()
        // Should not crash thanks to the player.engine != nil guard
    }
}

// MARK: - ObjC Exception Bridge Tests

final class ObjCExceptionBridgeTests: XCTestCase {
    
    func testTryObjCSuccessfulBlock() throws {
        var executed = false
        try tryObjC {
            executed = true
        }
        XCTAssertTrue(executed, "Block should have executed")
    }
    
    func testTryObjCResultSuccessfulBlock() {
        let result = tryObjCResult { () -> Int? in
            return 42
        }
        XCTAssertEqual(result, 42, "Should return the block's result")
    }
    
    func testTryObjCResultReturnsNilForNilBlock() {
        let result = tryObjCResult { () -> String? in
            return nil
        }
        XCTAssertNil(result, "Should return nil when block returns nil")
    }
    
    func testObjCExceptionErrorHasDescription() {
        let error = ObjCExceptionError(underlyingError: NSError(
            domain: "com.tellurstori.ObjCException",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Test exception"]
        ))
        XCTAssertEqual(error.localizedDescription, "Test exception")
    }
    
    func testTryObjCCatchesNSException() {
        // Use NSException.raise to trigger an ObjC exception
        XCTAssertThrowsError(try tryObjC {
            NSException(name: .internalInconsistencyException,
                       reason: "Test exception for unit test",
                       userInfo: nil).raise()
        }) { error in
            XCTAssertTrue(error is ObjCExceptionError,
                         "Error should be ObjCExceptionError, got \(type(of: error))")
            let objcError = error as! ObjCExceptionError
            XCTAssertTrue(objcError.localizedDescription.contains("NSInternalInconsistencyException"),
                         "Description should mention the exception name")
        }
    }
    
    func testTryObjCResultReturnsNilForNSException() {
        let result = tryObjCResult { () -> Int? in
            NSException(name: .genericException,
                       reason: "Test exception",
                       userInfo: nil).raise()
            return 42
        }
        XCTAssertNil(result, "Should return nil when ObjC exception is thrown")
    }
}
