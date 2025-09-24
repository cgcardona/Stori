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
    
    var body: some View {
        VStack(spacing: 12) {
            Text("Choose Track Color")
                .font(.headline)
                .foregroundColor(.primary)
            
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
        }
        .frame(width: 280, height: 200)
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

#Preview {
    EditableTrackColor(
        trackId: UUID(),
        projectManager: ProjectManager(),
        width: 4,
        height: 30
    )
}
