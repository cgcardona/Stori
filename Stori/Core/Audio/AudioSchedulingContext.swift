//
//  AudioSchedulingContext.swift
//  Stori
//
//  Unified timing context for audio scheduling operations.
//  Encapsulates sample rate, tempo, and time signature with computed conversions.
//
//  DESIGN RATIONALE:
//  - Single source of truth for all timing calculations
//  - Value type ensures thread-safe copying between contexts
//  - Pre-computed values avoid repeated calculations in hot paths
//  - Eliminates scattered sample rate / tempo handling across components
//

import Foundation
import AVFoundation

// MARK: - Audio Scheduling Context

/// A value type encapsulating all timing-related state for audio scheduling.
///
/// This provides a single source of truth for:
/// - Sample rate (hardware)
/// - Tempo (project)
/// - Time signature
/// - Beat ↔ Sample conversions
/// - Beat ↔ Seconds conversions
///
/// Usage:
/// ```swift
/// let context = AudioSchedulingContext(sampleRate: 48000, tempo: 120, timeSignature: .common)
/// let samples = context.beatsToSamples(4.0)  // 4 beats = 96000 samples at 120 BPM
/// let seconds = context.beatsToSeconds(4.0)  // 4 beats = 2.0 seconds at 120 BPM
/// ```
///
/// THREAD SAFETY:
/// This is a value type (struct), so it's inherently thread-safe when copied.
/// Components can capture a context at a point in time and use it freely.
struct AudioSchedulingContext: Sendable, Equatable {
    
    // MARK: - Core Properties
    
    /// Hardware sample rate in Hz (e.g., 44100, 48000, 96000)
    let sampleRate: Double
    
    /// Project tempo in beats per minute
    let tempo: Double
    
    /// Project time signature
    let timeSignature: TimeSignature
    
    // MARK: - Pre-Computed Values (for hot path efficiency)
    
    /// Seconds per beat: 60.0 / tempo
    let secondsPerBeat: Double
    
    /// Samples per beat: secondsPerBeat * sampleRate
    let samplesPerBeat: Double
    
    /// Seconds per bar (based on time signature)
    let secondsPerBar: Double
    
    /// Samples per bar
    let samplesPerBar: Double
    
    // MARK: - Initialization
    
    /// Create a scheduling context with explicit values
    init(sampleRate: Double, tempo: Double, timeSignature: TimeSignature = .fourFour) {
        self.sampleRate = sampleRate
        self.tempo = max(1.0, tempo)  // Guard against division by zero
        self.timeSignature = timeSignature
        
        // Pre-compute derived values
        self.secondsPerBeat = 60.0 / self.tempo
        self.samplesPerBeat = self.secondsPerBeat * sampleRate
        
        // Calculate bar duration based on time signature
        // beatsPerBar = numerator when denominator is 4 (quarter note = 1 beat)
        // For other denominators, adjust accordingly
        let beatsPerBar = Double(timeSignature.numerator) * (4.0 / Double(timeSignature.denominator))
        self.secondsPerBar = self.secondsPerBeat * beatsPerBar
        self.samplesPerBar = self.samplesPerBeat * beatsPerBar
    }
    
    /// Create a context with default values (48kHz, 120 BPM, 4/4)
    static let `default` = AudioSchedulingContext(
        sampleRate: 48000,
        tempo: 120,
        timeSignature: .fourFour
    )
    
    // MARK: - Beat ↔ Sample Conversions
    
    /// Convert beats to samples
    /// - Parameter beats: Number of beats
    /// - Returns: Number of samples
    @inlinable
    func beatsToSamples(_ beats: Double) -> Double {
        beats * samplesPerBeat
    }
    
    /// Convert samples to beats
    /// - Parameter samples: Number of samples
    /// - Returns: Number of beats
    @inlinable
    func samplesToBeats(_ samples: Double) -> Double {
        samples / samplesPerBeat
    }
    
    /// Convert samples to beats (from frame count)
    @inlinable
    func samplesToBeats(_ samples: AVAudioFrameCount) -> Double {
        Double(samples) / samplesPerBeat
    }
    
    // MARK: - Beat ↔ Seconds Conversions
    
    /// Convert beats to seconds
    /// - Parameter beats: Number of beats
    /// - Returns: Number of seconds
    @inlinable
    func beatsToSeconds(_ beats: Double) -> Double {
        beats * secondsPerBeat
    }
    
    /// Convert seconds to beats
    /// - Parameter seconds: Number of seconds
    /// - Returns: Number of beats
    @inlinable
    func secondsToBeats(_ seconds: Double) -> Double {
        seconds / secondsPerBeat
    }
    
    // MARK: - Sample ↔ Seconds Conversions
    
    /// Convert samples to seconds
    @inlinable
    func samplesToSeconds(_ samples: Double) -> Double {
        samples / sampleRate
    }
    
    /// Convert seconds to samples
    @inlinable
    func secondsToSamples(_ seconds: Double) -> Double {
        seconds * sampleRate
    }
    
    // MARK: - Bar/Beat Calculations
    
    /// Get the bar number for a given beat position (0-indexed)
    func barNumber(forBeat beat: Double) -> Int {
        let beatsPerBar = Double(timeSignature.numerator) * (4.0 / Double(timeSignature.denominator))
        return Int(beat / beatsPerBar)
    }
    
    /// Get the beat within the current bar (0-indexed)
    func beatInBar(forBeat beat: Double) -> Double {
        let beatsPerBar = Double(timeSignature.numerator) * (4.0 / Double(timeSignature.denominator))
        return beat.truncatingRemainder(dividingBy: beatsPerBar)
    }
    
    // MARK: - Context Updates
    
    /// Create a new context with updated tempo (preserving other values)
    func with(tempo newTempo: Double) -> AudioSchedulingContext {
        AudioSchedulingContext(
            sampleRate: sampleRate,
            tempo: newTempo,
            timeSignature: timeSignature
        )
    }
    
    /// Create a new context with updated sample rate (preserving other values)
    func with(sampleRate newSampleRate: Double) -> AudioSchedulingContext {
        AudioSchedulingContext(
            sampleRate: newSampleRate,
            tempo: tempo,
            timeSignature: timeSignature
        )
    }
    
    /// Create a new context with updated time signature (preserving other values)
    func with(timeSignature newTimeSignature: TimeSignature) -> AudioSchedulingContext {
        AudioSchedulingContext(
            sampleRate: sampleRate,
            tempo: tempo,
            timeSignature: newTimeSignature
        )
    }
}

// MARK: - CustomStringConvertible

extension AudioSchedulingContext: CustomStringConvertible {
    var description: String {
        "AudioSchedulingContext(sampleRate: \(Int(sampleRate))Hz, tempo: \(tempo) BPM, timeSignature: \(timeSignature))"
    }
}

// MARK: - Debugging

extension AudioSchedulingContext {
    /// Debug string with all computed values
    var debugDescription: String {
        """
        AudioSchedulingContext:
          Sample Rate: \(Int(sampleRate)) Hz
          Tempo: \(tempo) BPM
          Time Signature: \(timeSignature.numerator)/\(timeSignature.denominator)
          Seconds/Beat: \(String(format: "%.4f", secondsPerBeat))
          Samples/Beat: \(String(format: "%.2f", samplesPerBeat))
          Seconds/Bar: \(String(format: "%.4f", secondsPerBar))
          Samples/Bar: \(String(format: "%.2f", samplesPerBar))
        """
    }
}
