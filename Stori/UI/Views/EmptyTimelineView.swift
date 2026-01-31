//
//  EmptyTimelineView.swift
//  Stori
//
//  Empty timeline view shown when no project is loaded
//

import SwiftUI

// MARK: - Empty Timeline View
struct EmptyTimelineView: View {
    let onCreateProject: () -> Void
    let onOpenProject: () -> Void
    var projectManager: ProjectManager
    
    var body: some View {
        // Full-width landing page without sidebar
        newProjectContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Content Views
    private var newProjectContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Hero section - positioned to use space efficiently
                VStack(spacing: 16) {
                    // Logo and tagline - centered
                    HStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .shadow(color: .blue.opacity(0.35), radius: 18, x: 0, y: 8)
                            
                            Image(systemName: "waveform")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Stori")
                                .font(.system(size: 42, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            
                            Text("Create. Own. Monetize.")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 24)
                
                // Main action cards - 3 columns
                HStack(spacing: 18) {
                    // DAW Card
                    ActionCard(
                        icon: "music.note",
                        iconGradient: [.blue, .purple],
                        title: "Create Music",
                        subtitle: "Professional DAW + AI Generation",
                        description: "Everything you need to produce professional music",
                        features: [
                            "🎹 128 GM Instruments + SoundFont support",
                            "🥁 Step Sequencer: 300+ patterns, 27 categories",
                            "🎛️ Mixing with instruments, inserts & plugins",
                            "🎤 Multi-track recording + Piano Roll/Score editor",
                            "🤖 AI Music/Audio generation: MusicGen + AudioGen",
                            "💬 LLM musical assistant for songwriting",
                            "🎨 AI image generation for album artwork",
                            "⚡ Real-time processing <10ms latency"
                        ],
                        primaryAction: "Create New Project",
                        secondaryAction: "Open Project",
                        onPrimaryAction: onCreateProject,
                        onSecondaryAction: onOpenProject
                    )
                    
                    // Marketplace Card - Coming Soon
                    ActionCard(
                        icon: "cart.fill",
                        iconGradient: [.cyan, .blue],
                        title: "Marketplace",
                        subtitle: "Trade Music NFTs",
                        description: "Buy, sell, and discover unique music stems",
                        features: [
                            "🎵 Browse music and art across all genres",
                            "🔊 Real-time audio preview from IPFS",
                            "💰 Transparent pricing + built-in royalties",
                            "📊 Market analytics + activity feeds",
                            "🖼️ Album artwork with every STEM",
                            "🔍 Advanced search + genre filtering",
                            "🔄 Buy, sell, and trade seamlessly",
                            "⛓️ Powered by Stori L1 on Avalanche"
                        ],
                        primaryAction: "Explore Marketplace",
                        secondaryAction: nil,
                        onPrimaryAction: { },
                        onSecondaryAction: nil,
                        comingSoon: true
                    )
                    
                    // Wallet Card - Coming Soon
                    ActionCard(
                        icon: "bitcoinsign.circle.fill",
                        iconGradient: [.purple, .pink],
                        title: "Wallet",
                        subtitle: "Manage Your Assets",
                        description: "Secure Stori wallet",
                        features: [
                            "💎 View TUS token and music portfolio",
                            "📲 EIP-681 compliant QR code payments",
                            "🔄 Send & receive TUS on Stori L1",
                            "📜 Complete transaction history",
                            "🔒 Automatic payment detection",
                            "🔑 BIP-32/39/44 HD wallet support",
                            "💾 Secure backup & recovery with seed phrase",
                            "⚡ Fast native L1 transactions"
                        ],
                        primaryAction: "Open Wallet",
                        secondaryAction: nil,
                        onPrimaryAction: { },
                        onSecondaryAction: nil,
                        comingSoon: true
                    )
                }
                .padding(.horizontal, 40)
                
                Spacer()
                    .frame(height: 18)
                
                // Bottom feature highlights - compact
                HStack(spacing: 36) {
                    QuickFeature(icon: "bolt.fill", color: .yellow, text: "<10ms Latency")
                    QuickFeature(icon: "cube.transparent", color: .cyan, text: "IPFS Storage")
                    QuickFeature(icon: "lock.shield.fill", color: .blue, text: "EIP-681 Payments")
                    QuickFeature(icon: "sparkles", color: .purple, text: "AI-Powered")
                    QuickFeature(icon: "chart.line.uptrend.xyaxis", color: .green, text: "Smart Royalties")
                }
                .padding(.horizontal, 40)
                
                Spacer()
                    .frame(height: 18)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
}

// MARK: - Feature Components

// Main action card for routing users to app sections
struct ActionCard: View {
    let icon: String
    let iconGradient: [Color]
    let title: String
    let subtitle: String
    let description: String
    let features: [String]
    let primaryAction: String
    let secondaryAction: String?
    let onPrimaryAction: () -> Void
    let onSecondaryAction: (() -> Void)?
    var comingSoon: Bool = false
    
    @State private var isHovered = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 12) {
                // Icon and title section
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: iconGradient.map { $0.opacity(0.15) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: icon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: iconGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                        
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: iconGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                    
                    Spacer()
                }
                
                // Description
                Text(description)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.bottom, 4)
                
                // Features grid - 2 cards per row
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(features, id: \.self) { feature in
                        FeatureListItem(text: feature, color: iconGradient[0])
                    }
                }
                
                Spacer(minLength: 4)
                
                // Action buttons - horizontal layout
                HStack(spacing: 8) {
                    if comingSoon {
                        // Coming Soon button style
                        Text("Coming Soon")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [.orange.opacity(0.8), .orange],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .shadow(color: Color.orange.opacity(0.4), radius: 6, x: 0, y: 3)
                    } else {
                        Button(action: onPrimaryAction) {
                            Text(primaryAction)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        colors: iconGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(10)
                                .shadow(color: iconGradient[0].opacity(0.4), radius: 6, x: 0, y: 3)
                        }
                        .buttonStyle(.plain)
                        
                        if let secondaryAction = secondaryAction,
                           let secondaryHandler = onSecondaryAction {
                            Button(action: secondaryHandler) {
                                Text(secondaryAction)
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Color(.controlBackgroundColor))
                                    .foregroundColor(.primary)
                                    .cornerRadius(10)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.controlBackgroundColor).opacity(isHovered ? 1 : 0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            colors: comingSoon 
                                ? [Color.orange.opacity(isHovered ? 0.6 : 0.25), Color.orange.opacity(isHovered ? 0.4 : 0.15)]
                                : iconGradient.map { $0.opacity(isHovered ? 0.6 : 0.25) },
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
            )
            .shadow(color: (comingSoon ? Color.orange : iconGradient[0]).opacity(isHovered ? 0.3 : 0.12), radius: 20, x: 0, y: 10)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
            
            // Coming Soon badge
            if comingSoon {
                Text("Coming Soon")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.orange)
                    )
                    .foregroundColor(.white)
                    .padding(12)
            }
        }
    }
}

// Grid-style feature card - centered design
struct FeatureListItem: View {
    let text: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            // Parse emoji from text
            if let firstChar = text.first, firstChar.unicodeScalars.first?.properties.isEmoji == true {
                Text(String(firstChar))
                    .font(.system(size: 32))
                
                Text(String(text.dropFirst()).trimmingCharacters(in: .whitespaces))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            } else {
                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(color.opacity(0.25), lineWidth: 1.5)
        )
    }
}

// Quick feature highlight at bottom
struct QuickFeature: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(color)
            
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}

