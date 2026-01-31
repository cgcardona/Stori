//
//  LibraryCard.swift
//  Stori
//
//  Created by TellUrStori on 12/10/25.
//

import SwiftUI

/// A beautiful card component displaying a purchased license in the library
struct LibraryCard: View {
    let license: PurchasedLicense
    let onPlay: () -> Void
    let onDownload: (() -> Void)?
    
    @State private var isHovering: Bool = false
    @State private var showingPlayPulse: Bool = false
    private let enforcer = LicenseEnforcer.shared
    
    private let accessControl: LicenseAccessControl
    
    init(license: PurchasedLicense, onPlay: @escaping () -> Void, onDownload: (() -> Void)? = nil) {
        self.license = license
        self.onPlay = onPlay
        self.onDownload = onDownload
        self.accessControl = LicenseAccessControl(licenseType: license.licenseType)
    }
    
    var body: some View {
        Button(action: onPlay) {
            cardContent
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.controlBackgroundColor))
                .shadow(color: .black.opacity(isHovering ? 0.2 : 0.1), radius: isHovering ? 8 : 4, y: isHovering ? 4 : 2)
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .disabled(license.accessState == .expired || license.accessState == .exhausted)
    }
    
    // MARK: - Card Content
    
    private var cardContent: some View {
        VStack(spacing: 0) {
            // Album Art with Badge Overlay
            ZStack(alignment: .topTrailing) {
                // Cover Art
                albumArt
                
                // License Type Badge
                licenseBadge
                    .padding(8)
                
                // Play Button Overlay
                if isHovering && license.accessState != .expired && license.accessState != .exhausted {
                    playOverlay
                }
                
                // Status Indicator (plays remaining, days left)
                if hasStatusIndicator {
                    statusIndicator
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
            }
            .frame(height: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            // Info Section
            VStack(alignment: .leading, spacing: 4) {
                Text(license.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                
                Text(license.artistName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Action Row (visual only - entire card is clickable)
                HStack(spacing: 8) {
                    // Play indicator
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundColor(license.accessState == .active ? .primary : .secondary)
                    
                    // Download indicator (if allowed)
                    if accessControl.canDownload {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                    
                    // Resell indicator (if allowed)
                    if accessControl.canResell {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                            .foregroundColor(.green.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    // Access State Icon
                    Image(systemName: license.accessState.icon)
                        .font(.system(size: 10))
                        .foregroundColor(license.accessState.color)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Album Art
    
    private var albumArt: some View {
        ZStack {
            // Try to load image from URL, fall back to gradient
            if let imageURL = license.imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        gradientPlaceholder
                    @unknown default:
                        gradientPlaceholder
                    }
                }
            } else {
                gradientPlaceholder
            }
            
            // Expired/Exhausted Overlay
            if license.accessState == .expired || license.accessState == .exhausted {
                Rectangle()
                    .fill(.black.opacity(0.5))
                
                VStack(spacing: 4) {
                    Image(systemName: license.accessState.icon)
                        .font(.title2)
                    Text(license.accessState.label)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
            }
        }
    }
    
    private var gradientPlaceholder: some View {
        ZStack {
            // Gradient Background (unique per license type)
            LinearGradient(
                colors: license.licenseType.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Pattern Overlay
            GeometryReader { geo in
                ForEach(0..<8, id: \.self) { i in
                    Circle()
                        .fill(.white.opacity(0.03))
                        .frame(width: CGFloat.random(in: 20...60))
                        .offset(
                            x: CGFloat.random(in: 0...geo.size.width),
                            y: CGFloat.random(in: 0...geo.size.height)
                        )
                }
            }
            
            // Music Icon
            Image(systemName: license.licenseType.systemIcon)
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.3))
        }
    }
    
    // MARK: - License Badge
    
    private var licenseBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: license.licenseType.systemIcon)
                .font(.system(size: 9))
            Text(badgeText)
                .font(.system(size: 9, weight: .semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .strokeBorder(.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .foregroundColor(.white)
    }
    
    private var badgeText: String {
        switch license.licenseType {
        case .fullOwnership: return "OWNED"
        case .streaming: return "STREAM"
        case .limitedPlay: return "LIMITED"
        case .timeLimited: return "TIMED"
        case .commercialLicense: return "COMMERCIAL"
        }
    }
    
    // MARK: - Play Overlay
    
    private var playOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.4))
            
            Button(action: {
                showingPlayPulse = true
                onPlay()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingPlayPulse = false
                }
            }) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 50, height: 50)
                        .scaleEffect(showingPlayPulse ? 1.2 : 1.0)
                        .opacity(showingPlayPulse ? 0 : 1)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "play.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.black)
                        .offset(x: 2)
                }
            }
            .buttonStyle(.plain)
        }
        .transition(.opacity)
    }
    
    // MARK: - Status Indicator
    
    @ViewBuilder
    private var statusIndicator: some View {
        switch license.licenseType {
        case .limitedPlay:
            let remaining = enforcer.getRemainingPlays(for: license)
            let total = license.totalPlays ?? 10
            HStack(spacing: 4) {
                Image(systemName: "play.circle")
                    .font(.system(size: 10))
                Text("\(remaining)/\(total)")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(remaining <= 3 ? Color.orange : Color.black.opacity(0.6))
            )
            .foregroundColor(.white)
            
        case .timeLimited:
            if let days = license.daysRemaining {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("\(days)d left")
                        .font(.system(size: 10, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(days <= 3 ? Color.orange : Color.black.opacity(0.6))
                )
                .foregroundColor(.white)
            }
            
        default:
            EmptyView()
        }
    }
    
    private var hasStatusIndicator: Bool {
        switch license.licenseType {
        case .limitedPlay:
            return true // Always show for limited play
        case .timeLimited:
            return license.daysRemaining != nil
        default:
            return false
        }
    }
}

// MARK: - List Row Variant

/// A list-style variant of the library card for list view mode
struct LibraryListRow: View {
    let license: PurchasedLicense
    let onPlay: () -> Void
    let onDownload: (() -> Void)?
    
    @State private var isHovering: Bool = false
    private let enforcer = LicenseEnforcer.shared
    
    private let accessControl: LicenseAccessControl
    
    init(license: PurchasedLicense, onPlay: @escaping () -> Void, onDownload: (() -> Void)? = nil) {
        self.license = license
        self.onPlay = onPlay
        self.onDownload = onDownload
        self.accessControl = LicenseAccessControl(licenseType: license.licenseType)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Mini Album Art - try to load image, fall back to gradient
            ZStack {
                if let imageURL = license.imageURL {
                    AsyncImage(url: imageURL) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        default:
                            listRowPlaceholder
                        }
                    }
                } else {
                    listRowPlaceholder
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            
            // Info
            VStack(alignment: .leading, spacing: 2) {
                Text(license.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                Text(license.artistName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // License Type Badge
            Text(license.licenseType.shortTitle)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(license.licenseType.gradientColors.first?.opacity(0.2) ?? Color.gray.opacity(0.2))
                )
                .foregroundColor(license.licenseType.gradientColors.first ?? .gray)
            
            // Status
            if let statusText = statusText {
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(license.accessState.color)
                    .frame(width: 60, alignment: .trailing)
            }
            
            // Actions
            HStack(spacing: 8) {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(license.accessState == .active ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(license.accessState == .expired || license.accessState == .exhausted)
                
                if accessControl.canDownload {
                    Button(action: { onDownload?() }) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                }
            }
            .opacity(isHovering ? 1 : 0.6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isHovering ? Color(.controlBackgroundColor) : Color.clear)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
    
    private var listRowPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: license.licenseType.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: license.licenseType.systemIcon)
                .font(.system(size: 16))
                .foregroundColor(.white.opacity(0.5))
        }
    }
    
    private var statusText: String? {
        switch license.licenseType {
        case .limitedPlay:
            let remaining = enforcer.getRemainingPlays(for: license)
            return "\(remaining) plays"
        case .timeLimited:
            if let days = license.daysRemaining {
                return "\(days) days"
            }
        default:
            if license.accessState == .expired {
                return "Expired"
            } else if license.accessState == .exhausted {
                return "No plays"
            }
        }
        return nil
    }
}

// MARK: - License Type Extensions

extension LicenseType {
    var shortTitle: String {
        switch self {
        case .fullOwnership: return "Own"
        case .streaming: return "Stream"
        case .limitedPlay: return "Limited"
        case .timeLimited: return "Timed"
        case .commercialLicense: return "Commercial"
        }
    }
}


