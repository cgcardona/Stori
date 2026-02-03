//
//  StepSequencerView.swift
//  Stori
//
//  Main Step Sequencer interface with 16-step grid
//

import SwiftUI
import AVFoundation

// MARK: - Sequencer Color Scheme

/// Adaptive colors for the step sequencer that respect system appearance
struct SequencerColors {
    @Environment(\.colorScheme) static var colorScheme
    
    // Backgrounds
    static var background: Color { Color(nsColor: .windowBackgroundColor) }
    static var controlBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var gridBackground: Color { Color(nsColor: .textBackgroundColor) }
    
    // Surfaces (slightly elevated)
    static var surface: Color { Color(nsColor: .controlBackgroundColor) }
    static var surfaceElevated: Color { Color(nsColor: .unemphasizedSelectedContentBackgroundColor) }
    
    // Borders & Separators
    static var separator: Color { Color(nsColor: .separatorColor) }
    static var border: Color { Color(nsColor: .separatorColor).opacity(0.5) }
    
    // Text
    static var textPrimary: Color { .primary }
    static var textSecondary: Color { .secondary }
    static var textTertiary: Color { Color(nsColor: .tertiaryLabelColor) }
    
    // Interactive elements
    static var buttonBackground: Color { Color(nsColor: .controlColor) }
    static var buttonBackgroundHover: Color { Color(nsColor: .selectedControlColor) }
}

// MARK: - Step Sequencer View

struct StepSequencerView: View {
    @Bindable var sequencer: SequencerEngine
    var projectManager: ProjectManager
    var audioEngine: AudioEngine
    @Binding var selectedTrackId: UUID?
    
    // UI State
    @State private var showingSettings = false
    @State private var showingPresets = false
    @State private var showingKitSelector = false
    @State private var syncWithTransport = false
    @State private var isExporting = false
    @State private var showingExportSuccess = false
    @State private var exportedFileName: String = ""
    @State private var lastExportWasMIDI = false
    
    init(sequencer: SequencerEngine, projectManager: ProjectManager, audioEngine: AudioEngine, selectedTrackId: Binding<UUID?> = .constant(nil)) {
        self.sequencer = sequencer
        self.projectManager = projectManager
        self.audioEngine = audioEngine
        self._selectedTrackId = selectedTrackId
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            SequencerToolbar(
                sequencer: sequencer,
                audioEngine: audioEngine,
                projectManager: projectManager,
                syncWithTransport: $syncWithTransport,
                isExporting: $isExporting,
                showingSettings: $showingSettings,
                showingPresets: $showingPresets,
                showingKitSelector: $showingKitSelector,
                onExport: handleExport,
                onExportMIDI: handleExportMIDI,
                onExportMIDIToTrack: handleExportMIDIToTrack
            )
            
            // Main Grid Area - Geometry-based to maximize screen real estate
            GeometryReader { geometry in
                let laneHeaderWidth: CGFloat = 120
                let gridWidth = geometry.size.width - laneHeaderWidth
                let headerHeight: CGFloat = 28
                let gridHeight = geometry.size.height - headerHeight
                let laneCount = CGFloat(sequencer.pattern.lanes.count)
                // Calculate row height to fit all 16 lanes, min 28px, max 40px
                let rowHeight = min(40, max(28, gridHeight / laneCount))
                
                HStack(spacing: 0) {
                    // Lane Headers (left side) - Compact design
                    CompactLaneHeaderColumn(
                        sequencer: sequencer,
                        rowHeight: rowHeight,
                        headerHeight: headerHeight
                    )
                    .frame(width: laneHeaderWidth)
                    
                    // Step Grid - Fills available space
                    AdaptiveStepGridView(
                        sequencer: sequencer,
                        availableWidth: gridWidth,
                        rowHeight: rowHeight,
                        headerHeight: headerHeight
                    )
                }
            }
        }
        .background(SequencerColors.background)
        .onAppear {
            // Sync initial tempo from project
            if let tempo = projectManager.currentProject?.tempo {
                sequencer.setTempo(tempo)
            }
        }
        .onChange(of: projectManager.currentProject?.tempo) { _, newTempo in
            if let tempo = newTempo {
                sequencer.setTempo(tempo)
            }
        }
        // Sync with DAW transport
        .onChange(of: audioEngine.transportState) { _, newState in
            guard syncWithTransport else { return }
            switch newState {
            case .playing:
                if !sequencer.isPlaying {
                    sequencer.reset()
                    sequencer.play()
                }
            case .stopped:
                sequencer.stop()
            case .paused:
                sequencer.pause()
            case .recording:
                // Treat recording like playing for the sequencer
                if !sequencer.isPlaying {
                    sequencer.reset()
                    sequencer.play()
                }
            }
        }
        .sheet(isPresented: $showingPresets) {
            PresetsView(sequencer: sequencer)
        }
        .sheet(isPresented: $showingKitSelector) {
            KitSelectorView(sequencer: sequencer)
        }
         .alert(lastExportWasMIDI ? "MIDI Exported!" : "Pattern Exported!", isPresented: $showingExportSuccess) {
            Button("OK", role: .cancel) { }
        } message: {
            if lastExportWasMIDI {
                Text("'\(exportedFileName)' has been saved.")
            } else {
                Text("'\(exportedFileName)' has been added to the selected track.")
            }
        }
        // Keyboard shortcuts
        .background(
            SequencerKeyboardHandler(
                sequencer: sequencer,
                onPlayPause: {
                    if sequencer.isPlaying {
                        sequencer.pause()
                    } else {
                        sequencer.play()
                    }
                },
                onStop: { sequencer.stop() },
                onClear: { sequencer.clearPattern() }
            )
        )
    }
    
    // MARK: - Export Handler
    
    private func handleExport() {
        guard let project = projectManager.currentProject,
              !project.tracks.isEmpty else {
            return
        }
        
        isExporting = true
        lastExportWasMIDI = false
        
        // CRITICAL: Ensure sequencer tempo matches project tempo before export
        // This ensures the exported audio has the correct timing for the project's grid
        if sequencer.pattern.tempo != project.tempo {
            sequencer.setTempo(project.tempo)
        }
        
        // Export async to avoid UI freeze
        Task {
            if let audioURL = sequencer.exportToAudio(loops: 1) {
                // Determine target track: selected audio track or first audio track
                // Step sequencer exports are audio, so they should only go to audio tracks
                let trackId: UUID
                let trackName: String
                let trackRegions: [AudioRegion]
                
                if let selectedId = selectedTrackId,
                   let selected = project.tracks.first(where: { $0.id == selectedId && $0.isAudioTrack }) {
                    // Use selected track if it's an audio track
                    trackId = selectedId
                    trackName = selected.name
                    trackRegions = selected.regions
                } else if let firstAudioTrack = project.tracks.first(where: { $0.isAudioTrack }) {
                    // Fall back to first audio track
                    trackId = firstAudioTrack.id
                    trackName = firstAudioTrack.name
                    trackRegions = firstAudioTrack.regions
                } else {
                    // No audio tracks available - cannot export
                    isExporting = false
                    return
                }
                
                // Determine insert position: playhead if at a valid position, otherwise end of track
                let playheadBeat = audioEngine.currentPosition.beats
                let tempo = project.tempo
                
                // Find end of last region in beats
                let lastRegionEndBeat = trackRegions.map { region in
                    region.endBeat
                }.max() ?? 0
                
                // All comparisons in beats
                let insertPosition: Double
                if playheadBeat > 0.1 {
                    // Insert at playhead position (in beats)
                    insertPosition = playheadBeat
                } else {
                    // Insert at end of track (in beats)
                    insertPosition = lastRegionEndBeat
                }
                
                // Get the ACTUAL duration from the exported audio file
                let actualDuration: TimeInterval
                do {
                    // SECURITY (H-1, H-4): Validate header and size before loading
                    guard AudioFileHeaderValidator.validateHeader(at: audioURL) else {
                        isExporting = false
                        return
                    }
                    let fileSizeBytes = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0
                    guard fileSizeBytes > 0, fileSizeBytes <= AudioEngine.maxAudioImportFileSize else {
                        isExporting = false
                        return
                    }
                    let audioFile = try AVAudioFile(forReading: audioURL)
                    let frameCount = audioFile.length
                    let sampleRate = audioFile.fileFormat.sampleRate
                    actualDuration = Double(frameCount) / sampleRate
                } catch {
                    // Fallback to calculated duration
                    let numberOfBeats = Double(sequencer.pattern.steps) / 4.0
                    actualDuration = (60.0 / project.tempo) * numberOfBeats * 4
                }

                // File size (already validated above if we loaded; otherwise read for metadata)
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: audioURL.path)[.size] as? Int64) ?? 0

                // Create an AudioFile from the exported URL
                let audioFile = AudioFile(
                    name: sequencer.pattern.name,
                    url: audioURL,
                    duration: actualDuration,  // Use actual audio file duration
                    sampleRate: 48000,
                    channels: 2,
                    bitDepth: 16,
                    fileSize: fileSize,
                    format: .wav
                )
                
                // Create the AudioRegion with step sequencer metadata
                // insertPosition is already in beats
                let durationBeats = actualDuration * (tempo / 60.0)
                var region = AudioRegion(
                    audioFile: audioFile,
                    startBeat: insertPosition,
                    durationBeats: durationBeats,
                    tempo: tempo
                )
                
                // Add step sequencer metadata for visualization
                region.stepSequencerMetadata = StepSequencerMetadata(
                    pattern: sequencer.currentPatternGrid(), 
                    tempo: project.tempo,
                    kitName: sequencer.currentKitName
                )
                
                // Add to track
                projectManager.addRegionToTrack(region, trackId: trackId)
                
                // 📊 LOGGING: Step Sequencer Export
                
                // CRITICAL FIX: Reload audio engine so it includes the new region!
                if let updatedProject = projectManager.currentProject {
                    audioEngine.loadProject(updatedProject)
                }
                
                exportedFileName = "\(sequencer.pattern.name)"
                showingExportSuccess = true
            }
            
            isExporting = false
        }
    }
    
    // MARK: - MIDI Export Handler
    
    private func handleExportMIDI() {
        isExporting = true
        lastExportWasMIDI = true
        
        Task {
            if let midiURL = sequencer.exportToMIDI(loops: 1) {
                // Show save panel to let user choose location
                await MainActor.run {
                    let savePanel = NSSavePanel()
                    savePanel.allowedContentTypes = [.midi]
                    savePanel.nameFieldStringValue = "\(sequencer.pattern.name).mid"
                    savePanel.title = "Export MIDI Pattern"
                    savePanel.message = "Choose a location to save the MIDI file"
                    
                    if savePanel.runModal() == .OK, let destURL = savePanel.url {
                        do {
                            // Remove existing file if present
                            if FileManager.default.fileExists(atPath: destURL.path) {
                                try FileManager.default.removeItem(at: destURL)
                            }
                            // Copy to destination
                            try FileManager.default.copyItem(at: midiURL, to: destURL)
                            
                            exportedFileName = destURL.lastPathComponent
                            showingExportSuccess = true
                        } catch {
                            // Handle error silently for now
                        }
                    }
                    
                    // Clean up temp file
                    try? FileManager.default.removeItem(at: midiURL)
                }
            }
            
            isExporting = false
        }
    }
    
    // MARK: - MIDI to Track Export Handler
    
    private func handleExportMIDIToTrack() {
        guard projectManager.currentProject != nil,
              let trackId = sequencer.targetTrackId else {
            return
        }
        
        isExporting = true
        lastExportWasMIDI = true
        
        // Generate MIDI events from pattern
        let midiEvents = sequencer.generatePatternMIDIEvents(loops: 1)
        
        // Calculate duration in beats (pattern length in 16th notes)
        let durationBeats = Double(sequencer.pattern.steps) * 0.25
        
        // Convert sequencer MIDI events to MIDINotes
        let midiNotes = midiEvents.map { event in
            MIDINote(
                id: UUID(),
                pitch: event.note,
                velocity: event.velocity,
                startBeat: event.timestamp,
                durationBeats: event.duration,
                channel: event.channel
            )
        }
        
        // Create a MIDIRegion from the pattern
        let midiRegion = MIDIRegion(
            id: UUID(),
            name: sequencer.pattern.name,
            notes: midiNotes,
            startBeat: audioEngine.currentPosition.beats,  // Start at current playhead position
            durationBeats: durationBeats,
            instrumentId: nil,
            color: .cyan,  // Use drum sequencer color
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: [],
            pitchBendEvents: [],
            contentLengthBeats: durationBeats
        )
        
        // Add the MIDI region to the target track
        projectManager.addMIDIRegion(midiRegion, to: trackId)
        
        exportedFileName = "\(sequencer.pattern.name)"
        showingExportSuccess = true
        isExporting = false
    }
}

