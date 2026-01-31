//
//  StepSequencerRegionVisualization.swift
//  Stori
//
//  Visualizes step sequencer patterns as grids (N rows x M columns, typically 16x16)
//  Professional step sequencer visualization style:
//  - Fixed pattern width (doesn't stretch)
//  - Patterns reveal/clip as region resizes
//  - Looped iterations are darker
//  - Visual gaps at loop boundaries (top/bottom notches)
//  - Supports partial loops at the end
//
//  Created by Stori on 1/16/26.
//

import SwiftUI

struct StepSequencerRegionVisualization: View {
    let pattern: [[Bool]]  // N rows x M columns (typically 16x16 for extended kit, 1 bar)
    let regionDuration: TimeInterval
    let tempo: Double  // BPM
    let width: CGFloat
    let height: CGFloat
    let offsetBeats: Double  // [PHASE-3] How many beats to offset from the start (for left-edge trim)
    let isLooped: Bool  // Whether to tile/repeat the pattern or show empty space beyond original
    let contentLength: TimeInterval  // Length of one loop unit (may include empty space after pattern)
    let audioFileDuration: TimeInterval  // Original audio file duration (pattern only)
    
    // Visual constants for professional appearance
    private let loopNotchHeight: CGFloat = 3  // Height of visual gap at loop boundaries
    private let loopDividerWidth: CGFloat = 1  // Width of divider line between loops
    
    // Minimum cell width before switching to compact mode
    // Set to 4.0 to ensure compact mode activates reliably at low zoom levels
    private let minCellWidthForDetailedView: CGFloat = 4.0
    
    init(pattern: [[Bool]], regionDuration: TimeInterval, tempo: Double = 120.0, width: CGFloat, height: CGFloat, offsetBeats: Double = 0, isLooped: Bool = true, contentLength: TimeInterval? = nil, audioFileDuration: TimeInterval? = nil) {
        self.pattern = pattern
        self.regionDuration = regionDuration
        self.tempo = tempo
        self.width = width
        self.height = height
        self.offsetBeats = offsetBeats
        self.isLooped = isLooped
        // Default to pattern duration if not specified
        let defaultPatternDuration = (60.0 / tempo) * 4.0
        self.audioFileDuration = audioFileDuration ?? defaultPatternDuration
        self.contentLength = contentLength ?? self.audioFileDuration
    }
    
    // Calculate the fixed width for one audio pattern (based on audioFileDuration)
    private var patternWidth: CGFloat {
        guard regionDuration > 0 else { return width }
        let pixelsPerSecond = width / regionDuration
        return audioFileDuration * pixelsPerSecond
    }
    
    // Calculate the width for one content unit (pattern + any empty space)
    private var contentWidth: CGFloat {
        guard regionDuration > 0 else { return width }
        let pixelsPerSecond = width / regionDuration
        return contentLength * pixelsPerSecond
    }
    
    // Calculate the duration of one pattern (one bar) in seconds
    private var patternDuration: TimeInterval {
        (60.0 / tempo) * 4.0
    }
    
    // Determine if we should use compact mode (when cells are too small)
    private var shouldUseCompactMode: Bool {
        guard pattern.count > 0, pattern[0].count > 0 else { return false }
        let columns = pattern[0].count
        let cellWidth = patternWidth / CGFloat(columns)
        return cellWidth < minCellWidthForDetailedView
    }
    
