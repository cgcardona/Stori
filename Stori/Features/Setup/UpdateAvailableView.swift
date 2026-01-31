//
//  UpdateAvailableView.swift
//  Stori
//
//  UI for displaying available updates and handling the download/install flow.
//

import SwiftUI

// MARK: - UpdateAvailableView

struct UpdateAvailableView: View {
    @Bindable var updateManager: UpdateManager
    let release: ReleaseInfo
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Update Available")
                        .font(.headline)
                    
                    HStack(spacing: 4) {
                        Text("v\(updateManager.currentVersion)")
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("v\(release.version)")
                            .foregroundColor(.blue)
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
                }
                
                Spacer()
                
                if release.criticalUpdate == true {
                    Label("Critical", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            Divider()
            
            // Release notes
            if let notes = release.releaseNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("What's New")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(notes, id: \.self) { note in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(Color.blue)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 6)
                                    
                                    Text(note)
                                        .font(.callout)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 150)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()
            
            // Download progress (if downloading)
            if case .downloading(let progress) = updateManager.state {
                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    
                    Text("Downloading... \(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Ready to install
            if case .readyToInstall(let dmgURL) = updateManager.state {
                VStack(spacing: 8) {
                    Label("Download Complete", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    Text("Click 'Install' to open the update.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            // Error state
            if case .error(let message) = updateManager.state {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button("Remind Me Later") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("Skip This Version") {
                    updateManager.skipVersion(release.version)
                    dismiss()
                }
                
                Spacer()
                
                // Primary action button
                Group {
                    switch updateManager.state {
                    case .available:
                        Button("Download Update") {
                            Task {
                                await updateManager.downloadUpdate()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        
                    case .downloading:
                        Button("Downloading...") {}
                            .disabled(true)
                            .buttonStyle(.borderedProminent)
                        
                    case .readyToInstall(let dmgURL):
                        Button("Install Update") {
                            updateManager.installUpdate(from: dmgURL)
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        
                    default:
                        Button("Download Update") {
                            Task {
                                await updateManager.downloadUpdate()
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 450, height: 380)
    }
}

// MARK: - UpdateCheckButton

/// A button for the menu bar to check for updates
struct UpdateCheckButton: View {
    @Bindable var updateManager: UpdateManager
    @State private var showingUpdateSheet = false
    
    var body: some View {
        Button(action: {
            Task {
                await updateManager.checkForUpdates()
                if case .available = updateManager.state {
                    showingUpdateSheet = true
                }
            }
        }) {
            HStack {
                if updateManager.state == .checking {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Checking...")
                } else if updateManager.updateAvailable {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundColor(.blue)
                    Text("Update Available")
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Check for Updates")
                }
            }
        }
        .disabled(updateManager.state == .checking)
        .sheet(isPresented: $showingUpdateSheet) {
            if case .available(let release) = updateManager.state {
                UpdateAvailableView(updateManager: updateManager, release: release)
            }
        }
    }
}

// MARK: - UpdateBadge

/// A small badge that appears when an update is available
struct UpdateBadge: View {
    @Bindable var updateManager: UpdateManager
    
    var body: some View {
        if updateManager.updateAvailable {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 18, height: 18)
                
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Version Info View

/// Displays current version and update status
struct VersionInfoView: View {
    @Bindable var updateManager: UpdateManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Stori")
                .font(.headline)
            
            Text("Version \(updateManager.versionDisplayString)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            if let lastCheck = updateManager.lastCheckDate {
                Text("Last checked: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
