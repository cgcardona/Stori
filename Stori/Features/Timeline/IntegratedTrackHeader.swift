//
//  IntegratedTrackHeader.swift
//  Stori
//
//  Extracted from IntegratedTimelineView.swift
//  Contains the track header view with controls, sliders, and automation
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Track Drag Data

/// Data transferred during track drag and drop for reordering
struct TrackDragData: Codable, Transferable {
    let trackId: UUID
    let sourceIndex: Int

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .trackDragData)
    }
}

extension UTType {
    static let trackDragData = UTType(exportedAs: "com.tellurstori.track-drag-data",
                                      conformingTo: .data)
}

// MARK: - Integrated Track Header

struct IntegratedTrackHeader: View {
    let trackId: UUID  // Store ID instead of track snapshot
    @Binding var selectedTrackId: UUID?  // Direct binding for reactive updates
    @Binding var selectedTrackIds: Set<UUID>  // Multi-selection support
    let height: CGFloat
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    let onSelect: (EventModifiers) -> Void
    let onDelete: () -> Void
    let onRename: (String) -> Void
    let onNewAudioTrack: () -> Void
    let onNewMIDITrack: () -> Void
    let onMoveTrack: (Int, Int) -> Void  // Source index, destination index
    
    // Computed property that will refresh when selectedTrackId binding changes
    private var isSelected: Bool {
        selectedTrackId == trackId || selectedTrackIds.contains(trackId)
    }
    
    // Computed property to get current track state reactively
    // NOTE: Read from projectManager (single source of truth) for proper SwiftUI updates
    private var audioTrack: AudioTrack {
        return projectManager.currentProject?.tracks.first { $0.id == trackId }
            ?? AudioTrack(name: "Unknown", color: .gray)
    }
    
    // Computed property to get track index (1-based for display)
    private var trackNumber: Int {
        if let tracks = projectManager.currentProject?.tracks,
           let index = tracks.firstIndex(where: { $0.id == trackId }) {
            return index + 1  // 1-based numbering
        }
        return 1
    }
    
    @State private var showingIconPicker = false
    @State private var showingColorPicker = false
    
    // Track color options for menu
    private var trackColorOptions: [(name: String, color: TrackColor)] {
        [
            ("Blue", .blue),
            ("Red", .red),
            ("Green", .green),
            ("Yellow", .yellow),
            ("Purple", .purple),
            ("Pink", .pink),
            ("Orange", .orange),
            ("Teal", .teal),
            ("Indigo", .indigo),
            ("Gray", .gray)
        ]
    }
    
    /// Set track color
    private func setTrackColor(_ color: TrackColor) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        project.tracks[trackIndex].color = color
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    /// Duplicate the current track
    private func duplicateTrack() {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        
        let originalTrack = project.tracks[trackIndex]
        
        // Create a new track with copied properties
        var newTrack = AudioTrack(
            name: "\(originalTrack.name) Copy",
            trackType: originalTrack.trackType,
            color: originalTrack.color,
            iconName: originalTrack.iconName
        )
        
        // Copy mixer settings
        newTrack.mixerSettings = originalTrack.mixerSettings
        newTrack.sends = originalTrack.sends
        newTrack.voicePreset = originalTrack.voicePreset
        newTrack.automationLanes = originalTrack.automationLanes
        newTrack.automationMode = originalTrack.automationMode
        newTrack.pluginConfigs = originalTrack.pluginConfigs
        newTrack.inputSource = originalTrack.inputSource
        newTrack.outputDestination = originalTrack.outputDestination
        
        // Copy regions with new IDs
        newTrack.regions = originalTrack.regions.map { region in
            AudioRegion(
                audioFile: region.audioFile,
                startBeat: region.startBeat,
                durationBeats: region.durationBeats,
                tempo: projectManager.currentProject?.tempo ?? 120.0,
                fadeIn: region.fadeIn,
                fadeOut: region.fadeOut,
                gain: region.gain,
                isLooped: region.isLooped,
                offset: region.offset
            )
        }
        
        // Copy MIDI regions with new IDs
        newTrack.midiRegions = originalTrack.midiRegions.map { region in
            MIDIRegion(
                id: UUID(),
                name: newTrack.name,  // Use new track's name (regions display track name)
                notes: region.notes,
                startBeat: region.startBeat,
                durationBeats: region.durationBeats,
                instrumentId: region.instrumentId,
                color: region.color,
                isLooped: region.isLooped,
                loopCount: region.loopCount,
                isMuted: region.isMuted,
                controllerEvents: region.controllerEvents,
                pitchBendEvents: region.pitchBendEvents,
                contentLengthBeats: region.contentLengthBeats
            )
        }
        
        // Insert after the original track
        project.tracks.insert(newTrack, at: trackIndex + 1)
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Update audio engine
        if let updatedProject = projectManager.currentProject {
            audioEngine.loadProject(updatedProject)
        }
    }
    
