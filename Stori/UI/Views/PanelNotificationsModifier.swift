//
//  PanelNotificationsModifier.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - Panel Notifications Modifier
struct PanelNotificationsModifier: ViewModifier {
    let onToggleMixer: () -> Void
    let onToggleInspector: () -> Void
    let onToggleSelection: () -> Void
    let onOpenTrackInspector: () -> Void
    let onOpenRegionInspector: () -> Void
    let onOpenProjectInspector: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleMixer)) { _ in
                onToggleMixer()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
                onToggleInspector()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleSelection)) { _ in
                onToggleSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openTrackInspector)) { _ in
                onOpenTrackInspector()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRegionInspector)) { _ in
                onOpenRegionInspector()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openProjectInspector)) { _ in
                onOpenProjectInspector()
            }
    }
}
