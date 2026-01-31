//
//  PolishComponents.swift
//  Stori
//
//  Polished UI components with animations, loading states, and celebrations.
//  Phase 6: Production-ready polish.
//
//  Created by TellUrStori on 12/10/25.
//

import SwiftUI

// MARK: - Skeleton Loading Views

/// Animated skeleton loading placeholder for cards
struct SkeletonCard: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Cover skeleton
            RoundedRectangle(cornerRadius: 12)
                .fill(skeletonGradient)
                .frame(height: 160)
            
            // Text skeletons
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonGradient)
                    .frame(width: 120, height: 14)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonGradient)
                    .frame(width: 80, height: 10)
            }
            .padding(8)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.controlBackgroundColor))
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private var skeletonGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.gray.opacity(isAnimating ? 0.15 : 0.25),
                Color.gray.opacity(isAnimating ? 0.25 : 0.15)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

/// Skeleton loading grid for library/marketplace
struct SkeletonGrid: View {
    let columns: Int
    let count: Int
    
    init(columns: Int = 4, count: Int = 8) {
        self.columns = columns
        self.count = count
    }
    
    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: columns),
            spacing: 20
        ) {
            ForEach(0..<count, id: \.self) { index in
                SkeletonCard()
                    .opacity(1 - Double(index) * 0.08)
                    .animation(
                        .easeInOut(duration: 0.3).delay(Double(index) * 0.05),
                        value: index
                    )
            }
        }
        .padding(20)
    }
}

// MARK: - Purchase Success Celebration

/// Confetti celebration view for successful purchases
struct ConfettiView: View {
    @State private var confettiPieces: [ConfettiPiece] = []
    @State private var isAnimating = false
    
    let colors: [Color] = [
        .red, .orange, .yellow, .green, .blue, .purple, .pink,
        Color(red: 1, green: 0.84, blue: 0), // Gold
        Color(red: 0, green: 1, blue: 0.8)   // Cyan
    ]
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(confettiPieces) { piece in
                    ConfettiPieceView(piece: piece)
                }
            }
            .onAppear {
                generateConfetti(in: geometry.size)
            }
        }
        .allowsHitTesting(false)
    }
    
    private func generateConfetti(in size: CGSize) {
        for i in 0..<50 {
            let piece = ConfettiPiece(
                id: i,
                color: colors.randomElement() ?? .yellow,
                startX: size.width / 2,
                startY: size.height / 2,
                endX: CGFloat.random(in: 0...size.width),
                endY: CGFloat.random(in: -50...size.height + 100),
                rotation: Double.random(in: 0...720),
                scale: CGFloat.random(in: 0.5...1.5),
                delay: Double.random(in: 0...0.3)
            )
            confettiPieces.append(piece)
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id: Int
    let color: Color
    let startX: CGFloat
    let startY: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let rotation: Double
    let scale: CGFloat
    let delay: Double
}

struct ConfettiPieceView: View {
    let piece: ConfettiPiece
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(piece.color)
            .frame(width: 8 * piece.scale, height: 12 * piece.scale)
            .position(
                x: isAnimating ? piece.endX : piece.startX,
                y: isAnimating ? piece.endY : piece.startY
            )
            .rotationEffect(.degrees(isAnimating ? piece.rotation : 0))
            .opacity(isAnimating ? 0 : 1)
            .onAppear {
                withAnimation(
                    .easeOut(duration: 1.5)
                    .delay(piece.delay)
                ) {
                    isAnimating = true
                }
            }
    }
}

/// Success celebration overlay
struct PurchaseSuccessOverlay: View {
    let title: String
    let transactionHash: String?
    let onDismiss: () -> Void
    
    @State private var showConfetti = false
    @State private var showContent = false
    @State private var pulseScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Confetti
            if showConfetti {
                ConfettiView()
            }
            
