//
//  UpdateIndicatorView.swift
//  Stori
//
//  A compact toolbar indicator showing update status with escalation colors.
//  Designed to sit in the DAW control bar or toolbar unobtrusively.
//
//  Colors escalate based on days since the update was first detected:
//    - Green (0–3 days):  subtle, informational
//    - Yellow (4–10 days): gentle nudge
//    - Red (11+ days):    strong encouragement to update
//

import SwiftUI

// MARK: - UpdateIndicatorView

struct UpdateIndicatorView: View {
    var updateService: UpdateService
    @State private var showingUpdateSheet = false
    @State private var isHovering = false
    @State private var pulseAnimation = false
    
    var body: some View {
        Group {
            if updateService.hasUpdate {
                updateBadge
            } else if case .aheadOfRelease = updateService.state {
                devBuildBadge
            }
        }
    }
    
    // MARK: - Update Available Badge
    
    private var updateBadge: some View {
        Button {
            showingUpdateSheet = true
        } label: {
            HStack(spacing: 6) {
                // Pulsing dot
                Circle()
                    .fill(urgencyColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: urgencyColor.opacity(0.6), radius: pulseAnimation ? 4 : 1)
                
                // Status text
                statusText
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(urgencyColor.opacity(isHovering ? 0.2 : 0.1))
                    .stroke(urgencyColor.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
        .help(tooltipText)
        .sheet(isPresented: $showingUpdateSheet) {
            UpdateSheetView(updateService: updateService)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                pulseAnimation = true
            }
        }
        .accessibilityLabel("Update available")
        .accessibilityHint("Click to view update details")
    }
    
    // MARK: - Dev Build Badge
    
    private var devBuildBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            Text("Dev")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.1))
        )
        .help("You're running a development build ahead of the latest release")
        .accessibilityLabel("Development build")
    }
    
    // MARK: - Status Text
    
    @ViewBuilder
    private var statusText: some View {
        switch updateService.state {
        case .updateAvailable(let release):
            Text(release.version.displayString)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(urgencyColor)
            
        case .downloading(let progress):
            Text("\(progress.percent)%")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.blue)
            
        case .downloaded:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                Text("Ready")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.green)
            
        default:
            EmptyView()
        }
    }
    
    // MARK: - Urgency Colors
    
    private var urgencyColor: Color {
        switch updateService.urgency {
        case .low:    return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }
    
    private var tooltipText: String {
        switch updateService.state {
        case .updateAvailable(let release):
            var text = "Update available: \(release.version.displayString)"
            if let count = updateService.releasesBehindCount, count > 1 {
                text += " (\(count) releases behind)"
            }
            return text
            
        case .downloading(let progress):
            return "Downloading update: \(progress.percent)%"
            
        case .downloaded:
            return "Update downloaded and ready to install"
            
        default:
            return "Stori is up to date"
        }
    }
}
