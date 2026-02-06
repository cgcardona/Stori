//
//  QuantizationEngine.swift
//  Stori
//
//  MIDI note quantization and swing utilities.
//  Uses SnapResolution from MIDIModels for grid-based quantization.
//

import Foundation

/// Engine for quantizing and applying swing to MIDI notes.
/// Leverages existing SnapResolution infrastructure for consistent behavior.
enum QuantizationEngine {
    
    /// Quantize notes to a grid resolution
    /// - Parameters:
    ///   - notes: The notes to quantize
    ///   - resolution: SnapResolution defining the grid
    ///   - timeSignature: Current time signature for correct grid calculation
    ///   - strength: How strongly to pull notes to grid (0.0 - 1.0)
    ///   - quantizeDuration: Whether to also quantize note durations
    /// - Returns: Quantized notes
    static func quantize(
        notes: [MIDINote],
        resolution: SnapResolution,
        timeSignature: TimeSignature,
        strength: Float,
        quantizeDuration: Bool
    ) -> [MIDINote] {
        guard resolution != .off, strength > 0 else { return notes }
        
        return notes.map { note in
            // Quantize start position using time-signature-aware method (Issue #64)
            let quantizedStart = resolution.quantize(
                beat: note.startBeat,
                timeSignature: timeSignature,
                strength: strength
            )
            
            // Optionally quantize duration
            var quantizedDuration = note.durationBeats
            if quantizeDuration {
                let gridSize = resolution.stepDurationBeats(timeSignature: timeSignature)
                if gridSize > 0 {
                    let gridDuration = max(gridSize, round(note.durationBeats / gridSize) * gridSize)
                    quantizedDuration = note.durationBeats + (gridDuration - note.durationBeats) * Double(strength)
                }
            }
            
            return MIDINote(
                id: note.id,
                pitch: note.pitch,
                velocity: note.velocity,
                startBeat: quantizedStart,
                durationBeats: quantizedDuration,
                channel: note.channel
            )
        }
    }
    
    /// Apply swing to notes
    /// - Parameters:
    ///   - notes: The notes to swing
    ///   - amount: Swing amount (0.0 = straight, 1.0 = full triplet swing)
    ///   - gridResolution: The grid to apply swing to (e.g., 0.5 for 8th notes)
    /// - Returns: Notes with swing applied
    static func applySwing(
        notes: [MIDINote],
        amount: Double,
        gridResolution: Double
    ) -> [MIDINote] {
        guard gridResolution > 0, amount > 0 else { return notes }
        
        // Swing shifts every other grid position
        // amount = 0: straight timing
        // amount = 1: triplet feel (second note delayed by 1/3 of grid)
        let maxSwingOffset = gridResolution / 3.0
        
        return notes.map { note in
            // Determine which grid position this note is on
            let gridIndex = Int(round(note.startBeat / gridResolution))
            
            // Only swing odd-numbered grid positions (off-beats)
            guard gridIndex % 2 == 1 else { return note }
            
            // Calculate swing offset
            let swingOffset = maxSwingOffset * amount
            
            return MIDINote(
                id: note.id,
                pitch: note.pitch,
                velocity: note.velocity,
                startBeat: note.startBeat + swingOffset,
                durationBeats: note.durationBeats,
                channel: note.channel
            )
        }
    }
}
