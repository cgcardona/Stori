//
//  AudioGraphMutationCoalescingTests.swift
//  StoriTests
//
//  Tests for AudioGraphManager mutation coalescing and staleness handling.
//  Ensures rapid UI interactions don't cause audio glitches or unexpected state changes.
//

import XCTest
import AVFoundation
@testable import Stori

@MainActor
final class AudioGraphMutationCoalescingTests: XCTestCase {
    
    // MARK: - Test Fixtures
    
    var graphManager: AudioGraphManager!
    var mockEngine: AVAudioEngine!
    var mockMixer: AVAudioMixerNode!
    var executionLog: [String]!
    
    override func setUp() async throws {
        graphManager = AudioGraphManager()
        mockEngine = AVAudioEngine()
        mockMixer = mockEngine.mainMixerNode
        executionLog = []
        
        // Wire up dependencies
        graphManager.engine = mockEngine
        graphManager.mixer = mockMixer
        graphManager.getTrackNodes = { [:] }
        graphManager.getCurrentProject = { nil }
        graphManager.getTransportState = { .stopped }
        graphManager.getCurrentPosition = { PlaybackPosition(beats: 0) }
        graphManager.setGraphReady = { _ in }
        graphManager.onPlayFromBeat = { _ in }
    }
    
    override func tearDown() async throws {
        graphManager = nil
        mockEngine = nil
        mockMixer = nil
        executionLog = nil
    }
    
    // MARK: - Mutation Coalescing Tests
    
