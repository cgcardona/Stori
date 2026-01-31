//
//  IORoutingSection.swift
//  Stori
//
//  I/O routing controls for professional mixer channel strips
//

import SwiftUI

// MARK: - I/O Routing Section
struct IORoutingSection: View {
    let track: AudioTrack
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    let isCompact: Bool
    let onUpdateInput: (TrackInputSource) -> Void
    let onUpdateOutput: (TrackOutputDestination) -> Void
    let onUpdateInputTrim: (Float) -> Void
    
    @State private var showInputPicker = false
    @State private var showOutputPicker = false
    
    var body: some View {
        VStack(spacing: 4) {
            if isCompact {
                compactView
            } else {
                fullView
            }
        }
    }
    
    // MARK: - Compact View
    private var compactView: some View {
        HStack(spacing: 4) {
            // Input indicator
            IOIndicator(
                label: "I",
                value: track.inputSource.shortName,
                isActive: track.mixerSettings.isRecordEnabled,
                activeColor: .red
            )
            .onTapGesture { showInputPicker.toggle() }
            
            // Output indicator
            IOIndicator(
                label: "O",
                value: track.outputDestination.shortName,
                isActive: true,
                activeColor: .green
            )
            .onTapGesture { showOutputPicker.toggle() }
        }
        .popover(isPresented: $showInputPicker) {
            inputPickerView
        }
        .popover(isPresented: $showOutputPicker) {
            outputPickerView
        }
    }
    
    // MARK: - Full View
    private var fullView: some View {
        VStack(spacing: 4) {
            // Section Header
            HStack {
                Text("I/O")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(MixerColors.sectionHeader)
                Spacer()
            }
            
            // Input Row
            IORow(
                label: "INPUT",
                value: track.inputSource.displayName,
                isActive: track.mixerSettings.isRecordEnabled,
                activeColor: .red,
                onTap: { showInputPicker.toggle() }
            )
            
            // Output Row
            IORow(
                label: "OUTPUT",
                value: track.outputDestination.displayName,
                isActive: true,
                activeColor: .green,
                onTap: { showOutputPicker.toggle() }
            )
            
            // Input Trim (if input is enabled)
            if track.mixerSettings.isRecordEnabled {
                TrimControl(
                    label: "TRIM",
                    value: track.mixerSettings.inputTrim,
                    range: -20...20,
                    onChange: onUpdateInputTrim
                )
            }
        }
        .padding(.horizontal, 4)
        .popover(isPresented: $showInputPicker) {
            inputPickerView
        }
        .popover(isPresented: $showOutputPicker) {
            outputPickerView
        }
    }
    
    // MARK: - Input Picker
    private var inputPickerView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Input Source")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            
            Divider()
            
            // No Input option
            InputOptionRow(
                label: "No Input",
                isSelected: track.inputSource == .none,
                onSelect: {
                    onUpdateInput(.none)
                    showInputPicker = false
                }
            )
            
            // System Default
            InputOptionRow(
                label: "System Input",
                isSelected: track.inputSource == .systemDefault,
                onSelect: {
                    onUpdateInput(.systemDefault)
                    showInputPicker = false
                }
            )
            
            Divider()
            
            // Mono inputs (1-8)
            Text("Mono Inputs")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            
            ForEach(1...8, id: \.self) { channel in
                InputOptionRow(
                    label: "Input \(channel)",
                    isSelected: {
                        if case .input(let ch) = track.inputSource {
                            return ch == channel
                        }
                        return false
                    }(),
                    onSelect: {
                        onUpdateInput(.input(channel: channel))
                        showInputPicker = false
                    }
                )
            }
            
            Divider()
            
            // Stereo pairs
            Text("Stereo Pairs")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            
            ForEach([1, 3, 5, 7], id: \.self) { left in
                let right = left + 1
                InputOptionRow(
                    label: "Input \(left)/\(right)",
                    isSelected: {
                        if case .stereoInput(let l, let r) = track.inputSource {
                            return l == left && r == right
                        }
                        return false
                    }(),
                    onSelect: {
                        onUpdateInput(.stereoInput(left: left, right: right))
                        showInputPicker = false
                    }
                )
            }
        }
        .frame(width: 180)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Output Picker
    private var outputPickerView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Output Destination")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 8)
            
            Divider()
            
            // Stereo Out (default)
            InputOptionRow(
                label: "Stereo Out",
                isSelected: track.outputDestination == .stereoOut,
                onSelect: {
                    onUpdateOutput(.stereoOut)
                    showOutputPicker = false
                }
            )
            
            Divider()
            
            // Available buses (read from ProjectManager for reactive updates)
            if let project = projectManager.currentProject {
                if !project.buses.isEmpty {
                    Text("Buses")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                    
                    ForEach(project.buses) { bus in
                        InputOptionRow(
                            label: bus.name,
                            isSelected: {
                                if case .bus(let busId) = track.outputDestination {
                                    return busId == bus.id
                                }
                                return false
                            }(),
                            onSelect: {
                                onUpdateOutput(.bus(busId: bus.id))
                                showOutputPicker = false
                            }
                        )
                    }
                }
            }
            
            Divider()
            
            // Direct outputs
            Text("Direct Outputs")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
            
            ForEach([1, 3, 5, 7], id: \.self) { left in
                let right = left + 1
                InputOptionRow(
                    label: "Output \(left)/\(right)",
                    isSelected: {
                        if case .stereoOutput(let l, let r) = track.outputDestination {
                            return l == left && r == right
                        }
                        return false
                    }(),
                    onSelect: {
                        onUpdateOutput(.stereoOutput(left: left, right: right))
                        showOutputPicker = false
                    }
                )
            }
        }
        .frame(width: 180)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Supporting Components

struct IOIndicator: View {
    let label: String
    let value: String
    let isActive: Bool
    let activeColor: Color
    
    var body: some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(isActive ? activeColor : .secondary)
                .frame(width: 32)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black.opacity(0.3))
                )
        }
    }
}

struct IORow: View {
    let label: String
    let value: String
    let isActive: Bool
    let activeColor: Color
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 36, alignment: .leading)
                
                Text(value)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(isActive ? activeColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
                
                Image(systemName: "chevron.down")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.black.opacity(0.2))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct InputOptionRow: View {
    let label: String
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct TrimControl: View {
    let label: String
    let value: Float
    let range: ClosedRange<Float>
    let onChange: (Float) -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 7, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 28, alignment: .leading)
            
            // Mini slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black.opacity(0.3))
                    
                    // Fill
                    let normalizedValue = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(value > 0 ? Color.orange : Color.blue)
                        .frame(width: geometry.size.width * CGFloat(normalizedValue))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let normalizedPos = Float(gesture.location.x / geometry.size.width)
                            var newValue = range.lowerBound + normalizedPos * (range.upperBound - range.lowerBound)
                            newValue = max(range.lowerBound, min(range.upperBound, newValue))
                            onChange(newValue)
                        }
                )
            }
            .frame(height: 8)
            
            // Value display
            Text(String(format: "%+.0f", value))
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(value > 0 ? .orange : (value < 0 ? .blue : .secondary))
                .frame(width: 24, alignment: .trailing)
        }
        .padding(.top, 2)
    }
}
