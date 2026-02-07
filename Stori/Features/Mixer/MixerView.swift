//
//  MixerView.swift
//  Stori
//
//  Professional mixer interface with industry-standard architecture
//

import SwiftUI

struct MixerView: View {
    // PERFORMANCE: Changed from @ObservedObject to regular var
    // MixerView only CALLS methods on audioEngine, doesn't need to observe its state
    // Observing caused re-renders on every position update (30 FPS)
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    @Binding var selectedTrackId: UUID?
    
    // PERFORMANCE: Pass graph stability as parameter to avoid reading from audioEngine
    let isGraphStable: Bool
    
    // Get project from projectManager to stay in sync with timeline views
    private var project: AudioProject? {
        projectManager.currentProject
    }
    
    @State private var isMonitoringLevels = false
    @State private var showingBusCreation = false
    
    // Professional mixer controls
    @State private var globalChannelWidth: ChannelStripWidth = .standard
    @State private var showTracks = true
    @State private var showBuses = true
    @State private var searchQuery = ""
    
    // Meter data provider - @Observable for fine-grained updates
    @State private var meterProvider = MeterDataProvider()
    
    private var buses: [MixerBus] {
        project?.buses ?? []
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Wait for audio graph to be stable before rendering mixer
            // This prevents crashes from UI enumerating nodes during graph mutations
            if !isGraphStable {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Building audio graph...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.windowBackgroundColor))
            } else {
                mixerContent
            }
        }
    }
    
    @ViewBuilder
    private var mixerContent: some View {
        VStack(spacing: 0) {
            // Professional Mixer Toolbar
            professionalMixerToolbar
            
            // Channel Strips Area
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    if let project = project {
                        // Track Channel Strips (filtered by search)
                        if showTracks {
                            ForEach(filteredTracks(from: project.tracks)) { track in
                                ProfessionalChannelStrip(
                                    track: track,
                                    buses: buses,
                                    groups: project.groups,
                                    selectedTrackId: $selectedTrackId,
                                    audioEngine: audioEngine,
                                    projectManager: projectManager,
                                    meterData: meterProvider.meterData(for: track.id),
                                    onSelect: { selectedTrackId = track.id },
                                    onCreateBus: { name in createBus(name: name) },
                                    onRemoveBus: { busId in removeBus(busId) },
                                    displayWidth: track.channelStripWidth
                                )
                                .id("\(track.id)-promixer-\(selectedTrackId?.uuidString ?? "none")")
                            }
                        }
                        
                        // Visual separator between tracks and buses
                        if showTracks && showBuses && !filteredBuses.isEmpty {
                            mixerSectionDivider(label: "BUSES")
                        }
                        
                        // Bus Channel Strips (filtered by search)
                        if showBuses {
                            ForEach(filteredBuses) { bus in
                                BusChannelStrip(
                                    bus: bus,
                                    audioEngine: audioEngine,
                                    projectManager: projectManager,
                                    project: project,
                                    onDelete: { deleteBus(bus) }
                                )
                            }
                        }
                        
                        // Visual separator before master
                        mixerSectionDivider(label: "MASTER")
                        
                        // Master Channel Strip
                        ProfessionalMasterChannelStrip(
                            audioEngine: audioEngine,
                            projectManager: projectManager,
                            meterData: meterProvider.masterMeterData
                        )
                    } else {
                        EmptyMixerView()
                    }
                }
                .padding(.horizontal, 8)
            }
            .background(Color(.controlBackgroundColor))
        }
        .onAppear {
            isMonitoringLevels = true
            meterProvider.startMonitoring(audioEngine: audioEngine, projectManager: projectManager)
        }
        .onDisappear {
            isMonitoringLevels = false
            meterProvider.stopMonitoring()
        }
        .sheet(isPresented: $showingBusCreation) {
            ProfessionalBusCreationDialog(
                isPresented: $showingBusCreation,
                onCreateBus: { busName in
                    return createBus(name: busName)
                }
            )
        }
    }
    
    // MARK: - Professional Mixer Toolbar
    private var professionalMixerToolbar: some View {
        HStack(spacing: 12) {
            // Title
            Text("Mixer")
                .font(.headline)
                .fontWeight(.semibold)
            
            Divider()
                .frame(height: 16)
            
            // Filter toggles
            HStack(spacing: 6) {
                FilterToggle(label: "All", isOn: Binding(
                    get: { showTracks && showBuses },
                    set: { if $0 { showTracks = true; showBuses = true } }
                ))
                FilterToggle(label: "Tracks", isOn: $showTracks)
                FilterToggle(label: "Buses", isOn: $showBuses)
            }
            
            Divider()
                .frame(height: 16)
            
            // Search field
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                TextField("Filter...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 80)
                if !searchQuery.isEmpty {
                    Button(action: { searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(.textBackgroundColor))
            .cornerRadius(4)
            
            Divider()
                .frame(height: 16)
            
            // Channel width selector
            Menu {
                ForEach(ChannelStripWidth.allCases, id: \.self) { width in
                    Button(action: { setGlobalChannelWidth(width) }) {
                        HStack {
                            Text(width.rawValue)
                            if globalChannelWidth == width {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 11))
                    Text(globalChannelWidth.rawValue)
                        .font(.system(size: 11))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Add Bus menu
            Menu {
                Button("Create New Bus...") {
                    showingBusCreation = true
                }
                
                if let trackId = selectedTrackId,
                   let track = project?.tracks.first(where: { $0.id == trackId }) {
                    Button("Create Bus from '\(track.name)'") {
                        createBusFromSelectedTrack()
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 12))
                    Text("Add Bus")
                        .font(.system(size: 11))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Create New Bus")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(.separatorColor)),
            alignment: .bottom
        )
    }
    
    // MARK: - Section Divider
    private func mixerSectionDivider(label: String? = nil) -> some View {
        VStack(spacing: 2) {
            if let label = label {
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20)
            }
            
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(width: 2)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
    }
    
    // MARK: - Filtering
    private func filteredTracks(from tracks: [AudioTrack]) -> [AudioTrack] {
        guard !searchQuery.isEmpty else { return tracks }
        return tracks.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }
    
    private var filteredBuses: [MixerBus] {
        guard !searchQuery.isEmpty else { return buses }
        return buses.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }
    
    private func setGlobalChannelWidth(_ width: ChannelStripWidth) {
        globalChannelWidth = width
        
        // Apply to all tracks
        guard var project = projectManager.currentProject else { return }
        for i in 0..<project.tracks.count {
            project.tracks[i].channelStripWidth = width
        }
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    private func createBus(name: String) -> UUID {
        let newBus = MixerBus(name: name)
        
        // Add to project and save
        if var currentProject = project {
            currentProject.buses.append(newBus)
            currentProject.modifiedAt = Date()
            projectManager.currentProject = currentProject
            projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
            
            // Add to audio engine
            audioEngine.addBus(newBus)
        }
        
        return newBus.id
    }
    
    /// Create a bus from the currently selected track
    /// Auto-assigns a send from the track to the new bus
    private func createBusFromSelectedTrack() {
        guard let trackId = selectedTrackId,
              var currentProject = project,
              let trackIndex = currentProject.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        
        let track = currentProject.tracks[trackIndex]
        
        // Create bus with name based on track
        let busName = "\(track.name) Bus"
        let newBus = MixerBus(name: busName)
        
        // Add bus to project
        currentProject.buses.append(newBus)
        
        // Create a send from the track to the new bus
        let newSend = TrackSend(busId: newBus.id, sendLevel: 0.75, isPreFader: false)
        currentProject.tracks[trackIndex].sends.append(newSend)
        
        // Save project
        currentProject.modifiedAt = Date()
        projectManager.currentProject = currentProject
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Add to audio engine and establish routing
        audioEngine.addBus(newBus)
        audioEngine.setupTrackSend(trackId, to: newBus.id, level: 0.75)
        
    }
    
    private func removeBus(_ busId: UUID) {
        guard var currentProject = project else { return }
        
        // CRITICAL: Clean up sends from all tracks that reference this bus
        for i in 0..<currentProject.tracks.count {
            currentProject.tracks[i].sends.removeAll { $0.busId == busId }
        }
        
        // Remove the bus itself
        currentProject.buses.removeAll { $0.id == busId }
        currentProject.modifiedAt = Date()
        projectManager.currentProject = currentProject
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Remove from audio engine (also cleans up audio routing)
        audioEngine.removeBus(withId: busId)
        
    }
    
    private func deleteBus(_ bus: MixerBus) {
        removeBus(bus.id)
    }
}

// MARK: - Track Channel Strip
struct TrackChannelStrip: View {
    let trackId: UUID  // Store ID instead of track snapshot
    let buses: [MixerBus]
    @Binding var selectedTrackId: UUID?  // Direct binding for reactive updates
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    let onSelect: () -> Void
    let onCreateBus: (String) -> UUID  // Returns the created bus ID
    let onRemoveBus: (UUID) -> Void
    
    // Computed property that will refresh when selectedTrackId binding changes
    private var isSelected: Bool {
        selectedTrackId == trackId
    }
    
    // Computed property to get current track state reactively
    private var track: AudioTrack {
        projectManager.currentProject?.tracks.first { $0.id == trackId } ?? AudioTrack(name: "Unknown", color: .gray)
    }
    
    @State private var showingSends = true
    @State private var sendLevels: [UUID: Double] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Track Header
            trackHeaderSection
            
            // Enhanced Sends Section (conditional visibility)
            if showingSends {
                enhancedSendsSection
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
            }
            
            // Fader Section (with more space)
            faderSection
            
            // Mute/Solo Buttons (professional style at bottom)
            muteSoloSection
            
            // Track Name (compact at very bottom)
            trackNameSection
        }
        .frame(width: 80)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
        )
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Show Sends") {
                showingSends.toggle()
            }
            Divider()
            Button("Reset Track") { }
            Button("Duplicate Track") { }
        }
    }
    
    private var trackHeaderSection: some View {
        VStack(spacing: 4) {
            // Track Icon with Editable Color
            ZStack {
                EditableTrackColor(
                    trackId: trackId,
                    projectManager: projectManager,
                    width: 20,
                    height: 20,
                    cornerRadius: 10 // Make it circular
                )
                
                Image(systemName: "waveform")
                    .font(.system(size: 8))
                    .foregroundColor(.white)
                    .allowsHitTesting(false) // Allow taps to pass through to color picker
            }
            
            // Sends Toggle
            Button(action: { 
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingSends.toggle()
                }
            }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(showingSends ? 180 : 0)) // Smooth chevron rotation
            }
            .buttonStyle(.plain)
            .help("Toggle Sends")
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Professional DAW Style Sends Section
    private var enhancedSendsSection: some View {
        VStack(spacing: 2) {
            // Sends Header
            Text("SENDS")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.bottom, 2)
            
            // Send Slots (up to 8 sends like professional DAWs)
            ForEach(0..<8, id: \.self) { sendIndex in
                SendSlot(
                    sendIndex: sendIndex,
                    track: track,
                    availableBuses: buses,
                    audioEngine: audioEngine,  // Pass AudioEngine reference
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
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.15))
        )
        .padding(.horizontal, 4)
    }
    
    // MARK: - Bus Management Methods
    private func showBusCreationMenu() {
        // For now, create a default reverb bus
        // TODO: Show proper bus creation menu
        onCreateBus("Bus \(buses.count + 1)")
    }
    
    private func removeBusSend(_ busId: UUID) {
        sendLevels.removeValue(forKey: busId)
        onRemoveBus(busId)
    }
    
    private func assignBusToSend(sendIndex: Int, busId: UUID) {
        // Update the track's send assignment in the data model
        var updatedTrack = track
        
        let newSend = TrackSend(busId: busId, sendLevel: 0.0, isPreFader: false)
        
        // Ensure the sends array has enough slots
        while updatedTrack.sends.count <= sendIndex {
            updatedTrack.sends.append(TrackSend(busId: UUID(), sendLevel: 0.0, isPreFader: false))
        }
        
        // Assign the bus to the specific send slot
        updatedTrack.sends[sendIndex] = newSend
        
        // Update the project with the modified track
        projectManager.updateTrack(updatedTrack)
        
        // Initialize send level for UI state
        sendLevels[busId] = 0.0
        
        // Setup audio routing
        audioEngine.setupTrackSend(track.id, to: busId, level: 0.0)
    }
    
    
    private var faderSection: some View {
        VStack(spacing: 4) {
            // Level Display - show volume in dB
            Text(volumeDisplayText)
                .font(.caption2)
                .foregroundColor(.secondary)
                .monospacedDigit()  // Keep digits aligned
            
            // Vertical Fader (taller for better visibility)
            VerticalFader(
                value: Binding(
                    get: { Double(track.mixerSettings.volume) },
                    set: { newValue in
                        // Register undo for volume change (Issue #71)
                        let oldValue = track.mixerSettings.volume
                        UndoService.shared.registerVolumeChange(
                            track.id,
                            from: oldValue,
                            to: Float(newValue),
                            projectManager: projectManager,
                            audioEngine: audioEngine
                        )
                        // AudioEngine.updateTrackVolume() handles both audio AND project model updates
                        // This avoids triggering the onChange listener that reloads the entire audio engine
                        audioEngine.updateTrackVolume(trackId: track.id, volume: Float(newValue))
                    }
                ),
                height: 160
            )
            
            Text("-∞")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Volume Display Helper
    private var volumeDisplayText: String {
        let volume = track.mixerSettings.volume
        
        // Convert linear volume (0.0-1.0) to decibels
        if volume <= 0.0001 {
            return "-∞"
        } else {
            let dB = 20 * log10(volume)
            if dB >= -0.5 {
                return "0.0"  // Show 0.0 for unity gain
            } else {
                return String(format: "%.1f", dB)
            }
        }
    }
    
    // MARK: - Mute/Solo Section (Professional DAW Style)
    private var muteSoloSection: some View {
        HStack(spacing: 2) {
                // Mute Button
                Button(action: {
                    let newState = !track.mixerSettings.isMuted
                    // Register undo for mute toggle (Issue #71)
                    UndoService.shared.registerMuteToggle(
                        track.id,
                        wasMuted: track.mixerSettings.isMuted,
                        projectManager: projectManager,
                        audioEngine: audioEngine
                    )
                    audioEngine.updateTrackMute(trackId: track.id, isMuted: newState)
                }) {
                Text("M")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(track.mixerSettings.isMuted ? .white : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(track.mixerSettings.isMuted ? .orange : Color(.controlBackgroundColor))
                    )
                }
                .buttonStyle(.plain)
                .help("Mute Track")
            
            // Solo Button  
            Button(action: {
                let newState = !track.mixerSettings.isSolo
                // Register undo for solo toggle (Issue #71)
                UndoService.shared.registerSoloToggle(
                    track.id,
                    wasSolo: track.mixerSettings.isSolo,
                    projectManager: projectManager,
                    audioEngine: audioEngine
                )
                audioEngine.updateTrackSolo(trackId: track.id, isSolo: newState)
            }) {
                Text("S")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(track.mixerSettings.isSolo ? .black : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(track.mixerSettings.isSolo ? .yellow : Color(.controlBackgroundColor))
                    )
            }
            .buttonStyle(.plain)
            .help("Solo Track")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }
    
    private var trackNameSection: some View {
        VStack(spacing: 2) {
            EditableTrackName(
                trackId: trackId,
                projectManager: projectManager,
                font: .system(size: 9, weight: .medium),
                foregroundColor: .primary,
                alignment: .center,
                lineLimit: 1,
                truncationMode: .tail
            )
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

// MARK: - Bus Channel Strip
struct BusChannelStrip: View {
    let bus: MixerBus
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    let project: AudioProject?
    let onDelete: () -> Void
    
    @State private var showingEffects = false
    @State private var isEditingName = false
    @State private var editedName: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Bus Header
            busHeaderSection
            
            // Scrollable AudioFX Section
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    // AudioFX Section (always visible like professional DAWs)
                    audioFXSection
                }
                .padding(.horizontal, 4)
            }
            .frame(maxHeight: .infinity)
            
            Spacer(minLength: 4)
            
            // Return Fader
            returnFaderSection
            
            // Bus Name
            busNameSection
        }
        .frame(width: 90)  // Match standard track channel width
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.controlBackgroundColor))
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
        )
        .contextMenu {
            Button("Add Effect") {
                showingEffects = true
            }
            Divider()
            Button("Delete Bus", role: .destructive) {
                onDelete()
            }
        }
    }
    
    private var busHeaderSection: some View {
        VStack(spacing: 4) {
            // Bus Icon
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.blue)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                )
            
            // Effects Toggle
            Button(action: { showingEffects.toggle() }) {
                Image(systemName: "fx")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Toggle Effects")
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Professional DAW Style AudioFX Section
    private var audioFXSection: some View {
        BusInsertsSection(
            busId: bus.id,
            pluginChain: audioEngine.getBusPluginChain(for: bus.id),
            availableTracks: project?.tracks ?? [],
            availableBuses: project?.buses ?? [],
            onAddPlugin: { slot, descriptor in
                Task {
                    do {
                        try await audioEngine.insertBusPlugin(
                            busId: bus.id,
                            descriptor: descriptor,
                            atSlot: slot
                        )
                    } catch {
                        #if DEBUG
                        print("Failed to add bus plugin: \(error)")
                        #endif
                    }
                }
            },
            onToggleBypass: { slot in
                if let plugin = audioEngine.getBusPluginChain(for: bus.id)?.slots[slot] {
                    plugin.setBypass(!plugin.isBypassed)
                }
            },
            onRemoveEffect: { slot in
                audioEngine.removeBusPlugin(busId: bus.id, atSlot: slot)
            },
            onOpenEditor: { slot in
                audioEngine.openBusPluginEditor(busId: bus.id, slot: slot)
            }
        )
    }
    
    private var returnFaderSection: some View {
        VStack(spacing: 4) {
            Text("Return")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Return Level Display
            Text(String(format: "%.1f", bus.outputLevel * 100))
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Vertical Return Fader
            VerticalFader(
                value: Binding(
                    get: { bus.outputLevel },
                    set: { newValue in
                        // Update audio engine (it handles project update and notification)
                        audioEngine.updateBusOutputLevel(bus.id, outputLevel: newValue)
                    }
                ),
                height: 160
            )
            
            Text("-∞")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private var busNameSection: some View {
        VStack(spacing: 4) {
            if isEditingName {
                TextField("Bus Name", text: $editedName, onCommit: {
                    commitBusNameEdit()
                })
                .textFieldStyle(.plain)
                .font(.caption)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .frame(height: 30)
                .padding(.horizontal, 4)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(4)
                .onExitCommand {
                    isEditingName = false
                }
            } else {
                Text(bus.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(height: 30)
                    .onTapGesture(count: 2) {
                        editedName = bus.name
                        isEditingName = true
                    }
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
    
    private func commitBusNameEdit() {
        guard !editedName.isEmpty, editedName != bus.name else {
            isEditingName = false
            return
        }
        
        // Update the bus name in the project
        if var currentProject = projectManager.currentProject,
           let busIndex = currentProject.buses.firstIndex(where: { $0.id == bus.id }) {
            currentProject.buses[busIndex].name = editedName
            currentProject.modifiedAt = Date()
            projectManager.currentProject = currentProject
            projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        }
        
        isEditingName = false
    }
}

// MARK: - Empty Mixer View
struct EmptyMixerView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Project Loaded")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Create or open a project to use the mixer")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Supporting Views

// Rotary Knob Component
struct RotaryKnob: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let size: CGFloat
    var onDragStart: ((Double) -> Void)? = nil  // Called when drag starts with initial value
    var onDragEnd: ((Double) -> Void)? = nil    // Called when drag ends with final value
    
    @State private var isDragging = false
    @State private var lastDragValue: CGFloat = 0
    @State private var valueAtDragStart: Double = 0
    
    private var normalizedValue: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
    
    private var angle: Double {
        normalizedValue * 270 - 135 // -135° to +135°
    }
    
    var body: some View {
        ZStack {
            // Knob background
            Circle()
                .fill(Color(.controlBackgroundColor))
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
            
            // Knob indicator
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: size * 0.3)
                .offset(y: -size * 0.25)
                .rotationEffect(.degrees(angle))
            
            // Center dot
            Circle()
                .fill(Color.primary)
                .frame(width: 3, height: 3)
        }
        .frame(width: size, height: size)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        lastDragValue = gesture.translation.height
                        valueAtDragStart = value
                        onDragStart?(value)
                    }
                    
                    let delta = (lastDragValue - gesture.translation.height) * 0.01
                    let newValue = max(range.lowerBound, min(range.upperBound, value + delta))
                    
                    if newValue != value {
                        value = newValue
                    }
                    
                    lastDragValue = gesture.translation.height
                }
                .onEnded { _ in
                    isDragging = false
                    // Only call onDragEnd if value actually changed
                    if abs(value - valueAtDragStart) > 0.001 {
                        onDragEnd?(value)
                    }
                }
        )
    }
}

// Vertical Fader Component
struct VerticalFader: View {
    @Binding var value: Double
    let height: CGFloat
    var onDragStart: ((Double) -> Void)? = nil  // Called when drag starts with initial value
    var onDragEnd: ((Double) -> Void)? = nil    // Called when drag ends with final value
    
    @State private var isDragging = false
    @State private var valueAtDragStart: Double = 0
    
    private var normalizedValue: Double {
        max(0, min(1, value))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Track
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 6)
                    .cornerRadius(3)
                
                // Fill
                Rectangle()
                    .fill(LinearGradient(
                        colors: [.green, .yellow, .red],
                        startPoint: .bottom,
                        endPoint: .top
                    ))
                    .frame(width: 6, height: geometry.size.height * CGFloat(normalizedValue))
                    .cornerRadius(3)
                
                // Thumb
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                    .stroke(Color.accentColor, lineWidth: 1)
                    .frame(width: 20, height: 8)
                    .offset(y: -geometry.size.height * CGFloat(normalizedValue) + 4)
            }
            .frame(maxWidth: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            valueAtDragStart = value
                            onDragStart?(value)
                        }
                        let newValue = 1 - (gesture.location.y / geometry.size.height)
                        let clampedValue = max(0, min(1, newValue))
                        value = clampedValue
                    }
                    .onEnded { _ in
                        isDragging = false
                        // Only call onDragEnd if value actually changed
                        if abs(value - valueAtDragStart) > 0.001 {
                            onDragEnd?(value)
                        }
                    }
            )
        }
        .frame(height: height)
    }
}


