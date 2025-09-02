//
//  MainDAWView.swift
//  TellUrStoriDAW
//
//  Main DAW interface combining timeline, mixer, and transport
//

import SwiftUI

struct MainDAWView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var projectManager = ProjectManager()
    @State private var showingNewProjectSheet = false
    @State private var showingProjectBrowser = false
    @State private var selectedTrackId: UUID?
    @State private var selectedMainTab: MainTab = .daw
    
    // MARK: - Track Management
    private func addTrack(name: String? = nil) {
        let trackNumber = (projectManager.currentProject?.tracks.count ?? 0) + 1
        let trackName = name ?? "Track \(trackNumber)"
        
        // Add track to project manager - onChange handler will update audio engine
        projectManager.addTrack(name: trackName)
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(MainTab.allCases, id: \.self) { tab in
                        Button(action: {
                            selectedMainTab = tab
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: tab.iconName)
                                Text(tab.title)
                            }
                            .font(.system(size: 14, weight: selectedMainTab == tab ? .semibold : .regular))
                            .foregroundColor(selectedMainTab == tab ? .blue : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .background(Color(.controlBackgroundColor))
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color(.separatorColor)),
                    alignment: .bottom
                )
                
                // Tab content
                Group {
                    switch selectedMainTab {
                    case .daw:
                        dawContentView(geometry: geometry)
                    case .marketplace:
                        MarketplaceView()
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack {
                    Button("New") {
                        showingNewProjectSheet = true
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Create New Project (⌘N)")
                    
                    Button("Open") {
                        showingProjectBrowser = true
                    }
                    .keyboardShortcut("o", modifiers: .command)
                    .help("Open Project (⌘O)")
                    
                    if let project = projectManager.currentProject {
                        Button("Save") {
                            projectManager.saveCurrentProject()
                        }
                        .keyboardShortcut("s", modifiers: .command)
                        .help("Save Project (⌘S)")
                    }
                }
            }
            
            ToolbarItem(placement: .principal) {
                HStack {
                    if let project = projectManager.currentProject {
                        Text(project.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectView(projectManager: projectManager)
        }
        .sheet(isPresented: $showingProjectBrowser) {
            ProjectBrowserView(projectManager: projectManager)
        }
        .onAppear {
            // Start the audio engine first
            print("MainDAWView appeared, initializing audio engine...")
            
            // Give the audio engine a moment to initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let project = projectManager.currentProject {
                    print("Loading existing project into audio engine...")
                    audioEngine.loadProject(project)
                } else {
                    print("No existing project, audio engine ready for new project creation")
                }
            }
        }
        .onChange(of: projectManager.currentProject) { oldValue, newValue in
            if let project = newValue {
                audioEngine.loadProject(project)
            }
        }
    }
    
    private func dawContentView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Main content area
            HStack(spacing: 0) {
                    // Timeline and tracks area
                    VStack(spacing: 0) {
                        // Timeline ruler
                        TimelineRulerView(
                            audioEngine: audioEngine,
                            project: projectManager.currentProject
                        )
                        .frame(height: 40)
                        
                        // Step 4: Horizontal-only ScrollView
                        ScrollView(.horizontal) {
                            TimelineView(
                                project: projectManager.currentProject,
                                audioEngine: audioEngine,
                                projectManager: projectManager,
                                selectedTrackId: $selectedTrackId,
                                onAddTrack: { addTrack() },
                                onCreateProject: { showingNewProjectSheet = true }
                            )
                        }
                        
                        // COMMENTED OUT - will add back step by step
                        /*
                        ScrollView([.horizontal, .vertical]) {
                            TimelineView(
                                project: projectManager.currentProject,
                                audioEngine: audioEngine,
                                projectManager: projectManager,
                                selectedTrackId: $selectedTrackId,
                                onAddTrack: { addTrack() },
                                onCreateProject: { showingNewProjectSheet = true }
                            )
                        }
                        */
                    }
                    
                    // Mixer panel
                    MixerView(
                        project: projectManager.currentProject,
                        audioEngine: audioEngine,
                        selectedTrackId: $selectedTrackId
                    )
                    .frame(width: 300)
                }
                
                // Transport controls
                TransportView(audioEngine: audioEngine)
                    .frame(height: 80)
            }
        }
    }

// MARK: - Toolbar View
struct ToolbarView: View {
    @ObservedObject var projectManager: ProjectManager
    @ObservedObject var audioEngine: AudioEngine
    let onNewProject: () -> Void
    let onOpenProject: () -> Void
    