// MARK: - Toolbar Divider

private struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 24)
    }
}

// MARK: - MIDI Routing Controls

/// Compact routing controls for the sequencer toolbar
struct SequencerRoutingControls: View {
    @Bindable var sequencer: SequencerEngine
    var audioEngine: AudioEngine
    
    /// Available MIDI tracks for routing
    private var availableTracks: [(id: UUID, name: String)] {
        audioEngine.getMIDITracksForSequencerRouting()
    }
    
    /// Selected track name (for display)
    private var selectedTrackName: String? {
        guard let trackId = sequencer.targetTrackId else { return nil }
        return availableTracks.first { $0.id == trackId }?.name
    }
    
    /// Icon and color for current routing mode
    private var routingIcon: (name: String, color: Color) {
        switch sequencer.routingMode {
        case .preview:
            return ("speaker.wave.2.fill", .cyan)
        case .singleTrack:
            return ("arrow.right.circle.fill", .green)
        case .multiTrack:
            return ("arrow.triangle.branch", .orange)
        case .external:
            return ("cable.connector", .purple)
        }
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Routing Mode Menu
            Menu {
                // Preview Mode (Internal Sounds)
                Button(action: { sequencer.setRoutingMode(.preview) }) {
                    Label {
                        VStack(alignment: .leading) {
                            Text("Preview Mode")
                            Text("Built-in drum sounds")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                }
                
                Divider()
                
                // Single Track Routing
                if !availableTracks.isEmpty {
                    Menu("Route to Track") {
                        ForEach(availableTracks, id: \.id) { track in
                            Button(action: {
                                sequencer.setTargetTrack(track.id)
                            }) {
                                HStack {
                                    Text(track.name)
                                    if sequencer.targetTrackId == track.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                } else {
                    Text("No MIDI tracks available")
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Info about current routing
                if sequencer.routingMode != .preview {
                    if let name = selectedTrackName {
                        Label("Routing to: \(name)", systemImage: "arrow.right")
                            .foregroundColor(.secondary)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: routingIcon.name)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(routingIcon.color)
                    
                    if sequencer.routingMode == .preview {
                        Text("Preview")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.primary)
                    } else if let name = selectedTrackName {
                        Text(name)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .frame(maxWidth: 60)
                    } else {
                        Text("No Track")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.orange)
                    }
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(SequencerColors.controlBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(routingIcon.color.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .menuStyle(.borderlessButton)
            .help(sequencer.routingMode == .preview ? 
                  "Preview mode - using built-in sounds" : 
                  "Routing MIDI to track")
            
            // Warning indicator if routing but no instrument
            if sequencer.routingMode != .preview {
                if let trackId = sequencer.targetTrackId,
                   !audioEngine.trackHasInstrument(trackId) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .help("Target track has no instrument loaded")
                }
            }
        }
    }
}

// MARK: - Sequencer Toolbar

struct SequencerToolbar: View {
    @Bindable var sequencer: SequencerEngine
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    @Binding var syncWithTransport: Bool
    @Binding var isExporting: Bool
    @Binding var showingSettings: Bool
    @Binding var showingPresets: Bool
    @Binding var showingKitSelector: Bool
    var onExport: () -> Void
    var onExportMIDI: () -> Void
    var onExportMIDIToTrack: () -> Void
    
    @State private var showingDuplicateNameAlert = false
    @State private var editingPatternName: String = ""
    @State private var patternNameBeforeEdit: String = ""
    
    var body: some View {
        HStack(spacing: 0) {
            // ═══════════════════════════════════════════════════════════════
            // LEFT SECTION: Transport & Timing
            // ═══════════════════════════════════════════════════════════════
            HStack(spacing: 12) {
                // Transport Controls
                HStack(spacing: 4) {
                    // Play/Pause
                    Button(action: {
                        sequencer.isPlaying ? sequencer.pause() : sequencer.play()
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(sequencer.isPlaying ?
                                    Color.orange.opacity(0.2) :
                                    Color.green.opacity(0.2))
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: sequencer.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(sequencer.isPlaying ? .orange : .green)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(syncWithTransport)
                    .opacity(syncWithTransport ? 0.5 : 1)
                    
                    // Stop
                    Button(action: { sequencer.stop() }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(SequencerColors.controlBackground)
                                .frame(width: 32, height: 32)
                            
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(syncWithTransport)
                    .opacity(syncWithTransport ? 0.5 : 1)
                    
                    // Sync
                    Button(action: { syncWithTransport.toggle() }) {
                        Image(systemName: syncWithTransport ? "link" : "link.badge.plus")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(syncWithTransport ? .blue : .secondary)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(syncWithTransport ? Color.blue.opacity(0.2) : SequencerColors.controlBackground)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(syncWithTransport ? "Synced with DAW" : "Sync with DAW")
                }
                
                ToolbarDivider()
                
                // Tempo Display (read-only, syncs with project)
                HStack(spacing: 3) {
                    Text("\(Int(sequencer.pattern.tempo))")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.primary)
                    Text("BPM")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(width: 60)
                
                // Step Counter
                HStack(spacing: 2) {
                    Text(String(format: "%02d", sequencer.currentStep + 1))
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(sequencer.isPlaying ? .green : .secondary)
                    Text("/")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.5))
                    Menu {
                        ForEach(StepPattern.stepOptions, id: \.self) { steps in
                            Button("\(steps) steps") {
                                sequencer.setPatternLength(steps)
                            }
                        }
                    } label: {
                        Text(String(format: "%02d", sequencer.pattern.steps))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                
                ToolbarDivider()
                
                // Feel Controls (Swing & Humanize)
                HStack(spacing: 16) {
                    // Swing
                    HStack(spacing: 4) {
                        Text("SWG")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(sequencer.pattern.swing > 0 ? .purple : .secondary.opacity(0.6))
                        Slider(value: Binding(
                            get: { sequencer.pattern.swing },
                            set: { sequencer.setSwing($0) }
                        ), in: 0...1)
                        .frame(width: 48)
                        .tint(.purple)
                        Text("\(Int(sequencer.pattern.swing * 100))")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                    
                    // Humanize
                    HStack(spacing: 4) {
                        Text("HUM")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(sequencer.pattern.humanizeVelocity > 0 ? .green : .secondary.opacity(0.6))
                        Slider(value: Binding(
                            get: { sequencer.pattern.humanizeVelocity },
                            set: { sequencer.setHumanizeVelocity($0) }
                        ), in: 0...1)
                        .frame(width: 48)
                        .tint(.green)
                        Text("\(Int(sequencer.pattern.humanizeVelocity * 100))")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 12)
            
            Spacer()
            
            // ═══════════════════════════════════════════════════════════════
            // CENTER SECTION: Pattern Name (Editable)
            // ═══════════════════════════════════════════════════════════════
            HStack(spacing: 8) {
                TextField("Pattern Name", text: $editingPatternName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .frame(width: 140)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(SequencerColors.controlBackground)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                    .onAppear {
                        editingPatternName = sequencer.pattern.name
                        patternNameBeforeEdit = sequencer.pattern.name
                    }
                    .onChange(of: sequencer.pattern.name) { _, newValue in
                        // Sync local state when pattern changes externally (e.g., loading preset)
                        editingPatternName = newValue
                        patternNameBeforeEdit = newValue
                    }
                    .onSubmit {
                        let trimmedName = editingPatternName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedName.isEmpty && trimmedName != patternNameBeforeEdit {
                            // Register undo and apply change
                            UndoService.shared.registerPatternNameChange(from: patternNameBeforeEdit, to: trimmedName, sequencer: sequencer)
                            sequencer.pattern.name = trimmedName
                            patternNameBeforeEdit = trimmedName
                        } else if trimmedName.isEmpty {
                            // Revert to previous name if empty
                            editingPatternName = patternNameBeforeEdit
                        }
                    }
                
                // Save
                Button(action: {
                    let result = sequencer.saveCurrentPattern()
                    if result == .duplicateName {
                        showingDuplicateNameAlert = true
                    }
                }) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.green.opacity(0.15))
                        )
                }
                .buttonStyle(.plain)
                .help("Save pattern")
                .alert("Duplicate Name", isPresented: $showingDuplicateNameAlert) {
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("A pattern with this name already exists.")
                }
            }
            
            Spacer()
            
            // ═══════════════════════════════════════════════════════════════
            // RIGHT SECTION: Kit, Presets, Export, Clear
            // ═══════════════════════════════════════════════════════════════
            HStack(spacing: 8) {
                // Kit Selector
                Button(action: { showingKitSelector = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: sequencer.kitLoader.usingSamples ? "speaker.wave.2.fill" : "waveform")
                            .font(.system(size: 10))
                            .foregroundColor(sequencer.kitLoader.usingSamples ? .cyan : .secondary)
                        Text(sequencer.kitLoader.availableKits.isEmpty ? "Download drums" : sequencer.currentKitName)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .frame(minWidth: 110, maxWidth: 140)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(SequencerColors.controlBackground)
                    )
                }
                .buttonStyle(.plain)
                .help(sequencer.kitLoader.availableKits.isEmpty ? "Download a drum kit" : "Select drum kit")
                
                // Presets
                Button(action: { showingPresets = true }) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(SequencerColors.controlBackground)
                        )
                }
                .buttonStyle(.plain)
                .help("Browse presets")
                
                ToolbarDivider()
                
                // MIDI Routing Controls
                SequencerRoutingControls(sequencer: sequencer, audioEngine: audioEngine)
                
                ToolbarDivider()
                
                // Export Menu
                Menu {
                    Button(action: onExport) {
                        Label("Export Audio to Timeline", systemImage: "waveform")
                    }
                    
                    // Export MIDI to routed track (when a track is selected)
                    if sequencer.routingMode != .preview,
                       let trackId = sequencer.targetTrackId {
                        Button(action: onExportMIDIToTrack) {
                            Label("Add MIDI Pattern to Track", systemImage: "arrow.right.doc.on.clipboard")
                        }
                    }
                    
                    Divider()
                    
                    Button(action: onExportMIDI) {
                        Label("Export MIDI File...", systemImage: "pianokeys")
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11, weight: .medium))
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.purple)
                    )
                }
                .menuStyle(.borderlessButton)
                .disabled(isExporting)
                .opacity(isExporting ? 0.5 : 1)
                .help("Export pattern")
                
                // Clear
                Button(action: { sequencer.clearPattern() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red.opacity(0.7))
                        .frame(width: 32, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(SequencerColors.controlBackground)
                        )
                }
                .buttonStyle(.plain)
                .help("Clear pattern")
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 48)
        .background(SequencerColors.controlBackground)
    }
}

// MARK: - Lane Header Column

struct LaneHeaderColumn: View {
    @Bindable var sequencer: SequencerEngine
    
    private let rowHeight: CGFloat = 44
    
    var body: some View {
        VStack(spacing: 0) {
            // Header row (matches step grid header)
            HStack {
                Text("DRUMS")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(SequencerColors.controlBackground)
            
            // Lane headers
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(sequencer.pattern.lanes) { lane in
                        LaneHeaderRow(
                            lane: lane,
                            rowHeight: rowHeight,
                            onMuteToggle: { sequencer.toggleMute(laneId: lane.id) },
                            onSoloToggle: { sequencer.toggleSolo(laneId: lane.id) },
                            onPreview: { sequencer.previewSound(lane.soundType) }
                        )
                    }
                }
            }
        }
        .background(SequencerColors.background)
    }
}

// MARK: - Lane Header Row

struct LaneHeaderRow: View {
    let lane: SequencerLane
    let rowHeight: CGFloat
    let onMuteToggle: () -> Void
    let onSoloToggle: () -> Void
    let onPreview: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        HStack(spacing: 8) {
            // Color indicator with icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(
                        LinearGradient(
                            colors: [lane.soundType.color, lane.soundType.color.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .shadow(color: lane.soundType.color.opacity(0.3), radius: 4, x: 0, y: 2)
                
                Image(systemName: lane.soundType.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            // Sound name
            VStack(alignment: .leading, spacing: 2) {
                Text(lane.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(lane.soundType.rawValue.uppercased())
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
            }
            
            Spacer()
            
            // Control buttons (show on hover or if active)
            if isHovering || lane.isMuted || lane.isSolo {
                HStack(spacing: 3) {
                    // Preview button
                    ProButton(
                        icon: "speaker.wave.2.fill",
                        isActive: false,
                        activeColor: .white,
                        action: onPreview
                    )
                    .opacity(isHovering ? 1 : 0)
                    
                    // Mute button
                    ProButton(
                        label: "M",
                        isActive: lane.isMuted,
                        activeColor: .red,
                        action: onMuteToggle
                    )
                    
                    // Solo button
                    ProButton(
                        label: "S",
                        isActive: lane.isSolo,
                        activeColor: .yellow,
                        action: onSoloToggle
                    )
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .background(
            ZStack {
                // Base
                SequencerColors.surface
                
                // Hover highlight
                if isHovering {
                    Color.primary.opacity(0.03)
                }
                
                // Mute/Solo indicator
                if lane.isMuted {
                    Color.red.opacity(0.08)
                } else if lane.isSolo {
                    Color.yellow.opacity(0.08)
                }
                
                // Bottom border
                VStack {
                    Spacer()
                    SequencerColors.separator
                        .frame(height: 1)
                }
            }
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - Pro Button

struct ProButton: View {
    var icon: String? = nil
    var label: String? = nil
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isActive ? activeColor : SequencerColors.controlBackground)
                    .frame(width: 20, height: 20)
                
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(isActive ? .black : .secondary)
                } else if let label = label {
                    Text(label)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(isActive ? .black : .secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Compact Lane Header Column (16-row optimized)

struct CompactLaneHeaderColumn: View {
    @Bindable var sequencer: SequencerEngine
    let rowHeight: CGFloat
    let headerHeight: CGFloat
    
    var body: some View {
        VStack(spacing: 0) {
            // Header row (matches step grid header)
            HStack {
                Text("DRUMS")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .tracking(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: headerHeight)
            .background(SequencerColors.controlBackground)
            
            // Lane headers - scrollable to sync with grid
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(Array(sequencer.pattern.lanes.enumerated()), id: \.element.id) { index, lane in
                        CompactLaneHeaderRow(
                            lane: lane,
                            index: index,
                            rowHeight: rowHeight,
                            showExtendedLabel: index == 8,  // Show "EXTENDED" label on first extended kit lane
                            kitLoader: sequencer.kitLoader,  // Pass kit loader to check sample availability
                            onMuteToggle: { sequencer.toggleMute(laneId: lane.id) },
                            onSoloToggle: { sequencer.toggleSolo(laneId: lane.id) },
                            onPreview: { sequencer.previewSound(lane.soundType) }
                        )
                    }
                }
            }
        }
        .background(SequencerColors.background)
    }
}

// MARK: - Group Divider

// MARK: - Compact Lane Header Row (16-row optimized)

struct CompactLaneHeaderRow: View {
    let lane: SequencerLane
    let index: Int
    let rowHeight: CGFloat
    var showExtendedLabel: Bool = false  // Show "EXTENDED" overlay on this row
    let kitLoader: DrumKitLoader  // Kit loader to check sample availability
    let onMuteToggle: () -> Void
    let onSoloToggle: () -> Void
    let onPreview: () -> Void
    
    @State private var isHovering = false
    
    /// Whether this is an extended kit sound (rows 9-16)
    private var isExtendedKit: Bool {
        lane.soundType.isExtendedKit
    }
    
    /// Whether this sound has a real sample (vs. synthesized fallback)
    private var hasSample: Bool {
        kitLoader.hasSample(for: lane.soundType)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Prominent color indicator bar (full height)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: hasSample 
                            ? [lane.soundType.color, lane.soundType.color.opacity(0.7)]
                            : [Color.secondary.opacity(0.4), Color.secondary.opacity(0.2)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)
                .opacity(lane.isMuted ? 0.3 : 1.0)
            
            HStack(spacing: 4) {
                // Sound name - compact single line with kit-specific display name
                HStack(spacing: 2) {
                    // Use kit-specific display name (e.g., "Cymbal" for CR-78 instead of "Crash")
                    let displayName = kitLoader.currentKit.displayName(for: lane.soundType)
                    let shortName = String(displayName.prefix(3)).uppercased()
                    
                    Text(shortName)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(lane.isMuted ? .secondary : (hasSample ? lane.soundType.color : .secondary))
                        .strikethrough(!hasSample, color: .secondary.opacity(0.6))
                        .frame(width: 30, alignment: .leading)
                        .help(displayName)  // Show full name on hover
                    
                    // Show "N/A" badge for unavailable sounds
                    if !hasSample {
                        Text("N/A")
                            .font(.system(size: 6, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(3)
                            .help("Not available in this drum kit")
                    }
                }
                
                Spacer(minLength: 2)
                
                // Control buttons - always visible but compact
                HStack(spacing: 2) {
                    // Mute button
                    CompactButton(
                        label: "M",
                        isActive: lane.isMuted,
                        activeColor: .red,
                        size: max(16, rowHeight - 12),
                        action: onMuteToggle
                    )
                    
                    // Solo button
                    CompactButton(
                        label: "S",
                        isActive: lane.isSolo,
                        activeColor: .yellow,
                        size: max(16, rowHeight - 12),
                        action: onSoloToggle
                    )
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(height: rowHeight)
        .background(
            ZStack {
                // Base - subtle alternating background for extended kit
                if isExtendedKit {
                    SequencerColors.surface.opacity(0.5)
                } else {
                    SequencerColors.surface
                }
                
                // Hover highlight
                if isHovering {
                    Color.primary.opacity(0.03)
                }
                
                // Mute/Solo indicator
                if lane.isMuted {
                    Color.red.opacity(0.08)
                } else if lane.isSolo {
                    Color.yellow.opacity(0.08)
                }
                
                // Bottom border
                VStack {
                    Spacer()
                    SequencerColors.separator.opacity(0.5)
                        .frame(height: 0.5)
                }
            }
        )
        .overlay(alignment: .topLeading) {
            // "EXTENDED" label overlay - doesn't add height
            if showExtendedLabel {
                HStack(spacing: 4) {
                    Rectangle()
                        .fill(Color.purple)
                        .frame(width: 3, height: 1.5)
                    
                    Text("EXTENDED")
                        .font(.system(size: 6, weight: .bold, design: .rounded))
                        .foregroundColor(.purple)
                        .tracking(0.5)
                    
                    Spacer()
                }
                .padding(.leading, 8)
                .padding(.top, 2)
                .allowsHitTesting(false)  // Don't block interaction with the lane
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .onTapGesture(count: 2) {
            onPreview()
        }
    }
}

// MARK: - Compact Button

struct CompactButton: View {
    var label: String
    let isActive: Bool
    let activeColor: Color
    let size: CGFloat
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: max(8, size * 0.5), weight: .bold, design: .rounded))
                .foregroundColor(isActive ? .black : .secondary.opacity(0.6))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isActive ? activeColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Adaptive Step Grid View (fills available space)

struct AdaptiveStepGridView: View {
    @Bindable var sequencer: SequencerEngine
    let availableWidth: CGFloat
    let rowHeight: CGFloat
    let headerHeight: CGFloat
    
    /// Calculate step width to fill available space
    private var stepWidth: CGFloat {
        let steps = CGFloat(sequencer.pattern.steps)
        // Fill available width, min 32px per step
        return max(32, availableWidth / steps)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Step numbers header
            CompactStepNumbersHeader(
                steps: sequencer.pattern.steps,
                currentStep: sequencer.currentStep,
                isPlaying: sequencer.isPlaying,
                stepWidth: stepWidth,
                height: headerHeight
            )
            
            // Grid - horizontal scroll if needed, vertical scroll for 16 rows
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .leading) {
                    // Grid background with beat grouping
                    GridBackground(
                        steps: sequencer.pattern.steps,
                        stepWidth: stepWidth,
                        rowCount: sequencer.pattern.lanes.count,
                        rowHeight: rowHeight
                    )
                    
                    // Playhead column
                    if sequencer.isPlaying {
                        PlayheadColumn(
                            currentStep: sequencer.currentStep,
                            stepWidth: stepWidth,
                            totalHeight: rowHeight * CGFloat(sequencer.pattern.lanes.count)
                        )
                    }
                    
                    // Step rows
                    VStack(spacing: 0) {
                        ForEach(Array(sequencer.pattern.lanes.enumerated()), id: \.element.id) { index, lane in
                            StepRow(
                                lane: lane,
                                stepCount: sequencer.pattern.steps,
                                currentStep: sequencer.currentStep,
                                isPlaying: sequencer.isPlaying,
                                stepWidth: stepWidth,
                                stepHeight: rowHeight,
                                kitLoader: sequencer.kitLoader,  // Pass kit loader to check sample availability
                                onToggle: { step in
                                    sequencer.toggleStep(laneId: lane.id, step: step)
                                },
                                onVelocityChange: { step, delta in
                                    sequencer.adjustStepVelocity(laneId: lane.id, step: step, delta: delta)
                                },
                                onProbabilityChange: { step, delta in
                                    sequencer.adjustStepProbability(laneId: lane.id, step: step, delta: delta)
                                }
                            )
                        }
                    }
                }
            }
        }
        .background(SequencerColors.gridBackground)
    }
}

// MARK: - Compact Step Numbers Header

struct CompactStepNumbersHeader: View {
    let steps: Int
    let currentStep: Int
    let isPlaying: Bool
    let stepWidth: CGFloat
    let height: CGFloat
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(0..<steps, id: \.self) { step in
                    let isDownbeat = step % 4 == 0
                    let isCurrent = isPlaying && step == currentStep
                    let beatNumber = step / 4 + 1
                    let stepInBeat = step % 4 + 1
                    
                    ZStack {
                        // Current step highlight
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green.opacity(0.3))
                                .padding(2)
                        }
                        
                        // Step number
                        if isDownbeat {
                            // Show beat number for downbeats
                            Text("\(beatNumber)")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(isCurrent ? .green : .primary)
                        } else {
                            // Show step in beat for off-beats
                            Text("\(stepInBeat)")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundColor(isCurrent ? .green : .secondary.opacity(0.5))
                        }
                    }
                    .frame(width: stepWidth, height: height)
                }
            }
        }
        .frame(height: height)
        .background(SequencerColors.controlBackground)
    }
}

// MARK: - Step Grid View (Legacy - kept for compatibility)

struct StepGridView: View {
    @Bindable var sequencer: SequencerEngine
    
    // Step sizing
    private let stepWidth: CGFloat = 44
    private let stepHeight: CGFloat = 44
    
    var body: some View {
        VStack(spacing: 0) {
            // Step numbers header
            StepNumbersHeader(
                steps: sequencer.pattern.steps,
                currentStep: sequencer.currentStep,
                isPlaying: sequencer.isPlaying,
                stepWidth: stepWidth
            )
            
            // Grid
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .leading) {
                    // Grid background with beat grouping
                    GridBackground(steps: sequencer.pattern.steps, stepWidth: stepWidth, rowCount: sequencer.pattern.lanes.count, rowHeight: stepHeight)
                    
                    // Playhead column
                    if sequencer.isPlaying {
                        PlayheadColumn(
                            currentStep: sequencer.currentStep,
                            stepWidth: stepWidth,
                            totalHeight: stepHeight * CGFloat(sequencer.pattern.lanes.count)
                        )
                    }
                    
                    // Step rows
                    VStack(spacing: 0) {
                        ForEach(Array(sequencer.pattern.lanes.enumerated()), id: \.element.id) { index, lane in
                            StepRow(
                                lane: lane,
                                stepCount: sequencer.pattern.steps,
                                currentStep: sequencer.currentStep,
                                isPlaying: sequencer.isPlaying,
                                stepWidth: stepWidth,
                                stepHeight: stepHeight,
                                kitLoader: sequencer.kitLoader,  // Pass kit loader to check sample availability
                                onToggle: { step in
                                    sequencer.toggleStep(laneId: lane.id, step: step)
                                },
                                onVelocityChange: { step, delta in
                                    sequencer.adjustStepVelocity(laneId: lane.id, step: step, delta: delta)
                                },
                                onProbabilityChange: { step, delta in
                                    sequencer.adjustStepProbability(laneId: lane.id, step: step, delta: delta)
                                }
                            )
                        }
                    }
                }
            }
        }
        .background(SequencerColors.gridBackground)
    }
}

// MARK: - Grid Background

struct GridBackground: View {
    let steps: Int
    let stepWidth: CGFloat
    let rowCount: Int
    let rowHeight: CGFloat
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Canvas { context, size in
            let totalHeight = rowHeight * CGFloat(rowCount)
            let isDark = colorScheme == .dark
            
            // Draw beat group backgrounds (4 steps per beat, alternating shades)
            let stepsPerBeat = 4
            let numBeats = (steps + stepsPerBeat - 1) / stepsPerBeat  // Round up
            for beat in 0..<numBeats {
                let x = CGFloat(beat * stepsPerBeat) * stepWidth
                let isOddBeat = beat % 2 == 1
                
                // Determine actual width for this beat group (handle partial groups at the end)
                let remainingSteps = steps - (beat * stepsPerBeat)
                let beatSteps = min(stepsPerBeat, remainingSteps)
                let width = stepWidth * CGFloat(beatSteps)
                
                let rect = CGRect(x: x, y: 0, width: width, height: totalHeight)
                let beatColor = isDark ?
                    Color(white: isOddBeat ? 0.12 : 0.09) :
                    Color(white: isOddBeat ? 0.92 : 0.96)
                context.fill(Path(rect), with: .color(beatColor))
            }
            
            // Draw vertical grid lines
            for step in 0...steps {
                let x = CGFloat(step) * stepWidth
                let isDownbeat = step % 4 == 0
                
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: totalHeight))
                
                let lineColor = isDark ?
                    Color.white.opacity(isDownbeat ? 0.15 : 0.05) :
                    Color.black.opacity(isDownbeat ? 0.15 : 0.05)
                context.stroke(path, with: .color(lineColor), lineWidth: isDownbeat ? 1.5 : 0.5)
            }
            
            // Draw horizontal row lines
            for row in 0...rowCount {
                let y = CGFloat(row) * rowHeight
                
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: CGFloat(steps) * stepWidth, y: y))
                
                let rowLineColor = isDark ?
                    Color.white.opacity(0.08) :
                    Color.black.opacity(0.08)
                context.stroke(path, with: .color(rowLineColor), lineWidth: 0.5)
            }
        }
        .frame(width: CGFloat(steps) * stepWidth, height: rowHeight * CGFloat(rowCount))
    }
}

// MARK: - Playhead Column

struct PlayheadColumn: View {
    let currentStep: Int
    let stepWidth: CGFloat
    let totalHeight: CGFloat
    
    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.green.opacity(0.0), Color.green.opacity(0.15), Color.green.opacity(0.0)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: stepWidth, height: totalHeight)
            .offset(x: CGFloat(currentStep) * stepWidth)
            .animation(.easeOut(duration: 0.05), value: currentStep)
    }
}

// MARK: - Step Numbers Header

struct StepNumbersHeader: View {
    let steps: Int
    let currentStep: Int
    let isPlaying: Bool
    let stepWidth: CGFloat
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<steps, id: \.self) { step in
                ZStack {
                    // Beat marker background
                    if step % 4 == 0 {
                        Text(String(format: "%02d", step / 4 + 1))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.5))
                            .offset(y: -14)
                    }
                    
                    // Step number
                    ZStack {
                        if isPlaying && step == currentStep {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 22, height: 22)
                                .shadow(color: .green.opacity(0.5), radius: 6)
                        }
                        
                        Text(String(format: "%02d", step + 1))
                            .font(.system(size: 10, weight: step % 4 == 0 ? .bold : .medium, design: .monospaced))
                            .foregroundColor(stepTextColor(for: step))
                    }
                }
                .frame(width: stepWidth, height: 32)
            }
        }
        .background(SequencerColors.controlBackground)
    }
    
    private func stepTextColor(for step: Int) -> Color {
        if isPlaying && step == currentStep {
            return .white
        }
        if step % 4 == 0 {
            return .primary
        }
        return .secondary
    }
}

