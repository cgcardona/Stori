//
//  UpdateBannerView.swift
//  Stori
//
//  A non-blocking banner shown the first time an update is detected.
//  Slides in from the top of the window and provides quick actions:
//  Download, Not Now (snooze), Skip Version, and Release Notes.
//
//  For large version gaps, shows additional context (e.g. "6 releases behind").
//

import SwiftUI

// MARK: - UpdateBannerView

struct UpdateBannerView: View {
    var updateService: UpdateService
    let release: ReleaseInfo
    @State private var showingReleaseSheet = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            updateIcon
            
            // Message
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button("Release Notes") {
                    showingReleaseSheet = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .accessibilityLabel("View release notes")
                
                Button("Not Now") {
                    updateService.snoozeUpdate(release)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .accessibilityLabel("Snooze update for \(UpdateService.snoozeDays) days")
                
                Button("Download") {
                    updateService.downloadUpdate(release)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Download update \(release.version.displayString)")
                
                // Dismiss (X)
                Button {
                    updateService.dismissBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss update banner")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(bannerBackground)
        .sheet(isPresented: $showingReleaseSheet) {
            UpdateSheetView(updateService: updateService)
        }
    }
    
    // MARK: - Components
    
    private var updateIcon: some View {
        ZStack {
            Circle()
                .fill(urgencyColor.opacity(0.15))
                .frame(width: 32, height: 32)
            
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(urgencyColor)
        }
    }
    
    private var bannerBackground: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.regularMaterial)
            .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(urgencyColor.opacity(0.2), lineWidth: 1)
            )
    }
    
    // MARK: - Content
    
    private var headline: String {
        if isSignificantlyBehind {
            return "You're several versions behind"
        }
        return "Stori \(release.version.displayString) is available"
    }
    
    private var subtitle: String {
        var parts: [String] = []
        
        if let count = updateService.releasesBehindCount, count > 1 {
            parts.append("\(count) releases behind")
        }
        
        let distance = updateService.currentVersion.distance(to: release.version)
        if distance.isMajorBehind {
            parts.append(distance.summary)
        }
        
        parts.append("Current: \(updateService.currentVersion.displayString)")
        parts.append(release.formattedSize)
        
        return parts.joined(separator: " \u{00B7} ")
    }
    
    private var isSignificantlyBehind: Bool {
        if let count = updateService.releasesBehindCount, count >= 3 {
            return true
        }
        let distance = updateService.currentVersion.distance(to: release.version)
        return distance.isMajorBehind || distance.minorDelta >= 2
    }
    
    private var iconName: String {
        if isSignificantlyBehind {
            return "exclamationmark.arrow.circlepath"
        }
        return "arrow.down.circle.fill"
    }
    
    private var urgencyColor: Color {
        switch updateService.urgency {
        case .low:    return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }
}
