//
//  DAWControlButton.swift
//  Stori
//
//  DAW-style control button for view toggles and utilities
//

import SwiftUI

struct DAWControlButton: View {
    let icon: String
    let isActive: Bool
    let tooltip: String
    let accessibilityLabel: String?
    let accessibilityIdentifier: String?
    let action: () -> Void
    
    init(
        icon: String,
        isActive: Bool,
        tooltip: String,
        accessibilityLabel: String? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.isActive = isActive
        self.tooltip = tooltip
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(isActive ? .white : .secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isActive ? Color.accentColor : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
        .help(tooltip)
        .scaleEffect(isActive ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isActive)
        // ACCESSIBILITY: View toggle buttons
        .accessibilityLabel(accessibilityLabel ?? tooltip.components(separatedBy: "(").first?.trimmingCharacters(in: .whitespaces) ?? "Button")
        .accessibilityHint("Toggle panel visibility")
        .accessibilityValue(isActive ? "Visible" : "Hidden")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
    }
}
