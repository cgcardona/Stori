//
//  EditableTrackName.swift
//  Stori
//
//  Reusable component for editing track names with double-click functionality
//

import SwiftUI

struct EditableTrackName: View {
    let trackId: UUID
    var projectManager: ProjectManager
    let font: Font
    let foregroundColor: Color
    let alignment: TextAlignment
    let lineLimit: Int?
    let truncationMode: Text.TruncationMode
    
    @State private var isEditing = false
    @State private var editedName = ""
    @State private var nameBeforeEdit = ""  // Track original name for undo
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
        if isEditing {
            TextField("Track Name", text: $editedName)
                .textFieldStyle(.plain)
                .font(font)
                .foregroundColor(foregroundColor)
                .multilineTextAlignment(alignment)
                .focused($isTextFieldFocused)
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
                .onTapGesture(count: 2) {
                    startEdit()
                }
        }
    }
    
    // MARK: - Private Methods
    
    private func startEdit() {
        editedName = currentTrackName
        nameBeforeEdit = currentTrackName  // Capture original name for undo
        isEditing = true
    }
    
    private func commitEdit() {
        let trimmedName = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Don't allow empty names
        guard !trimmedName.isEmpty else {
            cancelEdit()
            return
        }
        
        // Only register undo if name actually changed
        if trimmedName != nameBeforeEdit {
            UndoService.shared.registerRenameTrack(trackId, oldName: nameBeforeEdit, newName: trimmedName, projectManager: projectManager)
        }
        
        // Update the track name in the project
        if var project = projectManager.currentProject,
           let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            project.tracks[trackIndex].name = trimmedName
            projectManager.currentProject = project
            projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        }
        
        isEditing = false
    }
    
    private func cancelEdit() {
        editedName = currentTrackName
        isEditing = false
    }
}