// MARK: - Step Row

struct StepRow: View {
    let lane: SequencerLane
    let stepCount: Int
    let currentStep: Int
    let isPlaying: Bool
    let stepWidth: CGFloat
    let stepHeight: CGFloat
    let kitLoader: DrumKitLoader  // Kit loader to check sample availability
    let onToggle: (Int) -> Void
    let onVelocityChange: (Int, Float) -> Void
    let onProbabilityChange: (Int, Float) -> Void
    
    /// Whether this sound has a real sample (vs. synthesized fallback)
    private var hasSample: Bool {
        kitLoader.hasSample(for: lane.soundType)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<stepCount, id: \.self) { step in
                StepCell(
                    isActive: lane.activeSteps.contains(step),
                    velocity: lane.velocity(for: step) ?? 0.8,
                    probability: lane.probability(for: step),
                    isCurrent: isPlaying && step == currentStep,
                    isDownbeat: step % 4 == 0,
                    color: lane.soundType.color,
                    width: stepWidth,
                    height: stepHeight,
                    onTap: { onToggle(step) },
                    onVelocityChange: { delta in onVelocityChange(step, delta) },
                    onProbabilityChange: { delta in onProbabilityChange(step, delta) }
                )
            }
        }
        .opacity(lane.isMuted ? 0.35 : (hasSample ? 1.0 : 0.4))  // Dim unavailable sounds
    }
}

