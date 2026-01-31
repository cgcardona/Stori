//
//  StaffRenderer.swift
//  Stori
//
//  Core rendering engine for music notation
//  Draws staff lines, clefs, notes, and all musical symbols
//

import SwiftUI

// MARK: - Staff Renderer

/// Handles all drawing operations for music notation
struct StaffRenderer {
    
    // MARK: - Configuration (Professional proportions)
    
    // Staff dimensions - matches professional engraving standards (Bravura/SMuFL)
    let staffLineSpacing: CGFloat = 12.0    // Larger for readability (~12-14pt)
    let staffLineWidth: CGFloat = 1.5       // Bold staff lines
    let stemWidth: CGFloat = 1.3            // Slightly thinner stems
    let noteheadWidth: CGFloat = 14.0       // Proper width (1.18 × spacing)
    let noteheadHeight: CGFloat = 10.0      // Proper height (0.83 × spacing)
    let ledgerLineExtension: CGFloat = 5.0  // Extension beyond notehead
    let measurePadding: CGFloat = 24.0
    
    // Colors - professional black notation
    let staffLineColor = Color.primary.opacity(0.85)  // Nearly black staff lines
    let noteColor = Color.primary                      // Pure black notes
    let selectedNoteColor = Color.green                // Green selection
    let restColor = Color.primary
    
    // MARK: - Staff Height
    
    var staffHeight: CGFloat {
        staffLineSpacing * 4  // 5 lines = 4 spaces
    }
    
    // MARK: - Draw Staff Lines
    