// MARK: - Supporting Models
// MixerBus, BusEffect, BusType and EffectType are now defined in AudioModels.swift

// MARK: - Custom UI Components

struct HSliderView: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let onChange: (Float) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)
                    .cornerRadius(2)
                
                // Fill
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(normalizedValue), height: 4)
                    .cornerRadius(2)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .offset(x: geometry.size.width * CGFloat(normalizedValue) - 8)
            }
            .frame(maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = Float(gesture.location.x / geometry.size.width)
                        let clampedValue = max(range.lowerBound, min(range.upperBound, 
                            range.lowerBound + newValue * (range.upperBound - range.lowerBound)))
                        
                        value = clampedValue
                        onChange(clampedValue)
                    }
            )
        }
    }
    
    private var normalizedValue: Float {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

struct KnobView: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let sensitivity: Float
    let onChange: (Float) -> Void
    
    @State private var isDragging = false
    @State private var lastDragValue: CGFloat = 0
    
    init(value: Binding<Float>, range: ClosedRange<Float>, sensitivity: Float = 0.01, onChange: @escaping (Float) -> Void) {
        self._value = value
        self.range = range
        self.sensitivity = sensitivity
        self.onChange = onChange
    }
    
    private var normalizedValue: Float {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
    
    private var angle: Double {
        Double(normalizedValue) * 270 - 135 // -135° to +135°
    }
    
    var body: some View {
        ZStack {
            // Knob background
            Circle()
                .fill(Color(.controlBackgroundColor))
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
            
            // Knob indicator
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: 8)
                .offset(y: -12)
                .rotationEffect(.degrees(angle))
            
            // Center dot
            Circle()
                .fill(Color.primary)
                .frame(width: 4, height: 4)
        }
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        lastDragValue = gesture.translation.height
                    }
                    
                    let delta = (lastDragValue - gesture.translation.height) * CGFloat(sensitivity)
                    let newValue = max(range.lowerBound, min(range.upperBound, value + Float(delta)))
                    
                    if newValue != value {
                        value = newValue
                        onChange(newValue)
                    }
                    
                    lastDragValue = gesture.translation.height
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}
