//
//  ScoreCoordinateMapper.swift
//  Stori
//
//  Single source of truth for score geometry.
//
//  All coordinate conversions — beat↔x, pitch↔y, staff bounds —
//  flow through this type. Rendering and interaction MUST both
//  consume this layer.
//
//  No duplicated math. No ad-hoc offsets. No "close enough."
//

import SwiftUI

// MARK: - Score Layout Metrics

/// Centralized layout constants for score rendering.
///
/// All spacing values are tuned for professional engraving readability.
/// Exposed clearly so future refinement is straightforward — change a
/// value here and it propagates everywhere consistently.
struct ScoreLayoutMetrics {
    
    // MARK: - Staff Dimensions
    
    /// Distance between adjacent staff lines (standard engraving size)
    let staffLineSpacing: CGFloat = 12.0
    
    /// Total height of the 5-line staff (4 spaces)
    var staffHeight: CGFloat { staffLineSpacing * 4 }
    
    // MARK: - Vertical Layout (per staff row)
    
    /// Total height of each staff row.
    /// Must accommodate ledger lines, stems, and flags above/below the staff.
    let staffRowHeight: CGFloat = 140
    
    /// Vertical padding from top of row to first staff line.
    /// Provides space for stems/flags on notes above the staff.
    let yOffset: CGFloat = 36
    
    // MARK: - Horizontal Layout
    
    /// Base measure width before zoom.
    /// Increased from 200 to reduce horizontal density in dense passages.
    let baseMeasureWidth: CGFloat = 250
    
    /// X position where clef drawing begins within staff content area
    let clefStartX: CGFloat = 10
    
    /// Horizontal space allocated for the clef glyph
    let clefWidth: CGFloat = 35
    
    /// Spacing after the time signature before measure content begins
    let postTimeSigSpacing: CGFloat = 10
    
    /// Padding on each side within a measure.
    /// Notes never touch barlines — this breathing room is essential for readability.
    let measurePadding: CGFloat = 20
    
    // MARK: - Track Labels
    
    let trackLabelWidth: CGFloat = 100
    
    // MARK: - Ruler
    
    let rulerHeight: CGFloat = 30
    
    // MARK: - Interaction
    
    /// Maximum distance (in points) from a note center for a tap to register
    let hitTargetRadius: CGFloat = 20.0
}

// MARK: - Score Coordinate Mapper

/// Pure, testable coordinate conversion layer.
///
/// Given musical parameters (clef, key signature, time signature, zoom),
/// this type provides bidirectional mapping between musical coordinates
/// (beats, MIDI pitch) and view coordinates (x, y in points).
///
/// **Both rendering and interaction code MUST use this mapper.**
/// This eliminates coordinate divergence — the root cause of
/// "the mouse lies" bugs where click targets don't match visuals.
///
/// All methods are pure functions with no side effects.
struct ScoreCoordinateMapper {
    let metrics: ScoreLayoutMetrics
    let clef: Clef
    let keySignature: KeySignature
    let timeSignature: ScoreTimeSignature
    let horizontalZoom: CGFloat
    
    // MARK: - Derived Properties
    
    var staffLineSpacing: CGFloat { metrics.staffLineSpacing }
    var staffHeight: CGFloat { metrics.staffHeight }
    var scaledMeasureWidth: CGFloat { metrics.baseMeasureWidth * horizontalZoom }
    var measureDuration: Double { timeSignature.measureDuration }
    var yOffset: CGFloat { metrics.yOffset }
    var measurePadding: CGFloat { metrics.measurePadding }
    
    // MARK: - Content Start X
    
    /// X position where measure content begins (after clef, key signature, time signature).
    ///
    /// This value MUST match the Canvas rendering's incremental layout.
    /// The rendering draws clef → key sig → time sig → notes, advancing
    /// `drawX` at each step. This property replicates that calculation
    /// deterministically from the same constants.
    var contentStartX: CGFloat {
        var x = metrics.clefStartX + metrics.clefWidth
        
        // Key signature width: each accidental takes staffLineSpacing × 1.2,
        // plus one staffLineSpacing of trailing space.
        // Matches StaffRenderer.drawKeySignature return value.
        let accidentalCount = abs(keySignature.sharps)
        if accidentalCount > 0 {
            x += CGFloat(accidentalCount) * staffLineSpacing * 1.2 + staffLineSpacing
        }
        
        // Time signature width.
        // Matches StaffRenderer.drawTimeSignature return value (x + spacing × 2.5).
        x += staffLineSpacing * 2.5
        
        // Post-time-signature spacing
        x += metrics.postTimeSigSpacing
        
        return x
    }
    
    // MARK: - Beat → X
    
    /// Convert a beat position to an X coordinate in staff-local space.
    ///
    /// Notes are distributed proportionally within the measure content area,
    /// which excludes `measurePadding` on each side of each measure.
    func xForBeat(_ beat: Double) -> CGFloat {
        let measureIndex = max(0, Int(beat / measureDuration))
        let beatInMeasure = beat - Double(measureIndex) * measureDuration
        let mStartX = contentStartX + CGFloat(measureIndex) * scaledMeasureWidth
        let contentWidth = scaledMeasureWidth - 2 * measurePadding
        return mStartX + measurePadding + CGFloat(beatInMeasure / measureDuration) * contentWidth
    }
    
    /// X position for a note within a specific measure.
    ///
    /// Uses the measure's index rather than deriving it from the beat,
    /// which matches the rendering loop's iteration pattern exactly.
    func xForNoteInMeasure(_ note: ScoreNote, measureIndex: Int) -> CGFloat {
        let mStartX = contentStartX + CGFloat(measureIndex) * scaledMeasureWidth
        let beatInMeasure = note.startBeat - Double(measureIndex) * measureDuration
        let contentWidth = scaledMeasureWidth - 2 * measurePadding
        return mStartX + measurePadding + CGFloat(beatInMeasure / measureDuration) * contentWidth
    }
    
