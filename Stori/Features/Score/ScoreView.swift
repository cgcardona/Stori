//
//  ScoreView.swift
//  Stori
//
//  Professional music score notation view
//  Displays MIDI data as traditional Western notation with bi-directional sync
//

import SwiftUI
import AppKit

// MARK: - Score Track Data

/// Represents a MIDI track's data for score rendering
struct ScoreTrackData: Identifiable {
    let id: UUID
    let name: String
    let region: MIDIRegion?
    let color: Color
    var clef: Clef = .treble  // Can be auto-detected based on pitch range
    
    init(from track: AudioTrack) {
        self.id = track.id
        self.name = track.name
        self.color = track.color.color  // Convert TrackColor to SwiftUI Color
        // Get the first MIDI region from the track
        self.region = track.midiRegions.first
        // Auto-detect clef based on average pitch
        if let region = self.region, !region.notes.isEmpty {
            let avgPitch = Double(region.notes.map { Int($0.pitch) }.reduce(0, +)) / Double(region.notes.count)
            self.clef = avgPitch < 60 ? .bass : .treble
        }
    }
    
    // Manual initializer for legacy single-track mode
    init(id: UUID, name: String, region: MIDIRegion?, color: Color) {
        self.id = id
        self.name = name
        self.region = region
        self.color = color
        // Auto-detect clef
        if let region = region, !region.notes.isEmpty {
            let avgPitch = Double(region.notes.map { Int($0.pitch) }.reduce(0, +)) / Double(region.notes.count)
            self.clef = avgPitch < 60 ? .bass : .treble
        }
    }
}

// MARK: - Score View

/// Main score notation editor view - supports multiple MIDI tracks
struct ScoreView: View {
    // Support both single region (legacy) and multi-track modes
    @Binding var region: MIDIRegion
    var midiTracks: [AudioTrack] = []  // All MIDI tracks for multi-staff display
    
    @State private var configuration = ScoreConfiguration()
    @State private var selectedNotes: Set<UUID> = []
    @State private var horizontalZoom: CGFloat = 1.0
    @State private var trackMeasures: [UUID: [ScoreMeasure]] = [:]  // Measures per track
    @State private var measures: [ScoreMeasure] = []  // Legacy single-track measures
    
    // Entry mode
    @State private var entryMode: ScoreEntryMode = .select
    @State private var currentDuration: NoteDuration = .quarter
    
    // For preview/playback - PERF: Uses isolated ScorePlayhead component
    var onPreviewNote: ((UInt8) -> Void)?
    var tempo: Double = 120.0
    
    // Cycle region (synced with main timeline)
    var cycleEnabled: Bool = false
    var cycleStartBeat: Double = 0
    var cycleEndBeat: Double = 4
    
    // Layout metrics — single source of truth for all spacing constants.
    // Every coordinate decision flows through ScoreLayoutMetrics.
    private let metrics = ScoreLayoutMetrics()
    
    private let renderer = StaffRenderer()
    
    /// Create a coordinate mapper for a specific clef.
    /// Both rendering and interaction MUST use this to guarantee coordinate agreement.
    private func makeMapper(for clef: Clef) -> ScoreCoordinateMapper {
        ScoreCoordinateMapper(
            metrics: metrics,
            clef: clef,
            keySignature: configuration.keySignature,
            timeSignature: configuration.timeSignature,
            horizontalZoom: horizontalZoom
        )
    }
    