    // MARK: - Column-Based Layout (DAW-style alignment)
    // All rows follow the same left/middle/right structure for visual consistency
    private let leftCol: CGFloat = 122   // MSRI + AI buttons (5 buttons * 20px + 4 gaps * 4px = 116px + 6px margin)
    private let midCol: CGFloat = 88     // Volume slider
    private let rightCol: CGFloat = 52   // Pan knob (32px knob + margins)
    private let colSpacing: CGFloat = 6  // Uniform spacing between columns
    // Total: 23px (track#) + 44px (icon) + 122+88+52 (content) + 2*6px spacing = ~347px (headerWidth)
    
    // Track index for drag/drop
    private var trackIndex: Int {
        projectManager.currentProject?.tracks.firstIndex(where: { $0.id == trackId }) ?? 0
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Track number column on far left
            VStack(spacing: 0) {
                // Small colored accent at top
                Rectangle()
                    .fill(audioTrack.color.color)
                    .frame(height: 4)
                
                // Track number - centered both horizontally and vertically
                Text("\(trackNumber)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: 23)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            
            // Track icon - centered vertically
            ZStack(alignment: .bottomTrailing) {
                trackIconOrImage
                    .frame(width: 44, height: height)
                
                // Chevron for expandable sub-tracks
                // TODO: Only show when track has sub-tracks
                Image(systemName: "chevron.right")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .offset(x: -4, y: -4)
                    .opacity(0) // Hidden for now - will show when folder tracks are implemented
            }
            
            // Main content with 2-3 rows (depending on automation state) - column aligned
            VStack(spacing: audioTrack.automationExpanded ? 13 : 4) {  // Slightly more spacing when automation enabled
                // Row 1: Identity (track name) - ALWAYS shown
                identityRow
                    .frame(height: audioTrack.automationExpanded ? 16 : 26)
                
                // Row 2: Transport & Mixer (changes based on automation state)
                transportMixerRow
                    .frame(height: audioTrack.automationExpanded ? 16 : 24)
                
                // Row 3: Automation controls row (only when automation enabled)
                if audioTrack.automationExpanded {
                    automationControlsRow
                        .frame(height: 16)
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, audioTrack.automationExpanded ? 4 : 6)  // Sacrifice 2px top when automation enabled
            .padding(.bottom, audioTrack.automationExpanded ? 4 : 6)  // Sacrifice 2px bottom when automation enabled
        }
        .frame(height: height)
        .background(trackRowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            // Use NSApp.currentEvent to check modifiers without blocking drop targets
            let flags = NSApp.currentEvent?.modifierFlags ?? []
            if flags.contains(.command) {
                onSelect([.command])
            } else if flags.contains(.shift) {
                onSelect([.shift])
            } else {
                onSelect([])
            }
        }
        .contextMenu {
            Button("Delete Track\(selectedTrackIds.count > 1 ? "s" : "")") {
                onDelete()
            }
            .keyboardShortcut(.delete, modifiers: .command)
            
            if selectedTrackIds.count == 1 {
                Button("Rename Track...") {
                    onRename(audioTrack.name)
                }
                
                Button("Duplicate Track") {
                    duplicateTrack()
                }
                .keyboardShortcut("d", modifiers: .command)
            }
            
            Divider()
            
            // Track color picker
            Button("Assign Track Color...") {
                showingColorPicker = true
            }
            
            Divider()
            
            Button("New Audio Track") {
                onNewAudioTrack()
            }
            .keyboardShortcut("a", modifiers: [.shift, .command])
            
            Button("New MIDI Track") {
                onNewMIDITrack()
            }
            .keyboardShortcut("m", modifiers: [.shift, .command])
        }
        .sheet(isPresented: $showingColorPicker) {
            TrackColorPickerView(
                selectedColor: audioTrack.color,
                onSelectColor: { color in
                    setTrackColor(color)
                    showingColorPicker = false
                }
            )
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
    }
    
    private var trackColor: Color {
        // Use the track's assigned color
        return audioTrack.color.color
    }
    
    private var trackIcon: String {
       // First check for explicit icon override
        if let explicitIcon = audioTrack.iconName, !explicitIcon.isEmpty {
            return explicitIcon
        }
        
        // Use track type icon for MIDI/Instrument tracks
        if audioTrack.isMIDITrack {
            return audioTrack.trackTypeIcon
        }

        return defaultIconName(for: audioTrack.name)
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
    
    /// Badge label for track type (shown for MIDI/Instrument tracks)
    private var trackTypeBadge: some View {
        Group {
            if audioTrack.isMIDITrack {
                Text(audioTrack.trackType == .midi ? "MIDI" : "INST")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(audioTrack.trackType == .midi ? Color.purple : Color.teal)
                    )
            }
        }
    }

    private func selectTrackIcon(_ icon: String) {
        // Capture old icon for undo
        let oldIcon = trackIcon
        
        // Register undo before applying change
        if oldIcon != icon {
            UndoService.shared.registerTrackIconChange(audioTrack.id, from: oldIcon, to: icon, projectManager: projectManager)
        }
        
        // Update both project manager and audio engine
        projectManager.updateTrackIcon(audioTrack.id, icon)
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Force audio engine to sync with updated project
        if let project = projectManager.currentProject {
            audioEngine.updateProjectData(project)
        }
    }
    
    private var recordButton: some View {
        Button(action: {
            // Toggle record enable for track
            let newState = !audioTrack.mixerSettings.isRecordEnabled
            audioEngine.updateTrackRecordEnable(audioTrack.id, newState)
            
            // Mirror into PM so other views relying on projectManager also update
            if var p = projectManager.currentProject,
               let idx = p.tracks.firstIndex(where: { $0.id == audioTrack.id }) {
                p.tracks[idx].mixerSettings.isRecordEnabled = newState
                projectManager.currentProject = p
                projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
            }
        }) {
            Text("R")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(
                    audioTrack.mixerSettings.isRecordEnabled ? .white :  // Active: white text
                    (isSelected ? Color.red : .secondary)  // Selected track: red, else gray
                )
                .frame(width: 20, height: 20)
                .background(audioTrack.mixerSettings.isRecordEnabled ? Color.red : Color.clear)  // Active: red bg
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            audioTrack.mixerSettings.isRecordEnabled ? .red :  // Active: red border
                            (isSelected ? Color.red : .gray),  // Selected track: red, else gray
                            lineWidth: 1
                        )
                )
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .help("Record Enable")
    }
    
    private var muteButton: some View {
        Button(action: {
            let newState = !audioTrack.mixerSettings.isMuted
            // Register undo for mute toggle (Issue #71)
            UndoService.shared.registerMuteToggle(
                audioTrack.id,
                wasMuted: audioTrack.mixerSettings.isMuted,
                projectManager: projectManager,
                audioEngine: audioEngine
            )
            audioEngine.updateTrackMute(trackId: audioTrack.id, isMuted: newState)
        }) {
            Text("M")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(audioTrack.mixerSettings.isMuted ? .white : .secondary)
                .frame(width: 20, height: 20)
                .background(audioTrack.mixerSettings.isMuted ? .orange : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(audioTrack.mixerSettings.isMuted ? .orange : .gray, lineWidth: 1)
                )
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .help("Mute")
    }
    
    private var soloButton: some View {
        Button(action: {
            let newState = !audioTrack.mixerSettings.isSolo
            // Register undo for solo toggle (Issue #71)
            UndoService.shared.registerSoloToggle(
                audioTrack.id,
                wasSolo: audioTrack.mixerSettings.isSolo,
                projectManager: projectManager,
                audioEngine: audioEngine
            )
            audioEngine.updateTrackSolo(trackId: audioTrack.id, isSolo: newState)
        }) {
            Text("S")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(audioTrack.mixerSettings.isSolo ? .black : .secondary)
                .frame(width: 20, height: 20)
                .background(audioTrack.mixerSettings.isSolo ? .yellow : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(audioTrack.mixerSettings.isSolo ? .yellow : .gray, lineWidth: 1)
                )
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .help("Solo")
    }
    
    // MARK: - Row 1: Identity Row
    
    private var identityRow: some View {
        HStack(spacing: 0) {
            // Track Name spans all columns for max width
            EditableTrackName(
                trackId: trackId,
                projectManager: projectManager,
                font: .system(size: 13, weight: .semibold),
                foregroundColor: .primary,
                alignment: .leading,
                lineLimit: 1,
                truncationMode: .tail
            )
            .alignmentGuide(.leading) { d in d[.leading] }
            
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
    
    /// Track icon button or track image thumbnail
    private var trackIconOrImage: some View {
        Group {
            // Show track image if available, otherwise show icon
            if let _ = audioTrack.imageAssetPath,
               let imageURL = projectManager.getTrackImageURL(trackId),
               let image = NSImage(contentsOf: imageURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(audioTrack.color.color, lineWidth: 1)
                    )
                    .help("Track Image")
            } else {
                Button(action: {
                    showingIconPicker.toggle()
                }) {
                    Image(systemName: trackIcon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(audioTrack.color.color)
                        .frame(width: 24, height: 24)
                        .background(audioTrack.color.color.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingIconPicker, arrowEdge: .bottom) {
                    TrackIconPicker(selectedIcon: .constant(trackIcon)) { icon in
                        selectTrackIcon(icon)
                        showingIconPicker = false
                    }
                }
                .help("Track Icon - Click to change")
            }
        }
    }
    
    // MARK: - Row 2: Transport & Mixer Row
    
    private var transportMixerRow: some View {
        HStack(spacing: colSpacing) {
            // LEFT COLUMN - MSRI + AI buttons (always visible)
            HStack(spacing: 4) {
                muteButton
                soloButton
                recordButton
                inputMonitorButton
            }
            .frame(width: leftCol, alignment: .leading)
            
            // MIDDLE COLUMN - Volume slider (always here)
            Slider(
                value: Binding<Double>(
                    get: { Double(audioTrack.mixerSettings.volume) },
                    set: { newValue in
                        let floatValue = Float(newValue)
                        // Register undo for volume change (Issue #71)
                        let oldValue = audioTrack.mixerSettings.volume
                        UndoService.shared.registerVolumeChange(
                            audioTrack.id,
                            from: oldValue,
                            to: floatValue,
                            projectManager: projectManager,
                            audioEngine: audioEngine
                        )
                        audioEngine.updateTrackVolume(trackId: audioTrack.id, volume: floatValue)
                    }
                ),
                in: 0.0...1.0
            )
            .controlSize(.mini)
            .help("Volume")
            .frame(width: midCol, alignment: .leading)
            
            // RIGHT COLUMN - Pan knob (always here)
            HStack(spacing: 0) {
                Spacer(minLength: 2)
                ChannelPanKnob(
                    value: Binding<Float>(
                        get: { audioTrack.mixerSettings.pan * 2 - 1 },
                        set: { newValue in
                            let panValue = (newValue + 1) / 2
                            // Register undo for pan change (Issue #71)
                            let oldValue = audioTrack.mixerSettings.pan
                            UndoService.shared.registerPanChange(
                                audioTrack.id,
                                from: oldValue,
                                to: panValue,
                                projectManager: projectManager,
                                audioEngine: audioEngine
                            )
                            audioEngine.updateTrackPan(trackId: audioTrack.id, pan: panValue)
                        }
                    ),
                    size: 32,
                    onChange: {}
                )
                Spacer(minLength: 10)
            }
            .frame(width: rightCol, alignment: .center)
        }
    }
    
    /// Input monitor button (I)
    private var inputMonitorButton: some View {
        Button(action: {
            toggleInputMonitor()
        }) {
            Text("I")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(
                    audioTrack.inputMonitorEnabled ? .black :  // Active: black text (cyan bg)
                    (isSelected ? Color.orange : .secondary)  // Selected track: orange, else gray
                )
                .frame(width: 20, height: 20)
                .background(audioTrack.inputMonitorEnabled ? Color.cyan : Color.clear)  // Active: cyan bg
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(
                            audioTrack.inputMonitorEnabled ? .cyan :  // Active: cyan border
                            (isSelected ? Color.orange : .gray),  // Selected track: orange, else gray
                            lineWidth: 1
                        )
                )
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .help("Input Monitor")
    }
    
    private func toggleInputMonitor() {
        guard var project = projectManager.currentProject,
              let idx = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        project.tracks[idx].inputMonitorEnabled.toggle()
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    // MARK: - Row 3: Automation Controls Row (shown when automation enabled)
    
    private var automationControlsRow: some View {
        HStack(spacing: colSpacing) {
            // Column 1: Green "Read" dropdown for automation mode (aligns with MSRI+AI)
            HStack(spacing: 0) {
                AutomationModeButton(
                    mode: Binding(
                        get: { audioTrack.automationMode },
                        set: { _ in }
                    ),
                    trackId: trackId,
                    projectManager: projectManager
                )
                Spacer(minLength: 0)
            }
            .frame(width: leftCol)
            
            // Column 2: Yellow "Volume" parameter dropdown (aligns with volume slider)
            HStack(spacing: 0) {
                automationParameterPicker
                Spacer(minLength: 0)
            }
            .frame(width: midCol)
            
            // Column 3: Blue "Track" selector for Track/Region mode (aligns with pan knob)
            HStack(spacing: 0) {
                Menu {
                    Button(action: {}) {
                        Text("Track  ✓")
                    }
                    Button(action: {}) {
                        Text("Region")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Track")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue)
                    )
                }
                .menuStyle(.borderlessButton)
                .help("Automation Target")
                Spacer(minLength: 0)
            }
            .frame(width: rightCol)
        }
    }
    
    // MARK: - Old Automation Actions Row (legacy, keep for reference)
    
    private var automationActionsRow: some View {
        HStack(spacing: colSpacing) {
            // LEFT COLUMN - Chevron (collapse/expand automation lanes)
            AutomationDisclosureButton(
                trackId: trackId,
                projectManager: projectManager
            )
            .frame(width: leftCol, alignment: .leading)
            
            // MIDDLE + RIGHT COLUMNS - Active parameter label or add parameter button
            if !audioTrack.automationLanes.isEmpty {
                HStack(spacing: 4) {
                    Text(audioTrack.automationLanes.first?.parameter.rawValue ?? "")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.green)
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .frame(width: midCol + rightCol, alignment: .leading)
            } else {
                Color.clear.frame(width: midCol + rightCol)
            }
        }
    }
    
    /// Dropdown to select which automation parameter lane to show/edit
    private var automationParameterPicker: some View {
        Menu {
            Section("Mixer") {
                ForEach(AutomationParameter.mixerParameters, id: \.self) { param in
                    Button(action: { addOrSelectLane(param) }) {
                        let isActive = activeAutomationParameter == param
                        Label {
                            Text(param.rawValue + (isActive ? "  ✓" : ""))
                        } icon: {
                            Image(systemName: param.icon)
                        }
                    }
                }
            }
            
            if audioTrack.isMIDITrack {
                Section("Synth") {
                    ForEach(AutomationParameter.synthParameters, id: \.self) { param in
                        Button(action: { addOrSelectLane(param) }) {
                            let isActive = activeAutomationParameter == param
                            Label {
                                Text(param.rawValue + (isActive ? "  ✓" : ""))
                            } icon: {
                                Image(systemName: param.icon)
                            }
                        }
                    }
                }
            }
        } label: {
            // Muted/dark background with yellow text
            HStack(spacing: 4) {
                Text(activeAutomationParameter.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.95, green: 0.85, blue: 0.3))  // Yellow text
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(red: 0.25, green: 0.25, blue: 0.25))  // Dark muted background
            )
        }
        .menuStyle(.borderlessButton)
        .help("Select Automation Parameter")
    }
    
    /// Currently active automation parameter (first visible lane or Volume)
    private var activeAutomationParameter: AutomationParameter {
        audioTrack.automationLanes.first(where: { $0.isVisible })?.parameter ?? .volume
    }
    
    private func hasLaneFor(_ param: AutomationParameter) -> Bool {
        audioTrack.automationLanes.contains(where: { $0.parameter == param })
    }
    
    /// Get the automation value at a specific beat position (for slider real-time display)
    private func getAutomationValue(for parameter: AutomationParameter, track: AudioTrack, atBeat beat: Double) -> Float? {
        // Visibility only affects UI display, not slider animation - check all lanes
        guard let lane = track.automationLanes.first(where: { $0.parameter == parameter }),
              !lane.points.isEmpty else {
            return nil
        }
        
        let sortedPoints = lane.sortedPoints
        
        // Before first point - return slider value (nil = use mixer setting)
        guard let first = sortedPoints.first else { return nil }
        if beat < first.beat { return nil }
        
        // After last point - return slider value (nil = use mixer setting)
        guard let last = sortedPoints.last else { return nil }
        if beat > last.beat { return nil }
        
        // Find surrounding points and interpolate
        for i in 0..<sortedPoints.count - 1 {
            let p1 = sortedPoints[i]
            let p2 = sortedPoints[i + 1]
            
            if beat >= p1.beat && beat <= p2.beat {
                // Linear interpolation between points
                let t = (beat - p1.beat) / (p2.beat - p1.beat)
                return p1.value + Float(t) * (p2.value - p1.value)
            }
        }
        
        // At a point exactly
        if let exactPoint = sortedPoints.first(where: { abs($0.beat - beat) < 0.001 }) {
            return exactPoint.value
        }
        
        return nil
    }
    
    private func addOrSelectLane(_ param: AutomationParameter) {
        guard var project = projectManager.currentProject,
              let idx = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        
        // Hide ALL lanes first
        for i in 0..<project.tracks[idx].automationLanes.count {
            project.tracks[idx].automationLanes[i].isVisible = false
        }
        
        // If lane doesn't exist, create it (visible by default)
        if let laneIdx = project.tracks[idx].automationLanes.firstIndex(where: { $0.parameter == param }) {
            // Lane exists - make it visible
            project.tracks[idx].automationLanes[laneIdx].isVisible = true
        } else {
            // Create new lane with initialValue from mixer for deterministic playback before first point
            let track = project.tracks[idx]
            var newLane = AutomationLane(
                parameter: param,
                points: [],
                initialValue: track.mixerValue(for: param),
                color: param.color
            )
            newLane.isVisible = true
            project.tracks[idx].automationLanes.append(newLane)
        }
        
        // Expand automation view
        project.tracks[idx].automationExpanded = true
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Update audio engine with new lane data
        audioEngine.updateTrackAutomation(project.tracks[idx])
    }
    
    private var trackRowBackground: some View {
        let backgroundColor = isSelected ? Color.blue.opacity(0.1) : Color.clear
        return Rectangle()
            .fill(backgroundColor)
            .overlay(
                Rectangle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5),
                alignment: .bottom
            )
    }
}

// MARK: - Track Color Picker View

struct TrackColorPickerView: View {
    let selectedColor: TrackColor
    let onSelectColor: (TrackColor) -> Void
    
    // Color grid with variations (light to dark)
    private let colorGrid: [[TrackColor]] = [
        // Row 1: Light pastels
        [
            .custom("#FF9999"), .custom("#FFB366"), .custom("#FFD966"), .custom("#99FF99"),
            .custom("#66D9FF"), .custom("#9999FF"), .custom("#FF99FF"), .custom("#FFCCFF")
        ],
        // Row 2: Medium bright
        [
            .red, .orange, .yellow, .green,
            .teal, .blue, .indigo, .purple
        ],
        // Row 3: Standard
        [
            .custom("#CC0000"), .custom("#FF6600"), .custom("#CCCC00"), .custom("#00CC00"),
            .custom("#00CCCC"), .custom("#0066CC"), .custom("#6633CC"), .custom("#CC00CC")
        ],
        // Row 4: Dark variants
        [
            .custom("#990000"), .custom("#CC5500"), .custom("#999900"), .custom("#009900"),
            .custom("#009999"), .custom("#004499"), .custom("#552299"), .custom("#990099")
        ],
        // Row 5: Very dark
        [
            .custom("#660000"), .custom("#883300"), .custom("#666600"), .custom("#006600"),
            .custom("#006666"), .custom("#003366"), .custom("#331166"), .custom("#660066")
        ],
        // Row 6: Grays
        [
            .custom("#FFFFFF"), .custom("#CCCCCC"), .custom("#999999"), .gray,
            .custom("#555555"), .custom("#333333"), .custom("#111111"), .custom("#000000")
        ]
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Color")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            // Color grid
            VStack(spacing: 6) {
                ForEach(0..<colorGrid.count, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(colorGrid[row], id: \.self) { color in
                            Button {
                                onSelectColor(color)
                            } label: {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(color.color)
                                    .frame(width: 32, height: 24)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(
                                                selectedColor == color ? Color.white : Color.clear,
                                                lineWidth: selectedColor == color ? 2 : 0
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.vertical)
        .frame(width: 350)
    }
}
