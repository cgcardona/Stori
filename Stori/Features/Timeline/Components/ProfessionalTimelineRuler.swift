//
//  ProfessionalTimelineRuler.swift
//  Stori
//
//  Professional two-layer timeline ruler with cycle overlay and playhead control
//

import SwiftUI

struct ProfessionalTimelineRuler: View {
    // PERFORMANCE: Removed @EnvironmentObject to prevent re-renders on every position update
    // All needed values are passed as parameters
    let pixelsPerBeat: CGFloat  // Beat-based timeline
    let contentWidth: CGFloat
    let height: CGFloat  // expect 60
    let projectTempo: Double  // Pass in from parent
    let snapToGrid: Bool  // [PHASE-1] For cycle region snap
    
    // Cycle region state (passed from parent to avoid observing audioEngine)
    let isCycleEnabled: Bool
    let cycleStartBeat: Double
    let cycleEndBeat: Double
    let onSeek: (TimeInterval) -> Void
    let onCycleRegionChanged: (Double, Double) -> Void
    
    // Height split
    private let topCycleHeight: CGFloat = 30
    private var bottomPlayheadHeight: CGFloat { height - topCycleHeight }
    
    // Derived values for time-mode display
    private var secondsPerBeat: Double { 60.0 / projectTempo }
    private var pixelsPerSecond: CGFloat { pixelsPerBeat / CGFloat(secondsPerBeat) }
    
    // Unique ID for forcing Canvas redraw when zoom changes OR tempo changes
    private var zoomId: String {
        "\(pixelsPerBeat)-\(contentWidth)-\(projectTempo)"
    }
    
    // MARK: - Tiled Canvas for Large Widths
    // macOS SwiftUI has texture size limits (~8192px). Split into tiles to avoid invisible Canvas.
    private let tileWidth: CGFloat = 2048
    
    private var numberOfTiles: Int {
        max(1, Int(ceil(contentWidth / tileWidth)))
    }
    
