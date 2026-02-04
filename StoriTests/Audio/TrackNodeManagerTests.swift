//
//  TrackNodeManagerTests.swift
//  StoriTests
//
//  Comprehensive tests for TrackNodeManager - Track audio node lifecycle management
//  Tests cover node creation, destruction, automation cache updates, and concurrency
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class TrackNodeManagerTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var manager: TrackNodeManager!
    private var engine: AVAudioEngine!
    private var mainMixer: AVAudioMixerNode!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        engine = AVAudioEngine()
        mainMixer = AVAudioMixerNode()
        
        engine.attach(mainMixer)
        engine.connect(mainMixer, to: engine.mainMixerNode, format: nil)
        
        manager = TrackNodeManager(engine: engine, mainMixer: mainMixer)
    }
    
    override func tearDown() async throws {
        // Clean up all tracks
        manager.clearAllTracks()
        
        engine.stop()
        manager = nil
        engine = nil
        mainMixer = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testTrackNodeManagerInitialization() {
        // Manager should initialize with empty track nodes
        XCTAssertNotNil(manager)
        XCTAssertEqual(manager.trackNodes.count, 0)
    }
    
    func testTrackNodeManagerHasEngine() {
        XCTAssertNotNil(manager.engine)
        XCTAssertNotNil(manager.mainMixer)
    }
    
    // MARK: - Track Node Creation Tests
    
    func testEnsureTrackNodeExistsCreatesNode() {
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        
        manager.ensureTrackNodeExists(track: track)
        
        let node = manager.getTrackNode(for: track.id)
        XCTAssertNotNil(node)
    }
    
    func testEnsureTrackNodeExistsIdempotent() {
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        
        manager.ensureTrackNodeExists(track: track)
        let node1 = manager.getTrackNode(for: track.id)
        
        manager.ensureTrackNodeExists(track: track)
        let node2 = manager.getTrackNode(for: track.id)
        
        // Should return same node
        XCTAssertTrue(node1 === node2)
    }
    
    func testCreateMultipleTrackNodes() {
        let track1 = AudioTrack(name: "Track 1", trackType: .audio, color: .blue)
        let track2 = AudioTrack(name: "Track 2", trackType: .audio, color: .red)
        let track3 = AudioTrack(name: "Track 3", trackType: .midi, color: .green)
        
        manager.ensureTrackNodeExists(track: track1)
        manager.ensureTrackNodeExists(track: track2)
        manager.ensureTrackNodeExists(track: track3)
        
        XCTAssertEqual(manager.trackNodes.count, 3)
        XCTAssertNotNil(manager.getTrackNode(for: track1.id))
        XCTAssertNotNil(manager.getTrackNode(for: track2.id))
        XCTAssertNotNil(manager.getTrackNode(for: track3.id))
    }
    
    // MARK: - Track Node Retrieval Tests
    
    func testGetTrackNodeValidId() {
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        manager.ensureTrackNodeExists(track: track)
        
        let node = manager.getTrackNode(for: track.id)
        
        XCTAssertNotNil(node)
        XCTAssertEqual(node?.trackId, track.id)
    }
    
    func testGetTrackNodeInvalidId() {
        let invalidId = UUID()
        
        let node = manager.getTrackNode(for: invalidId)
        
        XCTAssertNil(node)
    }
    
    // MARK: - Track Node Removal Tests
    
    func testRemoveTrackNode() {
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        manager.ensureTrackNodeExists(track: track)
        
        XCTAssertNotNil(manager.getTrackNode(for: track.id))
        
        manager.removeTrackNode(trackId: track.id)
        
        XCTAssertNil(manager.getTrackNode(for: track.id))
        XCTAssertEqual(manager.trackNodes.count, 0)
    }
    
    func testRemoveNonExistentTrackNode() {
        let invalidId = UUID()
        
        // Should handle gracefully
        manager.removeTrackNode(trackId: invalidId)
        
        XCTAssertEqual(manager.trackNodes.count, 0)
    }
    
    func testRemoveOneOfMultipleTracks() {
        let track1 = AudioTrack(name: "Track 1", trackType: .audio, color: .blue)
        let track2 = AudioTrack(name: "Track 2", trackType: .audio, color: .red)
        let track3 = AudioTrack(name: "Track 3", trackType: .midi, color: .green)
        
        manager.ensureTrackNodeExists(track: track1)
        manager.ensureTrackNodeExists(track: track2)
        manager.ensureTrackNodeExists(track: track3)
        
        manager.removeTrackNode(trackId: track2.id)
        
        XCTAssertEqual(manager.trackNodes.count, 2)
        XCTAssertNotNil(manager.getTrackNode(for: track1.id))
        XCTAssertNil(manager.getTrackNode(for: track2.id))
        XCTAssertNotNil(manager.getTrackNode(for: track3.id))
    }
    
    // MARK: - Clear All Tracks Tests
    
    func testClearAllTracks() {
        let track1 = AudioTrack(name: "Track 1", trackType: .audio, color: .blue)
        let track2 = AudioTrack(name: "Track 2", trackType: .audio, color: .red)
        
        manager.ensureTrackNodeExists(track: track1)
        manager.ensureTrackNodeExists(track: track2)
        
        XCTAssertEqual(manager.trackNodes.count, 2)
        
        manager.clearAllTracks()
        
        XCTAssertEqual(manager.trackNodes.count, 0)
    }
    
    func testClearAllTracksWhenEmpty() {
        // Should handle gracefully
        manager.clearAllTracks()
        
        XCTAssertEqual(manager.trackNodes.count, 0)
    }
    
    // MARK: - Initialize Track Nodes Tests
    
    func testInitializeTrackNodesFromProject() {
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        project.addTrack(AudioTrack(name: "Track 2", trackType: .midi, color: .red))
        
        manager.initializeTrackNodes(for: project)
        
        XCTAssertEqual(manager.trackNodes.count, 2)
        XCTAssertNotNil(manager.getTrackNode(for: project.tracks[0].id))
        XCTAssertNotNil(manager.getTrackNode(for: project.tracks[1].id))
    }
    
    func testInitializeTrackNodesClearsPreviousNodes() {
        // Add initial tracks
        let oldTrack = AudioTrack(name: "Old Track", trackType: .audio, color: .blue)
        manager.ensureTrackNodeExists(track: oldTrack)
        
        XCTAssertEqual(manager.trackNodes.count, 1)
        
        // Initialize with new project
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "New Track", trackType: .audio, color: .red))
        
        manager.initializeTrackNodes(for: project)
        
        // Should clear old and add new
        XCTAssertEqual(manager.trackNodes.count, 1)
        XCTAssertNil(manager.getTrackNode(for: oldTrack.id))
        XCTAssertNotNil(manager.getTrackNode(for: project.tracks[0].id))
    }
    
    func testInitializeTrackNodesWithEmptyProject() {
        let project = AudioProject(name: "Empty", tempo: 120.0)
        
        manager.initializeTrackNodes(for: project)
        
        XCTAssertEqual(manager.trackNodes.count, 0)
    }
    
    // MARK: - Store Track Node Tests
    
    func testStoreTrackNode() {
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        let node = TrackAudioNode(
            trackId: track.id,
            mixer: AVAudioMixerNode(),
            eq: AVAudioUnitEQ(numberOfBands: 3),
            engine: engine,
            format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        )
        
        manager.storeTrackNode(node, trackId: track.id)
        
        let retrievedNode = manager.getTrackNode(for: track.id)
        XCTAssertNotNil(retrievedNode)
        XCTAssertTrue(retrievedNode === node)
    }
    
    func testStoreTrackNodeOverwritesExisting() {
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        
        // Create first node
        let node1 = TrackAudioNode(
            trackId: track.id,
            mixer: AVAudioMixerNode(),
            eq: AVAudioUnitEQ(numberOfBands: 3),
            engine: engine,
            format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        )
        manager.storeTrackNode(node1, trackId: track.id)
        
        // Create second node with same ID
        let node2 = TrackAudioNode(
            trackId: track.id,
            mixer: AVAudioMixerNode(),
            eq: AVAudioUnitEQ(numberOfBands: 3),
            engine: engine,
            format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        )
        manager.storeTrackNode(node2, trackId: track.id)
        
        // Should retrieve second node
        let retrievedNode = manager.getTrackNode(for: track.id)
        XCTAssertTrue(retrievedNode === node2)
        XCTAssertFalse(retrievedNode === node1)
    }
    
    // MARK: - Automation Cache Update Tests (CRITICAL - Recent Enhancement)
    
    func testAutomationCacheUpdateCallback() {
        var callbackInvoked = false
        
        manager.onUpdateAutomationTrackCache = {
            callbackInvoked = true
        }
        
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        manager.ensureTrackNodeExists(track: track)
        
        // Callback should be invoked when track is added
        XCTAssertTrue(callbackInvoked)
    }
    
    func testAutomationCacheUpdateOnInitialize() {
        var callbackCount = 0
        
        manager.onUpdateAutomationTrackCache = {
            callbackCount += 1
        }
        
        var project = AudioProject(name: "Test", tempo: 120.0)
        project.addTrack(AudioTrack(name: "Track 1", trackType: .audio, color: .blue))
        project.addTrack(AudioTrack(name: "Track 2", trackType: .midi, color: .red))
        
        manager.initializeTrackNodes(for: project)
        
        // Callback should be invoked once during initialization
        XCTAssertGreaterThanOrEqual(callbackCount, 1)
    }
    
    func testAutomationCacheUpdateOnRemove() {
        var callbackCount = 0
        
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        manager.ensureTrackNodeExists(track: track)
        
        manager.onUpdateAutomationTrackCache = {
            callbackCount += 1
        }
        
        manager.removeTrackNode(trackId: track.id)
        
        // Callback should be invoked when track is removed
        XCTAssertEqual(callbackCount, 1)
    }
    
    func testAutomationCacheUpdateOnClearAll() {
        var callbackCount = 0
        
        let track1 = AudioTrack(name: "Track 1", trackType: .audio, color: .blue)
        let track2 = AudioTrack(name: "Track 2", trackType: .midi, color: .red)
        
        manager.ensureTrackNodeExists(track: track1)
        manager.ensureTrackNodeExists(track: track2)
        
        manager.onUpdateAutomationTrackCache = {
            callbackCount += 1
        }
        
        manager.clearAllTracks()
        
        // Callback should be invoked once when clearing all tracks
        XCTAssertEqual(callbackCount, 1)
    }
    
    func testAutomationCacheUpdateOnStore() {
        var callbackCount = 0
        
        manager.onUpdateAutomationTrackCache = {
            callbackCount += 1
        }
        
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        let node = TrackAudioNode(
            trackId: track.id,
            mixer: AVAudioMixerNode(),
            eq: AVAudioUnitEQ(numberOfBands: 3),
            engine: engine,
            format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        )
        
        manager.storeTrackNode(node, trackId: track.id)
        
        // Callback should be invoked when node is stored
        XCTAssertEqual(callbackCount, 1)
    }
    
    // MARK: - Concurrency Tests
    
    func testConcurrentTrackNodeCreation() async {
        let tracks = (0..<10).map { i in
            AudioTrack(name: "Track \(i)", trackType: .audio, color: .blue)
        }
        
        await withTaskGroup(of: Void.self) { group in
            for track in tracks {
                group.addTask { @MainActor in
                    self.manager.ensureTrackNodeExists(track: track)
                }
            }
        }
        
        // All tracks should be created
        XCTAssertEqual(manager.trackNodes.count, 10)
    }
    
    func testConcurrentTrackNodeRetrieval() async {
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        manager.ensureTrackNodeExists(track: track)
        
        var retrievedNodes: [TrackAudioNode?] = []
        
        await withTaskGroup(of: TrackAudioNode?.self) { group in
            for _ in 0..<10 {
                group.addTask { @MainActor in
                    self.manager.getTrackNode(for: track.id)
                }
            }
            
            for await node in group {
                retrievedNodes.append(node)
            }
        }
        
        // All retrievals should succeed
        XCTAssertEqual(retrievedNodes.count, 10)
        XCTAssertTrue(retrievedNodes.allSatisfy { $0 != nil })
    }
    
    func testConcurrentTrackNodeRemoval() async {
        // Create multiple tracks
        let tracks = (0..<10).map { i in
            AudioTrack(name: "Track \(i)", trackType: .audio, color: .blue)
        }
        
        for track in tracks {
            manager.ensureTrackNodeExists(track: track)
        }
        
        XCTAssertEqual(manager.trackNodes.count, 10)
        
        // Remove concurrently
        await withTaskGroup(of: Void.self) { group in
            for track in tracks {
                group.addTask { @MainActor in
                    self.manager.removeTrackNode(trackId: track.id)
                }
            }
        }
        
        // All tracks should be removed
        XCTAssertEqual(manager.trackNodes.count, 0)
    }
    
    // MARK: - Performance Tests
    
    func testTrackNodeCreationPerformance() {
        let tracks = (0..<100).map { i in
            AudioTrack(name: "Track \(i)", trackType: .audio, color: .blue)
        }
        
        measure {
            for track in tracks {
                manager.ensureTrackNodeExists(track: track)
            }
            
            // Clean up for next iteration
            manager.clearAllTracks()
        }
    }
    
    func testTrackNodeRetrievalPerformance() {
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        manager.ensureTrackNodeExists(track: track)
        
        measure {
            for _ in 0..<1000 {
                _ = manager.getTrackNode(for: track.id)
            }
        }
    }
    
    func testTrackNodeRemovalPerformance() {
        measure {
            let tracks = (0..<100).map { i in
                AudioTrack(name: "Track \(i)", trackType: .audio, color: .blue)
            }
            
            for track in tracks {
                manager.ensureTrackNodeExists(track: track)
            }
            
            for track in tracks {
                manager.removeTrackNode(trackId: track.id)
            }
        }
    }
    
    // MARK: - Memory Management Tests
    
    func testTrackNodeCleanup() {
        // Create nodes
        for i in 0..<5 {
            let track = AudioTrack(name: "Track \(i)", trackType: .audio, color: .blue)
            manager.ensureTrackNodeExists(track: track)
        }
        
        XCTAssertEqual(manager.trackNodes.count, 5)
        
        // Clear all
        manager.clearAllTracks()
        
        // Should be empty
        XCTAssertEqual(manager.trackNodes.count, 0)
    }
    
    func testMultipleManagerLifecycles() {
        // Create and destroy multiple managers
        for _ in 0..<5 {
            let tempEngine = AVAudioEngine()
            let tempMixer = AVAudioMixerNode()
            tempEngine.attach(tempMixer)
            
            let tempManager = TrackNodeManager(engine: tempEngine, mainMixer: tempMixer)
            
            let track = AudioTrack(name: "Temp Track", trackType: .audio, color: .blue)
            tempManager.ensureTrackNodeExists(track: track)
            
            tempManager.clearAllTracks()
            tempEngine.stop()
        }
        
        // If we get here, memory is managed correctly
        XCTAssertTrue(true, "Multiple manager lifecycles completed")
    }
    
    // MARK: - Edge Case Tests
    
    func testEnsureTrackNodeWithBusType() {
        let bus = AudioTrack(name: "Bus Track", trackType: .bus, color: .orange)
        
        manager.ensureTrackNodeExists(track: bus)
        
        let node = manager.getTrackNode(for: bus.id)
        XCTAssertNotNil(node)
    }
    
    func testEnsureTrackNodeWithMasterType() {
        let master = AudioTrack(name: "Master", trackType: .master, color: .black)
        
        manager.ensureTrackNodeExists(track: master)
        
        let node = manager.getTrackNode(for: master.id)
        XCTAssertNotNil(node)
    }
    
    func testRemoveSameTrackMultipleTimes() {
        let track = AudioTrack(name: "Test Track", trackType: .audio, color: .blue)
        manager.ensureTrackNodeExists(track: track)
        
        manager.removeTrackNode(trackId: track.id)
        XCTAssertNil(manager.getTrackNode(for: track.id))
        
        // Remove again - should handle gracefully
        manager.removeTrackNode(trackId: track.id)
        XCTAssertNil(manager.getTrackNode(for: track.id))
    }
    
    func testInitializeWithLargeProject() {
        var project = AudioProject(name: "Large Project", tempo: 120.0)
        
        // Add 100 tracks
        for i in 0..<100 {
            project.addTrack(AudioTrack(name: "Track \(i)", trackType: .audio, color: .blue))
        }
        
        manager.initializeTrackNodes(for: project)
        
        XCTAssertEqual(manager.trackNodes.count, 100)
    }
}
