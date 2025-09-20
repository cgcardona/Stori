//
//  EditableProjectTitle.swift
//  TellUrStoriDAW
//
//  Editable project title component for the title bar
//

import SwiftUI

struct EditableProjectTitle: View {
    let projectName: String
    let onNameChanged: (String) -> Void
    
    @State private var isEditing = false
    @State private var editingText = ""
    @State private var showingError = false
    @State private var errorMessage = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var body: some View {
        Group {
            if isEditing {
                TextField("Project Name", text: $editingText)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        commitChanges()
                    }
                    .onKeyPress(.escape) {
                        cancelEditing()
                        return .handled
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.controlBackgroundColor))
                            .stroke(Color.accentColor, lineWidth: 2)
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                Text(projectName)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .onTapGesture(count: 2) {
                        startEditing()
                    }
                    .help("Double-click to rename project")
            }
        }
        .alert("Invalid Project Name", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
    }
    
    private func startEditing() {
        editingText = projectName
        isEditing = true
        
        // Focus the text field after a brief delay to ensure it's rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            isTextFieldFocused = true
        }
    }
    
    private func commitChanges() {
        let trimmedName = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate the name
        guard !trimmedName.isEmpty else {
            showError("Project name cannot be empty.")
            return
        }
        
        guard trimmedName != projectName else {
            // No change, just exit editing mode
            cancelEditing()
            return
        }
        
        // Attempt to rename the project
        onNameChanged(trimmedName)
        isEditing = false
        isTextFieldFocused = false
    }
    
    private func cancelEditing() {
        editingText = projectName
        isEditing = false
        isTextFieldFocused = false
    }
    
    private func showError(_ message: String) {
        errorMessage = message
        showingError = true
        // Keep editing mode active so user can correct the error
    }
}
