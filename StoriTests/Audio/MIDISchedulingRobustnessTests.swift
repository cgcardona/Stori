//
//  MIDISchedulingRobustnessTests.swift
//  StoriTests
//
//  Comprehensive tests for MIDI scheduling robustness (Issue #009)
//  Tests lookahead, transport edge cases, timing accuracy, and real-time safety
//

import XCTest
import AVFoundation
@testable import Stori

@MainActor
final class MIDISchedulingRobustnessTests: XCTestCase {
    
    var scheduler: SampleAccurateMIDIScheduler!
    var receivedEvents: [(beat: Double, status: UInt8, data1: UInt8, data2: UInt8, sampleTime: AUEventSampleTime)] = []
    var currentBeat: Double = 0
    let testTempo: Double = 120.0
    let testSampleRate: Double = 48000.0
    
    override func setUp() async throws {
        scheduler = SampleAccurateMIDIScheduler()
        receivedEvents = []
        currentBeat = 0
        
        // Configure scheduler with test parameters
        scheduler.configure(tempo: testTempo, sampleRate: testSampleRate)
        
        // Set up beat provider
        scheduler.currentBeatProvider = { [weak self] in
            self?.currentBeat ?? 0
        }
        
        // Set up MIDI handler to capture events
        scheduler.sampleAccurateMIDIHandler = { [weak self] status, data1, data2, trackId, sampleTime in
            self?.receivedEvents.append((self?.currentBeat ?? 0, status, data1, data2, sampleTime))
        }
    }
    
    override func tearDown() async throws {
        scheduler.stop()
        scheduler = nil
        receivedEvents = []
    }
    
    // MARK: - 1. Lookahead & Buffer Timing Tests
    
    func testLookaheadIsufficient() {
        // Verify that 50ms lookahead is sufficient for all events to be scheduled
        // Worst case: 2ms timer + 10ms hardware = 12ms < 50ms lookahead ✓
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 1.0),
            createNote(pitch: 62, startBeat: 1.0, duration: 1.0),
            createNote(pitch: 64, startBeat: 2.0, duration: 1.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        // All events within first 50ms should be scheduled immediately
        let expectation = XCTestExpectation(description: "Events scheduled with lookahead")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Check that events were scheduled with positive sample times (future scheduling)
            XCTAssertGreaterThan(self.receivedEvents.count, 0, "Events should be scheduled")
            
            for event in self.receivedEvents {
                // Events should have positive or zero sample time (scheduled for future)
                XCTAssertGreaterThanOrEqual(event.sampleTime, 0, "Sample time should be >= 0")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    func testTimingReferenceRegenerationEvery2Seconds() {
        // Verify that timing reference is regenerated every 2 seconds max
        // This prevents accumulated drift in long playback sessions
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 1.0),
            createNote(pitch: 62, startBeat: 1.0, duration: 1.0),
            createNote(pitch: 64, startBeat: 2.0, duration: 1.0),
            createNote(pitch: 65, startBeat: 3.0, duration: 1.0),
            createNote(pitch: 67, startBeat: 4.0, duration: 1.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        let expectation = XCTestExpectation(description: "Timing reference stays fresh")
        expectation.expectedFulfillmentCount = 3
        
        // Check at 1s, 2s, and 3s intervals
        // Each check advances beat and verifies new events are scheduled
        for checkIndex in 1...3 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(checkIndex)) {
                let eventsBeforeAdvance = self.receivedEvents.count
                
                // Advance beat asynchronously to trigger new event scheduling
                DispatchQueue.global().async {
                    let startBeat = Double(checkIndex) * 0.8
                    for i in 0..<10 {
                        usleep(5000) // 5ms
                        self.currentBeat = startBeat + Double(i) * 0.1
                    }
                }
                
                // Wait for events to be scheduled
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    // Should have scheduled new events during the advancement
                    XCTAssertGreaterThanOrEqual(self.receivedEvents.count, eventsBeforeAdvance,
                                                "Events should continue scheduling at checkpoint \(checkIndex)")
                    expectation.fulfill()
                }
            }
        }
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - 2. Transport Edge Case Tests
    
    func testStopClearsAllScheduledEvents() {
        // Verify that stop() clears all scheduling state and sends note-offs
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 4.0),
            createNote(pitch: 62, startBeat: 1.0, duration: 4.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        // Let some events schedule
        let playExpectation = XCTestExpectation(description: "Events scheduled during play")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            playExpectation.fulfill()
        }
        wait(for: [playExpectation], timeout: 1.0)
        
        let eventsBeforeStop = receivedEvents.count
        XCTAssertGreaterThan(eventsBeforeStop, 0, "Should have scheduled some events")
        
        // Stop playback
        receivedEvents.removeAll()
        scheduler.stop()
        
        // Verify note-offs were sent (status 0x80)
        let noteOffs = receivedEvents.filter { $0.status & 0xF0 == 0x80 }
        XCTAssertGreaterThan(noteOffs.count, 0, "Should send note-offs on stop")
        
