//
//  NotationEngraver.swift
//  Stori
//
//  Intelligent engraving engine for professional music notation layout
//  Handles collision avoidance, stem directions, beam angles, and spacing
//

import SwiftUI

// MARK: - Notation Engraver

/// Professional engraving engine following standard music notation rules
/// Based on Elaine Gould's "Behind Bars" and traditional engraving practices
class NotationEngraver {
    
    // MARK: - Configuration
    
    let staffLineSpacing: CGFloat = 10.0
    let minimumNoteSpacing: CGFloat = 20.0
    let accidentalSpacing: CGFloat = 8.0
    
    
    // MARK: - Stem Direction
    
    /// Calculate optimal stem direction based on note position and context
    /// Rule: Notes on or above the middle line get stems down, below get stems up
    func calculateStemDirection(
        for note: ScoreNote,
        clef: Clef,
        neighborNotes: [ScoreNote] = []
    ) -> StemDirection {
        let staffPosition = note.pitch.staffPosition(for: clef)
        
        // Middle line is position 4 (0-indexed from bottom)
        // For treble clef, middle line is B4 (MIDI 71)
        let middleLinePosition = 4
        
        if staffPosition > middleLinePosition {
            return .down
        } else if staffPosition < middleLinePosition {
            return .up
        } else {
            // On the middle line - check context or default to down
            // If there are neighbor notes, follow their direction for consistency
            if let prevNote = neighborNotes.last {
                let prevPosition = prevNote.pitch.staffPosition(for: clef)
                return prevPosition >= middleLinePosition ? .down : .up
            }
            return .down // Default for middle line
        }
    }
    
    /// Calculate stem directions for a group of notes (for beaming)
    func calculateGroupStemDirection(notes: [ScoreNote], clef: Clef) -> StemDirection {
        guard !notes.isEmpty else { return .up }
        
        // Calculate average position of all notes
        let positions = notes.map { Int($0.pitch.staffPosition(for: clef)) }
        let avgPosition = Double(positions.reduce(0, +)) / Double(positions.count)
        
        // Also consider the outermost notes
        let minPosition = positions.min() ?? 0
        let maxPosition = positions.max() ?? 0
        
        // Distance from middle line (position 4)
        let middleLine = 4
        let distanceToTop = maxPosition - middleLine
        let distanceToBottom = middleLine - minPosition
        
        // Prefer the direction that keeps stems shorter
        if distanceToTop > distanceToBottom {
            return .down
        } else if distanceToBottom > distanceToTop {
            return .up
        } else {
            // Equal distance - use average position
            return avgPosition >= Double(middleLine) ? .down : .up
        }
    }
    
    // MARK: - Accidental Collision Resolution
    
    /// Calculate horizontal offsets for stacked accidentals to avoid collisions
    func resolveAccidentalCollisions(notes: [ScoreNote], clef: Clef) -> [UUID: CGFloat] {
        var offsets: [UUID: CGFloat] = [:]
        
        // Group notes that have accidentals
        let notesWithAccidentals = notes.filter { $0.accidental != nil }
        guard notesWithAccidentals.count > 1 else { return offsets }
        
        // Sort by staff position (lowest to highest)
        let sorted = notesWithAccidentals.sorted { 
            $0.pitch.staffPosition(for: clef) < $1.pitch.staffPosition(for: clef) 
        }
        
        // Check for vertical proximity and stagger if needed
        var previousPosition: Int? = nil
        var currentColumn = 0
        
        for note in sorted {
            let position = Int(note.pitch.staffPosition(for: clef))
            
            if let prev = previousPosition {
                // If notes are within 2 staff positions, they might collide
                if abs(position - prev) <= 2 {
                    currentColumn += 1
                } else {
                    currentColumn = 0
                }
            }
            
            // Apply horizontal offset based on column (stagger left)
            offsets[note.id] = -CGFloat(currentColumn) * accidentalSpacing
            previousPosition = position
        }
        
        return offsets
    }
    
    // MARK: - Note Spacing
    
    /// Calculate optimal horizontal spacing for notes in a measure
    /// Based on note durations - longer notes get more space
    func calculateNoteSpacing(
        notes: [ScoreNote],
        measureWidth: CGFloat
    ) -> [UUID: CGFloat] {
        var positions: [UUID: CGFloat] = [:]
        guard !notes.isEmpty else { return positions }
        
        let sortedNotes = notes.sorted { $0.startBeat < $1.startBeat }
        
        // Calculate total duration weight
        let weights = sortedNotes.map { spacingWeight(for: $0.displayDuration) }
        let totalWeight = weights.reduce(0, +)
        
        // Available space (leaving margins)
        let availableWidth = measureWidth - 40 // 20px margins on each side
        
        var currentX: CGFloat = 20 // Start margin
        
        for (index, note) in sortedNotes.enumerated() {
            positions[note.id] = currentX
            
            // Add spacing based on duration weight
            let weight = weights[index]
            let spacing = (weight / totalWeight) * availableWidth
            currentX += max(minimumNoteSpacing, spacing)
        }
        
        return positions
    }
    
    /// Get spacing weight for a note duration
    /// Quarter notes are the baseline (1.0)
    private func spacingWeight(for duration: NoteDuration) -> CGFloat {
        switch duration {
        case .whole: return 4.0
        case .half: return 2.0
        case .quarter: return 1.0
        case .eighth: return 0.75
        case .sixteenth: return 0.5
        case .thirtySecond: return 0.4
        case .sixtyFourth: return 0.35
        }
    }
    
    // MARK: - Beam Calculations
    
