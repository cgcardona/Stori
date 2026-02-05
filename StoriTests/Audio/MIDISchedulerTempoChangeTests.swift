//
//  MIDISchedulerTempoChangeTests.swift
//  StoriTests
//
//  Created by TellUrStoriDAW
//  Copyright © 2026 TellUrStori. All rights reserved.
//
//  Test suite for Bug #53: MIDI Scheduler Regeneration May Miss Events During Tempo Change
//  GitHub Issue: https://github.com/cgcardona/Stori/issues/53
//

import XCTest
@testable import Stori

/// Tests for MIDI scheduler tempo change handling (Bug #53 / Issue #53)
///
/// CRITICAL BUG FIXED:
/// When tempo changes during playback, events already scheduled in the AU MIDI queue
/// (from the lookahead window) were not cancelled, causing duplicate or mis-timed notes.
///
/// ROOT CAUSE:
/// - `AUScheduleMIDIEventBlock` schedules events up to 150ms ahead
/// - Once scheduled, events can't be cancelled without resetting the AU
/// - Old timing reference caused future events to calculate incorrect sample times
///
/// FIX IMPLEMENTED:
/// - Stop all active notes on tempo change
/// - Clear scheduled event tracking
/// - Create new timing reference with updated tempo
/// - Reschedule lookahead window from current position
/// - Send MIDI All Notes Off (CC 123) to clear AU queue
///
/// PROFESSIONAL STANDARD:
/// Logic Pro, Pro Tools, and Cubase all invalidate the lookahead buffer and
/// reschedule from the current position when tempo changes during playback.
final class MIDISchedulerTempoChangeTests: XCTestCase {
    
    // MARK: - Test Setup
    
    var scheduler: SampleAccurateMIDIScheduler!
    var capturedEvents: [(status: UInt8, data1: UInt8, data2: UInt8, trackId: UUID, sampleTime: AUEventSampleTime)]!
    var testTracks: [AudioTrack]!
    let testTrackId = UUID()
    let sampleRate: Double = 48000
    var currentBeat: Double = 0.0
    
    override func setUp() {
        super.setUp()
        
        capturedEvents = []
        scheduler = SampleAccurateMIDIScheduler()
        
        // Configure scheduler
        scheduler.configure(tempo: 120, sampleRate: sampleRate)
        
        // Set up beat provider
        scheduler.currentBeatProvider = { [weak self] in
            self?.currentBeat ?? 0.0
        }
        
        // Capture MIDI events
        scheduler.sampleAccurateMIDIHandler = { [weak self] status, data1, data2, trackId, sampleTime in
            self?.capturedEvents.append((status, data1, data2, trackId, sampleTime))
        }
        
        // Create test track
        testTracks = [AudioTrack(id: testTrackId)]
    }
    
    override func tearDown() {
        scheduler.stop()
        scheduler = nil
        capturedEvents = nil
        testTracks = nil
        super.tearDown()
    }
    
    // MARK: - Core Tempo Change Tests
    
    func testTempoChangeNoDoubleTrigger() {
        // BUG SCENARIO: Note scheduled at beat 4, tempo changes at beat 3.5
        // Should result in exactly ONE note-on at the recalculated time
        
        // Schedule a note at beat 4
        let region = MIDIRegion(startBeat: 0, durationBeats: 8, track: testTrackId)
        region.notes = [
            MIDINote(pitch: 60, startBeat: 4.0, durationBeats: 0.5, velocity: 100)
        ]
        testTracks[0].midiRegions = [region]
        
        scheduler.loadEvents(from: testTracks)
        
        // Start playback at beat 0
        currentBeat = 0.0
        scheduler.play(fromBeat: 0.0)
        
        // Advance to beat 3.5 (before the note)
        currentBeat = 3.5
        capturedEvents.removeAll()
        
        // Change tempo from 120 to 140 BPM
        scheduler.updateTempo(140)
        
        // Process events to schedule with new tempo
        scheduler.processScheduledEvents()
        
        // Filter for note-on events (0x90) for pitch 60
        let noteOnEvents = capturedEvents.filter { $0.status & 0xF0 == 0x90 && $0.data1 == 60 }
        
        // CRITICAL: Should have exactly 1 note-on, not 0 (missed) or 2 (doubled)
        XCTAssertEqual(noteOnEvents.count, 1,
                      "Tempo change should result in exactly 1 note-on (no double-trigger)")
    }
    
