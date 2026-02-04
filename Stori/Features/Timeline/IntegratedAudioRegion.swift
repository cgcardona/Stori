//
//  IntegratedAudioRegion.swift
//  Stori
//
//  Extracted from IntegratedTimelineView.swift
//  Contains the audio region view with resize gestures, context menus, and visualizations
//

import SwiftUI

// MARK: - Integrated Audio Region

/// Audio region view with resize gestures (drag gesture handled by PositionedAudioRegion wrapper)
struct IntegratedAudioRegion: View {
    // Use shared layout constants for consistency with MIDI regions
    private let regionCorner: CGFloat = RegionLayout.cornerRadius
    private let selectionStroke: CGFloat = RegionLayout.selectionStrokeWidth
    private let headerHeight: CGFloat = RegionLayout.headerHeight
    let region: AudioRegion
    let pixelsPerBeat: CGFloat  // Beat-based timeline (proper DAW architecture)
    let tempo: Double  // For beat→seconds conversion
    let trackHeight: CGFloat
    let isSelected: Bool  // Passed from parent - no observation here
    let isMultiSelected: Bool  // True if more than 1 region is selected
    let otherSelectedRegionIds: Set<UUID>  // For batch operations in context menu
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onRangeSelect: ([UUID]) -> Void
    let timeDisplayMode: TimeDisplayMode
    
    // Derived values for pixel positioning
    private var pixelsPerSecond: CGFloat { pixelsPerBeat * CGFloat(tempo / 60.0) }
    
    // Right-edge resize state
    @State private var isHoveringLoopZone: Bool = false
    @State private var isHoveringTrimZone: Bool = false
    @State private var isResizing: Bool = false
    @State private var resizeStartWidth: CGFloat = 0
    @State private var resizeType: ResizeType? = nil
    @State private var liveResizeWidth: CGFloat? = nil // [PHASE-1] Live resize width during drag
    @State private var dragStartCursorX: CGFloat = 0 // Global X position where drag started
    
    // [PHASE-3] Left-edge resize state
    @State private var isHoveringLeftTrimZone: Bool = false
    @State private var isResizingLeftEdge: Bool = false
    @State private var leftEdgeStartOffset: TimeInterval = 0 // Original offset when drag started
    @State private var leftEdgeStartBeat: Double = 0 // Original startBeat when drag started
    @State private var leftEdgeStartDuration: Double = 0 // Original durationBeats when drag started
    @State private var liveLeftEdgeOffset: CGFloat? = nil // Live X offset during left-edge drag (negative = reveal, positive = trim)
    
    // [PHASE-4] Snap state for visual feedback during resize
    @State private var isSnappedToGrid: Bool = false
    @State private var snapLinePosition: CGFloat? = nil // Position to show snap line indicator
    
    // [PHASE-5] Modifier key mode during resize
    private var resizeModifierMode: ResizeModifierMode {
        let flags = NSEvent.modifierFlags
        if flags.contains(.control) { return .loopOnly }
        if flags.contains(.command) { return .free }
        return .normal
    }
    
    enum ResizeModifierMode {
        case normal      // Default behavior with snap if enabled
        case free        // Command: Disable snap temporarily
        case loopOnly    // Control: Only resize to loop boundaries
        
        var label: String? {
            switch self {
            case .normal: return nil
            case .free: return "FREE"
            case .loopOnly: return "LOOP"
            }
        }
        
        var color: Color {
            switch self {
            case .normal: return .clear
            case .free: return .orange
            case .loopOnly: return .purple
            }
        }
    }
    
    // Helper to get SF Symbol for modifier mode
    private func modifierModeIcon(_ mode: ResizeModifierMode) -> String {
        switch mode {
        case .normal: return "circle"
        case .free: return "arrow.left.and.right"
        case .loopOnly: return "repeat"
        }
    }
    
    // Hover state for region highlight (pre-selection feedback)
    @State private var isHoveringRegion: Bool = false
    
    // Regenerate zone state (for AI-generated regions)
    @State private var isHoveringRegenerateZone: Bool = false
    
    // Fade handle state
    @State private var isHoveringFadeInHandle: Bool = false
    @State private var isHoveringFadeOutHandle: Bool = false
    @State private var isDraggingFadeIn: Bool = false
    @State private var isDraggingFadeOut: Bool = false
    @State private var liveFadeIn: TimeInterval? = nil
    @State private var liveFadeOut: TimeInterval? = nil
    @State private var fadeInBeforeDrag: TimeInterval = 0
    @State private var fadeOutBeforeDrag: TimeInterval = 0
    
    // Context menu dependencies
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    let trackId: UUID
    let snapToGrid: Bool
    let isAnchor: Bool
    
    // [V2-ANALYSIS] Access to timeline actions via Environment
    @Environment(\.timelineActions) var timelineActions
    
    // Check if this region is AI-generated
    private var isAIGenerated: Bool {
        region.aiGenerationMetadata != nil
    }
    
    // Resize type enum
    enum ResizeType {
        case loop      // Top-right corner - extends with looping
        case trim      // Bottom-right corner - trims or reveals audio
        case leftTrim  // [PHASE-3] Left edge - trims start or reveals earlier audio
    }
    
    private var regionWidth: CGFloat {
        region.durationBeats * pixelsPerBeat
    }
    
    // [PHASE-1] Display width accounts for live resize during drag
    private var displayWidth: CGFloat {
        // [PHASE-3] For left-edge resize, we keep the full width but clip from the left
        // The width only changes for RIGHT-edge resize
        return liveResizeWidth ?? regionWidth
    }
    
    // [PHASE-1] Display duration accounts for live resize during drag
    // Note: For left-edge resize, we keep full duration - the mask handles visual clipping
    private var displayDuration: TimeInterval {
        guard let liveWidth = liveResizeWidth else { return region.durationSeconds(tempo: tempo) }
        return liveWidth / pixelsPerSecond
    }
    
    // [PHASE-3] Left clip amount - how much to clip from the left edge
    // Positive = trim (hide left portion), Negative = reveal earlier audio (extend left)
    private var leftClipAmount: CGFloat {
        liveLeftEdgeOffset ?? 0
    }
    
    // [PHASE-3] Display width for left-edge resize (visible portion after clipping)
    private var leftResizeDisplayWidth: CGFloat {
        // When revealing (negative offset), width increases; when trimming (positive), width decreases
        max(20, regionWidth - leftClipAmount)
    }
    
    // [PHASE-3] Calculate display offset in beats for step sequencer visualization
    // During live preview, the mask handles clipping so we don't add offset
    // After release, the model's region.offset is already updated
    private func displayOffsetBeats(tempo: Double) -> Double {
        // Use the region's audio offset (updated after resize completes)
        let beatsPerSecond = tempo / 60.0
        return region.offset * beatsPerSecond
    }
    
    private var regionHeight: CGFloat {
        RegionLayout.regionHeight(for: trackHeight)
    }
    
    // isSelected is now passed from parent (no observation here)
    
    // Resize zone properties
    private let resizeZoneWidth: CGFloat = 15 // Width of right-edge resize zones
    private let debugResizeZones: Bool = false // Set to true to visualize zones
    