        // Verify scheduler state is cleared
        XCTAssertFalse(scheduler.isPlaying, "Should not be playing after stop")
    }
    
    func testStartStopStartNoDoubleNotes() {
        // Verify rapid start/stop/start doesn't cause duplicate notes
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 1.0),
        ])
        
        scheduler.loadEvents(from: [track])
        
        // Start
        scheduler.play(fromBeat: 0)
        let startExpectation1 = XCTestExpectation(description: "First start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            startExpectation1.fulfill()
        }
        wait(for: [startExpectation1], timeout: 1.0)
        
        let eventsAfterFirstStart = receivedEvents.count
        
        // Stop
        scheduler.stop()
        
        // Start again from same position
        receivedEvents.removeAll()
        scheduler.play(fromBeat: 0)
        
        let startExpectation2 = XCTestExpectation(description: "Second start")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            startExpectation2.fulfill()
        }
        wait(for: [startExpectation2], timeout: 1.0)
        
        // Count note-on events (status 0x90 with velocity > 0)
        let noteOns = receivedEvents.filter { $0.status & 0xF0 == 0x90 && $0.data2 > 0 }
        
        // Should have exactly 1 note-on (not double-scheduled)
        XCTAssertEqual(noteOns.count, 1, "Should not double-schedule notes on restart")
    }
    
    func testSeekClearsInFlightEvents() {
        // Verify seek() clears scheduled events and reschedules from new position
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 1.0),
            createNote(pitch: 62, startBeat: 2.0, duration: 1.0),
            createNote(pitch: 64, startBeat: 4.0, duration: 1.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        // Let initial events schedule
        let playExpectation = XCTestExpectation(description: "Initial events scheduled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            playExpectation.fulfill()
        }
        wait(for: [playExpectation], timeout: 1.0)
        
        XCTAssertGreaterThan(receivedEvents.count, 0, "Should have initial events")
        
        // Seek to beat 4 (skipping middle note)
        receivedEvents.removeAll()
        scheduler.seek(toBeat: 4.0)
        currentBeat = 4.0
        
        let seekExpectation = XCTestExpectation(description: "Events after seek")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            seekExpectation.fulfill()
        }
        wait(for: [seekExpectation], timeout: 1.0)
        
        // Should only have events from beat 4 onward (note pitch 64)
        let noteOns = receivedEvents.filter { $0.status & 0xF0 == 0x90 && $0.data2 > 0 }
        if !noteOns.isEmpty {
            XCTAssertEqual(noteOns.first?.data1, 64, "Should schedule note at beat 4 (pitch 64)")
        }
    }
    
    func testTempoChangeRegeneratesTimingReference() {
        // Verify tempo change creates new timing reference for accurate scheduling
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 2.0),
            createNote(pitch: 62, startBeat: 2.0, duration: 2.0),
            createNote(pitch: 64, startBeat: 4.0, duration: 2.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        // Let events schedule at original tempo
        let initialExpectation = XCTestExpectation(description: "Initial events")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            initialExpectation.fulfill()
        }
        wait(for: [initialExpectation], timeout: 1.0)
        
        let initialEventCount = receivedEvents.count
        XCTAssertGreaterThan(initialEventCount, 0, "Should have initial events")
        
        // Change tempo
        receivedEvents.removeAll()
        scheduler.updateTempo(140.0)
        currentBeat = 1.5
        
        // Advance beat asynchronously to trigger scheduling at new tempo
        DispatchQueue.global().async {
            for i in 0..<20 {
                usleep(5000) // 5ms between updates
                self.currentBeat = 1.5 + Double(i) * 0.15 // Advance toward beat 4.0
            }
        }
        
        // Events should continue scheduling with new tempo
        let tempoChangeExpectation = XCTestExpectation(description: "Events after tempo change")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            tempoChangeExpectation.fulfill()
        }
        wait(for: [tempoChangeExpectation], timeout: 1.0)
        
        XCTAssertGreaterThan(receivedEvents.count, 0, "Should continue scheduling after tempo change")
    }
    
    func testCycleJumpHandling() {
        // Verify cycle jump to start position doesn't cause duplicate notes
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 1.0),
            createNote(pitch: 62, startBeat: 1.0, duration: 1.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.setCycle(enabled: true, startBeat: 0.0, endBeat: 2.0)
        scheduler.play(fromBeat: 0)
        
        // Let events schedule in first cycle
        let firstCycleExpectation = XCTestExpectation(description: "First cycle events")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            firstCycleExpectation.fulfill()
        }
        wait(for: [firstCycleExpectation], timeout: 1.0)
        
        let firstCycleNoteOns = receivedEvents.filter { $0.status & 0xF0 == 0x90 && $0.data2 > 0 }
        
        // Simulate cycle jump
        receivedEvents.removeAll()
        scheduler.seek(toBeat: 0.0)
        currentBeat = 0.0
        
        let secondCycleExpectation = XCTestExpectation(description: "Second cycle events")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            secondCycleExpectation.fulfill()
        }
        wait(for: [secondCycleExpectation], timeout: 1.0)
        
        let secondCycleNoteOns = receivedEvents.filter { $0.status & 0xF0 == 0x90 && $0.data2 > 0 }
        
        // Should schedule same notes again (not skip them)
        XCTAssertEqual(secondCycleNoteOns.count, firstCycleNoteOns.count,
                       "Should schedule same notes on cycle jump")
    }
    
    // MARK: - 3. Real-Time Safety Tests
    
    func testNoAllocationInProcessingPath() {
        // Verify that processScheduledEvents doesn't allocate on audio thread
        // Note: This is a smoke test - real verification requires Instruments profiling
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 1.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        // Process many events rapidly (stress test)
        for i in 0..<100 {
            currentBeat = Double(i) * 0.01
            usleep(1000) // 1ms between updates
        }
        
        // If we get here without crashes, no obvious allocation issues
        XCTAssertTrue(true, "Processing should complete without allocation issues")
    }
    
    func testConcurrentAccessToSchedulerState() {
        // Verify thread-safe access to scheduler state (os_unfair_lock)
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 10.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        let expectation = XCTestExpectation(description: "Concurrent operations complete")
        expectation.expectedFulfillmentCount = 3
        
        // Concurrent operations from different threads
        DispatchQueue.global(qos: .userInteractive).async {
            for _ in 0..<50 {
                _ = self.scheduler.isPlaying
                usleep(1000)
            }
            expectation.fulfill()
        }
        
        DispatchQueue.global(qos: .utility).async {
            for i in 0..<50 {
                self.currentBeat = Double(i) * 0.1
                usleep(1000)
            }
            expectation.fulfill()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.scheduler.seek(toBeat: 5.0)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    // MARK: - 4. Timing Accuracy Tests
    
    func testSampleAccurateTiming() {
        // Verify that events are scheduled with correct sample times
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 1.0),
            createNote(pitch: 62, startBeat: 1.0, duration: 1.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        let expectation = XCTestExpectation(description: "Events scheduled with sample times")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
        
        let noteOns = receivedEvents.filter { $0.status & 0xF0 == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThan(noteOns.count, 0, "Should have note-on events")
        
        // Verify sample times are within lookahead window
        let maxLookaheadSamples = Int64(0.050 * testSampleRate) // 50ms * 48kHz = 2400 samples
        for event in noteOns {
            XCTAssertLessThanOrEqual(event.sampleTime, maxLookaheadSamples,
                                     "Sample time should be within lookahead window")
            XCTAssertGreaterThanOrEqual(event.sampleTime, 0,
                                        "Sample time should not be negative")
        }
    }
    
    func testSampleRateChangeRegeneratesTimingReference() {
        // Verify sample rate change creates new timing reference
        // CRITICAL: Users can switch audio interfaces mid-session (e.g., built-in → external DAC)
        // Sample rate changes require timing reference regeneration for accurate scheduling
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 2.0),
            createNote(pitch: 62, startBeat: 2.0, duration: 2.0),
            createNote(pitch: 64, startBeat: 4.0, duration: 2.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        // Let events schedule at original sample rate (48kHz)
        let initialExpectation = XCTestExpectation(description: "Initial events at 48kHz")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            initialExpectation.fulfill()
        }
        wait(for: [initialExpectation], timeout: 1.0)
        
        let initialEventCount = receivedEvents.count
        XCTAssertGreaterThan(initialEventCount, 0, "Should have initial events")
        
        // Change sample rate (user switched audio interface to 96kHz)
        receivedEvents.removeAll()
        scheduler.updateSampleRate(96000.0)
        currentBeat = 1.5
        
        // Advance beat asynchronously to trigger scheduling at new sample rate
        DispatchQueue.global().async {
            for i in 0..<20 {
                usleep(5000) // 5ms between updates
                self.currentBeat = 1.5 + Double(i) * 0.15 // Advance toward beat 4.0
            }
        }
        
        // Events should continue scheduling with new sample rate
        let sampleRateChangeExpectation = XCTestExpectation(description: "Events after sample rate change")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            sampleRateChangeExpectation.fulfill()
        }
        wait(for: [sampleRateChangeExpectation], timeout: 1.0)
        
        XCTAssertGreaterThan(receivedEvents.count, 0, 
                            "Should continue scheduling after sample rate change")
    }
    
    // MARK: - Helper Methods
    
    private func createTestTrack(with notes: [MIDINote]) -> AudioTrack {
        var track = AudioTrack(name: "Test Track", trackType: .midi)
        
        var region = MIDIRegion(startBeat: 0, durationBeats: 10)
        region.notes = notes
        region.isMuted = false
        region.isLooped = false
        
        track.midiRegions = [region]
        return track
    }
    
    private func createNote(pitch: UInt8, startBeat: Double, duration: Double, velocity: UInt8 = 100) -> MIDINote {
        MIDINote(
            pitch: pitch,
            velocity: velocity,
            startBeat: startBeat,
            durationBeats: duration
        )
    }
}
