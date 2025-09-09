//
//  MixerView.swift
//  TellUrStoriDAW
//
//  Professional mixer interface matching Logic Pro architecture
//

import SwiftUI

struct MixerView: View {
    let project: AudioProject?
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    @Binding var selectedTrackId: UUID?
    
    @State private var isMonitoringLevels = false
    @State private var buses: [MixerBus] = []
    @State private var showingBusCreation = false
    
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
                                track: track,
                                buses: buses,
                                isSelected: selectedTrackId == track.id,
                                audioEngine: audioEngine,
                                projectManager: projectManager,
                                onSelect: { selectedTrackId = track.id }
                            )
                        }
                        
                        // Bus Channel Strips
                        ForEach(buses) { bus in
                            BusChannelStrip(
                                bus: bus,
                                audioEngine: audioEngine,
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
            BusCreationView { busName, busType in
                createBus(name: busName, type: busType)
            }
        }
    }
    
    private var mixerHeaderView: some View {
        HStack {
            Text("Mixer")
                .font(.headline)
                .fontWeight(.semibold)
            
            Spacer()
            
            // Mixer Controls
            HStack(spacing: 12) {
                Button(action: { showingBusCreation = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                        Text("Add Bus")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .help("Create New Bus (⌘⇧B)")
                .keyboardShortcut("b", modifiers: [.command, .shift])
                
                Menu {
                    Button("Show All Sends") { }
                    Button("Hide All Sends") { }
                    Divider()
                    Button("Reset All Levels") { }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14))
                }
                .help("Mixer Options")
            }
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
    
    private func createBus(name: String, type: BusType) {
        let newBus = MixerBus(
            id: UUID(),
            name: name,
            type: type,
            inputLevel: 0.0,
            outputLevel: 0.75,
            effects: [],
            isMuted: false,
            isSolo: false
        )
        buses.append(newBus)
    }
    
    private func deleteBus(_ bus: MixerBus) {
        buses.removeAll { $0.id == bus.id }
    }
}

// MARK: - Track Channel Strip
struct TrackChannelStrip: View {
    let track: AudioTrack
    let buses: [MixerBus]
    let isSelected: Bool
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let onSelect: () -> Void
    
    @State private var showingSends = false
    @State private var sendLevels: [UUID: Double] = [:]
    
    var body: some View {
        VStack(spacing: 0) {
            // Track Header
            trackHeaderSection
            
            // Sends Section (expandable)
            if showingSends && !buses.isEmpty {
                sendsSection
            }
            
            // EQ Section
            eqSection
            
            // Pan Control
            panSection
            
            // Fader Section
            faderSection
            
            // Track Name
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
    
    private var sendsSection: some View {
        VStack(spacing: 6) {
            Text("Sends")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            ForEach(buses) { bus in
                VStack(spacing: 2) {
                    Text(bus.name)
                        .font(.caption2)
                        .lineLimit(1)
                    
                    RotaryKnob(
                        value: Binding(
                            get: { sendLevels[bus.id] ?? 0.0 },
                            set: { sendLevels[bus.id] = $0 }
                        ),
                        range: 0...1,
                        size: 24
                    )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.1))
    }
    
    private var eqSection: some View {
        VStack(spacing: 4) {
            Text("EQ")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            VStack(spacing: 4) {
                RotaryKnob(value: .constant(0.5), range: 0...1, size: 20)
                Text("Hi")
                    .font(.caption2)
                
                RotaryKnob(value: .constant(0.5), range: 0...1, size: 20)
                Text("Mid")
                    .font(.caption2)
                
                RotaryKnob(value: .constant(0.5), range: 0...1, size: 20)
                Text("Lo")
                    .font(.caption2)
            }
        }
        .padding(.vertical, 8)
    }
    
    private var panSection: some View {
        VStack(spacing: 4) {
            Text("Pan")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            RotaryKnob(
                value: .constant(0.5),
                range: 0...1,
                size: 28
            )
        }
        .padding(.vertical, 6)
    }
    
    private var faderSection: some View {
        VStack(spacing: 4) {
            // Level Display
            Text("0.0")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            // Vertical Fader
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
                height: 120
            )
            
            Text("-∞")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    private var trackNameSection: some View {
        VStack(spacing: 4) {
            Text(track.name)
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

// MARK: - Bus Channel Strip
struct BusChannelStrip: View {
    let bus: MixerBus
    @ObservedObject var audioEngine: AudioEngine
    let onDelete: () -> Void
    
    @State private var showingEffects = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Bus Header
            busHeaderSection
            
            // Effects Section
            if showingEffects {
                effectsSection
            }
            
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
                .fill(bus.type.color)
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: bus.type.iconName)
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
    
    private var effectsSection: some View {
        VStack(spacing: 4) {
            Text("FX")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            if bus.effects.isEmpty {
                Text("No Effects")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                ForEach(bus.effects) { effect in
                    Text(effect.name)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.1))
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
                value: .constant(bus.outputLevel),
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
    @State private var masterVolume: Double = 0.8
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
            
            // Master Fader
            VerticalFader(
                value: Binding(
                    get: { masterVolume },
                    set: { newValue in
                        masterVolume = newValue
                        audioEngine.updateMasterVolume(Float(newValue))
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

// Bus Creation View
struct BusCreationView: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, BusType) -> Void
    
    @State private var busName = ""
    @State private var selectedBusType: BusType = .reverb
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create New Bus")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Bus Name")
                    .font(.headline)
                
                TextField("Enter bus name", text: $busName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Bus Type")
                    .font(.headline)
                
                Picker("Bus Type", selection: $selectedBusType) {
                    ForEach(BusType.allCases, id: \.self) { type in
                        HStack {
                            Image(systemName: type.iconName)
                            Text(type.name)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.menu)
            }
            
            HStack(spacing: 16) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Create Bus") {
                    onCreate(busName.isEmpty ? selectedBusType.name : busName, selectedBusType)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(busName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

// MARK: - Supporting Models
struct MixerBus: Identifiable {
    let id: UUID
    let name: String
    let type: BusType
    var inputLevel: Double
    var outputLevel: Double
    var effects: [BusEffect]
    var isMuted: Bool
    var isSolo: Bool
}

struct BusEffect: Identifiable {
    let id = UUID()
    let name: String
    let type: EffectType
    var isEnabled: Bool
    var parameters: [String: Double]
}

enum BusType: CaseIterable {
    case reverb
    case delay
    case chorus
    case custom
    
    var name: String {
        switch self {
        case .reverb: return "Reverb"
        case .delay: return "Delay"
        case .chorus: return "Chorus"
        case .custom: return "Custom"
        }
    }
    
    var color: Color {
        switch self {
        case .reverb: return .blue
        case .delay: return .green
        case .chorus: return .purple
        case .custom: return .gray
        }
    }
    
    var iconName: String {
        switch self {
        case .reverb: return "waveform.path.ecg"
        case .delay: return "arrow.triangle.2.circlepath"
        case .chorus: return "waveform.path"
        case .custom: return "gear"
        }
    }
}

enum EffectType {
    case reverb
    case delay
    case eq
    case compressor
    case distortion
}

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