//
//  MIDIRegionView.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  Displays MIDI regions on the timeline with mini note visualization.
//

import SwiftUI

// MARK: - MIDI Region View

/// Displays a MIDI region on the timeline with a mini piano roll preview.
struct MIDIRegionView: View {
    let region: MIDIRegion
    let trackColor: Color
    let pixelsPerBeat: CGFloat  // Beat-based timeline (proper DAW architecture)
    let trackHeight: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    var onBounceToAudio: (() -> Void)? = nil
    var onDuplicate: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onLoop: ((UUID, Double) -> Void)? = nil  // Loop resize callback (duration in beats)
    var onResize: ((UUID, Double) -> Void)? = nil  // Trim resize callback (duration in beats)
    var trackName: String  // Track name passed from parent (computed from track)
    var trackIcon: String = "pianokeys"  // Track icon for consistency
    var isDrumTrack: Bool = false  // TRUE if track has drumKitId set (use drum grid visualization)
    
    // [PHASE-7] Snap and tempo for parity with audio regions
    var snapToGrid: Bool = true
    var tempo: Double = 120.0
    
    // [PHASE-8] Viewport culling for performance with large MIDI files
    var scrollOffset: CGFloat = 0  // Horizontal scroll offset in pixels
    var viewportWidth: CGFloat = 1200  // Visible viewport width in pixels
    
    // [PHASE-7] Live resize state for real-time visual feedback
    @State private var liveResizeWidth: CGFloat? = nil
    @State private var isResizing: Bool = false
    @State private var resizeType: ResizeType? = nil
    @State private var dragStartWidth: CGFloat = 0
    @State private var dragStartCursorX: CGFloat = 0
    
    // Hover state
    @State private var isHoveringRegion: Bool = false  // Pre-selection hover feedback
    @State private var isHoveringLoopZone: Bool = false
    @State private var isHoveringTrimZone: Bool = false
    
    // Resize zone width (right-edge area for resize/loop) - matches audio region
    private let resizeZoneWidth: CGFloat = 15  // Same as IntegratedAudioRegion
    private let debugResizeZones: Bool = false  // Set to true to visualize zones
    
    // [PHASE-7] Snap calculations
    private var secondsPerBeat: TimeInterval { 60.0 / tempo }
    private var secondsPerBar: TimeInterval { secondsPerBeat * 4.0 }
    
    // Legacy compatibility - conversion for code still using seconds-based positioning
    private var pixelsPerSecond: CGFloat { pixelsPerBeat / CGFloat(secondsPerBeat) }
    
    // MARK: - Layout Constants (unified with audio regions)
    
    private let cornerRadius: CGFloat = RegionLayout.cornerRadius
    private let headerHeight: CGFloat = RegionLayout.headerHeight
    private let borderWidth: CGFloat = RegionLayout.borderWidth
    
    // MARK: - Computed Properties
    
    /// Region width in pixels - uses pixelsPerBeat since duration is in BEATS
    private var regionWidth: CGFloat {
        max(20, CGFloat(region.durationBeats) * pixelsPerBeat)
    }
    
    // [PHASE-7] Display width accounts for live resize during drag
    private var displayWidth: CGFloat {
        liveResizeWidth ?? regionWidth
    }
    
    // [PHASE-7] Display duration for visualization (in beats)
    private var displayDurationBeats: Double {
        displayWidth / pixelsPerBeat
    }
    
    /// Effective content length in beats - the duration of one loop unit (notes + any empty space from resize)
    private var effectiveContentLengthBeats: Double {
        region.contentLengthBeats > 0 ? region.contentLengthBeats : region.durationBeats
    }
    
    /// Preview loop count during resize - only counts if resizing in loop mode
    private var displayLoopCount: Int {
        guard effectiveContentLengthBeats > 0 else { return 1 }
        let duration = liveResizeWidth != nil ? (liveResizeWidth! / pixelsPerBeat) : region.durationBeats
        // Only show loop count if actually looping (resizeType == .loop) or region is already looped
        if resizeType == .loop || region.isLooped {
            return max(1, Int(ceil(duration / effectiveContentLengthBeats)))
        }
        return 1
    }
    
