//
//  AudioSchedulingContext.swift
//  Stori
//
//  Shared timing reference for sample-accurate scheduling across all audio subsystems.
//  Ensures metronome, MIDI playback, and recording stay perfectly synchronized under tempo automation.
//
//  ARCHITECTURE (Issue #56 Fix):
//  - Single source of truth for beat-to-sample conversions
//  - Used by MetronomeEngine, SampleAccurateMIDIScheduler, and RecordingController
//  - Regenerated when tempo changes to maintain accuracy
//  - Thread-safe access via atomic properties
//
//  WHY THIS MATTERS:
//  - Without shared timing: Metronome drifts from MIDI under tempo automation
//  - With shared timing: All audio events use identical beat-to-sample calculations
//  - Professional DAW requirement: Metronome must be sample-accurate reference
//

import Foundation
@preconcurrency import AVFoundation

// TimeSignature is defined in AudioModels.swift and will be available when this file is compiled as part of the target

/// Shared scheduling context for all audio subsystems.
/// Provides consistent beat-to-sample conversion across metronome, MIDI, and recording.
///
/// THREAD SAFETY:
/// - All properties are immutable after creation
/// - Safe to read from any thread (no locks needed)
/// - New instances created when timing parameters change
struct AudioSchedulingContext: Sendable {
    /// Sample rate of the audio engine
    let sampleRate: Double
    
    /// Tempo in BPM at the time this context was created
    let tempo: Double
    
    /// Time signature (beats per bar, note value)
    let timeSignature: TimeSignature
    
    /// Default context for fallback scenarios
    static let `default` = AudioSchedulingContext(
        sampleRate: 48000,
        tempo: 120,
        timeSignature: TimeSignature(numerator: 4, denominator: 4)
    )
    
    /// Pre-calculated samples per beat for efficiency
    /// Formula: (60.0 / tempo) * sampleRate
    var samplesPerBeat: Double {
        (60.0 / tempo) * sampleRate
    }
    
    /// Convert a beat position to sample time
    /// - Parameters:
    ///   - beat: The beat position to convert
    ///   - referenceBeat: The beat position of the reference point (usually playback start)
    ///   - referenceSample: The sample time of the reference point
    /// - Returns: The absolute sample time for the given beat
    func sampleTime(forBeat beat: Double, referenceBeat: Double, referenceSample: Int64) -> Int64 {
        let beatDelta = beat - referenceBeat
        let sampleDelta = Int64(beatDelta * samplesPerBeat)
        return referenceSample + sampleDelta
    }
    
    /// Convert a sample time to beat position
    /// - Parameters:
    ///   - sample: The sample time to convert
    ///   - referenceBeat: The beat position of the reference point
    ///   - referenceSample: The sample time of the reference point
    /// - Returns: The beat position for the given sample time
    func beat(forSampleTime sample: Int64, referenceBeat: Double, referenceSample: Int64) -> Double {
        let sampleDelta = sample - referenceSample
        let beatDelta = Double(sampleDelta) / samplesPerBeat
        return referenceBeat + beatDelta
    }
    
    /// Calculate the number of samples per beat at current tempo and sample rate
    /// Convenience method for subsystems that need this value directly
    func samplesPerBeatInt64() -> Int64 {
        Int64(samplesPerBeat.rounded())
    }
    
    /// Convert seconds to beats at current tempo
    func secondsToBeats(_ seconds: Double) -> Double {
        seconds * (tempo / 60.0)
    }
    
    /// Convert beats to seconds at current tempo
    func beatsToSeconds(_ beats: Double) -> Double {
        beats * (60.0 / tempo)
    }
    
    /// Create a new context with updated tempo
    func with(tempo: Double) -> AudioSchedulingContext {
        AudioSchedulingContext(sampleRate: sampleRate, tempo: tempo, timeSignature: timeSignature)
    }
    
    /// Create a new context with updated sample rate
    func with(sampleRate: Double) -> AudioSchedulingContext {
        AudioSchedulingContext(sampleRate: sampleRate, tempo: tempo, timeSignature: timeSignature)
    }
    
    /// Create a new context with updated time signature
    func with(timeSignature: TimeSignature) -> AudioSchedulingContext {
        AudioSchedulingContext(sampleRate: sampleRate, tempo: tempo, timeSignature: timeSignature)
    }
}