    /// The content length for one loop iteration (includes empty space if resized)
    private var effectiveContentLength: TimeInterval {
        region.contentLength > 0 ? region.contentLength : region.audioFile.duration
    }
    
    private var loopCount: Int {
        // Calculate how many times the content loops - ONLY if actually looped
        // Uses contentLength (not audioFile.duration) to account for resize with empty space
        guard region.isLooped, effectiveContentLength > 0 else { return 1 }
        return max(1, Int(ceil(region.durationSeconds(tempo: tempo) / effectiveContentLength)))
    }
    
    // [PHASE-1] Preview loop count during resize - only counts if resizing in loop mode
    private var displayLoopCount: Int {
        guard effectiveContentLength > 0 else { return 1 }
        let durationSeconds = liveResizeWidth != nil ? (liveResizeWidth! / pixelsPerSecond) : region.durationSeconds(tempo: tempo)
        // Only show loop count if actually looping (resizeType == .loop) or region is already looped
        if resizeType == .loop || region.isLooped {
            return max(1, Int(ceil(durationSeconds / effectiveContentLength)))
        }
        return 1
    }
    
    private var isLooped: Bool {
        // Only consider looped if explicitly marked as looped
        region.isLooped
    }
    
    // [PHASE-1] Preview looped state during resize
    private var displayIsLooped: Bool {
        // During loop resize, preview as looped; otherwise respect region.isLooped
        (resizeType == .loop && displayLoopCount > 1) || region.isLooped
    }

    // MARK: - Analysis & Processing Badges

    private var tempoLabel: String? {
        guard let tempo = region.detectedTempo else { return nil }
        return "\(Int(round(tempo))) BPM"
    }

    private var keyLabel: String? {
        guard let key = region.detectedKey, !key.isEmpty else { return nil }
        return key
    }

    private var keyConfidenceValue: Float {
        region.keyConfidence ?? 0
    }

    private var shouldShowKeyBadge: Bool {
        keyConfidenceValue >= 0.10
    }

    private var keyBadgeOpacity: Double {
        if keyConfidenceValue >= 0.20 { return 1.0 }
        if keyConfidenceValue >= 0.10 { return 0.6 }
        return 0.0
    }

    private var tempoRateLabel: String? {
        let rate = region.tempoRate
        if abs(rate - 1.0) < 0.01 { return nil }
        return String(format: "×%.2f", rate)
    }

    private var pitchShiftLabel: String? {
        let cents = region.pitchShiftCents
        if abs(cents) < 25 { return nil }
        let semitones = cents / 100.0
        return String(format: "%+.1f st", semitones)
    }

