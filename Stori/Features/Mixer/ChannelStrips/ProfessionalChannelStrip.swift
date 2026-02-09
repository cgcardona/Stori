//
//  ProfessionalChannelStrip.swift
//  Stori
//
//  Professional-tier channel strip with all mixer controls
//  Professional-tier channel strip with all mixer controls
//

import SwiftUI

// MARK: - Professional Channel Strip
struct ProfessionalChannelStrip: View {
    // PERFORMANCE: Accept track directly instead of looking it up
    // This eliminates redundant lookups and avoids observing projectManager
    let track: AudioTrack
    let buses: [MixerBus]
    let groups: [TrackGroup]  // For group indicator display
    @Binding var selectedTrackId: UUID?
    // PERFORMANCE: This view only CALLS methods on audioEngine, no observation needed
    var audioEngine: AudioEngine
    // PERFORMANCE: Changed from @ObservedObject to regular property
    // Track data is now passed directly, projectManager only used for method calls
    var projectManager: ProjectManager
    let meterData: ChannelMeterData
    let onSelect: () -> Void
    let onCreateBus: (String) -> UUID
    let onRemoveBus: (UUID) -> Void
    
    // Display mode
    var displayWidth: ChannelStripWidth = .standard
    
    // Convenience accessor for track ID
    private var trackId: UUID { track.id }
    
    private var isSelected: Bool {
        selectedTrackId == trackId
    }
    
    // Section expansion state - persisted in track model
    private var collapsedSections: Set<ChannelStripSection> {
        track.collapsedSections
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Track Header (color strip + icon)
            trackHeaderSection
            
            // Scrollable content area for all sections
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    // INSTRUMENT Section (MIDI/Instrument tracks only)
                    if displayWidth != .narrow && track.isMIDITrack {
                        instrumentSection
                    }
                    
                    // I/O Section
                    if displayWidth != .narrow {
                        ioSection
                    }
                    
                    // INSERTS Section (labeled "AUDIO FX" for MIDI tracks like Logic)
                    if displayWidth != .narrow {
                        insertsSection
                    }
                    
                    // EQ Section
                    if displayWidth != .narrow {
                        eqSection
                    }
                    
                    // SENDS Section
                    if displayWidth != .narrow {
                        sendsSection
                    }
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: displayWidth == .narrow ? 0 : .infinity)
            
            Spacer(minLength: 4)
            
            // Pan Knob
            panSection
            
            // Fader with Meters
            faderSection
            
            // Transport Controls (M/S/R/I)
            transportSection
            
            // Automation Mode (standard/wide only)
            if displayWidth != .narrow {
                automationSection
            }
            
