//
//  TrackNotificationsModifier.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - Track Notifications Modifier
struct TrackNotificationsModifier: ViewModifier {
    let onNewTrackDialog: () -> Void
    let onNewAudioTrack: () -> Void
    let onNewMIDITrack: () -> Void
    let onDeleteTrack: () -> Void
    let onImportAudio: () -> Void
    let onImportMIDI: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .newTrackDialog)) { _ in
                onNewTrackDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newTrack)) { _ in
                onNewTrackDialog()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newAudioTrack)) { _ in
                onNewAudioTrack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .newMIDITrack)) { _ in
                onNewMIDITrack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .deleteTrack)) { _ in
                onDeleteTrack()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importAudio)) { _ in
                onImportAudio()
            }
            .onReceive(NotificationCenter.default.publisher(for: .importMIDIFile)) { _ in
                onImportMIDI()
            }
    }
}
