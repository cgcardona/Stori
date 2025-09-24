//
//  EditableTrackColor.swift
//  TellUrStoriDAW
//
//  Editable track color indicator with color picker
//

import SwiftUI

struct EditableTrackColor: View {
    let trackId: UUID
    @ObservedObject var projectManager: ProjectManager
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    
    @State private var showingColorPicker = false
    
    // Computed property to get current track color
    private var currentTrackColor: TrackColor {
        projectManager.currentProject?.tracks.first { $0.id == trackId }?.color ?? .blue
    }
    
    init(
        trackId: UUID,
        projectManager: ProjectManager,
        width: CGFloat = 4,
        height: CGFloat = 30,
        cornerRadius: CGFloat = 2
    ) {
        self.trackId = trackId
        self.projectManager = projectManager
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(currentTrackColor.color)
            .frame(width: width, height: height)
            .onTapGesture {
                showingColorPicker = true
            }
            .popover(isPresented: $showingColorPicker) {
                EditableTrackColorPicker(
                    selectedColor: currentTrackColor,
                    onColorSelected: { newColor in
                        updateTrackColor(newColor)
                        showingColorPicker = false
                    }
                )
                .padding()
            }
    }
    
    // MARK: - Private Methods
    
    private func updateTrackColor(_ newColor: TrackColor) {
        projectManager.updateTrackColor(trackId, newColor)
        projectManager.saveCurrentProject()
        
        print("🎨 TRACK COLOR: Updated track \(trackId) to \(newColor.rawValue)")
    }
}

// MARK: - Editable Track Color Picker

struct EditableTrackColorPicker: View {
    let selectedColor: TrackColor
    let onColorSelected: (TrackColor) -> Void
    
    private let colors = TrackColor.allCases
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    
    @State private var showingCustomColorPicker = false
    @State private var customColor = Color.blue
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Choose Track Color")
                .font(.headline)
                .foregroundColor(.primary)
            
            // Predefined Colors Grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(colors, id: \.self) { color in
                    ColorSwatch(
                        color: color,
                        isSelected: color == selectedColor,
                        onTap: {
                            onColorSelected(color)
                        }
                    )
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            // Custom Color Picker Button
            Button(action: {
                showingCustomColorPicker = true
            }) {
                HStack(spacing: 8) {
                    // Rainbow gradient circle
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .orange, .yellow, .green, .blue, .indigo, .purple, .red],
                                center: .center
                            )
                        )
                        .frame(width: 24, height: 24)
                    
                    Text("Custom Color...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                        .stroke(Color(.separatorColor), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(width: 280, height: 260)
        .sheet(isPresented: $showingCustomColorPicker) {
            CustomColorPickerSheet(
                initialColor: customColor,
                onColorSelected: { color in
                    customColor = color
                    // For now, we'll map to the closest predefined color
                    // In a future enhancement, we could extend TrackColor to support custom colors
                    let closestColor = findClosestTrackColor(to: color)
                    onColorSelected(closestColor)
                    showingCustomColorPicker = false
                }
            )
        }
    }
    
    // Helper to find closest predefined color
    private func findClosestTrackColor(to color: Color) -> TrackColor {
        // Simple mapping - in a real implementation, you'd calculate color distance
        // For now, return a reasonable default
        return .blue
    }
}

// MARK: - Color Swatch

struct ColorSwatch: View {
    let color: TrackColor
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(color.color)
            .frame(width: 40, height: 40)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isSelected ? Color.primary : Color.clear,
                        lineWidth: isSelected ? 3 : 0
                    )
            )
            .overlay(
                // Checkmark for selected color
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(isSelected ? .white : .clear)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
            )
            .onTapGesture {
                onTap()
            }
            .scaleEffect(isSelected ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Custom Color Picker Sheet

struct CustomColorPickerSheet: View {
    let initialColor: Color
    let onColorSelected: (Color) -> Void
    
    @State private var selectedColor: Color
    @Environment(\.dismiss) private var dismiss
    
    init(initialColor: Color, onColorSelected: @escaping (Color) -> Void) {
        self.initialColor = initialColor
        self.onColorSelected = onColorSelected
        self._selectedColor = State(initialValue: initialColor)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Custom Track Color")
                .font(.title2)
                .fontWeight(.semibold)
            
            // Color Preview
            RoundedRectangle(cornerRadius: 12)
                .fill(selectedColor)
                .frame(width: 80, height: 80)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.separatorColor), lineWidth: 1)
                )
            
            // Native Color Picker
            ColorPicker("Select Color", selection: $selectedColor, supportsOpacity: false)
                .labelsHidden()
                .scaleEffect(1.2)
            
            Spacer()
            
            // Action Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                Button("Choose Color") {
                    onColorSelected(selectedColor)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 320, height: 400)
    }
}

#Preview {
    EditableTrackColor(
        trackId: UUID(),
        projectManager: ProjectManager(),
        width: 4,
        height: 30
    )
}
