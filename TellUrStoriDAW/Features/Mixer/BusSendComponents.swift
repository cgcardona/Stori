//
//  BusSendComponents.swift
//  TellUrStoriDAW
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
            BusTypeIcon(type: bus.type)
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
        switch bus.type {
        case .reverb: return .blue
        case .delay: return .green
        case .chorus: return .purple
        case .custom: return .orange
        }
    }
}

// MARK: - Bus Type Icon Component
struct BusTypeIcon: View {
    let type: BusType
    
    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(iconColor)
    }
    
    private var iconName: String {
        switch type {
        case .reverb: return "waveform.path.ecg"
        case .delay: return "arrow.triangle.2.circlepath"
        case .chorus: return "waveform.path.badge.plus"
        case .custom: return "slider.horizontal.3"
        }
    }
    
    private var iconColor: Color {
        switch type {
        case .reverb: return .blue
        case .delay: return .green
        case .chorus: return .purple
        case .custom: return .orange
        }
    }
}

// MARK: - Bus Creation Menu Component
struct BusCreationMenu: View {
    @Binding var isPresented: Bool
    let onCreateBus: (BusType, String) -> UUID  // Returns the created bus ID
    
    @State private var selectedType: BusType = .reverb
    @State private var busName: String = ""
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Create New Bus")
                .font(.headline)
            
            // Bus Type Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Bus Type")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                    ForEach([BusType.reverb, .delay, .chorus, .custom], id: \.self) { type in
                        BusTypeButton(
                            type: type,
                            isSelected: selectedType == type,
                            action: { selectedType = type }
                        )
                    }
                }
            }
            
            // Bus Name Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Bus Name")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextField("Enter bus name", text: $busName)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Action Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                
                Button("Create Bus") {
                    let finalName = busName.isEmpty ? defaultBusName(for: selectedType) : busName
                    let _ = onCreateBus(selectedType, finalName)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(busName.isEmpty && selectedType == .custom)
            }
        }
        .padding(20)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 10)
        .onAppear {
            busName = defaultBusName(for: selectedType)
        }
        .onChange(of: selectedType) { _, newType in
            if busName == defaultBusName(for: selectedType) || busName.isEmpty {
                busName = defaultBusName(for: newType)
            }
        }
    }
    
    private func defaultBusName(for type: BusType) -> String {
        switch type {
        case .reverb: return "Reverb"
        case .delay: return "Delay"
        case .chorus: return "Chorus"
        case .custom: return ""
        }
    }
}

// MARK: - Bus Type Button Component
struct BusTypeButton: View {
    let type: BusType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                BusTypeIcon(type: type)
                    .frame(width: 24, height: 24)
                
                Text(type.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                    .stroke(
                        isSelected ? Color.accentColor : Color.gray.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Send Slot Component (Professional DAW Style)
struct SendSlot: View {
    let sendIndex: Int
    let track: AudioTrack
    let availableBuses: [MixerBus]
    let onCreateBus: (BusType, String) -> UUID  // Returns the created bus ID
    let onAssignBus: (UUID) -> Void
    
    @State private var showingBusMenu = false
    @State private var assignedBusId: UUID?
    @State private var sendLevel: Double = 0.0
    
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
                        BusTypeIcon(type: bus.type)
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
            
            // Send Level Knob (only visible if bus is assigned)
            if assignedBusId != nil {
                RotaryKnob(
                    value: $sendLevel,
                    range: 0...1,
                    size: 12
                )
            }
        }
        .popover(isPresented: $showingBusMenu, arrowEdge: .trailing) {
            SendBusSelectionMenu(
                availableBuses: availableBuses,
                onSelectBus: { busId in
                    assignedBusId = busId
                    onAssignBus(busId)
                    showingBusMenu = false
                },
                onCreateBus: { busType, busName in
                    let newBusId = onCreateBus(busType, busName)
                    // Auto-assign the newly created bus to this send slot
                    assignedBusId = newBusId
                    onAssignBus(newBusId)
                    showingBusMenu = false
                    return newBusId
                }
            )
            .frame(minWidth: 250, maxWidth: 300)
        }
    }
}

// MARK: - Send Bus Selection Menu
struct SendBusSelectionMenu: View {
    let availableBuses: [MixerBus]
    let onSelectBus: (UUID) -> Void
    let onCreateBus: (BusType, String) -> UUID  // Returns the created bus ID
    
    @State private var showingCreateBus = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Select Bus")
                .font(.headline)
                .padding(.horizontal)
            
            Divider()
            
