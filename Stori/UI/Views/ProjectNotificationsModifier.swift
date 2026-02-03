//
//  ProjectNotificationsModifier.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - Project Notifications Modifier
struct ProjectNotificationsModifier: ViewModifier {
    let audioEngine: AudioEngine
    let onSaveProject: () -> Void
    let onExportProject: () -> Void
    let onSkipToBeginning: () -> Void
    let onSkipToEnd: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .saveProject)) { _ in
                onSaveProject()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportProject)) { _ in
                onExportProject()
            }
            .onReceive(NotificationCenter.default.publisher(for: .skipToBeginning)) { _ in
                onSkipToBeginning()
            }
            .onReceive(NotificationCenter.default.publisher(for: .skipToEnd)) { _ in
                onSkipToEnd()
            }
            // Transport controls from menu
            .onReceive(NotificationCenter.default.publisher(for: .playPause)) { _ in
                if audioEngine.isPlaying {
                    audioEngine.pause()
                } else {
                    audioEngine.play()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .stop)) { _ in
                if audioEngine.isRecording {
                    audioEngine.stopRecording()
                } else {
                    audioEngine.stop()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .record)) { _ in
                if !audioEngine.isRecording {
                    audioEngine.record()
                }
            }
    }
}
