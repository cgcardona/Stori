//
//  EditableTrackName.swift
//  TellUrStoriDAW
//
//  Reusable component for editing track names with double-click functionality
//

import SwiftUI

struct EditableTrackName: View {
    let trackId: UUID
    @ObservedObject var projectManager: ProjectManager
    let font: Font
    let foregroundColor: Color
    let alignment: TextAlignment
    let lineLimit: Int?
    let truncationMode: Text.TruncationMode
    
    @State private var isEditing = false
    @State private var editedName = ""
    @FocusState private var isTextFieldFocused: Bool
    
    // Computed property to get current track name
    private var currentTrackName: String {
        projectManager.currentProject?.tracks.first { $0.id == trackId }?.name ?? "Unknown Track"
    }
    
    init(
        trackId: UUID,
        projectManager: ProjectManager,
        font: Font = .body,
        foregroundColor: Color = .primary,
        alignment: TextAlignment = .leading,
        lineLimit: Int? = 1,
        truncationMode: Text.TruncationMode = .tail
    ) {
        self.trackId = trackId
        self.projectManager = projectManager
        self.font = font
        self.foregroundColor = foregroundColor
        self.alignment = alignment
        self.lineLimit = lineLimit
        self.truncationMode = truncationMode
    }
    
    var body: some View {
        Group {
            if isEditing {
                TextField("Track Name", text: $editedName)
                    .textFieldStyle(.plain)
                    .font(font)
                    .foregroundColor(foregroundColor)
                    .multilineTextAlignment(alignment)
                    .focused($isTextFieldFocused)
                    .padding(.horizontal, 0) // Remove any default padding
                    .padding(.vertical, 0)   // Remove any default padding
                    .onSubmit {
                        commitEdit()
                    }
                    .onExitCommand {
                        cancelEdit()
                    }
                    .onAppear {
                        editedName = currentTrackName
                        isTextFieldFocused = true
                    }
            } else {
                Text(currentTrackName)
                    .font(font)
                    .foregroundColor(foregroundColor)
                    .lineLimit(lineLimit)
                    .truncationMode(truncationMode)
                    .multilineTextAlignment(alignment)
                    .padding(.horizontal, 0) // Match TextField padding
                    .padding(.vertical, 0)   // Match TextField padding
                    .onTapGesture(count: 2) {
                        startEdit()
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : alignment == .trailing ? .trailing : .center) // Ensure consistent alignment
    }
    
    // MARK: - Private Methods
    
    private func startEdit() {
        editedName = currentTrackName
        isEditing = true
        print("🏷️ EDIT: Started editing track name: \(currentTrackName)")
    }
    
    private func commitEdit() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Don't allow empty names
        guard !trimmedName.isEmpty else {
            cancelEdit()
            return
        }
        
        // Update the track name in the project
        if var project = projectManager.currentProject,
           let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            project.tracks[trackIndex].name = trimmedName
            projectManager.currentProject = project
            projectManager.saveCurrentProject()
            
            print("🏷️ EDIT: Updated track name to: '\(trimmedName)'")
        }
        
        isEditing = false
    }
    
    private func cancelEdit() {
        editedName = currentTrackName
        isEditing = false
        print("🏷️ EDIT: Cancelled track name edit")
    }
}

#Preview {
    // Create a mock project manager for preview
    let mockProjectManager = ProjectManager()
    let mockTrack = AudioTrack(name: "Sample Track", color: .blue)
    
    VStack(spacing: 20) {
        EditableTrackName(
            trackId: mockTrack.id,
            projectManager: mockProjectManager,
            font: .headline,
            foregroundColor: .primary
        )
        
        EditableTrackName(
            trackId: mockTrack.id,
            projectManager: mockProjectManager,
            font: .system(size: 9, weight: .medium),
            foregroundColor: .secondary,
            alignment: .center
        )
    }
    .padding()
}