            // Available Buses
            if !availableBuses.isEmpty {
                Text("Available Buses")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .padding(.horizontal)
                
                ForEach(availableBuses) { bus in
                    Button(action: { onSelectBus(bus.id) }) {
                        HStack(spacing: 8) {
                            BusTypeIcon(type: bus.type)
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
            BusCreationMenu(
                isPresented: $showingCreateBus,
                onCreateBus: { busType, busName in
                    let newBusId = onCreateBus(busType, busName)
                    showingCreateBus = false
                    return newBusId
                }
            )
            .frame(minWidth: 400, minHeight: 300)
            .presentationDetents([.medium])
        }
    }
}

// MARK: - Effect Slot Component (Professional DAW Style)
struct EffectSlot: View {
    let effectIndex: Int
    let bus: MixerBus
    let onAddEffect: (EffectType) -> Void
    let onToggleEffect: (Int) -> Void
    let onUpdateEffect: (BusEffect) -> Void
    let onRemoveEffect: (UUID) -> Void
    
    @State private var showingEffectMenu = false
    @State private var showingEffectUI = false
    @State private var assignedEffect: BusEffect?
    @State private var isHovered = false
    
    private var currentEffect: BusEffect? {
        if effectIndex < bus.effects.count {
            return bus.effects[effectIndex]
        }
        return assignedEffect
    }
    
    var body: some View {
        HStack(spacing: 2) {
            // Effect Slot Button
            Button(action: { 
                if currentEffect == nil {
                    showingEffectMenu.toggle()
                }
            }) {
                HStack(spacing: 2) {
                    if let effect = currentEffect {
                        if isHovered {
                            // Show hover controls (like Logic Pro) - Better Spacing
                            HStack(spacing: 8) {
                                // On/Off Toggle
                                Button(action: { 
                                    if var effect = currentEffect {
                                        effect.isEnabled.toggle()
                                        onUpdateEffect(effect)
                                    }
                                }) {
                                    Circle()
                                        .fill(effect.isEnabled ? Color.green : Color.red)
                                        .frame(width: 10, height: 10)
                                }
                                .buttonStyle(.plain)
                                .help(effect.isEnabled ? "Disable Effect" : "Enable Effect")
                                
                                // Open UI Button
                                Button(action: { 
                                    showingEffectUI = true
                                }) {
                                    Image(systemName: "slider.horizontal.3")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(.primary)
                                        .padding(2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.blue.opacity(0.2))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Open Effect Interface")
                                
                                // Change Effect Button
                                Button(action: { 
                                    showingEffectMenu.toggle()
                                }) {
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 8, weight: .medium))
                                        .foregroundColor(.primary)
                                        .padding(2)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(Color.orange.opacity(0.2))
                                        )
                                }
                                .buttonStyle(.plain)
                                .help("Change Effect Type")
                            }
                        } else {
                            // Show effect name normally
                            EffectTypeIcon(type: effect.type)
                                .frame(width: 12, height: 12)
                            
                            Text(effect.type.displayName)
                                .font(.system(size: 9, weight: .medium))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
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
                        .fill(assignedEffect != nil ? Color.accentColor.opacity(0.1) : Color.clear)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .help(assignedEffect == nil ? "Add Effect" : "Edit Effect")
            .onHover { hovering in
                isHovered = hovering
            }
            
            // Standalone On/Off Toggle (only visible if effect is assigned and not hovering)
            if currentEffect != nil && !isHovered {
                Button(action: { 
                    if var effect = currentEffect {
                        effect.isEnabled.toggle()
                        onUpdateEffect(effect)
                    }
                }) {
                    Circle()
                        .fill(currentEffect?.isEnabled == true ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }
                .buttonStyle(.plain)
                .help(currentEffect?.isEnabled == true ? "Disable Effect" : "Enable Effect")
            }
        }
        .popover(isPresented: $showingEffectMenu, arrowEdge: .trailing) {
            EffectSelectionMenu(
                onSelectEffect: { effectType in
                    let newEffect = BusEffect(
                        name: effectType.displayName,
                        type: effectType,
                        parameters: getDefaultParameters(for: effectType)
                    )
                    assignedEffect = newEffect
                    onAddEffect(effectType)
                    showingEffectMenu = false
                }
            )
            .frame(minWidth: 200, maxWidth: 250)
        }
        .sheet(isPresented: $showingEffectUI) {
            if let effect = currentEffect {
                EffectConfigurationRouter(
                    effectType: effect.type,
                    busName: bus.name,
                    isPresented: $showingEffectUI
                )
            }
        }
    }
    
    // MARK: - Helper Functions
    private func getDefaultParameters(for effectType: EffectType) -> [String: Double] {
        switch effectType {
        case .reverb:
            return [
                "roomSize": 50.0,
                "decayTime": 2.0,
                "wetLevel": 30.0,
                "dryLevel": 70.0,
                "predelay": 0.0
            ]
        case .delay:
            return [
                "delayTime": 250.0,
                "feedback": 25.0,
                "wetLevel": 30.0,
                "dryLevel": 70.0
            ]
        case .chorus:
            return [
                "rate": 1.0,
                "depth": 50.0,
                "wetLevel": 50.0,
                "dryLevel": 50.0
            ]
        case .compressor:
            return [
                "threshold": -12.0,
                "ratio": 4.0,
                "attack": 10.0,
                "release": 100.0,
                "makeupGain": 0.0
            ]
        case .eq:
            return [
                "lowGain": 0.0,
                "lowFreq": 100.0,
                "lowMidGain": 0.0,
                "highMidGain": 0.0,
                "highGain": 0.0
            ]
        case .distortion:
            return [
                "drive": 50.0,
                "tone": 50.0,
                "wetLevel": 100.0
            ]
        case .filter:
            return [
                "cutoff": 1000.0,
                "resonance": 0.0,
                "wetLevel": 100.0
            ]
        case .modulation:
            return [
                "rate": 0.5,
                "depth": 50.0,
                "wetLevel": 50.0
            ]
        }
    }
}

// MARK: - Effect Selection Menu
struct EffectSelectionMenu: View {
    let onSelectEffect: (EffectType) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Effect")
                .font(.headline)
                .padding(.horizontal)
            
            Divider()
            
            // Effect Categories
            ForEach(EffectType.allCases, id: \.self) { effectType in
                Button(action: { onSelectEffect(effectType) }) {
                    HStack(spacing: 8) {
                        EffectTypeIcon(type: effectType)
                            .frame(width: 16, height: 16)
                        
                        Text(effectType.displayName)
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
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Effect Type Enum (now defined in AudioModels.swift)

// MARK: - Effect Type Icon Component
struct EffectTypeIcon: View {
    let type: EffectType
    
    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(iconColor)
    }
    
    private var iconName: String {
        switch type {
        case .reverb: return "waveform.path.ecg"
        case .delay: return "arrow.triangle.2.circlepath"
        case .chorus: return "waveform.path.badge.plus"
        case .compressor: return "waveform.path.badge.minus"
        case .eq: return "slider.horizontal.3"
        case .distortion: return "waveform.path"
        case .filter: return "waveform.path.badge.plus"
        case .modulation: return "waveform"
        }
    }
    
    private var iconColor: Color {
        switch type {
        case .reverb: return .blue
        case .delay: return .green
        case .chorus: return .purple
        case .compressor: return .orange
        case .eq: return .cyan
        case .distortion: return .red
        case .filter: return .yellow
        case .modulation: return .pink
        }
    }
}

// MARK: - Effect Configuration Router
struct EffectConfigurationRouter: View {
    let effectType: EffectType
    let busName: String
    @Binding var isPresented: Bool
    
    var body: some View {
        Group {
            switch effectType {
            case .reverb:
                ReverbConfigurationView(busName: busName, isPresented: $isPresented)
            case .delay:
                DelayConfigurationView(busName: busName, isPresented: $isPresented)
            case .chorus:
                ChorusConfigurationView(busName: busName, isPresented: $isPresented)
            case .compressor:
                CompressorConfigurationView(busName: busName, isPresented: $isPresented)
            case .eq:
                EQConfigurationView(busName: busName, isPresented: $isPresented)
            case .distortion:
                DistortionConfigurationView(busName: busName, isPresented: $isPresented)
            case .filter:
                FilterConfigurationView(busName: busName, isPresented: $isPresented)
            case .modulation:
                ModulationConfigurationView(busName: busName, isPresented: $isPresented)
            }
        }
    }
}

// MARK: - Reverb Configuration View (TellUrStori Style)
struct ReverbConfigurationView: View {
    let busName: String
    @Binding var isPresented: Bool
    
    // Effect Parameters
    @State private var wetLevel: Double = 50.0
    @State private var dryLevel: Double = 0.0
    @State private var roomSize: Double = 60.0
    @State private var density: Double = 60.0
    @State private var decay: Double = 1.1
    @State private var distance: Double = 50.0
    @State private var attack: Double = 0.0
    @State private var predelay: Double = 8.0
    @State private var freeze: Bool = false
    
    // UI State
    @State private var selectedPreset = "Default Preset"
    @State private var dampingCurve: [CGPoint] = []
    
    // TellUrStori Visual Theme
    private let gradientColors = [
        Color.blue.opacity(0.8),
        Color.purple.opacity(0.8),
        Color.pink.opacity(0.8)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            effectHeaderBar
            
            // Main Content
            HStack(spacing: 0) {
                // Left Panel - EQ/Damping Curve
                dampingEQPanel
                    .frame(width: 400)
                
                Divider()
                
                // Right Panel - Controls
                controlsPanel
                    .frame(minWidth: 300)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(.controlBackgroundColor))
        .onAppear {
            setupDefaultCurve()
        }
    }
    
    private var effectHeaderBar: some View {
        HStack {
            // Power Button with Gradient
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .buttonStyle(.plain)
            .help("Close Effect")
            
            Spacer()
            
            // Effect Title with Gradient
            Text("REVERB")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Spacer()
            
            // Preset Selector with TellUrStori Styling
            Menu {
                Button("Default Preset") { selectedPreset = "Default Preset" }
                Button("Hall") { selectedPreset = "Hall" }
                Button("Room") { selectedPreset = "Room" }
                Button("Plate") { selectedPreset = "Plate" }
                Button("Spring") { selectedPreset = "Spring" }
                Button("Cathedral") { selectedPreset = "Cathedral" }
                Button("Ambient") { selectedPreset = "Ambient" }
            } label: {
                HStack {
                    Text(selectedPreset)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                        .stroke(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            }
            .menuStyle(.borderlessButton)
            
            Spacer()
            
            // Navigation Controls with Gradient Styling
            HStack(spacing: 8) {
                TellUrStoriButton(title: "Compare", action: {})
                TellUrStoriButton(title: "Copy", action: {})
                TellUrStoriButton(title: "Paste", action: {})
                TellUrStoriButton(title: "Undo", action: {})
                TellUrStoriButton(title: "Redo", action: {})
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            ZStack {
                // Subtle gradient background
                LinearGradient(
                    colors: [
                        Color(.controlBackgroundColor),
                        Color(.controlBackgroundColor).opacity(0.8)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Animated gradient border
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        LinearGradient(
                            colors: gradientColors.map { $0.opacity(0.3) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
    }
    
    private var dampingEQPanel: some View {
        VStack(spacing: 0) {
            // Tab Selector with TellUrStori Styling
            HStack {
                TabButton(title: "DAMPING EQ", isSelected: true)
                Spacer()
                TabButton(title: "Room", isSelected: false)
                TabButton(title: "MAIN", isSelected: true)
                Spacer()
                TabButton(title: "DETAILS", isSelected: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(
                    colors: [
                        Color(.controlBackgroundColor),
                        Color(.controlBackgroundColor).opacity(0.7)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            // EQ Curve Display
            ZStack {
                // Grid Background
                Canvas { context, size in
                    let gridColor = Color.gray.opacity(0.3)
                    
                    // Vertical grid lines
                    for i in 0...10 {
                        let x = size.width * CGFloat(i) / 10
                        context.stroke(
                            Path { path in
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                            },
                            with: .color(gridColor),
                            lineWidth: 0.5
                        )
                    }
                    
                    // Horizontal grid lines
                    for i in 0...8 {
                        let y = size.height * CGFloat(i) / 8
                        context.stroke(
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                            },
                            with: .color(gridColor),
                            lineWidth: 0.5
                        )
                    }
                }
                
                // EQ Curve with TellUrStori Gradient
                if !dampingCurve.isEmpty {
                    Path { path in
                        path.move(to: dampingCurve[0])
                        for point in dampingCurve.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    
                    // Control Points with Gradient
                    ForEach(Array(dampingCurve.enumerated()), id: \.offset) { index, point in
                        if index % 3 == 0 { // Show every 3rd point as control
                            Circle()
                                .fill(Color.white)
                                .stroke(
                                    LinearGradient(
                                        colors: gradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 10, height: 10)
                                .position(point)
                                .shadow(color: gradientColors[1].opacity(0.5), radius: 2)
                        }
                    }
                }
                
                // Frequency Labels
                VStack {
                    Spacer()
                    HStack {
                        Text("20")
                        Spacer()
                        Text("30")
                        Spacer()
                        Text("40")
                        Spacer()
                        Text("60")
                        Spacer()
                        Text("100")
                        Spacer()
                        Text("200")
                        Spacer()
                        Text("300")
                        Spacer()
                        Text("400")
                        Spacer()
                        Text("600")
                        Spacer()
                        Text("1k")
                        Spacer()
                        Text("2k")
                        Spacer()
                        Text("3k")
                        Spacer()
                        Text("4k")
                        Spacer()
                        Text("6k")
                        Spacer()
                        Text("8k")
                        Spacer()
                        Text("10k")
                        Spacer()
                        Text("20k")
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                }
                
                // Percentage Labels (Right Side)
                VStack {
                    HStack {
                        Spacer()
                        VStack(spacing: 0) {
                            Text("2.2 s")
                            Spacer()
                            Text("1.1 s")
                            Spacer()
                            Text("0.9 s")
                            Spacer()
                            Text("0.7 s")
                            Spacer()
                            Text("0.4 s")
                            Spacer()
                            Text("0.2 s")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .frame(height: 300)
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
            .padding(.horizontal, 16)
            
            Spacer()
        }
    }
    
    private var controlsPanel: some View {
        VStack(spacing: 20) {
            // Parameter Knobs
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                TellUrStoriParameterKnob(
                    title: "Attack",
                    value: $attack,
                    range: 0...100,
                    unit: "%",
                    gradientColors: gradientColors
                )
                
                TellUrStoriParameterKnob(
                    title: "Size",
                    value: $roomSize,
                    range: 0...100,
                    unit: "%",
                    gradientColors: gradientColors
                )
                
                TellUrStoriParameterKnob(
                    title: "Density",
                    value: $density,
                    range: 0...100,
                    unit: "%",
                    gradientColors: gradientColors
                )
                
                TellUrStoriParameterKnob(
                    title: "Decay",
                    value: $decay,
                    range: 0.3...100,
                    unit: "s",
                    gradientColors: gradientColors
                )
                
                TellUrStoriParameterKnob(
                    title: "Distance",
                    value: $distance,
                    range: 0...100,
                    unit: "%",
                    gradientColors: gradientColors
                )
                
                TellUrStoriParameterKnob(
                    title: "Dry",
                    value: $dryLevel,
                    range: 0...100,
                    unit: "%",
                    gradientColors: gradientColors
                )
                
                TellUrStoriParameterKnob(
                    title: "Wet",
                    value: $wetLevel,
                    range: 0...100,
                    unit: "%",
                    gradientColors: gradientColors
                )
            }
            .padding(.horizontal, 20)
            
            // Predelay Section with TellUrStori Styling
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "music.note")
                        .foregroundStyle(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("Predelay")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    Spacer()
                }
                
                HStack {
                    Text("\(predelay, specifier: "%.0f") ms")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Spacer()
                    
                    VStack {
                        HStack {
                            Text("0.3")
                            Spacer()
                            Text("100")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        
                        Text("Freeze")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Predelay Slider with Gradient
                HStack {
                    Slider(value: $predelay, in: 0.3...100)
                        .tint(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    
                    Toggle("", isOn: $freeze)
                        .toggleStyle(TellUrStoriToggleStyle(gradientColors: gradientColors))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.controlBackgroundColor).opacity(0.3))
                    .stroke(
                        LinearGradient(
                            colors: gradientColors.map { $0.opacity(0.5) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .padding(.horizontal, 20)
            
            Spacer()
            
            // Bottom Title with Gradient
            Text("REVERB")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .padding(.bottom, 20)
        }
        .padding(.vertical, 20)
    }
    
    private func setupDefaultCurve() {
        // Create a realistic damping curve similar to Logic Pro's ChromaVerb
        let width: CGFloat = 350
        let height: CGFloat = 250
        
        dampingCurve = [
            CGPoint(x: 0, y: height * 0.9),
            CGPoint(x: width * 0.15, y: height * 0.85),
            CGPoint(x: width * 0.3, y: height * 0.75),
            CGPoint(x: width * 0.45, y: height * 0.65),
            CGPoint(x: width * 0.6, y: height * 0.55),
            CGPoint(x: width * 0.75, y: height * 0.45),
            CGPoint(x: width * 0.9, y: height * 0.35),
            CGPoint(x: width, y: height * 0.25)
        ]
    }
}

// MARK: - Delay Configuration View
struct DelayConfigurationView: View {
    let busName: String
    @Binding var isPresented: Bool
    
    @State private var delayTime: Double = 250.0
    @State private var feedback: Double = 35.0
    @State private var wetLevel: Double = 30.0
    @State private var dryLevel: Double = 70.0
    @State private var lowCut: Double = 20.0
    @State private var highCut: Double = 8000.0
    @State private var sync: Bool = false
    
    private let gradientColors = [Color.green.opacity(0.8), Color.cyan.opacity(0.8), Color.blue.opacity(0.8)]
    
    var body: some View {
        VStack(spacing: 0) {
            EffectHeaderBar(title: "DELAY", gradientColors: gradientColors, isPresented: $isPresented)
            
            HStack(spacing: 0) {
                // Left Panel - Visualization
                VStack {
                    Text("DELAY VISUALIZATION")
                        .font(.headline)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                    
                    // Delay visualization would go here
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .frame(height: 300)
                        .cornerRadius(8)
                        .overlay(
                            Text("Delay Pattern Display")
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 400)
                .padding()
                
                Divider()
                
                // Right Panel - Controls
                VStack(spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                        TellUrStoriParameterKnob(title: "Time", value: $delayTime, range: 1...2000, unit: "ms", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Feedback", value: $feedback, range: 0...95, unit: "%", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Low Cut", value: $lowCut, range: 20...1000, unit: "Hz", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "High Cut", value: $highCut, range: 1000...20000, unit: "Hz", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Dry", value: $dryLevel, range: 0...100, unit: "%", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Wet", value: $wetLevel, range: 0...100, unit: "%", gradientColors: gradientColors)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    Text("DELAY")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                        .padding(.bottom, 20)
                }
                .frame(minWidth: 300)
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - Chorus Configuration View
struct ChorusConfigurationView: View {
    let busName: String
    @Binding var isPresented: Bool
    
    @State private var rate: Double = 0.5
    @State private var depth: Double = 50.0
    @State private var voices: Double = 4.0
    @State private var spread: Double = 180.0
    @State private var wetLevel: Double = 50.0
    @State private var dryLevel: Double = 50.0
    
    private let gradientColors = [Color.purple.opacity(0.8), Color.pink.opacity(0.8), Color.red.opacity(0.8)]
    
    var body: some View {
        VStack(spacing: 0) {
            EffectHeaderBar(title: "CHORUS", gradientColors: gradientColors, isPresented: $isPresented)
            
            HStack(spacing: 0) {
                // Left Panel - Waveform
                VStack {
                    Text("MODULATION WAVEFORM")
                        .font(.headline)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                    
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .frame(height: 300)
                        .cornerRadius(8)
                        .overlay(
                            Text("Chorus Waveform")
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 400)
                .padding()
                
                Divider()
                
                // Right Panel - Controls
                VStack(spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                        TellUrStoriParameterKnob(title: "Rate", value: $rate, range: 0.1...10, unit: "Hz", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Depth", value: $depth, range: 0...100, unit: "%", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Voices", value: $voices, range: 2...8, unit: "", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Spread", value: $spread, range: 0...360, unit: "°", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Dry", value: $dryLevel, range: 0...100, unit: "%", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Wet", value: $wetLevel, range: 0...100, unit: "%", gradientColors: gradientColors)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    Text("CHORUS")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                        .padding(.bottom, 20)
                }
                .frame(minWidth: 300)
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - Compressor Configuration View
struct CompressorConfigurationView: View {
    let busName: String
    @Binding var isPresented: Bool
    
    @State private var threshold: Double = -12.0
    @State private var ratio: Double = 4.0
    @State private var attack: Double = 10.0
    @State private var release: Double = 100.0
    @State private var makeupGain: Double = 0.0
    @State private var wetLevel: Double = 100.0
    
    private let gradientColors = [Color.orange.opacity(0.8), Color.red.opacity(0.8), Color.pink.opacity(0.8)]
    
    var body: some View {
        VStack(spacing: 0) {
            EffectHeaderBar(title: "COMPRESSOR", gradientColors: gradientColors, isPresented: $isPresented)
            
            HStack(spacing: 0) {
                // Left Panel - Gain Reduction Meter
                VStack {
                    Text("GAIN REDUCTION")
                        .font(.headline)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                    
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .frame(height: 300)
                        .cornerRadius(8)
                        .overlay(
                            Text("GR Meter")
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 400)
                .padding()
                
                Divider()
                
                // Right Panel - Controls
                VStack(spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                        TellUrStoriParameterKnob(title: "Threshold", value: $threshold, range: -60...0, unit: "dB", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Ratio", value: $ratio, range: 1...20, unit: ":1", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Attack", value: $attack, range: 0.1...100, unit: "ms", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Release", value: $release, range: 10...1000, unit: "ms", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Makeup", value: $makeupGain, range: 0...20, unit: "dB", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Knee", value: $wetLevel, range: 0...10, unit: "dB", gradientColors: gradientColors)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    Text("COMPRESSOR")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                        .padding(.bottom, 20)
                }
                .frame(minWidth: 300)
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - EQ Configuration View
struct EQConfigurationView: View {
    let busName: String
    @Binding var isPresented: Bool
    
    @State private var lowGain: Double = 0.0
    @State private var lowMidGain: Double = 0.0
    @State private var highMidGain: Double = 0.0
    @State private var highGain: Double = 0.0
    @State private var lowFreq: Double = 100.0
    @State private var highFreq: Double = 10000.0
    
    private let gradientColors = [Color.cyan.opacity(0.8), Color.blue.opacity(0.8), Color.purple.opacity(0.8)]
    
    var body: some View {
        VStack(spacing: 0) {
            EffectHeaderBar(title: "EQ", gradientColors: gradientColors, isPresented: $isPresented)
            
            HStack(spacing: 0) {
                // Left Panel - EQ Curve
                VStack {
                    Text("FREQUENCY RESPONSE")
                        .font(.headline)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                    
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .frame(height: 300)
                        .cornerRadius(8)
                        .overlay(
                            Text("EQ Curve Display")
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 400)
                .padding()
                
                Divider()
                
                // Right Panel - Controls
                VStack(spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        TellUrStoriParameterKnob(title: "Low Gain", value: $lowGain, range: -15...15, unit: "dB", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Low Freq", value: $lowFreq, range: 20...500, unit: "Hz", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Low Mid", value: $lowMidGain, range: -15...15, unit: "dB", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Mid Freq", value: $highFreq, range: 200...5000, unit: "Hz", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "High Mid", value: $highMidGain, range: -15...15, unit: "dB", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "High Gain", value: $highGain, range: -15...15, unit: "dB", gradientColors: gradientColors)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    Text("EQUALIZER")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                        .padding(.bottom, 20)
                }
                .frame(minWidth: 300)
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - Distortion Configuration View
struct DistortionConfigurationView: View {
    let busName: String
    @Binding var isPresented: Bool
    
    @State private var drive: Double = 30.0
    @State private var tone: Double = 50.0
    @State private var output: Double = 0.0
    @State private var wetLevel: Double = 100.0
    
    private let gradientColors = [Color.red.opacity(0.8), Color.orange.opacity(0.8), Color.yellow.opacity(0.8)]
    
    var body: some View {
        VStack(spacing: 0) {
            EffectHeaderBar(title: "DISTORTION", gradientColors: gradientColors, isPresented: $isPresented)
            
            HStack(spacing: 0) {
                // Left Panel - Waveform
                VStack {
                    Text("WAVEFORM SHAPING")
                        .font(.headline)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                    
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .frame(height: 300)
                        .cornerRadius(8)
                        .overlay(
                            Text("Distortion Curve")
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 400)
                .padding()
                
                Divider()
                
                // Right Panel - Controls
                VStack(spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        TellUrStoriParameterKnob(title: "Drive", value: $drive, range: 0...100, unit: "%", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Tone", value: $tone, range: 0...100, unit: "%", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Output", value: $output, range: -20...20, unit: "dB", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Mix", value: $wetLevel, range: 0...100, unit: "%", gradientColors: gradientColors)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    Text("DISTORTION")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                        .padding(.bottom, 20)
                }
                .frame(minWidth: 300)
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - Filter Configuration View
struct FilterConfigurationView: View {
    let busName: String
    @Binding var isPresented: Bool
    
    @State private var cutoff: Double = 1000.0
    @State private var resonance: Double = 0.7
    @State private var filterType: String = "Low Pass"
    @State private var wetLevel: Double = 100.0
    
    private let gradientColors = [Color.yellow.opacity(0.8), Color.green.opacity(0.8), Color.cyan.opacity(0.8)]
    
    var body: some View {
        VStack(spacing: 0) {
            EffectHeaderBar(title: "FILTER", gradientColors: gradientColors, isPresented: $isPresented)
            
            HStack(spacing: 0) {
                // Left Panel - Filter Response
                VStack {
                    Text("FILTER RESPONSE")
                        .font(.headline)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                    
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .frame(height: 300)
                        .cornerRadius(8)
                        .overlay(
                            Text("Filter Curve")
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 400)
                .padding()
                
                Divider()
                
                // Right Panel - Controls
                VStack(spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        TellUrStoriParameterKnob(title: "Cutoff", value: $cutoff, range: 20...20000, unit: "Hz", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Resonance", value: $resonance, range: 0.1...10, unit: "Q", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Mix", value: $wetLevel, range: 0...100, unit: "%", gradientColors: gradientColors)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    Text("FILTER")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                        .padding(.bottom, 20)
                }
                .frame(minWidth: 300)
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - Modulation Configuration View
struct ModulationConfigurationView: View {
    let busName: String
    @Binding var isPresented: Bool
    
    @State private var rate: Double = 2.0
    @State private var depth: Double = 50.0
    @State private var waveform: String = "Sine"
    @State private var wetLevel: Double = 50.0
    
    private let gradientColors = [Color.pink.opacity(0.8), Color.purple.opacity(0.8), Color.blue.opacity(0.8)]
    
    var body: some View {
        VStack(spacing: 0) {
            EffectHeaderBar(title: "MODULATION", gradientColors: gradientColors, isPresented: $isPresented)
            
            HStack(spacing: 0) {
                // Left Panel - LFO Waveform
                VStack {
                    Text("LFO WAVEFORM")
                        .font(.headline)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                    
                    Rectangle()
                        .fill(Color.black.opacity(0.8))
                        .frame(height: 300)
                        .cornerRadius(8)
                        .overlay(
                            Text("LFO Display")
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 400)
                .padding()
                
                Divider()
                
                // Right Panel - Controls
                VStack(spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                        TellUrStoriParameterKnob(title: "Rate", value: $rate, range: 0.1...20, unit: "Hz", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Depth", value: $depth, range: 0...100, unit: "%", gradientColors: gradientColors)
                        TellUrStoriParameterKnob(title: "Mix", value: $wetLevel, range: 0...100, unit: "%", gradientColors: gradientColors)
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                    
                    Text("MODULATION")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(LinearGradient(colors: gradientColors, startPoint: .leading, endPoint: .trailing))
                        .padding(.bottom, 20)
                }
                .frame(minWidth: 300)
                .padding(.vertical, 20)
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - Shared Effect Header Bar
struct EffectHeaderBar: View {
    let title: String
    let gradientColors: [Color]
    @Binding var isPresented: Bool
    
    @State private var selectedPreset = "Default Preset"
    
    var body: some View {
        HStack {
            // Close Button with Gradient
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .buttonStyle(.plain)
            .help("Close Effect")
            
            Spacer()
            
            // Effect Title with Gradient
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            
            Spacer()
            
            // Preset Selector
            Menu {
                Button("Default Preset") { selectedPreset = "Default Preset" }
                Button("Vintage") { selectedPreset = "Vintage" }
                Button("Modern") { selectedPreset = "Modern" }
                Button("Extreme") { selectedPreset = "Extreme" }
                Button("Subtle") { selectedPreset = "Subtle" }
            } label: {
                HStack {
                    Text(selectedPreset)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                        .stroke(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
            }
            .menuStyle(.borderlessButton)
            
            Spacer()
            
            // Navigation Controls
            HStack(spacing: 8) {
                TellUrStoriButton(title: "Compare", action: {})
                TellUrStoriButton(title: "Copy", action: {})
                TellUrStoriButton(title: "Paste", action: {})
                TellUrStoriButton(title: "Undo", action: {})
                TellUrStoriButton(title: "Redo", action: {})
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(.controlBackgroundColor),
                        Color(.controlBackgroundColor).opacity(0.8)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                RoundedRectangle(cornerRadius: 0)
                    .stroke(
                        LinearGradient(
                            colors: gradientColors.map { $0.opacity(0.3) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
    }
}

// MARK: - TellUrStori Parameter Knob Component
struct TellUrStoriParameterKnob: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    let gradientColors: [Color]
    
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            ZStack {
                // Knob Background with Gradient Border
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: gradientColors.map { $0.opacity(0.3) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 60, height: 60)
                
                // Knob Value Arc with Gradient
                Circle()
                    .trim(from: 0, to: CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) * 0.75)
                    .stroke(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 60, height: 60)
                    .rotationEffect(.degrees(-135))
                    .shadow(color: gradientColors[1].opacity(0.5), radius: isDragging ? 4 : 2)
                
                // Knob Indicator with Gradient
                Circle()
                    .fill(
                        LinearGradient(
                            colors: gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 8, height: 8)
                    .offset(y: -25)
                    .rotationEffect(.degrees(-135 + (value - range.lowerBound) / (range.upperBound - range.lowerBound) * 270))
                    .shadow(color: .black.opacity(0.3), radius: 2)
                
                // Center Dot
                Circle()
                    .fill(Color.primary)
                    .frame(width: 6, height: 6)
            }
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        if !isDragging { isDragging = true }
                        let center = CGPoint(x: 30, y: 30)
                        let angle = atan2(gesture.location.y - center.y, gesture.location.x - center.x)
                        let degrees = angle * 180 / .pi + 135
                        let normalizedDegrees = max(0, min(270, degrees))
                        let normalizedValue = normalizedDegrees / 270
                        value = range.lowerBound + (range.upperBound - range.lowerBound) * normalizedValue
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            
            Text(formatValue(value) + unit)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
    }
    
    private func formatValue(_ value: Double) -> String {
        if unit == "s" {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.0f", value)
        }
    }
}

// MARK: - TellUrStori Button Component
struct TellUrStoriButton: View {
    let title: String
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(.controlBackgroundColor))
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.6),
                                    Color.purple.opacity(0.6),
                                    Color.pink.opacity(0.6)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(.plain)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
    }
}

// MARK: - Tab Button Component
struct TabButton: View {
    let title: String
    let isSelected: Bool
    
    var body: some View {
        Button(action: {}) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(
                    isSelected ? 
                    LinearGradient(
                        colors: [Color.blue, Color.purple, Color.pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    ) :
                    LinearGradient(
                        colors: [Color.secondary],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TellUrStori Toggle Style
struct TellUrStoriToggleStyle: ToggleStyle {
    let gradientColors: [Color]
    
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    configuration.isOn ?
                    LinearGradient(
                        colors: gradientColors,
                        startPoint: .leading,
                        endPoint: .trailing
                    ) :
                    LinearGradient(
                        colors: [Color.gray.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 50, height: 30)
                .overlay(
                    Circle()
                        .fill(Color.white)
                        .shadow(radius: 2)
                        .padding(2)
                        .offset(x: configuration.isOn ? 10 : -10)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isOn)
                )
                .onTapGesture {
                    configuration.isOn.toggle()
                }
        }
    }
}

// MARK: - BusType Extension (displayName now defined in AudioModels.swift)
