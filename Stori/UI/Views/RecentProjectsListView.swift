//
//  RecentProjectsListView.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - Reusable Recent Projects List
struct RecentProjectsListView: View {
    var projectManager: ProjectManager
    let onProjectSelected: ((AudioProject) -> Void)?
    let showHeader: Bool
    let compactMode: Bool
    
    @State private var showingDeleteAlert = false
    @State private var projectToDelete: AudioProject?
    
    init(
        projectManager: ProjectManager, 
        onProjectSelected: ((AudioProject) -> Void)? = nil,
        showHeader: Bool = false,
        compactMode: Bool = false
    ) {
        self.projectManager = projectManager
        self.onProjectSelected = onProjectSelected
        self.showHeader = showHeader
        self.compactMode = compactMode
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if showHeader {
                // Header
                HStack {
                    Text("Recent Projects")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(NSColor.separatorColor)),
                    alignment: .bottom
                )
            }
            
            // Projects List
            if projectManager.recentProjects.isEmpty {
                if compactMode {
                    // Enhanced empty state for compact mode (EmptyTimelineView)
                    VStack(spacing: 32) {
                        Spacer()
                        
                        // Header with icon
                        VStack(spacing: 16) {
                            // Gradient icon
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 120, height: 120)
                                
                                Image(systemName: "clock")
                                    .font(.system(size: 48, weight: .medium))
                                    .foregroundColor(.white)
                            }
                            
                            // Title and subtitle
                            VStack(spacing: 8) {
                                Text("No Recent Projects")
                                    .font(.system(size: 28, weight: .semibold))
                                
                                Text("Your recently opened projects will appear here for quick access")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 500)
                            }
                        }
                        
                        // Feature highlights
                        VStack(alignment: .leading, spacing: 20) {
                            RecentFeatureRow(
                                icon: "arrow.counterclockwise",
                                title: "Quick Access",
                                description: "Jump back into your recent work instantly"
                            )
                            
                            RecentFeatureRow(
                                icon: "clock.arrow.circlepath",
                                title: "Auto-Tracked",
                                description: "Projects are automatically added when you open them"
                            )
                            
                            RecentFeatureRow(
                                icon: "list.bullet",
                                title: "Project History",
                                description: "See project details and last modified dates"
                            )
                            
                            RecentFeatureRow(
                                icon: "trash",
                                title: "Easy Management",
                                description: "Remove projects from the list or delete them entirely"
                            )
                        }
                        .frame(maxWidth: 500)
                        
                        Spacer()
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Simple empty state for non-compact mode
                    VStack(spacing: 12) {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No Recent Projects")
                            .font(.headline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text("Create a new project to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: compactMode ? 8 : 1) {
                        ForEach(projectManager.recentProjects) { project in
                            ProjectRowView(
                                project: project,
                                compactMode: compactMode,
                                onSelect: {
                                    onProjectSelected?(project)
                                },
                                onDelete: {
                                    projectToDelete = project
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                    .padding(compactMode ? 16 : 0)
                }
                .background(Color(compactMode ? .clear : NSColor.controlBackgroundColor))
            }
        }
        .onAppear {
            projectManager.loadRecentProjects()
        }
        .alert("Delete Project", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    projectManager.deleteProject(project)
                }
            }
        } message: {
            if let project = projectToDelete {
                Text("Are you sure you want to delete \"\(project.name)\"? This action cannot be undone.")
            }
        }
    }
}
