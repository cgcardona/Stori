//
//  MIDITimingReferenceTests.swift
//  StoriTests
//
//  Tests for MIDI timing reference staleness detection and sample time calculation.
//

import XCTest
import AVFoundation
@testable import Stori

final class MIDITimingReferenceTests: XCTestCase {
    
    let sampleRate: Double = 48000
    let tempo: Double = 120
    
    // MARK: - Basic Timing Tests
    
    func testCalculatesSampleTimeForFutureBeat() {
        let reference = MIDITimingReference.now(
            beat: 0,
            tempo: tempo,
            sampleRate: sampleRate
        )
        
        // Calculate sample time for beat 1 (0.5 seconds at 120 BPM)
        let sampleTime = reference.sampleTime(forBeat: 1.0)
        
        // Should be positive (future)
        XCTAssertGreaterThan(sampleTime, 0, "Future beat should have positive sample time")
        
        // Should be approximately 0.5s * 48000 = 24000 samples
        // Allow tolerance for measurement overhead
        XCTAssertGreaterThan(sampleTime, 20000, "Should be roughly 24000 samples")
        XCTAssertLessThan(sampleTime, 28000, "Should be roughly 24000 samples")
    }
    
    func testCalculatesSampleTimeForPastBeat() {
        let reference = MIDITimingReference.now(
            beat: 10,
            tempo: tempo,
            sampleRate: sampleRate
        )
        
        // Calculate sample time for beat 5 (past)
        let sampleTime = reference.sampleTime(forBeat: 5.0)
        
        // Should be 0 (clamped, not negative)
        XCTAssertEqual(sampleTime, 0, "Past beat should return immediate (0)")
    }
    
    func testIsInPastDetectsPastBeats() {
        let reference = MIDITimingReference.now(
            beat: 10,
            tempo: tempo,
            sampleRate: sampleRate
        )
        
        XCTAssertTrue(reference.isInPast(beat: 5.0), "Beat 5 should be in past when reference is at beat 10")
        XCTAssertFalse(reference.isInPast(beat: 15.0), "Beat 15 should be in future when reference is at beat 10")
    }
    
    // MARK: - Staleness Detection Tests
    
    func testFreshReferenceIsNotStale() {
        let reference = MIDITimingReference.now(
            beat: 0,
            tempo: tempo,
            sampleRate: sampleRate
        )
        
        XCTAssertFalse(reference.isStale, "Fresh reference should not be stale")
    }
    
    func testOldReferenceIsStale() async throws {
        // Create reference that's "old" by manipulating date
        // We can't actually wait 10 seconds in a test, so this tests the logic
        
        // Create a reference manually with old date
        let oldReference = MIDITimingReference(
            hostTime: mach_absolute_time(),
            createdAt: Date().addingTimeInterval(-15),  // 15 seconds ago
            beatPosition: 0,
            tempo: tempo,
            sampleRate: sampleRate
        )
        
        XCTAssertTrue(oldReference.isStale, "Reference older than 10s should be stale")
    }
    
    func testStaleReferenceReturnsSampleTimeImmediate() {
        let staleReference = MIDITimingReference(
            hostTime: mach_absolute_time(),
            createdAt: Date().addingTimeInterval(-15),  // Old
            beatPosition: 0,
            tempo: tempo,
            sampleRate: sampleRate
        )
        
        let sampleTime = staleReference.sampleTime(forBeat: 10.0)
        
        XCTAssertEqual(sampleTime, AUEventSampleTimeImmediate, "Stale reference should return immediate")
    }
    
    // MARK: - Tempo Variation Tests
    
    func testCalculatesCorrectlyAtDifferentTempos() {
        let tempos = [60.0, 120.0, 140.0, 180.0]
        
        for testTempo in tempos {
            let reference = MIDITimingReference.now(
                beat: 0,
                tempo: testTempo,
                sampleRate: sampleRate
            )
            
            // 1 beat should be (60/tempo) seconds
            let expectedSeconds = 60.0 / testTempo
            let expectedSamples = expectedSeconds * sampleRate
            
            let sampleTime = reference.sampleTime(forBeat: 1.0)
            
            // Allow 10% tolerance for measurement overhead
            let tolerance = expectedSamples * 0.1
            XCTAssertGreaterThan(Double(sampleTime), expectedSamples - tolerance,
                                "Sample time at \(Int(testTempo)) BPM should be ~\(Int(expectedSamples))")
            XCTAssertLessThan(Double(sampleTime), expectedSamples + tolerance,
                             "Sample time at \(Int(testTempo)) BPM should be ~\(Int(expectedSamples))")
        }
    }
    
    // MARK: - Sample Rate Variation Tests
    
    func testCalculatesCorrectlyAtDifferentSampleRates() {
        let sampleRates = [44100.0, 48000.0, 96000.0]
        
        for testRate in sampleRates {
            let reference = MIDITimingReference.now(
                beat: 0,
                tempo: 120,
                sampleRate: testRate
            )
            
            // At 120 BPM, 1 beat = 0.5 seconds
            let expectedSamples = 0.5 * testRate
            
            let sampleTime = reference.sampleTime(forBeat: 1.0)
            
            // Allow 10% tolerance
            let tolerance = expectedSamples * 0.1
            XCTAssertGreaterThan(Double(sampleTime), expectedSamples - tolerance,
                                "Sample time at \(Int(testRate))Hz should be ~\(Int(expectedSamples))")
            XCTAssertLessThan(Double(sampleTime), expectedSamples + tolerance,
                             "Sample time at \(Int(testRate))Hz should be ~\(Int(expectedSamples))")
        }
    }
    
    // MARK: - Edge Case Tests
    
    func testHandlesZeroBeat() {
        let reference = MIDITimingReference.now(
            beat: 0,
            tempo: tempo,
            sampleRate: sampleRate
        )
        
        let sampleTime = reference.sampleTime(forBeat: 0)
        
        // Should be immediate (or very close to 0)
        XCTAssertLessThan(sampleTime, 100, "Beat 0 should schedule very soon")
    }
    
    func testHandlesLargeBeats() {
        let reference = MIDITimingReference.now(
            beat: 0,
            tempo: tempo,
            sampleRate: sampleRate
        )
        
        // Test with beat 1000 (8.33 minutes at 120 BPM)
        let sampleTime = reference.sampleTime(forBeat: 1000)
        
        // Should be positive and reasonable
        XCTAssertGreaterThan(sampleTime, 0, "Large beat should have positive sample time")
        
        // At 120 BPM, 1000 beats = 500 seconds = 24,000,000 samples at 48kHz
        let expectedSamples: Int64 = 24_000_000
        let tolerance: Int64 = 1_000_000  // 1M samples tolerance (~20s)
        XCTAssertGreaterThan(sampleTime, expectedSamples - tolerance)
        XCTAssertLessThan(sampleTime, expectedSamples + tolerance)
    }
}
