//
//  MIDINotificationModifier.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - MIDI Notification Modifier

struct MIDINotificationModifier: ViewModifier {
    @Binding var activeSheet: DAWSheet?
    let onTogglePianoRoll: () -> Void
    let onToggleSynthesizer: () -> Void
    let onToggleStepSequencer: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleVirtualKeyboard)) { _ in
                if activeSheet == .virtualKeyboard {
                    activeSheet = nil
                } else {
                    activeSheet = .virtualKeyboard
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .togglePianoRoll)) { _ in
                onTogglePianoRoll()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSynthesizer)) { _ in
                onToggleSynthesizer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleStepSequencer)) { _ in
                onToggleStepSequencer()
            }
    }
}
