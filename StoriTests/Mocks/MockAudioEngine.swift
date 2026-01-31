//
//  MockAudioEngine.swift
//  StoriTests
//
//  Mock implementation of AudioEngine for testing.
//  Simulates audio engine behavior without actual audio hardware.
//

import Foundation
import AVFoundation
@testable import Stori

/// Mock AudioEngine for unit testing
/// Provides controllable audio engine behavior without requiring audio hardware
@MainActor
final class MockAudioEngine {
    // MARK: - Transport State
    
    var isPlaying = false
    var isRecording = false
    var currentPositionBeats: Double = 0.0
    var tempo: Double = 120.0
    
    // MARK: - Cycle/Loop State
    
    var cycleEnabled = false
    var cycleStartBeat: Double = 0.0
    var cycleEndBeat: Double = 4.0
    
    // MARK: - Metronome
    
    var metronomeEnabled = false
    var metronomeVolume: Float = 0.7
    
    // MARK: - Track State
    
    var trackVolumes: [UUID: Float] = [:]
    var trackPans: [UUID: Float] = [:]
    var trackMutes: [UUID: Bool] = [:]
    var trackSolos: [UUID: Bool] = [:]
    
    // MARK: - Call Tracking
    
    var playCallCount = 0
    var stopCallCount = 0
    var pauseCallCount = 0
    var recordCallCount = 0
    var seekCallCount = 0
    
    var lastSeekPosition: Double?
    
    // MARK: - Error Simulation
    
    var shouldFailPlay = false
    var shouldFailRecord = false
    var playError: Error?
    var recordError: Error?
    
    // MARK: - Transport Methods
    
    func play() throws {
        playCallCount += 1
        
        if shouldFailPlay {
            throw playError ?? TestError.mockFailure("Play failed")
        }
        
        isPlaying = true
    }
    
    func stop() {
        stopCallCount += 1
        isPlaying = false
        isRecording = false
    }
    
    func pause() {
        pauseCallCount += 1
        isPlaying = false
    }
    
    func startRecording() throws {
        recordCallCount += 1
        
        if shouldFailRecord {
            throw recordError ?? TestError.mockFailure("Record failed")
        }
        
        isRecording = true
        isPlaying = true
    }
    
    func seek(toBeats position: Double) {
        seekCallCount += 1
        lastSeekPosition = position
        currentPositionBeats = max(0, position)
    }
    
    // MARK: - Cycle Methods
    
    func setCycle(enabled: Bool, start: Double, end: Double) {
        cycleEnabled = enabled
        cycleStartBeat = start
        cycleEndBeat = end
    }
    
    // MARK: - Track Methods
    
    func setTrackVolume(_ trackId: UUID, volume: Float) {
        trackVolumes[trackId] = max(0, min(1, volume))
    }
    
    func setTrackPan(_ trackId: UUID, pan: Float) {
        trackPans[trackId] = max(-1, min(1, pan))
    }
    
    func setTrackMute(_ trackId: UUID, muted: Bool) {
        trackMutes[trackId] = muted
    }
    
    func setTrackSolo(_ trackId: UUID, soloed: Bool) {
        trackSolos[trackId] = soloed
    }
    
    // MARK: - Metering (Simulated)
    
    func getTrackLevel(_ trackId: UUID) -> Float {
        // Return simulated level based on playing state
        if isPlaying && trackMutes[trackId] != true {
            return Float.random(in: -60...0)  // dB level
        }
        return -Float.infinity
    }
    
    func getMasterLevel() -> (left: Float, right: Float) {
        if isPlaying {
            return (Float.random(in: -60...0), Float.random(in: -60...0))
        }
        return (-Float.infinity, -Float.infinity)
    }
    
    // MARK: - Position Simulation
    
    /// Simulate playback advancing by given beats
    func advancePlayhead(beats: Double) {
        guard isPlaying else { return }
        
        currentPositionBeats += beats
        
        // Handle cycle
        if cycleEnabled && currentPositionBeats >= cycleEndBeat {
            currentPositionBeats = cycleStartBeat
        }
    }
    
    // MARK: - Helper Methods
    
    func reset() {
        isPlaying = false
        isRecording = false
        currentPositionBeats = 0.0
        tempo = 120.0
        
        cycleEnabled = false
        cycleStartBeat = 0.0
        cycleEndBeat = 4.0
        
        metronomeEnabled = false
        metronomeVolume = 0.7
        
        trackVolumes.removeAll()
        trackPans.removeAll()
        trackMutes.removeAll()
        trackSolos.removeAll()
        
        playCallCount = 0
        stopCallCount = 0
        pauseCallCount = 0
        recordCallCount = 0
        seekCallCount = 0
        
        lastSeekPosition = nil
        
        shouldFailPlay = false
        shouldFailRecord = false
        playError = nil
        recordError = nil
    }
}

// MARK: - Mock Audio Node

/// Mock audio node for testing track audio processing
struct MockAudioNode {
    var id: UUID
    var volume: Float = 1.0
    var pan: Float = 0.0
    var isMuted: Bool = false
    var isBypassed: Bool = false
    
    var inputBuffer: [[Float]] = []
    var outputBuffer: [[Float]] = []
    
    /// Simulate processing audio (simple volume/pan)
    mutating func process(inputBuffer: [[Float]]) -> [[Float]] {
        guard !isMuted && !isBypassed else {
            // Return silence
            return inputBuffer.map { $0.map { _ in 0.0 } }
        }
        
        var output: [[Float]] = []
        
        // Simple stereo processing
        if inputBuffer.count >= 2 {
            let leftGain = volume * (1.0 - max(0, pan))
            let rightGain = volume * (1.0 + min(0, pan))
            
            output.append(inputBuffer[0].map { $0 * leftGain })
            output.append(inputBuffer[1].map { $0 * rightGain })
        } else if inputBuffer.count == 1 {
            // Mono to stereo
            let leftGain = volume * (1.0 - max(0, pan))
            let rightGain = volume * (1.0 + min(0, pan))
            
            output.append(inputBuffer[0].map { $0 * leftGain })
            output.append(inputBuffer[0].map { $0 * rightGain })
        }
        
        return output
    }
}

// MARK: - Mock MIDI Engine

/// Mock MIDI playback engine for testing
final class MockMIDIPlaybackEngine {
    var isPlaying = false
    var scheduledNotes: [(note: MIDINote, trackId: UUID, absoluteBeat: Double)] = []
    var playedNotes: [(note: MIDINote, trackId: UUID)] = []
    
    var noteOnCallCount = 0
    var noteOffCallCount = 0
    var allNotesOffCallCount = 0
    
    func scheduleNote(_ note: MIDINote, trackId: UUID, atBeat beat: Double) {
        scheduledNotes.append((note, trackId, beat))
    }
    
    func playNote(_ note: MIDINote, trackId: UUID) {
        noteOnCallCount += 1
        playedNotes.append((note, trackId))
    }
    
    func stopNote(_ note: MIDINote, trackId: UUID) {
        noteOffCallCount += 1
    }
    
    func allNotesOff() {
        allNotesOffCallCount += 1
    }
    
    func reset() {
        isPlaying = false
        scheduledNotes.removeAll()
        playedNotes.removeAll()
        noteOnCallCount = 0
        noteOffCallCount = 0
        allNotesOffCallCount = 0
    }
}
