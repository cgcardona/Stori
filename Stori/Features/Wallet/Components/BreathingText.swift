//
//  BreathingText.swift
//  Stori
//
//  Subtle breathing animation for balance display - creates ambient life
//

import SwiftUI

/// Text that gently pulses with a breathing animation
/// Used for portfolio balance to create subtle ambient life
struct BreathingText: View {
    let text: String
    let font: Font
    let color: Color
    
    @State private var opacity: Double = 0.85
    
    init(_ text: String, font: Font = .body, color: Color = .primary) {
        self.text = text
        self.font = font
        self.color = color
    }
    
    var body: some View {
        Text(text)
            .font(font)
            .foregroundColor(color)
            .opacity(opacity)
            .onAppear {
                // Start breathing animation after brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(
                        .easeInOut(duration: 2.5)
                        .repeatForever(autoreverses: true)
                    ) {
                        opacity = 1.0
                    }
                }
            }
    }
}

/// Glow overlay that pulses when balance updates
struct BalanceGlowEffect: ViewModifier {
    let isUpdating: Bool
    @State private var glowOpacity: Double = 0.0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                content
                    .foregroundColor(.white)
                    .blur(radius: 8)
                    .opacity(glowOpacity)
            )
            .onChange(of: isUpdating) { _, newValue in
                if newValue {
                    // Pulse when updating
                    withAnimation(.easeOut(duration: 0.3)) {
                        glowOpacity = 0.6
                    }
                } else {
                    // Fade out after update
                    withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                        glowOpacity = 0.0
                    }
                }
            }
    }
}

extension View {
    func balanceGlow(isUpdating: Bool) -> some View {
        modifier(BalanceGlowEffect(isUpdating: isUpdating))
    }
}
