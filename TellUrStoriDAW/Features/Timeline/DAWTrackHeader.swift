//
//  DAWTrackHeader.swift
//  TellUrStoriDAW
//
//  Professional DAW track header with industry-standard controls and styling
//

import SwiftUI

struct DAWTrackHeader: View {
    let track: AudioTrack
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let trackNumber: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    // MARK: - State
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showingTrackMenu = false
    
    var body: some View {
        HStack(spacing: 0) {
            // MARK: - Track Number & Icon
            VStack(spacing: 2) {
                // Track Number
                Text("\(trackNumber)")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                
                // Track Type Icon
                TrackTypeIcon(trackType: track.trackType)
                    .frame(width: 20, height: 16)
            }
            .frame(width: 32)
            .padding(.leading, 8)
            
            // MARK: - Track Color Indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: track.color.rawValue))
                .frame(width: 4, height: 40)
                .padding(.horizontal, 4)
            
            // MARK: - Track Name & Controls
            VStack(spacing: 0) {
                // Track Name
                HStack(spacing: 8) {
                    if isEditingName {
                        TextField("Track Name", text: $editedName)
                            .textFieldStyle(.plain)
                            .font(.system(.callout, weight: .medium))
                            .onSubmit {
                                commitNameEdit()
                            }
                            .onExitCommand {
                                cancelNameEdit()
                            }
                            .onAppear {
                                editedName = track.name
                            }
                    } else {
                        Text(track.name)
                            .font(.system(.callout, weight: .medium))
                            .foregroundColor(.primary)
                            .onTapGesture(count: 2) {
                                startNameEdit()
                            }
                    }
                    
                    Spacer()
                    
                    // Track Menu Button
                    Button(action: { showingTrackMenu.toggle() }) {
                        Image(systemName: "ellipsis")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .opacity(isSelected ? 1.0 : 0.0)
                }
                .frame(height: 20)
                
                // Control Buttons Row
                HStack(spacing: 6) {
                    // Mute Button
                    DAWTrackButton(
                        text: "M",
                        isActive: track.mixerSettings.isMuted,
                        activeColor: .orange,
                        size: .small
                    ) {
                        audioEngine.updateTrackMute(trackId: track.id, isMuted: !track.mixerSettings.isMuted)
                    }
                    
                    // Solo Button
                    DAWTrackButton(
                        text: "S",
                        isActive: track.mixerSettings.isSolo,
                        activeColor: .yellow,
                        size: .small
                    ) {
                        audioEngine.updateTrackSolo(trackId: track.id, isSolo: !track.mixerSettings.isSolo)
                    }
                    
                    // Record Enable Button
                    DAWTrackButton(
                        icon: "record.circle",
                        isActive: track.mixerSettings.isRecordEnabled,
                        activeColor: .red,
                        size: .small
                    ) {
                        audioEngine.updateTrackRecordEnable(track.id, !track.mixerSettings.isRecordEnabled)
                    }
                    
                    Spacer()
                    
                    // Input Monitoring (when record enabled)
                    if track.mixerSettings.isRecordEnabled {
                        DAWTrackButton(
                            icon: "speaker.wave.2",
                            isActive: track.mixerSettings.inputMonitoring,
                            activeColor: .blue,
                            size: .small
                        ) {
                            audioEngine.updateInputMonitoring(track.id, !track.mixerSettings.inputMonitoring)
                        }
                    }
                    
                    // Freeze Button (for CPU optimization)
                    DAWTrackButton(
                        icon: "snowflake",
                        isActive: track.isFrozen,
                        activeColor: .cyan,
                        size: .small
                    ) {
                        audioEngine.toggleTrackFreeze(track.id)
                    }
                }
                .frame(height: 18)
            }
            .padding(.horizontal, 8)
            
            Spacer()
            
            // MARK: - Level Meter
            TrackLevelMeter(
                level: audioEngine.getTrackLevel(track.id),
                isActive: !track.mixerSettings.isMuted && audioEngine.transportState == .playing
            )
            .frame(width: 20, height: 40)
            .padding(.trailing, 8)
        }
        .frame(height: 60)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            TrackContextMenu(
                track: track,
                onDelete: onDelete,
                onDuplicate: { duplicateTrack() },
                onColorChange: { color in changeTrackColor(color) }
            )
        }
        .popover(isPresented: $showingTrackMenu) {
            TrackMenuPopover(
                track: track,
                onDelete: onDelete,
                onDuplicate: { duplicateTrack() },
                onColorChange: { color in changeTrackColor(color) }
            )
        }
    }
    
    // MARK: - Helper Methods
    private func startNameEdit() {
        editedName = track.name
        isEditingName = true
    }
    
    private func commitNameEdit() {
        if !editedName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            projectManager.updateTrackName(track.id, editedName)
        }
        isEditingName = false
    }
    
    private func cancelNameEdit() {
        editedName = track.name
        isEditingName = false
    }
    
    private func duplicateTrack() {
        projectManager.duplicateTrack(track.id)
    }
    
    private func changeTrackColor(_ color: TrackColor) {
        projectManager.updateTrackColor(track.id, color)
    }
}