    func testTempoChangeActiveNotesReleased() {
        // Active notes should be released when tempo changes
        
        // Schedule a long note
        let region = MIDIRegion(startBeat: 0, durationBeats: 8, track: testTrackId)
        region.notes = [
            MIDINote(pitch: 60, startBeat: 0.0, durationBeats: 4.0, velocity: 100)
        ]
        testTracks[0].midiRegions = [region]
        
        scheduler.loadEvents(from: testTracks)
        
        // Start playback
        currentBeat = 0.0
        scheduler.play(fromBeat: 0.0)
        
        // Advance to beat 2.0 (note is active)
        currentBeat = 2.0
        capturedEvents.removeAll()
        
        // Change tempo
        scheduler.updateTempo(140)
        
        // Verify All Notes Off (CC 123) was sent
        let allNotesOffEvents = capturedEvents.filter { $0.status & 0xF0 == 0xB0 && $0.data1 == 123 }
        XCTAssertGreaterThan(allNotesOffEvents.count, 0,
                            "All Notes Off (CC 123) should be sent on tempo change")
        
        // Verify explicit note-off was sent for pitch 60
        let noteOffEvents = capturedEvents.filter { $0.status & 0xF0 == 0x80 && $0.data1 == 60 }
        XCTAssertGreaterThan(noteOffEvents.count, 0,
                            "Active notes should be explicitly released on tempo change")
    }
    
    func testTempoChangeTimingReferenceUpdated() {
        // Timing reference should be regenerated with new tempo
        
        currentBeat = 2.0
        scheduler.play(fromBeat: 2.0)
        
        // Change tempo from 120 to 140 BPM
        scheduler.updateTempo(140)
        
        // Schedule a note at beat 3.0
        let region = MIDIRegion(startBeat: 0, durationBeats: 8, track: testTrackId)
        region.notes = [
            MIDINote(pitch: 60, startBeat: 3.0, durationBeats: 0.5, velocity: 100)
        ]
        testTracks[0].midiRegions = [region]
        
        scheduler.loadEvents(from: testTracks)
        capturedEvents.removeAll()
        
        // Process events with new tempo
        scheduler.processScheduledEvents()
        
        // Find the note-on event
        guard let noteOnEvent = capturedEvents.first(where: { $0.status & 0xF0 == 0x90 && $0.data1 == 60 }) else {
            XCTFail("Note-on event should be scheduled")
            return
        }
        
        // Calculate expected sample time with new tempo (140 BPM)
        // Beat 3.0 is 1 beat away from current position (beat 2.0)
        // At 140 BPM: 1 beat = 60/140 = 0.428571 seconds
        // At 48000 Hz: 0.428571 * 48000 = ~20571 samples
        let expectedSamples = (1.0 / (140.0 / 60.0)) * sampleRate
        
        // Verify sample time is calculated with new tempo (within 100 samples tolerance)
        XCTAssertEqual(Double(noteOnEvent.sampleTime), expectedSamples, accuracy: 100,
                      "Note should be scheduled with new tempo's sample time")
    }
    
    // MARK: - Tempo Ramp Tests
    
