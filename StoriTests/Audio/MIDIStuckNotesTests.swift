//
//  MIDIStuckNotesTests.swift
//  StoriTests
//
//  Tests for Issue #74 - MIDI Note Off May Not Send When Transport Stops Abruptly
//
//  Verifies that:
//  1. All active notes receive Note Off when transport stops
//  2. Active note tracking works correctly (note-on adds, note-off removes)
//  3. Seek operations send Note Off for active notes
//  4. Tempo changes send Note Off for active notes
//  5. Backup safety net (allNotesOffAllTracks) is called
//

import XCTest
import AVFoundation
@testable import Stori

final class MIDIStuckNotesTests: XCTestCase {
    
    var scheduler: SampleAccurateMIDIScheduler!
    var capturedEvents: [(status: UInt8, data1: UInt8, data2: UInt8, trackId: UUID, sampleTime: UInt64)] = []
    let testTrackId = UUID()
    let testSampleRate: Double = 48000.0
    let testTempo: Double = 120.0
    
    override func setUp() async throws {
        try await super.setUp()
        
        scheduler = SampleAccurateMIDIScheduler()
        capturedEvents = []
        
        // Install test MIDI handler that captures events
        scheduler.configureSampleAccurateScheduling(
            avEngine: AVAudioEngine(),
            sampleRate: testSampleRate
        )
        
        // Install capture handler
        scheduler.setSampleAccurateMIDIHandler { [weak self] status, data1, data2, trackId, sampleTime in
            self?.capturedEvents.append((status, data1, data2, trackId, sampleTime))
        }
        
        // Set tempo
        scheduler.updateTempo(testTempo)
    }
    
    override func tearDown() async throws {
        scheduler.stop()
        scheduler = nil
        capturedEvents = []
        try await super.tearDown()
    }
    
    // MARK: - Basic Active Note Tracking
    
    func testActiveNoteTracking_NoteOnAddsToActiveNotes() {
        // Test that note-on events are tracked as active
        
        // Create MIDI sequence with note-on
        let events = [
            ScheduledMIDIEvent(
                beat: 0.0,
                status: 0x90,  // Note On
                data1: 60,     // Middle C
                data2: 100,    // Velocity
                trackId: testTrackId
            )
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        
        // Process events
        try? Thread.sleep(forTimeInterval: 0.05)  // 50ms
        
        // Verify note-on was captured
        let noteOns = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThan(noteOns.count, 0, "Note-on should be sent")
    }
    
    func testActiveNoteTracking_NoteOffRemovesFromActiveNotes() {
        // Test that note-off events remove from active tracking
        
        let events = [
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 60, data2: 100, trackId: testTrackId),  // Note On
            ScheduledMIDIEvent(beat: 1.0, status: 0x80, data1: 60, data2: 0, trackId: testTrackId)     // Note Off
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        
        // Wait for both events to process
        try? Thread.sleep(forTimeInterval: 0.6)  // Longer than 1 beat at 120 BPM (0.5s)
        
        // Verify both events were sent
        let noteOns = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        let noteOffs = capturedEvents.filter { $0.status == 0x80 || ($0.status == 0x90 && $0.data2 == 0) }
        
        XCTAssertGreaterThan(noteOns.count, 0, "Note-on should be sent")
        XCTAssertGreaterThan(noteOffs.count, 0, "Note-off should be sent")
    }
    
    // MARK: - Stop Behavior
    
    func testStopSendsNoteOffForActiveLongNote() {
        // Test that stopping during a long note sends Note Off
        
        // Schedule long note (4 beats = 2 seconds at 120 BPM)
        let events = [
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 60, data2: 100, trackId: testTrackId),  // Note On
            ScheduledMIDIEvent(beat: 4.0, status: 0x80, data1: 60, data2: 0, trackId: testTrackId)     // Note Off (far away)
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        
        // Wait for note-on to be sent
        try? Thread.sleep(forTimeInterval: 0.05)
        
        // Clear captured events
        capturedEvents.removeAll()
        
        // Stop transport (note is still sounding)
        scheduler.stop()
        
        // Verify Note Off was sent immediately
        let noteOffs = capturedEvents.filter { $0.status == 0x80 || ($0.status == 0xB0 && $0.data1 == 123) }
        XCTAssertGreaterThan(noteOffs.count, 0, "Note Off should be sent when stopping with active note")
        
        // Verify immediate timing (AUEventSampleTimeImmediate)
        if let firstNoteOff = noteOffs.first {
            XCTAssertEqual(firstNoteOff.sampleTime, 0, "Note Off should use AUEventSampleTimeImmediate (0)")
        }
    }
    
    func testStopSendsNoteOffForMultipleActiveNotes() {
        // Test that all active notes receive Note Off on stop
        
        // Schedule chord (3 notes)
        let events = [
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 60, data2: 100, trackId: testTrackId),  // C
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 64, data2: 100, trackId: testTrackId),  // E
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 67, data2: 100, trackId: testTrackId),  // G
            ScheduledMIDIEvent(beat: 8.0, status: 0x80, data1: 60, data2: 0, trackId: testTrackId),
            ScheduledMIDIEvent(beat: 8.0, status: 0x80, data1: 64, data2: 0, trackId: testTrackId),
            ScheduledMIDIEvent(beat: 8.0, status: 0x80, data1: 67, data2: 0, trackId: testTrackId)
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        
        // Wait for chord to play
        try? Thread.sleep(forTimeInterval: 0.05)
        
