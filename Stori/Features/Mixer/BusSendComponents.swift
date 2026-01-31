//
//  BusSendComponents.swift
//  Stori
//
//  Bus send control components for professional mixer interface
//

import SwiftUI

// MARK: - Bus Send Control Component
struct BusSendControl: View {
    let bus: MixerBus
    @Binding var sendLevel: Double
    let onRemove: () -> Void
    
    @State private var showingBusDetails = false
    
    var body: some View {
        HStack(spacing: 4) {
            // Bus Type Icon
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.blue)
                .frame(width: 16, height: 16)
            
            // Send Level Knob
            RotaryKnob(
                value: $sendLevel,
                range: 0...1,
                size: 20
            )
            
            // Bus Name (truncated)
            Text(bus.name)
                .font(.system(size: 8))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 30)
            
            Spacer()
            
            // Remove/Edit Button
            Button(action: { showingBusDetails.toggle() }) {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Bus Options")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(busTypeColor.opacity(0.1))
        )
        .contextMenu {
            Button("Edit Bus") {
                showingBusDetails = true
            }
            Button("Remove Send", role: .destructive) {
                onRemove()
            }
        }
    }
    
    private var busTypeColor: Color {
        // Use a generic blue color for all buses since types are removed
        return .blue
    }
}

// MARK: - Bus Type Icon Component
// BusTypeIcon removed - using generic bus icon instead

// MARK: - Professional Bus Creation Dialog
struct ProfessionalBusCreationDialog: View {
    @Binding var isPresented: Bool
    let onCreateBus: (String) -> UUID
    
    @State private var busName: String = ""
    @State private var isHovered = false
    
    var body: some View {
        VStack(spacing: 24) {
            headerSection
            
            Divider()
                .background(busGradient.opacity(0.3))
            
            configurationSection
            
            Divider()
                .background(busGradient.opacity(0.3))
            
            actionButtonsSection
        }
        .padding(28)
        .frame(width: 480)
        .background(dialogBackground)
        .onAppear {
            busName = ""
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.title2)
                    .foregroundStyle(busGradient)
                
                Text("Create New Bus")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            Text("Add a new audio bus for effects processing and routing")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var configurationSection: some View {
        VStack(spacing: 20) {
            busNameInput
            
            Text("Effects can be added to the bus after creation")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var busNameInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bus Name")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            TextField("Enter bus name", text: $busName)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                        .stroke(busGradient.opacity(0.3), lineWidth: 1)
                )
                .font(.body)
                .onSubmit {
                    // Create bus when Enter/Return is pressed
                    let finalName = busName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let busName = finalName.isEmpty ? "Bus" : finalName
                    let _ = onCreateBus(busName)
                    isPresented = false
                }
        }
    }
    
    // busTypeSelection removed - buses are now generic
    
    private var actionButtonsSection: some View {
        HStack(spacing: 16) {
            cancelButton
            createButton
        }
    }
    
    private var cancelButton: some View {
        Button("Cancel") {
            isPresented = false
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
        .foregroundColor(.secondary)
    }
    
    private var createButton: some View {
        Button(action: {
            let finalName = busName.trimmingCharacters(in: .whitespacesAndNewlines)
            let busName = finalName.isEmpty ? "Bus" : finalName
            let _ = onCreateBus(busName)
            isPresented = false
        }) {
            Text("Create Bus")
                .foregroundColor(.white)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(busGradient)
                .shadow(color: Color.blue.opacity(0.3), radius: isHovered ? 6 : 3)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
    
    private var dialogBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.windowBackgroundColor))
            .stroke(busGradient.opacity(0.2), lineWidth: 1)
            .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
    }
    
    private var busGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.8),
                Color.purple.opacity(0.8),
                Color.pink.opacity(0.8)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Send Slot Component (Professional DAW Style)
struct SendSlot: View {
    let sendIndex: Int
    let track: AudioTrack
    let availableBuses: [MixerBus]
    let audioEngine: AudioEngine  // Add AudioEngine reference
    var projectManager: ProjectManager  // Add for undo support
    let onCreateBus: (String) -> UUID  // Returns the created bus ID
    let onAssignBus: (UUID) -> Void
    let onUpdateTrack: (AudioTrack) -> Void  // Add callback to update track
    