    /// Original notes duration in beats (before any resize with empty space)
    private var originalNotesDurationBeats: Double {
        guard !region.notes.isEmpty else { return min(region.contentLengthBeats, 4.0) }
        let maxNoteEnd = region.notes.map { $0.startBeat + $0.durationBeats }.max() ?? 4.0
        return min(maxNoteEnd, region.contentLengthBeats)
    }
    
    /// Calculate the note range for proper vertical scaling
    /// Caps range to ensure notes remain visible (not too thin)
    private var noteRange: (min: UInt8, max: UInt8) {
        guard !region.notes.isEmpty else { return (60, 72) } // Default C4-C5
        
        let pitches = region.notes.map(\.pitch)
        let minPitch = pitches.min() ?? 60
        let maxPitch = pitches.max() ?? 72
        
        let range = maxPitch - minPitch
        
        // Ensure at least 12 notes of range for visibility
        if range < 12 {
            let padding = (12 - range) / 2
            return (max(0, minPitch - padding), min(127, maxPitch + padding))
        }
        
        // Cap maximum range to 36 notes (3 octaves) to ensure notes are visible
        // For wider ranges, center on the middle of the actual note range
        if range > 36 {
            let midPitch = (Int(minPitch) + Int(maxPitch)) / 2
            let cappedMin = UInt8(max(0, midPitch - 18))
            let cappedMax = UInt8(min(127, midPitch + 18))
            return (cappedMin, cappedMax)
        }
        
        return (minPitch, maxPitch)
    }
    
    /// Generate a hash of all notes to detect any changes
    private var notesHash: Int {
        var hasher = Hasher()
        for note in region.notes {
            hasher.combine(note.id)
            hasher.combine(note.pitch)
            hasher.combine(note.startBeat)
            hasher.combine(note.durationBeats)
        }
        return hasher.finalize()
    }
    