    var body: some View {
        HStack {
            // Project controls
            HStack(spacing: 12) {
                Button("New", action: onNewProject)
                    .keyboardShortcut("n", modifiers: .command)
                
                Button("Open", action: onOpenProject)
                    .keyboardShortcut("o", modifiers: .command)
                
                Button("Save") {
                    projectManager.saveCurrentProject()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(projectManager.currentProject == nil)
                
                Divider()
                    .frame(height: 20)
            }
            
            // Project info
            if let project = projectManager.currentProject {
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.headline)
                    Text("\(project.trackCount) tracks • \(Int(project.tempo)) BPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("No Project")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Performance indicators
            HStack(spacing: 16) {
                // CPU usage
                HStack(spacing: 4) {
                    Text("CPU:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(audioEngine.cpuUsage * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(audioEngine.cpuUsage > 0.8 ? .red : .primary)
                }
                
                // Audio status
                Circle()
                    .fill(audioEngine.isPlaying ? .green : .gray)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 16)
        .background(Color(.controlBackgroundColor))
    }
}

// MARK: - Timeline Ruler View
struct TimelineRulerView: View {
    @ObservedObject var audioEngine: AudioEngine
    let project: AudioProject?
    
    private let pixelsPerSecond: CGFloat = 100
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Color(.controlBackgroundColor)
                
                if let project = project {
                    // Time markers
                    Canvas { context, size in
                        drawTimeMarkers(context: context, size: size, project: project)
                    }
                    
                    // Playhead
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2)
                        .offset(x: CGFloat(audioEngine.currentPosition.timeInterval) * pixelsPerSecond)
                }
            }
        }
        .background(Color(.controlBackgroundColor))
    }
    
    private func drawTimeMarkers(context: GraphicsContext, size: CGSize, project: AudioProject) {
        let secondsVisible = size.width / pixelsPerSecond
        let markerInterval: TimeInterval = 1.0 // 1 second intervals
        
        for i in 0...Int(secondsVisible) {
            let time = TimeInterval(i) * markerInterval
            let x = time * Double(pixelsPerSecond)
            
            // Draw marker line
            let startPoint = CGPoint(x: x, y: size.height - 10)
            let endPoint = CGPoint(x: x, y: size.height)
            
            context.stroke(
                Path { path in
                    path.move(to: startPoint)
                    path.addLine(to: endPoint)
                },
                with: .color(.primary),
                lineWidth: 1
            )
            
            // Draw time label
            let minutes = Int(time) / 60
            let seconds = Int(time) % 60
            let timeString = String(format: "%d:%02d", minutes, seconds)
            
            context.draw(
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary),
                at: CGPoint(x: x + 4, y: size.height - 20)
            )
        }
    }
}

// MARK: - New Project View
struct NewProjectView: View {
    @ObservedObject var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var projectName = "Untitled"
    @State private var tempo: Double = 120
    @State private var timeSignature = TimeSignature.fourFour
    @State private var sampleRate: Double = 44100
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 8) {
                Text("Project")
                    .font(.title2)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            .padding(.top, 32)
            .padding(.bottom, 24)
            
            // Form Content
            VStack(spacing: 20) {
                // Project Name
                HStack {
                    Text("Project Name")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 120, alignment: .trailing)
                    
                    TextField("Untitled", text: $projectName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                
                // BPM
                HStack {
                    Text("BPM")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 120, alignment: .trailing)
                    
                    TextField("120", value: $tempo, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                }
                
                // Sample Rate
                HStack {
                    Text("Sample Rate")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 120, alignment: .trailing)
                    
                    Menu {
                        Button("44.1 kHz") { sampleRate = 44100.0 }
                        Button("48 kHz") { sampleRate = 48000.0 }
                        Button("96 kHz") { sampleRate = 96000.0 }
                    } label: {
                        HStack {
                            Text(sampleRateText)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                    }
                    .frame(width: 200)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                
                Button("Create") {
                    projectManager.createNewProject(name: projectName.isEmpty ? "Untitled" : projectName, tempo: tempo)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .padding(.bottom, 32)
        }
        .frame(width: 480, height: 320)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
    }
    
    private var sampleRateText: String {
        switch sampleRate {
        case 44100: return "44.1 kHz"
        case 48000: return "48 kHz"
        case 96000: return "96 kHz"
        default: return "\(Int(sampleRate/1000)) kHz"
        }
    }
}

// MARK: - Project Browser View
struct ProjectBrowserView: View {
    @ObservedObject var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteAlert = false
    @State private var projectToDelete: AudioProject?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recent Projects")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
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
            
            // Projects List
            if projectManager.recentProjects.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
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
                    LazyVStack(spacing: 1) {
                        ForEach(projectManager.recentProjects) { project in
                            ProjectRowView(
                                project: project,
                                onSelect: {
                                    projectManager.loadProject(project)
                                    dismiss()
                                },
                                onDelete: {
                                    projectToDelete = project
                                    showingDeleteAlert = true
                                }
                            )
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))
            }
        }
        .frame(width: 600, height: 350)
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
                }
            }
        } message: {
            if let project = projectToDelete {
                Text("Are you sure you want to delete \"\(project.name)\"? This action cannot be undone.")
            }
        }
    }
}

// MARK: - Project Row View
struct ProjectRowView: View {
    let project: AudioProject
    let onSelect: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Project Icon
            RoundedRectangle(cornerRadius: 8)
                .fill(LinearGradient(
                    colors: [Color.blue.opacity(0.7), Color.purple.opacity(0.7)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                )
            
            // Project Info
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Text("\(project.trackCount) tracks • \(Int(project.tempo)) BPM")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                
                Text("Modified: \(relativeTimeString(from: project.modifiedAt))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
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

// MARK: - Main Tab Enum

enum MainTab: String, CaseIterable {
    case daw = "daw"
    case marketplace = "marketplace"
    
    var title: String {
        switch self {
        case .daw: return "DAW"
        case .marketplace: return "Marketplace"
        }
    }
    
    var iconName: String {
        switch self {
        case .daw: return "waveform"
        case .marketplace: return "music.note.list"
        }
    }
}