    private var processingLabel: String? {
        let parts = [tempoRateLabel, pitchShiftLabel].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " • ")
    }
    
    // [PHASE-3] Loop badge removed - loop count shown only in resize popup
    private var loopBadgeOverlay: some View {
        EmptyView()
    }

    // [PHASE-4] Anchor badge removed - was showing "AUTO-MATCH ANCHOR" which was confusing
    private var anchorBadgeOverlay: some View {
        EmptyView()
    }

    private var analysisBadgesOverlay: some View {
        Group {
            HStack(spacing: 4) {
                if let tempoText = tempoLabel {
                    Text(tempoText)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.45))
                        .foregroundColor(.white)
                        .cornerRadius(3)
                }

                if shouldShowKeyBadge, let keyText = keyLabel {
                    Text(keyText)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.45))
                        .foregroundColor(.white)
                        .cornerRadius(3)
                        .opacity(keyBadgeOpacity)
                }

                if let procText = processingLabel {
                    Text(procText)
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.55))
                        .foregroundColor(.white)
                        .cornerRadius(3)
                }
            }
            .padding(4)
            .frame(maxWidth: .infinity,
                   maxHeight: .infinity,
                   alignment: .bottomTrailing)  // Moved from topTrailing to avoid covering duration
        }
    }
    
    // Loop dividers overlay (shows vertical dividers at each loop point - professional DAW style)
    // Note: Uses effectiveContentLength (not audioFile.duration) to match waveform tiling
    private var loopDividersOverlay: some View {
        GeometryReader { geometry in
            if displayIsLooped { // [PHASE-1] Use display values for real-time feedback
                // Calculate divider positions - use effectiveContentLength to match waveform tiling
                let iterationWidth = effectiveContentLength * pixelsPerSecond
                let currentLoopCount = displayLoopCount // [PHASE-1] Use display loop count
                
                ZStack(alignment: .leading) {
                    // Vertical dividers at loop points (waveform tiling handles the content now)
                    ForEach(1..<currentLoopCount, id: \.self) { index in
                        let dividerX = iterationWidth * Double(index)
                        
                        // Vertical divider line with notches (professional DAW style)
                        VStack(spacing: 0) {
                            // Top notch
                            Rectangle()
                                .fill(Color.white.opacity(0.7))
                                .frame(width: 2, height: 8)
                            
                            // Vertical line
                            Rectangle()
                                .fill(Color.white.opacity(0.5))
                                .frame(width: 2)
                            
                            // Bottom notch
                            Rectangle()
                                .fill(Color.white.opacity(0.7))
                                .frame(width: 2, height: 8)
                        }
                        .offset(x: dividerX - 1) // Center the 2px line
                    }
                }
            }
        }
    }
    
    // Beat grid overlay (shows beat markers after tempo analysis)
    private var beatGridOverlay: some View {
        GeometryReader { geometry in
            if let beats = region.detectedBeatTimesInSeconds, !beats.isEmpty {
                let downbeats = Set(region.downbeatIndices ?? [])
                
                Canvas { ctx, size in
                    // Draw each beat marker
                    for (index, beatTime) in beats.enumerated() {
                        // Calculate x position within the region
                        let x = beatTime * pixelsPerSecond
                        
                        // Skip beats outside visible region
                        guard x >= 0 && x < size.width else { continue }
                        
                        let isDownbeat = downbeats.contains(index)
                        
                        // Downbeats are more prominent (first beat of measure)
                        let lineWidth: CGFloat = isDownbeat ? 2.5 : 1.5
                        let opacity: CGFloat = isDownbeat ? 0.85 : 0.5
                        let color = isDownbeat ? Color.cyan : Color.white
                        
                        // Draw vertical line from top to bottom
                        let path = Path { p in
                            p.move(to: CGPoint(x: x, y: 0))
                            p.addLine(to: CGPoint(x: x, y: size.height))
                        }
                        
                        ctx.stroke(
                            path,
                            with: .color(color.opacity(opacity)),
                            lineWidth: lineWidth
                        )
                        
                        // Draw a small dot at the top for downbeats
                        if isDownbeat {
                            let dotRect = CGRect(x: x - 4, y: 2, width: 8, height: 8)
                            ctx.fill(
                                Circle().path(in: dotRect),
                                with: .color(Color.cyan.opacity(0.95))
                            )
                        }
                    }
                }
                .allowsHitTesting(false) // Don't interfere with region interactions
            }
        }
    }
    
    // [PHASE-1] Resize indicator overlay (popup below region)
    private var resizeIndicatorOverlay: some View {
        GeometryReader { geometry in
            if isResizing, let type = resizeType, let liveWidth = liveResizeWidth {
                let liveDuration = liveWidth / pixelsPerSecond
                let tempo = projectManager.currentProject?.tempo ?? 120.0
                let beatsPerSecond = tempo / 60.0
                let totalBeats = liveDuration * beatsPerSecond
                let loopCount = displayLoopCount
                
                // Calculate length in bars, beats, sixteenths
                let bars = Int(totalBeats / 4.0)
                let remainingBeats = totalBeats.truncatingRemainder(dividingBy: 4.0)
                let beats = Int(remainingBeats)
                let fractionalBeat = remainingBeats.truncatingRemainder(dividingBy: 1.0)
                let sixteenths = Int(fractionalBeat * 4.0)
                
                // Get modifier mode for badge display
                let mode = resizeModifierMode
                
                // Different tooltip based on operation type
                Group {
                    if type == .loop {
                        // LOOP operation: Show modifier mode or SNAP tooltip with measure/beat display
                        VStack(spacing: 4) {
                            // Modifier mode badge (FREE, LOOP) takes priority over SNAP
                            if let modeLabel = mode.label {
                                HStack(spacing: 4) {
                                    Image(systemName: modifierModeIcon(mode))
                                        .font(.system(size: 9, weight: .bold))
                                    Text(modeLabel)
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundColor(mode.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(3)
                            } else {
                                // Always show SNAP when no modifier mode is active
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right.to.line")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("SNAP")
                                        .font(.system(size: 9, weight: .bold))
                                }
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(3)
                            }
                            
                            // Measure indicator
                            HStack(spacing: 6) {
                                Text("\(bars + 1)")
                                    .font(.system(size: 14, weight: .bold))
                                    .monospacedDigit()
                                Text("\(beats + 1)  \(sixteenths + 1)")
                                    .font(.system(size: 10))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            
                            // Loop count if more than 1 iteration
                            if loopCount > 1 {
                                HStack(spacing: 4) {
                                    Image(systemName: "repeat")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("×\(loopCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .monospacedDigit()
                                }
                                .foregroundColor(.purple.opacity(0.9))
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.9))
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                        )
                        .position(
                            x: liveWidth - 40,
                            y: 30
                        )
                    } else {
                        // TRIM/RESIZE operation: Show length tooltip
                        HStack(spacing: 0) {
                            Text("Length: ")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.7))
                            Text("\(bars).\(beats).\(sixteenths)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.9))
                                .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                        )
                        .position(
                            x: liveWidth - 60, // Position inside the region to avoid clipping
                            y: 30
                        )
                    }
                }
            }
        }
    }
    
    // Resize zones overlay (extracted to reduce body complexity)
    // CRITICAL: Uses .global coordinate space to avoid feedback loop when zone moves during resize
    // Looped regions can only be looped more, NOT resized
    private var resizeZonesOverlay: some View {
        GeometryReader { geometry in
            // If region is already looped, entire right edge is loop zone (no trim allowed)
            // If region is NOT looped, top = loop, bottom = trim/resize
            if region.isLooped {
                // LOOPED REGION: Right edge only is loop zone (can't resize looped regions)
                // FIX: Constrain to right edge only so dragging/moving still works in the middle
                Rectangle()
                    .fill(debugResizeZones ? Color.green.opacity(0.3) : Color.clear)
                    .frame(width: resizeZoneWidth, height: geometry.size.height)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHoveringLoopZone = hovering
                        updateCursor()
                    }
                    .gesture(
                        DragGesture(coordinateSpace: .global)
                            .onChanged { value in
                                handleResizeDragGlobal(value: value, type: .loop)
                            }
                            .onEnded { value in
                                handleResizeEndGlobal(value: value, type: .loop)
                            }
                    )
                    .offset(x: geometry.size.width - resizeZoneWidth)
            } else {
                // NON-LOOPED REGION: Top = loop, Bottom = trim/resize
                VStack(spacing: 0) {
                    // Top half - Loop resize zone
                    Rectangle()
                        .fill(debugResizeZones ? Color.green.opacity(0.3) : Color.clear)
                        .frame(height: geometry.size.height / 2)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringLoopZone = hovering
                            updateCursor()
                        }
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    handleResizeDragGlobal(value: value, type: .loop)
                                }
                                .onEnded { value in
                                    handleResizeEndGlobal(value: value, type: .loop)
                                }
                        )
                    
                    // Bottom half - Trim resize zone (only for non-looped regions)
                    Rectangle()
                        .fill(debugResizeZones ? Color.orange.opacity(0.3) : Color.clear)
                        .frame(height: geometry.size.height / 2)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            isHoveringTrimZone = hovering
                            updateCursor()
                        }
                        .gesture(
                            DragGesture(coordinateSpace: .global)
                                .onChanged { value in
                                    handleResizeDragGlobal(value: value, type: .trim)
                                }
                                .onEnded { value in
                                    handleResizeEndGlobal(value: value, type: .trim)
                                }
                        )
                }
                .frame(width: resizeZoneWidth)
                .offset(x: geometry.size.width - resizeZoneWidth)
            }
        }
    }
    
    // [PHASE-3] Left-edge resize zone overlay (for trimming region start)
    private var leftResizeZoneOverlay: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(debugResizeZones ? Color.blue.opacity(0.3) : Color.clear)
                .frame(width: resizeZoneWidth, height: geometry.size.height)
                .contentShape(Rectangle())
                .offset(x: leftClipAmount) // Stay at the visible left edge during resize
                .onHover { hovering in
                    isHoveringLeftTrimZone = hovering
                    updateCursor()
                }
                .highPriorityGesture(
                    DragGesture(coordinateSpace: .global) // Use global to avoid feedback loop
                        .onChanged { value in
                            handleLeftEdgeDragGlobal(value: value)
                        }
                        .onEnded { value in
                            handleLeftEdgeEndGlobal(value: value)
                        }
                )
        }
    }
    
    // [PHASE-2] Fade handles overlay - visual curves and drag handles
    // Only shows handles when region has fade values or is being hovered
    private var fadeHandlesOverlay: some View {
        GeometryReader { geometry in
            let fadeInWidth = CGFloat(liveFadeIn ?? region.fadeIn) * pixelsPerSecond
            let fadeOutWidth = CGFloat(liveFadeOut ?? region.fadeOut) * pixelsPerSecond
            let regionWidth = geometry.size.width
            let regionHeight = geometry.size.height
            let hasFadeIn = (liveFadeIn ?? region.fadeIn) > 0.01
            let hasFadeOut = (liveFadeOut ?? region.fadeOut) > 0.01
            
            ZStack(alignment: .topLeading) {
                // Fade-in visual curve (triangle at start) - only show if fade exists
                if fadeInWidth > 2 {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: fadeInWidth, y: 0))
                        path.addLine(to: CGPoint(x: 0, y: regionHeight))
                        path.closeSubpath()
                    }
                    .fill(Color.black.opacity(0.4))
                }
                
                // Fade-out visual curve (triangle at end) - only show if fade exists
                if fadeOutWidth > 2 {
                    Path { path in
                        path.move(to: CGPoint(x: regionWidth, y: 0))
                        path.addLine(to: CGPoint(x: regionWidth - fadeOutWidth, y: 0))
                        path.addLine(to: CGPoint(x: regionWidth, y: regionHeight))
                        path.closeSubpath()
                    }
                    .fill(Color.black.opacity(0.4))
                }
                
                // Fade-in handle (draggable) - only show if fade exists or dragging
                if hasFadeIn || isDraggingFadeIn {
                    Circle()
                        .fill(isHoveringFadeInHandle || isDraggingFadeIn ? Color.white : Color.white.opacity(0.7))
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .position(x: max(5, fadeInWidth), y: headerHeight + 10)
                        .contentShape(Rectangle().size(CGSize(width: 20, height: 30)))
                        .onHover { hovering in
                            isHoveringFadeInHandle = hovering
                            if hovering {
                                NSCursor.resizeLeftRight.push()
                            } else if !isDraggingFadeIn {
                                NSCursor.pop()
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if !isDraggingFadeIn {
                                        // Capture value at drag start
                                        fadeInBeforeDrag = region.fadeIn
                                    }
                                    isDraggingFadeIn = true
                                    let newFadeInPixels = max(0, value.location.x)
                                    let maxFadePixels = regionWidth - fadeOutWidth - 20
                                    let clampedPixels = min(newFadeInPixels, maxFadePixels)
                                    liveFadeIn = TimeInterval(clampedPixels / pixelsPerSecond)
                                }
                                .onEnded { _ in
                                    isDraggingFadeIn = false
                                    if let newFade = liveFadeIn {
                                        // Register undo before applying change
                                        if abs(newFade - fadeInBeforeDrag) > 0.001 {
                                            UndoService.shared.registerFadeInChange(region.id, in: trackId, from: fadeInBeforeDrag, to: newFade, projectManager: projectManager)
                                        }
                                        updateFadeIn(newFade)
                                    }
                                    liveFadeIn = nil
                                    NSCursor.pop()
                                }
                        )
                }
                
                // Fade-out handle (draggable) - only show if fade exists or dragging
                if hasFadeOut || isDraggingFadeOut {
                    Circle()
                        .fill(isHoveringFadeOutHandle || isDraggingFadeOut ? Color.white : Color.white.opacity(0.7))
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.3), radius: 2)
                        .position(x: regionWidth - max(5, fadeOutWidth), y: headerHeight + 10)
                        .contentShape(Rectangle().size(CGSize(width: 20, height: 30)))
                        .onHover { hovering in
                            isHoveringFadeOutHandle = hovering
                            if hovering {
                                NSCursor.resizeLeftRight.push()
                            } else if !isDraggingFadeOut {
                                NSCursor.pop()
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if !isDraggingFadeOut {
                                        // Capture value at drag start
                                        fadeOutBeforeDrag = region.fadeOut
                                    }
                                    isDraggingFadeOut = true
                                    let distanceFromRight = regionWidth - value.location.x
                                    let maxFadePixels = regionWidth - fadeInWidth - 20
                                    let clampedPixels = min(max(0, distanceFromRight), maxFadePixels)
                                    liveFadeOut = TimeInterval(clampedPixels / pixelsPerSecond)
                                }
                                .onEnded { _ in
                                    isDraggingFadeOut = false
                                    if let newFade = liveFadeOut {
                                        // Register undo before applying change
                                        if abs(newFade - fadeOutBeforeDrag) > 0.001 {
                                            UndoService.shared.registerFadeOutChange(region.id, in: trackId, from: fadeOutBeforeDrag, to: newFade, projectManager: projectManager)
                                        }
                                        updateFadeOut(newFade)
                                    }
                                    liveFadeOut = nil
                                    NSCursor.pop()
                                }
                        )
                }
            }
        }
    }
    
    /// Update fade in value
    private func updateFadeIn(_ newValue: TimeInterval) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == region.id }) else {
            return
        }
        
        project.tracks[trackIndex].regions[regionIndex].fadeIn = newValue
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    /// Update fade out value
    private func updateFadeOut(_ newValue: TimeInterval) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == region.id }) else {
            return
        }
        
        project.tracks[trackIndex].regions[regionIndex].fadeOut = newValue
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    // Regenerate zone overlay (top-left corner for AI-generated regions)
    // Note: Regeneration disabled - AI generation now handled via cloud composer
    private var regenerateZoneOverlay: some View {
        EmptyView()
    }
    
    // [V2-MULTISELECT] Helper to get ordered region IDs in this track
    private func audioTrackRegionOrder() -> [UUID] {
        (projectManager.currentProject?
            .tracks.first(where: { $0.id == trackId })?
            .regions.sorted(by: { $0.startBeat < $1.startBeat })
            .map(\.id)) ?? []
    }
    
    // [V2-MULTISELECT] Get all regions across all tracks, ordered by start beat
    private func allRegionsOrder() -> [UUID] {
        guard let project = projectManager.currentProject else { return [] }
        
        let allRegions = project.tracks.flatMap { track in
            track.regions.map { region in
                (id: region.id, startBeat: region.startBeat)
            }
        }
        
        return allRegions
            .sorted(by: { $0.startBeat < $1.startBeat })
            .map(\.id)
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Main region background
            RoundedRectangle(cornerRadius: 4)
                .fill(regionColor.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(regionColor, lineWidth: 1)
                )
            
            // Professional-style header using shared component
            VStack {
                RegionHeaderView(
                    isSelected: isSelected,
                    baseColor: regionColor,
                    height: headerHeight,
                    cornerRadius: regionCorner
                ) {
                    HStack(spacing: 6) {
                        // Track icon - white for consistency with MIDI regions
                        Image(systemName: trackIcon)
                            .font(.system(size: 10, weight: .semibold))
                        
                        Text(region.audioFile.name)
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .fixedSize(horizontal: false, vertical: true)

                        Spacer(minLength: 4)
                    }
                    .foregroundColor(.white)  // White text for all regions (unified with MIDI)
                    .padding(.leading, 8)
                    .padding(.trailing, 6)
                    .padding(.top, 1)
                }
                Spacer()
            }
            .zIndex(2)  // ⬅️ ensure header stays above waveform
            
            // Selection border overlay using shared component
            RegionSelectionBorder(
                isSelected: isSelected,
                cornerRadius: regionCorner,
                strokeWidth: selectionStroke
            )
            .zIndex(1)  // ⬅️ behind header but above waveform
            
            // Content visualization: Step sequencer grid OR waveform
            // [PHASE-1] Use display values for real-time resize visualization
            Group {
                if let sequencerMeta = region.stepSequencerMetadata {
                    // Step sequencer grid visualization
                    // [PHASE-3] Pass offset for left-edge trim visualization
                    let offsetBeats = displayOffsetBeats(tempo: sequencerMeta.tempo)
                    // Calculate display content length (for live preview during resize)
                    let displayContentLen = resizeType == .trim && liveResizeWidth != nil 
                        ? (liveResizeWidth! / pixelsPerSecond) 
                        : effectiveContentLength
                    StepSequencerRegionVisualization(
                        pattern: sequencerMeta.pattern,
                        regionDuration: displayDuration, // Use live duration during resize
                        tempo: sequencerMeta.tempo,
                        width: displayWidth, // Use live width during resize
                        height: regionHeight - headerHeight,
                        offsetBeats: offsetBeats,
                        isLooped: displayIsLooped, // Only tile pattern when looping
                        contentLength: displayContentLen,
                        audioFileDuration: region.audioFile.duration
                    )
                    .padding(.top, headerHeight)
                } else {
                    // Professional waveform visualization using real audio data
                    // Waveform is at FIXED width based on audio duration,
                    // NOT scaled to region width. Resizing shows empty space, looping tiles.
                    let audioContentWidth = region.audioFile.duration * pixelsPerSecond
                    let iterationWidth = effectiveContentLength * pixelsPerSecond
                    
                    // Use HStack to tile waveforms for looping - each at natural width
                    // This prevents re-rendering when displayWidth changes
                    HStack(spacing: 0) {
                        ForEach(0..<displayLoopCount, id: \.self) { loopIndex in
                            ProfessionalWaveformView(
                                audioFile: region.audioFile,
                                style: .bars,
                                color: .white,
                                regionOffset: region.offset,
                                regionDuration: region.audioFile.duration
                            )
                            // Fixed width based on audio content - NEVER scales with region
                            .frame(width: audioContentWidth, height: regionHeight - headerHeight)
                            // If contentLength > audioFile.duration, add empty space
                            .frame(width: iterationWidth, alignment: .leading)
                            // Looped iterations (after first) are slightly dimmer - matches step sequencer style
                            .opacity(loopIndex == 0 ? 1.0 : 0.7)
                        }
                    }
                    .frame(width: displayWidth, alignment: .leading) // Clip to region bounds
                    .clipped()
                    .opacity(isSelected ? 0.3 : 0.6)
                    .padding(.horizontal, 4)
                    .padding(.top, headerHeight)
                    .overlay(loopDividersOverlay)
                    .overlay(beatGridOverlay)
                }
            }
            .clipped() // [PHASE-1] Clip content when resizing smaller
            .zIndex(0)  // ⬅️ below the header
        }
        .frame(width: displayWidth, height: regionHeight)
        // [PHASE-3] For left-edge resize, apply a clip mask that hides the left portion
        .mask(
            GeometryReader { geometry in
                Rectangle()
                    .frame(width: geometry.size.width - leftClipAmount, height: geometry.size.height)
                    .offset(x: leftClipAmount)
            }
        )
        .animation(nil, value: liveResizeWidth) // [PHASE-1] No animation during drag - direct tracking for smoothness
        .animation(nil, value: liveLeftEdgeOffset) // [PHASE-3] No animation for left-edge resize
        // NOTE: Copy mode indicator (green border with COPY label) is now handled
        // by PositionedAudioRegion wrapper via shared RegionDragHandler
        .overlay(loopBadgeOverlay)
        .overlay(anchorBadgeOverlay)
        .overlay(analysisBadgesOverlay)
        .overlay(resizeZonesOverlay)
        .overlay(leftResizeZoneOverlay) // [PHASE-3] Left-edge resize
        .overlay(resizeIndicatorOverlay) // [PHASE-1] New resize indicator
        .overlay(leftResizeIndicatorOverlay) // [PHASE-3] Left-edge indicator
        .overlay(fadeHandlesOverlay) // [PHASE-2] Fade in/out handles
        .overlay(regenerateZoneOverlay)
        // Hover highlight overlay (pre-selection feedback) - using shared component
        .overlay(
            RegionHoverHighlight(
                isHovering: isHoveringRegion,
                isSelected: isSelected,
                cornerRadius: regionCorner
            )
        )
        .scaleEffect(1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isHoveringRegion)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringRegion = hovering
        }
        // [V2-MULTISELECT] Exclusive gesture handling to prevent conflicts
        .gesture(
            // Cmd+click = toggle (highest priority)
            TapGesture().modifiers(.command).onEnded {
                onToggle()
            }
                .exclusively(before:
                                // Shift+click = range selection
                             TapGesture().modifiers(.shift).onEnded {
                                 let ids = allRegionsOrder()
                                 onRangeSelect(ids)
                             }
                    .exclusively(before:
                                    // Plain click = select only (lowest priority)
                                 TapGesture().onEnded {
                                     onSelect()
                                 }
                                )
                            )
        )
        // NOTE: Movement drag gesture is now handled by PositionedAudioRegion wrapper
        // using shared RegionDragHandler for consistent behavior with MIDI regions
        .contextMenu {
            regionContextMenu
        }
        .clipShape(RoundedRectangle(cornerRadius: 4)) // replaces .clipped()
        .shadow(
            color: isSelected ? Color.blue.opacity(0.5) : Color.clear,
            radius: 8,
            x: 0,
            y: 2
        )
    }
    
    private var regionColor: Color {
        // Use the track's color for consistency
        guard let project = projectManager.currentProject,
              let track = project.tracks.first(where: { $0.id == trackId }) else {
            return .blue // Fallback color
        }
        return track.color.color
    }
    
    private var trackIcon: String {
        // Get the track icon
        guard let project = projectManager.currentProject,
              let track = project.tracks.first(where: { $0.id == trackId }) else {
            return "music.quarternote.3"
        }
        
        // First check for explicit icon override
        if let explicitIcon = track.iconName, !explicitIcon.isEmpty {
            return explicitIcon
        }
        
        // Use track type icon for MIDI/Instrument tracks
        if track.isMIDITrack {
            return track.trackTypeIcon
        }
        
        return defaultIconName(for: track.name)
    }
    
    private func defaultIconName(for trackName: String) -> String {
        let name = trackName.lowercased()
        if name.contains("kick") || name.contains("drum") { return "music.note" }
        if name.contains("bass") { return "waveform" }
        if name.contains("guitar") { return "guitars" }
        if name.contains("piano") || name.contains("keys") { return "pianokeys" }
        if name.contains("vocal") || name.contains("voice") { return "mic" }
        if name.contains("synth") { return "tuningfork" }
        return "music.quarternote.3"
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(round(duration))  // Round instead of truncate
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - Resize Functions
    
    private func updateCursor() {
        // Keep resize cursor during active resize/loop operations
        if isResizing || isResizingLeftEdge {
            NSCursor.resizeLeftRight.set()
            return
        }
        
        if isHoveringRegenerateZone {
            // Use custom regenerate cursor for AI-generated regions
            NSCursor.regenerate.set()
        } else if isHoveringLoopZone {
            // Use custom loop cursor to clearly indicate loop/repeat operation
            NSCursor.loop.set()
        } else if isHoveringTrimZone {
            NSCursor.resizeLeftRight.set()
        } else if isHoveringLeftTrimZone {
            // [PHASE-3] Left edge trim cursor
            NSCursor.resizeLeftRight.set()
        } else {
            NSCursor.arrow.set()
        }
    }
    
    // MARK: - Global Coordinate Resize Handlers (avoids feedback loop)
    
    private func handleResizeDragGlobal(value: DragGesture.Value, type: ResizeType) {
        if !isResizing {
            isResizing = true
            resizeStartWidth = regionWidth
            resizeType = type
            dragStartCursorX = value.startLocation.x
        }
        
        // With GLOBAL coordinate space, translation is stable (not affected by view moving)
        let dragDistance = value.translation.width
        var newWidth = max(20, resizeStartWidth + dragDistance)
        let tempo = projectManager.currentProject?.tempo ?? 120.0
        
        // [PHASE-5] Apply modifier key behaviors
        let mode = resizeModifierMode
        
        switch mode {
        case .free:
            // Command key: Disable snap temporarily
            isSnappedToGrid = false
            snapLinePosition = nil
            
        case .loopOnly:
            // Control key: Only allow exact loop multiples
            let audioFileDuration = region.audioFile.duration
            let rawDuration = newWidth / pixelsPerSecond
            let loopCount = max(1, round(rawDuration / audioFileDuration))
            let snappedDuration = loopCount * audioFileDuration
            let snappedWidth = snappedDuration * pixelsPerSecond
            
            newWidth = snappedWidth
            isSnappedToGrid = true
            snapLinePosition = snappedWidth
            
        case .normal:
            // Default: Use global snap setting
            if snapToGrid {
                let rawDuration = newWidth / pixelsPerSecond
                let snappedDuration = calculateSnapInterval(for: rawDuration, mode: timeDisplayMode, tempo: tempo)
                let snappedWidth = snappedDuration * pixelsPerSecond
                
                let snapThreshold: CGFloat = 10.0
                if abs(newWidth - snappedWidth) < snapThreshold {
                    newWidth = snappedWidth
                    isSnappedToGrid = true
                    snapLinePosition = snappedWidth
                } else {
                    isSnappedToGrid = false
                    snapLinePosition = snappedWidth
                }
            } else {
                isSnappedToGrid = false
                snapLinePosition = nil
            }
        }
        
        liveResizeWidth = newWidth
    }
    
    private func handleResizeEndGlobal(value: DragGesture.Value, type: ResizeType) {
        let dragDistance = value.translation.width
        var newWidth = max(20, resizeStartWidth + dragDistance)
        let tempo = projectManager.currentProject?.tempo ?? 120.0
        
        // [PHASE-5] Apply same modifier logic as during drag
        let mode = resizeModifierMode
        var finalDurationSeconds: TimeInterval
        
        switch mode {
        case .free:
            // No snapping
            finalDurationSeconds = newWidth / pixelsPerSecond
            
        case .loopOnly:
            // Only exact loop multiples
            let audioFileDuration = region.audioFile.duration
            let rawDuration = newWidth / pixelsPerSecond
            let loopCount = max(1, round(rawDuration / audioFileDuration))
            finalDurationSeconds = loopCount * audioFileDuration
            
        case .normal:
            // Use global snap setting
            let rawDuration = newWidth / pixelsPerSecond
            finalDurationSeconds = snapToGrid ? calculateSnapInterval(for: rawDuration, mode: timeDisplayMode, tempo: tempo) : rawDuration
        }
        
        // Convert duration from seconds to beats for storage
        let finalDurationBeats = finalDurationSeconds * (tempo / 60.0)
        
        // Update the region based on resize type
        guard var project = projectManager.currentProject else { return }
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == region.id }) else {
            return
        }
        
        switch type {
        case .loop:
            // Loop resize - extend duration and mark as looped only if duration exceeds content length
            // Use contentLength (includes empty space) not audioFile.duration
            let loopUnit = region.contentLength > 0 ? region.contentLength : region.audioFile.duration
            project.tracks[trackIndex].regions[regionIndex].durationBeats = finalDurationBeats
            // CRITICAL: Clear isLooped if user drags back to original size (duration <= loopUnit in seconds)
            project.tracks[trackIndex].regions[regionIndex].isLooped = finalDurationSeconds > loopUnit
            
        case .trim:
            // Trim/Resize - extends region duration WITHOUT looping (creates empty space)
            // This is different from loop which repeats the content
            let newDurationBeats = max(0.1 * (tempo / 60.0), finalDurationBeats) // Minimum 0.1 seconds in beats
            project.tracks[trackIndex].regions[regionIndex].durationBeats = newDurationBeats
            // CRITICAL: Set contentLength to this duration in seconds - this becomes the new "base unit" for future loops
            project.tracks[trackIndex].regions[regionIndex].contentLength = max(0.1, finalDurationSeconds)
            // CRITICAL: Explicitly disable looping - resize means empty space, not repeated content
            project.tracks[trackIndex].regions[regionIndex].isLooped = false
            
        case .leftTrim:
            // Left trim is handled by separate handlers (handleLeftEdgeEndGlobal)
            // This case should not be reached, but is required for exhaustiveness
            return
        }
        
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Lightweight update - no graph rebuild needed for region resize/loop
        audioEngine.updateProjectData(project)
        
        // [PHASE-1] Reset resize state AFTER a short delay to let model updates propagate
        // This prevents the visual "snap back" when liveResizeWidth is cleared before region updates
        isResizing = false
        resizeType = nil
        
        // [PHASE-4] Reset snap state
        isSnappedToGrid = false
        snapLinePosition = nil
        
        updateCursor()
        
        // Delay clearing liveResizeWidth to allow parent view to re-render with updated region.duration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.liveResizeWidth = nil
        }
        
    }
    
    // MARK: - [PHASE-3] Left-Edge Resize Handlers
    
    private func handleLeftEdgeDragGlobal(value: DragGesture.Value) {
        if !isResizingLeftEdge {
            isResizingLeftEdge = true
            leftEdgeStartOffset = region.offset  // Audio offset in seconds
            leftEdgeStartBeat = region.startBeat  // Position in beats
            leftEdgeStartDuration = region.durationBeats  // Duration in beats
        }
        
        // With global coordinates, translation is stable
        let dragDistance = value.translation.width
        
        // Calculate constraints:
        // - Can't extend left past beginning of audio file (offset >= 0)
        // - Can't shrink so much that duration becomes too small (min 0.1s)
        let maxLeftExtend = leftEdgeStartOffset * pixelsPerSecond  // How far left we can go (pixels)
        let maxRightShrink = (leftEdgeStartDuration - 0.1) * pixelsPerSecond  // How far right we can go (pixels)
        
        // Clamp the drag distance
        let clampedDrag = max(-maxLeftExtend, min(dragDistance, maxRightShrink))
        
        liveLeftEdgeOffset = clampedDrag
        
    }
    
    private func handleLeftEdgeEndGlobal(value: DragGesture.Value) {
        let dragDistance = value.translation.width
        let tempo = projectManager.currentProject?.tempo ?? 120.0
        
        // Apply same clamping as in drag
        let maxLeftExtend = leftEdgeStartOffset * pixelsPerSecond
        let maxRightShrink = (leftEdgeStartDuration - 0.1) * pixelsPerSecond
        let clampedDrag = max(-maxLeftExtend, min(dragDistance, maxRightShrink))
        
        // Convert pixel drag to time offset (in seconds for audio offset and duration)
        let offsetChangeSeconds = clampedDrag / pixelsPerSecond
        // Also convert to beats for the start position
        let offsetChangeBeats = clampedDrag / pixelsPerBeat
        
        // Calculate new values
        var newOffset = leftEdgeStartOffset + offsetChangeSeconds
        var newStartBeat = leftEdgeStartBeat + offsetChangeBeats
        var newDurationSeconds = leftEdgeStartDuration - offsetChangeSeconds
        
        // Apply snap if enabled (snap beat position)
        if snapToGrid {
            let snappedBeat = round(newStartBeat)  // Snap to nearest beat
            let startBeatChange = snappedBeat - leftEdgeStartBeat
            // Convert beat change to seconds for offset/duration adjustment
            let startTimeChangeSeconds = startBeatChange * (60.0 / tempo)
            newStartBeat = snappedBeat
            newOffset = leftEdgeStartOffset + startTimeChangeSeconds
            newDurationSeconds = leftEdgeStartDuration - startTimeChangeSeconds
        }
        
        // Ensure constraints are still met after snapping
        newOffset = max(0, newOffset)
        newDurationSeconds = max(0.1, newDurationSeconds)
        
        
        // Update the region
        guard var project = projectManager.currentProject else { return }
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == region.id }) else {
            return
        }
        
        // Convert duration from seconds to beats for storage
        let newDurationBeats = newDurationSeconds * (tempo / 60.0)
        
        project.tracks[trackIndex].regions[regionIndex].offset = newOffset
        project.tracks[trackIndex].regions[regionIndex].startBeat = newStartBeat
        project.tracks[trackIndex].regions[regionIndex].durationBeats = newDurationBeats
        
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Lightweight update - no graph rebuild needed for left-edge trim
        audioEngine.updateProjectData(project)
        
        // Reset left-edge resize state
        isResizingLeftEdge = false
        updateCursor()
        
        // Delay clearing to allow re-render
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.liveLeftEdgeOffset = nil
        }
    }
    
    // [PHASE-3] Left-edge resize indicator overlay - positioned ABOVE region to avoid clipping
    private var leftResizeIndicatorOverlay: some View {
        GeometryReader { geometry in
            if isResizingLeftEdge, let leftOffset = liveLeftEdgeOffset, leftOffset > 0 {
                let offsetTimeSeconds = leftOffset / pixelsPerSecond
                let offsetBeats = leftOffset / pixelsPerBeat
                let newStartBeats = leftEdgeStartBeat + offsetBeats
                let measureNumber = Int(floor(newStartBeats / 4.0)) + 1
                let beatInMeasure = Int(newStartBeats.truncatingRemainder(dividingBy: 4.0)) + 1
                let offsetTime = offsetTimeSeconds  // For display
                
                // Position popup ABOVE the visible left edge (not below, to avoid track clipping)
                VStack(spacing: 4) {
                    // Show trim amount
                    HStack(spacing: 4) {
                        Image(systemName: "scissors")
                            .font(.system(size: 9, weight: .bold))
                        Text(String(format: "-%.2fs", offsetTime))
                            .font(.system(size: 10, weight: .bold))
                            .monospacedDigit()
                    }
                    .foregroundColor(.orange)
                    
                    // Measure indicator
                    HStack(spacing: 6) {
                        Text("\(measureNumber)")
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                        Text("\(beatInMeasure)  1  1")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.9))
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                )
                .position(
                    x: leftOffset + 50, // At visible left edge
                    y: -25 // ABOVE the region
                )
            }
        }
        .allowsHitTesting(false) // Don't block interactions
    }
    
    // MARK: - Context Menu
    private var regionContextMenu: some View {
        Group {
            Button("Cut") {
                // TODO: Implement cut
            }
            
            Button("Copy") {
                // TODO: Implement copy
            }
            
            Button("Split at Playhead") {
                let playheadBeat = audioEngine.currentPosition.beats
                splitRegionAtPlayhead(playheadBeat)
            }
            .disabled(!canSplitAtPlayhead)
            
            Divider()
            
            Button("Delete") {
                projectManager.removeRegionFromTrack(region.id, trackId: trackId, audioEngine: audioEngine)
                // audioEngine.loadProject is now called inside removeRegionFromTrack
            }
            
            Divider()
            
            Button("Duplicate") {
                duplicateRegion()
            }
            
            Divider()
            
            // 🎵 Audio Analysis
            Button("Analyze Audio (Tempo & Key)") {
                timelineActions.analyzeRegion(region.id)
            }
            
            Divider()
            
            // [V2-MULTISELECT] Pitch/Tempo Matching (only show when multiple regions selected)
            if isMultiSelected {
                Menu("Pitch & Tempo Matching") {
                    Button("Match Tempo to This Region") {
                        timelineActions.matchTempoToRegion(region.id)
                    }
                    
                    Button("Match Pitch to This Region") {
                        timelineActions.matchPitchToRegion(region.id)
                    }
                    
                    Divider()
                    
                    Button("Auto-Match All Selected") {
                        timelineActions.autoMatchSelectedRegions()
                    }
                    
                    Divider()
                    
                    Menu("Advanced Matching") {
                        Button("Sync to Project Tempo") {
                            syncSelectedToProjectTempo()
                        }
                        
                        Button("Harmonize Selected Regions") {
                            harmonizeSelectedRegions()
                        }
                        
                        Button("Reset Pitch & Tempo") {
                            resetPitchTempoForSelected()
                        }
                    }
                }
                
                Divider()
            }
            
            // 🎧 Audio Export Options
            Menu("Export Audio") {
                Button("Export Original") {
                    timelineActions.exportOriginalAudio(region.id)
                }
                
                Button("Export Processed") {
                    timelineActions.exportProcessedAudio(region.id)
                }
                
                Divider()
                
                Button("Export Comparison (Both)") {
                    timelineActions.exportAudioComparison(region.id)
                }
            }
            
            Divider()
            
            Button("Fade In...") {
                // TODO: Implement fade in
            }
            Button("Fade Out...") {
                // TODO: Implement fade out
            }
        }
    }
    
    // MARK: - Context Menu Helpers
    private var canSplitAtPlayhead: Bool {
        // Convert playhead from seconds to beats for comparison
        let tempo = projectManager.currentProject?.tempo ?? 120.0
        let playheadBeat = audioEngine.currentPosition.beats  // Use beats directly, not time
        let regionEndBeat = region.endBeat
        return playheadBeat > region.startBeat && playheadBeat < regionEndBeat
    }
    
    private func splitRegionAtPlayhead(_ playheadBeat: Double) {
        projectManager.splitRegionAtPosition(region.id, trackId: trackId, splitBeat: playheadBeat)
    }
    
    private func duplicateRegion() {
        // Duplicate at end of current region (in beats)
        let tempo = projectManager.currentProject?.tempo ?? 120.0
        let duplicatedRegion = AudioRegion(
            audioFile: region.audioFile,
            startBeat: region.endBeat,
            durationBeats: region.durationBeats,
            tempo: tempo,
            fadeIn: region.fadeIn,
            fadeOut: region.fadeOut,
            gain: region.gain,
            isLooped: region.isLooped,
            offset: region.offset
        )
        projectManager.addRegionToTrack(duplicatedRegion, trackId: trackId)
    }
    
    // MARK: [V2-MULTISELECT] Pitch/Tempo Matching Actions
    // NOTE: Smart beat snap, duplicateRegionAt, duplicateRegionToTrack, and getTargetTrack
    // are now in PositionedAudioRegion to work with the shared RegionDragHandler
    
    private func matchTempoToRegion(_ targetRegionId: UUID) {
        
        Task { @MainActor in
            guard let project = projectManager.currentProject else {
                return
            }
            
            // Find target region and its audio file
            guard let targetRegion = findRegion(targetRegionId, in: project) else {
                return
            }
            let targetFile = targetRegion.audioFile
            
            // Analyze target region tempo
            // TODO: Implement real analysis - temporarily stubbed
            let targetTempo: Double? = 120.0 // Stub tempo
            guard let targetTempo = targetTempo else {
                return
            }
            
            // Update target region with detected tempo
            updateRegionTempo(targetRegionId, tempo: targetTempo)
            
            // Process other selected regions
            for regionId in otherSelectedRegionIds {
                guard let region = findRegion(regionId, in: project) else {
                    continue
                }
                let audioFile = region.audioFile
                
                // Detect region's current tempo
                // TODO: Implement real analysis - temporarily stubbed
                let regionTempo: Double? = 120.0 // Stub tempo
                updateRegionTempo(regionId, tempo: regionTempo)
                
                // Calculate tempo adjustment
                let tempoRate: Float
                if let regionTempo = regionTempo {
                    tempoRate = Float(targetTempo / regionTempo)
                } else {
                    tempoRate = 1.0
                }
                
                // Apply tempo adjustment to the track
                updateRegionTempoRate(regionId, rate: tempoRate)
                applyTempoRateToTrack(regionId, rate: tempoRate)
            }
            
        }
    }
    
    private func matchPitchToRegion(_ targetRegionId: UUID) {
        
        Task { @MainActor in
            guard let project = projectManager.currentProject else {
                return
            }
            
            // Find target region and its audio file
            guard let targetRegion = findRegion(targetRegionId, in: project) else {
                return
            }
            let targetFile = targetRegion.audioFile
            
            // Analyze target region key
            // TODO: Implement real analysis - temporarily stubbed
            let targetKey: String? = "C Major" // Stub key
            guard let targetKey = targetKey else {
                return
            }
            
            // Update target region with detected key
            updateRegionKey(targetRegionId, key: targetKey)
            
            // Process other selected regions
            for regionId in otherSelectedRegionIds {
                guard let region = findRegion(regionId, in: project) else {
                    continue
                }
                let audioFile = region.audioFile
                
                // Detect region's current key
                // TODO: Implement real analysis - temporarily stubbed
                let regionKey: String? = "C Major" // Stub key
                updateRegionKey(regionId, key: regionKey)
                
                // Calculate pitch adjustment (simplified - real implementation would need music theory)
                let pitchShift: Float
                if let regionKey = regionKey {
                    pitchShift = calculatePitchShift(from: regionKey, to: targetKey)
                } else {
                    pitchShift = 0.0
                }
                
                // Apply pitch adjustment to the track
                updateRegionPitchShift(regionId, cents: pitchShift)
                applyPitchShiftToTrack(regionId, cents: pitchShift)
            }
            
        }
    }
    
    private func autoMatchSelectedRegions() {
        // TODO Phase 3: Implement intelligent auto-matching
        // 1. Analyze all selected regions for tempo and key
        // 2. Determine optimal target tempo and key
        // 3. Apply smart adjustments to create harmonic/rhythmic coherence
    }
    
    // MARK: - Helper Functions for Audio Analysis
    
    private func findRegion(_ regionId: UUID, in project: AudioProject) -> AudioRegion? {
        for track in project.tracks {
            if let region = track.regions.first(where: { $0.id == regionId }) {
                return region
            }
        }
        return nil
    }
    
    private func updateRegionTempo(_ regionId: UUID, tempo: Double?) {
        guard let project = projectManager.currentProject else { return }
        
        for trackIndex in project.tracks.indices {
            if let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].detectedTempo = tempo
                return
            }
        }
    }
    
    private func updateRegionKey(_ regionId: UUID, key: String?) {
        guard let project = projectManager.currentProject else { return }
        
        for trackIndex in project.tracks.indices {
            if let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].detectedKey = key
                return
            }
        }
    }
    
    private func updateRegionTempoRate(_ regionId: UUID, rate: Float) {
        guard let project = projectManager.currentProject else { return }
        
        for trackIndex in project.tracks.indices {
            if let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].tempoRate = rate
                return
            }
        }
    }
    
    private func updateRegionPitchShift(_ regionId: UUID, cents: Float) {
        guard let project = projectManager.currentProject else { return }
        
        for trackIndex in project.tracks.indices {
            if let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].pitchShiftCents = cents
                return
            }
        }
    }
    
    private func applyTempoRateToTrack(_ regionId: UUID, rate: Float) {
        guard let project = projectManager.currentProject else { return }
        
        // Find which track contains this region
        for track in project.tracks {
            if track.regions.contains(where: { $0.id == regionId }) {
                if let trackNode = audioEngine.getTrackNode(for: track.id) {
                    trackNode.setPlaybackRate(rate)
                }
                return
            }
        }
    }
    
    private func applyPitchShiftToTrack(_ regionId: UUID, cents: Float) {
        guard let project = projectManager.currentProject else { return }
        
        // Find which track contains this region
        for track in project.tracks {
            if track.regions.contains(where: { $0.id == regionId }) {
                if let trackNode = audioEngine.getTrackNode(for: track.id) {
                    trackNode.setPitchShift(cents)
                }
                return
            }
        }
    }
    
    private func calculatePitchShift(from sourceKey: String, to targetKey: String) -> Float {
        // Simplified pitch shift calculation - real implementation would use music theory
        // This is a placeholder that returns 0 for same key, random shift for different keys
        
        if sourceKey == targetKey {
            return 0.0
        }
        
        // Extract root notes (simplified)
        let sourceRoot = String(sourceKey.prefix(1))
        let targetRoot = String(targetKey.prefix(1))
        
        let noteOrder = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        
        guard let sourceIndex = noteOrder.firstIndex(of: sourceRoot),
              let targetIndex = noteOrder.firstIndex(of: targetRoot) else {
            return 0.0
        }
        
        // Calculate semitone difference
        var semitones = targetIndex - sourceIndex
        if semitones > 6 { semitones -= 12 }
        if semitones < -6 { semitones += 12 }
        
        // Convert to cents (100 cents per semitone)
        return Float(semitones * 100)
    }
    
    private func syncSelectedToProjectTempo() {
        // TODO Phase 2: Implement project tempo sync
        // 1. Get project tempo from ProjectManager
        // 2. Calculate tempo adjustments for each selected region
        // 3. Apply tempo rate changes to match project BPM
    }
    
    private func harmonizeSelectedRegions() {
        // TODO Phase 3: Implement harmonic analysis and adjustment
        // 1. Analyze keys of all selected regions
        // 2. Determine optimal harmonic relationships
        // 3. Apply pitch shifts to create musical harmony
    }
    
    private func resetPitchTempoForSelected() {
        // TODO Phase 2: Implement reset functionality
        // 1. Set pitchShiftCents = 0.0 for all selected regions
        // 2. Set tempoRate = 1.0 for all selected regions
        // 3. Apply changes via TrackAudioNode pitch/tempo controls
    }
}