            // Content
            VStack(spacing: 24) {
                // Success checkmark with pulse
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .scaleEffect(pulseScale)
                    
                    Circle()
                        .fill(Color.green)
                        .frame(width: 80, height: 80)
                    
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                }
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1 : 0.5)
                
                // Text
                VStack(spacing: 8) {
                    Text("Purchase Complete!")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if let hash = transactionHash {
                        HStack(spacing: 4) {
                            Image(systemName: "link")
                                .font(.caption2)
                            Text(String(hash.prefix(8)) + "..." + String(hash.suffix(6)))
                                .font(.system(.caption, design: .monospaced))
                        }
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.top, 4)
                    }
                }
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
                
                // Button
                Button(action: onDismiss) {
                    Text("Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: 200)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 20)
            }
            .padding(40)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showContent = true
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                showConfetti = true
            }
            
            // Pulse animation
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                pulseScale = 1.2
            }
        }
    }
}

// MARK: - Staggered Appear Animation

/// Modifier for staggered list/grid appearance
struct StaggeredAppearModifier: ViewModifier {
    let index: Int
    let total: Int
    @State private var hasAppeared = false
    
    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 20)
            .onAppear {
                withAnimation(
                    .spring(response: 0.4, dampingFraction: 0.8)
                    .delay(Double(index) * 0.05)
                ) {
                    hasAppeared = true
                }
            }
    }
}

extension View {
    func staggeredAppear(index: Int, total: Int = 10) -> some View {
        modifier(StaggeredAppearModifier(index: index, total: total))
    }
}

// MARK: - Shimmer Effect

/// Shimmer loading effect
struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        colors: [
                            .clear,
                            .white.opacity(0.3),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + (phase * geometry.size.width * 2))
                }
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Error Banner

/// Animated error banner with retry
struct ErrorBanner: View {
    let message: String
    let onRetry: (() -> Void)?
    let onDismiss: () -> Void
    
    @State private var isVisible = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
            
            if let retry = onRetry {
                Button("Retry") {
                    retry()
                }
                .font(.subheadline.weight(.medium))
                .foregroundColor(.accentColor)
            }
            
            Button {
                withAnimation(.spring()) {
                    isVisible = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onDismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.orange.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
        .offset(y: isVisible ? 0 : -100)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Loading Spinner with Message

struct LoadingView: View {
    let message: String
    @State private var rotation: Double = 0
    
    var body: some View {
        VStack(spacing: 16) {
            Circle()
                .trim(from: 0, to: 0.7)
                .stroke(
                    LinearGradient(
                        colors: [.accentColor, .accentColor.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
                .onAppear {
                    withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                        rotation = 360
                    }
                }
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Accessibility Helpers

extension View {
    /// Add comprehensive accessibility
    func accessibleCard(
        label: String,
        hint: String,
        traits: AccessibilityTraits = .isButton
    ) -> some View {
        self
            .accessibilityElement(children: .combine)
            .accessibilityLabel(label)
            .accessibilityHint(hint)
            .accessibilityAddTraits(traits)
    }
    
    /// Add license status to accessibility
    func accessibleLicenseStatus(_ license: PurchasedLicense) -> some View {
        let status: String
        switch license.licenseType {
        case .fullOwnership:
            status = "Full ownership, downloadable"
        case .streaming:
            status = "Streaming only"
        case .limitedPlay:
            let remaining = license.playsRemaining ?? 0
            status = "\(remaining) plays remaining"
        case .timeLimited:
            if let days = license.daysRemaining {
                status = "\(days) days remaining"
            } else {
                status = "Time limited"
            }
        case .commercialLicense:
            status = "Commercial license, downloadable"
        }
        
        return self.accessibilityValue(status)
    }
}

// MARK: - Haptic Feedback (macOS compatible)

struct HapticFeedback {
    static func success() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .default
        )
        #endif
    }
    
    static func error() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .levelChange,
            performanceTime: .default
        )
        #endif
    }
    
    static func selection() {
        #if os(macOS)
        NSHapticFeedbackManager.defaultPerformer.perform(
            .generic,
            performanceTime: .default
        )
        #endif
    }
}