// MARK: - Step Cell

struct StepCell: View {
    let isActive: Bool
    let velocity: Float  // 0.0-1.0, controls brightness/size
    let probability: Float  // 0.0-1.0, controls chance of triggering
    let isCurrent: Bool
    let isDownbeat: Bool
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let onTap: () -> Void
    let onVelocityChange: (Float) -> Void
    let onProbabilityChange: (Float) -> Void
    
    @State private var isHovering = false
    @State private var isPressed = false
    
    /// Velocity-based opacity (higher velocity = brighter)
    private var velocityOpacity: Double {
        Double(0.4 + velocity * 0.6)
    }
    
    /// Velocity-based scale (subtle size variation)
    private var velocityScale: CGFloat {
        CGFloat(0.85 + Double(velocity) * 0.15)
    }
    
    var body: some View {
        ZStack {
            // Active pad with velocity visualization
            if isActive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(velocityOpacity), color.opacity(velocityOpacity * 0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .padding(5)
                    .shadow(color: color.opacity(isCurrent ? 0.8 : 0.4 * velocityOpacity), radius: isCurrent ? 8 : 4, x: 0, y: 2)
                    .overlay(
                        // Highlight shine
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.3 * velocityOpacity), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                )
                            )
                            .padding(5)
                    )
                    .scaleEffect(isPressed ? 0.9 : (isCurrent ? 1.05 : velocityScale))
                