    func drawStaffLines(context: GraphicsContext, width: CGFloat, yOffset: CGFloat = 0) {
        for line in 0..<5 {
            let y = yOffset + CGFloat(line) * staffLineSpacing
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: width, y: y))
            }
            context.stroke(path, with: .color(staffLineColor), lineWidth: staffLineWidth)
        }
    }
    
    // MARK: - Draw Clef
    
    func drawClef(context: GraphicsContext, clef: Clef, x: CGFloat, yOffset: CGFloat = 0) {
        switch clef {
        case .treble:
            drawTrebleClef(context: context, x: x, yOffset: yOffset)
        case .bass:
            drawBassClef(context: context, x: x, yOffset: yOffset)
        case .alto, .tenor:
            drawCClef(context: context, x: x, yOffset: yOffset, isTenor: clef == .tenor)
        case .percussion:
            drawPercussionClef(context: context, x: x, yOffset: yOffset)
        }
    }
    
    /// Draw treble clef using Unicode symbol (clean, professional rendering)
    private func drawTrebleClef(context: GraphicsContext, x: CGFloat, yOffset: CGFloat) {
        // Use system music font which renders proper clefs
        let clefSize = staffHeight * 2.8  // Scale to fit staff
        let gLineY = yOffset + staffLineSpacing * 3  // G line (where clef centers)
        
        let clefText = Text("𝄞")
            .font(.system(size: clefSize))
            .foregroundColor(noteColor)
        
        // Position so the curl wraps around the G line
        context.draw(
            clefText,
            at: CGPoint(x: x + 22, y: gLineY + staffLineSpacing * 0.3),
            anchor: .center
        )
    }
    
    /// Draw bass clef using Unicode symbol (clean, professional rendering)
    private func drawBassClef(context: GraphicsContext, x: CGFloat, yOffset: CGFloat) {
        // Use system music font which renders proper clefs
        let clefSize = staffHeight * 2.2  // Scale to fit staff
        let fLineY = yOffset + staffLineSpacing * 1  // F line (where clef centers)
        
        let clefText = Text("𝄢")
            .font(.system(size: clefSize))
            .foregroundColor(noteColor)
        
        // Position so the dots align with F line
        context.draw(
            clefText,
            at: CGPoint(x: x + 22, y: fLineY + staffLineSpacing * 1.2),
            anchor: .center
        )
    }
    
    /// Draw C clef (alto/tenor) using Unicode symbol
    private func drawCClef(context: GraphicsContext, x: CGFloat, yOffset: CGFloat, isTenor: Bool) {
        let clefSize = staffHeight * 2.0
        // For alto: middle line (index 2), for tenor: 4th line (index 3)
        let cLineY = yOffset + staffLineSpacing * (isTenor ? 3 : 2)
        
        let clefText = Text("𝄡")
            .font(.system(size: clefSize))
            .foregroundColor(noteColor)
        
        context.draw(
            clefText,
            at: CGPoint(x: x + 20, y: cLineY),
            anchor: .center
        )
    }
    
    /// Draw percussion clef (two vertical bars)
    private func drawPercussionClef(context: GraphicsContext, x: CGFloat, yOffset: CGFloat) {
        let barWidth: CGFloat = staffLineSpacing * 0.35
        let barHeight: CGFloat = staffHeight
        let barSpacing: CGFloat = staffLineSpacing * 0.5
        let centerX = x + 15
        
        // Left bar
        var leftBar = Path()
        leftBar.addRect(CGRect(
            x: centerX - barSpacing/2 - barWidth,
            y: yOffset,
            width: barWidth,
            height: barHeight
        ))
        context.fill(leftBar, with: .color(noteColor))
        
        // Right bar
        var rightBar = Path()
        rightBar.addRect(CGRect(
            x: centerX + barSpacing/2,
            y: yOffset,
            width: barWidth,
            height: barHeight
        ))
        context.fill(rightBar, with: .color(noteColor))
    }
    
    // MARK: - Draw Key Signature
    
    func drawKeySignature(
        context: GraphicsContext,
        keySignature: KeySignature,
        clef: Clef,
        x: CGFloat,
        yOffset: CGFloat = 0
    ) -> CGFloat {
        
        guard keySignature.sharps != 0 else { return x }
        
        let symbol = keySignature.sharps > 0 ? "♯" : "♭"
        let count = abs(keySignature.sharps)
        
        // Get clef-specific positions for accidentals
        let positions: [CGFloat]
        
        switch clef {
        case .treble:
            // Treble clef positions (staff positions from top: 0=top line, 4=bottom line)
            // Order: F5, C5, G5, D5, A4, E5, B4 for sharps
            // Order: B4, E5, A4, D5, G4, C5, F4 for flats
            if keySignature.sharps > 0 {
                positions = [0, 1.5, -0.5, 1, 2.5, 0.5, 2] // Sharps
            } else {
                positions = [2, 0.5, 2.5, 1, 3, 1.5, 3.5] // Flats
            }
            
        case .bass:
            // Bass clef positions
            // Top line = A3, Line 1 = F3, Line 2 = D3, Line 3 = B2, Bottom = G2
            // Order: F3, C3, G3, D3, A2, E3, B2 for sharps
            // Order: B2, E3, A2, D3, G2, C3, F2 for flats
            if keySignature.sharps > 0 {
                positions = [1, 1.5, 0.5, 2, 3.5, 1.5, 3] // Sharps
            } else {
                positions = [3, 1.5, 3.5, 2, 4, 2.5, 4.5] // Flats
            }
            
        case .alto:
            // Alto clef positions (middle line = C4)
            // Order for sharps: F4, C4, G4, D4, A3, E4, B3
            // Order for flats: B3, E4, A3, D4, G3, C4, F3
            if keySignature.sharps > 0 {
                positions = [0.5, 2, -0.5, 1.5, 3, 1, 2.5] // Sharps
            } else {
                positions = [2.5, 1, 3, 1.5, 3.5, 2, 4] // Flats
            }
            
        case .tenor:
            // Tenor clef positions (4th line from bottom = C4)
            // Similar to alto but shifted
            if keySignature.sharps > 0 {
                positions = [-0.5, 1, -1.5, 0.5, 2, 0, 1.5] // Sharps
            } else {
                positions = [1.5, 0, 2, 0.5, 2.5, 1, 3] // Flats
            }
            
        case .percussion:
            // Percussion doesn't typically use key signatures, but provide defaults
            positions = []
        }
        
        var currentX = x
        for i in 0..<min(count, positions.count) {
            let position = positions[i]
            let y = yOffset + position * staffLineSpacing
            
            let text = Text(symbol)
                .font(.system(size: staffLineSpacing * 2))
                .foregroundColor(noteColor)
            
            context.draw(text, at: CGPoint(x: currentX, y: y), anchor: .center)
            currentX += staffLineSpacing * 1.2
        }
        
        return currentX + staffLineSpacing
    }
    
    // MARK: - Draw Time Signature
    
    func drawTimeSignature(
        context: GraphicsContext,
        timeSignature: ScoreTimeSignature,
        x: CGFloat,
        yOffset: CGFloat = 0
    ) -> CGFloat {
        // Use large, bold numbers that fill the staff height
        // Each number takes up exactly 2 staff spaces (half the staff)
        let fontSize = staffLineSpacing * 2.2  // Fills 2 spaces nicely
        
        // Numerator - centered in top half of staff (spaces 0-2)
        let numText = Text("\(timeSignature.beats)")
            .font(.system(size: fontSize, weight: .heavy, design: .serif))
            .foregroundColor(noteColor)
        
        context.draw(
            numText,
            at: CGPoint(x: x + 8, y: yOffset + staffLineSpacing * 1),  // Center of top half
            anchor: .center
        )
        
        // Denominator - centered in bottom half of staff (spaces 2-4)
        let denomText = Text("\(timeSignature.beatValue)")
            .font(.system(size: fontSize, weight: .heavy, design: .serif))
            .foregroundColor(noteColor)
        
        context.draw(
            denomText,
            at: CGPoint(x: x + 8, y: yOffset + staffLineSpacing * 3),  // Center of bottom half
            anchor: .center
        )
        
        return x + staffLineSpacing * 2.5
    }
    
    // MARK: - Draw Bar Line
    
    func drawBarLine(
        context: GraphicsContext,
        x: CGFloat,
        yOffset: CGFloat = 0,
        style: BarLineStyle = .single
    ) {
        let y1 = yOffset
        let y2 = yOffset + staffHeight
        let barlineWidth: CGFloat = 1.2  // Bold barlines
        
        switch style {
        case .single:
            let path = Path { p in
                p.move(to: CGPoint(x: x, y: y1))
                p.addLine(to: CGPoint(x: x, y: y2))
            }
            context.stroke(path, with: .color(noteColor), lineWidth: barlineWidth)
            
        case .double:
            for offset in [0, staffLineWidth * 3] as [CGFloat] {
                let path = Path { p in
                    p.move(to: CGPoint(x: x + offset, y: y1))
                    p.addLine(to: CGPoint(x: x + offset, y: y2))
                }
                context.stroke(path, with: .color(noteColor), lineWidth: staffLineWidth)
            }
            
        case .final:
            // Thin line
            let thinPath = Path { p in
                p.move(to: CGPoint(x: x, y: y1))
                p.addLine(to: CGPoint(x: x, y: y2))
            }
            context.stroke(thinPath, with: .color(noteColor), lineWidth: staffLineWidth)
            
            // Thick line
            let thickPath = Path { p in
                p.move(to: CGPoint(x: x + staffLineWidth * 3, y: y1))
                p.addLine(to: CGPoint(x: x + staffLineWidth * 3, y: y2))
            }
            context.stroke(thickPath, with: .color(noteColor), lineWidth: staffLineWidth * 3)
            
        case .repeatStart, .repeatEnd:
            // Similar to final but with dots
            drawBarLine(context: context, x: x, yOffset: yOffset, style: .double)
            
            // Draw dots
            let dotX = style == .repeatStart ? x + staffLineWidth * 6 : x - staffLineWidth * 3
            for lineIndex in [1.5, 2.5] {
                let dotY = yOffset + CGFloat(lineIndex) * staffLineSpacing
                let dotPath = Path(ellipseIn: CGRect(
                    x: dotX - 2,
                    y: dotY - 2,
                    width: 4,
                    height: 4
                ))
                context.fill(dotPath, with: .color(noteColor))
            }
        }
    }
    
    // MARK: - Draw Note
    
    func drawNote(
        context: GraphicsContext,
        note: ScoreNote,
        x: CGFloat,
        clef: Clef,
        yOffset: CGFloat = 0,
        isSelected: Bool = false
    ) {
        let staffPosition = note.pitch.staffPosition(for: clef)
        let noteY = yOffset + staffHeight - (CGFloat(staffPosition) * staffLineSpacing / 2)
        
        let color = isSelected ? selectedNoteColor : noteColor
        
        // Draw ledger lines if needed
        let ledgerLines = note.pitch.needsLedgerLines(for: clef)
        if ledgerLines > 0 {
            drawLedgerLines(
                context: context,
                count: ledgerLines,
                x: x,
                noteY: noteY,
                above: staffPosition > 9,
                yOffset: yOffset
            )
        }
        
        // Draw accidental if present
        if let accidental = note.accidental {
            drawAccidental(
                context: context,
                accidental: accidental,
                x: x - noteheadWidth,
                y: noteY,
                color: color
            )
        }
        
        // Draw notehead
        drawNotehead(
            context: context,
            duration: note.displayDuration,
            x: x,
            y: noteY,
            color: color
        )
        
        // Draw dots
        if note.dotCount > 0 {
            drawDots(
                context: context,
                count: note.dotCount,
                x: x + noteheadWidth / 2 + 4,
                y: noteY,
                color: color
            )
        }
        
        // Draw stem if needed
        if note.displayDuration.hasStem {
            let stemDirection = note.stemDirection == .auto
                ? StemDirection.forPitch(note.pitch, clef: clef)
                : note.stemDirection
            
            drawStem(
                context: context,
                x: x,
                noteY: noteY,
                direction: stemDirection,
                color: color
            )
            
            // Draw flags for unbeamed notes
            if note.beamGroupId == nil && note.displayDuration.flagCount > 0 {
                drawFlags(
                    context: context,
                    count: note.displayDuration.flagCount,
                    x: x,
                    noteY: noteY,
                    direction: stemDirection,
                    color: color
                )
            }
        }
        
        // Draw tie if needed
        if note.tieToNext {
            drawTieStart(context: context, x: x + noteheadWidth / 2, y: noteY)
        }
        
        // Draw articulations
        for articulation in note.articulations {
            drawArticulation(
                context: context,
                articulation: articulation,
                x: x,
                noteY: noteY,
                yOffset: yOffset,
                stemDirection: StemDirection.forPitch(note.pitch, clef: clef)
            )
        }
    }
    
    // MARK: - Draw Notehead
    
    private func drawNotehead(
        context: GraphicsContext,
        duration: NoteDuration,
        x: CGFloat,
        y: CGFloat,
        color: Color
    ) {
        // Professional noteheads are tilted ellipses
        // Tilt angle: approximately -20 degrees for filled notes, -15 for hollow
        let tiltAngle: CGFloat = duration == .whole || duration == .half ? -.pi / 12 : -.pi / 9
        
        // Whole notes are slightly wider
        let width = duration == .whole ? noteheadWidth * 1.15 : noteheadWidth
        let height = noteheadHeight
        
        switch duration {
        case .whole:
            // Whole note - oval with inner hole (like a donut)
            drawWholeNoteHead(context: context, x: x, y: y, width: width, height: height, color: color)
            
        case .half:
            // Half note - hollow ellipse with thick stroke
            let rect = CGRect(
                x: x - width / 2,
                y: y - height / 2,
                width: width,
                height: height
            )
            
            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: x, y: y)
            transform = transform.rotated(by: tiltAngle)
            transform = transform.translatedBy(x: -x, y: -y)
            
            let path = Path(ellipseIn: rect).applying(transform)
            context.stroke(path, with: .color(color), lineWidth: 2.0)
            
        default:
            // Quarter and shorter - filled ellipse
            let rect = CGRect(
                x: x - width / 2,
                y: y - height / 2,
                width: width,
                height: height
            )
            
            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: x, y: y)
            transform = transform.rotated(by: tiltAngle)
            transform = transform.translatedBy(x: -x, y: -y)
            
            let path = Path(ellipseIn: rect).applying(transform)
            context.fill(path, with: .color(color))
        }
    }
    
    /// Draw a whole note with inner hole (oval donut shape)
    private func drawWholeNoteHead(
        context: GraphicsContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat,
        height: CGFloat,
        color: Color
    ) {
        let tiltAngle: CGFloat = -.pi / 15
        
        // Outer ellipse
        let outerRect = CGRect(
            x: x - width / 2,
            y: y - height / 2,
            width: width,
            height: height
        )
        
        // Inner ellipse (the hole) - rotated differently for the characteristic whole note look
        let innerWidth = width * 0.55
        let innerHeight = height * 0.65
        let innerRect = CGRect(
            x: x - innerWidth / 2,
            y: y - innerHeight / 2,
            width: innerWidth,
            height: innerHeight
        )
        
        var outerTransform = CGAffineTransform.identity
        outerTransform = outerTransform.translatedBy(x: x, y: y)
        outerTransform = outerTransform.rotated(by: tiltAngle)
        outerTransform = outerTransform.translatedBy(x: -x, y: -y)
        
        // Inner hole is tilted more steeply
        var innerTransform = CGAffineTransform.identity
        innerTransform = innerTransform.translatedBy(x: x, y: y)
        innerTransform = innerTransform.rotated(by: tiltAngle * 2.5)
        innerTransform = innerTransform.translatedBy(x: -x, y: -y)
        
        let outerPath = Path(ellipseIn: outerRect).applying(outerTransform)
        let innerPath = Path(ellipseIn: innerRect).applying(innerTransform)
        
        // Draw outer filled, then "punch out" inner with background color simulation
        // For proper rendering, we use even-odd fill rule with combined path
        var combinedPath = Path()
        combinedPath.addPath(outerPath)
        combinedPath.addPath(innerPath)
        
        context.fill(combinedPath, with: .color(color), style: FillStyle(eoFill: true))
    }
    
    // MARK: - Draw Stem
    
    private func drawStem(
        context: GraphicsContext,
        x: CGFloat,
        noteY: CGFloat,
        direction: StemDirection,
        color: Color
    ) {
        // Standard stem length is 3.5 staff spaces (spans an octave)
        let stemLength = staffLineSpacing * 3.5
        
        // Stems connect to the right edge of notehead (up) or left edge (down)
        let stemX: CGFloat
        let stemY1: CGFloat
        let stemY2: CGFloat
        
        if direction == .up {
            // Stem goes up from right side of notehead
            stemX = x + noteheadWidth / 2 - 0.5  // Right edge
            stemY1 = noteY - noteheadHeight / 4  // Slightly into notehead for connection
            stemY2 = noteY - stemLength
        } else {
            // Stem goes down from left side of notehead
            stemX = x - noteheadWidth / 2 + 0.5  // Left edge
            stemY1 = noteY + noteheadHeight / 4  // Slightly into notehead for connection
            stemY2 = noteY + stemLength
        }
        
        let path = Path { p in
            p.move(to: CGPoint(x: stemX, y: stemY1))
            p.addLine(to: CGPoint(x: stemX, y: stemY2))
        }
        
        // Slightly thicker stems for visibility
        context.stroke(path, with: .color(color), lineWidth: 1.4)
    }
    
    // MARK: - Draw Flags
    
    private func drawFlags(
        context: GraphicsContext,
        count: Int,
        x: CGFloat,
        noteY: CGFloat,
        direction: StemDirection,
        color: Color
    ) {
        let stemLength = staffLineSpacing * 3.5
        let flagSpacing = staffLineSpacing * 0.8
        
        let stemX = direction == .up
            ? x + noteheadWidth / 2 - stemWidth / 2
            : x - noteheadWidth / 2 + stemWidth / 2
        
        let stemEndY = direction == .up
            ? noteY - stemLength
            : noteY + stemLength
        
        for i in 0..<count {
            let flagY = direction == .up
                ? stemEndY + CGFloat(i) * flagSpacing
                : stemEndY - CGFloat(i) * flagSpacing
            
            let path = Path { p in
                p.move(to: CGPoint(x: stemX, y: flagY))
                
                if direction == .up {
                    p.addQuadCurve(
                        to: CGPoint(x: stemX + 12, y: flagY + 15),
                        control: CGPoint(x: stemX + 15, y: flagY + 5)
                    )
                } else {
                    p.addQuadCurve(
                        to: CGPoint(x: stemX + 12, y: flagY - 15),
                        control: CGPoint(x: stemX + 15, y: flagY - 5)
                    )
                }
            }
            
            context.stroke(path, with: .color(color), lineWidth: 2)
        }
    }
    
    // MARK: - Draw Ledger Lines
    
    private func drawLedgerLines(
        context: GraphicsContext,
        count: Int,
        x: CGFloat,
        noteY: CGFloat,
        above: Bool,
        yOffset: CGFloat = 0
    ) {
        guard count > 0 else { return }
        
        // Ledger lines extend slightly beyond the notehead
        let lineStartX = x - noteheadWidth / 2 - ledgerLineExtension
        let lineEndX = x + noteheadWidth / 2 + ledgerLineExtension
        
        // Calculate which ledger lines to draw
        // Staff spans from yOffset (top line) to yOffset + staffHeight (bottom line)
        // Lines are at yOffset + n * staffLineSpacing for n in 0...4
        
        for i in 0..<count {
            let ledgerY: CGFloat
            if above {
                // Ledger lines above the staff: yOffset - staffLineSpacing, yOffset - 2*staffLineSpacing, etc.
                ledgerY = yOffset - CGFloat(i + 1) * staffLineSpacing
            } else {
                // Ledger lines below the staff: yOffset + staffHeight + staffLineSpacing, etc.
                ledgerY = yOffset + staffHeight + CGFloat(i + 1) * staffLineSpacing
            }
            
            // Only draw if the ledger line is at or between the note and the staff
            let shouldDraw: Bool
            if above {
                shouldDraw = ledgerY >= noteY - staffLineSpacing / 2
            } else {
                shouldDraw = ledgerY <= noteY + staffLineSpacing / 2
            }
            
            if shouldDraw {
                let path = Path { p in
                    p.move(to: CGPoint(x: lineStartX, y: ledgerY))
                    p.addLine(to: CGPoint(x: lineEndX, y: ledgerY))
                }
                context.stroke(path, with: .color(noteColor.opacity(0.6)), lineWidth: staffLineWidth)
            }
        }
    }
    
    // MARK: - Draw Accidental
    
    private func drawAccidental(
        context: GraphicsContext,
        accidental: Accidental,
        x: CGFloat,
        y: CGFloat,
        color: Color
    ) {
        let text = Text(accidental.displaySymbol)
            .font(.system(size: staffLineSpacing * 2.2))
            .foregroundColor(color)
        
        context.draw(text, at: CGPoint(x: x, y: y), anchor: .center)
    }
    
    // MARK: - Draw Dots
    
    private func drawDots(
        context: GraphicsContext,
        count: Int,
        x: CGFloat,
        y: CGFloat,
        color: Color
    ) {
        for i in 0..<count {
            let dotX = x + CGFloat(i) * 5
            let dotPath = Path(ellipseIn: CGRect(
                x: dotX - 1.5,
                y: y - 1.5,
                width: 3,
                height: 3
            ))
            context.fill(dotPath, with: .color(color))
        }
    }
    
    // MARK: - Draw Tie
    
    private func drawTieStart(context: GraphicsContext, x: CGFloat, y: CGFloat) {
        // This is a simplified tie - full implementation would connect to next note
        let path = Path { p in
            p.move(to: CGPoint(x: x, y: y + 5))
            p.addQuadCurve(
                to: CGPoint(x: x + 20, y: y + 5),
                control: CGPoint(x: x + 10, y: y + 12)
            )
        }
        context.stroke(path, with: .color(noteColor), lineWidth: 1.5)
    }
    
    // MARK: - Draw Articulation
    
    private func drawArticulation(
        context: GraphicsContext,
        articulation: Articulation,
        x: CGFloat,
        noteY: CGFloat,
        yOffset: CGFloat,
        stemDirection: StemDirection
    ) {
        let articulationY: CGFloat
        
        switch articulation.defaultPosition {
        case .aboveStaff:
            articulationY = yOffset - staffLineSpacing
        case .belowStaff:
            articulationY = yOffset + staffHeight + staffLineSpacing
        case .nearNotehead:
            articulationY = stemDirection == .up
                ? noteY + staffLineSpacing
                : noteY - staffLineSpacing
        }
        
        let text = Text(articulation.glyph)
            .font(.system(size: staffLineSpacing * 1.5))
            .foregroundColor(noteColor)
        
        context.draw(text, at: CGPoint(x: x, y: articulationY), anchor: .center)
    }
    
    // MARK: - Draw Rest
    
    func drawRest(
        context: GraphicsContext,
        rest: ScoreRest,
        x: CGFloat,
        yOffset: CGFloat = 0
    ) {
        let centerY = yOffset + staffHeight / 2
        
        let text = Text(rest.duration.restGlyph)
            .font(.system(size: staffLineSpacing * 3))
            .foregroundColor(restColor)
        
        context.draw(text, at: CGPoint(x: x, y: centerY), anchor: .center)
        
        // Draw dots
        if rest.dotCount > 0 {
            drawDots(
                context: context,
                count: rest.dotCount,
                x: x + staffLineSpacing,
                y: centerY - staffLineSpacing / 2,
                color: restColor
            )
        }
    }
    
    // MARK: - Draw Beam
    
    func drawBeam(
        context: GraphicsContext,
        notes: [ScoreNote],
        clef: Clef,
        getXPosition: (ScoreNote) -> CGFloat,
        yOffset: CGFloat = 0
    ) {
        guard notes.count >= 2 else { return }
        
        // Determine beam direction based on average pitch
        let avgPitch = notes.map { Int($0.pitch) }.reduce(0, +) / notes.count
        let direction = avgPitch >= Int(clef.middleLinePitch) ? StemDirection.down : StemDirection.up
        
        // Find stem end positions
        let stemLength = staffLineSpacing * 3.5
        var stemEnds: [(x: CGFloat, y: CGFloat)] = []
        
        for note in notes {
            let x = getXPosition(note)
            let staffPosition = note.pitch.staffPosition(for: clef)
            let noteY = yOffset + staffHeight - (CGFloat(staffPosition) * staffLineSpacing / 2)
            
            let stemX = direction == .up
                ? x + noteheadWidth / 2 - stemWidth / 2
                : x - noteheadWidth / 2 + stemWidth / 2
            
            let stemEndY = direction == .up
                ? noteY - stemLength
                : noteY + stemLength
            
            stemEnds.append((stemX, stemEndY))
        }
        
        // Draw the beam
        guard let first = stemEnds.first, let last = stemEnds.last else { return }
        
        // Calculate beam line (may be angled)
        let beamHeight: CGFloat = 4
        
        let beamPath = Path { p in
            p.move(to: CGPoint(x: first.x, y: first.y))
            p.addLine(to: CGPoint(x: last.x, y: last.y))
            p.addLine(to: CGPoint(x: last.x, y: last.y + (direction == .up ? beamHeight : -beamHeight)))
            p.addLine(to: CGPoint(x: first.x, y: first.y + (direction == .up ? beamHeight : -beamHeight)))
            p.closeSubpath()
        }
        
        context.fill(beamPath, with: .color(noteColor))
        
        // Draw stems
        for (i, note) in notes.enumerated() {
            let x = getXPosition(note)
            let staffPosition = note.pitch.staffPosition(for: clef)
            let noteY = yOffset + staffHeight - (CGFloat(staffPosition) * staffLineSpacing / 2)
            
            let stemPath = Path { p in
                p.move(to: CGPoint(x: stemEnds[i].x, y: noteY))
                p.addLine(to: CGPoint(x: stemEnds[i].x, y: stemEnds[i].y))
            }
            context.stroke(stemPath, with: .color(noteColor), lineWidth: stemWidth)
        }
    }
    
    // MARK: - Articulation Rendering
    
    /// Draw an articulation mark on a note
    func drawArticulation(
        context: GraphicsContext,
        articulation: Articulation,
        at x: CGFloat,
        noteY: CGFloat,
        stemDirection: StemDirection,
        yOffset: CGFloat
    ) {
        // Position articulation on opposite side of stem
        let offset: CGFloat = stemDirection == .up ? staffLineSpacing * 1.5 : -staffLineSpacing * 1.5
        let articulationY = noteY + offset
        
        let symbol = articulation.glyph
        let font = Font.system(size: 16, weight: .medium)
        
        context.draw(
            Text(symbol).font(font).foregroundColor(.black),
            at: CGPoint(x: x, y: articulationY),
            anchor: .center
        )
    }
    
    // MARK: - Dynamic Rendering
    
    /// Draw a dynamic marking below the staff
    func drawDynamic(
        context: GraphicsContext,
        dynamic: Dynamic,
        at x: CGFloat,
        yOffset: CGFloat
    ) {
        // Position dynamics below the staff
        let dynamicY = yOffset + staffHeight + staffLineSpacing * 2
        
        let symbol = dynamic.glyph
        let font = Font.custom("Times New Roman", size: 18).italic()
        
        context.draw(
            Text(symbol).font(font).foregroundColor(.black),
            at: CGPoint(x: x, y: dynamicY),
            anchor: .center
        )
    }
    
    /// Draw a crescendo/decrescendo hairpin
    func drawHairpin(
        context: GraphicsContext,
        isCrescendo: Bool,
        startX: CGFloat,
        endX: CGFloat,
        yOffset: CGFloat
    ) {
        let hairpinY = yOffset + staffHeight + staffLineSpacing * 2.5
        let hairpinHeight: CGFloat = 8
        
        let path = Path { p in
            if isCrescendo {
                // Crescendo: < shape opening to the right
                p.move(to: CGPoint(x: startX, y: hairpinY))
                p.addLine(to: CGPoint(x: endX, y: hairpinY - hairpinHeight / 2))
                p.move(to: CGPoint(x: startX, y: hairpinY))
                p.addLine(to: CGPoint(x: endX, y: hairpinY + hairpinHeight / 2))
            } else {
                // Decrescendo: > shape opening to the left
                p.move(to: CGPoint(x: startX, y: hairpinY - hairpinHeight / 2))
                p.addLine(to: CGPoint(x: endX, y: hairpinY))
                p.move(to: CGPoint(x: startX, y: hairpinY + hairpinHeight / 2))
                p.addLine(to: CGPoint(x: endX, y: hairpinY))
            }
        }
        
        context.stroke(path, with: .color(.black), lineWidth: 1.5)
    }
    
    // MARK: - Slur/Tie Rendering
    
    /// Draw a slur or tie arc between two notes
    func drawSlur(
        context: GraphicsContext,
        startX: CGFloat,
        startY: CGFloat,
        endX: CGFloat,
        endY: CGFloat,
        isAbove: Bool
    ) {
        let midX = (startX + endX) / 2
        let controlOffset: CGFloat = isAbove ? -20 : 20
        let midY = min(startY, endY) + controlOffset
        
        let path = Path { p in
            p.move(to: CGPoint(x: startX, y: startY))
            p.addQuadCurve(
                to: CGPoint(x: endX, y: endY),
                control: CGPoint(x: midX, y: midY)
            )
        }
        
        context.stroke(path, with: .color(.black), lineWidth: 1.5)
    }
    
    // MARK: - Tempo Marking
    
    /// Draw a tempo marking above the staff
    func drawTempoMarking(
        context: GraphicsContext,
        tempo: Double,
        at x: CGFloat,
        yOffset: CGFloat
    ) {
        let tempoY = yOffset - staffLineSpacing * 2
        
        // Draw quarter note symbol
        let noteSymbol = "♩"
        let tempoText = "\(noteSymbol) = \(Int(tempo))"
        let font = Font.system(size: 12, weight: .medium)
        
        context.draw(
            Text(tempoText).font(font).foregroundColor(.black),
            at: CGPoint(x: x, y: tempoY),
            anchor: .leading
        )
    }
    
    // MARK: - Expression Text
    
    /// Draw expression text (e.g., "dolce", "espressivo")
    func drawExpressionText(
        context: GraphicsContext,
        text: String,
        at x: CGFloat,
        yOffset: CGFloat
    ) {
        let expressionY = yOffset + staffHeight + staffLineSpacing * 3.5
        let font = Font.custom("Times New Roman", size: 12).italic()
        
        context.draw(
            Text(text).font(font).foregroundColor(.black),
            at: CGPoint(x: x, y: expressionY),
            anchor: .center
        )
    }
}

// MARK: - Bar Line Style

enum BarLineStyle {
    case single
    case double
    case final
    case repeatStart
    case repeatEnd
}

