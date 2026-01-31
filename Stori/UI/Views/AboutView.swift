//
//  AboutView.swift
//  Stori
//
//  Professional About window with version info and website link
//

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Version info - read from VERSION file (single source of truth)
    private let appVersion: String
    private let buildNumber: String
    private let releaseStage = "" // Use "-alpha", "-beta", "-rc1", etc. or leave empty for release
    
    // MARK: - Initialization
    init() {
        // Read version from VERSION file
        if let versionPath = Bundle.main.path(forResource: "VERSION", ofType: nil),
           let versionContent = try? String(contentsOfFile: versionPath, encoding: .utf8) {
            let version = versionContent.trimmingCharacters(in: .whitespacesAndNewlines)
            self.appVersion = version.isEmpty ? "0.1.0" : version
        } else {
            self.appVersion = "0.1.0" // Fallback if VERSION file not found
        }
        
        // Read build number from Info.plist
        self.buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    private var fullVersion: String {
        if releaseStage.isEmpty {
            return "Version \(appVersion) (\(buildNumber))"
        } else {
            return "Version \(appVersion)\(releaseStage) (\(buildNumber))"
        }
    }
    
    private let websiteURL = "https://example.com/"
    private let copyrightYear = "2026"
    
    var body: some View {
        VStack(spacing: 0) {
            // App Icon and Name
            VStack(spacing: 16) {
                // App Icon
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 128, height: 128)
                        .cornerRadius(22)
                        .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                } else {
                    // Fallback icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 22)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .purple, .pink],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 128, height: 128)
                        
                        Image(systemName: "music.note")
                            .font(.system(size: 64))
                            .foregroundColor(.white)
                    }
                    .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                }
                
                // App Name
                Text("Stori")
                    .font(.system(size: 28, weight: .medium))
                
                // Version
                Text(fullVersion)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                // Tagline
                Text("Professional DAW with AI & Blockchain")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            
            Divider()
            
            // Website Link
            VStack(spacing: 12) {
                Button(action: {
                    if let url = URL(string: websiteURL) {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.system(size: 12))
                        Text("example.com")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                
                // Copyright
                Text("© \(copyrightYear) TellUrStori. All rights reserved.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 20)
            
            Divider()
            
            // Technical Info
            VStack(spacing: 8) {
                AboutInfoRow(label: "Swift", value: "6.0")
                AboutInfoRow(label: "macOS", value: "15.0+")
                AboutInfoRow(label: "Architecture", value: processorArchitecture)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            
            Divider()
            
            // Close Button
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding()
        }
        .frame(width: 400)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var processorArchitecture: String {
        #if arch(arm64)
        return "Apple Silicon"
        #elseif arch(x86_64)
        return "Intel"
        #else
        return "Unknown"
        #endif
    }
}

// MARK: - About Info Row Component
struct AboutInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.primary)
        }
    }
}
