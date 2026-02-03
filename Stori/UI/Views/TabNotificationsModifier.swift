//
//  TabNotificationsModifier.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - Tab Notifications Modifier
struct TabNotificationsModifier: ViewModifier {
    let onOpenChatTab: () -> Void
    let onOpenVisualTab: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openChatTab)) { _ in
                onOpenChatTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openVisualTab)) { _ in
                onOpenVisualTab()
            }
    }
}