    // Computed property for track data
    private var scoreTracks: [ScoreTrackData] {
        if midiTracks.isEmpty {
            // Legacy single-track mode
            return [ScoreTrackData(id: region.id, name: "Track", region: region, color: .blue)]
        } else {
            return midiTracks.map { ScoreTrackData(from: $0) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            scoreToolbar
            
            Divider()
            
            // Score content - multi-track layout
            GeometryReader { geometry in
                let defaultMapper = makeMapper(for: scoreTracks.first?.clef ?? .treble)
                let scaledMeasureWidth = defaultMapper.scaledMeasureWidth
                let contentStartX = metrics.trackLabelWidth + defaultMapper.contentStartX
                let maxMeasures = scoreTracks.compactMap { $0.region?.notes.map { $0.endBeat }.max() }.max().map { Int(ceil($0 / configuration.timeSignature.measureDuration)) } ?? 4
                let totalWidth = max(geometry.size.width, CGFloat(max(4, maxMeasures)) * scaledMeasureWidth + contentStartX + 50)
                
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: - Ruler with Cycle Region (fixed at top)
                        HStack(spacing: 0) {
                            // Empty space for track labels column
                            Rectangle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: metrics.trackLabelWidth, height: metrics.rulerHeight)
                            
                            ZStack(alignment: .topLeading) {
                                // Ruler background
                                Rectangle()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                
                                // Cycle region overlay
                                if cycleEnabled {
                                    scoreCycleOverlay(contentStartX: defaultMapper.contentStartX, scaledMeasureWidth: scaledMeasureWidth)
                                }
                                
                                // Measure ruler — uses mapper's contentStartX for exact alignment
                                scoreRuler(contentStartX: defaultMapper.contentStartX, scaledMeasureWidth: scaledMeasureWidth, totalWidth: totalWidth - metrics.trackLabelWidth)
                                
                                // Playhead in ruler
                                ScorePlayhead(
                                    contentStartX: defaultMapper.contentStartX,
                                    scaledMeasureWidth: scaledMeasureWidth,
                                    measureDuration: configuration.timeSignature.measureDuration,
                                    height: metrics.rulerHeight
                                )
                            }
                            .frame(width: totalWidth - metrics.trackLabelWidth, height: metrics.rulerHeight)
                        }
                        
                        Divider()
                        
                        // MARK: - Multi-Track Staff Rows
                        ForEach(scoreTracks) { trackData in
                            let trackMapper = makeMapper(for: trackData.clef)
                            
                            HStack(spacing: 0) {
                                // Track label on the left
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(trackData.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    
                                    // Track color indicator
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(trackData.color)
                                        .frame(width: 40, height: 4)
                                }
                                .frame(width: metrics.trackLabelWidth - 8, alignment: .leading)
                                .padding(.horizontal, 4)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                
                                // Staff content for this track
                                ZStack(alignment: .topLeading) {
                                    staffRowContent(for: trackData, mapper: trackMapper, totalWidth: totalWidth - metrics.trackLabelWidth)
                                    
                                    // Playhead in staff
                                    ScorePlayhead(
                                        contentStartX: trackMapper.contentStartX,
                                        scaledMeasureWidth: scaledMeasureWidth,
                                        measureDuration: configuration.timeSignature.measureDuration,
                                        height: metrics.staffRowHeight
                                    )
                                }
                                .frame(width: totalWidth - metrics.trackLabelWidth, height: metrics.staffRowHeight)
                                .contentShape(Rectangle())
                                .gesture(
                                    SpatialTapGesture()
                                        .onEnded { value in
                                            handleTap(at: value.location, trackData: trackData)
                                        }
                                )
                            }
                            
                            // Divider between track rows
                            Divider()
                        }
                        
                        // Push content to top when it doesn't fill the viewport
                        Spacer(minLength: 0)
                    }
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                }
                .scrollContentBackground(.hidden)
                .onAppear {
                    quantizeAllTracks()
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            quantizeAllTracks()
        }
        // FIX (Issue #67): Removed .onChange(of: region.notes) reactive loop
        // that caused unnecessary re-quantization and potential precision loss.
        // NotationQuantizer creates display-only ScoreNotes without modifying MIDI,
        // so we only need to re-quantize when display configuration changes.
        .onChange(of: configuration.clef) { _, _ in
            quantizeAllTracks()
        }
        .onChange(of: configuration.timeSignature) { _, _ in
            quantizeAllTracks()
        }
        .onChange(of: configuration.keySignature) { _, _ in
            quantizeAllTracks()
        }
    }
    
