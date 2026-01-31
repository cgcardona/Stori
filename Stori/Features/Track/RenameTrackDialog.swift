//
//  RenameTrackDialog.swift
//  Stori
//
//  Simple dialog for renaming a track
//

import SwiftUI

struct RenameTrackDialog: View {
    @Binding var trackName: String
    let onRename: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Rename Track")
                .font(.title2.weight(.semibold))
            
            TextField("Track Name", text: $trackName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit {
                    handleRename()
                }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Button("Rename") {
                    handleRename()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(trackName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400, height: 150)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func handleRename() {
        guard !trackName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        onRename()
        dismiss()
    }
}