                // Velocity indicator bar at bottom
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.6))
                        .frame(width: (width - 14) * CGFloat(velocity), height: 3)
                        .padding(.bottom, 7)
                }
                
                // Probability indicator (top-left corner when < 100%)
                if probability < 1.0 {
                    VStack {
                        HStack {
                            Text("\(Int(probability * 100))%")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(2)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(2)
                                .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
            }
            
            // Hover indicator (when not active)
            if isHovering && !isActive {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(color.opacity(0.4), lineWidth: 2)
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 2)
                            .fill(color.opacity(0.1))
                            .padding(5)
                    )
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                    isPressed = false
                }
            }
            onTap()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        // Option + drag to adjust velocity
        .gesture(
            DragGesture(minimumDistance: 0)
                .modifiers(.option)
                .onChanged { value in
                    if isActive {
                        // Vertical drag adjusts velocity
                        let delta = Float(-value.translation.height / 100)
                        onVelocityChange(delta)
                    }
                }
        )
        // Command + drag to adjust probability
        .gesture(
            DragGesture(minimumDistance: 0)
                .modifiers(.command)
                .onChanged { value in
                    if isActive {
                        // Vertical drag adjusts probability
                        let delta = Float(-value.translation.height / 100)
                        onProbabilityChange(delta)
                    }
                }
        )
    }
}

// MARK: - Presets View (Encyclopedic Rhythm Library)

struct PresetsView: View {
    @Bindable var sequencer: SequencerEngine
    @Environment(\.dismiss) var dismiss
    
    // MARK: - State
    @State private var searchText: String = ""
    @State private var selectedGroupIndex: Int = 0
    @State private var selectedCategoryName: String? = nil
    @State private var hoveredPreset: String? = nil
    @State private var hoveredCategory: String? = nil
    @State private var expandedGroups: Set<String> = ["Genres"]
    @State private var patternToDelete: StepPattern? = nil
    @State private var showingDeleteConfirmation = false
    @State private var showFavoritesOnly = false
    
    // Quick access sections
    private enum QuickSection: String, CaseIterable {
        case myPatterns = "My Patterns"
        case favorites = "Favorites"
        case recentlyUsed = "Recently Used"
    }
    @State private var selectedQuickSection: QuickSection? = .myPatterns
    
    // MARK: - Computed Properties
    
    private var allCategories: [PresetCategory] {
        SequencerPresetLibrary.allCategories
    }
    
    private var allGroups: [PresetGroup] {
        SequencerPresetLibrary.allGroups
    }
    
    private var currentCategory: PresetCategory? {
        if let name = selectedCategoryName {
            return allCategories.first { $0.name == name }
        }
        return nil
    }
    
    private var isQuickSectionSelected: Bool {
        selectedQuickSection != nil
    }
    
    private var totalPatternCount: Int {
        SequencerPresetLibrary.totalCount + sequencer.savedPatterns.count
    }
    
