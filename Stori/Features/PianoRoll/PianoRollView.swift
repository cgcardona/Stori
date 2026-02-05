//
//  PianoRollView.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  Professional piano roll editor for MIDI note editing.
//  Features note drawing, velocity editing, quantization, and scale snapping.
//

import SwiftUI

// MARK: - PianoRollView

/// Main piano roll editor view for editing MIDI regions.
struct PianoRollView: View {
    @Binding var region: MIDIRegion
    @State private var selectedNotes: Set<UUID> = []
    @State private var horizontalZoom: CGFloat = 0.5  // Default to 50% to avoid Canvas render bug in nested ScrollViews
    @State private var verticalZoom: CGFloat = 1.0
    @State private var scrollOffset: CGPoint = .zero
    @State private var editMode: PianoRollEditMode = .select
    @State private var snapResolution: SnapResolution = .sixteenth
    @State private var currentScale: Scale = .major
    @State private var scaleRoot: UInt8 = 60 // C4
    @State private var showScaleHighlight = false
    @State private var showAutomationLanes = false  // Toggle for MIDI CC lanes
    @State private var automationLanes: [AutomationLane] = []  // Active CC/PitchBend lanes
    @State private var showTransformSheet = false   // MIDI Transform dialog
    @State private var showQuantizeOptions = false  // Quantize options sheet
    @State private var showVelocityPopover = false  // Velocity editor popover
    @State private var quantizeStrength: Double = 100  // 0-100%
    @State private var quantizeSwing: Double = 50     // 0-100%
    
    // Clipboard for copy/paste
    @State private var clipboard: [MIDINote] = []
    
    // For note drawing
    @State private var isDrawing = false
    @State private var drawingNote: MIDINote?
    @State private var drawStartPosition: CGPoint = .zero
    
    // For marquee selection
    @State private var isMarqueeSelecting = false
    @State private var marqueeStart: CGPoint = .zero
    @State private var marqueeEnd: CGPoint = .zero
    @State private var previousMarqueeSelection: Set<UUID> = []  // Track previous selection for audio feedback
    
    // For brush tool - track notes painted in current drag for undo
    @State private var brushPaintedNotes: Set<UUID> = []
    @State private var brushOldNotes: [MIDINote] = []  // Snapshot for undo
    
    // For note duplication with Option
    @State private var isDuplicatingDrag = false
    @State private var draggedNotesOriginalIds: Set<UUID> = []
    @State private var hasDuplicatedForCurrentDrag = false
    @State private var duplicateStartPositions: [UUID: (beat: Double, pitch: UInt8)] = [:]
    @State private var originalPositionsBeforeDrag: [UUID: (beat: Double, pitch: UInt8)] = [:]
    
    // For undo support during note drag (capture state at drag START, register at drag END)
    @State private var notesBeforeDrag: [MIDINote] = []
    
    // For undo support during note resize (capture state at resize START, register at resize END)
    @State private var notesBeforeResize: [MIDINote] = []
    
    // For pitch preview during drag (debouncing to avoid audio spam)
    @State private var lastPreviewedPitches: Set<UInt8> = []  // Track chord for multi-note drag
    @State private var lastPreviewTime: Date = .distantPast
    
    // For keyboard pitch indicator during drag (shows target pitch on keyboard)
    @State private var draggingPitch: UInt8? = nil
    
    // For scroll synchronization and note culling
    @State private var verticalScrollOffset: CGFloat = 0
    @State private var horizontalScrollOffset: CGFloat = 0
    @State private var visibleGridHeight: CGFloat = 500  // Updated by GeometryReader
    @State private var visibleGridWidth: CGFloat = 800   // Updated by GeometryReader
    
    // PERF: Playhead observes AudioEngine directly via PianoRollPlayhead
    // This prevents parent view re-renders when position changes
    
    // [PHASE-3] Tempo for measure display
    var tempo: Double = 120.0  // BPM, passed from parent
    
    // [PHASE-4] Cycle region (synced with main timeline)
    var cycleEnabled: Bool = false
    var cycleStartBeats: Double = 0
    var cycleEndBeats: Double = 4
    var snapToGrid: Bool = true  // Snap toggle state from parent
    var onCycleRegionChanged: ((Double, Double) -> Void)?  // Callback (startBeat, endBeat)
    
    // Undo manager for cmd+z / cmd+shift+z (unified undo system)
    private var undoManager: UndoManager? {
        UndoService.shared.undoManager
    }
    
    // For note preview
    var onPreviewNote: ((UInt8) -> Void)?
    var onStopPreview: (() -> Void)?  // Called when drag ends to stop any playing note
    
    // Grid settings
    let noteHeight: CGFloat = 16
    let pixelsPerBeat: CGFloat = 80
    let keyboardWidth: CGFloat = 80
    let automationLaneHeight: CGFloat = 80  // Height per automation lane
    
    // Piano range: C0 (MIDI 12) to B8 (MIDI 119) - full C8 octave included
    let minPitch: Int = 12   // C0
    let maxPitch: Int = 119  // B8 (complete C8 octave, no C9)
    var pitchRange: Int { maxPitch - minPitch + 1 }  // 108 notes
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            pianoRollToolbar
            
            Divider()
            
