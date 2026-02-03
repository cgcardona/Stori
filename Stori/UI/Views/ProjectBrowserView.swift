//
//  ProjectBrowserView.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

struct ProjectBrowserView: View {
    var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProject: AudioProject?
    @State private var hoveredProject: AudioProject?
    @State private var showingDeleteAlert = false
    @State private var projectToDelete: AudioProject?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Choose a Project")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            
            // Project Grid
            if projectManager.recentProjects.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No Recent Projects")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Create a new project to get started")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 240, maximum: 280), spacing: 20)
                    ], spacing: 20) {
                        ForEach(projectManager.recentProjects) { project in
                            ProjectThumbnailCard(
                                project: project,
                                projectManager: projectManager,
                                isSelected: selectedProject?.id == project.id,
                                isHovered: hoveredProject?.id == project.id,
                                onSelect: {
                                    selectedProject = project
                                },
                                onOpen: {
                                    projectManager.loadProject(project)
                                    dismiss()
                                },
                                onDelete: {
                                    projectToDelete = project
                                    showingDeleteAlert = true
                                },
                                onHover: { hovering in
                                    hoveredProject = hovering ? project : nil
                                }
                            )
                        }
                    }
                    .padding(24)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            }
            
            // Bottom bar with selected project info
            if let selected = selectedProject {
                HStack {
                    Text(selected.name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    
                    Button("Choose") {
                        projectManager.loadProject(selected)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction) // Responds to Return key
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(Color(NSColor.windowBackgroundColor))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(NSColor.separatorColor)),
                    alignment: .top
                )
            }
        }
        .frame(width: 920, height: 580)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
        .onAppear {
            projectManager.loadRecentProjects()
        }
        .alert("Delete Project", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let project = projectToDelete {
                    projectManager.deleteProject(project)
                    if selectedProject?.id == project.id {
                        selectedProject = nil
                    }
                }
            }
        } message: {
            if let project = projectToDelete {
                Text("Are you sure you want to delete \"\(project.name)\"? This action cannot be undone.")
            }
        }
    }
}