    private var filteredPresets: [PresetData] {
        var presets = SequencerPresetLibrary.allPresets
        
        // Apply search filter
        if !searchText.isEmpty {
            presets = presets.filter { preset in
                preset.name.localizedCaseInsensitiveContains(searchText) ||
                preset.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply favorites filter
        if showFavoritesOnly {
            presets = presets.filter { sequencer.favoritePresets.contains($0.name) }
        }
        
        return presets
    }
    
    private var filteredCategories: [PresetCategory] {
        if searchText.isEmpty && !showFavoritesOnly {
            return allCategories
        }
        
        return allCategories.compactMap { category in
            let filtered = category.presets.filter { preset in
                let matchesSearch = searchText.isEmpty || 
                    preset.name.localizedCaseInsensitiveContains(searchText) ||
                    preset.description.localizedCaseInsensitiveContains(searchText)
                let matchesFavorites = !showFavoritesOnly || sequencer.favoritePresets.contains(preset.name)
                return matchesSearch && matchesFavorites
            }
            
            if filtered.isEmpty { return nil }
            return PresetCategory(name: category.name, icon: category.icon, color: category.color, presets: filtered)
        }
    }
    
    private var filteredUserPatterns: [StepPattern] {
        if searchText.isEmpty {
            return sequencer.savedPatterns
        }
        
        return sequencer.savedPatterns.filter { pattern in
            pattern.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var totalSearchResults: Int {
        filteredPresets.count + filteredUserPatterns.count
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            searchBar
            Divider()
            
            HStack(spacing: 0) {
                sidebarView
                Divider()
                contentView
            }
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Text("\(totalPatternCount) patterns available")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 900, height: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            sequencer.loadSavedPatterns()
        }
        .alert("Delete Pattern?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { patternToDelete = nil }
            Button("Delete", role: .destructive) {
                if let pattern = patternToDelete {
                    sequencer.deletePattern(pattern)
                    patternToDelete = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(patternToDelete?.name ?? "")'? This cannot be undone.")
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Image(systemName: "square.grid.3x3.fill")
                .font(.title2)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.orange, .pink],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Pattern Library")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("Encyclopedic rhythm collection spanning all of human musical history")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Stats badges
            HStack(spacing: 8) {
                StatBadge(value: "\(SequencerPresetLibrary.allGroups.count)", label: "Groups", color: .blue)
                StatBadge(value: "\(SequencerPresetLibrary.allCategories.count)", label: "Categories", color: .purple)
                StatBadge(value: "\(totalPatternCount)", label: "Patterns", color: .orange)
            }
            
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }
    
    // MARK: - Search Bar
    
    private var searchBar: some View {
        HStack(spacing: 12) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search patterns...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
            
            // Favorites toggle
            Button(action: { showFavoritesOnly.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: showFavoritesOnly ? "star.fill" : "star")
                    Text("Favorites")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(showFavoritesOnly ? Color.yellow.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                .foregroundColor(showFavoritesOnly ? .yellow : .primary)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
    
    // MARK: - Sidebar View
    
    private var sidebarView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                // Quick Access Section
                VStack(alignment: .leading, spacing: 4) {
                    Text("QUICK ACCESS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                    
                    quickAccessButton(
                        section: .myPatterns,
                        icon: "heart.fill",
                        color: .pink,
                        count: sequencer.savedPatterns.count
                    )
                    
                    quickAccessButton(
                        section: .favorites,
                        icon: "star.fill",
                        color: .yellow,
                        count: sequencer.favoritePresets.count
                    )
                    
                    quickAccessButton(
                        section: .recentlyUsed,
                        icon: "clock.fill",
                        color: .blue,
                        count: sequencer.recentPresets.count
                    )
                }
                
                Divider()
                    .padding(.horizontal, 12)
                
                // Groups and Categories
                ForEach(allGroups) { group in
                    groupSection(group: group)
                }
            }
            .padding(.vertical, 12)
        }
        .frame(width: 220)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    private func quickAccessButton(section: QuickSection, icon: String, color: Color, count: Int) -> some View {
        let isSelected = selectedQuickSection == section && selectedCategoryName == nil
        
        return Button(action: {
            selectedQuickSection = section
            selectedCategoryName = nil
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .white : color)
                    .frame(width: 20)
                
                Text(section.rawValue)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
                
                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? color : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
    
    private func groupSection(group: PresetGroup) -> some View {
        let isExpanded = expandedGroups.contains(group.name)
        
        return VStack(alignment: .leading, spacing: 4) {
            // Group header
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedGroups.remove(group.name)
                    } else {
                        expandedGroups.insert(group.name)
                    }
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    
                    Image(systemName: group.icon)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text(group.name.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(group.categories.count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            
            // Categories
            if isExpanded {
                ForEach(group.categories) { category in
                    categoryButton(category: category)
                }
            }
        }
    }
    
    private func categoryButton(category: PresetCategory) -> some View {
        let isSelected = selectedCategoryName == category.name && selectedQuickSection == nil
        let isHovered = hoveredCategory == category.name
        
        return Button(action: {
            selectedCategoryName = category.name
            selectedQuickSection = nil
        }) {
            HStack(spacing: 8) {
                Image(systemName: category.icon)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white : category.color)
                    .frame(width: 18)
                
                Text(category.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Spacer()
                
                Text("\(category.presets.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? category.color : (isHovered ? category.color.opacity(0.15) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .onHover { hovering in
            hoveredCategory = hovering ? category.name : nil
        }
    }
    
    // MARK: - Content View
    
    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                if !searchText.isEmpty || showFavoritesOnly {
                    searchResultsContent
                } else if let section = selectedQuickSection, selectedCategoryName == nil {
                    quickSectionContent(section: section)
                } else if let category = currentCategory {
                    categoryContent(category: category)
                } else {
                    welcomeContent
                }
            }
            .padding(16)
        }
    }
    
    private func quickSectionContent(section: QuickSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Image(systemName: sectionIcon(section))
                    .foregroundColor(sectionColor(section))
                Text(section.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
            }
            
            switch section {
            case .myPatterns:
                userPatternsGrid
            case .favorites:
                favoritesGrid
            case .recentlyUsed:
                recentlyUsedGrid
            }
        }
    }
    
    private func sectionIcon(_ section: QuickSection) -> String {
        switch section {
        case .myPatterns: return "heart.fill"
        case .favorites: return "star.fill"
        case .recentlyUsed: return "clock.fill"
        }
    }
    
    private func sectionColor(_ section: QuickSection) -> Color {
        switch section {
        case .myPatterns: return .pink
        case .favorites: return .yellow
        case .recentlyUsed: return .blue
        }
    }
    
    private var userPatternsGrid: some View {
        Group {
            if sequencer.savedPatterns.isEmpty {
                emptyStateView(
                    icon: "heart",
                    title: "No Saved Patterns",
                    message: "Create a pattern in the sequencer and save it to see it here."
                )
            } else {
                ForEach(sequencer.savedPatterns) { pattern in
                    UserPatternCard(
                        pattern: pattern,
                        isHovered: hoveredPreset == pattern.name,
                        onLoad: {
                            sequencer.loadPattern(pattern)
                            dismiss()
                        },
                        onDelete: {
                            patternToDelete = pattern
                            showingDeleteConfirmation = true
                        }
                    )
                    .onHover { hovering in
                        hoveredPreset = hovering ? pattern.name : nil
                    }
                }
            }
        }
    }
    
    private var favoritesGrid: some View {
        Group {
            let favoritePresets = SequencerPresetLibrary.allPresets.filter { sequencer.favoritePresets.contains($0.name) }
            
            if favoritePresets.isEmpty {
                emptyStateView(
                    icon: "star",
                    title: "No Favorites Yet",
                    message: "Click the star on any pattern to add it to your favorites."
                )
            } else {
                ForEach(favoritePresets) { preset in
                    presetCard(preset: preset, category: findCategory(for: preset))
                }
            }
        }
    }
    
    private var recentlyUsedGrid: some View {
        Group {
            let recentPresets = sequencer.recentPresets.compactMap { name in
                SequencerPresetLibrary.allPresets.first { $0.name == name }
            }
            
            if recentPresets.isEmpty {
                emptyStateView(
                    icon: "clock",
                    title: "No Recent Patterns",
                    message: "Patterns you use will appear here for quick access."
                )
            } else {
                ForEach(recentPresets) { preset in
                    presetCard(preset: preset, category: findCategory(for: preset))
                }
            }
        }
    }
    
    private func categoryContent(category: PresetCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            HStack {
                Image(systemName: category.icon)
                    .foregroundColor(category.color)
                Text(category.name)
                    .font(.system(size: 16, weight: .semibold))
                Text("•")
                    .foregroundColor(.secondary)
                Text("\(category.presets.count) patterns")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            ForEach(category.presets) { preset in
                presetCard(preset: preset, category: category)
            }
        }
    }
    
    private var searchResultsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                Text("Search Results")
                    .font(.system(size: 16, weight: .semibold))
                Text("•")
                    .foregroundColor(.secondary)
                Text("\(totalSearchResults) patterns found")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            
            if totalSearchResults == 0 {
                emptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results",
                    message: "Try a different search term."
                )
            } else {
                // Show user patterns first if any match
                if !filteredUserPatterns.isEmpty {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundColor(.pink)
                            .font(.system(size: 12))
                        Text("My Patterns")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 4)
                    
                    ForEach(filteredUserPatterns) { pattern in
                        UserPatternCard(
                            pattern: pattern,
                            isHovered: hoveredPreset == pattern.name,
                            onLoad: {
                                sequencer.loadPattern(pattern)
                                dismiss()
                            },
                            onDelete: {
                                patternToDelete = pattern
                                showingDeleteConfirmation = true
                            }
                        )
                        .onHover { hovering in
                            hoveredPreset = hovering ? pattern.name : nil
                        }
                    }
                }
                
                // Show factory presets
                if !filteredPresets.isEmpty {
                    if !filteredUserPatterns.isEmpty {
                        HStack {
                            Image(systemName: "square.grid.3x3.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 12))
                            Text("Factory Presets")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 12)
                    }
                    
                    ForEach(filteredPresets) { preset in
                        presetCard(preset: preset, category: findCategory(for: preset))
                    }
                }
            }
        }
    }
    
    private var welcomeContent: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "music.note.list")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            
            Text("Welcome to the Pattern Library")
                .font(.system(size: 20, weight: .semibold))
            
            Text("Select a category from the sidebar to browse \(SequencerPresetLibrary.totalCount) patterns\nacross \(SequencerPresetLibrary.allCategories.count) categories spanning all genres of music.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.5))
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.secondary)
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    private func presetCard(preset: PresetData, category: PresetCategory?) -> some View {
        let isFavorite = sequencer.favoritePresets.contains(preset.name)
        let isHovered = hoveredPreset == preset.name
        let color = category?.color ?? .gray
        let icon = category?.icon ?? "waveform"
        
        return HStack(spacing: 12) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(color)
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text(preset.description)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    HStack(spacing: 2) {
                        Image(systemName: "metronome")
                            .font(.system(size: 9))
                        Text(preset.bpm)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(color)
                }
            }
            
            Spacer()
            
            // Mini preview (16 rows)
            PatternPreview(pattern: preset.pattern, color: color)
                .frame(width: 80, height: 42)
            
            // Favorite button (stops propagation to card tap)
            Button(action: {
                sequencer.toggleFavorite(preset.name)
            }) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 16))
                    .foregroundColor(isFavorite ? .yellow : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
            
            // Play icon (visual indicator only, card handles tap)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 24))
                .foregroundColor(isHovered ? color : .secondary.opacity(0.4))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isHovered ? color.opacity(0.5) : Color.clear, lineWidth: 2)
                )
        )
        .contentShape(Rectangle()) // Makes entire area tappable
        .onTapGesture {
            loadPreset(preset)
            dismiss()
        }
        .onHover { hovering in
            hoveredPreset = hovering ? preset.name : nil
        }
    }
    
    private func findCategory(for preset: PresetData) -> PresetCategory? {
        allCategories.first { $0.presets.contains(where: { $0.name == preset.name }) }
    }
    
    // MARK: - Actions
    
    private func loadPreset(_ preset: PresetData) {
        // Capture old pattern for undo
        let oldPattern = sequencer.pattern
        
        // Clear current pattern (without individual undo registration)
        for lane in sequencer.pattern.lanes {
            for step in 0..<16 {
                sequencer.setStep(laneId: lane.id, step: step, active: false, registerUndo: false)
            }
        }
        
        // Set new pattern name
        sequencer.pattern.name = preset.name
        
        // Load pattern data - Core Kit (Rows 1-8)
        setSteps("Kick", preset.kicks)
        setSteps("Snare", preset.snares)
        setSteps("Closed Hat", preset.closedHats)
        setSteps("Open Hat", preset.openHats)
        setSteps("Clap", preset.claps)
        setSteps("Low Tom", preset.lowToms)
        setSteps("Mid Tom", preset.midToms)
        setSteps("High Tom", preset.highToms)
        
        // Extended Kit (Rows 9-16)
        setSteps("Crash", preset.crashes)
        setSteps("Ride", preset.rides)
        setSteps("Rim", preset.rimshots)
        setSteps("Cowbell", preset.cowbells)
        setSteps("Shaker", preset.shakers)
        setSteps("Tambourine", preset.tambourines)
        setSteps("Low Conga", preset.lowCongas)
        setSteps("High Conga", preset.highCongas)
        
        // Register undo for entire preset load
        let newPattern = sequencer.pattern
        UndoService.shared.registerUndo(actionName: "Load Preset") { [weak sequencer] in
            sequencer?.pattern = oldPattern
        } redo: { [weak sequencer] in
            sequencer?.pattern = newPattern
        }
        
        // Add to recents
        sequencer.addToRecents(preset.name)
    }
    
    private func setSteps(_ laneName: String, _ steps: [Int]) {
        if let lane = sequencer.pattern.lanes.first(where: { $0.name == laneName }) {
            for step in steps {
                sequencer.setStep(laneId: lane.id, step: step, active: true, registerUndo: false)
            }
        }
    }
    
}

// MARK: - Stat Badge

struct StatBadge: View {
    let value: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - User Pattern Card (for My Patterns section)

struct UserPatternCard: View {
    let pattern: StepPattern
    let isHovered: Bool
    let onLoad: () -> Void
    let onDelete: () -> Void
    @State private var showDeleteIcon = false
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.pink.opacity(0.2))
                    .frame(width: 44, height: 44)
                Image(systemName: "heart.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.pink)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(pattern.name)
                    .font(.system(size: 14, weight: .semibold))
                Text("User Pattern • \(pattern.lanes.count) lanes")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if showDeleteIcon {
                Button(action: onDelete) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            
            Button(action: onLoad) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(isHovered ? .pink : .secondary.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isHovered ? Color.pink.opacity(0.5) : Color.clear, lineWidth: 2)
                )
        )
        .contentShape(Rectangle()) // Makes entire area tappable
        .onTapGesture {
            onLoad()
        }
        .onHover { hovering in
            showDeleteIcon = hovering
        }
    }
}

// MARK: - Pattern Preview (Mini Grid - 16 rows)

struct PatternPreview: View {
    let pattern: [[Bool]]  // Up to 16 rows x 16 steps
    let color: Color
    
    // Compact sizing for 16 rows
    private let cellSize: CGFloat = 2
    private let spacing: CGFloat = 0.5
    
