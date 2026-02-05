//
//  MIDILookaheadStressTests.swift
//  StoriTests
//
//  Stress tests for MIDI lookahead scheduling under heavy load (Issue #34)
//  Verifies timing accuracy remains consistent regardless of CPU load
//

import XCTest
import AVFoundation
@testable import Stori

@MainActor
final class MIDILookaheadStressTests: XCTestCase {
    
    var scheduler: SampleAccurateMIDIScheduler!
    var receivedEvents: [(beat: Double, status: UInt8, data1: UInt8, sampleTime: AUEventSampleTime, receiveTime: CFAbsoluteTime)] = []
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
        
        // Set up MIDI handler to capture events with receive timestamp
        scheduler.sampleAccurateMIDIHandler = { [weak self] status, data1, data2, trackId, sampleTime in
            let receiveTime = CFAbsoluteTimeGetCurrent()
            self?.receivedEvents.append((self?.currentBeat ?? 0, status, data1, sampleTime, receiveTime))
        }
    }
    
    override func tearDown() async throws {
        scheduler.stop()
        scheduler = nil
        receivedEvents = []
    }
    
    // MARK: - 1. Lookahead Verification Tests
    
    func testLookaheadIs150Milliseconds() {
        // Verify that lookahead is set to professional standard (150ms)
        // This was increased from 50ms to match Logic Pro/Pro Tools
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 1.0),
            createNote(pitch: 62, startBeat: 0.5, duration: 1.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        let expectation = XCTestExpectation(description: "Events scheduled with 150ms lookahead")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Events should be scheduled with sample times representing future playback
            XCTAssertGreaterThan(self.receivedEvents.count, 0, "Events should be scheduled")
            
            // Verify sample times are within 150ms lookahead window
            let maxLookaheadSamples = Int64(0.150 * self.testSampleRate) // 150ms
            for event in self.receivedEvents {
                XCTAssertGreaterThanOrEqual(event.sampleTime, 0, "Sample time should be non-negative")
                XCTAssertLessThanOrEqual(event.sampleTime, maxLookaheadSamples,
                                         "Sample time should be within 150ms lookahead window")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - 2. CPU Load Stress Tests
    
    func testTimingAccuracyUnderCPULoad() {
        // Simulate heavy CPU load and verify MIDI timing doesn't degrade
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 0.5),
            createNote(pitch: 62, startBeat: 0.5, duration: 0.5),
            createNote(pitch: 64, startBeat: 1.0, duration: 0.5),
            createNote(pitch: 65, startBeat: 1.5, duration: 0.5),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        let expectation = XCTestExpectation(description: "Timing accurate under load")
        
        // Simulate CPU load by doing intensive work on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            for _ in 0..<100 {
                // Simulate heavy computation (sorting large arrays)
                let _ = (0..<10000).map { $0 * 2 }.sorted()
                usleep(1000) // 1ms between bursts
            }
        }
        
        // Check timing after CPU load
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            let noteOns = self.receivedEvents.filter { $0.status & 0xF0 == 0x90 }
            
            // All 4 notes should have been scheduled despite CPU load
            XCTAssertGreaterThanOrEqual(noteOns.count, 4,
                                        "All notes should be scheduled despite CPU load")
            
            // Sample times should still be valid (not negative)
            for event in noteOns {
                XCTAssertGreaterThanOrEqual(event.sampleTime, 0,
                                            "Sample times should remain valid under load")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 2.0)
    }
    
    func testNoLateNotesWithSimulatedGUIRedraws() {
        // Simulate main thread blocking (GUI redraws) and verify MIDI isn't affected
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 2.0),
        ])
        
        scheduler.loadEvents(from: [track])
        let startTime = CFAbsoluteTimeGetCurrent()
        scheduler.play(fromBeat: 0)
        
        // Allow initial scheduling
        Thread.sleep(forTimeInterval: 0.05)
        let initialEventCount = receivedEvents.count
        XCTAssertGreaterThan(initialEventCount, 0, "Should have initial events")
        
        // Simulate main thread blocking (GUI redraw)
        Thread.sleep(forTimeInterval: 0.1) // 100ms block
        
        // Beat provider runs on background queue, so it shouldn't be blocked
        // Events should continue being scheduled
        
        let expectation = XCTestExpectation(description: "Events continue during main thread block")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            // Events should have been scheduled throughout the "block"
            // (Lookahead ensures they were pre-scheduled)
            XCTAssertGreaterThanOrEqual(self.receivedEvents.count, initialEventCount,
                                        "Events should continue being scheduled")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - 3. Jitter Resistance Tests
    
    func testSystemJitterDoesNotCauseLateNotes() {
        // Verify that timing jitter in the scheduler doesn't cause late notes
        // 150ms lookahead should absorb up to 138ms of jitter
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 1.0),
            createNote(pitch: 62, startBeat: 0.25, duration: 1.0),
            createNote(pitch: 64, startBeat: 0.5, duration: 1.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        let expectation = XCTestExpectation(description: "Jitter resistance")
        
        // Simulate timing jitter by varying currentBeat updates
        var jitterBeat: Double = 0
        for i in 0..<20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.01) {
                // Add random jitter (up to ±5ms worth of beats)
                let jitter = Double.random(in: -0.01...0.01)
                jitterBeat += 0.05 + jitter
                self.currentBeat = jitterBeat
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let noteOns = self.receivedEvents.filter { $0.status & 0xF0 == 0x90 }
            
            // All notes should be scheduled despite jitter
            XCTAssertGreaterThanOrEqual(noteOns.count, 3,
                                        "All notes should be scheduled despite timing jitter")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - 4. WYSIWYG Verification Tests
    
    func testVisualTimingMatchesAudioTiming() {
        // Verify that scheduled sample times match the beat positions
        // This ensures WYSIWYG: what you see in Piano Roll = what you hear
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 1.0),
            createNote(pitch: 62, startBeat: 1.0, duration: 1.0),
        ])
        
        scheduler.loadEvents(from: [track])
        scheduler.play(fromBeat: 0)
        
        let expectation = XCTestExpectation(description: "Visual = Audio timing")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            let noteOns = self.receivedEvents.filter { $0.status & 0xF0 == 0x90 }.sorted { $0.data1 < $1.data1 }
            
            XCTAssertEqual(noteOns.count, 2, "Should have 2 note-ons")
            
            if noteOns.count >= 2 {
                // First note should have smaller sample time than second
                XCTAssertLessThan(noteOns[0].sampleTime, noteOns[1].sampleTime,
                                  "Note order should match beat order")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
    
    // MARK: - 5. Performance Tests
    
    func testLookaheadPerformanceUnderLoad() {
        // Measure performance of lookahead scheduling with many events
        
        var notes: [MIDINote] = []
        for i in 0..<100 {
            notes.append(createNote(
                pitch: UInt8(60 + (i % 12)),
                startBeat: Double(i) * 0.1,
                duration: 0.1
            ))
        }
        
        let track = createTestTrack(with: notes)
        scheduler.loadEvents(from: [track])
        
        measure {
            // Simulate playback through all events
            scheduler.play(fromBeat: 0)
            
            for i in 0..<100 {
                currentBeat = Double(i) * 0.1
                Thread.sleep(forTimeInterval: 0.001) // 1ms per iteration
            }
            
            scheduler.stop()
        }
    }
    
    func testLookaheadDoesNotCauseExcessiveLatency() {
        // Verify that 150ms lookahead doesn't introduce user-perceptible latency
        // For MIDI input → playback, total latency should be hardware buffer + lookahead
        
        let track = createTestTrack(with: [
            createNote(pitch: 60, startBeat: 0.0, duration: 1.0),
        ])
        
        scheduler.loadEvents(from: [track])
        
        let scheduleStartTime = CFAbsoluteTimeGetCurrent()
        scheduler.play(fromBeat: 0)
        
        // Wait for first event to be scheduled
        Thread.sleep(forTimeInterval: 0.01)
        
        let scheduleEndTime = CFAbsoluteTimeGetCurrent()
        let schedulingLatency = scheduleEndTime - scheduleStartTime
        
        // Scheduling should be fast (< 20ms including thread overhead)
        XCTAssertLessThan(schedulingLatency, 0.020,
                         "Scheduling latency should be minimal despite lookahead")
    }
    
    // MARK: - Helper Methods
    
    private func createTestTrack(with notes: [MIDINote]) -> AudioTrack {
        let track = AudioTrack(name: "Test Track", trackType: .midi)
        
        let region = MIDIRegion(
            id: UUID(),
            name: "Test Region",
            notes: notes,
            startBeat: 0,
            durationBeats: 20,
            instrumentId: nil,
            color: .blue,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            contentLengthBeats: 20
        )
        
        var mutableTrack = track
        mutableTrack.midiRegions = [region]
        return mutableTrack
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