            // Main content area - unified horizontal scrolling for ruler and grid
            // Vertical scroll synced between keyboard and grid via offset tracking
            GeometryReader { containerGeometry in
                // Calculate available height for grid/keyboard, ensuring minimum of 100
                // Subtract automation lanes height if visible
                let automationHeight = showAutomationLanes ? CGFloat(automationLanes.count) * automationLaneHeight : 0
                let rawAvailableHeight = containerGeometry.size.height - 24 - 1 - automationHeight - (showAutomationLanes && !automationLanes.isEmpty ? 1 : 0)
                let availableHeight = max(100, rawAvailableHeight)
                
                HStack(spacing: 0) {
                    // Left column: corner + keyboard + velocity label (fixed width)
                    VStack(spacing: 0) {
                        // Corner (matches ruler height)
                        Rectangle()
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .frame(width: keyboardWidth, height: 24)
                            .onAppear {
                                // Track visible height for pitch row culling
                                visibleGridHeight = availableHeight
                            }
                            .onChange(of: availableHeight) { _, newHeight in
                                visibleGridHeight = newHeight
                            }
                        
                        Divider()
                        
                        // Keyboard (synced with grid's vertical scroll via offset)
                        // FIX: Canvas is now VIEWPORT-sized, draws in scrolled coordinates
                        // This prevents the huge offscreen texture that caused initial paint failures
                        // Wrap in ScrollView to capture scroll wheel events
                        PianoKeyboardScrollWrapper(
                            keyboard: AnyView(pianoKeyboard),
                            keyboardWidth: keyboardWidth,
                            availableHeight: availableHeight,
                            verticalScrollOffset: $verticalScrollOffset,
                            gridHeight: gridHeight,
                            onPreviewNote: onPreviewNote,
                            keyboardPitchAt: keyboardPitchAt(visibleY:),
                            minPitch: minPitch,
                            maxPitch: maxPitch
                        )
                        .frame(width: keyboardWidth, height: availableHeight)
                        
                        // MIDI CC Automation lane labels (when visible)
                        if showAutomationLanes {
                            ForEach(automationLanes) { lane in
                                Divider()
                                
                                HStack(spacing: 4) {
                                    Image(systemName: lane.parameter.icon)
                                        .foregroundColor(lane.color)
                                        .font(.system(size: 10))
                                    Text(lane.parameter.shortName)
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(width: keyboardWidth, height: automationLaneHeight)
                                .background(Color(nsColor: .controlBackgroundColor))
                            }
                        }
                    }
                    .frame(width: keyboardWidth)
                    
                    Divider()
                    
                    // Right column: ruler + grid + velocity (all scroll horizontally together)
                    GeometryReader { outerGeo in
                        ScrollView(.horizontal, showsIndicators: true) {
                            ZStack(alignment: .topLeading) {
                                // Horizontal scroll offset probe
                                GeometryReader { innerGeo in
                                    let offset = -innerGeo.frame(in: .named("hScroll")).minX
                                    Color.clear
                                        .onChange(of: offset) { _, newOffset in
                                            horizontalScrollOffset = max(0, newOffset)
                                        }
                                        .onAppear {
                                            horizontalScrollOffset = max(0, offset)
                                            visibleGridWidth = outerGeo.size.width
                                        }
                                }
                                .frame(width: 0, height: 0)
                                
                                VStack(spacing: 0) {
                                    // Ruler row (fixed height at top)
                                    ZStack(alignment: .topLeading) {
                                        timeRuler
                                            .frame(width: gridWidth, height: 24)
                                        
                                        cycleOverlay
                                            .frame(width: gridWidth, height: 24)
                                        
                                        // Playhead in ruler (isolated for performance)
                                        PianoRollPlayhead(
                                            pixelsPerBeat: scaledPixelsPerBeat,
                                            height: 24
                                        )
                                    }
                                    .frame(width: gridWidth, height: 24)
                                    
                                    Divider()
                                    
                                    // Grid area (scrolls vertically, tracks offset for keyboard sync)
                                    // FIX: noteGrid is now a BACKGROUND overlay, viewport-sized, draws in scrolled coordinates
                                    // This prevents the huge offscreen texture that caused initial paint failures
                                    ZStack {
                                        // Background: viewport-sized grid lanes (draws in scrolled coordinates)
                                        noteGrid
                                            .frame(width: gridWidth, height: availableHeight)
                                        
                                        // Foreground: scrollable content
                                        ScrollViewReader { scrollProxy in
                                            ScrollView(.vertical, showsIndicators: true) {
                                                ZStack(alignment: .topLeading) {
                                                    // Scroll offset probe - update state directly
                                                    GeometryReader { geo in
                                                        let offset = -geo.frame(in: .named("gridScroll")).minY
                                                        Color.clear
                                                            .onChange(of: offset) { _, newOffset in
                                                                verticalScrollOffset = newOffset
                                                            }
                                                            .onAppear {
                                                                verticalScrollOffset = offset
                                                            }
                                                    }
                                                    .frame(height: 0)
                                                    
                                                    // Transparent spacer to maintain scroll content height
                                                    Color.clear
                                                        .frame(width: gridWidth, height: gridHeight)
                                                    
                                                    notesOverlay
                                                    
                                                    if isMarqueeSelecting {
                                                        marqueeSelectionView
                                                    }
                                                    
                                                    // Playhead in grid (isolated for performance)
                                                    PianoRollPlayhead(
                                                        pixelsPerBeat: scaledPixelsPerBeat,
                                                        height: gridHeight
                                                    )
                                                    
                                                    if isDrawing, let note = drawingNote {
                                                        noteView(for: note, isSelected: true, isPreview: true)
                                                    }
                                                    
                                                    // Scroll anchor positioned at C4 via padding/offset in scrollable content
                                                    Color.clear
                                                        .frame(width: 1, height: 1)
                                                        .id("scrollAnchor")
                                                        .padding(.top, initialScrollTargetY)
                                                }
                                                .frame(width: gridWidth, height: gridHeight)
                                                .contentShape(Rectangle())
                                                .gesture(gridGesture)
                                            }
                                            .coordinateSpace(name: "gridScroll")
                                            .onAppear {
                                                // Use DispatchQueue for centering - more reliable than Task
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                                    scrollProxy.scrollTo("scrollAnchor", anchor: .center)
                                                }
                                            }
                                        }
                                    }
                                    .frame(height: availableHeight)
                                    
                                    // MIDI CC Automation Lanes (collapsible)
                                    if showAutomationLanes {
                                        ForEach($automationLanes) { $lane in
                                            Divider()
                                            
                                            MIDICCAutomationLane(
                                                lane: $lane,
                                                region: $region,
                                                durationBeats: region.durationBeats,
                                                pixelsPerBeat: scaledPixelsPerBeat,
                                                height: automationLaneHeight
                                            )
                                            .frame(width: gridWidth, height: automationLaneHeight)
                                        }
                                    }
                                }
                            }
                        }
                        .coordinateSpace(name: "hScroll")
                        .onChange(of: outerGeo.size.width) { _, newWidth in
                            visibleGridWidth = newWidth
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // Auto-create lanes for any existing CC data in the region
            initializeLanesFromExistingData()
        }
        .onChange(of: region.id) { _, _ in
            // Re-initialize lanes when region changes (e.g., switching tracks)
            automationLanes.removeAll()
            showAutomationLanes = false
            initializeLanesFromExistingData()
        }
        .task {
            // Wait for SwiftUI layout to complete before initializing automation lanes
            await Task.yield()
            if automationLanes.isEmpty {
                initializeLanesFromExistingData()
            }
        }
        .sheet(isPresented: $showTransformSheet) {
            MIDITransformView(
                region: $region,
                selectedNotes: $selectedNotes,
                isPresented: $showTransformSheet
            )
        }
    }
    
    /// Initialize automation lanes from existing CC/PitchBend data in the MIDI region
    private func initializeLanesFromExistingData() {
        // Check for existing pitch bend events
        if !region.pitchBendEvents.isEmpty && !automationLanes.contains(where: { $0.parameter == .pitchBend }) {
            automationLanes.append(AutomationLane(parameter: .pitchBend, color: AutomationParameter.pitchBend.color))
            showAutomationLanes = true
        }
        
        // Check for existing CC events by controller number
        let existingCCs = Set(region.controllerEvents.map { $0.controller })
        
        for ccNumber in existingCCs {
            if let param = ccNumberToParameter(ccNumber),
               !automationLanes.contains(where: { $0.parameter == param }) {
                automationLanes.append(AutomationLane(parameter: param, color: param.color))
                showAutomationLanes = true
            }
        }
    }
    
    /// Map CC number to AutomationParameter
    private func ccNumberToParameter(_ cc: UInt8) -> AutomationParameter? {
        switch cc {
        case 1: return .midiCC1
        case 7: return .midiCC7
        case 10: return .midiCC10
        case 11: return .midiCC11
        case 64: return .midiCC64
        case 74: return .midiCC74
        default: return nil
        }
    }
    
    // MARK: - Computed Properties
    
    private var gridWidth: CGFloat {
        // Ensure grid extends well beyond visible notes for comfortable editing
        // Minimum 128 beats (32 bars) for usability, extend based on content
        let maxNoteEnd = region.notes.map { $0.endBeat }.max() ?? 0
        let effectiveDuration = max(region.durationBeats, maxNoteEnd, 128.0) // Minimum 128 beats (32 bars)
        return CGFloat(effectiveDuration) * pixelsPerBeat * horizontalZoom + 800
    }
    
    private var gridHeight: CGFloat {
        CGFloat(pitchRange) * noteHeight * verticalZoom
    }
    
    /// Calculate Y position to scroll to on initial appear (centers on C4/middle C)
    private var initialScrollTargetY: CGFloat {
        // Always center on middle C (MIDI 60 = C4)
        let middleCRowIndex = maxPitch - 60
        return CGFloat(middleCRowIndex) * scaledNoteHeight
    }
    
    
    
    private var scaledNoteHeight: CGFloat {
        noteHeight * verticalZoom
    }
    
    /// Range of pitches currently visible on screen (with buffer for smooth scrolling)
    private var visiblePitchRange: ClosedRange<Int> {
        // Calculate which rows are visible based on scroll offset and visible height
        let buffer = 5  // Extra rows above/below for smooth scrolling
        let firstVisibleRow = max(0, Int(verticalScrollOffset / scaledNoteHeight) - buffer)
        let lastVisibleRow = min(pitchRange - 1, Int((verticalScrollOffset + visibleGridHeight) / scaledNoteHeight) + buffer)
        
        // Convert row indices to pitches (rows go top-to-bottom, pitches go high-to-low)
        let highestVisiblePitch = min(maxPitch, maxPitch - firstVisibleRow)
        let lowestVisiblePitch = max(minPitch, maxPitch - lastVisibleRow)
        
        // Ensure valid range (lowerBound <= upperBound)
        let validLow = min(lowestVisiblePitch, highestVisiblePitch)
        let validHigh = max(lowestVisiblePitch, highestVisiblePitch)
        
        return validLow...validHigh
    }
    
    /// Range of beats currently visible on screen (with buffer for smooth scrolling)
    private var visibleBeatRange: ClosedRange<Double> {
        let buffer = 4.0  // Extra beats left/right for smooth scrolling
        let firstBeat = max(0, horizontalScrollOffset / scaledPixelsPerBeat - buffer)
        let lastBeat = max(firstBeat, (horizontalScrollOffset + visibleGridWidth) / scaledPixelsPerBeat + buffer)
        
        // Ensure valid range (lowerBound <= upperBound)
        return firstBeat...lastBeat
    }
    
    /// PERF: Notes filtered to only those visible in the current viewport
    /// This dramatically reduces the number of NoteView instances created
    private var visibleNotes: [MIDINote] {
        let pitchRange = visiblePitchRange
        let beatRange = visibleBeatRange
        
        return region.notes.filter { note in
            // Check pitch visibility (vertical culling)
            let pitchVisible = pitchRange.contains(Int(note.pitch))
            
            // Check beat visibility (horizontal culling)
            // Note is visible if it overlaps with the visible beat range
            let noteStart = note.startBeat
            let noteEnd = note.endBeat
            let beatVisible = noteEnd >= beatRange.lowerBound && noteStart <= beatRange.upperBound
            
            return pitchVisible && beatVisible
        }
    }
    
    private var scaledPixelsPerBeat: CGFloat {
        pixelsPerBeat * horizontalZoom
    }
    
    // PERF: Playhead position is now read directly by PianoRollPlayhead from AudioEngine
    // This prevents view re-renders when playhead moves
    
    // MARK: - Toolbar
    
    /// Logic Pro-inspired toolbar with dropdown menus and icon tools
    private var pianoRollToolbar: some View {
        HStack(spacing: 0) {
            // LEFT: Menu Bar (Edit, Functions, View)
            PianoRollMenuBar(
                selectedNotes: $selectedNotes,
                region: $region,
                showScaleHighlight: $showScaleHighlight,
                currentScale: $currentScale,
                showAutomationLanes: $showAutomationLanes,
                automationLanes: $automationLanes,
                horizontalZoom: $horizontalZoom,
                showTransformSheet: $showTransformSheet,
                showQuantizeOptions: $showQuantizeOptions,
                snapResolution: snapResolution,
                onSelectAll: selectAll,
                onDeselectAll: deselectAll,
                onDeleteSelected: deleteSelected,
                onQuantize: quantizeSelected,
                onLegato: legatoSelected,
                onCut: cutSelected,
                onCopy: copySelected,
                onPaste: pasteNotes
            )
            .padding(.leading, 8)
            
            toolbarDivider
            
            // CENTER-LEFT: Tool Selector (icons only)
            PianoRollToolSelector(selection: $editMode)
                .padding(.horizontal, 8)
            
            toolbarDivider
            
            // CENTER: Snap Control (prominent like Logic)
            snapControl
                .padding(.horizontal, 12)
            
            Spacer()
            
            // RIGHT: Zoom Control
            zoomControl
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .toolShortcuts(editMode: $editMode)
        .sheet(isPresented: $showQuantizeOptions) {
            QuantizeOptionsSheet(
                resolution: $snapResolution,
                strength: $quantizeStrength,
                swing: $quantizeSwing,
                selectedNoteCount: selectedNotes.count,
                onQuantize: quantizeWithOptions
            )
        }
    }
    
    /// Snap control styled like Logic Pro
    private var snapControl: some View {
        HStack(spacing: 4) {
            Text("Snap:")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Menu {
                ForEach(SnapResolution.allCases, id: \.self) { res in
                    Button(action: { snapResolution = res }) {
                        HStack {
                            Text(res.rawValue)
                            if res == snapResolution {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(snapResolution.rawValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }
            .menuStyle(.borderlessButton)
        }
    }
    
    /// Zoom control with horizontal and vertical sliders
    private var zoomControl: some View {
        HStack(spacing: 8) {
            // Horizontal zoom
            HStack(spacing: 4) {
                Image(systemName: "arrow.left.and.right")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                Button(action: { horizontalZoom = max(0.25, horizontalZoom - 0.25) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Slider(value: $horizontalZoom, in: 0.25...4.0, step: 0.25)
                    .frame(width: 70)
                
                Button(action: { horizontalZoom = min(4.0, horizontalZoom + 0.25) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            
            // Vertical zoom
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.and.down")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                
                Button(action: { verticalZoom = max(0.5, verticalZoom - 0.25) }) {
                    Image(systemName: "minus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Slider(value: $verticalZoom, in: 0.5...3.0, step: 0.25)
                    .frame(width: 70)
                
                Button(action: { verticalZoom = min(3.0, verticalZoom + 0.25) }) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
        }
    }
    
    /// Consistent divider for toolbar sections
    private var toolbarDivider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 4)
    }
    
    // MARK: - Clipboard Operations
    
    private func cutSelected() {
        copySelected()
        deleteSelected()
    }
    
    private func copySelected() {
        clipboard = region.notes.filter { selectedNotes.contains($0.id) }
    }
    
    private func pasteNotes() {
        guard !clipboard.isEmpty else { return }
        
        // Find the earliest note in clipboard to calculate offset
        let earliestBeat = clipboard.map { $0.startBeat }.min() ?? 0
        
        // Paste at current playhead position or after last note
        let pastePosition = region.notes.map { $0.endBeat }.max() ?? 0
        let offset = pastePosition - earliestBeat + 0.25  // Small gap
        
        // Create new notes with offset
        var newNotes: [MIDINote] = []
        for note in clipboard {
            let newNote = MIDINote(
                pitch: note.pitch,
                velocity: note.velocity,
                startBeat: note.startBeat + offset,
                durationBeats: note.durationBeats
            )
            newNotes.append(newNote)
        }
        
        // Add to region and select
        region.notes.append(contentsOf: newNotes)
        selectedNotes = Set(newNotes.map { $0.id })
    }
    
    private func deselectAll() {
        selectedNotes.removeAll()
    }
    
    private func legatoSelected() {
        // Extend each selected note to the next note of the same pitch
        let selectedNotesList = region.notes.filter { selectedNotes.contains($0.id) }
        
        for selectedNote in selectedNotesList {
            // Find the next note with the same pitch
            let nextNote = region.notes
                .filter { $0.pitch == selectedNote.pitch && $0.startBeat > selectedNote.startBeat }
                .min(by: { $0.startBeat < $1.startBeat })
            
            if let next = nextNote {
                // Extend to the start of the next note
                if let index = region.notes.firstIndex(where: { $0.id == selectedNote.id }) {
                    region.notes[index].durationBeats = next.startBeat - selectedNote.startBeat
                }
            }
        }
    }
    
    private func quantizeWithOptions() {
        // Quantize with strength (not full snap)
        for noteId in selectedNotes {
            if let index = region.notes.firstIndex(where: { $0.id == noteId }) {
                let currentBeat = region.notes[index].startBeat
                let quantizedBeat = snapResolution.quantize(beat: currentBeat, strength: Float(quantizeStrength / 100.0))
                region.notes[index].startBeat = quantizedBeat
            }
        }
    }
    
    // MARK: - Piano Keyboard
    
    /// Canvas for drawing the piano keyboard (visuals only, no gestures)
    /// FIX: Canvas is VIEWPORT-sized, draws in scrolled coordinates
    /// This prevents the huge offscreen texture that caused initial paint failures
    private var pianoKeyboardCanvas: some View {
        // Capture highlighted pitches for canvas (includes dragging pitch for real-time feedback)
        let selectedPitches = highlightedPitches
        let rowH = scaledNoteHeight
        let scrollOffset = verticalScrollOffset
        
        return Canvas { context, size in
            // Calculate visible rows based on viewport and scroll offset
            let buffer = 2  // Small buffer for smooth edges
            let firstRow = max(0, Int(floor(scrollOffset / rowH)) - buffer)
            let lastRow = min(pitchRange - 1, Int(ceil((scrollOffset + size.height) / rowH)) + buffer)
            
            guard firstRow <= lastRow else { return }
            for rowIndex in firstRow...lastRow {
                let pitch = maxPitch - rowIndex
                // VIEWPORT-SPACE y: subtract scroll offset to get position in viewport
                let y = CGFloat(rowIndex) * rowH - scrollOffset
                let isBlack = MIDIHelper.isBlackKey(UInt8(pitch))
                let isC = pitch % 12 == 0
                let isSelected = selectedPitches.contains(UInt8(pitch))
                let octave = (pitch / 12) - 1  // MIDI octave numbering
                
                let keyRect = CGRect(x: 0, y: y, width: size.width, height: rowH)
                
                // Draw key background (blue if selected)
                if isSelected {
                    // Highlighted key for selected note
                    context.fill(Path(keyRect), with: .color(Color.blue.opacity(0.7)))
                } else if isC {
                    // C notes get a subtle blue tint for octave orientation
                    context.fill(Path(keyRect), with: .color(Color(red: 0.85, green: 0.9, blue: 1.0)))
                    context.stroke(
                        Path(keyRect),
                        with: .color(Color.blue.opacity(0.3)),
                        lineWidth: 0.5
                    )
                } else if isBlack {
                    context.fill(Path(keyRect), with: .color(Color(white: 0.15)))
                } else {
                    context.fill(Path(keyRect), with: .color(Color(white: 0.95)))
                    context.stroke(
                        Path(keyRect),
                        with: .color(Color.gray.opacity(0.2)),
                        lineWidth: 0.5
                    )
                }
                
                // Highlight C notes (left marker) - thicker for emphasis
                if isC && !isSelected {
                    let markerRect = CGRect(x: 0, y: y, width: 4, height: rowH)
                    context.fill(Path(markerRect), with: .color(.blue))
                }
                
                // Draw note labels
                let noteName = MIDIHelper.noteName(for: UInt8(pitch))
                let textColor: Color = isSelected ? .white : (isBlack ? .white : .black)
                
                // Always show C notes with octave, show others when zoomed in
                if isC {
                    // Prominent octave label for C notes
                    let octaveLabel = Text("C\(octave)")
                        .font(.system(size: min(12, max(9, rowH * 0.75)), weight: .bold, design: .rounded))
                        .foregroundColor(isSelected ? .white : .blue)
                    
                    context.draw(
                        octaveLabel,
                        at: CGPoint(x: size.width - 22, y: y + rowH / 2),
                        anchor: .center
                    )
                } else if rowH >= 14 {
                    // Show other note names when zoomed in enough
                    let text = Text(noteName)
                        .font(.system(size: min(9, rowH * 0.6)))
                        .foregroundColor(textColor.opacity(0.7))
                    
                    context.draw(
                        text,
                        at: CGPoint(x: size.width - 22, y: y + rowH / 2),
                        anchor: .center
                    )
                }
            }
        }
        .allowsHitTesting(false)  // Canvas is visual only, gestures handled by container
        // FIX: Removed .drawingGroup() - with viewport-sized canvas, we don't need offscreen rasterization
    }
    
    /// Piano keyboard with gestures - properly clipped to visible area
    /// CRITICAL: Gestures are on the container, not the Canvas, so hit-testing respects clipping
    private var pianoKeyboard: some View {
        // This is just the canvas - gestures will be added by the container in body
        pianoKeyboardCanvas
    }
    
    /// Calculate pitch from a Y position in the VISIBLE keyboard area (accounting for scroll)
    private func keyboardPitchAt(visibleY: CGFloat) -> Int {
        // Convert visible Y to canvas Y by adding the scroll offset
        let canvasY = visibleY + verticalScrollOffset
        let rowIndex = Int(canvasY / scaledNoteHeight)
        return maxPitch - rowIndex
    }
    
    // MARK: - Note Grid
    
    /// Grid background with horizontal pitch rows only (vertical lines drawn separately for alignment)
    /// FIX: Canvas is VIEWPORT-sized, draws in scrolled coordinates
    /// This prevents the huge offscreen texture that caused initial paint failures
    private var noteGrid: some View {
        let rowH = scaledNoteHeight
        let scrollOffset = verticalScrollOffset
        let hScrollOffset = horizontalScrollOffset
        let scaleHighlight = showScaleHighlight
        let scale = currentScale
        let root = scaleRoot
        let zoom = horizontalZoom
        let pxPerBeat = scaledPixelsPerBeat
        
        return Canvas { context, size in
            // HORIZONTAL ROWS (pitch lanes)
            // Calculate visible rows based on viewport and scroll offset
            let buffer = 2  // Small buffer for smooth edges
            let firstRow = max(0, Int(floor(scrollOffset / rowH)) - buffer)
            let lastRow = min(pitchRange - 1, Int(ceil((scrollOffset + size.height) / rowH)) + buffer)
            
            guard firstRow <= lastRow else { return }
            for rowIndex in firstRow...lastRow {
                let pitch = maxPitch - rowIndex
                // VIEWPORT-SPACE y: subtract scroll offset to get position in viewport
                let y = CGFloat(rowIndex) * rowH - scrollOffset
                
                let isBlack = MIDIHelper.isBlackKey(UInt8(pitch))
                let isC = pitch % 12 == 0
                let octave = (pitch / 12) - 1
                let isEvenOctave = octave % 2 == 0
                let isInScale = scaleHighlight && scale.contains(pitch: UInt8(pitch), root: root)
                
                // Row background with octave zebra striping
                var rowColor: Color
                if isInScale {
                    rowColor = isBlack ? Color.blue.opacity(0.15) : Color.blue.opacity(0.08)
                } else if isC {
                    // C rows get a subtle blue tint for octave boundary
                    rowColor = Color(red: 0.12, green: 0.15, blue: 0.22)
                } else {
                    // Zebra stripe by octave for orientation
                    let baseWhite: Double = isBlack ? 0.12 : 0.18
                    let zebraAdjust: Double = isEvenOctave ? 0.0 : 0.02
                    rowColor = Color(white: baseWhite + zebraAdjust)
                }
                
                let rowRect = CGRect(x: 0, y: y, width: size.width, height: rowH)
                context.fill(Path(rowRect), with: .color(rowColor))
                
                // Row separator - stronger line at C for octave boundaries
                let lineWidth: CGFloat = isC ? 1.0 : 0.5
                let linePath = Path { path in
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                let strokeColor = isC ? Color.blue.opacity(0.4) : Color.gray.opacity(0.1)
                context.stroke(linePath, with: .color(strokeColor), lineWidth: lineWidth)
            }
            
            // VERTICAL GRID LINES (beat markers)
            // Determine opacity for each tier based on zoom
            let eighthOpacity: Double = zoom >= 0.75 ? 0.15 : 0.0
            let sixteenthOpacity: Double = zoom >= 1.5 ? 0.08 : 0.0
            
            let beatsPerBar: CGFloat = 4.0
            let pxPerBar = pxPerBeat * beatsPerBar
            
            // Pre-calculate colors
            let barColor = Color.white.opacity(0.35)
            let beatColor = Color.white.opacity(0.2)
            let eighthColor = Color.white.opacity(eighthOpacity)
            let sixteenthColor = Color.white.opacity(sixteenthOpacity)
            
            // Calculate visible bars based on horizontal scroll
            let firstBar = max(0, Int(floor(hScrollOffset / pxPerBar)))
            let lastBar = Int(ceil((hScrollOffset + size.width) / pxPerBar)) + 1
            
            for barIndex in firstBar..<lastBar {
                let barX = round(CGFloat(barIndex) * pxPerBar - hScrollOffset)
                
                // Bar line (strongest)
                if barX >= 0 && barX < size.width {
                    let barPath = Path { path in
                        path.move(to: CGPoint(x: barX, y: 0))
                        path.addLine(to: CGPoint(x: barX, y: size.height))
                    }
                    context.stroke(barPath, with: .color(barColor), lineWidth: 1.5)
                }
                
                // Beat lines within this bar (1, 2, 3)
                for beat in 1..<4 {
                    let beatX = round(barX + CGFloat(beat) * pxPerBeat)
                    if beatX >= 0 && beatX < size.width {
                        let beatPath = Path { path in
                            path.move(to: CGPoint(x: beatX, y: 0))
                            path.addLine(to: CGPoint(x: beatX, y: size.height))
                        }
                        context.stroke(beatPath, with: .color(beatColor), lineWidth: 1)
                    }
                }
                
                // 8th note lines (only if zoomed enough)
                if eighthOpacity > 0 {
                    for eighthOffset in [0.5, 1.5, 2.5, 3.5] {
                        let eighthX = round(barX + CGFloat(eighthOffset) * pxPerBeat)
                        if eighthX >= 0 && eighthX < size.width {
                            let eighthPath = Path { path in
                                path.move(to: CGPoint(x: eighthX, y: 0))
                                path.addLine(to: CGPoint(x: eighthX, y: size.height))
                            }
                            context.stroke(eighthPath, with: .color(eighthColor), lineWidth: 0.75)
                        }
                    }
                }
                
                // 16th note lines (only if zoomed enough)
                if sixteenthOpacity > 0 {
                    for sixteenthOffset in [0.25, 0.75, 1.25, 1.75, 2.25, 2.75, 3.25, 3.75] {
                        let sixteenthX = round(barX + CGFloat(sixteenthOffset) * pxPerBeat)
                        if sixteenthX >= 0 && sixteenthX < size.width {
                            let sixteenthPath = Path { path in
                                path.move(to: CGPoint(x: sixteenthX, y: 0))
                                path.addLine(to: CGPoint(x: sixteenthX, y: size.height))
                            }
                            context.stroke(sixteenthPath, with: .color(sixteenthColor), lineWidth: 0.5)
                        }
                    }
                }
            }
        }
        // FIX: Removed .drawingGroup() - with viewport-sized canvas, we don't need offscreen rasterization
    }
    
    // MARK: - Measure Ruler
    
    /// [PHASE-3] Measure-based ruler showing bar numbers (1, 2, 3...)
    private var timeRuler: some View {
        Canvas { context, size in
            // PERF: Optimized ruler with pixel alignment and reduced Path allocations
            let beatsPerBar: CGFloat = 4.0  // 4/4 time
            let pixelsPerBar = scaledPixelsPerBeat * beatsPerBar
            let pixelsPerBeat = scaledPixelsPerBeat
            
            // Pre-calculate zoom thresholds
            let showEighths = horizontalZoom >= 0.75
            let showSixteenths = horizontalZoom >= 1.5
            
            var bar = 1
            var x: CGFloat = 0
            
            while x < size.width {
                // Pixel-align for crisp rendering
                let alignedX = round(x)
                
                // Draw bar line (major tick)
                var barTickPath = Path()
                barTickPath.move(to: CGPoint(x: alignedX, y: size.height))
                barTickPath.addLine(to: CGPoint(x: alignedX, y: size.height - 14))
                context.stroke(barTickPath, with: .color(.gray), lineWidth: 1.25)
                
                // Draw bar number
                let barText = Text("\(bar)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                context.draw(barText, at: CGPoint(x: alignedX + 4, y: 8), anchor: .leading)
                
                // Draw beat subdivisions within the bar
                for beat in 1..<4 {
                    let beatX = round(x + CGFloat(beat) * pixelsPerBeat)
                    if beatX < size.width {
                        // Quarter note beat tick
                        var beatTickPath = Path()
                        beatTickPath.move(to: CGPoint(x: beatX, y: size.height))
                        beatTickPath.addLine(to: CGPoint(x: beatX, y: size.height - 10))
                        context.stroke(beatTickPath, with: .color(.gray.opacity(0.7)), lineWidth: 0.85)
                    }
                    
                    // 8th note subdivisions
                    if showEighths {
                        let eighthX = round(x + (CGFloat(beat) - 0.5) * pixelsPerBeat)
                        if eighthX > alignedX && eighthX < size.width {
                            var eighthTickPath = Path()
                            eighthTickPath.move(to: CGPoint(x: eighthX, y: size.height))
                            eighthTickPath.addLine(to: CGPoint(x: eighthX, y: size.height - 6))
                            context.stroke(eighthTickPath, with: .color(.gray.opacity(0.5)), lineWidth: 0.65)
                        }
                    }
                    
                    // 16th note subdivisions
                    if showSixteenths {
                        for sixteenth in [0.25, 0.75] {
                            let sixteenthX = round(x + (CGFloat(beat) - sixteenth) * pixelsPerBeat)
                            if sixteenthX > alignedX && sixteenthX < size.width {
                                var sixteenthTickPath = Path()
                                sixteenthTickPath.move(to: CGPoint(x: sixteenthX, y: size.height))
                                sixteenthTickPath.addLine(to: CGPoint(x: sixteenthX, y: size.height - 4))
                                context.stroke(sixteenthTickPath, with: .color(.gray.opacity(0.35)), lineWidth: 0.5)
                            }
                        }
                    }
                }
                
                // First beat subdivisions
                if showEighths {
                    let eighthX = round(x + 0.5 * pixelsPerBeat)
                    if eighthX < size.width {
                        var eighthTickPath = Path()
                        eighthTickPath.move(to: CGPoint(x: eighthX, y: size.height))
                        eighthTickPath.addLine(to: CGPoint(x: eighthX, y: size.height - 6))
                        context.stroke(eighthTickPath, with: .color(.gray.opacity(0.5)), lineWidth: 0.65)
                    }
                }
                
                if showSixteenths {
                    for sixteenth in [0.25, 0.75] {
                        let sixteenthX = round(x + sixteenth * pixelsPerBeat)
                        if sixteenthX < size.width {
                            var sixteenthTickPath = Path()
                            sixteenthTickPath.move(to: CGPoint(x: sixteenthX, y: size.height))
                            sixteenthTickPath.addLine(to: CGPoint(x: sixteenthX, y: size.height - 4))
                            context.stroke(sixteenthTickPath, with: .color(.gray.opacity(0.35)), lineWidth: 0.5)
                        }
                    }
                }
                
                bar += 1
                x += pixelsPerBar
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Cycle Overlay
    
    /// [PHASE-4] Yellow cycle region bar for piano roll ruler - interactive
    /// Styled to match timeline cycle overlay (uniform color, no handles)
    private var cycleOverlay: some View {
        GeometryReader { geometry in
            if cycleEnabled {
                let startX = cycleStartBeats * scaledPixelsPerBeat
                let endX = cycleEndBeats * scaledPixelsPerBeat
                let width = max(8, endX - startX)  // Min width for handles
                let handleWidth: CGFloat = 8
                
                ZStack(alignment: .leading) {
                    // Main cycle bar - uniform color, no separate handles
                    Rectangle()
                        .fill(Color.yellow.opacity(0.5))
                        .frame(width: width, height: 20)
                    
                    // Measure badge with proper formatting (1.1 - 2.1 format)
                    let startMeasure = formatMeasure(cycleStartBeats)
                    let endMeasure = formatMeasure(cycleEndBeats)
                    let durationBeats = cycleEndBeats - cycleStartBeats
                    let bars = Int(durationBeats / 4)
                    let barsText = bars == 1 ? "1 bar" : "\(bars) bars"
                    
                    Text("\(startMeasure) – \(endMeasure)  (\(barsText))")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.black.opacity(0.85))
                        .frame(width: width, alignment: .center)
                }
                .position(x: startX + width / 2, y: 12)
                .contentShape(Rectangle())
                .gesture(cycleDragGesture)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        // Determine which cursor to show based on position
                        let leftHandleEnd = handleWidth
                        let rightHandleStart = width - handleWidth
                        
                        if location.x < leftHandleEnd || location.x > rightHandleStart {
                            NSCursor.resizeLeftRight.set()
                        } else {
                            NSCursor.openHand.set()
                        }
                    case .ended:
                        NSCursor.arrow.set()
                    }
                }
            }
        }
    }
    
    /// Format beats to measure.beat format (e.g., 1.1, 2.3)
    private func formatMeasure(_ beats: Double) -> String {
        let beatsPerBar: Double = 4  // Assuming 4/4 time
        let measure = Int(beats / beatsPerBar) + 1
        let beat = Int(beats.truncatingRemainder(dividingBy: beatsPerBar)) + 1
        return "\(measure).\(beat)"
    }
    
    // [PHASE-4] Drag gesture state for cycle region
    @State private var cycleDragMode: CycleDragMode = .none
    @State private var cycleDragStartBeats: Double = 0
    @State private var cycleDragEndBeats: Double = 0
    
    private enum CycleDragMode { case none, left, right, body }
    
    private var cycleDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let handleWidth: CGFloat = 8
                let startX = cycleStartBeats * scaledPixelsPerBeat
                let endX = cycleEndBeats * scaledPixelsPerBeat
                
                // Determine drag mode on first touch
                if cycleDragMode == .none {
                    let localX = value.startLocation.x
                    let leftHandleEnd = startX + handleWidth
                    let rightHandleStart = endX - handleWidth
                    
                    if localX < leftHandleEnd {
                        cycleDragMode = .left
                        NSCursor.resizeLeftRight.set()
                    } else if localX > rightHandleStart {
                        cycleDragMode = .right
                        NSCursor.resizeLeftRight.set()
                    } else {
                        cycleDragMode = .body
                        NSCursor.closedHand.set()
                    }
                    cycleDragStartBeats = cycleStartBeats
                    cycleDragEndBeats = cycleEndBeats
                }
                
                let deltaBeats = value.translation.width / scaledPixelsPerBeat
                let minLen: Double = 1  // Minimum 1 beat
                let beatsPerBar: Double = 4  // 4/4
                
                // [PHASE-4] Detect modifier keys for snap behavior
                let flags = NSEvent.modifierFlags
                let isCommandPressed = flags.contains(.command)
                let isShiftPressed = flags.contains(.shift)
                
                // Snap function based on modifiers:
                // Command = free (no snap)
                // Shift = snap to beats
                // Default = snap to bars (when snapToGrid is on)
                func applySnap(_ value: Double) -> Double {
                    if isCommandPressed {
                        // Command: Free mode - no snapping
                        return value
                    } else if isShiftPressed {
                        // Shift: Snap to individual beats
                        return round(value)
                    } else if snapToGrid {
                        // Default: Snap to bars
                        return round(value / beatsPerBar) * beatsPerBar
                    }
                    return value
                }
                
                switch cycleDragMode {
                case .left:
                    var newStart = max(0, cycleDragStartBeats + deltaBeats)
                    newStart = applySnap(newStart)
                    if (cycleEndBeats - newStart) >= minLen {
                        onCycleRegionChanged?(newStart, cycleEndBeats)
                    }
                case .right:
                    var newEnd = max(minLen, cycleDragEndBeats + deltaBeats)
                    newEnd = applySnap(newEnd)
                    if (newEnd - cycleStartBeats) >= minLen {
                        onCycleRegionChanged?(cycleStartBeats, newEnd)
                    }
                case .body:
                    let duration = cycleDragEndBeats - cycleDragStartBeats
                    var newStart = max(0, cycleDragStartBeats + deltaBeats)
                    newStart = applySnap(newStart)
                    let newEnd = newStart + duration
                    onCycleRegionChanged?(newStart, newEnd)
                case .none:
                    break
                }
            }
            .onEnded { _ in
                cycleDragMode = .none
                NSCursor.arrow.set()
            }
    }
    
    // MARK: - Marquee Selection
    
    private var marqueeSelectionView: some View {
        let rect = CGRect(
            x: min(marqueeStart.x, marqueeEnd.x),
            y: min(marqueeStart.y, marqueeEnd.y),
            width: abs(marqueeEnd.x - marqueeStart.x),
            height: abs(marqueeEnd.y - marqueeStart.y)
        )
        
        return Rectangle()
            .stroke(Color.blue, lineWidth: 1)
            .background(Color.blue.opacity(0.1))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
    
    // MARK: - Selected Note Pitches (for piano key highlighting)
    
    private var selectedNotePitches: Set<UInt8> {
        Set(region.notes.filter { selectedNotes.contains($0.id) }.map { $0.pitch })
    }
    
    /// Pitches to highlight on keyboard: includes selected notes AND dragging target pitch
    private var highlightedPitches: Set<UInt8> {
        var pitches = selectedNotePitches
        if let dragPitch = draggingPitch {
            pitches.insert(dragPitch)
        }
        return pitches
    }
    
    // MARK: - Notes Overlay
    
    /// PERF: Only render notes that are visible in the current viewport
    /// This dramatically reduces the number of NoteView instances (e.g., from 839 to ~50)
    private var notesOverlay: some View {
        // Fallback to all notes if scroll tracking isn't initialized yet
        let notesToRender = (horizontalScrollOffset == 0 && visibleGridWidth <= 800) ? region.notes : visibleNotes
        
        return ForEach(notesToRender) { note in
            noteView(for: note, isSelected: selectedNotes.contains(note.id), isPreview: false)
        }
    }
    
    private func noteView(for note: MIDINote, isSelected: Bool, isPreview: Bool) -> some View {
        let x = note.startBeat * scaledPixelsPerBeat
        // Calculate y position relative to the limited pitch range (C0-C8)
        let y = CGFloat(maxPitch - Int(note.pitch)) * scaledNoteHeight
        let width = max(4, note.durationBeats * scaledPixelsPerBeat)
        
        // Determine if this is an original note being duplicated (show half-transparent)
        let isOriginalDuringDuplication = isDuplicatingDrag && draggedNotesOriginalIds.contains(note.id)
        let opacity: Double = isPreview ? 0.7 : (isOriginalDuringDuplication ? 0.3 : 1.0)
        
        return NoteView(
            note: note,
            isSelected: isSelected,
            editMode: editMode,
            width: width,
            height: scaledNoteHeight,
            pixelsPerBeat: scaledPixelsPerBeat,
            onSelect: { selectNote(note) },
            onDeselect: { deselectNote(note) },
            onPlaySound: { onPreviewNote?(note.pitch) },
            onMove: { offset in moveNote(note, by: offset) },
            onResize: { delta in resizeNote(note, by: delta) },
            onDelete: { deleteNote(note) },
            onResizeEnd: {
                // Register undo ONCE at resize end (not during resize motion)
                if !notesBeforeResize.isEmpty {
                    let beforeNotes = notesBeforeResize
                    let afterNotes = region.notes
                    
                    undoManager?.registerUndo(withTarget: undoManager!) { _ in
                        self.region.notes = beforeNotes
                    }
                    undoManager?.setActionName("Resize Note")
                    
                    // Clear snapshot
                    notesBeforeResize = []
                }
            },
            onDragEnd: { 
                // Register undo ONCE at drag end (not during drag motion)
                // This prevents undo stack pollution (hundreds of undo entries per drag)
                if !notesBeforeDrag.isEmpty {
                    let beforeNotes = notesBeforeDrag
                    let afterNotes = region.notes
                    
                    undoManager?.registerUndo(withTarget: undoManager!) { _ in
                        self.region.notes = beforeNotes
                    }
                    undoManager?.setActionName("Move Notes")
                    
                    // Clear snapshot
                    notesBeforeDrag = []
                }
                
                // Clean up drag state
                isDuplicatingDrag = false
                draggedNotesOriginalIds = []
                hasDuplicatedForCurrentDrag = false
                duplicateStartPositions.removeAll()
                originalPositionsBeforeDrag.removeAll()
                // Reset pitch preview and keyboard indicator state
                lastPreviewedPitches.removeAll()
                draggingPitch = nil
                // Stop any playing preview note to prevent stuck notes
                onStopPreview?()
            },
            onSlice: { relativeBeats in sliceNote(note, at: relativeBeats) },
            onGlue: { glueNote(note) },
            onLegato: { legatoNote(note) }
        )
        .position(x: x + width / 2, y: y + scaledNoteHeight / 2)
        .opacity(opacity)
    }
    
    // MARK: - Grid Gesture
    
    private var gridGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                handleGridDrag(value)
            }
            .onEnded { value in
                handleGridDragEnd(value)
            }
    }
    
    private func handleGridDrag(_ value: DragGesture.Value) {
        switch editMode {
        case .draw:
            if !isDrawing {
                // Start drawing a new note
                isDrawing = true
                drawStartPosition = value.startLocation
                
                let pitch = pitchAt(y: value.startLocation.y)
                let rawBeat = beatAt(x: value.startLocation.x)
                var startBeat = rawBeat
                
                if snapResolution != .off {
                    startBeat = snapResolution.quantize(beat:rawBeat)
                }
                
                drawingNote = MIDINote(
                    pitch: pitch,
                    velocity: 100,  // ~78% velocity - standard DAW default
                    startBeat: startBeat,
                    durationBeats: snapResolution.stepDurationBeats > 0 ? snapResolution.stepDurationBeats : 0.25
                )
                
                onPreviewNote?(pitch)
            } else if var note = drawingNote {
                // Update note duration while dragging
                var endBeat = beatAt(x: value.location.x)
                if snapResolution != .off {
                    endBeat = snapResolution.quantize(beat:endBeat)
                }
                note.durationBeats = max(snapResolution.stepDurationBeats > 0 ? snapResolution.stepDurationBeats : 0.1, endBeat - note.startBeat)
                drawingNote = note
            }
            
        case .erase:
            // Find and delete notes under cursor
            let pitch = pitchAt(y: value.location.y)
            let beat = beatAt(x: value.location.x)
            
            if let noteToDelete = region.notes.first(where: { note in
                note.pitch == pitch && note.startBeat <= beat && note.endBeat > beat
            }) {
                deleteNote(noteToDelete)
            }
            
        case .select:
            // Marquee selection - drag to select multiple notes
            if !isMarqueeSelecting {
                isMarqueeSelecting = true
                marqueeStart = value.startLocation
                previousMarqueeSelection = []  // Reset tracking at start of new marquee
            }
            marqueeEnd = value.location
            
            // Update selection based on marquee rectangle
            let rect = CGRect(
                x: min(marqueeStart.x, marqueeEnd.x),
                y: min(marqueeStart.y, marqueeEnd.y),
                width: abs(marqueeEnd.x - marqueeStart.x),
                height: abs(marqueeEnd.y - marqueeStart.y)
            )
            
            // Find notes within the marquee rectangle
            var newSelection = Set<UUID>()
            var notesInMarquee: [MIDINote] = []  // Track actual notes for audio feedback
            
            for note in region.notes {
                let noteX = note.startBeat * scaledPixelsPerBeat
                let noteY = CGFloat(maxPitch - Int(note.pitch)) * scaledNoteHeight
                let noteWidth = note.durationBeats * scaledPixelsPerBeat
                let noteRect = CGRect(x: noteX, y: noteY, width: noteWidth, height: scaledNoteHeight)
                
                if rect.intersects(noteRect) {
                    newSelection.insert(note.id)
                    notesInMarquee.append(note)
                }
            }
            
            // LOGIC PRO BEHAVIOR: Play audio for newly selected notes
            // Detect notes that just became selected (weren't in previous selection)
            let newlySelectedIds = newSelection.subtracting(previousMarqueeSelection)
            
            if !newlySelectedIds.isEmpty {
                // Find the notes that were newly selected and play their pitches
                let newlySelectedNotes = notesInMarquee.filter { newlySelectedIds.contains($0.id) }
                
                // Group by pitch to avoid playing the same pitch multiple times
                let uniquePitches = Set(newlySelectedNotes.map { $0.pitch })
                
                // Play each unique pitch (sorted for consistent audio experience)
                // Limit to 8 simultaneous previews to avoid audio overload on fast drags
                let sortedPitches = uniquePitches.sorted()
                let pitchesToPlay = sortedPitches.prefix(8)
                
                for pitch in pitchesToPlay {
                    onPreviewNote?(pitch)
                }
            }
            
            // Update state
            selectedNotes = newSelection
            previousMarqueeSelection = newSelection
            
        case .brush:
            // Brush tool: paint notes at grid positions as you drag
            
            // Capture old notes state at start of brush stroke
            if brushPaintedNotes.isEmpty {
                brushOldNotes = region.notes
            }
            
            let pitch = pitchAt(y: value.location.y)
            var startBeat = beatAt(x: value.location.x)
            
            // Snap to grid
            if snapResolution != .off {
                startBeat = snapResolution.quantize(beat:startBeat)
            }
            
            // Check if a note already exists at this grid position
            let duration = snapResolution.stepDurationBeats > 0 ? snapResolution.stepDurationBeats : 0.25
            let noteExists = region.notes.contains { note in
                note.pitch == pitch && 
                abs(note.startBeat - startBeat) < 0.01  // Same grid position
            }
            
            // Only add if no note exists at this position
            if !noteExists && startBeat >= 0 && startBeat < region.durationBeats {
                let newNote = MIDINote(
                    pitch: pitch,
                    velocity: 100,
                    startBeat: startBeat,
                    durationBeats: duration
                )
                region.notes.append(newNote)
                brushPaintedNotes.insert(newNote.id)
                
                // Play preview sound for new note
                onPreviewNote?(pitch)
            }
            
        case .slice, .glue, .legato, .velocity:
            // These modes operate on existing notes via tap/click, not grid drag
            break
        }
    }
    
    private func handleGridDragEnd(_ value: DragGesture.Value) {
        if editMode == .draw, let note = drawingNote {
            // Capture state for undo
            let oldNotes = region.notes
            
            // Add the drawn note to the region
            region.addNote(note)
            selectedNotes = [note.id]
            
            // Register undo
            if let undoManager = undoManager {
                undoManager.registerUndo(withTarget: undoManager) { _ in
                    self.region.notes = oldNotes
                }
                undoManager.setActionName("Add Note")
            }
        }
        
        // Handle brush tool undo
        if editMode == .brush && !brushPaintedNotes.isEmpty {
            let paintedNoteIds = brushPaintedNotes
            let oldNotes = brushOldNotes
            
            // Select all painted notes
            selectedNotes = paintedNoteIds
            
            // Register undo
            if let undoManager = undoManager {
                undoManager.registerUndo(withTarget: undoManager) { _ in
                    self.region.notes = oldNotes
                    self.selectedNotes = []
                }
                undoManager.setActionName("Brush Paint Notes")
            }
            
            // Reset brush state
            brushPaintedNotes.removeAll()
            brushOldNotes.removeAll()
        }
        
        // End marquee selection
        isMarqueeSelecting = false
        previousMarqueeSelection = []  // Reset for next marquee operation
        
        isDrawing = false
        drawingNote = nil
    }
    
    // MARK: - Helper Methods
    
    private func pitchAt(y: CGFloat) -> UInt8 {
        // Calculate pitch from y position within limited range (C0-C8)
        let rowIndex = Int(y / scaledNoteHeight)
        let pitch = maxPitch - rowIndex
        return UInt8(clamping: max(minPitch, min(maxPitch, pitch)))
    }
    
    /// X position to beat (timeline is beat-based).
    private func beatAt(x: CGFloat) -> Double {
        x / scaledPixelsPerBeat
    }
    
    // MARK: - Note Actions
    
    private func selectNote(_ note: MIDINote) {
        selectedNotes.insert(note.id)
    }
    
    private func deselectNote(_ note: MIDINote) {
        selectedNotes.remove(note.id)
    }
    
    private func selectAll() {
        selectedNotes = Set(region.notes.map(\.id))
    }
    
    private func deleteSelected() {
        region.removeNotes(withIds: selectedNotes)
        selectedNotes.removeAll()
    }
    
    private func deleteNote(_ note: MIDINote) {
        // Capture state for undo
        let oldNotes = region.notes
        let oldSelection = selectedNotes
        
        // Perform delete
        if selectedNotes.count > 1 {
            region.removeNotes(withIds: selectedNotes)
            selectedNotes.removeAll()
        } else {
            region.removeNotes(withIds: [note.id])
            selectedNotes.remove(note.id)
        }
        
        // Register undo
        if let undoManager = undoManager {
            undoManager.registerUndo(withTarget: undoManager) { _ in
                self.region.notes = oldNotes
                self.selectedNotes = oldSelection
            }
            undoManager.setActionName("Delete Notes")
        }
    }
    
    // MARK: - Scissor Tool (Slice)
    
    /// Split a note at the specified position (relative to note start, in beats)
    private func sliceNote(_ note: MIDINote, at relativePositionBeats: Double) {
        // Calculate the two new note durations
        let firstDuration = relativePositionBeats
        let secondDuration = note.durationBeats - relativePositionBeats
        
        // Ensure both parts have meaningful duration
        guard firstDuration >= 0.05 && secondDuration >= 0.05 else { return }
        
        // Capture state for undo
        let oldNotes = region.notes
        
        // Create the first note (from start to split point)
        let firstNote = MIDINote(
            id: UUID(),
            pitch: note.pitch,
            velocity: note.velocity,
            startBeat: note.startBeat,
            durationBeats: firstDuration,
            channel: note.channel
        )
        
        // Create the second note (from split point to end)
        let secondNote = MIDINote(
            id: UUID(),
            pitch: note.pitch,
            velocity: note.velocity,
            startBeat: note.startBeat + relativePositionBeats,
            durationBeats: secondDuration,
            channel: note.channel
        )
        
        // Remove original and add the two new notes
        region.removeNotes(withIds: [note.id])
        region.notes.append(firstNote)
        region.notes.append(secondNote)
        
        // Select the new notes
        selectedNotes = [firstNote.id, secondNote.id]
        
        // Register undo
        if let undoManager = undoManager {
            undoManager.registerUndo(withTarget: undoManager) { _ in
                self.region.notes = oldNotes
                self.selectedNotes = []
            }
            undoManager.setActionName("Split Note")
        }
    }
    
    // MARK: - Glue Tool (Merge)
    
    /// Merge a note with the next adjacent note of the same pitch
    private func glueNote(_ note: MIDINote) {
        // Find the next adjacent note with same pitch
        let noteEndTime = note.startBeat + note.durationBeats
        
        // Find notes that start at or very close to where this note ends (within 0.01 beats tolerance)
        let tolerance = 0.01
        guard let nextNote = region.notes.first(where: {
            $0.id != note.id &&
            $0.pitch == note.pitch &&
            abs($0.startBeat - noteEndTime) < tolerance
        }) else {
            // No adjacent note found
            return
        }
        
        // Capture state for undo
        let oldNotes = region.notes
        
        // Create merged note
        let mergedNote = MIDINote(
            id: UUID(),
            pitch: note.pitch,
            velocity: note.velocity,  // Keep velocity of first note
            startBeat: note.startBeat,
            durationBeats: note.durationBeats + nextNote.durationBeats,
            channel: note.channel
        )
        
        // Remove both original notes and add merged one
        region.removeNotes(withIds: [note.id, nextNote.id])
        region.notes.append(mergedNote)
        
        // Select the merged note
        selectedNotes = [mergedNote.id]
        
        // Register undo
        if let undoManager = undoManager {
            undoManager.registerUndo(withTarget: undoManager) { _ in
                self.region.notes = oldNotes
                self.selectedNotes = []
            }
            undoManager.setActionName("Glue Notes")
        }
    }
    
    // MARK: - Legato Tool
    
    /// Extend a note to reach the start of the next note (same pitch or any pitch)
    private func legatoNote(_ note: MIDINote) {
        let noteEndTime = note.startBeat + note.durationBeats
        
        // Find the next note that starts after this one (any pitch, sorted by start beat)
        let notesAfter = region.notes
            .filter { $0.id != note.id && $0.startBeat > note.startBeat }
            .sorted { $0.startBeat < $1.startBeat }
        
        guard let nextNote = notesAfter.first else {
            // No next note - extend to end of region
            let newDuration = region.durationBeats - note.startBeat
            if newDuration > note.durationBeats {
                updateNoteDuration(note, to: newDuration)
            }
            return
        }
        
        // Calculate new duration to reach the next note
        let newDuration = nextNote.startBeat - note.startBeat
        
        // Only extend if new duration is longer
        if newDuration > note.durationBeats {
            updateNoteDuration(note, to: newDuration)
        }
    }
    
    /// Helper to update note duration with undo support
    private func updateNoteDuration(_ note: MIDINote, to newDurationBeats: Double) {
        // Capture state for undo
        let oldNotes = region.notes
        
        // Find and update the note
        if let index = region.notes.firstIndex(where: { $0.id == note.id }) {
            region.notes[index].durationBeats = newDurationBeats
        }
        
        // Register undo
        if let undoManager = undoManager {
            undoManager.registerUndo(withTarget: undoManager) { _ in
                self.region.notes = oldNotes
            }
            undoManager.setActionName("Legato")
        }
    }
    
    private func duplicateSelectedNotes(including note: MIDINote) {
        // Get notes to duplicate (either selected notes or just the dragged note)
        let notesToDuplicate = selectedNotes.isEmpty ? [note.id] : selectedNotes
        
        // Store original IDs for visual feedback (half-transparent originals)
        draggedNotesOriginalIds = notesToDuplicate
        
        // Create duplicates
        var newNotes: [MIDINote] = []
        var newSelection: Set<UUID> = []
        duplicateStartPositions.removeAll()
        
        for noteId in notesToDuplicate {
            guard let originalNote = region.notes.first(where: { $0.id == noteId }) else { continue }
            
            // Use captured position if available (more accurate), otherwise use current position
            let (startBeat, pitch) = originalPositionsBeforeDrag[noteId] ?? (originalNote.startBeat, originalNote.pitch)
            
            // Create a new note with a new ID but same properties
            let duplicatedNote = MIDINote(
                id: UUID(), // New unique ID
                pitch: pitch,
                velocity: originalNote.velocity,
                startBeat: startBeat,
                durationBeats: originalNote.durationBeats,
                channel: originalNote.channel
            )
            
            // Store the starting position for offset calculations (use captured position)
            duplicateStartPositions[duplicatedNote.id] = (startBeat, pitch)
            
            newNotes.append(duplicatedNote)
            newSelection.insert(duplicatedNote.id)
        }
        
        // Add duplicates to region
        region.notes.append(contentsOf: newNotes)
        
        // Select only the duplicates (originals become half-transparent)
        selectedNotes = newSelection
        
        isDuplicatingDrag = true
    }
    
    private func moveNote(_ note: MIDINote, by offset: CGSize) {
        // Capture original state on VERY FIRST call (before any movement) for undo
        if originalPositionsBeforeDrag.isEmpty {
            // Snapshot entire notes array for undo (capture at drag START)
            notesBeforeDrag = region.notes
            
            // Capture individual positions for drag calculations
            let notesToCapture = selectedNotes.isEmpty ? [note.id] : selectedNotes
            for noteId in notesToCapture {
                if let originalNote = region.notes.first(where: { $0.id == noteId }) {
                    originalPositionsBeforeDrag[noteId] = (originalNote.startBeat, originalNote.pitch)
                }
            }
        }
        
        // Check if Option is held at the start of drag
        // We detect "start" by checking if offset is very small (first few pixels)
        let isNearStart = abs(offset.width) < 5 && abs(offset.height) < 5
        
        if isNearStart && !hasDuplicatedForCurrentDrag {
            let modifiers = NSEvent.modifierFlags
            let shouldDuplicate = modifiers.contains(.option)
            
            if shouldDuplicate {
                // This is the start of a drag with Option - duplicate first
                duplicateSelectedNotes(including: note)
                hasDuplicatedForCurrentDrag = true
                
                // CRITICAL: Restore original notes to their TRUE original positions
                // They may have moved before we detected Option key
                for (originalId, originalPos) in originalPositionsBeforeDrag {
                    if let index = region.notes.firstIndex(where: { $0.id == originalId }) {
                        region.notes[index].startBeat = originalPos.beat
                        region.notes[index].pitch = originalPos.pitch
                    }
                }
                // Don't return - let the move happen normally with the duplicates
            } else {
                // Mark that we checked but didn't duplicate (so we don't check again)
                hasDuplicatedForCurrentDrag = true
            }
        }
        
        // Capture state for undo
        let oldNotes = region.notes
        
        let rawTimeOffset = offset.width / scaledPixelsPerBeat
        let pitchOffset = Int(-offset.height / scaledNoteHeight)
        
        // If multiple notes are selected, move all of them together with the same offset
        let notesToMove = selectedNotes.isEmpty ? [note.id] : Array(selectedNotes)
        
        // Track ALL new pitches for audio preview (play the entire chord)
        var newPitchesForPreview: Set<UInt8> = []
        
        for noteId in notesToMove {
            // Skip original notes during duplication - they should never move
            if isDuplicatingDrag && draggedNotesOriginalIds.contains(noteId) {
                continue
            }
            
            guard let index = region.notes.firstIndex(where: { $0.id == noteId }) else { continue }
            
            var movedNote = region.notes[index]
            
            // If this is a duplicate drag, calculate position from the stored start position
            // Otherwise, calculate incrementally from current position
            if isDuplicatingDrag, let startPos = duplicateStartPositions[noteId] {
                // Calculate absolute position from start
                var newStartBeat = startPos.beat + rawTimeOffset
                if snapResolution != .off {
                    newStartBeat = snapResolution.quantize(beat:newStartBeat)
                }
                movedNote.startBeat = max(0, newStartBeat)
                movedNote.pitch = UInt8(clamping: Int(startPos.pitch) + pitchOffset)
            } else {
                // Normal drag: calculate offset from EACH note's own position
                // FIX: Use movedNote.startBeat (not note.startBeat) to preserve relative timing
                var newStartBeat = movedNote.startBeat + rawTimeOffset
                if snapResolution != .off {
                    newStartBeat = snapResolution.quantize(beat: newStartBeat)
                }
                movedNote.startBeat = max(0, newStartBeat)
                movedNote.pitch = UInt8(clamping: Int(movedNote.pitch) + pitchOffset)
            }
            
            region.notes[index] = movedNote
            
            // Collect all unique pitches for chord preview
            newPitchesForPreview.insert(movedNote.pitch)
        }
        
        // Play audio preview and update keyboard indicator when pitch changes
        if !newPitchesForPreview.isEmpty {
            // Update dragging pitch for keyboard highlight (use highest pitch)
            draggingPitch = newPitchesForPreview.max()
            
            // Play audio preview when pitch actually changes (debounced to avoid spam)
            if pitchOffset != 0 {
                previewPitchesIfChanged(newPitchesForPreview)
            }
        }
        
        // NOTE: Undo is registered at drag END, not during drag motion (see onDragEnd callback)
        // This prevents undo stack pollution (hundreds of undo entries per drag)
    }
    
    /// Preview multiple pitches (chord) with debouncing to avoid audio spam during fast drags
    private func previewPitchesIfChanged(_ pitches: Set<UInt8>) {
        let now = Date()
        let timeSinceLastPreview = now.timeIntervalSince(lastPreviewTime)
        let pitchesChanged = pitches != lastPreviewedPitches
        
        // Only trigger if pitch set changed or at least 100ms have passed
        if pitchesChanged || timeSinceLastPreview > 0.1 {
            lastPreviewedPitches = pitches
            lastPreviewTime = now
            
            // Play all pitches in the chord (sorted for consistent triggering)
            // Limit to 8 simultaneous notes to prevent audio overload
            let sortedPitches = pitches.sorted()
            let pitchesToPlay = sortedPitches.prefix(8)
            
            for pitch in pitchesToPlay {
                onPreviewNote?(pitch)
            }
        }
    }
    
    private func resizeNote(_ note: MIDINote, by delta: CGFloat) {
        guard let index = region.notes.firstIndex(where: { $0.id == note.id }) else { return }
        
        // Capture state at resize START (first call)
        if notesBeforeResize.isEmpty {
            notesBeforeResize = region.notes
        }
        
        let durationDelta = delta / scaledPixelsPerBeat
        var newDuration = note.durationBeats + durationDelta
        
        if snapResolution != .off {
            newDuration = max(snapResolution.stepDurationBeats, snapResolution.quantize(beat:newDuration))
        } else {
            newDuration = max(0.01, newDuration)
        }
        
        region.notes[index].durationBeats = newDuration
        
        // NOTE: Undo is registered at resize END, not during resize motion (see onResizeEnd callback)
        // This prevents undo stack pollution (hundreds of undo entries per resize)
    }
    
    private func updateNoteVelocity(_ noteId: UUID, velocity: UInt8) {
        guard let index = region.notes.firstIndex(where: { $0.id == noteId }) else { return }
        
        // Create a new copy to ensure binding updates properly
        var updatedNotes = region.notes
        updatedNotes[index].velocity = velocity
        region.notes = updatedNotes
    }
    
    /// Update velocity for all selected notes to an absolute value
    private func updateSelectedNotesVelocity(_ velocity: UInt8) {
        guard !selectedNotes.isEmpty else { return }
        
        var updatedNotes = region.notes
        for i in updatedNotes.indices {
            if selectedNotes.contains(updatedNotes[i].id) {
                updatedNotes[i].velocity = velocity
            }
        }
        region.notes = updatedNotes
    }
    
    private func quantizeSelected() {
        guard snapResolution != .off else { return }
        
        for id in selectedNotes {
            if let index = region.notes.firstIndex(where: { $0.id == id }) {
                region.notes[index].startBeat = snapResolution.quantize(beat:region.notes[index].startBeat)
                region.notes[index].durationBeats = max(
                    snapResolution.stepDurationBeats,
                    snapResolution.quantize(beat:region.notes[index].durationBeats)
                )
            }
        }
    }
}

// MARK: - VelocityEditorView

/// Toolbar component for editing velocity of selected notes.
/// Uses a slider for adjustment with read-only text display.
struct VelocityEditorView: View {
    let selectedNotes: Set<UUID>
    let notes: [MIDINote]
    let onVelocityChange: (UInt8) -> Void
    
    /// Computed average velocity of selected notes for display
    private var displayVelocity: UInt8 {
        let selectedNotesList = notes.filter { selectedNotes.contains($0.id) }
        guard !selectedNotesList.isEmpty else { return 100 }  // Default to standard DAW velocity when no selection
        let sum = selectedNotesList.reduce(0) { $0 + Int($1.velocity) }
        return UInt8(sum / selectedNotesList.count)
    }
    
    /// Range of velocities in selection (for showing variation)
    private var velocityRange: (min: UInt8, max: UInt8)? {
        let selectedNotesList = notes.filter { selectedNotes.contains($0.id) }
        guard selectedNotesList.count > 1 else { return nil }
        let velocities = selectedNotesList.map { $0.velocity }
        guard let min = velocities.min(), let max = velocities.max(), min != max else { return nil }
        return (min, max)
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Velocity slider
            Slider(
                value: Binding(
                    get: { Double(displayVelocity) },
                    set: { newValue in
                        let velocity = UInt8(clamping: Int(newValue))
                        onVelocityChange(velocity)
                    }
                ),
                in: 1...127,
                step: 1
            )
            .frame(width: 100)
            .tint(.blue)
            
            // Read-only velocity display (always synced with slider)
            Text("\(displayVelocity)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .frame(width: 28, alignment: .trailing)
                .foregroundColor(.primary)
            
            // Show velocity range indicator if multiple notes with different velocities
            if let range = velocityRange {
                Text("(\(range.min)-\(range.max))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - NoteView

/// Individual MIDI note view with drag and resize support.
struct NoteView: View {
    let note: MIDINote
    let isSelected: Bool
    let editMode: PianoRollEditMode
    let width: CGFloat
    let height: CGFloat
    let pixelsPerBeat: CGFloat
    let onSelect: () -> Void
    let onDeselect: () -> Void
    let onPlaySound: () -> Void
    let onMove: (CGSize) -> Void
    let onResize: (CGFloat) -> Void
    let onDelete: () -> Void
    let onResizeEnd: () -> Void
    let onDragEnd: () -> Void
    let onSlice: (Double) -> Void  // Split note at position in beats (relative to note start)
    let onGlue: () -> Void               // Merge with next adjacent note
    let onLegato: () -> Void             // Extend to next note
    
    @State private var isDragging = false
    @State private var isResizing = false
    
    private let resizeHandleWidth: CGFloat = 8
    
    var body: some View {
        ZStack(alignment: .trailing) {
            // Note body
            RoundedRectangle(cornerRadius: 3)
                .fill(noteColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(isSelected ? Color.white : Color.black.opacity(0.3), lineWidth: isSelected ? 2 : 0.5)
                )
                .shadow(color: .black.opacity(isDragging ? 0.3 : 0.1), radius: isDragging ? 4 : 1, y: isDragging ? 2 : 0)
            
            // Resize handle
            Rectangle()
                .fill(Color.clear)
                .frame(width: resizeHandleWidth)
                .contentShape(Rectangle())
                .gesture(resizeGesture)
                .onHover { hovering in
                    if hovering {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            
            // Velocity indicator (darker strip on left)
            if height >= 8 {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 3)
                    Spacer()
                }
            }
        }
        .frame(width: width, height: height - 1)
        .gesture(editMode == .select ? moveGesture : nil)
        .gesture(editMode == .slice ? sliceGesture : nil)
        .onTapGesture {
            switch editMode {
            case .select:
                // Play sound when clicking a note
                onPlaySound()
                // Toggle selection
                if isSelected {
                    onDeselect()
                } else {
                    onSelect()
                }
            case .erase:
                // Delete note when in erase mode
                onDelete()
            case .draw:
                // In draw mode, clicking existing note selects it
                onPlaySound()
                if !isSelected {
                    onSelect()
                }
            case .glue:
                // Merge with next adjacent note of same pitch
                onGlue()
            case .legato:
                // Extend note to next note
                onLegato()
            case .slice, .brush, .velocity:
                // Handled by drag gesture or other mechanism
                break
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
            Divider()
            Text("Pitch: \(note.noteName)")
            Text("Velocity: \(note.velocity)")
            Text("Duration: \(String(format: "%.2f", note.durationBeats)) beats")
        }
    }
    
    private var noteColor: Color {
        // Professional velocity gradient: cool (low) → warm (high)
        // This gives immediate visual feedback about note dynamics
        let velocityFactor = Double(note.velocity) / 127.0
        
        if isSelected {
            // Selected notes: orange tint with brightness based on velocity
            let saturation = 0.7 + velocityFactor * 0.3  // 0.7 to 1.0
            let brightness = 0.6 + velocityFactor * 0.4  // 0.6 to 1.0
            return Color(hue: 0.08, saturation: saturation, brightness: brightness)  // Orange hue
        } else {
            // Unselected notes: blue (low) → cyan (mid) → green (high) gradient
            // Hue: 0.6 (blue) → 0.45 (cyan) → 0.35 (teal) → 0.28 (green)
            let hue = 0.6 - velocityFactor * 0.35  // Blue to teal/green
            let saturation = 0.65 + velocityFactor * 0.35  // 0.65 to 1.0
            let brightness = 0.5 + velocityFactor * 0.5  // 0.5 to 1.0
            return Color(hue: hue, saturation: saturation, brightness: brightness)
        }
    }
    
    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                onMove(value.translation)
            }
            .onEnded { _ in
                isDragging = false
                onDragEnd()
            }
    }
    
    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isResizing = true
                onResize(value.translation.width)
            }
            .onEnded { _ in
                isResizing = false
                onResizeEnd()
            }
    }
    
    /// Slice gesture: tap anywhere on note to split at that position
    private var sliceGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                // Calculate the relative position within the note (in beats)
                let relativeX = value.location.x
                let relativeBeats = relativeX / pixelsPerBeat
                
                // Only slice if click is not too close to edges (min 0.1 beats from each edge)
                let minSliceMargin = 0.1
                if relativeBeats > minSliceMargin && relativeBeats < (note.durationBeats - minSliceMargin) {
                    onSlice(relativeBeats)
                }
            }
    }
}

// MARK: - Isolated Playhead (Performance Optimization)
// Uses @Observable AudioEngine for fine-grained updates
// Only this view re-renders when currentPosition changes, not the parent piano roll

private struct PianoRollPlayhead: View {
    @Environment(AudioEngine.self) private var audioEngine
    let pixelsPerBeat: CGFloat
    let height: CGFloat
    
    var body: some View {
        // PERF: Use TimelineReader to isolate playhead updates - prevents parent re-renders
        TimelineView(.animation(minimumInterval: 1/60)) { timeline in
            let currentBeats = audioEngine.currentPosition.beats
            let xOffset = CGFloat(currentBeats) * pixelsPerBeat
            
            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: height)
                .offset(x: xOffset)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - MIDI CC Automation Lane

/// Bridges MIDIRegion CC events with the visual AutomationLane system
struct MIDICCAutomationLane: View {
    @Binding var lane: AutomationLane
    @Binding var region: MIDIRegion
    let durationBeats: Double
    let pixelsPerBeat: CGFloat
    let height: CGFloat
    
    @State private var selectedPoints: Set<UUID> = []
    @State private var isDrawing = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Rectangle()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                
                // Grid lines
                gridLines(in: geometry)
                
                // Curve fill
                curveFill(in: geometry)
                
                // Curve stroke
                curveStroke(in: geometry)
                
                // Breakpoints
                breakpoints(in: geometry)
            }
            .contentShape(Rectangle())
            .gesture(drawGesture(in: geometry))
        }
        .frame(height: height)
        .onAppear { syncFromMIDI() }
        .onChange(of: lane.points) { _, _ in syncToMIDI() }
    }
    
    // MARK: - Grid Lines
    
    private func gridLines(in geometry: GeometryProxy) -> some View {
        Canvas { context, size in
            // Horizontal lines at 25%, 50%, 75%
            for fraction in [0.25, 0.5, 0.75] {
                let y = size.height * (1 - CGFloat(fraction))
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
            }
            
            // Vertical beat lines
            var x: CGFloat = 0
            while x < size.width {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(.gray.opacity(0.15)), lineWidth: 0.5)
                x += pixelsPerBeat
            }
        }
    }
    
    // MARK: - Curve Drawing
    
    /// Default value for this parameter (used for baseline)
    private var defaultY: CGFloat {
        CGFloat(1 - lane.parameter.defaultValue)
    }
    
    private func curveFill(in geometry: GeometryProxy) -> some View {
        Path { path in
            let sortedPoints = lane.sortedPoints
            let defaultYPos = geometry.size.height * defaultY
            let endX = geometry.size.width  // Extend to full visible width
            
            // Start from bottom-left
            path.move(to: CGPoint(x: 0, y: geometry.size.height))
            
            if sortedPoints.isEmpty {
                // No points: draw baseline at default value
                path.addLine(to: CGPoint(x: 0, y: defaultYPos))
                path.addLine(to: CGPoint(x: endX, y: defaultYPos))
                path.addLine(to: CGPoint(x: endX, y: geometry.size.height))
            } else {
                // Draw from start at default/first value
                let firstPos = pointPosition(sortedPoints.first!, in: geometry)
                path.addLine(to: CGPoint(x: 0, y: firstPos.y))
                path.addLine(to: firstPos)
                
                // Draw through all points
                for i in 1..<sortedPoints.count {
                    addCurveSegment(from: sortedPoints[i-1], to: sortedPoints[i], in: geometry, to: &path)
                }
                
                // Extend to end of region at last value
                let lastPos = pointPosition(sortedPoints.last!, in: geometry)
                path.addLine(to: CGPoint(x: endX, y: lastPos.y))
                path.addLine(to: CGPoint(x: endX, y: geometry.size.height))
            }
            
            path.closeSubpath()
        }
        .fill(lane.color.opacity(0.15))
    }
    
    private func curveStroke(in geometry: GeometryProxy) -> some View {
        Path { path in
            let sortedPoints = lane.sortedPoints
            let defaultYPos = geometry.size.height * defaultY
            let endX = geometry.size.width  // Extend to full visible width
            
            if sortedPoints.isEmpty {
                // No points: draw baseline at default value
                path.move(to: CGPoint(x: 0, y: defaultYPos))
                path.addLine(to: CGPoint(x: endX, y: defaultYPos))
            } else {
                // Start from x=0 at first point's value
                let firstPos = pointPosition(sortedPoints.first!, in: geometry)
                path.move(to: CGPoint(x: 0, y: firstPos.y))
                path.addLine(to: firstPos)
                
                // Draw through all points
                for i in 1..<sortedPoints.count {
                    addCurveSegment(from: sortedPoints[i-1], to: sortedPoints[i], in: geometry, to: &path)
                }
                
                // Extend to end of region
                let lastPos = pointPosition(sortedPoints.last!, in: geometry)
                path.addLine(to: CGPoint(x: endX, y: lastPos.y))
            }
        }
        .stroke(lane.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
    
    private func addCurveSegment(from p1: AutomationPoint, to p2: AutomationPoint, in geometry: GeometryProxy, to path: inout Path) {
        let pos1 = pointPosition(p1, in: geometry)
        let pos2 = pointPosition(p2, in: geometry)
        
        switch p1.curve {
        case .linear:
            path.addLine(to: pos2)
        case .smooth:
            let controlX = (pos1.x + pos2.x) / 2
            path.addCurve(to: pos2, control1: CGPoint(x: controlX, y: pos1.y), control2: CGPoint(x: controlX, y: pos2.y))
        case .step:
            path.addLine(to: CGPoint(x: pos2.x, y: pos1.y))
            path.addLine(to: pos2)
        case .exponential:
            let controlX = pos1.x + (pos2.x - pos1.x) * 0.8
            path.addQuadCurve(to: pos2, control: CGPoint(x: controlX, y: pos1.y))
        case .logarithmic:
            let controlX = pos1.x + (pos2.x - pos1.x) * 0.2
            path.addQuadCurve(to: pos2, control: CGPoint(x: controlX, y: pos2.y))
        case .sCurve:
            let controlX1 = pos1.x + (pos2.x - pos1.x) * 0.25
            let controlX2 = pos1.x + (pos2.x - pos1.x) * 0.75
            path.addCurve(to: pos2, control1: CGPoint(x: controlX1, y: pos1.y), control2: CGPoint(x: controlX2, y: pos2.y))
        }
    }
    
    private func pointPosition(_ point: AutomationPoint, in geometry: GeometryProxy) -> CGPoint {
        let x = point.beat * pixelsPerBeat
        let y = geometry.size.height * (1 - CGFloat(point.value))
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Breakpoints
    
    private func breakpoints(in geometry: GeometryProxy) -> some View {
        ForEach(lane.points) { point in
            let position = pointPosition(point, in: geometry)
            let isSelected = selectedPoints.contains(point.id)
            
            ZStack {
                // Value label (shown above or below the point)
                Text(valueLabel(for: point))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(lane.color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                    )
                    .offset(x: 20, y: position.y < 30 ? 16 : -16)  // Below if near top, else above
                
                // Breakpoint circle
                Circle()
                    .fill(isSelected ? Color.white : lane.color)
                    .frame(width: isSelected ? 12 : 10, height: isSelected ? 12 : 10)
                    .overlay(
                        Circle()
                            .stroke(lane.color, lineWidth: 2)
                    )
                    .shadow(color: lane.color.opacity(0.5), radius: 2)
            }
            .position(position)
            .gesture(pointDragGesture(point: point, geometry: geometry))
            .onTapGesture { selectedPoints = [point.id] }
            .contextMenu {
                Button("Delete", role: .destructive) {
                    lane.removePoint(point.id)
                }
                Divider()
                Text("Beat: \(String(format: "%.2f", point.beat))")
                Text("Value: \(valueLabel(for: point))")
            }
        }
    }
    
    /// Format value label based on parameter type
    private func valueLabel(for point: AutomationPoint) -> String {
        switch lane.parameter {
        case .pitchBend:
            // Convert from 0-1 display to -8192...+8191 range, show as semitones
            let bendValue = (point.value - 0.5) * 2  // -1 to +1
            let semitones = bendValue * 2  // Assuming ±2 semitone range
            if abs(semitones) < 0.1 {
                return "0 st"
            }
            return String(format: "%+.1f st", semitones)
        case .midiCC64:  // Sustain is on/off
            return point.value > 0.5 ? "On" : "Off"
        default:
            // Show as percentage for most CC values
            return "\(Int(point.value * 100))%"
        }
    }
    
    private func pointDragGesture(point: AutomationPoint, geometry: GeometryProxy) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let beat = max(0, value.location.x / pixelsPerBeat)
                let normalizedValue = Float(max(0, min(1, 1 - value.location.y / geometry.size.height)))
                lane.updatePoint(point.id, beat: beat, value: normalizedValue)
            }
            .onEnded { _ in
                // Sync to MIDI when drag ends
                syncToMIDI()
            }
    }
    
    // MARK: - Gestures
    
    private func drawGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let beat = max(0, value.location.x / pixelsPerBeat)
                let normalizedValue = Float(max(0, min(1, 1 - value.location.y / geometry.size.height)))
                
                if isDrawing {
                    // Update or add point near cursor
                    addOrUpdatePoint(atBeat: beat, value: normalizedValue)
                } else {
                    isDrawing = true
                    lane.addPoint(atBeat: beat, value: normalizedValue)
                }
            }
            .onEnded { _ in
                isDrawing = false
                // Explicitly sync to MIDI when gesture ends (in case onChange didn't fire)
                syncToMIDI()
            }
    }
    
    private func addOrUpdatePoint(atBeat beat: Double, value: Float) {
        let threshold = 0.1
        if let existingIndex = lane.points.firstIndex(where: { abs($0.beat - beat) < threshold }) {
            lane.points[existingIndex].value = value
        } else {
            lane.addPoint(atBeat: beat, value: value)
        }
    }
    
    // MARK: - MIDI Sync
    
    /// Sync automation lane points FROM MIDIRegion CC events
    private func syncFromMIDI() {
        guard let ccNumber = lane.parameter.ccNumber else {
            // Handle pitch bend separately
            if lane.parameter == .pitchBend {
                lane.points = region.pitchBendEvents.map { event in
                    // Convert from -1...1 to 0...1 range for display
                    let displayValue = (event.normalizedValue + 1) / 2
                    return AutomationPoint(
                        beat: event.beat,
                        value: displayValue,
                        curve: .linear
                    )
                }
            }
            return
        }
        
        // Filter CC events for this controller number
        let relevantEvents = region.controllerEvents.filter { $0.controller == ccNumber }
        lane.points = relevantEvents.map { event in
            AutomationPoint(
                beat: event.beat,
                value: Float(event.value) / 127.0,
                curve: .linear
            )
        }
    }
    
    /// Sync automation lane points TO MIDIRegion CC events
    private func syncToMIDI() {
        guard let ccNumber = lane.parameter.ccNumber else {
            // Handle pitch bend separately
            if lane.parameter == .pitchBend {
                region.pitchBendEvents = lane.sortedPoints.map { point in
                    MIDIPitchBendEvent.fromNormalized(point.value * 2 - 1, beat: point.beat)
                }
            }
            return
        }
        
        // Remove existing events for this CC and add updated ones
        region.controllerEvents.removeAll { $0.controller == ccNumber }
        
        for point in lane.sortedPoints {
            let event = MIDICCEvent(
                controller: ccNumber,
                value: UInt8(clamping: Int(point.value * 127)),
                beat: point.beat
            )
            region.controllerEvents.append(event)
        }
    }
}

// MARK: - Piano Keyboard Scroll Wrapper

/// Wrapper for piano keyboard that handles both click/drag gestures and scroll wheel events
private struct PianoKeyboardScrollWrapper: NSViewRepresentable {
    let keyboard: AnyView
    let keyboardWidth: CGFloat
    let availableHeight: CGFloat
    @Binding var verticalScrollOffset: CGFloat
    let gridHeight: CGFloat
    let onPreviewNote: ((UInt8) -> Void)?
    let keyboardPitchAt: (CGFloat) -> Int
    let minPitch: Int
    let maxPitch: Int
    
    func makeNSView(context: Context) -> NSScrollableKeyboardView {
        let view = NSScrollableKeyboardView()
        view.onScroll = { deltaY in
            let maxOffset = max(0, gridHeight - availableHeight)
            let newOffset = max(0, min(verticalScrollOffset - deltaY, maxOffset))
            DispatchQueue.main.async {
                verticalScrollOffset = newOffset
            }
        }
        
        // Add hosting view for SwiftUI keyboard
        let hostingView = NSHostingView(rootView: keyboard)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingView)
        
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: view.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Store callbacks for mouse handling
        view.onMouseDown = { location in
            let pitch = keyboardPitchAt(location.y)
            if pitch >= minPitch && pitch <= maxPitch {
                onPreviewNote?(UInt8(pitch))
            }
        }
        
        view.onMouseDragged = { location in
            let pitch = keyboardPitchAt(location.y)
            if pitch >= minPitch && pitch <= maxPitch {
                onPreviewNote?(UInt8(pitch))
            }
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSScrollableKeyboardView, context: Context) {
        // Update hosting view with new keyboard
        if let hostingView = nsView.subviews.first as? NSHostingView<AnyView> {
            hostingView.rootView = keyboard
        }
    }
}

private class NSScrollableKeyboardView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    var onMouseDown: ((NSPoint) -> Void)?
    var onMouseDragged: ((NSPoint) -> Void)?
    
    override func scrollWheel(with event: NSEvent) {
        let deltaY = event.scrollingDeltaY
        onScroll?(deltaY)  // Direct delta (natural scrolling)
    }
    
    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onMouseDown?(location)
    }
    
    override func mouseDragged(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        onMouseDragged?(location)
    }
}