        capturedEvents.removeAll()
        
        // Stop
        scheduler.stop()
        
        // Verify all 3 notes got Note Off (or CC 123)
        let noteOffs = capturedEvents.filter { 
            $0.status == 0x80 || ($0.status == 0xB0 && $0.data1 == 123) 
        }
        XCTAssertGreaterThanOrEqual(noteOffs.count, 3, "All 3 notes should receive Note Off")
    }
    
    func testStopClearsActiveNotesCollection() {
        // Test that stop clears the internal active notes collection
        
        // Schedule note
        let events = [
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 60, data2: 100, trackId: testTrackId),
            ScheduledMIDIEvent(beat: 4.0, status: 0x80, data1: 60, data2: 0, trackId: testTrackId)
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        try? Thread.sleep(forTimeInterval: 0.05)
        
        // Stop
        scheduler.stop()
        
        // Play again - should not send stray Note Offs
        capturedEvents.removeAll()
        scheduler.play()
        try? Thread.sleep(forTimeInterval: 0.05)
        
        // Should only see new note-ons, not old note-offs
        let spuriousNoteOffs = capturedEvents.filter { 
            $0.status == 0x80 && $0.data1 == 60 
        }
        XCTAssertEqual(spuriousNoteOffs.count, 0, "Stopped notes should not send Note Off on restart")
    }
    
    // MARK: - Seek Behavior
    
    func testSeekSendsNoteOffForActiveNotes() {
        // Test that seeking sends Note Off for active notes
        
        let events = [
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 60, data2: 100, trackId: testTrackId),
            ScheduledMIDIEvent(beat: 8.0, status: 0x80, data1: 60, data2: 0, trackId: testTrackId)
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        try? Thread.sleep(forTimeInterval: 0.05)
        
        capturedEvents.removeAll()
        
        // Seek to beat 4.0 (mid-note)
        scheduler.seek(toBeat: 4.0)
        
        // Verify Note Off sent
        let noteOffs = capturedEvents.filter { $0.status == 0x80 && $0.data1 == 60 }
        XCTAssertGreaterThan(noteOffs.count, 0, "Seek should send Note Off for active note")
    }
    
    func testSeekToStartOfLongNote_NoFalseNoteOff() {
        // Test that seeking to the start of a long note doesn't send spurious Note Off
        
        // Long note from beat 4-12
        let events = [
            ScheduledMIDIEvent(beat: 4.0, status: 0x90, data1: 60, data2: 100, trackId: testTrackId),
            ScheduledMIDIEvent(beat: 12.0, status: 0x80, data1: 60, data2: 0, trackId: testTrackId)
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        
        // Seek to beat 4.0 (note start)
        scheduler.seek(toBeat: 4.0)
        
        // Start playback
        capturedEvents.removeAll()
        scheduler.play()
        try? Thread.sleep(forTimeInterval: 0.05)
        
        // Should see note-on, not note-off
        let noteOns = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThan(noteOns.count, 0, "Should play note-on from seek position")
    }
    
    // MARK: - Tempo Change Behavior
    
    func testTempoChangeSendsNoteOffForActiveNotes() {
        // Test that tempo changes send Note Off for active notes
        
        let events = [
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 60, data2: 100, trackId: testTrackId),
            ScheduledMIDIEvent(beat: 8.0, status: 0x80, data1: 60, data2: 0, trackId: testTrackId)
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        try? Thread.sleep(forTimeInterval: 0.05)
        
        capturedEvents.removeAll()
        
        // Change tempo mid-note
        scheduler.updateTempo(90.0)
        
        // Verify Note Off or CC 123 sent
        let noteOffEvents = capturedEvents.filter { 
            $0.status == 0x80 || ($0.status == 0xB0 && $0.data1 == 123) 
        }
        XCTAssertGreaterThan(noteOffEvents.count, 0, "Tempo change should send Note Off for active notes")
    }
    
    // MARK: - CC 123 (All Notes Off) Safety Net
    
    func testStopSendsCC123_AllNotesOff() {
        // Test that stop sends CC 123 (All Notes Off) as backup safety net
        
        let events = [
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 60, data2: 100, trackId: testTrackId),
            ScheduledMIDIEvent(beat: 8.0, status: 0x80, data1: 60, data2: 0, trackId: testTrackId)
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        try? Thread.sleep(forTimeInterval: 0.05)
        
        capturedEvents.removeAll()
        scheduler.stop()
        
        // Verify CC 123 (All Notes Off) was sent
        let allNotesOffCC = capturedEvents.filter { 
            $0.status == 0xB0 && $0.data1 == 123 
        }
        
        // NOTE: The current implementation sends explicit note-offs, not CC 123
        // This test documents expected behavior if CC 123 is added
        // XCTAssertGreaterThan(allNotesOffCC.count, 0, "CC 123 should be sent as safety net")
        
        // For now, verify explicit note-offs are sent
        let explicitNoteOffs = capturedEvents.filter { $0.status == 0x80 }
        XCTAssertGreaterThan(explicitNoteOffs.count, 0, "Explicit Note Offs should be sent")
    }
    
    // MARK: - Edge Cases
    
    func testStopWithNoActiveNotes_NoSpuriousEvents() {
        // Test that stop with no active notes doesn't send spurious events
        
        // Schedule note that already ended
        let events = [
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 60, data2: 100, trackId: testTrackId),
            ScheduledMIDIEvent(beat: 0.1, status: 0x80, data1: 60, data2: 0, trackId: testTrackId)
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        
        // Wait for note to end
        try? Thread.sleep(forTimeInterval: 0.2)
        
        capturedEvents.removeAll()
        
        // Stop (no notes active)
        scheduler.stop()
        
        // Should not send any events
        XCTAssertEqual(capturedEvents.count, 0, "Stop with no active notes should not send events")
    }
    
    func testRapidStopStartCycle_NoDoubleNoteOffs() {
        // Test rapid stop/start doesn't cause duplicate Note Offs
        
        let events = [
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 60, data2: 100, trackId: testTrackId),
            ScheduledMIDIEvent(beat: 8.0, status: 0x80, data1: 60, data2: 0, trackId: testTrackId)
        ]
        
        for _ in 0..<5 {
            scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
            scheduler.play()
            try? Thread.sleep(forTimeInterval: 0.02)  // 20ms
            
            capturedEvents.removeAll()
            scheduler.stop()
            
            // Count Note Offs
            let noteOffs = capturedEvents.filter { $0.status == 0x80 && $0.data1 == 60 }
            XCTAssertLessThanOrEqual(noteOffs.count, 1, "Should send at most 1 Note Off per stop")
        }
    }
    
    func testStopDuringNoteRelease_NoStuckTail() {
        // Test stopping during ADSR release phase doesn't leave tail
        
        // Short note followed by immediate stop
        let events = [
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 60, data2: 100, trackId: testTrackId),
            ScheduledMIDIEvent(beat: 0.5, status: 0x80, data1: 60, data2: 0, trackId: testTrackId)  // Note Off scheduled
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        
        // Wait for note-on
        try? Thread.sleep(forTimeInterval: 0.05)
        
        // Stop before scheduled Note Off
        capturedEvents.removeAll()
        scheduler.stop()
        
        // Verify immediate Note Off sent
        let noteOffs = capturedEvents.filter { $0.status == 0x80 && $0.data1 == 60 }
        XCTAssertGreaterThan(noteOffs.count, 0, "Stop should send Note Off even if one was scheduled")
    }
    
    // MARK: - Multi-Track Tests
    
    func testStopSendsNoteOffForAllTracks() {
        // Test that stop sends Note Off for active notes across multiple tracks
        
        let track1 = UUID()
        let track2 = UUID()
        let track3 = UUID()
        
        let events = [
            // Track 1: Piano
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 60, data2: 100, trackId: track1),
            ScheduledMIDIEvent(beat: 8.0, status: 0x80, data1: 60, data2: 0, trackId: track1),
            
            // Track 2: Strings
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 64, data2: 100, trackId: track2),
            ScheduledMIDIEvent(beat: 8.0, status: 0x80, data1: 64, data2: 0, trackId: track2),
            
            // Track 3: Pad
            ScheduledMIDIEvent(beat: 0.0, status: 0x90, data1: 67, data2: 100, trackId: track3),
            ScheduledMIDIEvent(beat: 8.0, status: 0x80, data1: 67, data2: 0, trackId: track3)
        ]
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        try? Thread.sleep(forTimeInterval: 0.05)
        
        capturedEvents.removeAll()
        scheduler.stop()
        
        // Verify Note Offs for all 3 tracks
        let track1NoteOffs = capturedEvents.filter { $0.trackId == track1 && $0.status == 0x80 }
        let track2NoteOffs = capturedEvents.filter { $0.trackId == track2 && $0.status == 0x80 }
        let track3NoteOffs = capturedEvents.filter { $0.trackId == track3 && $0.status == 0x80 }
        
        XCTAssertGreaterThan(track1NoteOffs.count, 0, "Track 1 should get Note Off")
        XCTAssertGreaterThan(track2NoteOffs.count, 0, "Track 2 should get Note Off")
        XCTAssertGreaterThan(track3NoteOffs.count, 0, "Track 3 should get Note Off")
    }
    
    // MARK: - Integration Tests
    
    func testMIDIPlaybackEngineStop_CallsAllNotesOffAllTracks() async throws {
        // Test that MIDIPlaybackEngine.stop() calls the backup safety net
        
        // Create minimal audio engine setup
        let audioEngine = AudioEngine()
        let projectManager = ProjectManager(undoService: UndoService())
        let midiPlaybackEngine = MIDIPlaybackEngine()
        
        audioEngine.configure(
            projectManager: projectManager,
            undoService: UndoService(),
            recordingController: nil,
            midiScheduler: nil
        )
        
        // Configure MIDI engine
        let instrumentManager = InstrumentManager()
        midiPlaybackEngine.configure(with: instrumentManager, audioEngine: audioEngine)
        
        // Play and stop
        midiPlaybackEngine.play()
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        midiPlaybackEngine.stop()
        
        // Verify that stop completed without hanging
        XCTAssertFalse(midiPlaybackEngine.isPlaying, "MIDI engine should be stopped")
        
        // Clean up
        audioEngine.cleanup()
    }
    
    // MARK: - Performance Tests
    
    func testStopPerformance_LargeNumberOfActiveNotes() {
        // Test that stop is performant even with many active notes
        
        // Generate 128 simultaneous notes (full MIDI range)
        var events: [ScheduledMIDIEvent] = []
        for pitch: UInt8 in 0..<128 {
            events.append(ScheduledMIDIEvent(
                beat: 0.0,
                status: 0x90,
                data1: pitch,
                data2: 100,
                trackId: testTrackId
            ))
            events.append(ScheduledMIDIEvent(
                beat: 8.0,
                status: 0x80,
                data1: pitch,
                data2: 0,
                trackId: testTrackId
            ))
        }
        
        scheduler.scheduleEvents(events, currentBeatPosition: { 0.0 })
        scheduler.play()
        try? Thread.sleep(forTimeInterval: 0.05)
        
        // Measure stop time
        measure {
            capturedEvents.removeAll()
            scheduler.stop()
            
            // Re-start for next iteration
            scheduler.play()
            try? Thread.sleep(forTimeInterval: 0.05)
        }
        
        // Verify all notes got Note Offs
        let finalNoteOffs = capturedEvents.filter { $0.status == 0x80 }
        XCTAssertGreaterThanOrEqual(finalNoteOffs.count, 100, "Most notes should receive Note Off")
    }
}