    var body: some View {
        VStack(spacing: spacing) {
            // Show all rows (up to 16)
            ForEach(0..<min(pattern.count, 16), id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<16, id: \.self) { step in
                        let isActive = row < pattern.count && step < pattern[row].count && pattern[row][step]
                        Rectangle()
                            .fill(isActive ? rowColor(row) : Color.gray.opacity(0.15))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }
    
    /// Color for each drum row (matches DrumSoundType order)
    private func rowColor(_ row: Int) -> Color {
        switch row {
        case 0: return .red.opacity(0.9)       // Kick
        case 1: return .orange.opacity(0.9)    // Snare
        case 2: return .cyan.opacity(0.9)      // Hi-hat Closed
        case 3: return .cyan.opacity(0.7)      // Hi-hat Open
        case 4: return .pink.opacity(0.9)      // Clap
        case 5: return .brown.opacity(0.9)     // Tom Low
        case 6: return .brown.opacity(0.8)     // Tom Mid
        case 7: return .brown.opacity(0.7)     // Tom High
        // Extended kit (rows 9-16)
        case 8: return .yellow.opacity(0.9)    // Crash
        case 9: return .yellow.opacity(0.7)    // Ride
        case 10: return .purple.opacity(0.9)   // Rimshot
        case 11: return .orange.opacity(0.8)   // Cowbell
        case 12: return .green.opacity(0.8)    // Shaker
        case 13: return .mint.opacity(0.9)     // Tambourine
        case 14: return .indigo.opacity(0.9)   // Conga Low
        case 15: return .indigo.opacity(0.7)   // Conga High
        default: return color
        }
    }
}

// MARK: - Fallback Drum Kit Option (when list API unavailable)

private struct FallbackDrumKitOption: Identifiable {
    let id: String
    let name: String
    let description: String
    let color: Color
    static let icon = "drum.fill"
    /// Shared muted palette for both fallback and API list so the grid stays multicolored when connected.
    static let palette: [Color] = [
        Color(red: 0.72, green: 0.48, blue: 0.28),
        Color(red: 0.58, green: 0.32, blue: 0.32),
        Color(red: 0.28, green: 0.52, blue: 0.55),
        Color(red: 0.42, green: 0.38, blue: 0.55),
        Color(red: 0.32, green: 0.52, blue: 0.38),
        Color(red: 0.3, green: 0.45, blue: 0.62),
    ]
    /// Fallback options matching backend kit IDs.
    static let all: [FallbackDrumKitOption] = [
        FallbackDrumKitOption(id: "cr78", name: "CR-78", description: "Vintage rhythm box. Characterful patterns and tones.", color: palette[0]),
        FallbackDrumKitOption(id: "linndrum", name: "LinnDrum", description: "’80s staple. Tight, sample-based drum sounds.", color: palette[1]),
        FallbackDrumKitOption(id: "pearl", name: "Pearl", description: "Classic drum kit. Natural acoustic sounds.", color: palette[2]),
        FallbackDrumKitOption(id: "tr505", name: "TR-505", description: "Digital drum machine. Clean, modern percussion.", color: palette[3]),
        FallbackDrumKitOption(id: "tr909", name: "TR-909", description: "Industry-standard electronic drums. Punchy and precise.", color: palette[4]),
        FallbackDrumKitOption(id: "template", name: "Template Kit", description: "Starting point for custom drum kits.", color: palette[5]),
    ]
}

// MARK: - Drum Kit Download Card (grid cell for fallback + API list)

private struct DrumKitDownloadCardView: View {
    let kitId: String
    let name: String
    let description: String?
    let subtitle: String?
    let icon: String
    let color: Color
    let isInstalled: Bool
    let isDownloading: Bool
    let canDownload: Bool  // Only show download UI when network is connected
    let isSelected: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void

    var body: some View {
        Button(action: {
            if isDownloading {
                // Do nothing while downloading
                return
            }
            if isInstalled {
                // Downloaded: select it and dismiss modal
                onSelect()
            } else {
                // Not downloaded: download it (will auto-select and dismiss after)
                onDownload()
            }
        }) {
            VStack(alignment: .leading, spacing: 10) {
                // Header: Name + Badge
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    downloadStateBadge
                }

                // Description
                if let desc = description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(height: 120)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? color.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? color.opacity(0.6) : Color(nsColor: .separatorColor).opacity(0.4), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isInstalled ? "Select \(name)" : "Download \(name)")
    }

    @ViewBuilder
    private var downloadStateBadge: some View {
        Group {
            if isSelected {
                // Active/selected kit: Green checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
            } else if isInstalled {
                // Downloaded but not active: Gray checkmark (always show)
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary)
            } else if isDownloading {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 20, height: 20)
            } else {
                // Not downloaded: always show download icon (colored when available, gray when offline)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 16))
                    .foregroundColor(canDownload ? color : .secondary)
            }
        }
    }
}

// MARK: - Kit Selector View

