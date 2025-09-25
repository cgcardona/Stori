//
//  ProfessionalTrackHeader.swift
//  TellUrStoriDAW
//
//  Professional track header component matching industry-standard DAW quality
//

import SwiftUI

struct ProfessionalTrackHeader: View {
    let track: TrackHeaderModel
    let isSelected: Bool
    let height: CGFloat
    
    @ObservedObject var headerManager: TrackHeaderManager
    @State private var isEditingName = false
    @State private var editingName: String
    @State private var showingColorPicker = false
    @State private var showingAIGeneration = false
    @State private var isDragHovered = false
    
    // Animation states
    @State private var scaleEffect: CGFloat = 1.0
    @State private var shadowRadius: CGFloat = 2.0
    
    init(track: TrackHeaderModel, isSelected: Bool, height: CGFloat, headerManager: TrackHeaderManager) {
        self.track = track
        self.isSelected = isSelected
        self.height = height
        self.headerManager = headerManager
        self._editingName = State(initialValue: track.name)
    }
    
    var body: some View {
        HStack(spacing: 0) {
            // Color-coded left border with track type icon
            trackIndicatorStrip
            
            // Main header content
            headerContent
        }
        .frame(height: height)
        .background(headerBackground)
        .overlay(headerBorder)
        .scaleEffect(scaleEffect)
        .shadow(color: .black.opacity(0.1), radius: shadowRadius, x: 0, y: 1)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.1), value: isDragHovered)
        .onTapGesture {
            headerManager.selectTrack(id: track.id)
        }
        .contextMenu {
            trackContextMenu
        }
        .sheet(isPresented: $showingColorPicker) {
            TrackColorPicker(selectedColor: track.color) { newColor in
                headerManager.updateTrackColor(id: track.id, color: newColor)
            }
        }
        .sheet(isPresented: $showingAIGeneration) {
            AIGenerationView(
                targetTrack: convertToAudioTrack(from: track),
                projectManager: headerManager.projectManager ?? ProjectManager()
            )
        }
    }
    
    // MARK: - Track Indicator Strip
    private var trackIndicatorStrip: some View {
        VStack(spacing: 0) {
            // Track number
            Text("\(track.trackNumber)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 20, height: 16)
                .background(track.color.color.opacity(0.8))
                .cornerRadius(2)
            
            Spacer(minLength: 4)
            
            // Track type icon
            Image(systemName: track.typeIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(track.color.color)
                .frame(width: 20, height: 16)
                .background(track.color.color.opacity(0.1))
                .cornerRadius(2)
            
            Spacer()
        }
        .frame(width: 24)
        .background(
            Rectangle()
                .fill(track.color.color)
                .frame(width: 4)
                .offset(x: -10)
        )
        .padding(.vertical, 4)
    }
    
    // MARK: - Header Content
    private var headerContent: some View {
        VStack(spacing: 6) {
            // Top row: Track name and status indicators
            trackNameRow
            
            // Bottom row: Controls
            trackControlsRow
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
    
    // MARK: - Track Name Row
    private var trackNameRow: some View {
        HStack(spacing: 8) {
            // Track name (editable)
            if isEditingName {
                TextField("Track Name", text: $editingName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .medium))
                    .onSubmit {
                        headerManager.updateTrackName(id: track.id, name: editingName)
                        isEditingName = false
                    }
                    .onExitCommand {
                        editingName = track.name
                        isEditingName = false
                    }
            } else {
                Text(track.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) {
                        isEditingName = true
                    }
                    .help("Double-click to rename")
            }
            
            Spacer()
            
            // Status indicators
            statusIndicators
        }
    }
    
    // MARK: - Status Indicators
    private var statusIndicators: some View {
        HStack(spacing: 4) {
            // Freeze indicator
            if track.isFrozen {
                Image(systemName: "snowflake")
                    .font(.system(size: 10))
                    .foregroundColor(.blue)
                    .help("Track is frozen")
            }
            
            // Record enable indicator (when active)
            if track.isRecordEnabled {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                    .help("Record enabled")
            }
            
            // Color indicator (clickable)
            Button(action: {
                showingColorPicker = true
            }) {
                Circle()
                    .fill(track.color.color)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(.white.opacity(0.3), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("Change track color")
        }
    }
    
    // MARK: - Track Controls Row
    private var trackControlsRow: some View {
        HStack(spacing: 6) {
            // Record enable
            TrackControlButton(
                icon: "record.circle",
                isActive: track.isRecordEnabled,
                activeColor: .red,
                action: {
                    headerManager.toggleRecordEnable(id: track.id)
                }
            )
            .help("Record Enable (R)")
            
            // Mute
            TrackControlButton(
                text: "M",
                isActive: track.isMuted,
                activeColor: .orange,
                action: {
                    headerManager.toggleMute(id: track.id)
                }
            )
            .help("Mute (M)")
            
            // Solo
            TrackControlButton(
                text: "S",
                isActive: track.isSolo,
                activeColor: .yellow,
                action: {
                    headerManager.toggleSolo(id: track.id)
                }
            )
            .help("Solo (S)")
            
            // Volume control
            VStack(spacing: 1) {
                Text("VOL")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(.secondary)
                
                ProfessionalSlider(
                    value: track.volume,
                    range: 0...1,
                    width: 50,
                    height: 8
                ) { newValue in
                    headerManager.updateVolume(id: track.id, volume: newValue)
                }
                
                Text(track.volumeDisplayText)
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            
            // Pan control
            VStack(spacing: 1) {
                Text("PAN")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundColor(.secondary)
                
                ProfessionalKnob(
                    value: track.pan,
                    range: -1...1,
                    size: 20
                ) { newValue in
                    headerManager.updatePan(id: track.id, pan: newValue)
                }
                
                Text(track.panDisplayText)
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // AI Generation button
            Button(action: {
                showingAIGeneration = true
            }) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 11))
                    .foregroundColor(.purple)
                    .frame(width: 20, height: 20)
                    .background(.purple.opacity(0.1))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("Generate AI Music")
            
            // Delete button
            Button(action: {
                headerManager.removeTrack(id: track.id)
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                    .frame(width: 18, height: 18)
                    .background(.red.opacity(0.1))
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .help("Delete Track (⌘⌫)")
        }
    }
    
    // MARK: - Background and Border
    private var headerBackground: some View {
        Rectangle()
            .fill(
                isSelected 
                    ? LinearGradient(
                        colors: [
                            .accentColor.opacity(0.15),
                            .accentColor.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    : LinearGradient(
                        colors: [
                            Color(.controlBackgroundColor),
                            Color(.controlBackgroundColor).opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
            )
    }
    
    private var headerBorder: some View {
        Rectangle()
            .stroke(
                isSelected 
                    ? Color.blue.opacity(0.3)
                    : .gray.opacity(0.2),
                lineWidth: isSelected ? 1 : 0.5
            )
    }
    
    // MARK: - Context Menu
    private var trackContextMenu: some View {
        Group {
            Button("Duplicate Track") {
                headerManager.duplicateTrack(id: track.id)
            }
            
            Button("Delete Track") {
                headerManager.removeTrack(id: track.id)
            }
            
            Divider()
            
            Button("Track Color...") {
                showingColorPicker = true
            }
            
            Button(track.isFrozen ? "Unfreeze Track" : "Freeze Track") {
                // TODO: Implement freeze functionality
            }
            
            Divider()
            
            Button("Generate AI Music...") {
                showingAIGeneration = true
            }
        }
    }
}

// MARK: - Track Control Button
struct TrackControlButton: View {
    let icon: String?
    let text: String?
    let isActive: Bool
    let activeColor: Color
    let action: () -> Void
    
    init(icon: String, isActive: Bool, activeColor: Color, action: @escaping () -> Void) {
        self.icon = icon
        self.text = nil
        self.isActive = isActive
        self.activeColor = activeColor
        self.action = action
    }
    
    init(text: String, isActive: Bool, activeColor: Color, action: @escaping () -> Void) {
        self.icon = nil
        self.text = text
        self.isActive = isActive
        self.activeColor = activeColor
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Group {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                } else if let text = text {
                    Text(text)
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundColor(isActive ? .black : .secondary)
            .frame(width: 18, height: 18)
            .background(
                isActive 
                    ? activeColor
                    : Color.clear
            )
            .cornerRadius(3)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(.secondary.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive ? 1.0 : 0.95)
        .animation(.easeInOut(duration: 0.1), value: isActive)
    }
}

// MARK: - Professional Slider
struct ProfessionalSlider: View {
    let value: Float
    let range: ClosedRange<Float>
    let width: CGFloat
    let height: CGFloat
    let onChange: (Float) -> Void
    
    @State private var dragValue: Float
    @State private var isDragging = false
    
    init(value: Float, range: ClosedRange<Float>, width: CGFloat, height: CGFloat, onChange: @escaping (Float) -> Void) {
        self.value = value
        self.range = range
        self.width = width
        self.height = height
        self.onChange = onChange
        self._dragValue = State(initialValue: value)
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(.gray.opacity(0.3))
                    .frame(height: height)
                
                // Fill
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: thumbPosition, height: height)
                
                // Thumb
                Circle()
                    .fill(.white)
                    .frame(width: height + 2, height: height + 2)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .offset(x: thumbPosition - (height + 2) / 2)
            }
        }
        .frame(width: width, height: height)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                    }
                    
                    let percent = max(0, min(1, gesture.location.x / width))
                    dragValue = range.lowerBound + Float(percent) * (range.upperBound - range.lowerBound)
                    onChange(dragValue)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onChange(of: value) { _, newValue in
            if !isDragging {
                dragValue = newValue
            }
        }
    }
    
    private var thumbPosition: CGFloat {
        let percent = (dragValue - range.lowerBound) / (range.upperBound - range.lowerBound)
        return width * CGFloat(percent)
    }
}

// MARK: - Professional Knob
struct ProfessionalKnob: View {
    let value: Float
    let range: ClosedRange<Float>
    let size: CGFloat
    let onChange: (Float) -> Void
    
    @State private var dragValue: Float
    @State private var isDragging = false
    @State private var lastDragLocation: CGPoint = .zero
    
    init(value: Float, range: ClosedRange<Float>, size: CGFloat, onChange: @escaping (Float) -> Void) {
        self.value = value
        self.range = range
        self.size = size
        self.onChange = onChange
        self._dragValue = State(initialValue: value)
    }
    
    var body: some View {
        ZStack {
            // Knob body
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.gray.opacity(0.8), .gray.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(.white.opacity(0.3), lineWidth: 0.5)
                )
            
            // Center detent for pan
            if range.lowerBound < 0 && range.upperBound > 0 {
                Circle()
                    .fill(abs(dragValue) < 0.05 ? .blue : .gray.opacity(0.6))
                    .frame(width: 3, height: 3)
            }
            
            // Value indicator
            Rectangle()
                .fill(.white)
                .frame(width: 1, height: size * 0.3)
                .offset(y: -size * 0.2)
                .rotationEffect(.degrees(Double(rotationAngle)))
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        lastDragLocation = gesture.location
                    }
                    
                    let deltaY = lastDragLocation.y - gesture.location.y
                    let sensitivity: Float = 0.01
                    let delta = Float(deltaY) * sensitivity
                    
                    dragValue = max(range.lowerBound, min(range.upperBound, dragValue + delta))
                    
                    // Snap to center for pan
                    if range.lowerBound < 0 && range.upperBound > 0 && abs(dragValue) < 0.05 {
                        dragValue = 0
                    }
                    
                    onChange(dragValue)
                    lastDragLocation = gesture.location
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onChange(of: value) { _, newValue in
            if !isDragging {
                dragValue = newValue
            }
        }
    }
    
    private var rotationAngle: Float {
        let percent = (dragValue - range.lowerBound) / (range.upperBound - range.lowerBound)
        return -135 + (percent * 270) // -135° to +135° range
    }
}

// MARK: - Track Color Picker
struct TrackColorPicker: View {
    let selectedColor: TrackColor
    let onColorSelected: (TrackColor) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Choose Track Color")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                    ForEach(TrackColor.allPredefinedCases, id: \.self) { color in
                        Button(action: {
                            onColorSelected(color)
                            dismiss()
                        }) {
                            Circle()
                                .fill(color.color)
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(.white, lineWidth: selectedColor == color ? 3 : 0)
                                )
                                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
                
                Spacer()
            }
            .padding()
            .navigationTitle("Track Color")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 300, height: 400)
    }
}

// MARK: - Helper Functions
extension ProfessionalTrackHeader {
    private func convertToAudioTrack(from trackHeader: TrackHeaderModel) -> AudioTrack {
        var audioTrack = AudioTrack(
            name: trackHeader.name,
            trackType: .audio,
            color: trackHeader.color
        )
        
        // Update mixer settings to match track header
        audioTrack.mixerSettings.volume = trackHeader.volume
        audioTrack.mixerSettings.pan = trackHeader.pan
        audioTrack.mixerSettings.isMuted = trackHeader.isMuted
        audioTrack.mixerSettings.isSolo = trackHeader.isSolo
        
        return audioTrack
    }
}
