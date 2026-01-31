//
//  VaultIntroStep.swift
//  Stori
//
//  Introductory step for wallet creation - establishes self-custody philosophy
//

import SwiftUI

struct VaultIntroStep: View {
    let onContinue: () -> Void
    @State private var showContent = false
    @State private var showPrinciples = false
    @State private var showButton = false
    
    var body: some View {
        VStack(spacing: 32) {
            // Animated vault icon
            AnimatedVaultIcon()
                .frame(width: 120, height: 120)
                .opacity(showContent ? 1 : 0)
                .scaleEffect(showContent ? 1 : 0.8)
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: showContent)
            
            // Main message
            VStack(spacing: 12) {
                Text("Your Vault. Your Keys. Your Music.")
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                
                Text("This wallet gives you complete ownership of your digital assets. No company, not even Stori, can access your funds.")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 450)
            }
            .opacity(showContent ? 1 : 0)
            .offset(y: showContent ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.3), value: showContent)
            
            // Key principles
            HStack(spacing: 24) {
                PrincipleCard(
                    icon: "key.fill",
                    title: "Self-Custody",
                    description: "Only you control your keys"
                )
                
                PrincipleCard(
                    icon: "lock.shield.fill",
                    title: "Encrypted",
                    description: "Protected by macOS Keychain"
                )
                
                PrincipleCard(
                    icon: "person.badge.key.fill",
                    title: "Your Identity",
                    description: "One address, infinite possibilities"
                )
            }
            .opacity(showPrinciples ? 1 : 0)
            .offset(y: showPrinciples ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.5), value: showPrinciples)
            
            Spacer()
            
            // Continue button
            Button(action: onContinue) {
                HStack(spacing: 8) {
                    Text("Create My Vault")
                        .fontWeight(.semibold)
                    Image(systemName: "arrow.right")
                }
                .frame(minWidth: 200)
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [hexColor("6366F1"), hexColor("8B5CF6")],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(12)
                .shadow(color: Color.purple.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.7), value: showButton)
        }
        .padding(32)
        .onAppear {
            showContent = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showPrinciples = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showButton = true
            }
        }
    }
}

// MARK: - Animated Vault Icon

struct AnimatedVaultIcon: View {
    @State private var isUnlocking = false
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            hexColor("8B5CF6").opacity(0.3),
                            hexColor("8B5CF6").opacity(0.1),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: 60
                    )
                )
                .frame(width: 120, height: 120)
            
            // Main vault
            ZStack {
                Circle()
                    .fill(hexColor("8B5CF6").opacity(0.15))
                    .frame(width: 90, height: 90)
                
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [hexColor("6366F1"), hexColor("8B5CF6")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
    }
}

// MARK: - Principle Card

struct PrincipleCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(hexColor("8B5CF6").opacity(0.1))
                    .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(hexColor("8B5CF6"))
            }
            
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                
                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(hexColor("8B5CF6").opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Helper

private func hexColor(_ hex: String) -> Color {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    let a, r, g, b: UInt64
    switch hex.count {
    case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
    case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
    case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
    default: (a, r, g, b) = (255, 0, 0, 0)
    }
    return Color(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
}