    /// Calculate beam angle and positions for a group of beamed notes
    func calculateBeamLayout(
        notes: [ScoreNote],
        clef: Clef,
        noteXPositions: [UUID: CGFloat]
    ) -> BeamLayout {
        guard notes.count >= 2 else {
            return BeamLayout(angle: 0, startY: 0, endY: 0, beamCount: 0)
        }
        
        let sortedNotes = notes.sorted { $0.startBeat < $1.startBeat }
        let stemDirection = calculateGroupStemDirection(notes: sortedNotes, clef: clef)
        
        // Calculate staff positions
        let positions = sortedNotes.map { CGFloat($0.pitch.staffPosition(for: clef)) }
        
        // First and last note positions
        let firstPosition = positions.first ?? 0
        let lastPosition = positions.last ?? 0
        
        // Calculate beam angle
        // Max angle is typically 1 staff space per 4 staff spaces horizontal
        let horizontalDistance = (noteXPositions[sortedNotes.last!.id] ?? 0) - 
                                  (noteXPositions[sortedNotes.first!.id] ?? 0)
        let verticalDifference = (lastPosition - firstPosition) * staffLineSpacing / 2
        
        // Limit the angle to reasonable values
        let maxAngle: CGFloat = horizontalDistance > 0 ? 
            min(abs(verticalDifference / horizontalDistance), 0.25) : 0
        let angle = verticalDifference > 0 ? maxAngle : -maxAngle
        
        // Calculate stem length to ensure proper beam placement
        let stemLength = staffLineSpacing * 3.5
        
        // Start and end Y positions for the beam
        let startY = firstPosition * staffLineSpacing / 2 + 
                     (stemDirection == .up ? -stemLength : stemLength)
        let endY = lastPosition * staffLineSpacing / 2 + 
                   (stemDirection == .up ? -stemLength : stemLength)
        
        // Determine beam count based on shortest note in group
        let shortestDuration = sortedNotes.map { $0.displayDuration }.min { 
            $0.rawValue < $1.rawValue 
        }
        let beamCount = shortestDuration?.flagCount ?? 1
        
        return BeamLayout(
            angle: angle,
            startY: startY,
            endY: endY,
            beamCount: beamCount,
            stemDirection: stemDirection
        )
    }
    
    // MARK: - Ledger Lines
    
    /// Calculate number of ledger lines needed for a note
    func ledgerLineCount(for note: ScoreNote, clef: Clef) -> (above: Int, below: Int) {
        let position = note.pitch.staffPosition(for: clef)
        
        // Staff spans positions 0-8 (5 lines = 9 positions including spaces)
        var above = 0
        var below = 0
        
        if position < 0 {
            // Below staff - count lines needed
            below = (-position + 1) / 2
        } else if position > 8 {
            // Above staff - count lines needed
            above = (position - 8 + 1) / 2
        }
        
        return (above, below)
    }
    
    // MARK: - Articulation Positioning
    
    /// Calculate vertical position for articulations relative to the note
    func articulationPosition(
        for articulation: Articulation,
        note: ScoreNote,
        stemDirection: StemDirection,
        clef: Clef
    ) -> ArticulationPlacement {
        let notePosition = CGFloat(note.pitch.staffPosition(for: clef))
        
        switch articulation.defaultPosition {
        case .aboveStaff:
            // Always above, with clearance from highest element
            let y = max(10, notePosition + 3) * staffLineSpacing / 2
            return ArticulationPlacement(offset: CGPoint(x: 0, y: -y - 10), isAbove: true)
            
        case .belowStaff:
            // Always below, with clearance from lowest element
            let y = min(-2, notePosition - 3) * staffLineSpacing / 2
            return ArticulationPlacement(offset: CGPoint(x: 0, y: -y + 10), isAbove: false)
            
        case .nearNotehead:
            // On opposite side of stem
            if stemDirection == .up {
                // Articulation goes below
                return ArticulationPlacement(
                    offset: CGPoint(x: 0, y: staffLineSpacing),
                    isAbove: false
                )
            } else {
                // Articulation goes above
                return ArticulationPlacement(
                    offset: CGPoint(x: 0, y: -staffLineSpacing),
                    isAbove: true
                )
            }
        }
    }
    
    // MARK: - Dynamic Positioning
    
    /// Calculate position for dynamic markings
    func dynamicPosition(
        dynamic: Dynamic,
        measureStartX: CGFloat,
        beatPosition: Double,
        measureDuration: Double,
        measureWidth: CGFloat,
        staffBottom: CGFloat
    ) -> CGPoint {
        let x = measureStartX + CGFloat(beatPosition / measureDuration) * measureWidth
        let y = staffBottom + 20 // Below staff with padding
        
        return CGPoint(x: x, y: y)
    }
}

// MARK: - Supporting Types

/// Layout information for a beam group
struct BeamLayout {
    let angle: CGFloat
    let startY: CGFloat
    let endY: CGFloat
    let beamCount: Int
    var stemDirection: StemDirection = .up
    
    /// Calculate Y position at a given X along the beam
    func yPosition(at x: CGFloat, startX: CGFloat, endX: CGFloat) -> CGFloat {
        guard endX != startX else { return startY }
        let t = (x - startX) / (endX - startX)
        return startY + t * (endY - startY)
    }
}

/// Placement information for an articulation
struct ArticulationPlacement {
    let offset: CGPoint
    let isAbove: Bool
}

// MARK: - Extensions for Engraving

extension ScoreMeasure {
    
    /// Apply engraving rules to notes in this measure
    mutating func applyEngraving(with engraver: NotationEngraver, clef: Clef) {
        // Calculate stem directions
        for i in 0..<notes.count {
            let neighbors = Array(notes.prefix(i))
            notes[i].stemDirection = engraver.calculateStemDirection(
                for: notes[i],
                clef: clef,
                neighborNotes: neighbors
            )
        }
    }
}

