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
    
    // Track view size for accurate tap detection
    @State private var viewSize: CGSize = .zero
    
    // For preview/playback - PERF: Uses isolated ScorePlayhead component
    var onPreviewNote: ((UInt8) -> Void)?
    var tempo: Double = 120.0
    
    // Cycle region (synced with main timeline)
    var cycleEnabled: Bool = false
    var cycleStartBeat: Double = 0
    var cycleEndBeat: Double = 4
    
    // Layout constants
    let measureWidth: CGFloat = 200
    let rulerHeight: CGFloat = 30
    let staffRowHeight: CGFloat = 120  // Height per staff row (enough for ledger lines and stems)
    let trackLabelWidth: CGFloat = 100  // Width for track labels on left
    
    private let renderer = StaffRenderer()
    
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
                let scaledMeasureWidth = measureWidth * horizontalZoom
                let contentStartX: CGFloat = trackLabelWidth + 60  // Track label + clef/sig area
                let maxMeasures = scoreTracks.compactMap { $0.region?.notes.map { $0.endBeat }.max() }.max().map { Int(ceil($0 / configuration.timeSignature.measureDuration)) } ?? 4
                let totalWidth = max(geometry.size.width, CGFloat(max(4, maxMeasures)) * scaledMeasureWidth + contentStartX + 50)
                let totalStaffHeight = CGFloat(max(1, scoreTracks.count)) * staffRowHeight
                
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: - Ruler with Cycle Region (fixed at top)
                        HStack(spacing: 0) {
                            // Empty space for track labels column
                            Rectangle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .frame(width: trackLabelWidth, height: rulerHeight)
                            
                            ZStack(alignment: .topLeading) {
                                // Ruler background
                                Rectangle()
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                
                                // Cycle region overlay
                                if cycleEnabled {
                                    scoreCycleOverlay(contentStartX: 60, scaledMeasureWidth: scaledMeasureWidth)
                                }
                                
                                // Measure ruler (contentStartX is relative to this view, so use 60)
                                scoreRuler(contentStartX: 60, scaledMeasureWidth: scaledMeasureWidth, totalWidth: totalWidth - trackLabelWidth)
                                
                                // Playhead in ruler
                                ScorePlayhead(
                                    contentStartX: 60,
                                    scaledMeasureWidth: scaledMeasureWidth,
                                    measureDuration: configuration.timeSignature.measureDuration,
                                    height: rulerHeight
                                )
                            }
                            .frame(width: totalWidth - trackLabelWidth, height: rulerHeight)
                        }
                        
                        Divider()
                        
                        // MARK: - Multi-Track Staff Rows
                        ForEach(scoreTracks) { trackData in
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
                                .frame(width: trackLabelWidth - 8, alignment: .leading)
                                .padding(.horizontal, 4)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                                
                                // Staff content for this track
                                ZStack(alignment: .topLeading) {
                                    staffRowContent(for: trackData, scaledMeasureWidth: scaledMeasureWidth, totalWidth: totalWidth - trackLabelWidth)
                                    
                                    // Playhead in staff
                                    ScorePlayhead(
                                        contentStartX: 60,
                                        scaledMeasureWidth: scaledMeasureWidth,
                                        measureDuration: configuration.timeSignature.measureDuration,
                                        height: staffRowHeight
                                    )
                                }
                                .frame(width: totalWidth - trackLabelWidth, height: staffRowHeight)
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
                    viewSize = geometry.size
                    quantizeAllTracks()
                }
                .onChange(of: geometry.size) { _, newSize in
                    viewSize = newSize
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            quantizeAllTracks()
        }
        .onChange(of: region.notes) { _, _ in
            quantizeAllTracks()
        }
    }
    
    // MARK: - Staff Row Content (per track)
    
    private func staffRowContent(for trackData: ScoreTrackData, scaledMeasureWidth: CGFloat, totalWidth: CGFloat) -> some View {
        let trackMeasures = self.trackMeasures[trackData.id] ?? []
        
        return Canvas { context, size in
            var currentX: CGFloat = 10
            let yOffset: CGFloat = 30  // Top padding within row (centers staff in 120pt row)
            
            // Draw clef
            renderer.drawClef(
                context: context,
                clef: trackData.clef,
                x: currentX,
                yOffset: yOffset
            )
            currentX += 35
            
            // Draw time signature (only on first visible measure concept)
            currentX = renderer.drawTimeSignature(
                context: context,
                timeSignature: configuration.timeSignature,
                x: currentX,
                yOffset: yOffset
            )
            currentX += 10
            
            let contentStartX = currentX
            
            // Draw staff lines
            renderer.drawStaffLines(
                context: context,
                width: totalWidth,
                yOffset: yOffset
            )
            
            // Draw measures with notes
            for (measureIndex, measure) in trackMeasures.enumerated() {
                let measureStartX = contentStartX + CGFloat(measureIndex) * scaledMeasureWidth
                
                // Bar line
                if measureIndex > 0 {
                    renderer.drawBarLine(context: context, x: measureStartX, yOffset: yOffset)
                }
                
                // Draw notes
                for note in measure.notes {
                    let noteBeatInMeasure = note.startBeat - Double(measureIndex) * configuration.timeSignature.measureDuration
                    let noteX = measureStartX + 15 + CGFloat(noteBeatInMeasure / configuration.timeSignature.measureDuration) * (scaledMeasureWidth - 30)
                    
                    let isSelected = selectedNotes.contains(note.id)
                    renderer.drawNote(
                        context: context,
                        note: note,
                        x: noteX,
                        clef: trackData.clef,
                        yOffset: yOffset,
                        isSelected: isSelected
                    )
                }
            }
            
            // Final bar line
            if !trackMeasures.isEmpty {
                let finalX = contentStartX + CGFloat(trackMeasures.count) * scaledMeasureWidth
                renderer.drawBarLine(context: context, x: finalX, yOffset: yOffset, style: .final)
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
        .frame(width: totalWidth, height: rulerHeight)
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
            .frame(width: max(0, cycleWidth), height: rulerHeight - 10)
            .offset(x: cycleStartX, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.yellow.opacity(0.6), lineWidth: 1)
                    .frame(width: max(0, cycleWidth), height: rulerHeight - 10)
                    .offset(x: cycleStartX, y: 2)
            )
    }
    
    // MARK: - Toolbar
    
    private var scoreToolbar: some View {
        HStack(spacing: 12) {
            // Entry mode selector (no label to prevent text wrapping)
            Picker("", selection: $entryMode) {
                ForEach(ScoreEntryMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 180)
            
            Divider().frame(height: 20)
            
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
                HStack(spacing: 4) {
                    Image(systemName: configuration.clef.iconName)
                    Text(configuration.clef.displayName.components(separatedBy: " ").first ?? "")
                }
            }
            
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
            }
            
            // Time signature selector
            Menu {
                Button("4/4 (Common)") { configuration.timeSignature = .common }
                Button("3/4 (Waltz)") { configuration.timeSignature = .waltz }
                Button("2/4 (March)") { configuration.timeSignature = .march }
                Button("6/8") { configuration.timeSignature = .compound6 }
                Button("2/2 (Cut)") { configuration.timeSignature = .cut }
            } label: {
                Text(configuration.timeSignature.displayString)
                    .font(.system(.body, design: .serif))
            }
            
            Divider().frame(height: 20)
            
            // Duration palette (when in draw mode)
            if entryMode == .draw {
                durationPalette
            }
            
            // Transform menu (when notes are selected)
            if !selectedNotes.isEmpty {
                Divider().frame(height: 20)
                transformMenu
            }
            
            Spacer()
            
            // Zoom controls
            HStack(spacing: 4) {
                Button(action: { horizontalZoom = max(0.5, horizontalZoom - 0.25) }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                
                Text("\(Int(horizontalZoom * 100))%")
                    .frame(width: 50)
                    .font(.caption)
                
                Button(action: { horizontalZoom = min(2.0, horizontalZoom + 0.25) }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)
            }
            
            Divider().frame(height: 20)
            
            // Export menu
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
            }
            .help("Export or Print")
            
            Divider().frame(height: 20)
            
            // Refresh button
            Button(action: quantizeMIDI) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Re-quantize from MIDI")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
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
    
    // MARK: - Score Content
    
    private var scoreContent: some View {
        let scaledMeasureWidth = measureWidth * horizontalZoom
        let staffHeight = renderer.staffHeight
        let totalWidth = max(800, CGFloat(max(1, measures.count)) * scaledMeasureWidth + 150)
        let totalHeight = staffHeight + 60  // Compact: staff + padding
        
        return Canvas { context, size in
            var currentX: CGFloat = 40
            // Position staff at top with fixed padding (not centered)
            let yOffset: CGFloat = 30  // Fixed top padding
            
            // Draw initial clef
            renderer.drawClef(
                context: context,
                clef: configuration.clef,
                x: currentX,
                yOffset: yOffset
            )
            currentX += 40
            
            // Draw key signature
            currentX = renderer.drawKeySignature(
                context: context,
                keySignature: configuration.keySignature,
                clef: configuration.clef,
                x: currentX,
                yOffset: yOffset
            )
            
            // Draw time signature
            currentX = renderer.drawTimeSignature(
                context: context,
                timeSignature: configuration.timeSignature,
                x: currentX + 10,
                yOffset: yOffset
            )
            currentX += 20
            
            let contentStartX = currentX
            
            // Draw staff lines across entire width
            renderer.drawStaffLines(
                context: context,
                width: totalWidth,
                yOffset: yOffset
            )
            
            // Draw measures
            for (measureIndex, measure) in measures.enumerated() {
                let measureStartX = contentStartX + CGFloat(measureIndex) * scaledMeasureWidth
                
                // Draw measure number above staff (every measure, or every 4 if zoomed out)
                let showEveryMeasure = scaledMeasureWidth > 80
                let showNumber = showEveryMeasure || (measureIndex % 4 == 0) || measureIndex == 0
                
                if showNumber {
                    let measureNumberText = Text("\(measureIndex + 1)")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    context.draw(
                        measureNumberText,
                        at: CGPoint(x: measureStartX + 4, y: yOffset - 12),
                        anchor: .bottomLeading
                    )
                }
                
                // Draw bar line at start of measure (except first)
                if measureIndex > 0 {
                    renderer.drawBarLine(
                        context: context,
                        x: measureStartX,
                        yOffset: yOffset,
                        style: measure.repeatStart ? .repeatStart : .single
                    )
                }
                
                // Calculate note positions within measure
                let noteSpacing = scaledMeasureWidth / CGFloat(max(1, measure.notes.count + 1))
                
                // Draw rests
                for (restIndex, rest) in measure.rests.enumerated() {
                    let restBeatInMeasure = rest.startBeat - Double(measureIndex) * configuration.timeSignature.measureDuration
                    let restX = measureStartX + 20 + CGFloat(restBeatInMeasure / configuration.timeSignature.measureDuration) * (scaledMeasureWidth - 40)
                    
                    renderer.drawRest(
                        context: context,
                        rest: rest,
                        x: restX,
                        yOffset: yOffset
                    )
                }
                
                // Group notes by beam group
                var beamGroups: [UUID: [ScoreNote]] = [:]
                var unbeamedNotes: [ScoreNote] = []
                
                for note in measure.notes {
                    if let groupId = note.beamGroupId {
                        beamGroups[groupId, default: []].append(note)
                    } else {
                        unbeamedNotes.append(note)
                    }
                }
                
                // Draw beamed groups
                for (_, groupNotes) in beamGroups {
                    let sortedNotes = groupNotes.sorted { $0.startBeat < $1.startBeat }
                    
                    renderer.drawBeam(
                        context: context,
                        notes: sortedNotes,
                        clef: configuration.clef,
                        getXPosition: { note in
                            let noteBeatInMeasure = note.startBeat - Double(measureIndex) * configuration.timeSignature.measureDuration
                            return measureStartX + 20 + CGFloat(noteBeatInMeasure / configuration.timeSignature.measureDuration) * (scaledMeasureWidth - 40)
                        },
                        yOffset: yOffset
                    )
                    
                    // Draw noteheads (without stems, as beam drawing handles them)
                    for note in sortedNotes {
                        let noteBeatInMeasure = note.startBeat - Double(measureIndex) * configuration.timeSignature.measureDuration
                        let noteX = measureStartX + 20 + CGFloat(noteBeatInMeasure / configuration.timeSignature.measureDuration) * (scaledMeasureWidth - 40)
                        
                        // Draw just the notehead
                        let staffPosition = note.pitch.staffPosition(for: configuration.clef)
                        let noteY = yOffset + renderer.staffHeight - (CGFloat(staffPosition) * renderer.staffLineSpacing / 2)
                        
                        let isSelected = selectedNotes.contains(note.id)
                        let color = isSelected ? renderer.selectedNoteColor : renderer.noteColor
                        
                        let rect = CGRect(
                            x: noteX - renderer.noteheadWidth / 2,
                            y: noteY - renderer.noteheadHeight / 2,
                            width: renderer.noteheadWidth,
                            height: renderer.noteheadHeight
                        )
                        let notePath = Path(ellipseIn: rect)
                        context.fill(notePath, with: .color(color))
                    }
                }
                
                // Draw unbeamed notes
                for note in unbeamedNotes {
                    let noteBeatInMeasure = note.startBeat - Double(measureIndex) * configuration.timeSignature.measureDuration
                    let noteX = measureStartX + 20 + CGFloat(noteBeatInMeasure / configuration.timeSignature.measureDuration) * (scaledMeasureWidth - 40)
                    
                    let isSelected = selectedNotes.contains(note.id)
                    
                    renderer.drawNote(
                        context: context,
                        note: note,
                        x: noteX,
                        clef: configuration.clef,
                        yOffset: yOffset,
                        isSelected: isSelected
                    )
                }
                
                // Draw measure number (show for every measure)
                if configuration.showMeasureNumbers {
                    let measureNumText = Text("\(measure.measureNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    context.draw(
                        measureNumText,
                        at: CGPoint(x: measureStartX + 5, y: yOffset - 15),
                        anchor: .bottomLeading
                    )
                }
            }
            
            // Draw final bar line
            if !measures.isEmpty {
                let finalX = contentStartX + CGFloat(measures.count) * scaledMeasureWidth
                renderer.drawBarLine(
                    context: context,
                    x: finalX,
                    yOffset: yOffset,
                    style: .final
                )
            }
            
            // PERF: Playhead is now drawn by isolated ScorePlayhead component
            // that observes AudioEngine directly, preventing full score redraws
        }
        .drawingGroup()  // PERF: Rasterize score rendering to prevent redraws
        .frame(
            minWidth: totalWidth,
            minHeight: totalHeight
        )
        .contentShape(Rectangle())
        .gesture(tapGesture)
    }
    
    // MARK: - Gestures
    
    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                handleTap(at: value.location)
            }
    }
    
    private func handleTap(at location: CGPoint) {
        switch entryMode {
        case .select:
            // Find note at location and select it
            if let note = findNote(at: location, in: viewSize) {
                // Check if Shift key is held for multi-select
                let shiftHeld = NSEvent.modifierFlags.contains(.shift)
                
                if shiftHeld {
                    // Shift+click: toggle note in selection
                    if selectedNotes.contains(note.id) {
                        selectedNotes.remove(note.id)
                    } else {
                        selectedNotes.insert(note.id)
                    }
                } else {
                    // Regular click: clear selection and select only this note
                    selectedNotes.removeAll()
                    selectedNotes.insert(note.id)
                }
                
                // Preview the note
                onPreviewNote?(note.pitch)
            } else {
                // Clicked on empty space: clear selection
                selectedNotes.removeAll()
            }
            
        case .draw:
            // Add note at location
            addNote(at: location, in: viewSize)
            
        case .erase:
            // Delete note at location
            if let note = findNote(at: location, in: viewSize) {
                deleteNote(note)
            }
        }
    }
    
    // MARK: - Note Operations
    
    private func findNote(at location: CGPoint, in size: CGSize? = nil) -> ScoreNote? {
        let scaledMeasureWidth = measureWidth * horizontalZoom
        
        // Calculate yOffset to match Canvas rendering (centered vertically)
        let staffHeight = renderer.staffHeight
        let viewHeight = size?.height ?? 300
        let yOffset = max(40, (viewHeight - staffHeight) / 2 - 20)
        
        // Calculate contentStartX EXACTLY as in rendering
        var currentX: CGFloat = 40 // Initial X
        currentX += 40 // Clef width
        
        // Key signature width (depends on number of accidentals)
        let accidentalCount = abs(configuration.keySignature.sharps)
        if accidentalCount > 0 {
            currentX += CGFloat(accidentalCount) * renderer.staffLineSpacing * 1.2
            currentX += renderer.staffLineSpacing // Return spacing from drawKeySignature
        }
        
        currentX += 10 // Space before time signature
        currentX += renderer.staffLineSpacing * 2 // Time signature width (from drawTimeSignature)
        currentX += 20 // Final spacing
        
        let contentStartX = currentX
        
        for measure in measures {
            for note in measure.notes {
                let measureIndex = measure.measureNumber - 1
                let measureStartX = contentStartX + CGFloat(measureIndex) * scaledMeasureWidth
                let noteBeatInMeasure = note.startBeat - Double(measureIndex) * configuration.timeSignature.measureDuration
                let noteX = measureStartX + 20 + CGFloat(noteBeatInMeasure / configuration.timeSignature.measureDuration) * (scaledMeasureWidth - 40)
                
                let staffPosition = note.pitch.staffPosition(for: configuration.clef)
                // Calculate noteY using the same formula as rendering
                let noteY = yOffset + staffHeight - (CGFloat(staffPosition) * renderer.staffLineSpacing / 2)
                
                // Check if tap is near this note (increased hit area for easier selection)
                let distance = hypot(location.x - noteX, location.y - noteY)
                if distance < 20 {
                    return note
                }
            }
        }
        
        return nil
    }
    
    private func addNote(at location: CGPoint, in size: CGSize? = nil) {
        let scaledMeasureWidth = measureWidth * horizontalZoom
        
        // Calculate yOffset to match Canvas rendering
        let staffHeight = renderer.staffHeight
        let viewHeight = size?.height ?? 300
        let yOffset = max(40, (viewHeight - staffHeight) / 2 - 20)
        
        // Calculate contentStartX EXACTLY as in rendering
        var currentX: CGFloat = 40 // Initial X
        currentX += 40 // Clef width
        
        // Key signature width (depends on number of accidentals)
        let accidentalCount = abs(configuration.keySignature.sharps)
        if accidentalCount > 0 {
            currentX += CGFloat(accidentalCount) * renderer.staffLineSpacing * 1.2
            currentX += renderer.staffLineSpacing // Return spacing from drawKeySignature
        }
        
        currentX += 10 // Space before time signature
        currentX += renderer.staffLineSpacing * 2 // Time signature width (from drawTimeSignature)
        currentX += 20 // Final spacing
        
        let contentStartX = currentX
        
        // Calculate pitch from Y position (relative to the staff)
        // Inverse of: noteY = yOffset + staffHeight - (staffPosition * staffLineSpacing / 2)
        // Note: Subtract 2 to correct for coordinate system offset between rendering and click detection
        let rawStaffPosition = Int(round((yOffset + staffHeight - location.y) / (renderer.staffLineSpacing / 2)))
        let staffPosition = rawStaffPosition - 2
        let pitch = pitchFromStaffPosition(staffPosition, clef: configuration.clef)
        
        // Calculate beat from X position
        let measureFloat = (location.x - contentStartX) / scaledMeasureWidth
        let measureIndex = max(0, Int(measureFloat))
        let beatInMeasure = (measureFloat - Double(measureIndex)) * configuration.timeSignature.measureDuration
        let totalBeat = Double(measureIndex) * configuration.timeSignature.measureDuration + beatInMeasure
        
        // Create MIDI note
        // Note: MIDI note startBeat and durationBeats are stored in BEATS, not seconds!
        let newNote = MIDINote(
            pitch: pitch,
            velocity: 80,
            startBeat: totalBeat,
            durationBeats: currentDuration.rawValue
        )
        
        region.notes.append(newNote)
        onPreviewNote?(pitch)
    }
    
    private func deleteNote(_ scoreNote: ScoreNote) {
        region.notes.removeAll { $0.id == scoreNote.midiNoteId }
    }
    
    private func pitchFromStaffPosition(_ position: Int, clef: Clef) -> UInt8 {
        // Exact inverse of UInt8.staffPosition(for:) in ScoreModels.swift
        
        // Remove clef offset first
        let clefOffset: Int
        switch clef {
        case .treble:
            clefOffset = -6  // Middle C is one ledger line below treble staff
        case .bass:
            clefOffset = 6   // Middle C is one ledger line above bass staff
        case .alto:
            clefOffset = 0   // Middle C is on the middle line
        case .tenor:
            clefOffset = 2   // Middle C is on the fourth line
        case .percussion:
            return 60  // Default for percussion
        }
        
        let positionWithoutClef = position - clefOffset
        
        // Calculate octave and note offset
        let octaveOffset = positionWithoutClef / 7
        let noteOffset = ((positionWithoutClef % 7) + 7) % 7  // Handle negative modulo
        
        // Convert octave offset back to actual octave
        let middleCOctave = 4
        let octave = middleCOctave + octaveOffset
        
        // Map noteOffset to semitones: C=0, D=2, E=4, F=5, G=7, A=9, B=11
        let noteToSemitone = [0, 2, 4, 5, 7, 9, 11]
        let semitone = noteToSemitone[noteOffset]
        
        // Calculate MIDI pitch
        let pitch = (octave + 1) * 12 + semitone
        
        return UInt8(max(0, min(127, pitch)))
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
            .fill(Color.green)
            .frame(width: 2, height: height)
            .offset(x: x - 1)
            .allowsHitTesting(false)
    }
}
