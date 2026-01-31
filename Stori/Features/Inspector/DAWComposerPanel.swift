//
//  DAWComposerPanel.swift
//  Stori
//
//  Composer panel for AI-powered music creation
//

import SwiftUI

struct DAWComposerPanel: View {
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    
    var body: some View {
        VStack(spacing: 0) {
            // Cursor-style composer interface
            ComposerView()
                .environment(projectManager)
                .environment(audioEngine)
        }
        .background(Color(.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(.separatorColor)),
            alignment: .leading
        )
    }
}
