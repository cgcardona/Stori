//
//  EditableTrackColor.swift
//  TellUrStoriDAW
//
//  Editable track color indicator with color picker
//

import SwiftUI

// MARK: - Color Extension for Hex Conversion
extension Color {
    /// Convert SwiftUI Color to hex string
    func toHex() -> String {
        // Convert to UIColor/NSColor to get RGB components
        #if canImport(UIKit)
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #else
        let nsColor = NSColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        
        nsColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        
        let r = Int(red * 255)
        let g = Int(green * 255)
        let b = Int(blue * 255)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

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
    
    private let colors = TrackColor.allPredefinedCases
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    
    @State private var showingCustomColorPicker = false
    @State private var customColor = Color.blue
    
    var body: some View {
        VStack(spacing: 20) {
            // Header with professional styling
            Text("Choose Track Color")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.primary)
            
            // Predefined Colors Grid with better spacing
            LazyVGrid(columns: columns, spacing: 12) {
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
            .padding(.horizontal, 16)
            
            // Professional divider
            Rectangle()
                .fill(Color(.separatorColor))
                .frame(height: 1)
                .padding(.horizontal, 16)
            
            // Custom Color Picker Button with DAW styling
            Button(action: {
                showingCustomColorPicker = true
            }) {
                HStack(spacing: 12) {
                    // Rainbow gradient circle with better styling
                    Circle()
                        .fill(
                            AngularGradient(
                                colors: [.red, .orange, .yellow, .green, .blue, .indigo, .purple, .red],
                                center: .center
                            )
                        )
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                    
                    Text("Custom Color...")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.controlBackgroundColor))
                        .stroke(Color(.separatorColor), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
        }
        .frame(width: 320, height: 300)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.windowBackgroundColor))
        )
        .sheet(isPresented: $showingCustomColorPicker) {
            CustomColorPickerSheet(
                initialColor: customColor,
                onColorSelected: { color in
                    customColor = color
                    // Create a custom TrackColor with the selected hex value
                    let hexString = color.toHex()
                    let customTrackColor = TrackColor.custom(hexString)
                    onColorSelected(customTrackColor)
                    showingCustomColorPicker = false
                }
            )
        }
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
    @State private var showingColorPicker = false
    @Environment(\.dismiss) private var dismiss
    
    init(initialColor: Color, onColorSelected: @escaping (Color) -> Void) {
        self.initialColor = initialColor
        self.onColorSelected = onColorSelected
        self._selectedColor = State(initialValue: initialColor)
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header with professional styling
            Text("Custom Track Color")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.primary)
            
            // Color Preview - larger and more prominent
            RoundedRectangle(cornerRadius: 16)
                .fill(selectedColor)
                .frame(width: 120, height: 120)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(.separatorColor), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
            
            // Native Color Picker with consistent styling
            VStack(spacing: 12) {
                Text("Select Color")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                
                Button(action: {
                    showingColorPicker = true
                }) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(selectedColor)
                        .frame(width: 60, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separatorColor), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingColorPicker) {
                    ColorPicker("Select Color", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .padding()
                        .frame(width: 280, height: 200)
                }
            }
            
            Spacer()
            
            // Action Buttons with DAW styling
            HStack(spacing: 16) {
                Button("Cancel") {
                    showingColorPicker = false
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minWidth: 100)
                
                Button("Choose Color") {
                    showingColorPicker = false
                    onColorSelected(selectedColor)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(minWidth: 100)
            }
        }
        .padding(32)
        .frame(width: 380, height: 460)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.windowBackgroundColor))
        )
    }
}