    private var tiledTicksView: some View {
        // Use HStack to naturally position tiles side by side from x=0
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<numberOfTiles, id: \.self) { tileIndex in
                let tileX = CGFloat(tileIndex) * tileWidth
                let thisTileWidth = min(tileWidth, contentWidth - tileX)
                
                Canvas { ctx, size in
                    // Draw time markers for this tile, offset by tileX
                    drawTimeMarkersForTile(ctx: ctx, size: size, tileOffsetX: tileX)
                }
                .frame(width: thisTileWidth, height: bottomPlayheadHeight)
                .drawingGroup()  // PERF: Rasterize to prevent continuous redraws
                .id("\(zoomId)-tile-\(tileIndex)")
            }
        }
        .frame(width: contentWidth, height: bottomPlayheadHeight, alignment: .leading)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // BASE BACKGROUND
            Rectangle()
                .fill(Color(NSColor.controlBackgroundColor))
            
            // Use VStack to properly separate cycle lane from ruler area
            VStack(spacing: 0) {
                // --- TOP: CYCLE LANE (30px) -----------------------------------
                ZStack(alignment: .topLeading) {
                    // Subtle separation background for cycle lane
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.08),
                                    Color.black.opacity(0.04)
                                ],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .overlay(
                            Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 0.5),
                            alignment: .bottom
                        )

                    if isCycleEnabled {
                        CycleOverlay(
                            cycleStartBeat: cycleStartBeat,
                            cycleEndBeat: cycleEndBeat,
                            pixelsPerBeat: pixelsPerBeat,
                            maxWidth: contentWidth,
                            tempo: projectTempo,
                            snapToGrid: snapToGrid,
                            onCycleRegionChanged: onCycleRegionChanged
                        )
                    }
                }
                .frame(width: contentWidth, height: topCycleHeight)
                .contentShape(Rectangle())  // Ensure cycle lane area is tappable for CycleOverlay
                .accessibilityLabel("Cycle lane")
                .accessibilityHint("Drag to move or resize the cycle region")
                
                // --- BOTTOM: RULER + CLICK-TO-SEEK (30px) ---------------------
                ZStack(alignment: .topLeading) {
                    // Tiled Canvas for bar/beat markers (no hit testing)
                    tiledTicksView
                        .allowsHitTesting(false)
                    
                    // Click-to-seek layer (transparent, handles playhead positioning)
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let x = max(0, value.location.x)
                                    let t = Double(x / pixelsPerSecond)
                                    onSeek(t)
                                }
                        )
                        .accessibilityLabel("Timeline ruler")
                        .accessibilityHint("Click to move playhead")
                        .accessibilityAddTraits(.isButton)
                }
                .frame(width: contentWidth, height: bottomPlayheadHeight)
            }

            // --- PLAYHEAD (spans both layers, no hit testing) -----------------
            // PERFORMANCE: Uses @Observable TransportModel for fine-grained updates
            RulerPlayhead(
                height: height,
                pixelsPerSecond: pixelsPerSecond
            )
        }
        .frame(width: contentWidth, height: height)
    }

    // MARK: Ticks/Labels (bottom lane) - Original (unused, kept for reference)
    private func drawTimeMarkers(ctx: GraphicsContext, size: CGSize) {
        // Always use beats mode
        drawBeatsMode(ctx: ctx, size: size)
    }
    
    // MARK: - Tiled Drawing (avoids macOS texture size limits)
    private func drawTimeMarkersForTile(ctx: GraphicsContext, size: CGSize, tileOffsetX: CGFloat) {
        // Always use beats mode - beats is now the standard throughout the app
        drawBeatsModeForTile(ctx: ctx, size: size, tileOffsetX: tileOffsetX)
    }
    
    // MARK: - Time Mode for Tile
    private func drawTimeModeForTile(ctx: GraphicsContext, size: CGSize, tileOffsetX: CGFloat) {
        let pps = pixelsPerSecond
        guard pps > 0 else { return }
        
        // Calculate which seconds fall within this tile
        let tileStartSecond = Int(floor(tileOffsetX / pps))
        let tileEndSecond = Int(ceil((tileOffsetX + size.width) / pps))
        
        // Adaptive marker interval
        let majorInterval: Int
        let mediumInterval: Int
        let showMinorTicks: Bool
        let fontSize: CGFloat
        
        if pps < 5 {
            majorInterval = 30
            mediumInterval = 10
            showMinorTicks = false
            fontSize = 12
        } else if pps < 15 {
            majorInterval = 10
            mediumInterval = 5
            showMinorTicks = false
            fontSize = 11
        } else if pps < 50 {
            majorInterval = 5
            mediumInterval = 1
            showMinorTicks = false
            fontSize = 11
        } else {
            majorInterval = 5
            mediumInterval = 1
            showMinorTicks = true
            fontSize = 11
        }
        
        let lineColor = Color.primary  // Adapts to light/dark mode
        
        for second in max(0, tileStartSecond - 1)...tileEndSecond {
            let globalX = CGFloat(second) * pps
            let localX = globalX - tileOffsetX  // Convert to tile-local coordinates
            
            // Skip if outside this tile's bounds
            guard localX >= -20 && localX <= size.width + 20 else { continue }
            
            if second % majorInterval == 0 {
                var p = Path()
                p.move(to: CGPoint(x: localX, y: 0))
                p.addLine(to: CGPoint(x: localX, y: size.height))
                ctx.stroke(p, with: .color(lineColor), lineWidth: 1.5)
                
                let m = second / 60, s = second % 60
                let label = String(format: "%d:%02d", m, s)
                let resolvedText = ctx.resolve(
                    Text(label)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(lineColor)
                )
                ctx.draw(resolvedText, at: CGPoint(x: localX + 3, y: 4), anchor: .topLeading)
            } else if second % mediumInterval == 0 {
                var p = Path()
                p.move(to: CGPoint(x: localX, y: 6))
                p.addLine(to: CGPoint(x: localX, y: size.height))
                ctx.stroke(p, with: .color(lineColor.opacity(0.6)), lineWidth: 1)
            } else if showMinorTicks {
                var p = Path()
                p.move(to: CGPoint(x: localX, y: 12))
                p.addLine(to: CGPoint(x: localX, y: size.height))
                ctx.stroke(p, with: .color(lineColor.opacity(0.35)), lineWidth: 0.8)
            }
        }
    }
    
    // MARK: - Beats Mode for Tile
    private func drawBeatsModeForTile(ctx: GraphicsContext, size: CGSize, tileOffsetX: CGFloat) {
        let tempo = projectTempo
        let secondsPerBeat = 60.0 / tempo
        let pixelsPerBeat = CGFloat(secondsPerBeat) * pixelsPerSecond
        let pixelsPerBar = pixelsPerBeat * 4
        let beatsPerBar = 4
        
        // Calculate which beats fall within this tile
        let tileStartBeat = max(0, Int(floor(tileOffsetX / pixelsPerBeat)) - 1)
        let tileEndBeat = Int(ceil((tileOffsetX + size.width) / pixelsPerBeat)) + 1
        
        // Adaptive intervals
        let labelBarInterval: Int
        let showBeatTicks: Bool
        let fontSize: CGFloat
        
        if pixelsPerBar < 15 {
            labelBarInterval = 4
            showBeatTicks = false
            fontSize = 12
        } else if pixelsPerBar < 30 {
            labelBarInterval = 2
            showBeatTicks = false
            fontSize = 12
        } else if pixelsPerBar < 60 {
            labelBarInterval = 1
            showBeatTicks = false
            fontSize = 11
        } else if pixelsPerBar < 120 {
            labelBarInterval = 1
            showBeatTicks = true
            fontSize = 11
        } else {
            labelBarInterval = 1
            showBeatTicks = true
            fontSize = 11
        }
        
        let lineColor = Color.primary  // Adapts to light/dark mode
        
        for beat in tileStartBeat...tileEndBeat {
            let globalX = CGFloat(beat) * pixelsPerBeat
            let localX = globalX - tileOffsetX  // Convert to tile-local coordinates
            
            // Skip if outside this tile's bounds (with margin for text)
            guard localX >= -30 && localX <= size.width + 10 else { continue }
            
            let bar = (beat / beatsPerBar) + 1
            let isBarStart = beat % beatsPerBar == 0
            
            if isBarStart {
                let shouldShowLabel = (bar - 1) % labelBarInterval == 0
                
                var p = Path()
                p.move(to: CGPoint(x: localX, y: 0))
                p.addLine(to: CGPoint(x: localX, y: size.height))
                ctx.stroke(p, with: .color(lineColor), lineWidth: shouldShowLabel ? 1.5 : 1.0)
                
                if shouldShowLabel {
                    let label = "\(bar)"
                    let resolvedText = ctx.resolve(
                        Text(label)
                            .font(.system(size: fontSize, weight: .bold))
                            .foregroundColor(lineColor)
                    )
                    ctx.draw(resolvedText, at: CGPoint(x: localX + 3, y: 4), anchor: .topLeading)
                }
            } else if showBeatTicks {
                var p = Path()
                p.move(to: CGPoint(x: localX, y: 10))
                p.addLine(to: CGPoint(x: localX, y: size.height))
                ctx.stroke(p, with: .color(lineColor.opacity(0.35)), lineWidth: 0.8)
            }
        }
    }
    
    // MARK: - Time Mode (Minutes:Seconds)
    private func drawTimeMode(ctx: GraphicsContext, size: CGSize) {
        let pps = pixelsPerSecond
        guard pps > 0 else { return }
        let totalSeconds = Int(ceil(contentWidth / pps))

        // Adaptive marker interval based on zoom level
        // Show time markers at reasonable intervals - not too sparse
        let majorInterval: Int
        let mediumInterval: Int
        let showMinorTicks: Bool
        let fontSize: CGFloat
        
        if pps < 5 {  // Very zoomed out (< 0.5x)
            majorInterval = 30  // Every 30 seconds
            mediumInterval = 10  // Every 10 seconds
            showMinorTicks = false
            fontSize = 12
        } else if pps < 15 {  // Zoomed out (0.5x - 1.5x)
            majorInterval = 10  // Every 10 seconds
            mediumInterval = 5   // Every 5 seconds
            showMinorTicks = false
            fontSize = 11
        } else if pps < 50 {  // Normal (1.5x - 5.0x)
            majorInterval = 5   // Every 5 seconds
            mediumInterval = 1   // Every second
            showMinorTicks = false
            fontSize = 11
        } else {  // Zoomed in (> 5.0x)
            majorInterval = 5   // Every 5 seconds
            mediumInterval = 1   // Every second
            showMinorTicks = true  // Show half-seconds
            fontSize = 11
        }

        let lineColor = Color(NSColor.labelColor)
        
        for second in 0...totalSeconds {
            let x = CGFloat(second) * pps
            if second % majorInterval == 0 {
                // Major tick - bold line with large label
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(lineColor), lineWidth: 1.5)

                let m = second / 60, s = second % 60
                let label = String(format: "%d:%02d", m, s)
                let resolvedText = ctx.resolve(
                    Text(label)
                        .font(.system(size: fontSize, weight: .bold))
                        .foregroundColor(lineColor)
                )
                ctx.draw(resolvedText, at: CGPoint(x: x + 3, y: 6), anchor: .topLeading)
            } else if second % mediumInterval == 0 {
                // Medium tick with lighter line
                var p = Path()
                p.move(to: CGPoint(x: x, y: 6))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(lineColor.opacity(0.6)), lineWidth: 1)
            } else if showMinorTicks {
                // Minor tick (only when zoomed in enough)
                var p = Path()
                p.move(to: CGPoint(x: x, y: 12))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(lineColor.opacity(0.35)), lineWidth: 0.8)
            }
        }
    }
    
    // MARK: - Beats Mode (Bars.Beats.Ticks)
    private func drawBeatsMode(ctx: GraphicsContext, size: CGSize) {
        // Use the project tempo passed in from the parent
        let tempo = projectTempo
        
        // Calculate timing
        let secondsPerBeat = 60.0 / tempo
        let pixelsPerBeat = CGFloat(secondsPerBeat) * pixelsPerSecond
        let pixelsPerBar = pixelsPerBeat * 4  // 4/4 time
        
        // Calculate how many beats fit in the content width
        let totalBeats = Int(ceil(contentWidth / pixelsPerBeat))
        
        // Assume 4/4 time signature (4 beats per bar)
        let beatsPerBar = 4
        
        // DEBUG: Log values to understand why bars aren't showing at certain zoom levels
        
        // Adaptive label interval based on zoom level
        // Show bar numbers at reasonable intervals - not too sparse
        // Show bar numbers frequently even when zoomed out
        let labelBarInterval: Int
        let showBeatTicks: Bool
        let showBeatLabels: Bool
        let fontSize: CGFloat
        
        if pixelsPerBar < 15 {
            // Extremely zoomed out: show every 4 bars
            labelBarInterval = 4
            showBeatTicks = false
            showBeatLabels = false
            fontSize = 12
        } else if pixelsPerBar < 30 {
            // Very zoomed out: show every 2 bars  
            labelBarInterval = 2
            showBeatTicks = false
            showBeatLabels = false
            fontSize = 12
        } else if pixelsPerBar < 60 {
            // Zoomed out: show every bar
            labelBarInterval = 1
            showBeatTicks = false
            showBeatLabels = false
            fontSize = 11
        } else if pixelsPerBar < 120 {
            // Medium zoom: show every bar with beat ticks
            labelBarInterval = 1
            showBeatTicks = true
            showBeatLabels = false
            fontSize = 11
        } else {
            // Zoomed in: show every bar with beat labels
            labelBarInterval = 1
            showBeatTicks = true
            showBeatLabels = pixelsPerBeat > 20
            fontSize = 11
        }
        
        // Log first few bars being drawn
        var barsDrawn = 0
        
        for beat in 0...totalBeats {
            let x = CGFloat(beat) * pixelsPerBeat
            let bar = (beat / beatsPerBar) + 1  // Bar number (1-based)
            let beatInBar = (beat % beatsPerBar) + 1  // Beat in bar (1-based)
            let isBarStart = beat % beatsPerBar == 0
            
            if isBarStart {
                let shouldShowLabel = (bar - 1) % labelBarInterval == 0
                
                // Log first 3 bars being drawn
                if barsDrawn < 3 {
                    barsDrawn += 1
                }
                
                // Major tick (every bar) - always draw the line
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                
                // Always draw bar line and label for debugging
                // DEBUG: Draw a visible red rectangle to verify Canvas is rendering
                let debugRect = CGRect(x: x, y: 0, width: 20, height: size.height)
                ctx.fill(Path(debugRect), with: .color(.red.opacity(0.3)))
                
                // Bold line for labeled bars
                ctx.stroke(p, with: .color(.primary), lineWidth: 2.0)
                
                // Label: Bar number
                let label = "\(bar)"
                let resolvedText = ctx.resolve(
                    Text(label)
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(.primary)
                )
                ctx.draw(resolvedText, at: CGPoint(x: x + 3, y: 4), anchor: .topLeading)
            } else if showBeatTicks {
                // Minor tick (every beat) - only when zoom allows
                var p = Path()
                p.move(to: CGPoint(x: x, y: 10))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(Color(NSColor.labelColor).opacity(0.35)), lineWidth: 0.8)
                
                // Optional: show beat number if there's enough space
                if showBeatLabels {
                    let label = "\(bar).\(beatInBar)"
                    let resolvedText = ctx.resolve(
                        Text(label)
                            .font(.system(size: 8, weight: .regular))
                            .foregroundColor(Color(NSColor.secondaryLabelColor))
                    )
                    ctx.draw(resolvedText, at: CGPoint(x: x + 2, y: 13), anchor: .topLeading)
                }
            }
        }
    }
}