// MARK: - Track Type Icon
struct TrackTypeIcon: View {
    let trackType: TrackType
    
    var body: some View {
        Image(systemName: iconName)
            .font(.caption)
            .foregroundColor(iconColor)
    }
    
    private var iconName: String {
        switch trackType {
        case .audio:
            return "waveform"
        case .midi:
            return "music.note"
        case .instrument:
            return "pianoforte"
        case .bus:
            return "arrow.branch"
        }
    }
    
    private var iconColor: Color {
        switch trackType {
        case .audio:
            return .blue
        case .midi:
            return .green
        case .instrument:
            return .purple
        case .bus:
            return .orange
        }
    }
}

// MARK: - DAW Track Button
struct DAWTrackButton: View {
    let text: String?
    let icon: String?
    let isActive: Bool
    let activeColor: Color
    let size: ButtonSize
    let action: () -> Void
    
    enum ButtonSize {
        case small, medium
        
        var dimension: CGFloat {
            switch self {
            case .small: return 16
            case .medium: return 20
            }
        }
        
        var fontSize: Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            }
        }
    }
    
    init(
        text: String,
        isActive: Bool = false,
        activeColor: Color = .accentColor,
        size: ButtonSize = .small,
        action: @escaping () -> Void
    ) {
        self.text = text
        self.icon = nil
        self.isActive = isActive
        self.activeColor = activeColor
        self.size = size
        self.action = action
    }
    
    init(
        icon: String,
        isActive: Bool = false,
        activeColor: Color = .accentColor,
        size: ButtonSize = .small,
        action: @escaping () -> Void
    ) {
        self.text = nil
        self.icon = icon
        self.isActive = isActive
        self.activeColor = activeColor
        self.size = size
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Group {
                if let text = text {
                    Text(text)
                        .font(size.fontSize)
                        .fontWeight(.semibold)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(size.fontSize)
                }
            }
            .foregroundColor(isActive ? .white : .secondary)
            .frame(width: size.dimension, height: size.dimension)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isActive ? activeColor : Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isActive)
    }
}

// MARK: - Track Level Meter
struct TrackLevelMeter: View {
    let level: Float
    let isActive: Bool
    
    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<8, id: \.self) { segment in
                Rectangle()
                    .fill(segmentColor(for: segment))
                    .frame(height: 4)
                    .opacity(shouldShowSegment(segment) ? 1.0 : 0.2)
            }
        }
        .animation(.easeInOut(duration: 0.1), value: level)
    }
    
    private func shouldShowSegment(_ segment: Int) -> Bool {
        guard isActive else { return false }
        let threshold = Float(segment) / 8.0
        return level > threshold
    }
    
    private func segmentColor(for segment: Int) -> Color {
        switch segment {
        case 0...4:
            return .green
        case 5...6:
            return .yellow
        default:
            return .red
        }
    }
}

// MARK: - Track Context Menu
struct TrackContextMenu: View {
    let track: AudioTrack
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onColorChange: (TrackColor) -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Button("Duplicate Track") {
                onDuplicate()
            }
            
            Divider()
            
            Menu("Track Color") {
                ForEach(TrackColor.allPredefinedCases, id: \.self) { color in
                    Button(action: { onColorChange(color) }) {
                        HStack {
                            Circle()
                                .fill(Color(hex: color.rawValue))
                                .frame(width: 12, height: 12)
                            Text(colorName(for: color))
                        }
                    }
                }
            }
            
            Divider()
            
            Button("Delete Track", role: .destructive) {
                onDelete()
            }
        }
    }
    
    private func colorName(for color: TrackColor) -> String {
        switch color {
        case .blue: return "Blue"
        case .red: return "Red"
        case .green: return "Green"
        case .yellow: return "Yellow"
        case .purple: return "Purple"
        case .pink: return "Pink"
        case .orange: return "Orange"
        case .teal: return "Teal"
        case .indigo: return "Indigo"
        case .gray: return "Gray"
        case .custom(_): return "Custom"
        }
    }
}

// MARK: - Track Menu Popover
struct TrackMenuPopover: View {
    let track: AudioTrack
    let onDelete: () -> Void
    let onDuplicate: () -> Void
    let onColorChange: (TrackColor) -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Track Options")
                .font(.headline)
                .padding(.bottom, 4)
            
            Button("Duplicate Track") {
                onDuplicate()
                dismiss()
            }
            .buttonStyle(.plain)
            
            Divider()
            
            Text("Track Color")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 8) {
                ForEach(TrackColor.allPredefinedCases, id: \.self) { color in
                    Button(action: {
                        onColorChange(color)
                        dismiss()
                    }) {
                        Circle()
                            .fill(Color(hex: color.rawValue))
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .stroke(track.color == color ? Color.primary : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
            
            Button("Delete Track", role: .destructive) {
                onDelete()
                dismiss()
            }
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 200)
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