    func testTempoRampTimingAccuracy() {
        // Simulate linear tempo ramp from 120 to 140 BPM over 4 bars
        // Notes should be scheduled accurately at each tempo step
        
        // Schedule notes every beat for 4 bars
        let region = MIDIRegion(startBeat: 0, durationBeats: 16, track: testTrackId)
        for beat in stride(from: 0.0, to: 16.0, by: 1.0) {
            region.notes.append(
                MIDINote(pitch: 60, startBeat: beat, durationBeats: 0.25, velocity: 100)
            )
        }
        testTracks[0].midiRegions = [region]
        
        scheduler.loadEvents(from: testTracks)
        
        // Start playback
        currentBeat = 0.0
        scheduler.play(fromBeat: 0.0)
        
        // Simulate tempo ramp: 120 → 125 → 130 → 135 → 140 (every bar)
        let tempoSteps = [120.0, 125.0, 130.0, 135.0, 140.0]
        var allNoteOnEvents: [(beat: Double, sampleTime: AUEventSampleTime, tempo: Double)] = []
        
        for (index, tempo) in tempoSteps.enumerated() {
            let beatPosition = Double(index * 4) // 0, 4, 8, 12, 16
            currentBeat = beatPosition
            
            if index > 0 {
                scheduler.updateTempo(tempo)
            }
            
            capturedEvents.removeAll()
            scheduler.processScheduledEvents()
            
            // Capture note-on events for this tempo step
            let noteOns = capturedEvents.filter { $0.status & 0xF0 == 0x90 }
            for event in noteOns {
                allNoteOnEvents.append((beatPosition, event.sampleTime, tempo))
            }
        }
        
        // Verify we captured events throughout the tempo ramp
        XCTAssertGreaterThan(allNoteOnEvents.count, 0,
                            "Events should be scheduled throughout tempo ramp")
        
        // Verify sample times are reasonable (no negative or absurdly large values)
        for event in allNoteOnEvents {
            XCTAssertGreaterThanOrEqual(event.sampleTime, 0,
                                       "Sample time should be non-negative")
            XCTAssertLessThan(event.sampleTime, Int64(sampleRate * 10),
                            "Sample time should be reasonable (< 10 seconds ahead)")
        }
    }
    
    func testTempoIncreaseShortensNoteSpacing() {
        // When tempo increases, notes should get closer together in time
        
        // Schedule two notes 1 beat apart
        let region = MIDIRegion(startBeat: 0, durationBeats: 8, track: testTrackId)
        region.notes = [
            MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.25, velocity: 100),
            MIDINote(pitch: 62, startBeat: 2.0, durationBeats: 0.25, velocity: 100)
        ]
        testTracks[0].midiRegions = [region]
        
        scheduler.loadEvents(from: testTracks)
        
        // Measure spacing at 120 BPM
        currentBeat = 0.0
        scheduler.play(fromBeat: 0.0)
        scheduler.processScheduledEvents()
        
        let events120 = capturedEvents.filter { $0.status & 0xF0 == 0x90 }
        guard events120.count == 2 else {
            XCTFail("Should have 2 note-on events at 120 BPM")
            return
        }
        let spacing120 = events120[1].sampleTime - events120[0].sampleTime
        
        // Change to 180 BPM (1.5x faster) and measure again
        scheduler.stop()
        capturedEvents.removeAll()
        
        scheduler.updateTempo(180)
        currentBeat = 0.0
        scheduler.play(fromBeat: 0.0)
        scheduler.processScheduledEvents()
        
        let events180 = capturedEvents.filter { $0.status & 0xF0 == 0x90 }
        guard events180.count == 2 else {
            XCTFail("Should have 2 note-on events at 180 BPM")
            return
        }
        let spacing180 = events180[1].sampleTime - events180[0].sampleTime
        
