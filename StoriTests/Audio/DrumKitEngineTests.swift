//
//  DrumKitEngineTests.swift
//  StoriTests
//
//  Unit tests for DrumKitEngine - attach/detach (Issue #81), playback, and kit loading.
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class DrumKitEngineTests: XCTestCase {

    private var engine: AVAudioEngine!
    private var drumKit: DrumKitEngine!

    override func setUp() async throws {
        try await super.setUp()
        engine = AVAudioEngine()
        drumKit = DrumKitEngine()
    }

    override func tearDown() async throws {
        drumKit.detach()
        if engine.isRunning {
            engine.stop()
        }
        drumKit = nil
        engine = nil
        try await super.tearDown()
    }

    // MARK: - Attach / Detach (Issue #81)

    /// attach then detach must not crash; detach disconnects before detach to avoid graph corruption.
    func testAttachThenDetachNoCrash() {
        drumKit.attach(to: engine, connectToMixer: true)
        XCTAssertTrue(drumKit.isReady)

        drumKit.detach()

        XCTAssertFalse(drumKit.isReady)
    }

    /// detach when not attached is a no-op (no crash).
    func testDetachWhenNotAttachedIsNoOp() {
        drumKit.detach()
        XCTAssertFalse(drumKit.isReady)
    }

    /// attach, detach, attach again (reuse) must not crash.
    func testDetachThenReattach() {
        drumKit.attach(to: engine, connectToMixer: true)
        drumKit.detach()
        drumKit.attach(to: engine, connectToMixer: false)
        XCTAssertTrue(drumKit.isReady)
        drumKit.detach()
    }
}
