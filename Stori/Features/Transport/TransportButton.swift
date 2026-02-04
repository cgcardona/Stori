//
//  TransportButton.swift
//  Stori
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
    let accessibilityLabel: String?
    let accessibilityHint: String?
    let accessibilityValue: String?
    let accessibilityIdentifier: String?
    
    init(
        icon: String,
        isActive: Bool = false,
        color: Color = .accentColor,
        accessibilityLabel: String? = nil,
        accessibilityHint: String? = nil,
        accessibilityValue: String? = nil,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.isActive = isActive
        self.color = color
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.accessibilityValue = accessibilityValue
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            iconView
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(backgroundView)
        .scaleEffect(isActive ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isActive)
        // ACCESSIBILITY: Transport controls
        .accessibilityLabel(accessibilityLabel ?? "Button")
        .accessibilityHint(accessibilityHint ?? "")
        .accessibilityValue(accessibilityValue ?? "")
        .accessibilityIdentifier(accessibilityIdentifier ?? "")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .when(color == .red) { $0.accessibilityAddTraits(.playsSound) }
    }
    
    private var iconView: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(iconColor)
    }
    
    private var iconColor: Color {
        if isActive {
            return .white
        } else if color == .red {
            return color.opacity(0.9)
        } else {
            return .secondary
        }
    }
    
    private var backgroundView: some View {
        Circle()
            .fill(isActive ? color : Color.clear)
            .overlay(
                Circle()
                    .stroke(isActive ? color : Color.secondary.opacity(0.3), lineWidth: 1)
            )
    }
}

// MARK: - View Extension for Conditional Modifiers
private extension View {
    @ViewBuilder
    func when<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
