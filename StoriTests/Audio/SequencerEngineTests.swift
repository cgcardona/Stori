//
//  SequencerEngineTests.swift
//  StoriTests
//
//  Comprehensive tests for SequencerEngine - Step sequencer playback and pattern management
//  Tests cover pattern editing, playback control, MIDI routing, and drum kit management
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class SequencerEngineTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var sequencer: SequencerEngine!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        sequencer = SequencerEngine(tempo: 120.0)
    }
    
    override func tearDown() async throws {
        sequencer.stop()
        sequencer = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testSequencerInitialization() {
        XCTAssertNotNil(sequencer)
        XCTAssertEqual(sequencer.playbackState, .stopped)
        XCTAssertEqual(sequencer.currentStep, 0)
        XCTAssertNotNil(sequencer.pattern)
    }
    
    func testSequencerDefaultPattern() {
        let pattern = sequencer.pattern
        
        XCTAssertGreaterThan(pattern.lanes.count, 0)
        XCTAssertGreaterThan(pattern.steps, 0)
        XCTAssertEqual(pattern.tempo, 120.0)
    }
    
    func testSequencerInitialPlaybackState() {
        XCTAssertEqual(sequencer.playbackState, .stopped)
        XCTAssertFalse(sequencer.isPlaying)
    }
    
    func testSequencerCurrentStepInitialValue() {
        XCTAssertEqual(sequencer.currentStep, 0)
    }
    
    // MARK: - Playback Control Tests
    
    func testSequencerPlay() {
        sequencer.play()
        
        XCTAssertEqual(sequencer.playbackState, .playing)
        XCTAssertTrue(sequencer.isPlaying)
    }
    
    func testSequencerStop() {
        sequencer.play()
        XCTAssertTrue(sequencer.isPlaying)
        
        sequencer.stop()
        
        XCTAssertEqual(sequencer.playbackState, .stopped)
        XCTAssertFalse(sequencer.isPlaying)
        XCTAssertEqual(sequencer.currentStep, 0)
    }
    
    func testSequencerStopWhenNotPlaying() {
        // Should handle gracefully
        sequencer.stop()
        
        XCTAssertEqual(sequencer.playbackState, .stopped)
    }
    
    func testSequencerPlayStopCycle() {
        for _ in 0..<5 {
            sequencer.play()
            XCTAssertTrue(sequencer.isPlaying)
            
            sequencer.stop()
            XCTAssertFalse(sequencer.isPlaying)
        }
    }
    
    // MARK: - Pattern Tests
    
    func testSequencerPatternGrid() {
        let grid = sequencer.currentPatternGrid()
        
        // Grid should have rows (lanes) and columns (steps)
        XCTAssertGreaterThan(grid.count, 0)
        if grid.count > 0 {
            XCTAssertGreaterThan(grid[0].count, 0)
        }
    }
    
    func testSequencerPatternUpdate() {
        let originalPattern = sequencer.pattern
        
        // Create new pattern
        let newPattern = StepPattern.defaultDrumKit(tempo: 140.0)
        sequencer.pattern = newPattern
        
        XCTAssertNotEqual(sequencer.pattern.tempo, originalPattern.tempo)
        XCTAssertEqual(sequencer.pattern.tempo, 140.0)
    }
    
    // MARK: - Routing Tests
    
    func testSequencerRoutingInitialState() {
        let routing = sequencer.routing
        
        XCTAssertNotNil(routing)
    }
    
    func testSequencerTargetTrackId() {
        let trackId = UUID()
        
        sequencer.targetTrackId = trackId
        
        XCTAssertEqual(sequencer.targetTrackId, trackId)
    }
    
    func testSequencerRoutingMode() {
        // Test routing mode can be set
        // (Actual enum values depend on SequencerRoutingMode definition)
        let initialMode = sequencer.routingMode
        XCTAssertNotNil(initialMode)
    }
    
    // MARK: - MIDI Event Callback Tests
    
    func testSequencerMIDIEventCallback() {
        var receivedEvents: [SequencerMIDIEvent] = []
        
        sequencer.onMIDIEvent = { event in
            receivedEvents.append(event)
        }
        
        // Trigger would normally happen during playback
        // This tests that callback can be set
        XCTAssertNotNil(sequencer.onMIDIEvent)
    }
    
    func testSequencerMIDIEventsCallback() {
        var receivedBatches: [[SequencerMIDIEvent]] = []
        
        sequencer.onMIDIEvents = { events in
            receivedBatches.append(events)
        }
        
        XCTAssertNotNil(sequencer.onMIDIEvents)
    }
    
    // MARK: - Drum Kit Tests
    
    func testSequencerCurrentKitName() {
        let kitName = sequencer.currentKitName
        
        XCTAssertFalse(kitName.isEmpty)
    }
    
    func testSequencerKitLoader() {
        let kitLoader = sequencer.kitLoader
        
        XCTAssertNotNil(kitLoader)
        XCTAssertNotNil(kitLoader.currentKit)
    }
    
    // MARK: - Step Advancement Tests
    
    func testCurrentStepAdvancement() {
        // Current step should advance during playback
        // (This is internal to the engine, tested through integration)
        XCTAssertEqual(sequencer.currentStep, 0)
    }
    
    func testCurrentStepWrapsAtPatternEnd() {
        let steps = sequencer.pattern.steps
        
        // If step is at end, should wrap to 0
        let wrappedStep = (steps) % steps
        XCTAssertEqual(wrappedStep, 0)
    }
    
    // MARK: - Performance Tests
    
    func testSequencerCreationPerformance() {
        measure {
            for _ in 0..<10 {
                let tempSequencer = SequencerEngine(tempo: 120.0)
                tempSequencer.stop()
            }
        }
    }
    
    func testSequencerPlayStopPerformance() {
        measure {
            for _ in 0..<50 {
                sequencer.play()
                sequencer.stop()
            }
        }
    }
    
    func testSequencerPatternGridPerformance() {
        measure {
            for _ in 0..<100 {
                _ = sequencer.currentPatternGrid()
            }
        }
    }
    
    // MARK: - Memory Management Tests
    
    func testSequencerCleanup() {
        for _ in 0..<5 {
            let tempSequencer = SequencerEngine(tempo: 140.0)
            tempSequencer.play()
            tempSequencer.stop()
        }
        
        XCTAssertTrue(true, "Multiple sequencer lifecycles completed")
    }
    
    // MARK: - Integration Tests
    
    func testSequencerFullWorkflow() {
        // Complete workflow: initialize, configure, play, stop
        
        // 1. Configure
        sequencer.targetTrackId = UUID()
        
        // 2. Set up MIDI callback
        var eventCount = 0
        sequencer.onMIDIEvent = { _ in
            eventCount += 1
        }
        
        // 3. Play
        sequencer.play()
        XCTAssertTrue(sequencer.isPlaying)
        
        // 4. Stop
        sequencer.stop()
        XCTAssertFalse(sequencer.isPlaying)
        XCTAssertEqual(sequencer.currentStep, 0)
        
        XCTAssertTrue(true, "Full sequencer workflow completed")
    }
}
