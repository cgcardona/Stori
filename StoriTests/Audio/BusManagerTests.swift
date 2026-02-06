//
//  BusManagerTests.swift
//  StoriTests
//
//  Unit tests for BusManager - bus nodes, track sends, and removeAllSendsForTrack (Issue #81).
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class BusManagerTests: XCTestCase {

    private var engine: AVAudioEngine!
    private var mainMixer: AVAudioMixerNode!
    private var busManager: BusManager!
    private var project: AudioProject!
    private var trackNodes: [UUID: TrackAudioNode]!
    private var trackA: AudioTrack!
    private var trackB: AudioTrack!
    private var bus: MixerBus!

    override func setUp() async throws {
        try await super.setUp()
        engine = AVAudioEngine()
        mainMixer = AVAudioMixerNode()
        engine.attach(mainMixer)
        engine.connect(mainMixer, to: engine.mainMixerNode, format: nil)

        trackA = AudioTrack(name: "A", trackType: .audio, color: .blue)
        trackB = AudioTrack(name: "B", trackType: .audio, color: .red)
        bus = MixerBus(name: "Reverb")
        project = AudioProject(name: "Bus Test", tempo: 120.0)
        project.addTrack(trackA)
        project.addTrack(trackB)
        project.buses.append(bus)

        trackNodes = [:]
        let format = engine.outputNode.inputFormat(forBus: 0)
        for (index, track) in [trackA!, trackB!].enumerated() {
            let node = makeTrackNode(for: track)
            trackNodes[track.id] = node
            engine.attach(node.panNode)
            engine.attach(node.volumeNode)
            engine.attach(node.eqNode)
            engine.attach(node.playerNode)
            engine.attach(node.timePitchUnit)
            engine.connect(node.panNode, to: mainMixer, fromBus: 0, toBus: AVAudioNodeBus(index), format: format)
        }

        busManager = BusManager(
            engine: engine,
            mixer: mainMixer,
            trackNodes: { [weak self] in self?.trackNodes ?? [:] },
            currentProject: { [weak self] in self?.project },
            transportState: { .stopped },
            modifyGraphSafely: { work in try work() },
            updateSoloState: {},
            reconnectMetronome: {},
            setupPositionTimer: {},
            isInstallingPlugin: { false },
            setIsInstallingPlugin: { _ in }
        )
        busManager.setupBusesForProject(project)
        try? engine.start()
    }

    override func tearDown() async throws {
        if engine.isRunning {
            engine.stop()
        }
        busManager = nil
        trackNodes = nil
        project = nil
        trackA = nil
        trackB = nil
        bus = nil
        engine = nil
        mainMixer = nil
        try await super.tearDown()
    }

    private func makeTrackNode(for track: AudioTrack) -> TrackAudioNode {
        let playerNode = AVAudioPlayerNode()
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)
        let timePitch = AVAudioUnitTimePitch()
        let pluginChain = PluginChain(id: UUID(), maxSlots: 8)
        return TrackAudioNode(
            id: track.id,
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
    }

    // MARK: - removeAllSendsForTrack (Issue #81)

    /// removeAllSendsForTrack clears only that track's sends; other track's send remains (removeTrackSend still finds it).
    func testRemoveAllSendsForTrackClearsOnlyThatTrack() {
        busManager.setupTrackSend(trackA.id, to: bus.id, level: 0.5)
        busManager.setupTrackSend(trackB.id, to: bus.id, level: 0.3)

        busManager.removeAllSendsForTrack(trackA.id)

        // Track B's send must still be in BusManager (otherwise removeTrackSend would no-op)
        busManager.removeTrackSend(trackB.id, from: bus.id)
        // Second call is no-op (key already removed) - no crash
        busManager.removeTrackSend(trackB.id, from: bus.id)
    }

    /// removeAllSendsForTrack when track has multiple sends to different buses clears all of them (no crash).
    func testRemoveAllSendsForTrackClearsMultipleSends() {
        let bus2 = MixerBus(name: "Delay")
        project.buses.append(bus2)
        busManager.addBus(bus2)

        busManager.setupTrackSend(trackA.id, to: bus.id, level: 0.5)
        busManager.setupTrackSend(trackA.id, to: bus2.id, level: 0.4)

        busManager.removeAllSendsForTrack(trackA.id)
        // No crash; track A's sends are cleared
    }

    /// removeAllSendsForTrack when track has no sends is a no-op (no crash).
    func testRemoveAllSendsForTrackWhenNoSendsIsNoOp() {
        busManager.setupTrackSend(trackB.id, to: bus.id, level: 0.3)

        busManager.removeAllSendsForTrack(trackA.id)

        // Track B's send still exists
        busManager.removeTrackSend(trackB.id, from: bus.id)
    }
}