    // MARK: - Staff Row Content (per track)
    
    /// Renders a single staff row using the shared coordinate mapper.
    /// Note positions come from the mapper, guaranteeing exact agreement
    /// with hit-testing coordinates. Decorations (clef, key sig, time sig)
    /// are drawn incrementally, and their widths match the mapper's
    /// contentStartX computation.
    private func staffRowContent(for trackData: ScoreTrackData, mapper: ScoreCoordinateMapper, totalWidth: CGFloat) -> some View {
        let trackMeasureArray = self.trackMeasures[trackData.id] ?? []
        
        return Canvas { context, size in
            // Draw decorations — positions match mapper's contentStartX calculation
            var drawX = mapper.metrics.clefStartX
            
            // Draw clef
            renderer.drawClef(
                context: context,
                clef: trackData.clef,
                x: drawX,
                yOffset: mapper.yOffset
            )
            drawX += mapper.metrics.clefWidth
            
            // Draw key signature (was missing from multi-track path)
            drawX = renderer.drawKeySignature(
                context: context,
                keySignature: configuration.keySignature,
                clef: trackData.clef,
                x: drawX,
                yOffset: mapper.yOffset
            )
            
            // Draw time signature
            drawX = renderer.drawTimeSignature(
                context: context,
                timeSignature: configuration.timeSignature,
                x: drawX,
                yOffset: mapper.yOffset
            )
            // drawX now equals mapper.contentStartX - postTimeSigSpacing (by construction)
            
            // Draw staff lines across entire width
            renderer.drawStaffLines(
                context: context,
                width: totalWidth,
                yOffset: mapper.yOffset
            )
            
            // Draw measures with notes — all positions from the mapper
            for (measureIndex, measure) in trackMeasureArray.enumerated() {
                let measureStartX = mapper.measureStartX(at: measureIndex)
                
                // Bar line
                if measureIndex > 0 {
                    renderer.drawBarLine(context: context, x: measureStartX, yOffset: mapper.yOffset)
                }
                
                // Draw notes using mapper for exact positioning
                for note in measure.notes {
                    let noteX = mapper.xForNoteInMeasure(note, measureIndex: measureIndex)
                    
                    let isSelected = selectedNotes.contains(note.id)
                    renderer.drawNote(
                        context: context,
                        note: note,
                        x: noteX,
                        clef: trackData.clef,
                        yOffset: mapper.yOffset,
                        isSelected: isSelected
                    )
                }
            }
            
            // Final bar line
            if !trackMeasureArray.isEmpty {
                let finalX = mapper.measureStartX(at: trackMeasureArray.count)
                renderer.drawBarLine(context: context, x: finalX, yOffset: mapper.yOffset, style: .final)
            }
        }
        .drawingGroup()
    }
    
    // MARK: - Quantize All Tracks
    
    private func quantizeAllTracks() {
        let quantizer = NotationQuantizer()
        
        // Quantize main region (legacy support)
        measures = quantizer.quantize(
            notes: region.notes,
            timeSignature: configuration.timeSignature,
            tempo: configuration.tempo,
            keySignature: configuration.keySignature
        )
        
        // Quantize each track's region
        var newTrackMeasures: [UUID: [ScoreMeasure]] = [:]
        for trackData in scoreTracks {
            if let region = trackData.region {
                newTrackMeasures[trackData.id] = quantizer.quantize(
                    notes: region.notes,
                    timeSignature: configuration.timeSignature,
                    tempo: configuration.tempo,
                    keySignature: configuration.keySignature
                )
            } else {
                newTrackMeasures[trackData.id] = []
            }
        }
        trackMeasures = newTrackMeasures
    }
    
    // MARK: - Score Ruler (Measure Numbers)
    