    // MARK: - X → Beat
    
    /// Convert an X coordinate in staff-local space to a beat position.
    ///
    /// This is the exact inverse of `xForBeat(_:)`.
    func beatAtX(_ x: CGFloat) -> Double {
        let relativeX = x - contentStartX
        let measureIndex = max(0, Int(relativeX / scaledMeasureWidth))
        let measureLocalX = relativeX - CGFloat(measureIndex) * scaledMeasureWidth
        let contentWidth = scaledMeasureWidth - 2 * measurePadding
        let fraction = max(0, min(1, (measureLocalX - measurePadding) / contentWidth))
        let beatInMeasure = Double(fraction) * measureDuration
        return Double(measureIndex) * measureDuration + beatInMeasure
    }
    
    // MARK: - Pitch → Y
    
    /// Convert a MIDI pitch to a Y coordinate in staff-local space.
    ///
    /// Staff position increases upward: higher pitches produce lower Y values.
    /// Formula: `y = yOffset + staffHeight − (staffPosition × halfSpacing)`
    func yForPitch(_ pitch: UInt8) -> CGFloat {
        let staffPosition = pitch.staffPosition(for: clef)
        return yOffset + staffHeight - (CGFloat(staffPosition) * staffLineSpacing / 2)
    }
    
    // MARK: - Y → Pitch
    
    /// Convert a Y coordinate in staff-local space to a MIDI pitch.
    ///
    /// This is the exact inverse of `yForPitch(_:)`.
    /// Returns the nearest diatonic pitch (natural — no accidentals).
    func pitchAtY(_ y: CGFloat) -> UInt8 {
        let staffPosition = Int(round((yOffset + staffHeight - y) / (staffLineSpacing / 2)))
        return pitchFromStaffPosition(staffPosition)
    }
    
    // MARK: - Staff Vertical Bounds
    
    /// Y coordinate of the top staff line
    var staffTopY: CGFloat { yOffset }
    
    /// Y coordinate of the bottom staff line
    var staffBottomY: CGFloat { yOffset + staffHeight }
    
    /// Y coordinate of the staff center (middle line)
    var staffCenterY: CGFloat { yOffset + staffHeight / 2 }
    
    // MARK: - Measure Bounds
    
    /// X coordinate where a measure begins (its barline position)
    func measureStartX(at measureIndex: Int) -> CGFloat {
        contentStartX + CGFloat(measureIndex) * scaledMeasureWidth
    }
    
    // MARK: - Hit Testing
    
    /// Find the ScoreNote nearest to a point, if within hit target radius.
    ///
    /// Returns the closest note within `metrics.hitTargetRadius` points,
    /// or nil if no note is close enough. This uses the same coordinate
    /// math as rendering, guaranteeing that visually displayed notes
    /// and clickable notes always agree.
    func findNote(at point: CGPoint, in measures: [ScoreMeasure]) -> ScoreNote? {
        var closestNote: ScoreNote?
        var closestDistance: CGFloat = .infinity
        
        for measure in measures {
            let measureIndex = measure.measureNumber - 1
            for note in measure.notes {
                let noteX = xForNoteInMeasure(note, measureIndex: measureIndex)
                let noteY = yForPitch(note.pitch)
                let distance = hypot(point.x - noteX, point.y - noteY)
                if distance < metrics.hitTargetRadius && distance < closestDistance {
                    closestNote = note
                    closestDistance = distance
                }
            }
        }
        
        return closestNote
    }
    
    // MARK: - Pitch Conversion Helper
    
    /// Convert a staff position to a MIDI pitch.
    ///
    /// This is the exact inverse of `UInt8.staffPosition(for:)`.
    /// Staff positions are integers where each step is one diatonic scale degree.
    /// The clef offset is removed, then octave and note are extracted.
    ///
    /// **Critical**: Uses floor division for negative positions.
    /// Swift's `/` truncates toward zero, which gives wrong octaves
    /// for notes below middle C. The `(x - 6) / 7` formula with
    /// Swift truncation produces correct floor(x/7) results.
    func pitchFromStaffPosition(_ position: Int) -> UInt8 {
        let clefOffset: Int
        switch clef {
        case .treble: clefOffset = -6
        case .bass: clefOffset = 6
        case .alto: clefOffset = 0
        case .tenor: clefOffset = 2
        case .percussion: return 60
        }
        
        let positionWithoutClef = position - clefOffset
        
        let octaveOffset: Int
        let noteOffset: Int
        
        if positionWithoutClef >= 0 {
            octaveOffset = positionWithoutClef / 7
            noteOffset = positionWithoutClef % 7
        } else {
            // Floor division: (x - 6) / 7 with Swift truncation gives floor(x / 7).
            // This ensures positions -1..-7 → octave -1, -8..-14 → octave -2, etc.
            octaveOffset = (positionWithoutClef - 6) / 7
            noteOffset = ((positionWithoutClef % 7) + 7) % 7
        }
        
        let middleCOctave = 4
        let octave = middleCOctave + octaveOffset
        
        // Map diatonic scale degree to chromatic semitone offset
        // C=0, D=2, E=4, F=5, G=7, A=9, B=11
        let noteToSemitone = [0, 2, 4, 5, 7, 9, 11]
        let semitone = noteToSemitone[noteOffset]
        
        let pitch = (octave + 1) * 12 + semitone
        return UInt8(max(0, min(127, pitch)))
    }
}
