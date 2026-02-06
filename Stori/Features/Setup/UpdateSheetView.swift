//
//  UpdateSheetView.swift
//  Stori
//
//  Full update details sheet with release notes, download progress,
//  and install actions. This is the primary update UI surface.
//

import SwiftUI

// MARK: - UpdateSheetView

struct UpdateSheetView: View {
    var updateService: UpdateService
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content (scrollable)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Version info
                    versionInfoSection
                    
                    // "Behind" indicator
                    if let count = updateService.releasesBehindCount, count > 1 {
                        behindIndicator(count: count)
                    }
                    
                    // Release notes
                    if let release = currentRelease, !release.releaseNotes.isEmpty {
                        releaseNotesSection(notes: release.releaseNotes)
                    }
                    
                    // Download progress
                    if case .downloading(let progress) = updateService.state {
                        downloadProgressSection(progress: progress)
                    }
                    
                    // Downloaded / ready to install
                    if case .downloaded(let fileURL, _) = updateService.state {
                        downloadedSection(fileURL: fileURL)
                    }
                    
                    // Error
                    if case .error(let error) = updateService.state {
                        errorSection(error: error)
                    }
                    
                    // Up to date
                    if case .upToDate = updateService.state {
                        upToDateSection
                    }
                    
                    // Ahead of release
                    if case .aheadOfRelease = updateService.state {
                        aheadSection
                    }
                }
                .padding(24)
            }
            
            Divider()
            
            // Footer actions
            footerActions
        }
        .frame(width: 500)
        .frame(minHeight: 420, maxHeight: 600)
    }
    
    // MARK: - Current Release
    
    private var currentRelease: ReleaseInfo? {
        switch updateService.state {
        case .updateAvailable(let r): return r
        case .downloading: return nil
        case .downloaded(_, let r): return r
        default: return nil
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(spacing: 14) {
            // App icon placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.8), .purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(headerTitle)
                    .font(.system(size: 16, weight: .semibold))
                
                Text("Current: \(updateService.versionDisplayString)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Urgency badge
            if updateService.hasUpdate {
                urgencyBadge
            }
        }
        .padding(20)
    }
    
    private var headerTitle: String {
        switch updateService.state {
        case .updateAvailable(let r):
            return "Stori \(r.version.displayString) Available"
        case .downloading:
            return "Downloading Update..."
        case .downloaded(_, let r):
            return "Stori \(r.version.displayString) Ready"
        case .upToDate:
            return "Stori is Up to Date"
        case .aheadOfRelease:
            return "Development Build"
        case .error:
            return "Update Check Failed"
        default:
            return "Software Update"
        }
    }
    
    private var urgencyBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(urgencyColor)
                .frame(width: 6, height: 6)
            
            Text(urgencyLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(urgencyColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(urgencyColor.opacity(0.1))
        )
    }
    
    private var urgencyColor: Color {
        switch updateService.urgency {
        case .low:    return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }
    
    private var urgencyLabel: String {
        switch updateService.urgency {
        case .low:    return "New"
        case .medium: return "Recommended"
        case .high:   return "Important"
        }
    }
    
    // MARK: - Version Info
    
    private var versionInfoSection: some View {
        HStack(spacing: 16) {
            if let release = currentRelease {
                VStack(spacing: 4) {
                    Text(updateService.currentVersion.displayString)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("Installed")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 4) {
                    Text(release.version.displayString)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.blue)
                    Text(release.formattedSize)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Behind Indicator
    
    private func behindIndicator(count: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 14))
            
            Text("You're \(count) releases behind. We recommend updating to get the latest features and fixes.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.08))
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    // MARK: - Release Notes
    
    private func releaseNotesSection(notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's New")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            
            Text(notes)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.controlBackgroundColor))
                )
        }
    }
    
    // MARK: - Download Progress
    
    private func downloadProgressSection(progress: DownloadProgress) -> some View {
        VStack(spacing: 10) {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)
            
            HStack {
                Text(progress.formattedProgress)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(progress.percent)%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.blue)
            }
            
            Button("Cancel Download") {
                updateService.cancelDownload()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.red)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.controlBackgroundColor))
        )
    }
    
    // MARK: - Downloaded
    
    private func downloadedSection(fileURL: URL) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download Complete")
                        .font(.system(size: 13, weight: .semibold))
                    Text(fileURL.lastPathComponent)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("To install the update:")
                    .font(.system(size: 12, weight: .medium))
                
                installStep(number: 1, text: "Quit Stori")
                installStep(number: 2, text: "Open the downloaded file")
                installStep(number: 3, text: "Drag Stori into your Applications folder (replace existing)")
                installStep(number: 4, text: "Relaunch Stori")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.controlBackgroundColor))
            )
            
            Text("Your projects and settings will be preserved.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .italic()
        }
    }
    
    private func installStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.blue)
                .frame(width: 20, alignment: .trailing)
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Error
    
    private func errorSection(error: UpdateError) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(error.localizedDescription)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                
                if error.isRetryable {
                    Text("We'll try again automatically.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.08))
                .stroke(Color.red.opacity(0.2), lineWidth: 0.5)
        )
    }
    
    // MARK: - Up to Date
    
    private var upToDateSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .font(.system(size: 20))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("You're on the latest version")
                    .font(.system(size: 13, weight: .medium))
                
                if let lastCheck = updateService.store.lastCheckDate {
                    Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Ahead
    
    private var aheadSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "hammer.fill")
                .foregroundColor(.secondary)
                .font(.system(size: 16))
            
            VStack(alignment: .leading, spacing: 2) {
                Text("You're on a newer build than the latest release")
                    .font(.system(size: 13, weight: .medium))
                
                Text("This is a development or pre-release build.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Footer Actions
    
    private var footerActions: some View {
        HStack(spacing: 12) {
            // Left-aligned secondary actions
            if let release = currentRelease {
                Button("Skip This Version") {
                    updateService.skipVersion(release)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .accessibilityLabel("Skip version \(release.version.displayString)")
                
                Button("Not Now") {
                    updateService.snoozeUpdate(release)
                    dismiss()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .accessibilityLabel("Snooze for \(UpdateService.snoozeDays) days")
            }
            
            Spacer()
            
            // Right-aligned primary action
            primaryActionButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    @ViewBuilder
    private var primaryActionButton: some View {
        switch updateService.state {
        case .updateAvailable(let release):
            HStack(spacing: 8) {
                Button("View on GitHub") {
                    updateService.openReleasePage(release)
                }
                .accessibilityLabel("Open release page in browser")
                
                Button("Download Update") {
                    updateService.downloadUpdate(release)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Download update \(release.version.displayString)")
            }
            
        case .downloading:
            Button("Cancel") {
                updateService.cancelDownload()
            }
            .accessibilityLabel("Cancel download")
            
        case .downloaded(let fileURL, _):
            HStack(spacing: 8) {
                Button("Show in Finder") {
                    updateService.installUpdate(from: fileURL)
                }
                .accessibilityLabel("Reveal downloaded file in Finder")
                
                Button("Open") {
                    updateService.openDownloadedFile(fileURL)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Open downloaded update file")
            }
            
        case .error(let error):
            if error.isRetryable {
                Button("Try Again") {
                    Task {
                        await updateService.checkNow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Retry update check")
            }
            
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
        default:
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
    }
}