// MARK: - Ruler Playhead (isolated for performance)
// Uses @Observable AudioEngine for fine-grained updates
// Only this view re-renders when currentPosition changes, not the parent ruler
private struct RulerPlayhead: View {
    @Environment(AudioEngine.self) private var audioEngine
    let height: CGFloat
    let pixelsPerSecond: CGFloat
    
    // Triangle dimensions for playhead head
    private let triangleWidth: CGFloat = 12
    private let triangleHeight: CGFloat = 8
    private let lineWidth: CGFloat = 2
    
    var body: some View {
        // Calculate playhead X position (this is where the CENTER of the line should be)
        let playheadX = CGFloat(audioEngine.currentPosition.timeInterval) * pixelsPerSecond
        
        // Use Canvas for precise pixel-perfect positioning
        Canvas { context, size in
            // Draw triangle head at top, centered on the playhead position
            let trianglePath = Path { path in
                // Triangle centered at playheadX
                let left = playheadX - triangleWidth / 2
                let right = playheadX + triangleWidth / 2
                let top: CGFloat = 0
                let bottom = triangleHeight
                
                path.move(to: CGPoint(x: playheadX, y: bottom))  // Bottom center (point)
                path.addLine(to: CGPoint(x: left, y: top))       // Top left
                path.addLine(to: CGPoint(x: right, y: top))      // Top right
                path.closeSubpath()
            }
            context.fill(trianglePath, with: .color(.red))
            
            // Draw vertical line starting from bottom of triangle to bottom of ruler
            let linePath = Path { path in
                let lineLeft = playheadX - lineWidth / 2
                path.addRect(CGRect(x: lineLeft, y: triangleHeight, width: lineWidth, height: size.height - triangleHeight))
            }
            context.fill(linePath, with: .color(.red))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

