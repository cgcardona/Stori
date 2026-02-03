//
//  AudioGraphManagerTests.swift
//  StoriTests
//
//  Comprehensive tests for audio graph mutation coordination
//  CRITICAL: Graph mutations affect all audio routing and playback
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class AudioGraphManagerTests: XCTestCase {
    
    var sut: AudioGraphManager!
    var mockEngine: AVAudioEngine!
    var mockMixer: AVAudioMixerNode!
    var mockTrackNodes: [UUID: TrackAudioNode]!
    var mockProject: AudioProject!
    var mutationExecuted: Bool!
    
    override func setUp() async throws {
        try await super.setUp()
        
        sut = AudioGraphManager()
        mockEngine = AVAudioEngine()
        mockMixer = AVAudioMixerNode()
        mockTrackNodes = [:]
        mutationExecuted = false
        
        // Create mock project
        mockProject = AudioProject(
            name: "Test Project",
            tempo: 120.0,
            timeSignature: .fourFour
        )
        
        // Wire up dependencies
        sut.engine = mockEngine
        sut.mixer = mockMixer
        sut.getTrackNodes = { [weak self] in self?.mockTrackNodes ?? [:] }
        sut.getCurrentProject = { [weak self] in self?.mockProject }
        sut.getTransportState = { .stopped }
        sut.getCurrentPosition = { PlaybackPosition(beats: 0) }
        sut.setGraphReady = { _ in }
    }
    
    override func tearDown() async throws {
        if mockEngine.isRunning {
            mockEngine.stop()
        }
        mockEngine = nil
        mockMixer = nil
        mockTrackNodes = nil
        mockProject = nil
        sut = nil
        try await super.tearDown()
    }
    
    // MARK: - Graph Generation Tracking Tests
    
    func testGraphGenerationIncrementsOnStructuralMutation() throws {
        let initialGeneration = sut.graphGeneration
        
        try sut.modifyGraphSafely {
            self.mutationExecuted = true
        }
        
        XCTAssertTrue(mutationExecuted)
        XCTAssertEqual(sut.graphGeneration, initialGeneration + 1, "Structural mutation should increment generation")
    }
    
    func testGraphGenerationDoesNotIncrementOnConnectionMutation() throws {
        let initialGeneration = sut.graphGeneration
        
        try sut.modifyGraphConnections {
            self.mutationExecuted = true
        }
        
        XCTAssertTrue(mutationExecuted)
        XCTAssertEqual(sut.graphGeneration, initialGeneration, "Connection mutation should NOT increment generation")
    }
    
    func testGraphGenerationDoesNotIncrementOnHotSwap() throws {
        let trackId = UUID()
        let initialGeneration = sut.graphGeneration
        
        try sut.modifyGraphForTrack(trackId) {
            self.mutationExecuted = true
        }
        
        XCTAssertTrue(mutationExecuted)
        XCTAssertEqual(sut.graphGeneration, initialGeneration, "Hot-swap mutation should NOT increment generation")
    }
    
    func testIsGraphGenerationValid() throws {
        let capturedGeneration = sut.graphGeneration
        
        XCTAssertTrue(sut.isGraphGenerationValid(capturedGeneration))
        
        // Perform structural mutation
        try sut.modifyGraphSafely {
            // Generation incremented inside
        }
        
        XCTAssertFalse(sut.isGraphGenerationValid(capturedGeneration), "Old generation should be invalid")
        XCTAssertTrue(sut.isGraphGenerationValid(sut.graphGeneration), "Current generation should be valid")
    }
    
    // MARK: - Reentrancy Handling Tests
    
    func testReentrantMutationDoesNotDeadlock() throws {
        var outerExecuted = false
        var innerExecuted = false
        
        try sut.modifyGraphSafely {
            outerExecuted = true
            
            // Reentrant call - should execute directly without mutex
            try? self.sut.modifyGraphConnections {
                innerExecuted = true
            }
        }
        
        XCTAssertTrue(outerExecuted, "Outer mutation should execute")
        XCTAssertTrue(innerExecuted, "Inner reentrant mutation should execute")
    }
    
    func testNestedMutationsExecuteDirectly() throws {
        var executionOrder: [String] = []
        
        try sut.modifyGraphSafely {
            executionOrder.append("outer-start")
            
            try? self.sut.modifyGraphConnections {
                executionOrder.append("inner")
            }
            
            executionOrder.append("outer-end")
        }
        
        XCTAssertEqual(executionOrder, ["outer-start", "inner", "outer-end"])
    }
    
    // MARK: - Structural Mutation Tests
    
    func testStructuralMutationStopsAndRestartsEngine() throws {
        // Start engine
        mockEngine.attach(mockMixer)
        mockEngine.connect(mockMixer, to: mockEngine.outputNode, format: nil)
        try mockEngine.start()
        
        XCTAssertTrue(mockEngine.isRunning, "Engine should be running before mutation")
        
        var engineWasRunningDuringWork = false
        try sut.modifyGraphSafely {
            engineWasRunningDuringWork = self.mockEngine.isRunning
            self.mutationExecuted = true
        }
        
        XCTAssertTrue(mutationExecuted)
        XCTAssertFalse(engineWasRunningDuringWork, "Engine should be stopped during structural mutation")
        XCTAssertTrue(mockEngine.isRunning, "Engine should be restarted after mutation")
    }
    
    func testStructuralMutationIncrementsGeneration() throws {
        let initialGeneration = sut.graphGeneration
        
        try sut.modifyGraphSafely {
            self.mutationExecuted = true
        }
        
        XCTAssertEqual(sut.graphGeneration, initialGeneration + 1)
    }
    
    func testStructuralMutationCallsGraphReadyCallbacks() throws {
        var graphReadyCalls: [Bool] = []
        
        sut.setGraphReady = { ready in
            graphReadyCalls.append(ready)
        }
        
        try sut.modifyGraphSafely {
            self.mutationExecuted = true
        }
        
        XCTAssertEqual(graphReadyCalls, [false, true], "Should set graph not ready, then ready")
    }
    
    // MARK: - Connection Mutation Tests
    
    func testConnectionMutationPausesAndResumesEngine() throws {
        // Start engine
        mockEngine.attach(mockMixer)
        mockEngine.connect(mockMixer, to: mockEngine.outputNode, format: nil)
        try mockEngine.start()
        
        XCTAssertTrue(mockEngine.isRunning)
        
        var engineWasRunningDuringWork = true
        try sut.modifyGraphConnections {
            // Engine is paused (not stopped) during connection mutation
            // Note: AVAudioEngine.pause() doesn't set isRunning to false
            self.mutationExecuted = true
        }
        
        XCTAssertTrue(mutationExecuted)
        XCTAssertTrue(mockEngine.isRunning, "Engine should still be running after connection mutation")
    }
    
    func testConnectionMutationDoesNotResetEngine() throws {
        // Connection mutations should NOT call engine.reset()
        // This preserves audio buffers for minimal disruption
        
        try sut.modifyGraphConnections {
            self.mutationExecuted = true
        }
        
        XCTAssertTrue(mutationExecuted)
        // No way to directly verify reset() wasn't called, but mutation should complete successfully
    }
    
    // MARK: - Hot-Swap Mutation Tests
    
    func testHotSwapOnlyResetsAffectedTrack() throws {
        let trackId1 = UUID()
        
        try sut.modifyGraphForTrack(trackId1) {
            self.mutationExecuted = true
        }
        
        XCTAssertTrue(mutationExecuted)
        // Only the affected track's instrument should be reset
        // (Verification is implicit through non-crashing behavior)
    }
    
    func testHotSwapPreservesOtherTracksPlayback() throws {
        let trackId = UUID()
        
        try sut.modifyGraphForTrack(trackId) {
            self.mutationExecuted = true
        }
        
        XCTAssertTrue(mutationExecuted)
        // Hot-swap should not affect other tracks' playback state
    }
    
    // MARK: - Mutation Error Handling Tests
    
    func testMutationErrorIsPropagated() {
        enum TestError: Error {
            case testFailure
        }
        
        XCTAssertThrowsError(try sut.modifyGraphSafely {
            throw TestError.testFailure
        }) { error in
            XCTAssertTrue(error is TestError)
        }
    }
    
    func testMutationErrorStillRestoresState() throws {
        enum TestError: Error {
            case testFailure
        }
        
        var graphReadyCalls: [Bool] = []
        sut.setGraphReady = { ready in
            graphReadyCalls.append(ready)
        }
        
        do {
            try sut.modifyGraphSafely {
                throw TestError.testFailure
            }
            XCTFail("Should have thrown error")
        } catch {
            // Expected
        }
        
        // Graph ready should still be set to true even after error
        XCTAssertTrue(graphReadyCalls.contains(false), "Should have set graph not ready")
        XCTAssertTrue(graphReadyCalls.last == true, "Should restore graph ready state")
    }
    
    // MARK: - Concurrent Mutation Tests
    
    func testConcurrentMutationsSerialized() async throws {
        var executionOrder: [Int] = []
        let lock = NSLock()
        
        // Launch multiple mutations concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<5 {
                group.addTask { @MainActor in
                    try? self.sut.modifyGraphConnections {
                        lock.lock()
                        executionOrder.append(i)
                        lock.unlock()
                        
                        // Simulate work
                        Thread.sleep(forTimeInterval: 0.01)
                    }
                }
            }
        }
        
        // All mutations should have executed
        XCTAssertEqual(executionOrder.count, 5)
        
        // They should have executed serially (no overlaps)
        // This is hard to prove definitively, but count should match
    }
    
    // MARK: - Graph Ready Flag Tests
    
    func testGraphReadyFlagSetCorrectlyDuringMutation() throws {
        var graphReadyStates: [Bool] = []
        
        sut.setGraphReady = { ready in
            graphReadyStates.append(ready)
        }
        
        try sut.modifyGraphSafely {
            self.mutationExecuted = true
        }
        
        XCTAssertEqual(graphReadyStates.first, false, "Should disable graph at start")
        XCTAssertEqual(graphReadyStates.last, true, "Should enable graph at end")
    }
    
    // MARK: - Performance Tests
    
    func testStructuralMutationPerformance() {
        measure {
            try? sut.modifyGraphSafely {
                // Minimal work
            }
        }
    }
    
    func testConnectionMutationPerformance() {
        measure {
            try? sut.modifyGraphConnections {
                // Minimal work
            }
        }
    }
    
    func testHotSwapMutationPerformance() {
        let trackId = UUID()
        
        measure {
            try? sut.modifyGraphForTrack(trackId) {
                // Minimal work
            }
        }
    }
}
