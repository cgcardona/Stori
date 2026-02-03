//
//  ProjectThumbnailCard.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - Project Thumbnail Card
struct ProjectThumbnailCard: View {
    let project: AudioProject
    let projectManager: ProjectManager
    let isSelected: Bool
    let isHovered: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onHover: (Bool) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail/Preview
            ZStack {
                // Try to load actual screenshot, fall back to gradient placeholder
                if let thumbnailURL = projectManager.getProjectThumbnailURL(for: project),
                   let nsImage = NSImage(contentsOf: thumbnailURL) {
                    // Display actual screenshot
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // Fallback: gradient placeholder
                    ZStack {
                        LinearGradient(
                            colors: [
                                Color.blue.opacity(0.6),
                                Color.purple.opacity(0.5),
                                Color.pink.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        // Waveform pattern overlay
                        VStack(spacing: 8) {
                            ForEach(0..<5) { index in
                                HStack(spacing: 4) {
                                    ForEach(0..<12) { _ in
                                        RoundedRectangle(cornerRadius: 1)
                                            .fill(Color.white.opacity(0.15))
                                            .frame(width: 3, height: CGFloat.random(in: 10...35))
                                    }
                                }
                            }
                        }
                        .padding()
                    }
                }
                
                // Delete button (shows on hover)
                if isHovered {
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onDelete) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
                                    .padding(8)
                                    .background(Color.red.opacity(0.9))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            
            // Project Info
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("\(project.trackCount) tracks • \(Int(project.tempo)) BPM")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                
                Text("Modified: \(relativeTimeString(from: project.modifiedAt))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                onOpen()
            } else {
                onSelect()
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                onHover(hovering)
            }
        }
        .contextMenu {
            Button("Open Project") {
                onOpen()
            }
            
            Divider()
            
            Button("Delete Project", role: .destructive) {
                onDelete()
            }
        }
    }
    
    private func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let timeInterval = now.timeIntervalSince(date)
        
        let minutes = Int(timeInterval / 60)
        let hours = Int(timeInterval / 3600)
        let days = Int(timeInterval / 86400)
        
        if days > 0 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else if hours > 0 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if minutes > 0 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else {
            return "Just now"
        }
    }
}