            // Track Name
            trackNameSection
        }
        .frame(width: displayWidth.width)
        .background(channelBackground)
        .accessibilityIdentifier(AccessibilityID.Mixer.channelStrip(trackId))
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            channelContextMenu
        }
    }
    
    // MARK: - Track Header
    private var trackHeaderSection: some View {
        VStack(spacing: 4) {
            // Group indicator (if track belongs to a group)
            if let groupId = track.groupId,
               let group = groups.first(where: { $0.id == groupId }) {
                HStack(spacing: 2) {
                    Circle()
                        .fill(group.color)
                        .frame(width: 6, height: 6)
                    if displayWidth != .narrow {
                        Text(group.name.prefix(3).uppercased())
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(group.color)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                    Capsule()
                        .fill(group.color.opacity(0.15))
                )
            }
            
            // Color strip
            Rectangle()
                .fill(track.color.color)
                .frame(height: 4)
            
            // Track Icon
            HStack(spacing: 4) {
                Image(systemName: trackIcon)
                    .font(.system(size: 12))
                    .foregroundColor(track.color.color)
                
                if displayWidth == .wide {
                    Text("\(trackIndex + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private var trackIndex: Int {
        projectManager.currentProject?.tracks.firstIndex { $0.id == trackId } ?? 0
    }
    
    private var trackIcon: String {
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
    
    /// AU plugin name from voicePreset (format: "AU:PluginName:Manufacturer").
    private func extractAUNameFromVoicePreset(_ voicePreset: String?) -> String? {
        guard let preset = voicePreset, preset.hasPrefix("AU:") else { return nil }
        let components = preset.split(separator: ":").map(String.init)
        guard components.count >= 2 else { return nil }
        return components[1]
    }
    
    // MARK: - Instrument Section (MIDI/Instrument tracks only)
    @State private var showingInstrumentBrowser = false
    
    private var instrumentSection: some View {
        VStack(spacing: 2) {
            // Section Header
            HStack {
                Text("INSTRUMENT")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(MixerColors.sectionHeader)
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // Instrument Slot
            Button(action: {
                showingInstrumentBrowser = true
            }) {
                HStack(spacing: 4) {
                    // Instrument icon
                    Image(systemName: instrumentIcon)
                        .font(.system(size: 10))
                        .foregroundColor(hasInstrument ? .blue : .secondary)
                    
                    // Instrument name
                    Text(instrumentDisplayName)
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundColor(hasInstrument ? .primary : .secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(hasInstrument ? Color.blue.opacity(0.1) : Color.clear)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showingInstrumentBrowser) {
                UnifiedInstrumentPickerView(
                    onAUInstrumentSelected: { descriptor in
                        loadAUInstrument(descriptor: descriptor)
                    },
                    onGMInstrumentSelected: { gmInstrument in
                        loadGMInstrument(gmInstrument)
                    },
                    currentGMProgram: track.gmProgram,
                    currentAUName: extractAUNameFromVoicePreset(track.voicePreset)
                )
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(MixerColors.slotBackground)
        )
    }
    
    private var hasInstrument: Bool {
        // Check if track has an instrument loaded
        track.voicePreset != nil || track.trackType == .instrument
    }
    
    private var instrumentDisplayName: String {
        if let preset = track.voicePreset {
            return preset
        }
        return "No Instrument"
    }
    
    private var instrumentIcon: String {
        if hasInstrument {
            return "pianokeys"
        }
        return "plus.circle"
    }
    
    private func loadAUInstrument(descriptor: PluginDescriptor) {
        // Load the AU instrument for this track
        // NOTE: Do NOT use @MainActor here - audio graph work should not be on main thread
        Task {
            do {
                try await audioEngine.loadTrackInstrument(trackId: trackId, descriptor: descriptor)
                
                // Update track model with instrument identifier (this needs MainActor)
                await MainActor.run {
                    guard var project = projectManager.currentProject,
                          let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
                    
                    // Clear numeric instrument fields (AU uses voicePreset string with AU: prefix)
                    project.tracks[trackIndex].gmProgram = nil
                    project.tracks[trackIndex].drumKitId = nil
                    project.tracks[trackIndex].synthPresetId = nil
                    // AU identifier is stored in voicePreset with AU: prefix by InstrumentManager
                    project.tracks[trackIndex].voicePreset = "AU:\(descriptor.name):\(descriptor.manufacturer)"
                    project.modifiedAt = Date()
                    projectManager.currentProject = project
                    projectManager.hasUnsavedChanges = true
                }
                
            } catch {
            }
        }
    }
    
    private func loadGMInstrument(_ gmInstrument: GMInstrument) {
        // Load the GM SoundFont instrument for this track
        Task { @MainActor in
            do {
                try await audioEngine.loadTrackGMInstrument(trackId: trackId, instrument: gmInstrument)
                
                // Update track model with numeric program AND display name
                guard var project = projectManager.currentProject,
                      let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
                
                // Clear other instrument fields (mutually exclusive)
                project.tracks[trackIndex].drumKitId = nil
                project.tracks[trackIndex].synthPresetId = nil
                // Set numeric program number (primary identifier)
                project.tracks[trackIndex].gmProgram = gmInstrument.rawValue
                // Set display name (for UI)
                project.tracks[trackIndex].voicePreset = gmInstrument.name
                project.modifiedAt = Date()
                projectManager.currentProject = project
                projectManager.hasUnsavedChanges = true
                
            } catch {
            }
        }
    }
    
    private func loadDrumKit(_ kitName: String) {
        // Load the drum kit for this track
        Task { @MainActor in
            guard var project = projectManager.currentProject,
                  let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
            
            // Clear other instrument fields (mutually exclusive)
            project.tracks[trackIndex].gmProgram = nil
            project.tracks[trackIndex].synthPresetId = nil
            // Set drum kit identifier (primary identifier)
            project.tracks[trackIndex].drumKitId = kitName
            // Set display name (for UI)
            project.tracks[trackIndex].voicePreset = kitName
            project.modifiedAt = Date()
            projectManager.currentProject = project
            projectManager.hasUnsavedChanges = true
            
            // InstrumentManager will create the DrumKitEngine when needed
            // Force recreation of the instrument
            InstrumentManager.shared.removeInstrument(for: trackId)
            _ = InstrumentManager.shared.getOrCreateInstrument(for: trackId)
            
            // Schedule rebuild of track graph to connect drum kit
            audioEngine.scheduleRebuild(trackId: trackId)
            
        }
    }
    
    // MARK: - I/O Section
    private var ioSection: some View {
        IORoutingSection(
            track: track,
            audioEngine: audioEngine,
            projectManager: projectManager,
            isCompact: displayWidth == .standard,
            onUpdateInput: { newInput in
                updateTrackInputSource(newInput)
            },
            onUpdateOutput: { newOutput in
                updateTrackOutputDestination(newOutput)
            },
            onUpdateInputTrim: { newTrim in
                updateTrackInputTrim(newTrim)
            }
        )
    }
    
    // MARK: - Inserts Section
    private var insertsSection: some View {
        let allTracks = projectManager.currentProject?.tracks ?? []
        
        return InsertsSection(
            trackId: trackId,
            pluginChain: audioEngine.getPluginChain(for: trackId),
            sidechainSources: getSidechainSources(),
            availableTracks: allTracks,
            availableBuses: buses,
            onAddPlugin: { slotIndex, descriptor in
                addInsertPlugin(at: slotIndex, descriptor: descriptor)
            },
            onToggleBypass: { slotIndex in
                toggleInsertBypass(at: slotIndex)
            },
            onRemoveEffect: { slotIndex in
                removeInsertEffect(at: slotIndex)
            },
            onOpenEditor: { slotIndex in
                openInsertEditor(at: slotIndex)
            },
            onSetSidechain: { slotIndex, source in
                setSidechainSource(at: slotIndex, source: source)
            }
        )
    }
    
    // Get current sidechain sources for all slots
    private func getSidechainSources() -> [Int: SidechainSource] {
        var sources: [Int: SidechainSource] = [:]
        for slot in 0..<8 {
            let source = audioEngine.getSidechainSource(trackId: trackId, slot: slot)
            if source.isEnabled {
                sources[slot] = source
            }
        }
        return sources
    }
    
    // Set sidechain source for a slot
    private func setSidechainSource(at slotIndex: Int, source: SidechainSource) {
        audioEngine.setSidechainSource(trackId: trackId, slot: slotIndex, source: source)
    }
    
    // MARK: - EQ Section
    private var eqSection: some View {
        EQKnobsSection(
            highEQ: Binding(
                get: { track.mixerSettings.highEQ },
                set: { updateEQ(high: $0) }
            ),
            midEQ: Binding(
                get: { track.mixerSettings.midEQ },
                set: { updateEQ(mid: $0) }
            ),
            lowEQ: Binding(
                get: { track.mixerSettings.lowEQ },
                set: { updateEQ(low: $0) }
            ),
            isEnabled: Binding(
                get: { track.mixerSettings.eqEnabled },
                set: { updateEQEnabled($0) }
            ),
            onUpdate: { }
        )
        .padding(.horizontal, 2)
    }
    
    // MARK: - Sends Section
    private var sendsSection: some View {
        VStack(spacing: 2) {
            // Section Header
            HStack {
                Text("SENDS")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(MixerColors.sectionHeader)
                Spacer()
            }
            .padding(.horizontal, 4)
            
            // Send Slots
            ForEach(0..<8, id: \.self) { sendIndex in
                SendSlot(
                    sendIndex: sendIndex,
                    track: track,
                    availableBuses: buses,
                    audioEngine: audioEngine,
                    projectManager: projectManager,  // Pass for undo support
                    onCreateBus: onCreateBus,
                    onAssignBus: { busId in
                        assignBusToSend(sendIndex: sendIndex, busId: busId)
                    },
                    onUpdateTrack: { updatedTrack in
                        projectManager.updateTrack(updatedTrack)
                    }
                )
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(MixerColors.slotBackground)
        )
        .padding(.horizontal, 2)
    }
    
    // MARK: - Pan Section
    private var panSection: some View {
        VStack(spacing: 2) {
            if displayWidth == .narrow {
                // Compact pan display for narrow mode
                // Convert 0.0-1.0 range to -1.0 to +1.0 range
                CompactPanDisplay(value: (track.mixerSettings.pan - 0.5) * 2.0)
            } else {
                ChannelPanKnob(
                    value: Binding(
                        get: {
                            // Convert 0.0-1.0 range (stored) to -1.0 to +1.0 range (knob expects)
                            (track.mixerSettings.pan - 0.5) * 2.0
                        },
                        set: { newValue in
                            // Convert -1.0 to +1.0 range (knob provides) to 0.0-1.0 range (stored)
                            let storedValue = (newValue + 1.0) / 2.0
                            // Register undo for pan change (Issue #71)
                            let oldValue = track.mixerSettings.pan
                            UndoService.shared.registerPanChange(
                                trackId,
                                from: oldValue,
                                to: storedValue,
                                projectManager: projectManager,
                                audioEngine: audioEngine
                            )
                            audioEngine.updateTrackPan(trackId: trackId, pan: storedValue)
                        }
                    ),
                    size: displayWidth == .wide ? 36 : 30,
                    onChange: { }
                )
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Fader Section
    private var faderSection: some View {
        ChannelFader(
            value: Binding(
                get: { track.mixerSettings.volume },
                set: { newValue in
                    // Register undo for volume change (Issue #71)
                    let oldValue = track.mixerSettings.volume
                    UndoService.shared.registerVolumeChange(
                        trackId,
                        from: oldValue,
                        to: newValue,
                        projectManager: projectManager,
                        audioEngine: audioEngine
                    )
                    audioEngine.updateTrackVolume(trackId: trackId, volume: newValue)
                }
            ),
            meterLeft: meterData.leftLevel,
            meterRight: meterData.rightLevel,
            peakLeft: meterData.peakLeft,
            peakRight: meterData.peakRight,
            height: displayWidth == .narrow ? 120 : 160,
            showMeter: displayWidth != .narrow,
            onChange: { }
        )
        .padding(.horizontal, displayWidth == .narrow ? 2 : 6)
    }
    
    // MARK: - Transport Section
    private var transportSection: some View {
        HStack(spacing: displayWidth == .narrow ? 2 : 4) {
            // Mute (with group linking)
            ChannelButton(
                label: "M",
                isActive: track.mixerSettings.isMuted,
                activeColor: MixerColors.muteActive,
                size: displayWidth == .narrow ? 16 : 20,
                accessibilityLabel: "Mute",
                accessibilityHint: "Toggle track mute"
            ) {
                toggleGroupedMute()
            }
            .accessibilityIdentifier(AccessibilityID.Mixer.trackMute(trackId))
            
            // Solo with Solo-Safe indicator (with group linking)
            ZStack(alignment: .topTrailing) {
                ChannelButton(
                    label: "S",
                    isActive: track.mixerSettings.isSolo,
                    activeColor: MixerColors.soloActive,
                    size: displayWidth == .narrow ? 16 : 20,
                    accessibilityLabel: "Solo",
                    accessibilityHint: "Toggle track solo"
                ) {
                    toggleGroupedSolo()
                }
                .accessibilityIdentifier(AccessibilityID.Mixer.trackSolo(trackId))
                .contextMenu {
                    Toggle("Solo Safe", isOn: Binding(
                        get: { track.mixerSettings.soloSafe },
                        set: { toggleSoloSafe($0) }
                    ))
                    .help("When enabled, track won't be muted when other tracks solo")
                }
                
                // Solo-Safe indicator dot
                if track.mixerSettings.soloSafe {
                    Circle()
                        .fill(Color.cyan)
                        .frame(width: 5, height: 5)
                        .offset(x: 2, y: -2)
                }
            }
            
            if displayWidth != .narrow {
                // Record Arm
                ChannelButton(
                    label: "R",
                    isActive: track.mixerSettings.isRecordEnabled,
                    activeColor: MixerColors.recordArm,
                    size: 20
                ) {
                    toggleRecordArm()
                }
                .accessibilityIdentifier(AccessibilityID.Mixer.trackRecord(trackId))
                
                // Input Monitor
                ChannelButton(
                    label: "I",
                    isActive: track.inputMonitorEnabled,
                    activeColor: MixerColors.inputMonitor,
                    size: 20
                ) {
                    toggleInputMonitor()
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func toggleSoloSafe(_ enabled: Bool) {
        var updatedTrack = track
        updatedTrack.mixerSettings.soloSafe = enabled
        projectManager.updateTrack(updatedTrack)
    }
    
    // MARK: - Automation Section
    private var automationSection: some View {
        HStack(spacing: 4) {
            Menu {
                ForEach(AutomationMode.allCases, id: \.self) { mode in
                    Button(action: { setAutomationMode(mode) }) {
                        HStack {
                            Text(mode.rawValue)
                            if track.automationMode == mode {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(track.automationMode.shortLabel)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(automationModeColor)
                    
                    // Automation data indicator
                    if track.hasAutomationData {
                        Circle()
                            .fill(automationModeColor)
                            .frame(width: 4, height: 4)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(automationModeColor.opacity(0.15))
                )
            }
            .buttonStyle(.plain)
            .help(track.hasAutomationData 
                  ? "Automation Mode: \(track.automationMode.rawValue) (\(track.automationLaneCount) lane(s) with data)"
                  : "Automation Mode: \(track.automationMode.rawValue)")
        }
        .padding(.vertical, 2)
    }
    
    private func setAutomationMode(_ mode: AutomationMode) {
        var updatedTrack = track
        updatedTrack.automationMode = mode
        projectManager.updateTrack(updatedTrack)
    }
    
    private var automationModeColor: Color {
        switch track.automationMode {
        case .off: return .secondary
        case .read: return .green
        case .touch: return .yellow
        case .latch: return .orange
        case .write: return .red
        }
    }
    
    // MARK: - Track Name Section
    private var trackNameSection: some View {
        VStack(spacing: 2) {
            EditableTrackName(
                trackId: trackId,
                projectManager: projectManager,
                font: .system(size: displayWidth == .narrow ? 8 : 10, weight: .medium),
                foregroundColor: .primary,
                alignment: .center,
                lineLimit: displayWidth == .narrow ? 1 : 2,
                truncationMode: .tail
            )
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }
    
    // MARK: - Channel Background
    private var channelBackground: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(isSelected ? MixerColors.channelSelected : MixerColors.channelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isSelected ? Color.accentColor : Color.clear,
                        lineWidth: isSelected ? 1.5 : 0
                    )
            )
    }
    
    // MARK: - Context Menu
    @ViewBuilder
    private var channelContextMenu: some View {
        Button("Reset Channel Strip") {
            resetChannelStrip()
        }
        
        Divider()
        
        Menu("Channel Width") {
            ForEach(ChannelStripWidth.allCases, id: \.self) { width in
                Button(width.rawValue) {
                    setChannelWidth(width)
                }
            }
        }
        
        Divider()
        
        // Grouping options
        groupingMenu
        
        Divider()
        
        Button("Duplicate Track") {
            // TODO: Implement
        }
        
        Button("Delete Track", role: .destructive) {
            // TODO: Implement
        }
    }
    
    @ViewBuilder
    private var groupingMenu: some View {
        let existingGroups = projectManager.currentProject?.groups ?? []
        let currentGroup = existingGroups.first { $0.id == track.groupId }
        
        Menu("Track Group") {
            // Show current group if any
            if let group = currentGroup {
                Button("Currently in: \(group.name)") { }
                    .disabled(true)
                Divider()
            }
            
            // Create new group
            Button("Create New Group...") {
                createNewGroup()
            }
            
            // Assign to existing groups
            if !existingGroups.isEmpty {
                Divider()
                ForEach(existingGroups) { group in
                    Button(group.name) {
                        assignToGroup(group.id)
                    }
                }
            }
            
            // Remove from group
            if currentGroup != nil {
                Divider()
                Button("Remove from Group", role: .destructive) {
                    removeFromGroup()
                }
            }
        }
    }
    
    private func createNewGroup() {
        guard var project = projectManager.currentProject else { return }
        
        // Create a new group with the track's name
        let newGroup = TrackGroup(name: "\(track.name) Group", color: track.color.color)
        project.groups.append(newGroup)
        
        // Assign this track to the new group
        if let index = project.tracks.firstIndex(where: { $0.id == trackId }) {
            project.tracks[index].groupId = newGroup.id
        }
        
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
    }
    
    private func assignToGroup(_ groupId: UUID) {
        var updatedTrack = track
        updatedTrack.groupId = groupId
        projectManager.updateTrack(updatedTrack)
        
        if let group = projectManager.currentProject?.groups.first(where: { $0.id == groupId }) {
        }
    }
    
    private func removeFromGroup() {
        var updatedTrack = track
        updatedTrack.groupId = nil
        projectManager.updateTrack(updatedTrack)
    }
    
    // MARK: - Grouped Parameter Control
    
    /// Get tracks in the same group as this track
    private var groupedTracks: [AudioTrack] {
        guard let groupId = track.groupId,
              let project = projectManager.currentProject,
              let group = project.groups.first(where: { $0.id == groupId }),
              group.isEnabled else {
            return []
        }
        return project.tracks.filter { $0.groupId == groupId && $0.id != trackId }
    }
    
    /// Get the current group's linked parameters
    private var linkedParameters: Set<GroupLinkedParameter> {
        guard let groupId = track.groupId,
              let group = projectManager.currentProject?.groups.first(where: { $0.id == groupId }) else {
            return []
        }
        return group.linkedParameters
    }
    
    private func toggleGroupedMute() {
        let newMuteState = !track.mixerSettings.isMuted
        
        // Register undo for mute toggle (Issue #71)
        UndoService.shared.registerMuteToggle(
            trackId,
            wasMuted: track.mixerSettings.isMuted,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        
        // Update this track
        audioEngine.updateTrackMute(trackId: trackId, isMuted: newMuteState)
        
        // Update grouped tracks if mute is linked
        if linkedParameters.contains(.mute) {
            for groupedTrack in groupedTracks {
                // Register undo for each grouped track
                UndoService.shared.registerMuteToggle(
                    groupedTrack.id,
                    wasMuted: groupedTrack.mixerSettings.isMuted,
                    projectManager: projectManager,
                    audioEngine: audioEngine
                )
                audioEngine.updateTrackMute(trackId: groupedTrack.id, isMuted: newMuteState)
            }
        }
    }
    
    private func toggleGroupedSolo() {
        let newSoloState = !track.mixerSettings.isSolo
        
        // Register undo for solo toggle (Issue #71)
        UndoService.shared.registerSoloToggle(
            trackId,
            wasSolo: track.mixerSettings.isSolo,
            projectManager: projectManager,
            audioEngine: audioEngine
        )
        
        // Update this track
        audioEngine.updateTrackSolo(trackId: trackId, isSolo: newSoloState)
        
        // Update grouped tracks if solo is linked
        if linkedParameters.contains(.solo) {
            for groupedTrack in groupedTracks {
                // Register undo for each grouped track
                UndoService.shared.registerSoloToggle(
                    groupedTrack.id,
                    wasSolo: groupedTrack.mixerSettings.isSolo,
                    projectManager: projectManager,
                    audioEngine: audioEngine
                )
                audioEngine.updateTrackSolo(trackId: groupedTrack.id, isSolo: newSoloState)
            }
        }
    }
    
    // MARK: - Actions
    
    private func toggleInsertBypass(at index: Int) {
        // Toggle AU plugin bypass
        guard let pluginChain = audioEngine.getPluginChain(for: trackId),
              let plugin = pluginChain.slots[index] else {
            return
        }
        
        audioEngine.setPluginBypass(trackId: trackId, slot: index, bypassed: !plugin.isBypassed)
    }
    
    private func removeInsertEffect(at index: Int) {
        // Remove AU plugin
        guard let pluginChain = audioEngine.getPluginChain(for: trackId),
              let _ = pluginChain.slots[index] else {
            return
        }
        
        audioEngine.removePlugin(trackId: trackId, atSlot: index)
    }
    
    private func addInsertPlugin(at index: Int, descriptor: PluginDescriptor) {
        
        // Load the AU plugin into the track's plugin chain
        Task { @MainActor in
            do {
                try await audioEngine.insertPlugin(
                    trackId: trackId,
                    descriptor: descriptor,
                    atSlot: index,
                    sandboxed: false  // Use in-process for lower latency; set true for crash isolation
                )
            } catch {
            }
        }
    }
    
    private func openInsertEditor(at index: Int) {
        // Check if there's an AU plugin at this slot
        guard let pluginChain = audioEngine.getPluginChain(for: trackId) else {
            return
        }
        
        guard pluginChain.slots[index] != nil else {
            return
        }
        
        // Open AU plugin editor
        audioEngine.openPluginEditor(trackId: trackId, slot: index)
        
        // Note: Built-in AudioEffect types don't have editors yet
    }
    
    private func updateEQ(high: Float? = nil, mid: Float? = nil, low: Float? = nil) {
        if let high = high {
            audioEngine.updateTrackHighEQ(trackId: trackId, value: high)
        }
        if let mid = mid {
            audioEngine.updateTrackMidEQ(trackId: trackId, value: mid)
        }
        if let low = low {
            audioEngine.updateTrackLowEQ(trackId: trackId, value: low)
        }
    }
    
    private func updateEQEnabled(_ enabled: Bool) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].mixerSettings.eqEnabled = enabled
        project.modifiedAt = Date()
        
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        audioEngine.updateTrackEQEnabled(trackId: trackId, enabled: enabled)
    }
    
    // MARK: - I/O Routing Updates
    
    private func updateTrackInputSource(_ inputSource: TrackInputSource) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].inputSource = inputSource
        project.modifiedAt = Date()
        
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // TODO: Update audio engine input routing when implemented
    }
    
    private func updateTrackOutputDestination(_ outputDestination: TrackOutputDestination) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].outputDestination = outputDestination
        project.modifiedAt = Date()
        
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // TODO: Update audio engine output routing when implemented
    }
    
    private func updateTrackInputTrim(_ trim: Float) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].mixerSettings.inputTrim = trim
        project.modifiedAt = Date()
        
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // TODO: Apply input trim in audio engine when implemented
    }
    
    private func assignBusToSend(sendIndex: Int, busId: UUID) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        let newSend = TrackSend(busId: busId, sendLevel: 0.0, isPreFader: false)
        
        while project.tracks[trackIndex].sends.count <= sendIndex {
            project.tracks[trackIndex].sends.append(TrackSend(busId: UUID(), sendLevel: 0.0, isPreFader: false))
        }
        project.tracks[trackIndex].sends[sendIndex] = newSend
        project.modifiedAt = Date()
        
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Setup audio routing
        audioEngine.setupTrackSend(trackId, to: busId, level: 0.0)
    }
    
    private func toggleRecordArm() {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].mixerSettings.isRecordEnabled.toggle()
        project.modifiedAt = Date()
        
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    private func toggleInputMonitor() {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].inputMonitorEnabled.toggle()
        project.modifiedAt = Date()
        
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    private func resetChannelStrip() {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].mixerSettings = MixerSettings()
        project.tracks[trackIndex].pluginConfigs = []
        project.modifiedAt = Date()
        
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        audioEngine.loadProject(project)
    }
    
    private func setChannelWidth(_ width: ChannelStripWidth) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else { return }
        
        project.tracks[trackIndex].channelStripWidth = width
        project.modifiedAt = Date()
        
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
}

// MARK: - Channel Button
struct ChannelButton: View {
    let label: String
    let isActive: Bool
    let activeColor: Color
    let size: CGFloat
    let accessibilityLabel: String?
    let accessibilityHint: String?
    let action: () -> Void
    
    init(
        label: String,
        isActive: Bool,
        activeColor: Color,
        size: CGFloat,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isActive = isActive
        self.activeColor = activeColor
        self.size = size
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundColor(isActive ? (activeColor == MixerColors.soloActive ? .black : .white) : .secondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(isActive ? activeColor : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(isActive ? activeColor : Color.gray.opacity(0.5), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        // ACCESSIBILITY: Mixer channel buttons (Mute/Solo/etc)
        .accessibilityLabel(accessibilityLabel ?? label)
        .accessibilityHint(accessibilityHint ?? "Toggle \(accessibilityLabel ?? label)")
        .accessibilityValue(isActive ? "On" : "Off")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Meter Data Model
struct ChannelMeterData {
    var leftLevel: Float = 0
    var rightLevel: Float = 0
    var peakLeft: Float = 0
    var peakRight: Float = 0
    var isClipping: Bool = false
    
    // Gain Reduction (for compressor/limiter effects)
    var gainReduction: Float = 0  // dB of gain reduction (0 = no compression)
    
    // LUFS Loudness (for master metering)
    var loudnessMomentary: Float = -70  // 400ms window (LUFS)
    var loudnessShortTerm: Float = -70  // 3s window (LUFS)
    var loudnessIntegrated: Float = -70 // Program loudness (LUFS)
    var truePeak: Float = -70           // Inter-sample peak (dBTP)
    
    static let zero = ChannelMeterData()
}