    private func scoreRuler(contentStartX: CGFloat, scaledMeasureWidth: CGFloat, totalWidth: CGFloat) -> some View {
        Canvas { context, size in
            let measureCount = max(1, measures.count)
            
            // Draw measure numbers and tick marks
            for measureIndex in 0...measureCount {
                let x = contentStartX + CGFloat(measureIndex) * scaledMeasureWidth
                
                // Measure line
                var linePath = Path()
                linePath.move(to: CGPoint(x: x, y: size.height - 10))
                linePath.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(linePath, with: .color(.primary), lineWidth: 1)
                
                // Measure number (1-indexed)
                if measureIndex < measureCount {
                    let measureNumber = Text("\(measureIndex + 1)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary)
                    context.draw(measureNumber, at: CGPoint(x: x + 4, y: size.height - 18), anchor: .topLeading)
                }
                
                // Beat ticks within measure (if zoomed in enough)
                if scaledMeasureWidth > 100 && measureIndex < measureCount {
                    let beatsPerMeasure = configuration.timeSignature.beats
                    for beat in 1..<beatsPerMeasure {
                        let beatX = x + CGFloat(beat) * scaledMeasureWidth / CGFloat(beatsPerMeasure)
                        var beatPath = Path()
                        beatPath.move(to: CGPoint(x: beatX, y: size.height - 5))
                        beatPath.addLine(to: CGPoint(x: beatX, y: size.height))
                        context.stroke(beatPath, with: .color(.primary.opacity(0.4)), lineWidth: 0.5)
                    }
                }
            }
        }
        .frame(width: totalWidth, height: metrics.rulerHeight)
        .drawingGroup()
    }
    
    // MARK: - Cycle Region Overlay
    
    private func scoreCycleOverlay(contentStartX: CGFloat, scaledMeasureWidth: CGFloat) -> some View {
        let measureDuration = configuration.timeSignature.measureDuration
        let cycleStartX = contentStartX + CGFloat(cycleStartBeat / measureDuration) * scaledMeasureWidth
        let cycleEndX = contentStartX + CGFloat(cycleEndBeat / measureDuration) * scaledMeasureWidth
        let cycleWidth = cycleEndX - cycleStartX
        
        return Rectangle()
            .fill(Color.yellow.opacity(0.3))
            .frame(width: max(0, cycleWidth), height: metrics.rulerHeight - 10)
            .offset(x: cycleStartX, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.yellow.opacity(0.6), lineWidth: 1)
                    .frame(width: max(0, cycleWidth), height: metrics.rulerHeight - 10)
                    .offset(x: cycleStartX, y: 2)
            )
    }
    
    // MARK: - Toolbar
    