struct KitSelectorView: View {
    @Environment(\.dismiss) var dismiss
    @Bindable var sequencer: SequencerEngine
    @State private var isLoadingKit = false
    @State private var hoveredKit: UUID?
    @State private var remoteDrumKits: [DrumKitItem] = []
    @State private var kitListLoading = false
    @State private var kitListError: String?
    @State private var downloadingKitId: String?
    @State private var downloadingAllDrums = false
    @State private var downloadingBundle = false
    @State private var downloadAllDrumsProgress: (Int, Int)?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "music.quarternote.3")
                            .font(.system(size: 20))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        Text("Drum Kits")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                    }
                    Text("Select a drum kit to change the sequencer sounds")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Always show full grid of all drum options (download + select)
            stepSequencerNoKitsView
                .task { await loadRemoteDrumKitsForStepSequencer() }
            
            Divider()
        }
        .frame(width: 600, height: 500)
    }
    
    private var stepSequencerNoKitsView: some View {
        let isNetworkConnected = !remoteDrumKits.isEmpty
        let hasGrid = !FallbackDrumKitOption.all.isEmpty

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if hasGrid {
                    // Top controls and error (no duplicate title/description)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center) {
                            Spacer()
                            if isNetworkConnected {
                                stepSequencerDownloadAllControl
                            }
                        }
                        if let error = kitListError {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)


                    // Always show the fallback grid with descriptions
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ], spacing: 14) {
                        ForEach(FallbackDrumKitOption.all) { option in
                            let isInstalled = AssetDownloadService.isDrumKitInstalled(kitId: option.id)
                            // Show download button if network is connected AND kit is not installed
                            let showDownload = isNetworkConnected && !isInstalled
                            // Check if this kit is selected by matching directory name
                            let isSelected = sequencer.kitLoader.currentKit.directory?.lastPathComponent == option.id
                            
                            DrumKitDownloadCardView(
                                kitId: option.id,
                                name: option.name,
                                description: option.description,
                                subtitle: nil,
                                icon: FallbackDrumKitOption.icon,
                                color: option.color,
                                isInstalled: isInstalled,
                                isDownloading: downloadingKitId == option.id,
                                canDownload: showDownload,
                                isSelected: isSelected,
                                onSelect: { selectDownloadedKit(option.id) },
                                onDownload: { startDownloadDrumKit(option.id) }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                } else {
                    Text("Place drum kit folders in ~/Library/Application Support/Stori/DrumKits/")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 32)
                        .padding(.top, 40)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor).opacity(0.6),
                    Color(nsColor: .windowBackgroundColor).opacity(0.8)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    /// Title-row control: Download all drums (and optional bundle). Obvious but non-obtrusive.
    private var stepSequencerDownloadAllControl: some View {
        HStack(spacing: 12) {
            if downloadingAllDrums {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    if let (current, total) = downloadAllDrumsProgress, total > 0 {
                        Text("\(current) of \(total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if downloadingBundle {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Downloading all…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                if stepSequencerHasKitsToDownload {
                    Button(action: { Task { await stepSequencerDownloadAllDrumKits() } }) {
                        Text("Download all")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.accentColor)
                    .accessibilityLabel("Download all drum kits")
                }
                Button(action: { Task { await stepSequencerDownloadBundle() } }) {
                    Text("Get drums + instruments")
                        .font(.system(size: 11, weight: .regular))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
                .accessibilityLabel("Download all drums and instruments")
                if AssetDownloadService.hasAnyDrumKitsOnDisk() {
                    Button(action: { stepSequencerClearAllDrumKits() }) {
                        Text("Clear downloaded drums")
                            .font(.system(size: 11, weight: .regular))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.orange)
                    .accessibilityLabel("Clear downloaded drum kits to allow redownload")
                }
            }
        }
    }
    
    private func stepSequencerClearAllDrumKits() {
        do {
            try AssetDownloadService.removeAllDrumKits()
            sequencer.kitLoader.loadAvailableKits()
            kitListError = nil
        } catch {
            kitListError = "Could not clear drum kits: \(error.localizedDescription)"
        }
    }

    private var stepSequencerHasKitsToDownload: Bool {
        // Only check remote kits since we always show fallback grid
        guard !remoteDrumKits.isEmpty else { return false }
        return remoteDrumKits.contains { !AssetDownloadService.isDrumKitInstalled(kitId: $0.id) }
    }
    
    private func stepSequencerKitDownloadRow(_ item: DrumKitItem) -> some View {
        let isInstalled = AssetDownloadService.isDrumKitInstalled(kitId: item.id)
        let isDownloading = downloadingKitId == item.id
        return HStack(spacing: 12) {
            Image(systemName: "drum")
                .font(.system(size: 20))
                .foregroundColor(.orange)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .medium))
                if let count = item.fileCount {
                    Text("\(count) files")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if isInstalled {
                Text("Installed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if isDownloading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Button("Download") {
                    Task { await stepSequencerDownloadDrumKit(item.id) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func loadRemoteDrumKitsForStepSequencer() async {
        guard sequencer.kitLoader.availableKits.isEmpty else { return }
        
        // Check if backend is configured (Config.plist or environment variable)
        guard !AppConfig.apiBaseURL.isEmpty else {
            kitListError = "Backend not configured. Download official DMG or configure your own backend (see Config.plist.example)"
            return
        }
        
        kitListLoading = true
        kitListError = nil
        defer { kitListLoading = false }
        do {
            remoteDrumKits = try await AssetDownloadService.shared.listDrumKits()
        } catch {
            // Prefer lastError (user-friendly), fallback to sanitized error message
            if let serviceError = AssetDownloadService.shared.lastError {
                kitListError = serviceError
            } else {
                // Sanitize error.localizedDescription to remove server URLs
                var message = error.localizedDescription
                #if !DEBUG
                // Remove server URL patterns in production
                message = message.replacingOccurrences(of: " \\(server:.*\\)", with: "", options: .regularExpression)
                message = message.replacingOccurrences(of: "https?://[^\\s)]+", with: "[server]", options: .regularExpression)
                #endif
                kitListError = message
            }
        }
    }
    
    /// Synchronous kick-off so the button action fires reliably on macOS.
    private func startDownloadDrumKit(_ kitId: String) {
        Task { await stepSequencerDownloadDrumKit(kitId) }
    }

    @MainActor
    private func stepSequencerDownloadDrumKit(_ kitId: String) async {
        downloadingKitId = kitId
        kitListError = nil
        defer { downloadingKitId = nil }
        do {
            try await AssetDownloadService.shared.downloadDrumKit(kitId: kitId)
            sequencer.kitLoader.loadAvailableKits()
            // Auto-select the newly downloaded kit
            selectDownloadedKit(kitId)
        } catch {
            // Prefer lastError (user-friendly), fallback to sanitized error message
            if let serviceError = AssetDownloadService.shared.lastError {
                kitListError = serviceError
            } else {
                // Sanitize error.localizedDescription to remove server URLs
                var message = error.localizedDescription
                #if !DEBUG
                // Remove server URL patterns in production
                message = message.replacingOccurrences(of: " \\(server:.*\\)", with: "", options: .regularExpression)
                message = message.replacingOccurrences(of: "https?://[^\\s)]+", with: "[server]", options: .regularExpression)
                #endif
                kitListError = message
            }
        }
    }

    private func stepSequencerDownloadAllDrumKits() async {
        downloadingAllDrums = true
        downloadAllDrumsProgress = nil
        defer {
            downloadingAllDrums = false
            downloadAllDrumsProgress = nil
        }
        do {
            try await AssetDownloadService.shared.downloadAllDrumKits { current, total in
                downloadAllDrumsProgress = (current, total)
            }
            sequencer.kitLoader.loadAvailableKits()
        } catch {
            // Prefer lastError (user-friendly), fallback to sanitized error message
            if let serviceError = AssetDownloadService.shared.lastError {
                kitListError = serviceError
            } else {
                // Sanitize error.localizedDescription to remove server URLs
                var message = error.localizedDescription
                #if !DEBUG
                // Remove server URL patterns in production
                message = message.replacingOccurrences(of: " \\(server:.*\\)", with: "", options: .regularExpression)
                message = message.replacingOccurrences(of: "https?://[^\\s)]+", with: "[server]", options: .regularExpression)
                #endif
                kitListError = message
            }
        }
    }

    private func stepSequencerDownloadBundle() async {
        downloadingBundle = true
        defer { downloadingBundle = false }
        do {
            try await AssetDownloadService.shared.downloadBundle()
            sequencer.kitLoader.loadAvailableKits()
        } catch {
            // Prefer lastError (user-friendly), fallback to sanitized error message
            if let serviceError = AssetDownloadService.shared.lastError {
                kitListError = serviceError
            } else {
                // Sanitize error.localizedDescription to remove server URLs
                var message = error.localizedDescription
                #if !DEBUG
                // Remove server URL patterns in production
                message = message.replacingOccurrences(of: " \\(server:.*\\)", with: "", options: .regularExpression)
                message = message.replacingOccurrences(of: "https?://[^\\s)]+", with: "[server]", options: .regularExpression)
                #endif
                kitListError = message
            }
        }
    }

    private func selectKit(_ kit: DrumKit) {
        isLoadingKit = true
        Task {
            await sequencer.selectKit(kit)
            isLoadingKit = false
            dismiss()
        }
    }
    
    private func selectDownloadedKit(_ kitId: String) {
        // Find the kit by matching the directory name (e.g., "cr78" matches .../DrumKits/cr78/)
        #if DEBUG
        print("🔵 [StepSequencer] Attempting to select kit: \(kitId)")
        print("🔵 [StepSequencer] Available kits: \(sequencer.kitLoader.availableKits.map { $0.directory?.lastPathComponent ?? "no-dir" })")
        #endif
        
        if let kit = sequencer.kitLoader.availableKits.first(where: { kit in
            guard let directory = kit.directory else { return false }
            return directory.lastPathComponent == kitId
        }) {
            #if DEBUG
            print("✅ [StepSequencer] Found and selecting kit: \(kit.name)")
            #endif
            selectKit(kit)
        } else {
            #if DEBUG
            print("🔴 [StepSequencer] Could not find kit with ID: \(kitId)")
            #endif
        }
    }
    
    private func previewKit(_ kit: DrumKit) {
        // Preview the kit by playing a quick pattern
        sequencer.previewSound(.kick)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            sequencer.previewSound(.snare)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            sequencer.previewSound(.hihatClosed)
        }
    }
    
}

// MARK: - Kit Card

struct KitCard: View {
    let kit: DrumKit
    let isSelected: Bool
    let isHovered: Bool
    let isLoading: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void
    
    private var isSynthesized: Bool {
        kit.directory == nil
    }
    
    private var accentColor: Color {
        if isSynthesized {
            return .purple
        } else {
            return .cyan
        }
    }
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: isSynthesized ? "waveform" : "speaker.wave.2.fill")
                                .font(.system(size: 18))
                                .foregroundColor(accentColor)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kit.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(kit.author)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.green)
                    }
                }
                
                // Sample indicators
                if !isSynthesized {
                    HStack(spacing: 4) {
                        ForEach(DrumSoundType.allCases.prefix(8), id: \.self) { soundType in
                            let hasSound = kit.hasSound(for: soundType)
                            Circle()
                                .fill(hasSound ? soundType.color.opacity(0.8) : Color.gray.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                    }
                } else {
                    Text("Synthesized • Built-in")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                // Footer
                HStack {
                    Text(kit.license)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.secondary.opacity(0.1))
                        )
                    
                    Spacer()
                    
                    // Preview button
                    Button(action: onPreview) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(accentColor.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .opacity(isHovered ? 1 : 0)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                isSelected ? Color.green.opacity(0.5) :
                                    (isHovered ? accentColor.opacity(0.3) : Color.clear),
                                lineWidth: 2
                            )
                    )
                    .shadow(
                        color: isHovered ? accentColor.opacity(0.15) : .clear,
                        radius: 8,
                        x: 0,
                        y: 4
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - User Patterns Grid View

struct UserPatternsGridView: View {
    let patterns: [StepPattern]
    let hoveredPreset: String?
    let onHover: (String?) -> Void
    let onLoad: (StepPattern) -> Void
    let onDelete: (StepPattern) -> Void
    
    var body: some View {
        ScrollView {
            if patterns.isEmpty {
                // Empty state
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("No Saved Patterns")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Text("Create a pattern in the sequencer and click 'Save' to add it here.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 100)
            } else {
                VStack(spacing: 10) {
                    ForEach(patterns) { pattern in
                        UserPatternCard(
                            pattern: pattern,
                            isHovered: hoveredPreset == pattern.name,
                            onLoad: { onLoad(pattern) },
                            onDelete: { onDelete(pattern) }
                        )
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                onHover(hovering ? pattern.name : nil)
                            }
                        }
                    }
                }
                .padding(12)
            }
        }
    }
}

// MARK: - User Pattern Preview (16 rows)

struct UserPatternPreview: View {
    let pattern: StepPattern
    
    // Compact sizing for 16 rows
    private let cellSize: CGFloat = 2
    private let spacing: CGFloat = 0.5
    
    var body: some View {
        VStack(spacing: spacing) {
            // Show all lanes (up to 16)
            ForEach(0..<min(pattern.lanes.count, 16), id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<16, id: \.self) { step in
                        let isActive = pattern.lanes[row].activeSteps.contains(step)
                        Rectangle()
                            .fill(isActive ? pattern.lanes[row].soundType.color.opacity(0.9) : Color.gray.opacity(0.15))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }
}

// MARK: - Keyboard Handler

struct SequencerKeyboardHandler: NSViewRepresentable {
    @Bindable var sequencer: SequencerEngine
    let onPlayPause: () -> Void
    let onStop: () -> Void
    let onClear: () -> Void
    
    func makeNSView(context: Context) -> NSView {
        let view = KeyCaptureView()
        view.onKeyDown = { event in
            handleKeyDown(event)
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
    
    private func handleKeyDown(_ event: NSEvent) {
        // Check for modifier keys
        let hasCommand = event.modifierFlags.contains(.command)
        let hasOption = event.modifierFlags.contains(.option)
        
        switch event.keyCode {
        case 49: // Space - Play/Pause
            if !hasCommand && !hasOption {
                onPlayPause()
            }
            
        case 36: // Return - Stop
            if !hasCommand {
                onStop()
            }
            
        case 51: // Delete - Clear pattern
            if hasCommand {
                onClear()
            }
            
        case 8: // C - Copy
            if hasCommand {
                sequencer.copyPattern()
            }
            
        case 9: // V - Paste
            if hasCommand {
                sequencer.pastePattern()
            }
            
        case 18...21, 23, 26, 22, 28: // Number keys 1-8 (toggle row visibility/solo)
            let rowIndex = keyCodeToNumber(event.keyCode)
            if hasOption && rowIndex < sequencer.pattern.lanes.count {
                // Option + number = solo that lane
                let laneId = sequencer.pattern.lanes[rowIndex].id
                sequencer.toggleSolo(laneId: laneId)
            } else if hasCommand && rowIndex < sequencer.pattern.lanes.count {
                // Command + number = mute that lane
                let laneId = sequencer.pattern.lanes[rowIndex].id
                sequencer.toggleMute(laneId: laneId)
            }
            
        case 125: // Down arrow - decrease swing
            if hasOption {
                sequencer.setSwing(sequencer.pattern.swing - 0.1)
            }
            
        case 126: // Up arrow - increase swing
            if hasOption {
                sequencer.setSwing(sequencer.pattern.swing + 0.1)
            }
            
        default:
            break
        }
    }
    
    private func keyCodeToNumber(_ keyCode: UInt16) -> Int {
        switch keyCode {
        case 18: return 0  // 1
        case 19: return 1  // 2
        case 20: return 2  // 3
        case 21: return 3  // 4
        case 23: return 4  // 5
        case 22: return 5  // 6
        case 26: return 6  // 7
        case 28: return 7  // 8
        default: return -1
        }
    }
    
    class KeyCaptureView: NSView {
        var onKeyDown: ((NSEvent) -> Void)?
        
        override var acceptsFirstResponder: Bool { true }
        
        override func keyDown(with event: NSEvent) {
            onKeyDown?(event)
        }
    }
}

