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
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Top toolbar
                ToolbarView(
                    projectManager: projectManager,
                    audioEngine: audioEngine,
                    onNewProject: { showingNewProjectSheet = true },
                    onOpenProject: { showingProjectBrowser = true }
                )
                .frame(height: 60)
                
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
                        
                        // Tracks area
                        ScrollView([.horizontal, .vertical]) {
                            TimelineView(
                                project: projectManager.currentProject,
                                audioEngine: audioEngine,
                                projectManager: projectManager,
                                selectedTrackId: $selectedTrackId
                            )
                        }
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
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectView(projectManager: projectManager)
        }
        .sheet(isPresented: $showingProjectBrowser) {
            ProjectBrowserView(projectManager: projectManager)
        }
        .onAppear {
            // Load the current project into the audio engine
            if let project = projectManager.currentProject {
                audioEngine.loadProject(project)
            }
        }
        .onChange(of: projectManager.currentProject) { _, newProject in
            if let project = newProject {
                audioEngine.loadProject(project)
            }
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
    
    @State private var projectName = "Untitled Project"
    @State private var tempo: Double = 120
    @State private var timeSignature = TimeSignature.fourFour
    @State private var sampleRate: Double = 44100
    
    var body: some View {
        NavigationView {
            Form {
                Section("Project Settings") {
                    TextField("Project Name", text: $projectName)
                    
                    HStack {
                        Text("Tempo")
                        Spacer()
                        TextField("BPM", value: $tempo, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    Picker("Sample Rate", selection: $sampleRate) {
                        Text("44.1 kHz").tag(44100.0)
                        Text("48 kHz").tag(48000.0)
                        Text("96 kHz").tag(96000.0)
                    }
                }
            }
            .navigationTitle("New Project")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        projectManager.createNewProject(name: projectName, tempo: tempo)
                        dismiss()
                    }
                    .disabled(projectName.isEmpty)
                }
            }
        }
        .frame(width: 400, height: 300)
    }
}

// MARK: - Project Browser View
struct ProjectBrowserView: View {
    @ObservedObject var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(projectManager.recentProjects) { project in
                    ProjectRowView(project: project) {
                        projectManager.loadProject(project)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Recent Projects")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .frame(width: 500, height: 400)
        .onAppear {
            projectManager.loadRecentProjects()
        }
    }
}

// MARK: - Project Row View
struct ProjectRowView: View {
    let project: AudioProject
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.headline)
                    
                    Text("\(project.trackCount) tracks • \(Int(project.tempo)) BPM")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Modified: \(project.modifiedAt, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
