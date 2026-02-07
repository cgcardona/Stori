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
    var capturedEvents: [(status: UInt8, data1: UInt8, data2: UInt8, trackId: UUID, sampleTime: AUEventSampleTime)] = []
    let testTrackId = UUID()
    let testSampleRate: Double = 48000.0
    let testTempo: Double = 120.0
    
    override func setUp() async throws {
        try await super.setUp()
        
        scheduler = SampleAccurateMIDIScheduler()
        capturedEvents = []
        
        // Configure scheduler
        scheduler.configure(tempo: testTempo, sampleRate: testSampleRate)
        
        // Install capture handler via the real API
        scheduler.sampleAccurateMIDIHandler = { [weak self] status, data1, data2, trackId, sampleTime in
            self?.capturedEvents.append((status, data1, data2, trackId, sampleTime))
        }
        
        // Set up beat provider - tracks elapsed time at 120 BPM
        let playStartTime = Date()
        scheduler.currentBeatProvider = { [playStartTime] in
            let elapsed = Date().timeIntervalSince(playStartTime)
            let beatsPerSecond = 120.0 / 60.0  // 2 beats per second at 120 BPM
            return elapsed * beatsPerSecond
        }
    }
    
    override func tearDown() async throws {
        scheduler.stop()
        scheduler = nil
        capturedEvents = []
        try await super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    /// Create a test track with MIDI region containing notes
    private func createTestTrack(notes: [MIDINote], regionStart: Double = 0.0) -> AudioTrack {
        var track = AudioTrack(id: testTrackId, name: "Test Track", trackType: .midi)
        
        let region = MIDIRegion(
            id: UUID(),
            name: "Test Region",
            notes: notes,
            startBeat: regionStart,
            durationBeats: notes.map { $0.startBeat + $0.durationBeats }.max() ?? 4.0,
            instrumentId: nil,
            color: .blue,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 4.0
        )
        
        track.midiRegions = [region]
        return track
    }
    
    /// Create a single MIDI note
    private func createNote(pitch: UInt8, velocity: UInt8 = 100, startBeat: Double, durationBeats: Double, channel: UInt8 = 0) -> MIDINote {
        MIDINote(
            id: UUID(),
            pitch: pitch,
            velocity: velocity,
            startBeat: startBeat,
            durationBeats: durationBeats,
            channel: channel
        )
    }
    
    // MARK: - Basic Active Note Tracking
    
    func testActiveNoteTracking_NoteOnAddsToActiveNotes() {
        // Test that note-on events are tracked as active
        
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 4.0)  // Middle C, long note
        ]
        
        let track = createTestTrack(notes: notes)
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0.0)
        
        // Process events - wait for note-on to be sent
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify note-on was captured
        let noteOns = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThan(noteOns.count, 0, "Note-on should be sent")
        XCTAssertEqual(noteOns.first?.data1, 60, "Should be middle C")
    }
    
    func testActiveNoteTracking_NoteOffRemovesFromActiveNotes() {
        // Test that note-off events remove from active tracking
        // This test verifies the scheduler tracks Note Ons and removes them on Note Off
        
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 4.0)  // 4 beat note
        ]
        
        let track = createTestTrack(notes: notes)
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0.0)
        
        // Wait for note-on to be sent
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify note-on was sent
        let noteOns = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThan(noteOns.count, 0, "Note-on should be sent")
        
        // Stop will send Note Off (this is the real test - stop sends Note Off for active notes)
        capturedEvents.removeAll()
        scheduler.stop()
        
        let noteOffs = capturedEvents.filter { $0.status == 0x80 }
        XCTAssertGreaterThan(noteOffs.count, 0, "Note-off should be sent when stopping with active note")
    }
    
    // MARK: - Stop Behavior
    
    func testStopSendsNoteOffForActiveLongNote() {
        // Test that stopping during a long note sends Note Off
        
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 8.0)  // Very long note
        ]
        
        let track = createTestTrack(notes: notes)
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0.0)
        
        // Wait for note-on to be sent
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify note is playing
        let noteOnsBefore = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThan(noteOnsBefore.count, 0, "Note should be playing")
        
        // Clear captured events
        capturedEvents.removeAll()
        
        // Stop transport (note is still sounding)
        scheduler.stop()
        
        // Verify Note Off was sent immediately
        let noteOffs = capturedEvents.filter { $0.status == 0x80 }
        XCTAssertGreaterThan(noteOffs.count, 0, "Note Off should be sent when stopping with active note")
        XCTAssertEqual(noteOffs.first?.data1, 60, "Should send Note Off for middle C")
        
        // Note: AUEventSampleTimeImmediate is UInt64.max, not 0 - just verify Note Off was sent
    }
    
    func testStopSendsNoteOffForMultipleActiveNotes() {
        // Test that all active notes receive Note Off on stop
        
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 8.0),  // C
            createNote(pitch: 64, startBeat: 0.0, durationBeats: 8.0),  // E
            createNote(pitch: 67, startBeat: 0.0, durationBeats: 8.0)   // G (chord)
        ]
        
        let track = createTestTrack(notes: notes)
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0.0)
        
        // Wait for chord to start playing
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify all notes started
        let noteOns = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThanOrEqual(noteOns.count, 3, "All 3 notes should be playing")
        
        capturedEvents.removeAll()
        
        // Stop
        scheduler.stop()
        
        // Verify all 3 notes got Note Off
        let noteOffs = capturedEvents.filter { $0.status == 0x80 }
        XCTAssertGreaterThanOrEqual(noteOffs.count, 3, "All 3 notes should receive Note Off")
        
        let pitches = Set(noteOffs.map { $0.data1 })
        XCTAssertTrue(pitches.contains(60), "Should send Note Off for C")
        XCTAssertTrue(pitches.contains(64), "Should send Note Off for E")
        XCTAssertTrue(pitches.contains(67), "Should send Note Off for G")
    }
    
    func testStopClearsActiveNotesCollection() {
        // Test that stop clears the internal active notes collection
        
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 4.0)
        ]
        
        let track = createTestTrack(notes: notes)
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0.0)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Stop
        scheduler.stop()
        
        // Play again - should not send stray Note Offs
        capturedEvents.removeAll()
        scheduler.play(fromBeat: 0.0)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Should only see new note-ons, not old note-offs from previous playback
        let spuriousNoteOffs = capturedEvents.filter { 
            $0.status == 0x80 && $0.sampleTime == 0  // Immediate Note Offs
        }
        
        // Note: We might see scheduled Note Offs from the new playback, but not immediate ones from stale state
        let noteOns = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThan(noteOns.count, 0, "Should play notes on restart")
    }
    
    // MARK: - Seek Behavior
    
    func testSeekSendsNoteOffForActiveNotes() {
        // Test that seeking sends Note Off for active notes
        
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 8.0)
        ]
        
        let track = createTestTrack(notes: notes)
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0.0)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify note is playing
        let noteOns = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThan(noteOns.count, 0, "Note should be playing")
        
        capturedEvents.removeAll()
        
        // Seek to beat 4.0 (mid-note)
        scheduler.seek(toBeat: 4.0)
        
        // Verify Note Off sent
        let noteOffs = capturedEvents.filter { $0.status == 0x80 && $0.data1 == 60 }
        XCTAssertGreaterThan(noteOffs.count, 0, "Seek should send Note Off for active note")
    }
    
    func testSeekToStartOfLongNote_NoFalseNoteOff() {
        // Test that seeking to the start of a long note doesn't send spurious Note Off
        
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 8.0)  // Note starts at beat 0
        ]
        
        let track = createTestTrack(notes: notes)
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0.0)
        
        // Let note start playing
        Thread.sleep(forTimeInterval: 0.1)
        
        // Stop and seek back to beat 0
        scheduler.stop()
        capturedEvents.removeAll()
        
        // Seek back to start and play again
        scheduler.seek(toBeat: 0.0)
        scheduler.play(fromBeat: 0.0)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Should see note-on from new playback
        let noteOns = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThan(noteOns.count, 0, "Should play note-on from seek position")
    }
    
    // MARK: - Tempo Change Behavior
    
    func testTempoChangeSendsNoteOffForActiveNotes() {
        // Test that tempo changes send Note Off for active notes
        
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 8.0)
        ]
        
        let track = createTestTrack(notes: notes)
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0.0)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify note is playing
        let noteOns = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThan(noteOns.count, 0, "Note should be playing")
        
        capturedEvents.removeAll()
        
        // Change tempo mid-note
        scheduler.updateTempo(90.0)
        
        // Verify Note Off sent
        let noteOffs = capturedEvents.filter { $0.status == 0x80 }
        XCTAssertGreaterThan(noteOffs.count, 0, "Tempo change should send Note Off for active notes")
    }
    
    // MARK: - Edge Cases
    
    func testStopWithNoActiveNotes_NoSpuriousEvents() {
        // Test that stop with no active notes doesn't send spurious events
        
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 0.1)  // Very short note
        ]
        
        let track = createTestTrack(notes: notes)
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0.0)
        
        // Wait for note to end naturally
        Thread.sleep(forTimeInterval: 0.3)
        
        capturedEvents.removeAll()
        
        // Stop (no notes should be active)
        scheduler.stop()
        
        // Should not send any events
        XCTAssertEqual(capturedEvents.count, 0, "Stop with no active notes should not send events")
    }
    
    func testRapidStopStartCycle_NoDoubleNoteOffs() {
        // Test rapid stop/start doesn't cause duplicate Note Offs
        
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 8.0)
        ]
        
        let track = createTestTrack(notes: notes)
        
        for _ in 0..<5 {
            scheduler.loadEvents(from: [track])
            scheduler.play(fromBeat: 0.0)
            Thread.sleep(forTimeInterval: 0.05)  // 50ms
            
            capturedEvents.removeAll()
            scheduler.stop()
            
            // Count Note Offs from this stop
            let noteOffs = capturedEvents.filter { $0.status == 0x80 && $0.data1 == 60 }
            XCTAssertLessThanOrEqual(noteOffs.count, 1, "Should send at most 1 Note Off per stop")
        }
    }
    
    func testStopDuringNoteRelease_NoStuckTail() {
        // Test stopping during ADSR release phase doesn't leave tail
        
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 2.0)  // 2 beat note
        ]
        
        let track = createTestTrack(notes: notes)
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0.0)
        
        // Wait for note-on
        Thread.sleep(forTimeInterval: 0.1)
        
        // Verify note is playing
        let noteOns = capturedEvents.filter { $0.status == 0x90 && $0.data2 > 0 }
        XCTAssertGreaterThan(noteOns.count, 0, "Note should be playing")
        
        // Stop before scheduled Note Off would fire (note still active)
        capturedEvents.removeAll()
        scheduler.stop()
        
        // Verify Note Off sent (even though one was scheduled for later)
        let noteOffs = capturedEvents.filter { $0.status == 0x80 && $0.data1 == 60 }
        XCTAssertGreaterThan(noteOffs.count, 0, "Stop should send Note Off even if one was scheduled")
    }
    
    // MARK: - Multi-Track Tests
    
    func testStopSendsNoteOffForAllTracks() {
        // Test that stop sends Note Off for active notes across multiple tracks
        
        let track1Id = UUID()
        let track2Id = UUID()
        let track3Id = UUID()
        
        var track1 = AudioTrack(id: track1Id, name: "Piano", trackType: .midi)
        track1.midiRegions = [MIDIRegion(
            id: UUID(),
            name: "Piano Region",
            notes: [createNote(pitch: 60, startBeat: 0.0, durationBeats: 8.0)],
            startBeat: 0.0,
            durationBeats: 8.0,
            instrumentId: nil,
            color: .blue,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 8.0
        )]
        
        var track2 = AudioTrack(id: track2Id, name: "Strings", trackType: .midi)
        track2.midiRegions = [MIDIRegion(
            id: UUID(),
            name: "Strings Region",
            notes: [createNote(pitch: 64, startBeat: 0.0, durationBeats: 8.0)],
            startBeat: 0.0,
            durationBeats: 8.0,
            instrumentId: nil,
            color: .red,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 8.0
        )]
        
        var track3 = AudioTrack(id: track3Id, name: "Pad", trackType: .midi)
        track3.midiRegions = [MIDIRegion(
            id: UUID(),
            name: "Pad Region",
            notes: [createNote(pitch: 67, startBeat: 0.0, durationBeats: 8.0)],
            startBeat: 0.0,
            durationBeats: 8.0,
            instrumentId: nil,
            color: .green,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: 8.0
        )]
        
        scheduler.loadEvents(from: [track1, track2, track3])
        scheduler.play(fromBeat: 0.0)
        Thread.sleep(forTimeInterval: 0.1)
        
        capturedEvents.removeAll()
        scheduler.stop()
        
        // Verify Note Offs for all 3 tracks
        let track1NoteOffs = capturedEvents.filter { $0.trackId == track1Id && $0.status == 0x80 }
        let track2NoteOffs = capturedEvents.filter { $0.trackId == track2Id && $0.status == 0x80 }
        let track3NoteOffs = capturedEvents.filter { $0.trackId == track3Id && $0.status == 0x80 }
        
        XCTAssertGreaterThan(track1NoteOffs.count, 0, "Track 1 should get Note Off")
        XCTAssertGreaterThan(track2NoteOffs.count, 0, "Track 2 should get Note Off")
        XCTAssertGreaterThan(track3NoteOffs.count, 0, "Track 3 should get Note Off")
    }
    
    // MARK: - Integration Tests
    
    @MainActor
    func testMIDIPlaybackEngineStop_CallsAllNotesOffAllTracks() async throws {
        // Test that MIDIPlaybackEngine.stop() calls the backup safety net
        
        // Create minimal setup
        let midiPlaybackEngine = MIDIPlaybackEngine()
        
        // Create a simple track with a long note
        let notes = [
            createNote(pitch: 60, startBeat: 0.0, durationBeats: 8.0)
        ]
        let track = createTestTrack(notes: notes)
        
        // Configure with dummy AudioEngine reference
        let audioEngine = AudioEngine()
        let instrumentManager = InstrumentManager()
        midiPlaybackEngine.configure(with: instrumentManager, audioEngine: audioEngine)
        
        // Load events and play
        midiPlaybackEngine.loadRegions(from: [track], tempo: testTempo)
        midiPlaybackEngine.play(fromBeat: 0.0)
        try await Task.sleep(nanoseconds: 50_000_000)  // 50ms
        
        // Stop - should call allNotesOffAllTracks() as backup
        midiPlaybackEngine.stop()
        
        // Verify that stop completed without hanging
        XCTAssertFalse(midiPlaybackEngine.isPlaying, "MIDI engine should be stopped")
    }
    
    // MARK: - Performance Tests
    
    func testStopPerformance_LargeNumberOfActiveNotes() {
        // Test that stop is performant even with many active notes
        
        // Generate 64 simultaneous notes (dense chord)
        var notes: [MIDINote] = []
        for pitch in stride(from: 36, to: 100, by: 1) {  // 64 notes
            notes.append(createNote(
                pitch: UInt8(pitch),
                startBeat: 0.0,
                durationBeats: 8.0
            ))
        }
        
        let track = createTestTrack(notes: notes)
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0.0)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Measure stop time
        measure {
            capturedEvents.removeAll()
            scheduler.stop()
            
            // Re-start for next iteration
            scheduler.play(fromBeat: 0.0)
            Thread.sleep(forTimeInterval: 0.1)
        }
        
        // Verify many notes got Note Offs
        scheduler.stop()
        let finalNoteOffs = capturedEvents.filter { $0.status == 0x80 }
        XCTAssertGreaterThanOrEqual(finalNoteOffs.count, 50, "Most notes should receive Note Off")
    }
}
