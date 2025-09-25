//
//  TransportButton.swift
//  TellUrStoriDAW
//
//  Professional transport button component for DAW controls
//

import SwiftUI

// MARK: - Transport Button
struct TransportButton: View {
    let icon: String
    let isActive: Bool
    let color: Color
    let action: () -> Void
    
    init(icon: String, isActive: Bool = false, color: Color = .accentColor, action: @escaping () -> Void) {
        self.icon = icon
        self.isActive = isActive
        self.color = color
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(isActive ? .white : color)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isActive ? color : Color.clear)
                        .overlay(
                            Circle()
                                .stroke(color, lineWidth: 2)
                        )
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isActive ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isActive)
    }
}
