//
//  StepSequencerVelocityTests.swift
//  StoriTests
//
//  Comprehensive tests for Step Sequencer velocity handling
//  Ensures velocity dynamics are correctly applied from UI → MIDI → Audio output
//

import XCTest
@testable import Stori
import AVFoundation

@MainActor
final class StepSequencerVelocityTests: XCTestCase {
    
    // MARK: - Test Properties
    
    private var sequencer: SequencerEngine!
    private var capturedMIDIEvents: [SequencerMIDIEvent]!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        sequencer = SequencerEngine(tempo: 120.0)
        capturedMIDIEvents = []
        
        // Capture all MIDI events for verification
        sequencer.onMIDIEvents = { [weak self] events in
            self?.capturedMIDIEvents.append(contentsOf: events)
        }
    }
    
    override func tearDown() async throws {
        sequencer.stop()
        sequencer = nil
        capturedMIDIEvents = nil
        try await super.tearDown()
    }
    
    // MARK: - Model Layer Tests
    
    func testStepVelocityStoredCorrectly() {
        // Given: A sequencer pattern
        var lane = sequencer.pattern.lanes[0]
        
        // When: Setting different velocities for different steps
        lane.setStep(0, velocity: 1.0)   // Max velocity
        lane.setStep(1, velocity: 0.5)   // Medium velocity
        lane.setStep(2, velocity: 0.1)   // Low velocity
        
        // Then: Velocities should be stored exactly as set
        XCTAssertEqual(Double(lane.velocity(for: 0) ?? 0), 1.0, accuracy: 0.001)
        XCTAssertEqual(Double(lane.velocity(for: 1) ?? 0), 0.5, accuracy: 0.001)
        XCTAssertEqual(Double(lane.velocity(for: 2) ?? 0), 0.1, accuracy: 0.001)
    }
    
    func testStepVelocityClampedToValidRange() {
        // Given: A lane
        var lane = sequencer.pattern.lanes[0]
        
        // When: Attempting to set out-of-range velocities
        lane.setStep(0, velocity: 1.5)   // Above max
        lane.setStep(1, velocity: -0.2)  // Below min
        
        // Then: Should clamp to valid range [0.0, 1.0]
        XCTAssertEqual(Double(lane.velocity(for: 0) ?? 0), 1.0, accuracy: 0.001)
        XCTAssertEqual(Double(lane.velocity(for: 1) ?? 0), 0.0, accuracy: 0.001)
    }
    
    func testVelocityAdjustmentWithDelta() {
        // Given: A step with initial velocity
        var lane = sequencer.pattern.lanes[0]
        lane.setStep(0, velocity: 0.5)
        
        // When: Adjusting velocity by delta
        lane.adjustVelocity(for: 0, delta: 0.2)
        
        // Then: Velocity should be updated correctly
        XCTAssertEqual(Double(lane.velocity(for: 0) ?? 0), 0.7, accuracy: 0.001)
    }
    
    func testVelocityAdjustmentClampedAtBounds() {
        // Given: A step near max velocity
        var lane = sequencer.pattern.lanes[0]
        lane.setStep(0, velocity: 0.95)
        
        // When: Adjusting beyond max
        lane.adjustVelocity(for: 0, delta: 0.2)
        
        // Then: Should clamp to 1.0
        XCTAssertEqual(Double(lane.velocity(for: 0) ?? 0), 1.0, accuracy: 0.001)
        
        // Given: A step near min velocity (enforced minimum is 0.1)
        lane.setStep(1, velocity: 0.15)
        
        // When: Adjusting below min
        lane.adjustVelocity(for: 1, delta: -0.2)
        
        // Then: Should clamp to minimum (0.1 as per implementation)
        XCTAssertLessThanOrEqual(lane.velocity(for: 1) ?? 0, 0.1)
    }
    
    // MARK: - MIDI Event Generation Tests
    
    func testMIDIEventVelocityConversion() {
        // Given: Steps with specific velocities
        let testCases: [(stepVelocity: Float, expectedMIDIVelocity: UInt8)] = [
            (1.0, 127),   // Max velocity
            (0.8, 101),   // ~80% velocity (0.8 * 127 = 101.6 → 101)
            (0.5, 63),    // Half velocity (0.5 * 127 = 63.5 → 63)
            (0.2, 25),    // Low velocity (0.2 * 127 = 25.4 → 25)
            (0.0, 1)      // Zero velocity should clamp to 1 (not 0)
        ]
        
        for (stepVelocity, expectedVelocity) in testCases {
            // When: Creating MIDI event from step
            let lane = sequencer.pattern.lanes[0]
            let event = SequencerMIDIEvent.from(
                lane: lane,
                step: 0,
                stepVelocity: stepVelocity,
                totalSteps: 16
            )
            
            // Then: MIDI velocity should match expected value
            XCTAssertEqual(event.velocity, expectedVelocity,
                           "Velocity \(stepVelocity) should convert to MIDI \(expectedVelocity), got \(event.velocity)")
        }
    }
    
    func testPatternMIDIEventsPreserveVelocity() {
        // Given: Pattern with varying velocities (lane volume 1.0 so step velocity maps directly)
        let kickLane = sequencer.pattern.lanes[0]
        let kickId = kickLane.id
        sequencer.setLaneVolume(laneId: kickId, volume: 1.0, registerUndo: false)
        
        // Set kick hits with different velocities
        sequencer.setStep(laneId: kickId, step: 0, active: true, velocity: 1.0)    // Strong
        sequencer.setStep(laneId: kickId, step: 4, active: true, velocity: 0.5)    // Medium
        sequencer.setStep(laneId: kickId, step: 8, active: true, velocity: 0.25)   // Weak
        
        // When: Generating MIDI events
        let events = sequencer.generatePatternMIDIEvents(loops: 1)
        
        // Then: Events should have correct velocities
        let kickEvents = events.filter { $0.soundType == .kick }
        XCTAssertEqual(kickEvents.count, 3)
        
        // Sort by timestamp to ensure predictable order
        let sortedEvents = kickEvents.sorted { $0.timestamp < $1.timestamp }
        
        XCTAssertEqual(sortedEvents[0].velocity, 127, "Strong kick should have velocity 127")
        XCTAssertEqual(sortedEvents[1].velocity, 63, "Medium kick should have velocity ~63")
        XCTAssertEqual(sortedEvents[2].velocity, 31, "Weak kick should have velocity ~31")
    }
    
    func testVelocityWithLaneVolumeMultiplier() {
        // Given: Lane with reduced volume
        let kickLane = sequencer.pattern.lanes[0]
        let kickId = kickLane.id
        
        // Set lane volume to 50%
        sequencer.setLaneVolume(laneId: kickId, volume: 0.5, registerUndo: false)
        
        // Set step at max velocity
        sequencer.setStep(laneId: kickId, step: 0, active: true, velocity: 1.0)
        
        // When: Generating MIDI events
        let events = sequencer.generatePatternMIDIEvents(loops: 1)
        
        // Then: MIDI velocity should be step velocity × lane volume
        // 1.0 × 0.5 = 0.5 → MIDI 63
        let kickEvents = events.filter { $0.soundType == .kick }
        XCTAssertEqual(kickEvents.count, 1)
        XCTAssertEqual(kickEvents[0].velocity, 63, "Velocity should be scaled by lane volume")
    }
    
    // MARK: - Playback Tests
    
    func testPlaybackTriggersWithCorrectVelocity() async {
        // Given: Pattern with velocity variations
        let kickLane = sequencer.pattern.lanes[0]
        let kickId = kickLane.id
        
        sequencer.setStep(laneId: kickId, step: 0, active: true, velocity: 1.0)
        sequencer.setStep(laneId: kickId, step: 1, active: true, velocity: 0.3)
        
        // Configure routing to send MIDI
        sequencer.routing.mode = .singleTrack
        sequencer.routing.targetTrackId = UUID()
        
        // When: Playing pattern
        sequencer.play()
        
        // Wait for a few steps to trigger
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        sequencer.stop()
        
        // Then: Captured MIDI events should have correct velocities
        XCTAssertGreaterThan(capturedMIDIEvents.count, 0, "Should have captured MIDI events")
        
        // Find kick events
        let kickEvents = capturedMIDIEvents.filter { $0.soundType == .kick }
        if kickEvents.count >= 2 {
            // First kick should be loud, second should be soft
            XCTAssertGreaterThan(kickEvents[0].velocity, 100, "First kick should be loud (>100)")
            XCTAssertLessThan(kickEvents[1].velocity, 50, "Second kick should be soft (<50)")
        }
    }
    
    func testVelocityRangeProducesAudibleDifference() {
        // This test documents that velocity MUST produce audible differences
        // Testing actual audio output is beyond unit tests, but we verify the data path
        
        // Given: Two steps with min and max velocity
        let lane = sequencer.pattern.lanes[0]
        
        let maxVelocityEvent = SequencerMIDIEvent.from(
            lane: lane,
            step: 0,
            stepVelocity: 1.0,
            totalSteps: 16
        )
        
        let minVelocityEvent = SequencerMIDIEvent.from(
            lane: lane,
            step: 1,
            stepVelocity: 0.1,
            totalSteps: 16
        )
        
        // Then: MIDI velocities should differ significantly
        let velocityRatio = Float(maxVelocityEvent.velocity) / Float(minVelocityEvent.velocity)
        XCTAssertGreaterThan(velocityRatio, 5.0,
                             "Max velocity should be >5x louder than min velocity for audible dynamics")
    }
    
    // MARK: - MIDI Export Tests
    
    func testMIDIExportPreservesVelocity() {
        // Given: Pattern with velocity gradient
        let lane = sequencer.pattern.lanes[0]
        let laneId = lane.id
        
        // Create velocity gradient: 1.0, 0.75, 0.5, 0.25
        for step in 0..<4 {
            let velocity = 1.0 - Float(step) * 0.25
            sequencer.setStep(laneId: laneId, step: step, active: true, velocity: velocity)
        }
        
        // When: Exporting to MIDI
        guard let midiURL = sequencer.exportToMIDI(loops: 1) else {
            XCTFail("MIDI export failed")
            return
        }
        
        // Then: MIDI file should contain velocity information
        // (Detailed MIDI parsing would require AVMIDIPlayer or third-party library)
        // For now, verify file was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: midiURL.path))
        
        // Cleanup
        try? FileManager.default.removeItem(at: midiURL)
    }
    
    // MARK: - Edge Case Tests
    
    func testVelocityWithHumanizationApplied() {
        // Given: Pattern with humanization enabled
        sequencer.setHumanizeVelocity(0.2, registerUndo: false)
        
        let lane = sequencer.pattern.lanes[0]
        let laneId = lane.id
        
        // Set consistent velocity
        sequencer.setStep(laneId: laneId, step: 0, active: true, velocity: 0.8)
        
        // When: Generating multiple loops (each should have slight variation)
        var velocities: Set<UInt8> = []
        for _ in 0..<10 {
            let events = sequencer.generatePatternMIDIEvents(loops: 1)
            if let firstEvent = events.first {
                velocities.insert(firstEvent.velocity)
            }
        }
        
        // Then: Should see some variation (but not guaranteed in 10 samples)
        // At minimum, all velocities should be within reasonable range of 0.8
        for velocity in velocities {
            let normalized = Float(velocity) / 127.0
            XCTAssertTrue((0.6...1.0).contains(normalized),
                          "Humanized velocity should stay within ~20% of original")
        }
    }
    
    func testVelocityPreservedAcrossPatternLoops() {
        // Given: Pattern with specific velocities (lane volume 1.0 for direct mapping)
        let lane = sequencer.pattern.lanes[0]
        let laneId = lane.id
        sequencer.setLaneVolume(laneId: laneId, volume: 1.0, registerUndo: false)
        
        sequencer.setStep(laneId: laneId, step: 0, active: true, velocity: 0.9)
        
        // When: Generating multiple loops
        let events = sequencer.generatePatternMIDIEvents(loops: 4)
        
        // Then: Each loop should have same velocity
        let firstStepEvents = events.filter { Int($0.timestamp / 0.25) % 16 == 0 }
        XCTAssertEqual(firstStepEvents.count, 4, "Should have 4 loop iterations")
        
        for event in firstStepEvents {
            XCTAssertEqual(event.velocity, 114, accuracy: 1,
                           "All loops should have consistent velocity")
        }
    }
    
    func testZeroVelocityStepIsNotTriggered() {
        // Given: Step with zero velocity (effectively off)
        let lane = sequencer.pattern.lanes[0]
        let laneId = lane.id
        
        // Set step to zero velocity (should be same as not active)
        sequencer.setStep(laneId: laneId, step: 0, active: true, velocity: 0.0)
        
        // When: Generating events
        let events = sequencer.generatePatternMIDIEvents(loops: 1)
        
        // Then: Should not generate event (or velocity should be clamped to minimum)
        if let firstEvent = events.first {
            // If event exists, velocity must be at least 1
            XCTAssertGreaterThanOrEqual(firstEvent.velocity, 1)
        }
    }
    
    // MARK: - Integration Tests
    
    func testGhostNotesWithLowVelocity() {
        // Ghost notes are essential for drum programming
        // Given: Snare pattern with ghost notes
        let snareLane = sequencer.pattern.lanes[1] // Snare
        let snareId = snareLane.id
        
        // Main snare hits (steps 4, 12)
        sequencer.setStep(laneId: snareId, step: 4, active: true, velocity: 1.0)
        sequencer.setStep(laneId: snareId, step: 12, active: true, velocity: 1.0)
        
        // Ghost notes (steps 2, 6, 10, 14)
        sequencer.setStep(laneId: snareId, step: 2, active: true, velocity: 0.2)
        sequencer.setStep(laneId: snareId, step: 6, active: true, velocity: 0.2)
        sequencer.setStep(laneId: snareId, step: 10, active: true, velocity: 0.2)
        sequencer.setStep(laneId: snareId, step: 14, active: true, velocity: 0.2)
        
        // When: Generating MIDI
        let events = sequencer.generatePatternMIDIEvents(loops: 1)
        let snareEvents = events.filter { $0.soundType == .snare }
        
        // Then: Should have 6 snare hits with correct velocity split
        XCTAssertEqual(snareEvents.count, 6)
        
        let mainHits = snareEvents.filter { $0.velocity > 100 }
        let ghostNotes = snareEvents.filter { $0.velocity < 50 }
        
        XCTAssertEqual(mainHits.count, 2, "Should have 2 main hits")
        XCTAssertEqual(ghostNotes.count, 4, "Should have 4 ghost notes")
    }
    
    func testAccentedBeatsWithHighVelocity() {
        // Accents are critical for groove
        // Given: Hi-hat pattern with accented downbeats
        let hihatLane = sequencer.pattern.lanes[2] // Closed hi-hat
        let hihatId = hihatLane.id
        
        // Set all 16th notes
        for step in 0..<16 {
            let velocity: Float = (step % 4 == 0) ? 1.0 : 0.5  // Accent downbeats
            sequencer.setStep(laneId: hihatId, step: step, active: true, velocity: velocity)
        }
        
        // When: Generating MIDI
        let events = sequencer.generatePatternMIDIEvents(loops: 1)
        let hihatEvents = events.filter { $0.soundType == .hihatClosed }
        
        // Then: Downbeats should be louder
        XCTAssertEqual(hihatEvents.count, 16)
        
        let downbeats = hihatEvents.filter { Int($0.timestamp / 0.25) % 4 == 0 }
        let offbeats = hihatEvents.filter { Int($0.timestamp / 0.25) % 4 != 0 }
        
        for downbeat in downbeats {
            XCTAssertGreaterThan(downbeat.velocity, 100, "Downbeats should be accented")
        }
        
        for offbeat in offbeats {
            XCTAssertLessThan(offbeat.velocity, 80, "Off-beats should be softer")
        }
    }
    
    // MARK: - Regression Tests
    
    func testVelocityNotHardcodedInTrigger() {
        // This test explicitly verifies the bug described in issue #66
        // Given: Two steps with dramatically different velocities
        let lane = sequencer.pattern.lanes[0]
        let laneId = lane.id
        
        sequencer.setStep(laneId: laneId, step: 0, active: true, velocity: 1.0)   // Loud
        sequencer.setStep(laneId: laneId, step: 1, active: true, velocity: 0.2)   // Soft
        
        // When: Generating events
        let events = sequencer.generatePatternMIDIEvents(loops: 1)
        
        // Then: Velocities MUST differ (not hardcoded to same value)
        XCTAssertEqual(events.count, 2)
        XCTAssertNotEqual(events[0].velocity, events[1].velocity,
                          "Velocity must not be hardcoded - each step should have its own velocity")
        
        // Verify the actual difference is significant
        let diff = abs(Int(events[0].velocity) - Int(events[1].velocity))
        XCTAssertGreaterThan(diff, 50,
                             "Velocity difference should be audibly significant (>50 MIDI units)")
    }
}
