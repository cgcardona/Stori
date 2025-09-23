//
//  MixerView.swift
//  TellUrStoriDAW
//
//  Professional mixer interface with industry-standard architecture
//

import SwiftUI

struct MixerView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    @Binding var selectedTrackId: UUID?
    
    // Get project from projectManager to stay in sync with timeline views
    private var project: AudioProject? {
        projectManager.currentProject
    }
    
    @State private var isMonitoringLevels = false
    @State private var showingBusCreation = false
    
    private var buses: [MixerBus] {
        project?.buses ?? []
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Mixer Header
            mixerHeaderView
            
            // Channel Strips Area
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 1) {
                    if let project = project {
                        // Track Channel Strips
                        ForEach(project.tracks) { track in
                            TrackChannelStrip(
                                trackId: track.id,
                                buses: buses,
                                selectedTrackId: $selectedTrackId,
                                audioEngine: audioEngine,
                                projectManager: projectManager,
                                onSelect: { selectedTrackId = track.id },
                                onCreateBus: { name in
                                    createBus(name: name)
                                },
                                onRemoveBus: { busId in
                                    removeBus(busId)
                                }
                            )
                            .id("\(track.id)-mixer-\(selectedTrackId?.uuidString ?? "none")")
                        }
                        
                        // Bus Channel Strips
                        ForEach(buses) { bus in
                            BusChannelStrip(
                                bus: bus,
                                audioEngine: audioEngine,
                                projectManager: projectManager,
                                project: project,
                                onDelete: { deleteBus(bus) }
                            )
                        }
                        
                        // Master Channel Strip
                        MasterChannelStrip(
                            audioEngine: audioEngine,
                            projectManager: projectManager
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
            // Level monitoring will be handled by individual channel strips
        }
        .onDisappear {
            isMonitoringLevels = false
            // Level monitoring cleanup handled by individual channel strips
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
    
    private var mixerHeaderView: some View {
        HStack {
            Text("Mixer")
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
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
    
    private func createBus(name: String) -> UUID {
        let newBus = MixerBus(name: name)
        
        // Add to project and save
        if var currentProject = project {
            currentProject.buses.append(newBus)
            currentProject.modifiedAt = Date()
            projectManager.currentProject = currentProject
            projectManager.saveCurrentProject()
            
            // Add to audio engine
            audioEngine.addBus(newBus)
        }
        
        return newBus.id
    }
    
    private func removeBus(_ busId: UUID) {
        guard var currentProject = project else { return }
        currentProject.buses.removeAll { $0.id == busId }
        currentProject.modifiedAt = Date()
        projectManager.currentProject = currentProject
        projectManager.saveCurrentProject()
        
        // Remove from audio engine
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
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
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
    
    @State private var showingSends = false
    @State private var sendLevels: [UUID: Double] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Track Header
            trackHeaderSection
            
            // Enhanced Sends Section (always visible)
            enhancedSendsSection
            
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
            print("🎛️ Mixer Channel Tapped: \(track.name) (\(trackId))")
            onSelect()
            print("🎛️ Mixer Channel Selection Called")
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
            // Track Icon
            Circle()
                .fill(track.color.color)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "waveform")
                        .font(.system(size: 8))
                        .foregroundColor(.white)
                )
            
            // Sends Toggle
            Button(action: { showingSends.toggle() }) {
                Image(systemName: showingSends ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
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
        
        // Create a new TrackSend for this bus assignment
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
        
        print("✅ SEND PERSISTENCE: Assigned bus \(busId) to send slot \(sendIndex) on track \(track.name)")
    }
    
    
    private var faderSection: some View {
        VStack(spacing: 4) {
            // Level Display
            Text("0.0")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Vertical Fader (taller for better visibility)
            VerticalFader(
                value: Binding(
                    get: { Double(track.mixerSettings.volume) },
                    set: { newValue in
                        var updatedTrack = track
                        updatedTrack.mixerSettings.volume = Float(newValue)
                        projectManager.updateTrack(updatedTrack)
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
    
    // MARK: - Mute/Solo Section (Professional DAW Style)
    private var muteSoloSection: some View {
        HStack(spacing: 2) {
                // Mute Button
                Button(action: {
                    let newState = !track.mixerSettings.isMuted
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
            Text(track.name)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

// MARK: - Bus Channel Strip
struct BusChannelStrip: View {
    let bus: MixerBus
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let project: AudioProject?
    let onDelete: () -> Void
    
    @State private var showingEffects = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Bus Header
            busHeaderSection
            
            // AudioFX Section (always visible like professional DAWs)
            audioFXSection
            
            // Return Fader
            returnFaderSection
            
            // Bus Name
            busNameSection
        }
        .frame(width: 80)
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
        VStack(spacing: 2) {
            // AudioFX Header
            Text("AUDIO FX")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.bottom, 2)
            
            // Effect Slots (up to 8 like professional DAWs)
            ForEach(0..<8, id: \.self) { effectIndex in
                EffectSlot(
                    effectIndex: effectIndex,
                    bus: bus,
                    onAddEffect: { effectType in
                        addEffectToBus(effectIndex: effectIndex, effectType: effectType)
                    },
                    onToggleEffect: { effectIndex in
                        toggleEffect(effectIndex: effectIndex)
                    },
                    onUpdateEffect: { effect in
                        updateBusEffect(effect)
                    },
                    onRemoveEffect: { effectId in
                        removeEffectFromBus(effectId)
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
    
    private func addEffectToBus(effectIndex: Int, effectType: EffectType) {
        print("🎛️ MIXER VIEW: Adding \(effectType) to bus \(bus.name) at slot \(effectIndex)")
        
        // Create new effect with default parameters
        let newEffect = BusEffect(
            name: effectType.rawValue.capitalized,
            type: effectType,
            parameters: effectType.defaultParameters,
            presetName: "Default"
        )
        
        // Add effect to project model
        guard var currentProject = project,
              let busIndex = currentProject.buses.firstIndex(where: { $0.id == bus.id }) else {
            print("❌ MIXER VIEW: Failed to find bus in project")
            return
        }
        
        // Add effect to bus
        currentProject.buses[busIndex].effects.append(newEffect)
        currentProject.modifiedAt = Date()
        projectManager.currentProject = currentProject
        projectManager.saveCurrentProject()
        
        print("✅ MIXER VIEW: Added effect to project, calling audio engine...")
        // Add effect to audio engine
        audioEngine.addEffectToBus(bus.id, effect: newEffect)
    }
    
    private func toggleEffect(effectIndex: Int) {
        // TODO: Toggle effect on/off
        print("Toggling effect at slot \(effectIndex)")
    }
    
    private func updateBusEffect(_ effect: BusEffect) {
        print("🎛️ MIXER VIEW: Updating bus effect - \(effect.type) with parameters: \(effect.parameters)")
        
        // Update effect in project and audio engine
        guard var currentProject = project,
              let busIndex = currentProject.buses.firstIndex(where: { $0.id == bus.id }),
              let effectIndex = currentProject.buses[busIndex].effects.firstIndex(where: { $0.id == effect.id }) else { 
            print("❌ MIXER VIEW: Failed to find bus or effect in project")
            return 
        }
        
        currentProject.buses[busIndex].effects[effectIndex] = effect
        currentProject.modifiedAt = Date()
        projectManager.currentProject = currentProject
        projectManager.saveCurrentProject()
        
        print("💾 MIXER VIEW: Saved effect to project, calling audio engine...")
        // Update in audio engine
        audioEngine.updateBusEffect(bus.id, effect: effect)
    }
    
    private func removeEffectFromBus(_ effectId: UUID) {
        // Remove effect from project and audio engine
        guard var currentProject = project,
              let busIndex = currentProject.buses.firstIndex(where: { $0.id == bus.id }) else { return }
        
        currentProject.buses[busIndex].effects.removeAll { $0.id == effectId }
        currentProject.modifiedAt = Date()
        projectManager.currentProject = currentProject
        projectManager.saveCurrentProject()
        
        // Remove from audio engine
        audioEngine.removeEffectFromBus(bus.id, effectId: effectId)
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
                        // Update audio engine
                        audioEngine.updateBusOutputLevel(bus.id, outputLevel: newValue)
                        
                        // Update project manager to trigger UI refresh
                        if let project = project {
                            projectManager.currentProject = project
                            projectManager.saveCurrentProject()
                        }
                        
                        // Only log when dragging stops to reduce noise
                        // print("🎚️ RETURN LEVEL: Updated bus '\(bus.name)' output level to \(Int(newValue * 100))%")
                    }
                ),
                height: 120
            )
            
            Text("-∞")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private var busNameSection: some View {
        VStack(spacing: 4) {
            Text(bus.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 30)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - Master Channel Strip
struct MasterChannelStrip: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    @State private var masterHiEQ: Double = 0.5
    @State private var masterMidEQ: Double = 0.5
    @State private var masterLoEQ: Double = 0.5
    
    var body: some View {
        VStack(spacing: 0) {
            // Master Header
            masterHeaderSection
            
            // Master EQ
            masterEQSection
            
            // Master Fader
            masterFaderSection
            
            // Master Label
            masterLabelSection
        }
        .frame(width: 100)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.controlBackgroundColor))
                .stroke(Color.orange.opacity(0.5), lineWidth: 2)
        )
    }
    
    private var masterHeaderSection: some View {
        VStack(spacing: 4) {
            // Master Icon
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(
                    colors: [.orange, .red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "speaker.wave.3")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                )
        }
        .padding(.vertical, 8)
    }
    
    private var masterEQSection: some View {
        VStack(spacing: 4) {
            Text("Master EQ")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                RotaryKnob(value: $masterHiEQ, range: 0...1, size: 24)
                Text("Hi")
                    .font(.caption2)
                
                RotaryKnob(value: $masterMidEQ, range: 0...1, size: 24)
                Text("Mid")
                    .font(.caption2)
                
                RotaryKnob(value: $masterLoEQ, range: 0...1, size: 24)
                Text("Lo")
                    .font(.caption2)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var masterFaderSection: some View {
        VStack(spacing: 4) {
            Text("Master")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Master Level Display
            Text("0.0")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Master Fader (taller for better visibility)
            VerticalFader(
                value: Binding(
                    get: { audioEngine.masterVolume },
                    set: { newValue in
                        audioEngine.updateMasterVolume(Float(newValue))
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
    
    private var masterLabelSection: some View {
        VStack(spacing: 4) {
            Text("Master")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.orange)
                .frame(height: 30)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
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
    
    @State private var isDragging = false
    @State private var lastDragValue: CGFloat = 0
    
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
                }
        )
    }
}

// Vertical Fader Component
struct VerticalFader: View {
    @Binding var value: Double
    let height: CGFloat
    
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
                        let newValue = 1 - (gesture.location.y / geometry.size.height)
                        let clampedValue = max(0, min(1, newValue))
                        value = clampedValue
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