    /// Toolbar styled to match Piano Roll: icon tools, dropdown menus, slider zoom.
    private var scoreToolbar: some View {
        HStack(spacing: 0) {
            // LEFT: Score-specific menus (Clef, Key, Time)
            scoreMenuBar
                .padding(.leading, 8)
            
            scoreToolbarDivider
            
            // CENTER-LEFT: Tool selector (icon buttons matching Piano Roll style)
            ScoreToolSelector(selection: $entryMode)
                .padding(.horizontal, 8)
            
            scoreToolbarDivider
            
            // Duration palette (when in draw mode)
            if entryMode == .draw {
                durationPalette
                    .padding(.horizontal, 8)
                scoreToolbarDivider
            }
            
            // Transform menu (when notes are selected)
            if !selectedNotes.isEmpty {
                transformMenu
                    .padding(.horizontal, 8)
                scoreToolbarDivider
            }
            
            // Export / refresh
            HStack(spacing: 6) {
                Menu {
                    Button(action: exportToPDF) {
                        Label("Export PDF...", systemImage: "doc.fill")
                    }
                    Button(action: exportToMusicXML) {
                        Label("Export MusicXML...", systemImage: "doc.text")
                    }
                    Divider()
                    Button(action: printScore) {
                        Label("Print...", systemImage: "printer")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .help("Export or Print")
                
                Button(action: quantizeMIDI) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Re-quantize from MIDI")
            }
            .padding(.horizontal, 8)
            
            Spacer()
            
            // RIGHT: Zoom control (slider matching Piano Roll style)
            scoreZoomControl
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    /// Dropdown menus for score configuration (Clef, Key Signature, Time Signature)
    private var scoreMenuBar: some View {
        HStack(spacing: 2) {
            // Clef selector
            Menu {
                ForEach(Clef.allCases) { clef in
                    Button(action: { configuration.clef = clef }) {
                        HStack {
                            Text(clef.displayName)
                            if configuration.clef == clef {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: configuration.clef.iconName)
                        .font(.system(size: 10))
                    Text(configuration.clef.displayName.components(separatedBy: " ").first ?? "")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
            }
            .menuStyle(.borderlessButton)
            
            // Key signature selector
            Menu {
                ForEach(KeySignature.allKeys) { key in
                    Button(action: { configuration.keySignature = key }) {
                        HStack {
                            Text(key.displayName)
                            if configuration.keySignature == key {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(configuration.keySignature.displayName.components(separatedBy: " / ").first ?? "C Major")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            .menuStyle(.borderlessButton)
            
            // Time signature selector
            Menu {
                Button("4/4 (Common)") { configuration.timeSignature = .common }
                Button("3/4 (Waltz)") { configuration.timeSignature = .waltz }
                Button("2/4 (March)") { configuration.timeSignature = .march }
                Button("6/8") { configuration.timeSignature = .compound6 }
                Button("2/2 (Cut)") { configuration.timeSignature = .cut }
            } label: {
                Text(configuration.timeSignature.displayString)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
            }
            .menuStyle(.borderlessButton)
        }
    }
    
    /// Zoom control matching Piano Roll style (arrow icon + slider)
    private var scoreZoomControl: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.left.and.right")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            
            Button(action: { horizontalZoom = max(0.5, horizontalZoom - 0.25) }) {
                Image(systemName: "minus")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            
            Slider(value: $horizontalZoom, in: 0.5...2.0, step: 0.25)
                .frame(width: 70)
            
            Button(action: { horizontalZoom = min(2.0, horizontalZoom + 0.25) }) {
                Image(systemName: "plus")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
        }
    }
    
    /// Consistent divider for toolbar sections
    private var scoreToolbarDivider: some View {
        Divider()
            .frame(height: 20)
            .padding(.horizontal, 4)
    }
    
    // MARK: - Export Actions
    
    private func exportToPDF() {
        let exporter = ScorePDFExporter()
        var exportConfig = ScorePDFExporter.ExportConfiguration()
        exportConfig.title = region.name
        exporter.exportWithDialog(region: region, configuration: configuration, exportConfig: exportConfig)
    }
    
    private func exportToMusicXML() {
        let exporter = MusicXMLExporter()
        exporter.exportWithDialog(region: region, configuration: configuration)
    }
    
    private func printScore() {
        let printController = ScorePrintController()
        printController.printScore(region: region, configuration: configuration)
    }
    
    // MARK: - Duration Palette
    
    private var durationPalette: some View {
        HStack(spacing: 2) {
            ForEach([NoteDuration.whole, .half, .quarter, .eighth, .sixteenth], id: \.self) { duration in
                Button(action: { currentDuration = duration }) {
                    durationIcon(for: duration)
                        .frame(width: 24, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(currentDuration == duration ? Color.accentColor.opacity(0.2) : Color.clear)
                        )
                }
                .buttonStyle(.borderless)
            }
        }
    }
    
    private func durationIcon(for duration: NoteDuration) -> some View {
        VStack(spacing: 0) {
            switch duration {
            case .whole:
                Ellipse()
                    .stroke(lineWidth: 1.5)
                    .frame(width: 12, height: 8)
            case .half:
                VStack(spacing: 0) {
                    Rectangle().frame(width: 1.5, height: 16)
                    Ellipse()
                        .stroke(lineWidth: 1.5)
                        .frame(width: 10, height: 7)
                }
            case .quarter:
                VStack(spacing: 0) {
                    Rectangle().frame(width: 1.5, height: 16)
                    Ellipse()
                        .fill()
                        .frame(width: 10, height: 7)
                }
            case .eighth:
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        Rectangle().frame(width: 1.5, height: 16)
                        Ellipse()
                            .fill()
                            .frame(width: 10, height: 7)
                    }
                    Path { p in
                        p.move(to: CGPoint(x: 12, y: 0))
                        p.addQuadCurve(to: CGPoint(x: 18, y: 10), control: CGPoint(x: 20, y: 3))
                    }
                    .stroke(lineWidth: 1.5)
                    .frame(width: 20, height: 20)
                }
            case .sixteenth:
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 0) {
                        Rectangle().frame(width: 1.5, height: 16)
                        Ellipse()
                            .fill()
                            .frame(width: 10, height: 7)
                    }
                    VStack(spacing: 2) {
                        ForEach(0..<2, id: \.self) { _ in
                            Path { p in
                                p.move(to: CGPoint(x: 0, y: 0))
                                p.addQuadCurve(to: CGPoint(x: 6, y: 6), control: CGPoint(x: 8, y: 2))
                            }
                            .stroke(lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                        }
                    }
                    .offset(x: -2, y: 0)
                }
            default:
                Ellipse()
                    .fill()
                    .frame(width: 10, height: 7)
            }
        }
        .foregroundColor(.primary)
    }
    
    // MARK: - Transform Menu
    
    private var transformMenu: some View {
        Menu {
            Menu("Transpose") {
                Button("Up Octave (⌘↑)") { transposeSelected(by: 12) }
                Button("Down Octave (⌘↓)") { transposeSelected(by: -12) }
                Divider()
                Button("Up Half Step") { transposeSelected(by: 1) }
                Button("Down Half Step") { transposeSelected(by: -1) }
                Divider()
                Button("Up Whole Step") { transposeSelected(by: 2) }
                Button("Down Whole Step") { transposeSelected(by: -2) }
            }
            
            Menu("Duration") {
                Button("Double Duration") { scaleDuration(by: 2.0) }
                Button("Halve Duration") { scaleDuration(by: 0.5) }
            }
            
            Divider()
            
            Button("Invert") { invertSelected() }
            Button("Retrograde") { retrogradeSelected() }
            
            Divider()
            
            Menu("Quantize") {
                Button("Quarter Notes") { quantizeSelected(to: .quarter) }
                Button("Eighth Notes") { quantizeSelected(to: .eighth) }
                Button("Sixteenth Notes") { quantizeSelected(to: .sixteenth) }
            }
            
            Divider()
            
            Button("Delete Selected", role: .destructive) { deleteSelected() }
        } label: {
            Label("Transform", systemImage: "wand.and.stars")
        }
        .help("Transform selected notes")
    }
    
    // MARK: - Transform Actions
    
    private func transposeSelected(by semitones: Int) {
        for noteId in selectedNotes {
            if let measure = measures.first(where: { $0.notes.contains { $0.id == noteId } }),
               let scoreNote = measure.notes.first(where: { $0.id == noteId }) {
                // Update in MIDI region
                if let index = region.notes.firstIndex(where: { $0.id == scoreNote.midiNoteId }) {
                    let newPitch = Int(region.notes[index].pitch) + semitones
                    region.notes[index].pitch = UInt8(max(0, min(127, newPitch)))
                }
            }
        }
        quantizeMIDI()
    }
    
    private func scaleDuration(by factor: Double) {
        for noteId in selectedNotes {
            if let measure = measures.first(where: { $0.notes.contains { $0.id == noteId } }),
               let scoreNote = measure.notes.first(where: { $0.id == noteId }) {
                if let index = region.notes.firstIndex(where: { $0.id == scoreNote.midiNoteId }) {
                    region.notes[index].durationBeats *= factor
                }
            }
        }
        quantizeMIDI()
    }
    
    private func invertSelected() {
        let selectedPitches = selectedNotes.compactMap { noteId -> UInt8? in
            if let measure = measures.first(where: { $0.notes.contains { $0.id == noteId } }),
               let scoreNote = measure.notes.first(where: { $0.id == noteId }) {
                return scoreNote.pitch
            }
            return nil
        }
        guard !selectedPitches.isEmpty else { return }
        
        let pivot = (selectedPitches.min()! + selectedPitches.max()!) / 2
        
        for noteId in selectedNotes {
            if let measure = measures.first(where: { $0.notes.contains { $0.id == noteId } }),
               let scoreNote = measure.notes.first(where: { $0.id == noteId }) {
                if let index = region.notes.firstIndex(where: { $0.id == scoreNote.midiNoteId }) {
                    let distance = Int(region.notes[index].pitch) - Int(pivot)
                    let newPitch = Int(pivot) - distance
                    region.notes[index].pitch = UInt8(max(0, min(127, newPitch)))
                }
            }
        }
        quantizeMIDI()
    }
    
    private func retrogradeSelected() {
        let selectedIndices = selectedNotes.compactMap { noteId -> Int? in
            if let measure = measures.first(where: { $0.notes.contains { $0.id == noteId } }),
               let scoreNote = measure.notes.first(where: { $0.id == noteId }) {
                return region.notes.firstIndex(where: { $0.id == scoreNote.midiNoteId })
            }
            return nil
        }.sorted()
        
        guard selectedIndices.count > 1 else { return }
        
        let startTimes = selectedIndices.map { region.notes[$0].startBeat }
        let reversedStartTimes = Array(startTimes.reversed())
        
        for (i, index) in selectedIndices.enumerated() {
            region.notes[index].startBeat = reversedStartTimes[i]
        }
        quantizeMIDI()
    }
    
    private func quantizeSelected(to resolution: NoteDuration) {
        // Note: MIDI startBeat is in beats, resolution.rawValue is also in beats
        let gridSize = resolution.rawValue
        
        for noteId in selectedNotes {
            if let measure = measures.first(where: { $0.notes.contains { $0.id == noteId } }),
               let scoreNote = measure.notes.first(where: { $0.id == noteId }) {
                if let index = region.notes.firstIndex(where: { $0.id == scoreNote.midiNoteId }) {
                    let quantizedStart = round(region.notes[index].startBeat / gridSize) * gridSize
                    region.notes[index].startBeat = quantizedStart
                }
            }
        }
        quantizeMIDI()
    }
    
    private func deleteSelected() {
        for noteId in selectedNotes {
            if let measure = measures.first(where: { $0.notes.contains { $0.id == noteId } }),
               let scoreNote = measure.notes.first(where: { $0.id == noteId }) {
                region.notes.removeAll { $0.id == scoreNote.midiNoteId }
            }
        }
        selectedNotes.removeAll()
        quantizeMIDI()
    }
    
    // MARK: - Interaction (Mapper-Based)
    
    /// Handle tap gesture on a staff row.
    /// Uses the shared ScoreCoordinateMapper so that click coordinates
    /// and rendering coordinates are guaranteed to agree.
    private func handleTap(at location: CGPoint, trackData: ScoreTrackData) {
        let mapper = makeMapper(for: trackData.clef)
        let trackMeasureArray = trackMeasures[trackData.id] ?? []
        
        switch entryMode {
        case .select:
            if let note = mapper.findNote(at: location, in: trackMeasureArray) {
                let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                if shiftHeld {
                    if selectedNotes.contains(note.id) {
                        selectedNotes.remove(note.id)
                    } else {
                        selectedNotes.insert(note.id)
                    }
                } else {
                    selectedNotes = [note.id]
                }
                onPreviewNote?(note.pitch)
            } else {
                selectedNotes.removeAll()
            }
            
        case .draw:
            guard midiTracks.isEmpty else { return } // Only editable in single-track mode
            let pitch = mapper.pitchAtY(location.y)
            let beat = mapper.beatAtX(location.x)
            let newNote = MIDINote(
                pitch: pitch,
                velocity: 80,
                startBeat: beat,
                durationBeats: currentDuration.rawValue
            )
            region.notes.append(newNote)
            onPreviewNote?(pitch)
            quantizeAllTracks()
            
        case .erase:
            guard midiTracks.isEmpty else { return }
            if let note = mapper.findNote(at: location, in: trackMeasureArray) {
                region.notes.removeAll { $0.id == note.midiNoteId }
                quantizeAllTracks()
            }
        }
    }
    
    // MARK: - Quantization
    
    private func quantizeMIDI() {
        let quantizer = NotationQuantizer()
        measures = quantizer.quantize(
            notes: region.notes,
            timeSignature: configuration.timeSignature,
            tempo: configuration.tempo,
            keySignature: configuration.keySignature
        )
    }
}

// MARK: - Score Entry Mode

enum ScoreEntryMode: String, CaseIterable {
    case select
    case draw
    case erase
    
    var displayName: String {
        switch self {
        case .select: return "Select"
        case .draw: return "Draw"
        case .erase: return "Erase"
        }
    }
    
    var icon: String {
        switch self {
        case .select: return "arrow.up.left.and.arrow.down.right"
        case .draw: return "pencil"
        case .erase: return "eraser"
        }
    }
    
    var shortcut: String {
        switch self {
        case .select: return "V"
        case .draw: return "P"
        case .erase: return "E"
        }
    }
}

// MARK: - Score Tool Selector

/// Icon-only tool selector matching Piano Roll style
private struct ScoreToolSelector: View {
    @Binding var selection: ScoreEntryMode
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(ScoreEntryMode.allCases, id: \.self) { mode in
                ScoreToolButton(
                    mode: mode,
                    isSelected: selection == mode,
                    action: { selection = mode }
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

/// Individual tool button with icon and hover state (matches Piano Roll's ToolButton)
private struct ScoreToolButton: View {
    let mode: ScoreEntryMode
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: mode.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: 26, height: 22)
                .background(backgroundColor)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("\(mode.displayName) (\(mode.shortcut))")
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if isHovered {
            return .primary
        } else {
            return .secondary
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isHovered {
            return Color(nsColor: .controlBackgroundColor)
        } else {
            return Color.clear
        }
    }
}

// MARK: - MIDI Editor Mode

/// Toggle between Piano Roll and Score notation view
enum MIDIEditorMode: String, CaseIterable {
    case pianoRoll
    case score
    
    var displayName: String {
        switch self {
        case .pianoRoll: return "Piano Roll"
        case .score: return "Score"
        }
    }
    
    var iconName: String {
        switch self {
        case .pianoRoll: return "pianokeys"
        case .score: return "music.note.list"
        }
    }
}

// MARK: - Isolated Score Playhead (Performance Optimization)
// Uses @Observable AudioEngine for fine-grained updates
// Only this view re-renders when currentPosition changes, not the parent score

private struct ScorePlayhead: View {
    @Environment(AudioEngine.self) private var audioEngine
    let contentStartX: CGFloat
    let scaledMeasureWidth: CGFloat
    let measureDuration: Double
    let height: CGFloat
    
    var body: some View {
        let currentBeat = audioEngine.currentPosition.beats
        let measurePosition = currentBeat / measureDuration
        let x = contentStartX + CGFloat(measurePosition) * scaledMeasureWidth
        
        Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: height)
            .offset(x: x - 1)
            .allowsHitTesting(false)
    }
}
