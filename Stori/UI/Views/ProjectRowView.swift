//
//  ProjectRowView.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - Project Row View
struct ProjectRowView: View {
    let project: AudioProject
    let compactMode: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    init(project: AudioProject, compactMode: Bool = false, onSelect: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.project = project
        self.compactMode = compactMode
        self.onSelect = onSelect
        self.onDelete = onDelete
    }
    
    var body: some View {
        HStack(spacing: compactMode ? 12 : 16) {
            // Project Icon
            RoundedRectangle(cornerRadius: compactMode ? 6 : 8)
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: compactMode ? 40 : 48, height: compactMode ? 40 : 48)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: compactMode ? 16 : 20, weight: .medium))
                        .foregroundColor(.white)
                )
            
            // Project Info
            VStack(alignment: .leading, spacing: compactMode ? 2 : 4) {
                Text(project.name)
                    .font(.system(size: compactMode ? 14 : 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("\(project.trackCount) tracks • \(Int(project.tempo)) BPM")
                    .font(.system(size: compactMode ? 12 : 13))
                    .foregroundColor(.secondary)
                
                if !compactMode {
                    Text("Modified: \(relativeTimeString(from: project.modifiedAt))")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                if isHovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Delete Project")
                    .transition(.opacity.combined(with: .scale))
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color(NSColor.controlAccentColor).opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .contextMenu {
            Button("Open Project") {
                onSelect()
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
