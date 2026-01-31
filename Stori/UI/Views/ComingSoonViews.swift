//
//  ComingSoonViews.swift
//  Stori
//
//  Coming Soon teaser views for Marketplace and Wallet
//

import SwiftUI

// MARK: - Marketplace Coming Soon View

struct MarketplaceComingSoonView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding()
            }
            
            ScrollView {
                VStack(spacing: 24) {
                    // Hero section
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.cyan.opacity(0.3), Color.blue.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "cart.fill")
                                .font(.system(size: 44, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.cyan, .blue],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        Text("Stori Marketplace")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .blue],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Coming Soon")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.orange)
                            )
                            .foregroundColor(.white)
                        
                        Text("Trade unique music STEMs as NFTs on Stori L1")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 20)
                    
                    // Features grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ComingSoonFeatureCard(
                            icon: "music.note.list",
                            color: .cyan,
                            title: "Browse STEMs",
                            description: "Discover music across all genres"
                        )
                        
                        ComingSoonFeatureCard(
                            icon: "speaker.wave.3.fill",
                            color: .blue,
                            title: "Audio Preview",
                            description: "Real-time streaming from IPFS"
                        )
                        
                        ComingSoonFeatureCard(
                            icon: "dollarsign.circle.fill",
                            color: .green,
                            title: "Fair Pricing",
                            description: "Transparent pricing with royalties"
                        )
                        
                        ComingSoonFeatureCard(
                            icon: "chart.bar.fill",
                            color: .purple,
                            title: "Analytics",
                            description: "Track market activity"
                        )
                        
                        ComingSoonFeatureCard(
                            icon: "photo.artframe",
                            color: .pink,
                            title: "Album Artwork",
                            description: "AI-generated art with every STEM"
                        )
                        
                        ComingSoonFeatureCard(
                            icon: "magnifyingglass",
                            color: .orange,
                            title: "Advanced Search",
                            description: "Filter by genre, BPM, key"
                        )
                    }
                    .padding(.horizontal, 40)
                    
                    // Blockchain info
                    HStack(spacing: 12) {
                        Image(systemName: "link")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.cyan)
                        
                        Text("Powered by Stori L1 on Avalanche")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 16)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Composer Panel Coming Soon View (Inspector right panel)

struct ComposerComingSoonView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Composer")
                .font(.system(size: 18, weight: .semibold))
            Text("Coming Soon")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            Text("AI-powered project creation will be available via the Composer service.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Tokenize Project Coming Soon View

struct TokenizeComingSoonView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding()
            }
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)
                Text("Tokenize Project")
                    .font(.system(size: 24, weight: .bold))
                Text("Coming Soon")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.secondary)
                Text("Convert your STEMs to NFTs on Stori L1.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Spacer()
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Wallet Coming Soon View

struct WalletComingSoonView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding()
            }
            
            ScrollView {
                VStack(spacing: 24) {
                    // Hero section
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.purple.opacity(0.3), Color.pink.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "wallet.bifold")
                                .font(.system(size: 44, weight: .medium))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.purple, .pink],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                        }
                        
                        Text("Stori Wallet")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .pink],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Coming Soon")
                            .font(.system(size: 18, weight: .semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.orange)
                            )
                            .foregroundColor(.white)
                        
                        Text("Secure self-custodial wallet for TUS tokens and NFTs")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                    .padding(.top, 20)
                    
                    // Features grid
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 16),
                        GridItem(.flexible(), spacing: 16)
                    ], spacing: 16) {
                        ComingSoonFeatureCard(
                            icon: "lock.shield.fill",
                            color: .green,
                            title: "Secure Storage",
                            description: "Keys in macOS Keychain"
                        )
                        
                        ComingSoonFeatureCard(
                            icon: "key.fill",
                            color: .blue,
                            title: "HD Wallet",
                            description: "BIP-32/39/44 standard"
                        )
                        
                        ComingSoonFeatureCard(
                            icon: "bitcoinsign.circle.fill",
                            color: .orange,
                            title: "TUS Tokens",
                            description: "Native L1 transactions"
                        )
                        
                        ComingSoonFeatureCard(
                            icon: "photo.stack.fill",
                            color: .purple,
                            title: "NFT Portfolio",
                            description: "View your STEM collection"
                        )
                        
                        ComingSoonFeatureCard(
                            icon: "qrcode",
                            color: .cyan,
                            title: "QR Payments",
                            description: "EIP-681 compliant"
                        )
                        
                        ComingSoonFeatureCard(
                            icon: "clock.arrow.circlepath",
                            color: .pink,
                            title: "History",
                            description: "Complete transaction records"
                        )
                    }
                    .padding(.horizontal, 40)
                    
                    // Security info
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.green)
                        
                        Text("Self-custodial: You own your keys")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 16)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Coming Soon Feature Card

struct ComingSoonFeatureCard: View {
    let icon: String
    let color: Color
    let title: String
    let description: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(color)
            
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
            
            Text(description)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(color.opacity(0.2), lineWidth: 1.5)
        )
    }
}