    @State private var showingBusMenu = false
    @State private var assignedBusId: UUID?
    @State private var sendLevel: Double = 0.0
    @State private var isPreFader: Bool = false
    @State private var sendPan: Float = 0.0
    @State private var isMuted: Bool = false
    @State private var showingPanControl: Bool = false
    
    // Undo state tracking
    @State private var sendLevelBeforeDrag: Double = 0.0
    
    var body: some View {
        HStack(spacing: 2) {
            // Send Label
            Text("S\(sendIndex + 1)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 16)
            
            // Send Assignment Button/Display
            Button(action: { 
                if assignedBusId == nil {
                    // Show bus creation modal (professional DAW style)
                    showingBusMenu.toggle()
                } else {
                    showingBusMenu.toggle()
                }
            }) {
                HStack(spacing: 2) {
                    if let busId = assignedBusId,
                       let bus = availableBuses.first(where: { $0.id == busId }) {
                        // Show assigned bus
                        Image(systemName: "waveform.path.ecg")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.blue)
                            .frame(width: 8, height: 8)
                        
                        Text(bus.name)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        // Show empty slot
                        Text("---")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(assignedBusId != nil ? Color.accentColor.opacity(0.1) : Color.clear)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help(assignedBusId == nil ? "Create New Aux" : "Change Bus Assignment")
            
            // Send Level Knob and Pre/Post Fader Toggle (only visible if bus is assigned)
            if assignedBusId != nil {
                // Mute button
                Button(action: {
                    let wasMuted = isMuted
                    isMuted.toggle()
                    if let busId = assignedBusId {
                        updateTrackSendMuted(busId: busId, isMuted: isMuted)
                        // Register undo
                        UndoService.shared.registerSendMuteChange(track.id, sendIndex: sendIndex, busId: busId, wasMuted: wasMuted, projectManager: projectManager, audioEngine: audioEngine)
                    }
                }) {
                    Text("M")
                        .font(.system(size: 6, weight: .bold))
                        .foregroundColor(isMuted ? .white : .secondary)
                        .frame(width: 10, height: 10)
                        .background(
                            Circle()
                                .fill(isMuted ? Color.orange : Color.clear)
                                .stroke(Color.secondary.opacity(0.5), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help(isMuted ? "Send Muted" : "Mute Send")
                
                // Pre/Post Fader Toggle
                Button(action: {
                    let wasPreFader = isPreFader
                    isPreFader.toggle()
                    if let busId = assignedBusId {
                        updateTrackSendPreFader(busId: busId, isPreFader: isPreFader)
                        // Register undo
                        UndoService.shared.registerSendPreFaderChange(track.id, sendIndex: sendIndex, busId: busId, wasPreFader: wasPreFader, projectManager: projectManager)
                    }
                }) {
                    Text(isPreFader ? "P" : "o")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(isPreFader ? .white : .secondary)
                        .frame(width: 10, height: 10)
                        .background(
                            Circle()
                                .fill(isPreFader ? Color.orange : Color.clear)
                                .stroke(Color.secondary.opacity(0.5), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help(isPreFader ? "Pre-Fader (before track volume)" : "Post-Fader (after track volume)")
                
                // Send level knob
                RotaryKnob(
                    value: $sendLevel,
                    range: 0...1,
                    size: 12,
                    onDragStart: { initialValue in
                        sendLevelBeforeDrag = initialValue
                    },
                    onDragEnd: { finalValue in
                        if let busId = assignedBusId {
                            // Register undo with the values from before/after drag
                            UndoService.shared.registerSendLevelChange(track.id, sendIndex: sendIndex, busId: busId, from: sendLevelBeforeDrag, to: finalValue, projectManager: projectManager, audioEngine: audioEngine)
                        }
                    }
                )
                .onChange(of: sendLevel) { _, newValue in
                    if let busId = assignedBusId {
                        // Update audio engine send level
                        audioEngine.updateTrackSendLevel(track.id, busId: busId, level: newValue)
                        
                        // CRITICAL FIX: Update the track's sends array in the data model
                        updateTrackSendLevel(busId: busId, level: newValue)
                    }
                }
            }
        }
        .popover(isPresented: $showingBusMenu, arrowEdge: .trailing) {
            SendBusSelectionMenu(
                availableBuses: availableBuses,
                onSelectBus: { busId in
                    assignedBusId = busId
                    onAssignBus(busId)
                    // Setup audio routing
                    audioEngine.setupTrackSend(track.id, to: busId, level: sendLevel)
                    showingBusMenu = false
                },
                onCreateBus: { busName in
                    let newBusId = onCreateBus(busName)
                    // Auto-assign the newly created bus to this send slot
                    assignedBusId = newBusId
                    onAssignBus(newBusId)
                    // Setup audio routing
                    audioEngine.setupTrackSend(track.id, to: newBusId, level: sendLevel)
                    showingBusMenu = false
                    return newBusId
                },
                onClearBus: assignedBusId != nil ? {
                    // Remove the send routing
                    if let busId = assignedBusId {
                        audioEngine.removeTrackSend(track.id, from: busId)
                        
                        // Clear the track's send at this index
                        var updatedTrack = track
                        if sendIndex < updatedTrack.sends.count {
                            updatedTrack.sends.remove(at: sendIndex)
                            onUpdateTrack(updatedTrack)
                        }
                    }
                    assignedBusId = nil
                    sendLevel = 0.0
                    showingBusMenu = false
                } : nil
            )
            .frame(minWidth: 250, maxWidth: 300)
        }
        .contextMenu {
            if let busId = assignedBusId {
                // Pan control section
                Menu("Send Pan") {
                    Button("Left") {
                        sendPan = -1.0
                        updateTrackSendPan(busId: busId, pan: -1.0)
                    }
                    Button("Center") {
                        sendPan = 0.0
                        updateTrackSendPan(busId: busId, pan: 0.0)
                    }
                    Button("Right") {
                        sendPan = 1.0
                        updateTrackSendPan(busId: busId, pan: 1.0)
                    }
                }
                
                Divider()
                
                Toggle(isPreFader ? "Pre-Fader (before volume)" : "Post-Fader (after volume)", isOn: $isPreFader)
                    .onChange(of: isPreFader) { _, newValue in
                        updateTrackSendPreFader(busId: busId, isPreFader: newValue)
                    }
                
                Toggle("Mute Send", isOn: $isMuted)
                    .onChange(of: isMuted) { _, newValue in
                        updateTrackSendMuted(busId: busId, isMuted: newValue)
                    }
                
                Divider()
                
                Button("Remove Send", role: .destructive) {
                    audioEngine.removeTrackSend(track.id, from: busId)
                    var updatedTrack = track
                    if sendIndex < updatedTrack.sends.count {
                        updatedTrack.sends.remove(at: sendIndex)
                        onUpdateTrack(updatedTrack)
                    }
                    assignedBusId = nil
                    sendLevel = 0.0
                }
            } else {
                Button("Assign Bus...") {
                    showingBusMenu = true
                }
            }
        }
        .onAppear {
            // Initialize send state from track's sends array
            // Note: Audio routing is already set up during project load in setupBusesForProject
            // We only need to restore the UI state here, NOT re-establish audio routing
            // Calling setupTrackSend here would cause double-connection with different bus input indices
            if sendIndex < track.sends.count {
                let trackSend = track.sends[sendIndex]
                if trackSend.busId != UUID() { // Check if it's not a placeholder UUID
                    assignedBusId = trackSend.busId
                    sendLevel = trackSend.sendLevel
                    isPreFader = trackSend.isPreFader
                    sendPan = trackSend.pan
                    isMuted = trackSend.isMuted
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    private func updateTrackSendLevel(busId: UUID, level: Double) {
        var updatedTrack = track
        
        // Ensure the sends array has enough slots
        while updatedTrack.sends.count <= sendIndex {
            updatedTrack.sends.append(TrackSend(busId: UUID()))
        }
        
        // Update the send level in the track's sends array
        if updatedTrack.sends[sendIndex].busId == busId {
            let oldSend = updatedTrack.sends[sendIndex]
            updatedTrack.sends[sendIndex] = TrackSend(
                busId: busId,
                sendLevel: level,
                isPreFader: oldSend.isPreFader,
                pan: oldSend.pan,
                isMuted: oldSend.isMuted
            )
            onUpdateTrack(updatedTrack)
        }
    }
    
    private func updateTrackSendPreFader(busId: UUID, isPreFader: Bool) {
        var updatedTrack = track
        
        // Ensure the sends array has enough slots
        while updatedTrack.sends.count <= sendIndex {
            updatedTrack.sends.append(TrackSend(busId: UUID()))
        }
        
        // Update the pre-fader setting in the track's sends array
        if updatedTrack.sends[sendIndex].busId == busId {
            let oldSend = updatedTrack.sends[sendIndex]
            updatedTrack.sends[sendIndex] = TrackSend(
                busId: busId,
                sendLevel: oldSend.sendLevel,
                isPreFader: isPreFader,
                pan: oldSend.pan,
                isMuted: oldSend.isMuted
            )
            onUpdateTrack(updatedTrack)
            // Note: Pre-fader routing would need AudioEngine implementation to actually change signal path
        }
    }
    
    private func updateTrackSendMuted(busId: UUID, isMuted: Bool) {
        var updatedTrack = track
        
        // Ensure the sends array has enough slots
        while updatedTrack.sends.count <= sendIndex {
            updatedTrack.sends.append(TrackSend(busId: UUID()))
        }
        
        // Update the muted setting in the track's sends array
        if updatedTrack.sends[sendIndex].busId == busId {
            let oldSend = updatedTrack.sends[sendIndex]
            updatedTrack.sends[sendIndex] = TrackSend(
                busId: busId,
                sendLevel: oldSend.sendLevel,
                isPreFader: oldSend.isPreFader,
                pan: oldSend.pan,
                isMuted: isMuted
            )
            onUpdateTrack(updatedTrack)
            
            // Update AudioEngine - mute the send by setting level to 0 or restore
            if isMuted {
                audioEngine.updateTrackSendLevel(track.id, busId: busId, level: 0.0)
            } else {
                audioEngine.updateTrackSendLevel(track.id, busId: busId, level: oldSend.sendLevel)
            }
        }
    }
    
    private func updateTrackSendPan(busId: UUID, pan: Float) {
        var updatedTrack = track
        
        // Ensure the sends array has enough slots
        while updatedTrack.sends.count <= sendIndex {
            updatedTrack.sends.append(TrackSend(busId: UUID()))
        }
        
        // Update the pan setting in the track's sends array
        if updatedTrack.sends[sendIndex].busId == busId {
            let oldSend = updatedTrack.sends[sendIndex]
            updatedTrack.sends[sendIndex] = TrackSend(
                busId: busId,
                sendLevel: oldSend.sendLevel,
                isPreFader: oldSend.isPreFader,
                pan: pan,
                isMuted: oldSend.isMuted
            )
            onUpdateTrack(updatedTrack)
            
            // Note: Send pan would need AudioEngine implementation for stereo send routing
        }
    }
}

// MARK: - Send Bus Selection Menu
struct SendBusSelectionMenu: View {
    let availableBuses: [MixerBus]
    let onSelectBus: (UUID) -> Void
    let onCreateBus: (String) -> UUID  // Returns the created bus ID
    let onClearBus: (() -> Void)?  // Optional: Clear the bus assignment
    
    @State private var showingCreateBus = false
    
    init(availableBuses: [MixerBus], onSelectBus: @escaping (UUID) -> Void, onCreateBus: @escaping (String) -> UUID, onClearBus: (() -> Void)? = nil) {
        self.availableBuses = availableBuses
        self.onSelectBus = onSelectBus
        self.onCreateBus = onCreateBus
        self.onClearBus = onClearBus
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Bus")
                .font(.headline)
                .padding(.horizontal)
            
            Divider()
            
            // Clear Bus Option (if callback provided)
            if let clearAction = onClearBus {
                Button(action: clearAction) {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red)
                            .frame(width: 16, height: 16)
                        
                        Text("Remove from Send")
                            .font(.body)
                            .foregroundColor(.red)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                
                Divider()
            }
            
            // Available Buses
            if !availableBuses.isEmpty {
                Text("Available Buses")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal)
                
                ForEach(availableBuses) { bus in
                    Button(action: { onSelectBus(bus.id) }) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.blue)
                                .frame(width: 16, height: 16)
                            
                            Text(bus.name)
                                .font(.body)
                            
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                    )
                    .onHover { isHovered in
                        // Add hover effect if needed
                    }
                }
                
                Divider()
            }
            
            // Create New Bus
            Button(action: { showingCreateBus = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.accentColor)
                    
                    Text("Create New Bus")
                        .font(.body)
                    
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .frame(minWidth: 200)
        .padding(.vertical, 8)
        .sheet(isPresented: $showingCreateBus) {
            ProfessionalBusCreationDialog(
                isPresented: $showingCreateBus,
                onCreateBus: { busName in
                    return onCreateBus(busName)
                }
            )
            .presentationDetents([.medium])
        }
    }
}

