//
//  PortfolioShimmer.swift
//  Stori
//
//  Subtle shimmer effect for portfolio card gradient
//  Creates premium, alive feeling
//

import SwiftUI

/// Adds subtle animated shimmer to gradient backgrounds
struct PortfolioShimmerModifier: ViewModifier {
    @State private var shimmerPosition: CGFloat = -1.0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.15),
                            .white.opacity(0.25),
                            .white.opacity(0.15),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 0.3)
                    .offset(x: shimmerPosition * geometry.size.width)
                    .blendMode(.overlay)
                }
            )
            .onAppear {
                // Start shimmer animation after brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    withAnimation(
                        .linear(duration: 3.0)
                        .repeatForever(autoreverses: false)
                    ) {
                        shimmerPosition = 2.0
                    }
                }
            }
    }
}

extension View {
    /// Adds subtle shimmer animation to portfolio gradient backgrounds
    func portfolioShimmer() -> some View {
        modifier(PortfolioShimmerModifier())
    }
}

/// Pulsing glow effect for portfolio card
struct PortfolioPulseGlow: ViewModifier {
    @State private var glowIntensity: Double = 0.2
    
    func body(content: Content) -> some View {
        content
            .shadow(
                color: Color.purple.opacity(glowIntensity),
                radius: 20,
                x: 0,
                y: 10
            )
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 3.0)
                    .repeatForever(autoreverses: true)
                ) {
                    glowIntensity = 0.35
                }
            }
    }
}

extension View {
    /// Adds pulsing glow effect to portfolio card
    func portfolioPulseGlow() -> some View {
        modifier(PortfolioPulseGlow())
    }
}