    // MARK: - Body
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background with gradient (same whether selected or not - matches audio region style)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(
                    LinearGradient(
                        colors: [
                            trackColor.opacity(0.4),
                            trackColor.opacity(0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Border - strokeBorder keeps stroke inside bounds (not extending past region width)
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(trackColor, lineWidth: borderWidth)
            
            // Content
            VStack(spacing: 0) {
                // Header with region name
                regionHeader
                
                // Note visualization
                noteVisualization
                    .padding(.horizontal, 2)
                    .padding(.bottom, 2)
            }
            
            // Hover highlight (pre-selection feedback) - using shared component
            RegionHoverHighlight(
                isHovering: isHoveringRegion,
                isSelected: isSelected,
                cornerRadius: cornerRadius
            )
            
            // Selection border overlay - using shared component for consistency with audio regions
            RegionSelectionBorder(
                isSelected: isSelected,
                cornerRadius: cornerRadius,
                strokeWidth: RegionLayout.selectionStrokeWidth
            )
            
            // Resize indicator overlay - shows during resize/loop operations
            resizeIndicatorOverlay
            
            // Resize zones overlay - ALWAYS active (not just when selected)
            resizeZonesOverlay
        }
        .frame(width: displayWidth, height: RegionLayout.regionHeight(for: trackHeight))
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        // Unified shadow styling with audio regions
        .shadow(
            color: isSelected ? Color.blue.opacity(0.5) : Color.clear,
            radius: 8,
            x: 0,
            y: 2
        )
        .animation(nil, value: liveResizeWidth)  // [PHASE-7] No animation during drag for smooth tracking
        .animation(.easeInOut(duration: 0.2), value: isSelected)  // Unified with audio region
        .animation(.easeInOut(duration: 0.1), value: isHoveringRegion)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringRegion = hovering
        }
        .onTapGesture(count: 2) {
            // Double-click: Open Piano Roll for editing
            onDoubleClick()
        }
        .onTapGesture(count: 1) {
            // Single click: Select the region
            onSelect()
        }
        .contextMenu {
            midiRegionContextMenu
        }
        .help("\(trackName) - \(region.noteCount) notes")
    }
    
    // MARK: - Context Menu
    
    @ViewBuilder
    private var midiRegionContextMenu: some View {
        Button {
            onDoubleClick()
        } label: {
            Label("Edit in Piano Roll", systemImage: "pianokeys")
        }
        
        Divider()
        
        if let bounceAction = onBounceToAudio {
            Button {
                bounceAction()
            } label: {
                Label("Bounce to Audio", systemImage: "waveform")
            }
        }
        
        if let duplicateAction = onDuplicate {
            Button {
                duplicateAction()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
        }
        
        Divider()
        
        if let deleteAction = onDelete {
            Button(role: .destructive) {
                deleteAction()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Subviews
    
    private var regionHeader: some View {
        RegionHeaderView(
            isSelected: isSelected,
            baseColor: trackColor,
            height: headerHeight,
            cornerRadius: cornerRadius
        ) {
            HStack(spacing: 4) {
                // Track icon (consistent with track header)
                Image(systemName: trackIcon)
                    .font(.system(size: 9, weight: .medium))
                
                // Region name (from track)
                Text(trackName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                
                Spacer()
                
                // Note count
                Text("\(region.noteCount)")
                    .font(.system(size: 8, weight: .medium))
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(
                        Capsule()
                            .fill(trackColor.opacity(0.5))
                    )
            }
            .foregroundColor(.white)
            .padding(.horizontal, 4)
        }
    }
    
    // Detect if this is a step sequencer region based on track type
    private var isStepSequencerRegion: Bool {
        // Use track's drumKitId status instead of guessing from pitches
        // Bass notes (45, 47, 50) overlap with drum pitches, causing false positives
        return isDrumTrack && !region.notes.isEmpty
    }
    
    // Convert MIDI notes to step sequencer grid pattern (16×16 to match Step Sequencer)
    private var stepSequencerPattern: [[Bool]] {
        // Full 16-row mapping matching DrumSoundType enum
        let drumPitchToRow: [UInt8: Int] = [
            // Core Kit (Rows 1-8)
            36: 0,  // Kick
            38: 1,  // Snare
            42: 2,  // Closed Hat
            46: 3,  // Open Hat
            39: 4,  // Clap
            45: 5,  // Low Tom
            47: 6,  // Mid Tom
            50: 7,  // High Tom
            // Extended Kit (Rows 9-16)
            49: 8,  // Crash
            51: 9,  // Ride
            37: 10, // Rimshot
            56: 11, // Cowbell
            82: 12, // Shaker
            54: 13, // Tambourine
            64: 14, // Low Conga
            63: 15  // High Conga
        ]
        
        var grid: [[Bool]] = Array(repeating: Array(repeating: false, count: 16), count: 16)
        let stepDuration = region.durationBeats / 16.0
        
        var noteCount = 0
        var cellCount = 0
        var unmappedNotes: [UInt8] = []
        
        for note in region.notes {
            noteCount += 1
            if let row = drumPitchToRow[note.pitch] {
                let column = Int(note.startBeat / stepDuration)
                if column >= 0 && column < 16 {
                    if !grid[row][column] {
                        cellCount += 1
                    }
                    grid[row][column] = true
                }
            } else {
                unmappedNotes.append(note.pitch)
            }
        }
        
        return grid
    }
    
    private var noteVisualization: some View {
        Group {
            if isStepSequencerRegion {
                // Step sequencer grid visualization
                // Calculate display content length for live preview during resize
                let displayContentLen = resizeType == .trim && liveResizeWidth != nil 
                    ? (liveResizeWidth! / pixelsPerBeat) 
                    : effectiveContentLengthBeats
                let displayIsLooped = (resizeType == .loop && isResizing) || region.isLooped
                // 16 columns are built from region.durationBeats (stepDuration = region.durationBeats/16),
                // so pattern width must equal region width — use displayDurationBeats, not originalNotesDurationBeats
                let stepSeqPatternDuration = displayDurationBeats
                
                StepSequencerRegionVisualization(
                    pattern: stepSequencerPattern,
                    regionDuration: displayDurationBeats,
                    tempo: tempo,
                    width: displayWidth,
                    height: trackHeight - headerHeight,
                    isLooped: displayIsLooped,
                    contentLength: displayContentLen,
                    audioFileDuration: stepSeqPatternDuration
                )
            } else {
                // [PHASE-7] Piano roll style visualization with contentLength support
                Canvas { context, size in
                    let noteMin = noteRange.min
                    let noteMax = noteRange.max
                    let pitchRange = CGFloat(noteMax - noteMin + 1)
                    // Minimum 2px height to ensure visibility
                    let noteHeight = max(2, (size.height - 2) / pitchRange)
                    
                    // Content width = the full loop unit (notes + empty space)
                    let contentWidth = CGFloat(effectiveContentLengthBeats) * pixelsPerBeat
                    // Notes only occupy the original portion
                    let notesWidth = CGFloat(originalNotesDurationBeats) * pixelsPerBeat
                    
                    // Determine if we should show looped content
                    let showLooped = (resizeType == .loop && isResizing) || region.isLooped
                    
                    // Calculate how many content units to render
                    let totalContentUnits: Int
                    if showLooped && contentWidth > 0 {
                        totalContentUnits = Int(ceil(size.width / contentWidth))
                    } else {
                        totalContentUnits = 1
                    }
                    
                    // [PHASE-8] Viewport culling: Calculate visible time range based on scroll position
                    // The region is positioned at regionStartX in the timeline
                    let regionStartX = CGFloat(region.startBeat) * pixelsPerBeat
                    
                    // Add buffer zone to render notes slightly beyond viewport edges (prevents clipping at edges)
                    let bufferZone: CGFloat = 500  // 500px buffer on each side
                    
                    // Calculate which portion of THIS region is visible in the scrollview viewport
                    let viewportStartX = max(0, scrollOffset - bufferZone)  // Left edge with buffer
                    let viewportEndX = scrollOffset + viewportWidth + bufferZone  // Right edge with buffer
                    
                    // Calculate visible pixel range WITHIN this region
                    let visibleRegionStartX = max(0, viewportStartX - regionStartX)
                    let visibleRegionEndX = min(size.width, viewportEndX - regionStartX)
                    
                    // Convert to beats (notes are positioned in beats, not pixels)
                    let visibleStartBeat = Double(visibleRegionStartX / pixelsPerBeat)
                    let visibleEndBeat = Double(visibleRegionEndX / pixelsPerBeat)
                    
                    // Pre-filter notes to only those visible in the VIEWPORT (not just Canvas)
                    // This dramatically reduces iteration count from 5000+ to ~100-500 visible notes
                    let visibleNotes = region.notes.filter { note in
                        let noteEndTime = note.startBeat + note.durationBeats
                        // Note is visible if it overlaps with the viewport
                        return noteEndTime >= visibleStartBeat && note.startBeat <= visibleEndBeat
                    }
                    
                    
                    var notesDrawn = 0
                    var notesSkippedAfterEnd = 0
                    var notesSkippedOutsideVisible = 0
                    var notesSkippedClipped = 0
                    
                    for contentIndex in 0..<totalContentUnits {
                        let contentUnitX = CGFloat(contentIndex) * contentWidth
                        let isLoopedSection = contentIndex > 0
                        
                        // Draw loop divider at content unit boundary
                        if isLoopedSection && contentUnitX > 0 && contentUnitX < size.width {
                            // Vertical divider line
                            let dividerPath = Path { path in
                                path.move(to: CGPoint(x: contentUnitX, y: 0))
                                path.addLine(to: CGPoint(x: contentUnitX, y: size.height))
                            }
                            context.stroke(dividerPath, with: .color(Color.white.opacity(0.3)), lineWidth: 1)
                        }
                        
                        // Draw notes only within the notes portion of this content unit
                        // [PHASE-8] Now iterating through pre-filtered visibleNotes instead of all notes
                        for note in visibleNotes {
                            
                            // Calculate position within this content unit
                            // Note: startTime and duration are in BEATS, use pixelsPerBeat
                            let noteX = contentUnitX + CGFloat(note.startBeat) * pixelsPerBeat
                            let noteW = max(2, CGFloat(note.durationBeats) * pixelsPerBeat)
                            
                            // Clamp pitch to visible range (prevents overflow when range is capped)
                            let clampedPitch = max(noteMin, min(noteMax, note.pitch))
                            let yNormalized = CGFloat(Int(noteMax) - Int(clampedPitch)) / pitchRange
                            let y = yNormalized * (size.height - noteHeight)
                            
                            // Skip notes that start after the notes portion ends
                            let notesEndX = contentUnitX + notesWidth
                            if noteX >= notesEndX { 
                                notesSkippedAfterEnd += 1
                                continue 
                            }
                            
                            // Skip notes outside visible area
                            if noteX + noteW < 0 || noteX > size.width { 
                                notesSkippedOutsideVisible += 1
                                continue 
                            }
                            
                            // Clip to notes portion and display width
                            let clippedRight = min(noteX + noteW, notesEndX, size.width)
                            let clippedWidth = clippedRight - max(0, noteX)
                            if clippedWidth <= 0 { 
                                notesSkippedClipped += 1
                                continue 
                            }
                            
                            notesDrawn += 1
                            
                            // Draw note bar
                            let rect = CGRect(
                                x: max(0, noteX),
                                y: y,
                                width: clippedWidth,
                                height: max(1, noteHeight - 1)
                            )
                            
                            // Note color - slightly darker for looped sections
                            let velocityFactor = Double(note.velocity) / 127.0
                            let baseOpacity = 0.5 + velocityFactor * 0.5
                            let noteColor = Color.white.opacity(isLoopedSection ? baseOpacity * 0.7 : baseOpacity)
                            
                            context.fill(
                                Path(roundedRect: rect, cornerRadius: 1),
                                with: .color(noteColor)
                            )
                        }
                    }
                }
                .frame(height: trackHeight - headerHeight)
                .clipped()  // Clip to region bounds
            }
        }
        // Force redraw when ANY note property changes or contentLength changes
        .id("\(notesHash)-\(region.contentLengthBeats)")
    }
    
    // MARK: - Resize Indicator Overlay (popup during resize/loop like audio regions)
    
    private var resizeIndicatorOverlay: some View {
        GeometryReader { geometry in
            if isResizing, let type = resizeType, let liveWidth = liveResizeWidth {
                let liveDurationBeats = liveWidth / pixelsPerBeat
                let loopCount = displayLoopCount
                
                // Calculate length in bars, beats, sixteenths (MIDI uses beats directly)
                let bars = Int(liveDurationBeats / 4.0)
                let remainingBeats = liveDurationBeats.truncatingRemainder(dividingBy: 4.0)
                let beats = Int(remainingBeats)
                let fractionalBeat = remainingBeats.truncatingRemainder(dividingBy: 1.0)
                let sixteenths = Int(fractionalBeat * 4.0)
                
                // Different tooltip based on operation type
                Group {
                    if type == .loop {
                        // LOOP operation: Show SNAP tooltip with measure/beat display
                        VStack(spacing: 4) {
                            // SNAP indicator
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
        .allowsHitTesting(false)  // Don't interfere with region interactions
    }
    
    // MARK: - Resize Zones Overlay (matches audio region behavior EXACTLY)
    
    private var resizeZonesOverlay: some View {
        GeometryReader { geometry in
            // Looped regions can only be looped more, NOT resized
            if region.isLooped {
                // LOOPED REGION: Entire zone is loop-only (can't resize looped regions)
                Rectangle()
                    .fill(debugResizeZones ? Color.green.opacity(0.3) : Color.clear)
                    .frame(height: geometry.size.height)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        isHoveringLoopZone = hovering
                        isHoveringTrimZone = false
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
                    .frame(width: resizeZoneWidth)
                    .offset(x: displayWidth - resizeZoneWidth)
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
                // CRITICAL: Position at RIGHT EDGE - use displayWidth for proper tracking
                .frame(width: resizeZoneWidth)
                .offset(x: displayWidth - resizeZoneWidth)
            }
        }
    }
    
    // MARK: - Resize Functions
    
    enum ResizeType {
        case loop    // Top half - extends with looping
        case trim    // Bottom half - adjusts duration
    }
    
    private func updateCursor() {
        // Keep the current cursor during resize operations
        if isResizing {
            if resizeType == .loop {
                NSCursor.loop.set()  // Use the shared loop cursor from NSCursor extension
            } else {
                NSCursor.resizeLeftRight.set()
            }
            return
        }
        
        if isHoveringLoopZone {
            NSCursor.loop.set()  // Use the shared loop cursor for loop zone
        } else if isHoveringTrimZone {
            NSCursor.resizeLeftRight.set()  // Standard resize cursor for trim zone
        } else {
            NSCursor.arrow.set()
        }
    }
    
    // [PHASE-7] Global coordinate drag handler for smooth 1:1 tracking
    private func handleResizeDragGlobal(value: DragGesture.Value, type: ResizeType) {
        if !isResizing {
            isResizing = true
            dragStartWidth = regionWidth
            dragStartCursorX = value.startLocation.x
            resizeType = type
        }
        
        // Calculate new width using global cursor movement
        let currentCursorX = value.location.x
        let cursorDelta = currentCursorX - dragStartCursorX
        var newWidth = max(20, dragStartWidth + cursorDelta)
        
        // [PHASE-7] Apply snap based on modifier keys
        let flags = NSEvent.modifierFlags
        let isCommandPressed = flags.contains(.command)
        let isShiftPressed = flags.contains(.shift)
        
        // MIDI duration is in BEATS - use pixelsPerBeat for conversion
        let newDurationBeats = newWidth / pixelsPerBeat
        var snappedDurationBeats = newDurationBeats
        
        if isCommandPressed {
            // Command: Free mode - no snapping
            snappedDurationBeats = newDurationBeats
        } else if isShiftPressed {
            // Shift: Snap to beats (1 beat resolution)
            snappedDurationBeats = round(newDurationBeats)
        } else if snapToGrid {
            // Default: Snap to bars (4 beats in 4/4 time)
            snappedDurationBeats = round(newDurationBeats / 4.0) * 4.0
        }
        
        newWidth = max(20, snappedDurationBeats * pixelsPerBeat)
        liveResizeWidth = newWidth
    }
    
    // [PHASE-7] Global coordinate drag end handler
    private func handleResizeEndGlobal(value: DragGesture.Value, type: ResizeType) {
        guard let finalWidth = liveResizeWidth else {
            isResizing = false
            return
        }
        
        // MIDI duration is in BEATS - use pixelsPerBeat for conversion
        let finalDurationBeats = max(0.25, finalWidth / pixelsPerBeat)  // Minimum 1/4 beat
        
        // Call the parent's resize callbacks (duration in beats)
        switch type {
        case .loop:
            onLoop?(region.id, finalDurationBeats)
            
        case .trim:
            onResize?(region.id, finalDurationBeats)
        }
        
        // Reset resize state
        isResizing = false
        dragStartWidth = 0
        dragStartCursorX = 0
        resizeType = nil
        liveResizeWidth = nil
        NSCursor.arrow.set()
    }
}

// RoundedCorners and UIRectCorner are now in RegionDragBehavior.swift (shared component)