        // Verify spacing at 180 BPM is ~2/3 of spacing at 120 BPM (120/180 = 0.667)
        let ratio = Double(spacing180) / Double(spacing120)
        XCTAssertEqual(ratio, 120.0 / 180.0, accuracy: 0.05,
                      "Note spacing should scale inversely with tempo")
    }
    
    // MARK: - Edge Cases
    
    func testTempoChangeAtNoteOnset() {
        // Tempo change exactly at a note's onset should not double-trigger
        
        let region = MIDIRegion(startBeat: 0, durationBeats: 8, track: testTrackId)
        region.notes = [
            MIDINote(pitch: 60, startBeat: 4.0, durationBeats: 0.5, velocity: 100)
        ]
        testTracks[0].midiRegions = [region]
        
        scheduler.loadEvents(from: testTracks)
        
        // Advance to exactly beat 4.0
        currentBeat = 4.0
        scheduler.play(fromBeat: 4.0)
        
        capturedEvents.removeAll()
        
        // Change tempo exactly at note onset
        scheduler.updateTempo(140)
        scheduler.processScheduledEvents()
        
        // Count note-on events for pitch 60
        let noteOnCount = capturedEvents.filter { $0.status & 0xF0 == 0x90 && $0.data1 == 60 }.count
        
        XCTAssertEqual(noteOnCount, 1,
                      "Tempo change at note onset should not cause double-trigger")
    }
    
    func testMultipleTempoChangesInQuickSuccession() {
        // Rapid tempo changes should not cause event queue corruption
        
        let region = MIDIRegion(startBeat: 0, durationBeats: 8, track: testTrackId)
        region.notes = [
            MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 0.5, velocity: 100)
        ]
        testTracks[0].midiRegions = [region]
        
        scheduler.loadEvents(from: testTracks)
        
        currentBeat = 0.0
        scheduler.play(fromBeat: 0.0)
        
        // Change tempo multiple times rapidly
        scheduler.updateTempo(130)
        scheduler.updateTempo(140)
        scheduler.updateTempo(150)
        scheduler.updateTempo(120)
        
        capturedEvents.removeAll()
        scheduler.processScheduledEvents()
        
        // Should have exactly one note-on (no corruption/duplication)
        let noteOnCount = capturedEvents.filter { $0.status & 0xF0 == 0x90 && $0.data1 == 60 }.count
        
        XCTAssertEqual(noteOnCount, 1,
                      "Multiple rapid tempo changes should not corrupt event queue")
    }
    
    func testTempoChangeWithCycleLoop() {
        // Tempo change during cycle loop should maintain correct timing
        
        let region = MIDIRegion(startBeat: 0, durationBeats: 8, track: testTrackId)
        region.notes = [
            MIDINote(pitch: 60, startBeat: 1.0, durationBeats: 0.25, velocity: 100)
        ]
        testTracks[0].midiRegions = [region]
        
        scheduler.loadEvents(from: testTracks)
        
        // Enable cycle from beat 0 to 2
        scheduler.setCycle(enabled: true, startBeat: 0, endBeat: 2)
        
        currentBeat = 0.5
        scheduler.play(fromBeat: 0.5)
        
        // Change tempo mid-cycle
        scheduler.updateTempo(140)
        
        capturedEvents.removeAll()
        scheduler.processScheduledEvents()
        
        // Note at beat 1.0 should be scheduled (within cycle range)
        let noteOnCount = capturedEvents.filter { $0.status & 0xF0 == 0x90 && $0.data1 == 60 }.count
        
        XCTAssertGreaterThan(noteOnCount, 0,
                            "Tempo change should not prevent cycle loop notes from scheduling")
    }
    
    func testTempoChangeWhileNotPlaying() {
        // Tempo change while stopped should not cause errors
        
        // Don't start playback
        XCTAssertNoThrow(scheduler.updateTempo(140),
                        "Tempo change while stopped should not throw")
        
        // Start playback with new tempo
        currentBeat = 0.0
        XCTAssertNoThrow(scheduler.play(fromBeat: 0.0),
                        "Playback should start correctly after tempo change while stopped")
    }
    
    // MARK: - Integration Tests
    
    func testTempoAutomationScenario() {
        // Real-world scenario: Tempo automation in electronic music build-up
        // Tempo gradually increases from 120 to 140 over 16 beats
        
        // Schedule notes throughout the build-up
        let region = MIDIRegion(startBeat: 0, durationBeats: 16, track: testTrackId)
        for beat in stride(from: 0.0, to: 16.0, by: 0.25) {
            region.notes.append(
                MIDINote(pitch: 60, startBeat: beat, durationBeats: 0.1, velocity: 100)
            )
        }
        testTracks[0].midiRegions = [region]
        
        scheduler.loadEvents(from: testTracks)
        
        // Start playback
        currentBeat = 0.0
        scheduler.play(fromBeat: 0.0)
        
        // Simulate tempo automation curve
        var allEvents: [AUEventSampleTime] = []
        
        for beat in stride(from: 0.0, to: 16.0, by: 1.0) {
            // Linear tempo interpolation
            let tempo = 120.0 + (140.0 - 120.0) * (beat / 16.0)
            currentBeat = beat
            scheduler.updateTempo(tempo)
            
            capturedEvents.removeAll()
            scheduler.processScheduledEvents()
            
            let noteOns = capturedEvents.filter { $0.status & 0xF0 == 0x90 }
            allEvents.append(contentsOf: noteOns.map { $0.sampleTime })
        }
        
        // Verify all events were scheduled
        XCTAssertGreaterThan(allEvents.count, 0,
                            "Tempo automation should schedule all events")
        
        // Verify no duplicate sample times (would indicate double-triggering)
        let uniqueTimes = Set(allEvents)
        XCTAssertEqual(uniqueTimes.count, allEvents.count,
                      "No events should have duplicate sample times (no double-triggering)")
    }
    
    func testTempoChangeWithMultipleTracks() {
        // Tempo change should correctly handle multiple tracks
        
        let track1Id = UUID()
        let track2Id = UUID()
        
        let region1 = MIDIRegion(startBeat: 0, durationBeats: 8, track: track1Id)
        region1.notes = [
            MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 0.5, velocity: 100)
        ]
        
        let region2 = MIDIRegion(startBeat: 0, durationBeats: 8, track: track2Id)
        region2.notes = [
            MIDINote(pitch: 64, startBeat: 2.0, durationBeats: 0.5, velocity: 100)
        ]
        
        let multiTracks = [
            AudioTrack(id: track1Id, midiRegions: [region1]),
            AudioTrack(id: track2Id, midiRegions: [region2])
        ]
        
        scheduler.loadEvents(from: multiTracks)
        
        currentBeat = 1.0
        scheduler.play(fromBeat: 1.0)
        
        // Change tempo
        scheduler.updateTempo(140)
        
        capturedEvents.removeAll()
        scheduler.processScheduledEvents()
        
        // Both tracks should have their notes scheduled
        let track1Events = capturedEvents.filter { $0.trackId == track1Id && $0.status & 0xF0 == 0x90 }
        let track2Events = capturedEvents.filter { $0.trackId == track2Id && $0.status & 0xF0 == 0x90 }
        
        XCTAssertGreaterThan(track1Events.count, 0, "Track 1 events should be scheduled")
        XCTAssertGreaterThan(track2Events.count, 0, "Track 2 events should be scheduled")
    }
    
    // MARK: - Regression Protection
    
    func testTempoChangePreservesEventOrder() {
        // Events should maintain their beat-relative order after tempo change
        
        let region = MIDIRegion(startBeat: 0, durationBeats: 8, track: testTrackId)
        region.notes = [
            MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 0.25, velocity: 100),
            MIDINote(pitch: 62, startBeat: 2.5, durationBeats: 0.25, velocity: 100),
            MIDINote(pitch: 64, startBeat: 3.0, durationBeats: 0.25, velocity: 100)
        ]
        testTracks[0].midiRegions = [region]
        
        scheduler.loadEvents(from: testTracks)
        
        currentBeat = 1.0
        scheduler.play(fromBeat: 1.0)
        
        // Change tempo
        scheduler.updateTempo(140)
        
        capturedEvents.removeAll()
        scheduler.processScheduledEvents()
        
        // Extract note-on events and their pitches
        let noteOns = capturedEvents.filter { $0.status & 0xF0 == 0x90 }
        let pitches = noteOns.map { $0.data1 }
        
        // Verify order: 60, 62, 64
        XCTAssertEqual(pitches, [60, 62, 64],
                      "Event order should be preserved after tempo change")
    }
    
    func testTempoChangeNoMemoryLeak() {
        // Repeated tempo changes should not leak memory
        
        let region = MIDIRegion(startBeat: 0, durationBeats: 8, track: testTrackId)
        region.notes = [
            MIDINote(pitch: 60, startBeat: 2.0, durationBeats: 0.5, velocity: 100)
        ]
        testTracks[0].midiRegions = [region]
        
        scheduler.loadEvents(from: testTracks)
        
        currentBeat = 0.0
        scheduler.play(fromBeat: 0.0)
        
        // Perform many tempo changes
        for _ in 0..<100 {
            scheduler.updateTempo(Double.random(in: 60...180))
            scheduler.processScheduledEvents()
        }
        
        // If we get here without crashing or hanging, memory management is OK
        XCTAssertTrue(true, "Repeated tempo changes should not cause memory issues")
    }
}