    var body: some View {
        Canvas { context, size in
            let rows = pattern.count
            guard rows > 0, patternWidth > 0 else { return }
            let columns = pattern[0].count
            
            // Fixed cell dimensions based on pattern width (NOT stretched)
            let cellWidth = patternWidth / CGFloat(columns)
            let cellHeight = (size.height - loopNotchHeight * 2) / CGFloat(rows)  // Account for notches
            let contentY = loopNotchHeight  // Start below top notch
            
            // [PHASE-3] Calculate offset in terms of patterns and partial columns
            let beatsPerBar = 4.0
            let offsetBars = offsetBeats / beatsPerBar
            let offsetPatterns = Int(offsetBars)  // Full patterns to skip
            let partialOffsetBeats = offsetBeats.truncatingRemainder(dividingBy: beatsPerBar)
            let partialOffsetColumns = Int(partialOffsetBeats / beatsPerBar * Double(columns))
            let partialOffsetX = CGFloat(partialOffsetColumns) * cellWidth
            
            // Calculate how many content units (pattern + empty space) fit
            // Each content unit = patternWidth of audio + any empty space from resize
            let fullContentUnits: Int
            let totalContentUnits: Int
            
            if isLooped && contentWidth > 0 {
                // When looped, tile the entire content unit (pattern + empty space)
                fullContentUnits = Int(size.width / contentWidth)
                totalContentUnits = fullContentUnits + (size.width.truncatingRemainder(dividingBy: contentWidth) > 0 ? 1 : 0)
            } else {
                // Not looped - only show 1 content unit
                totalContentUnits = 1
                fullContentUnits = 1
            }
            
            // COMPACT MODE: When zoomed out too far, show simplified horizontal bars
            // Always show something visible even at low zoom levels
            if cellWidth < minCellWidthForDetailedView {
                drawCompactMode(context: context, size: size, rows: rows, columns: columns, 
                               cellHeight: cellHeight, contentY: contentY, totalContentUnits: totalContentUnits,
                               offsetPatterns: offsetPatterns, partialOffsetX: partialOffsetX, isLooped: isLooped)
                return
            }
            
            // Draw each content unit (pattern + any empty space)
            for contentIndex in 0..<totalContentUnits {
                // Calculate the start position of this content unit
                let contentUnitX = CGFloat(contentIndex) * contentWidth - partialOffsetX
                let isLoopedCopy = contentIndex > 0  // First content unit is original, rest are loops
                
                // Within this content unit, only draw the pattern (patternWidth), rest is empty
                // Pattern starts at contentUnitX, empty space from contentUnitX + patternWidth to contentUnitX + contentWidth
                
                // Determine how much of the pattern is visible in this content unit
                let patternEndX = contentUnitX + patternWidth
                let visiblePatternWidth = min(patternWidth, max(0, size.width - contentUnitX))
                let visibleColumns = min(columns, Int(ceil(visiblePatternWidth / cellWidth)))
                
                // Draw loop boundary visuals (darker background for looped copies)
                if isLoopedCopy {
                    // Darker overlay for the pattern portion of looped regions
                    let overlayRect = CGRect(
                        x: max(0, contentUnitX),
                        y: 0,
                        width: min(patternWidth, size.width - max(0, contentUnitX)),
                        height: size.height
                    )
                    if overlayRect.width > 0 {
                        context.fill(
                            Path(overlayRect),
                            with: .color(Color.black.opacity(0.15))
                        )
                    }
                }
                
                // Draw grid cells for the pattern (NOT the empty space)
                for row in 0..<rows {
                    for col in 0..<visibleColumns {
                        let x = contentUnitX + (CGFloat(col) * cellWidth)
                        
                        // Skip if cell is outside visible region or beyond pattern
                        if x >= size.width || x >= patternEndX { continue }
                        if x + cellWidth <= 0 { continue }
                        
                        // Calculate cell rect, clipping at region edge and pattern edge
                        let cellRight = min(x + cellWidth - 2, size.width - 1, patternEndX - 2)
                        let cellActualWidth = cellRight - max(0, x + 1)
                        if cellActualWidth <= 0 { continue }
                        
                        let y = contentY + CGFloat(row) * cellHeight
                        
                        let rect = CGRect(
                            x: max(0, x + 1),
                            y: y + 1,
                            width: cellActualWidth,
                            height: cellHeight - 2
                        )
                        
                        let isActive = row < pattern.count && col < pattern[row].count && pattern[row][col]
                        
                        // Opacity is reduced for looped copies
                        let baseOpacity: Double = isLoopedCopy ? 0.7 : 0.9
                        let inactiveOpacity: Double = isLoopedCopy ? 0.05 : 0.08
                        
                        if isActive {
                            // Active step - white bar (dimmer for loops)
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: 1),
                                with: .color(Color.white.opacity(baseOpacity))
                            )
                        } else {
                            // Inactive step - subtle darker shade
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: 1),
                                with: .color(Color.white.opacity(inactiveOpacity))
                            )
                        }
                    }
                }
                
                // Draw loop boundary notches and divider at content unit boundary (not pattern boundary)
                if isLoopedCopy {
                    let dividerX = contentUnitX
                    
                    // Top notch (visual gap)
                    let topNotch = CGRect(x: dividerX - 1, y: 0, width: 2, height: loopNotchHeight)
                    context.fill(Path(topNotch), with: .color(Color.black.opacity(0.6)))
                    
                    // Bottom notch (visual gap)  
                    let bottomNotch = CGRect(x: dividerX - 1, y: size.height - loopNotchHeight, width: 2, height: loopNotchHeight)
                    context.fill(Path(bottomNotch), with: .color(Color.black.opacity(0.6)))
                    
                    // Vertical divider line between loops
                    let dividerPath = Path { path in
                        path.move(to: CGPoint(x: dividerX, y: loopNotchHeight))
                        path.addLine(to: CGPoint(x: dividerX, y: size.height - loopNotchHeight))
                    }
                    context.stroke(
                        dividerPath,
                        with: .color(Color.white.opacity(0.25)),
                        lineWidth: loopDividerWidth
                    )
                }
            }
        }
        .frame(width: width, height: height)
    }
    
    // MARK: - Compact Mode Drawing (for low zoom levels)
    // Shows horizontal bars for each lane instead of individual cells
    // This ensures visualization is always visible
    private func drawCompactMode(
        context: GraphicsContext,
        size: CGSize,
        rows: Int,
        columns: Int,
        cellHeight: CGFloat,
        contentY: CGFloat,
        totalContentUnits: Int,
        offsetPatterns: Int,
        partialOffsetX: CGFloat,
        isLooped: Bool
    ) {
        // For each lane, check if any step is active and draw a bar
        for row in 0..<rows {
            let hasActiveSteps = pattern[row].contains(true)
            guard hasActiveSteps else { continue }
            
            // Count active steps to determine opacity
            let activeCount = pattern[row].filter { $0 }.count
            let density = CGFloat(activeCount) / CGFloat(columns)
            
            // Draw the bar across the entire visible width for this lane
            let y = contentY + CGFloat(row) * cellHeight
            let barHeight = max(cellHeight - 2, 1)
            
            // If not looped, only draw 1 content unit
            let unitsToRender = isLooped ? totalContentUnits : 1
            
            // Draw bar segments for each content unit (only the pattern portion, not empty space)
            for contentIndex in 0..<unitsToRender {
                let contentUnitX = CGFloat(contentIndex) * contentWidth - partialOffsetX
                let isLoopedCopy = contentIndex > 0
                
                // Determine visible portion of the PATTERN (not the full content unit)
                let patternStartX = contentUnitX
                let patternEndX = contentUnitX + patternWidth
                let startX = max(0, patternStartX)
                let endX = min(size.width, patternEndX)
                let visibleWidth = endX - startX
                
                guard visibleWidth > 0 else { continue }
                
                // Base opacity adjusted for loops and density
                let baseOpacity: Double = isLoopedCopy ? 0.5 : 0.7
                let barOpacity = baseOpacity * (0.5 + density * 0.5)  // Min 50% of base when sparse
                
                let rect = CGRect(
                    x: startX + 1,
                    y: y + 1,
                    width: visibleWidth - 2,
                    height: barHeight
                )
                
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(Color.white.opacity(barOpacity))
                )
                
                // Draw loop boundary for looped copies (at content unit boundary, not pattern)
                if isLoopedCopy && contentUnitX > 0 {
                    // Darker divider line at loop boundary
                    let dividerPath = Path { path in
                        path.move(to: CGPoint(x: contentUnitX, y: contentY))
                        path.addLine(to: CGPoint(x: contentUnitX, y: size.height - loopNotchHeight))
                    }
                    context.stroke(
                        dividerPath,
                        with: .color(Color.black.opacity(0.4)),
                        lineWidth: 1
                    )
                }
            }
        }
        
        // Draw background for inactive lanes (subtle grid) - only within first pattern if not looped
        let bgWidth = isLooped ? size.width : min(patternWidth, size.width)
        for row in 0..<rows {
            let hasActiveSteps = pattern[row].contains(true)
            if !hasActiveSteps {
                let y = contentY + CGFloat(row) * cellHeight
                let rect = CGRect(
                    x: 0,
                    y: y + 1,
                    width: bgWidth,
                    height: max(cellHeight - 2, 1)
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(Color.white.opacity(0.03))
                )
            }
        }
    }
}
