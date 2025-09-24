//
//  EmptyTimelineView.swift
//  TellUrStoriDAW
//
//  Empty timeline view shown when no project is loaded
//

import SwiftUI

// MARK: - Empty Timeline View
struct EmptyTimelineView: View {
    let onCreateProject: () -> Void
    let onOpenProject: () -> Void
    @ObservedObject var projectManager: ProjectManager
    @State private var selectedCategory: ProjectCategory = .newProject
    
    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundColor(.blue)
                    Text("Choose a Project")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Categories
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(ProjectCategory.allCases, id: \.self) { category in
                        Button(action: {
                            selectedCategory = category
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: category.iconName)
                                    .font(.system(size: 16))
                                    .foregroundColor(selectedCategory == category ? .white : .blue)
                                    .frame(width: 20)
                                
                                Text(category.title)
                                    .font(.system(size: 14, weight: selectedCategory == category ? .medium : .regular))
                                    .foregroundColor(selectedCategory == category ? .white : .primary)
                                
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                selectedCategory == category ? 
                                Color.blue : Color.clear
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.bottom, 20)
                
                Spacer()
            }
            .frame(width: 280)
            .background(Color(.controlBackgroundColor))
            
            // Right content area
            VStack(spacing: 0) {
                // Content based on selected category
                Group {
                    switch selectedCategory {
                    case .newProject:
                        newProjectContent
                    case .recent:
                        recentProjectsContent
                    case .tutorials:
                        tutorialsContent
                    case .demoProjects:
                        demoProjectsContent
                    case .projectTemplates:
                        projectTemplatesContent
                    case .myTemplates:
                        myTemplatesContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.windowBackgroundColor))
                
                // Bottom action bar
                HStack {
                    Spacer()
                    
                    Button("Open an existing project...") {
                        onOpenProject()
                    }
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button("Choose") {
                        if selectedCategory == .newProject {
                            onCreateProject()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCategory != .newProject)
                }
                .padding(20)
                .background(Color(.controlBackgroundColor))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Content Views
    private var newProjectContent: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Main project template
            VStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 140)
                    .overlay(
                        VStack {
                            Image(systemName: "waveform")
                                .font(.system(size: 32))
                                .foregroundColor(.white)
                            Text("Empty Project")
                                .font(.headline)
                                .foregroundColor(.white)
                        }
                    )
                
                Text("Empty Project")
                    .font(.title3)
                    .fontWeight(.medium)
                
                Text("Start with an empty project and build from scratch")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            
            Spacer()
        }
    }
    
    private var recentProjectsContent: some View {
        RecentProjectsListView(
            projectManager: projectManager,
            onProjectSelected: { project in
                projectManager.loadProject(project)
            },
            showHeader: false,
            compactMode: true
        )
    }
    

    private var tutorialsContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "play.circle")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Tutorials")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Learn TellUrStori with interactive tutorials")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var demoProjectsContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Demo Projects")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Explore example projects and learn techniques")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var projectTemplatesContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Project Templates")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Start with pre-configured project templates")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var myTemplatesContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("My Templates")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Your custom project templates")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Project Category Enum
enum ProjectCategory: CaseIterable {
    case newProject
    case recent
    case tutorials
    case demoProjects
    case projectTemplates
    case myTemplates
    
    var title: String {
        switch self {
        case .newProject: return "New Project"
        case .recent: return "Recent"
        case .tutorials: return "Tutorials"
        case .demoProjects: return "Demo Projects"
        case .projectTemplates: return "Project Templates"
        case .myTemplates: return "My Templates"
        }
    }
    
    var iconName: String {
        switch self {
        case .newProject: return "doc.badge.plus"
        case .recent: return "clock"
        case .tutorials: return "play.circle"
        case .demoProjects: return "music.note.list"
        case .projectTemplates: return "doc.on.doc"
        case .myTemplates: return "folder"
        }
    }
}