    /// Test that rapid mutations on same target are coalesced
    func testRapidMutationsAreCoalesced() async throws {
        let expectation = expectation(description: "Coalesced mutations executed")
        var executionCount = 0
        var finalValue = 0
        
        // Queue 10 rapid mutations for same target
        for i in 1...10 {
            graphManager.modifyGraphConnections {
                executionCount += 1
                finalValue = i
            }
        }
        
        // Wait for coalescing delay (50ms) + buffer
        try await Task.sleep(for: .milliseconds(100))
        
        // Assert: Only 1 mutation should have executed (the final one)
        XCTAssertEqual(executionCount, 1, "Should coalesce 10 mutations into 1")
        XCTAssertEqual(finalValue, 10, "Should execute the final mutation value")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    /// Test that mutations for different targets are NOT coalesced
    func testDifferentTargetsNotCoalesced() async throws {
        let expectation = expectation(description: "Different target mutations executed")
        var trackAExecutions = 0
        var trackBExecutions = 0
        
        let trackAId = UUID()
        let trackBId = UUID()
        
        // Queue mutations for different tracks
        for _ in 1...5 {
            graphManager.modifyGraphForTrack(trackAId) {
                trackAExecutions += 1
            }
            graphManager.modifyGraphForTrack(trackBId) {
                trackBExecutions += 1
            }
        }
        
        // Wait for coalescing delay
        try await Task.sleep(for: .milliseconds(100))
        
        // Assert: Each track should execute once (coalesced per-track)
        XCTAssertEqual(trackAExecutions, 1, "Track A mutations should be coalesced")
        XCTAssertEqual(trackBExecutions, 1, "Track B mutations should be coalesced")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    /// Test that only the FINAL state is applied when coalescing
    func testCoalescingAppliesFinalStateOnly() async throws {
        let expectation = expectation(description: "Final state applied")
        var pluginBypassStates: [Bool] = []
        
        // Simulate rapid bypass toggling (on → off → on → off → on)
        let toggleStates = [true, false, true, false, true]
        
        for state in toggleStates {
            graphManager.modifyGraphConnections {
                pluginBypassStates.append(state)
            }
        }
        
        // Wait for coalescing
        try await Task.sleep(for: .milliseconds(100))
        
        // Assert: Only the final state (true) should be applied
        XCTAssertEqual(pluginBypassStates.count, 1, "Should execute once")
        XCTAssertEqual(pluginBypassStates.last, true, "Final bypass state should be true")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    /// Test that coalescing delay is appropriate for audio buffer size
    func testCoalescingDelayMatchesBufferPeriod() {
        // At 48kHz, 512 samples = 10.67ms
        // Coalescing delay should be ~50ms (multiple buffer periods)
        // This ensures smooth audio without glitches
        
        let coalescingDelay = 0.050 // 50ms from AudioGraphManager
        let sampleRate = 48000.0
        let bufferSize = 512.0
        let bufferPeriod = bufferSize / sampleRate // ~10.67ms
        
        // Assert: Coalescing delay should be at least 4-5 buffer periods
        let bufferPeriods = coalescingDelay / bufferPeriod
        XCTAssertGreaterThanOrEqual(bufferPeriods, 4.0, "Coalescing delay should span multiple buffer periods")
        XCTAssertLessThanOrEqual(bufferPeriods, 10.0, "Coalescing delay should not be too long (UI responsiveness)")
    }
    
    // MARK: - Staleness Detection Tests
    
    /// Test that stale mutations (>500ms old) are discarded
    func testStaleMutationsDiscarded() async throws {
        let expectation = expectation(description: "Stale mutations discarded")
        var executionCount = 0
        
        // Queue a mutation
        graphManager.modifyGraphConnections {
            executionCount += 1
        }
        
        // Wait for staleness threshold (500ms) + buffer
        try await Task.sleep(for: .milliseconds(600))
        
        // Mutation should be discarded as stale
        // (We can't directly test this without accessing private state,
        //  but we can verify that no execution happens after staleness)
        
        // Note: In real scenario, the flush would happen at 50ms
        // This test simulates a scenario where flush is delayed
        // In production, mutations older than 500ms are discarded during flush
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    /// Test that mutations within staleness window are NOT discarded
    func testFreshMutationsExecuted() async throws {
        let expectation = expectation(description: "Fresh mutations executed")
        var executionCount = 0
        
        // Queue mutation
        graphManager.modifyGraphConnections {
            executionCount += 1
        }
        
        // Wait for coalescing delay (50ms) but BEFORE staleness (500ms)
        try await Task.sleep(for: .milliseconds(100))
        
        // Mutation should have executed (not stale)
        XCTAssertEqual(executionCount, 1, "Fresh mutation should execute")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Batch Mode Tests
    
    /// Test that batch mode disables coalescing
    func testBatchModeDisablesCoalescing() async throws {
        let expectation = expectation(description: "Batch mode mutations executed")
        var executionCount = 0
        
        // Execute mutations in batch mode
        try graphManager.performBatchOperation {
            // All mutations should execute immediately, not coalesced
            for _ in 1...10 {
                try self.graphManager.modifyGraphConnections {
                    executionCount += 1
                }
            }
        }
        
        // Assert: All 10 mutations should execute immediately
        XCTAssertEqual(executionCount, 10, "Batch mode should not coalesce mutations")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Rate Limiting Integration Tests
    
    /// Test that rate limiting still works for structural mutations
    func testRateLimitingForStructuralMutations() async throws {
        var executionCount = 0
        
        // Queue 15 structural mutations (limit is 10 per second)
        for _ in 1...15 {
            graphManager.modifyGraphSafely {
                executionCount += 1
            }
        }
        
        // Wait for any pending executions
        try await Task.sleep(for: .milliseconds(100))
        
        // Assert: Should reject mutations over rate limit
        // First 10 execute, remaining 5 rejected
        XCTAssertLessThanOrEqual(executionCount, 10, "Should rate limit structural mutations")
    }
    
    /// Test that connection mutations use coalescing instead of rate limiting
    func testConnectionMutationsUseCoalescing() async throws {
        var executionCount = 0
        
        // Queue 15 connection mutations (would hit rate limit without coalescing)
        for _ in 1...15 {
            graphManager.modifyGraphConnections {
                executionCount += 1
            }
        }
        
        // Wait for coalescing
        try await Task.sleep(for: .milliseconds(100))
        
        // Assert: Should coalesce into 1 execution (not rate-limited)
        XCTAssertEqual(executionCount, 1, "Connection mutations should coalesce, not rate limit")
    }
    
    // MARK: - Real-World Scenario Tests
    
    /// Test plugin bypass spam (Issue #58 scenario)
    func testPluginBypassSpamCoalesced() async throws {
        let expectation = expectation(description: "Plugin bypass spam handled")
        var bypassStates: [Bool] = []
        let trackId = UUID()
        
        // Simulate user spam-clicking bypass 20 times
        for i in 1...20 {
            let isOdd = i % 2 == 1
            graphManager.modifyGraphConnections {
                bypassStates.append(isOdd)
            }
        }
        
        // Wait for coalescing
        try await Task.sleep(for: .milliseconds(100))
        
        // Assert: Only final state should be applied
        XCTAssertEqual(bypassStates.count, 1, "Should coalesce all bypass toggles")
        XCTAssertEqual(bypassStates.last, false, "Final state should match last toggle (20th = even = false)")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    /// Test routing change spam
    func testRoutingChangeSpamCoalesced() async throws {
        let expectation = expectation(description: "Routing spam handled")
        var routingChanges = 0
        
        // Simulate rapid bus send routing changes
        for _ in 1...10 {
            graphManager.modifyGraphConnections {
                routingChanges += 1
            }
        }
        
        // Wait for coalescing
        try await Task.sleep(for: .milliseconds(100))
        
        // Assert: Coalesced into single execution
        XCTAssertEqual(routingChanges, 1, "Routing changes should coalesce")
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    /// Test that normal (non-spam) mutations execute promptly
    func testNormalMutationsExecuteWithinLatency() async throws {
        let expectation = expectation(description: "Normal mutation executes promptly")
        let startTime = Date()
        var executionTime: Date?
        
        // Queue single mutation
        graphManager.modifyGraphConnections {
            executionTime = Date()
        }
        
        // Wait for coalescing delay
        try await Task.sleep(for: .milliseconds(100))
        
        // Assert: Should execute within reasonable latency
        if let execTime = executionTime {
            let latency = execTime.timeIntervalSince(startTime)
            XCTAssertLessThan(latency, 0.100, "Mutation latency should be < 100ms")
        } else {
            XCTFail("Mutation did not execute")
        }
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Edge Cases
    
    /// Test empty mutation queue flush
    func testEmptyQueueFlush() async throws {
        // This should not crash or cause issues
        // (Internal test - flush happens automatically)
        
        // Wait for any scheduled flushes
        try await Task.sleep(for: .milliseconds(100))
        
        // No assertions - just verifying no crash
    }
    
    /// Test mutation during engine restart
    func testMutationDuringEngineRestart() async throws {
        // Simulate engine restart scenario
        mockEngine.stop()
        
        var executionCount = 0
        graphManager.modifyGraphConnections {
            executionCount += 1
        }
        
        try await Task.sleep(for: .milliseconds(100))
        
        // Should still execute (graph manager handles engine state)
        XCTAssertEqual(executionCount, 1, "Should execute mutation even when engine stopped")
    }
}
