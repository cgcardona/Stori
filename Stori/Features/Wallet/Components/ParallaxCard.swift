//
//  ParallaxCard.swift
//  Stori
//
//  Parallax effect for cards that responds to mouse movement
//  Creates depth and premium feel on hover
//

import SwiftUI

/// Adds parallax 3D tilt effect on hover
struct ParallaxCardModifier: ViewModifier {
    let intensity: CGFloat
    @State private var offset: CGSize = .zero
    @State private var isHovered = false
    
    init(intensity: CGFloat = 1.0) {
        self.intensity = intensity
    }
    
    func body(content: Content) -> some View {
        GeometryReader { geometry in
            content
                .rotation3DEffect(
                    .degrees(Double(offset.width / 20) * intensity),
                    axis: (x: 0, y: 1, z: 0)
                )
                .rotation3DEffect(
                    .degrees(Double(-offset.height / 20) * intensity),
                    axis: (x: 1, y: 0, z: 0)
                )
                .scaleEffect(isHovered ? 1.02 : 1.0)
                .shadow(
                    color: Color.black.opacity(isHovered ? 0.15 : 0.08),
                    radius: isHovered ? 16 : 8,
                    y: isHovered ? 8 : 4
                )
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        let centerX = geometry.size.width / 2
                        let centerY = geometry.size.height / 2
                        
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            offset = CGSize(
                                width: (location.x - centerX) / 10 * intensity,
                                height: (location.y - centerY) / 10 * intensity
                            )
                            isHovered = true
                        }
                    case .ended:
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                            offset = .zero
                            isHovered = false
                        }
                    }
                }
        }
    }
}

extension View {
    /// Adds parallax tilt effect on hover
    /// - Parameter intensity: Strength of the effect (0.0 - 2.0, default 1.0)
    func parallaxTilt(intensity: CGFloat = 1.0) -> some View {
        modifier(ParallaxCardModifier(intensity: intensity))
    }
}

/// Holographic shimmer effect for NFT cards
struct HolographicShimmer: ViewModifier {
    @State private var shimmerOffset: CGFloat = -1.0
    let isHovered: Bool
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [
                        .clear,
                        .white.opacity(isHovered ? 0.3 : 0.0),
                        .pink.opacity(isHovered ? 0.2 : 0.0),
                        .blue.opacity(isHovered ? 0.2 : 0.0),
                        .clear
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .rotationEffect(.degrees(shimmerOffset * 45))
                .opacity(isHovered ? 1.0 : 0.0)
                .blendMode(.overlay)
                .animation(.easeInOut(duration: 0.6), value: isHovered)
            )
    }
}

extension View {
    /// Adds holographic shimmer overlay on hover
    func holographicShimmer(isHovered: Bool) -> some View {
        modifier(HolographicShimmer(isHovered: isHovered))
    }
}
