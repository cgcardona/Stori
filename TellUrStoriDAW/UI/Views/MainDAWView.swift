//
//  MainDAWView.swift
//  TellUrStoriDAW
//
//  Main DAW interface combining timeline, mixer, and transport
//

import SwiftUI

enum MainTab: String, CaseIterable {
    case daw = "DAW"
    case marketplace = "Marketplace"
    
    var title: String {
        return self.rawValue
    }
    
    var iconName: String {
        switch self {
        case .daw:
            return "waveform"
        case .marketplace:
            return "cart"
        }
    }
}

struct MainDAWView: View {
    @StateObject private var audioEngine = AudioEngine()
    @StateObject private var projectManager = ProjectManager()
    @State private var showingNewProjectSheet = false
    @State private var showingProjectBrowser = false
    @State private var selectedTrackId: UUID?
    @State private var selectedMainTab: MainTab = .daw
    
    // MARK: - Zoom Controls
    @State private var horizontalZoom: Double = 1.0 // 0.1x to 10x zoom
    @State private var verticalZoom: Double = 1.0   // 0.5x to 3x zoom
    
    // MARK: - Panel Visibility State
    @State private var showingLibrary = false
    @State private var showingInspector = false
    @State private var showingMixer = false
    
    // MARK: - Panel Size State
    @State private var libraryWidth: CGFloat = 250
    @State private var inspectorWidth: CGFloat = 300
    @State private var mixerHeight: CGFloat = 200
    
    // MARK: - Track Management
    private func addTrack(name: String? = nil) {
        let trackNumber = (projectManager.currentProject?.tracks.count ?? 0) + 1
        let trackName = name ?? "Track \(trackNumber)"
        
        // Add track to project manager - onChange handler will update audio engine
        projectManager.addTrack(name: trackName)
    }
    
    private func deleteSelectedTrack() {
        guard let selectedId = selectedTrackId,
              let project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == selectedId }) else {
            print("No track selected or track not found")
            return
        }
        
        let track = project.tracks[trackIndex]
        print("Deleting track: \(track.name)")
        
        // Remove track from project manager - onChange handler will update audio engine
        projectManager.removeTrack(selectedId)
        
        // Clear selection since the track is deleted
        selectedTrackId = nil
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
            ToolbarItem(placement: .principal) {
                Text("TellUrStoriDAW")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
        }
        .sheet(isPresented: $showingNewProjectSheet) {
            NewProjectView(projectManager: projectManager)
        }
        .sheet(isPresented: $showingProjectBrowser) {
            ProjectBrowserView(projectManager: projectManager)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleMixer)) { _ in
            if selectedMainTab == .daw {
                showingMixer.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleLibrary)) { _ in
            if selectedMainTab == .daw {
                showingLibrary.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleInspector)) { _ in
            if selectedMainTab == .daw {
                showingInspector.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newProject)) { _ in
            showingNewProjectSheet = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .openProject)) { _ in
            showingProjectBrowser = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveProject)) { _ in
            if projectManager.currentProject != nil {
                projectManager.saveCurrentProject()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newTrack)) { _ in
            if projectManager.currentProject != nil && selectedMainTab == .daw {
                addTrack()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteTrack)) { _ in
            if projectManager.currentProject != nil && selectedMainTab == .daw {
                deleteSelectedTrack()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .skipToBeginning)) { _ in
            if projectManager.currentProject != nil && selectedMainTab == .daw {
                audioEngine.skipToBeginning()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .skipToEnd)) { _ in
            if projectManager.currentProject != nil && selectedMainTab == .daw {
                audioEngine.skipToEnd()
            }
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
                // Only load project if it's a completely different project (different ID)
                if oldValue?.id != project.id {
                    print("Loading new project into audio engine: \(project.name)")
                    audioEngine.loadProject(project)
                }
            }
        }
    }
    
    private func dawContentView(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Main content area with professional panel layout
            HStack(spacing: 0) {
                // Left Panel: Library (when visible)
                if showingLibrary {
                    HStack(spacing: 0) {
                        DAWLibraryPanel()
                            .frame(width: libraryWidth)
                        
                        // Resize Handle
                        ResizeHandle(
                            orientation: .vertical,
                            onDrag: { delta in
                                libraryWidth = max(200, min(400, libraryWidth + delta))
                            }
                        )
                    }
                    .transition(.move(edge: .leading))
                }
                
                // Center: Main DAW Content
                VStack(spacing: 0) {
                    // Timeline and tracks area
                    VStack(spacing: 0) {
                        // Zoom controls toolbar (only show when project exists)
                        if projectManager.currentProject != nil {
                            ZoomControlsView(
                                horizontalZoom: $horizontalZoom,
                                verticalZoom: $verticalZoom
                            )
                        }
                        
                        // Timeline ruler (aligned with track content) with Cycle Overlay
                        ZStack(alignment: .topLeading) {
                            HStack(spacing: 0) {
                                // Spacer to align with track headers (280px)
                                Color.clear
                                    .frame(width: 280)
                                
                                // Timeline ruler
                                TimelineRulerView(
                                    audioEngine: audioEngine,
                                    project: projectManager.currentProject,
                                    horizontalZoom: horizontalZoom
                                )
                            }
                            .frame(height: 40)
                            
                            // Cycle overlay over timeline ruler
                            if audioEngine.isCycleEnabled {
                                CycleOverlayView(
                                    cycleStartTime: audioEngine.cycleStartTime,
                                    cycleEndTime: audioEngine.cycleEndTime,
                                    horizontalZoom: horizontalZoom,
                                    onCycleRegionChanged: { start, end in
                                        audioEngine.setCycleRegion(start: start, end: end)
                                    }
                                )
                                .offset(x: 280, y: 0) // Align with timeline ruler
                            }
                        }
                        
                        // Working Timeline with track creation
                        ScrollView(.horizontal) {
                            TimelineView(
                                project: projectManager.currentProject,
                                audioEngine: audioEngine,
                                projectManager: projectManager,
                                selectedTrackId: $selectedTrackId,
                                horizontalZoom: horizontalZoom,
                                verticalZoom: verticalZoom,
                                onAddTrack: { addTrack() },
                                onCreateProject: { showingNewProjectSheet = true },
                                onOpenProject: { showingProjectBrowser = true }
                            )
                        }
                    }
                    
                    // Bottom area: Mixer panel (when visible)
                    if showingMixer {
                        VStack(spacing: 0) {
                            // Resize Handle
                            ResizeHandle(
                                orientation: .horizontal,
                                onDrag: { delta in
                                    mixerHeight = max(150, min(400, mixerHeight - delta))
                                }
                            )
                            
                            MixerView(
                                project: projectManager.currentProject,
                                audioEngine: audioEngine,
                                projectManager: projectManager,
                                selectedTrackId: $selectedTrackId
                            )
                            .frame(height: mixerHeight)
                        }
                        .transition(.move(edge: .bottom))
                    }
                }
                
                // Right Panel: Inspector (when visible)
                if showingInspector {
                    HStack(spacing: 0) {
                        // Resize Handle
                        ResizeHandle(
                            orientation: .vertical,
                            onDrag: { delta in
                                inspectorWidth = max(250, min(500, inspectorWidth - delta))
                            }
                        )
                        
                        DAWInspectorPanel(
                            selectedTrackId: $selectedTrackId,
                            project: projectManager.currentProject,
                            audioEngine: audioEngine
                        )
                        .frame(width: inspectorWidth)
                    }
                    .transition(.move(edge: .trailing))
                }
            }
            
            // Professional DAW Control Bar - Pinned to Bottom
            DAWControlBar(
                audioEngine: audioEngine,
                projectManager: projectManager,
                showingMixer: $showingMixer,
                showingLibrary: $showingLibrary,
                showingInspector: $showingInspector
            )
        }
        .animation(.easeInOut(duration: 0.3), value: showingLibrary)
        .animation(.easeInOut(duration: 0.3), value: showingInspector)
        .animation(.easeInOut(duration: 0.3), value: showingMixer)
    }
}

// MARK: - Zoom Controls View
struct ZoomControlsView: View {
    @Binding var horizontalZoom: Double
    @Binding var verticalZoom: Double
    
    var body: some View {
        HStack(spacing: 12) {
            // Spacer to align with track headers
            Color.clear
                .frame(width: 280)
            
            // Horizontal zoom control
            HStack(spacing: 4) {
                Image(systemName: "minus.magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption2)
                
                Slider(value: $horizontalZoom, in: 0.1...10.0, step: 0.1)
                    .frame(width: 80)
                    .accentColor(.blue)
                
                Image(systemName: "plus.magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption2)
                
                Text("\(String(format: "%.1f", horizontalZoom))x")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 25, alignment: .leading)
            }
            
            Divider()
                .frame(height: 16)
            
            // Vertical zoom control
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .foregroundColor(.secondary)
                    .font(.caption2)
                
                Slider(value: $verticalZoom, in: 0.5...3.0, step: 0.1)
                    .frame(width: 70)
                    .accentColor(.green)
                
                Text("\(String(format: "%.1f", verticalZoom))x")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 25, alignment: .leading)
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
}

// MARK: - Timeline Ruler View
struct TimelineRulerView: View {
    @ObservedObject var audioEngine: AudioEngine
    let project: AudioProject?
    let horizontalZoom: Double
    
    private var pixelsPerSecond: CGFloat { 100 * CGFloat(horizontalZoom) }
    
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

// MARK: - Cycle Overlay View
struct CycleOverlayView: View {
    let cycleStartTime: TimeInterval
    let cycleEndTime: TimeInterval
    let horizontalZoom: Double
    let onCycleRegionChanged: (TimeInterval, TimeInterval) -> Void
    
    private var pixelsPerSecond: CGFloat { 100 * CGFloat(horizontalZoom) }
    
    var body: some View {
        let startX = CGFloat(cycleStartTime) * pixelsPerSecond
        let endX = CGFloat(cycleEndTime) * pixelsPerSecond
        let width = endX - startX
        
        HStack(spacing: 0) {
            // Cycle region background and handles
            Rectangle()
                .fill(Color.yellow.opacity(0.3))
                .frame(width: width, height: 40)
                .overlay(
                    Rectangle()
                        .stroke(Color.yellow, lineWidth: 2)
                        .frame(width: width, height: 40)
                )
                .offset(x: startX)
            
            Spacer()
        }
        .frame(height: 40)
        .clipped()
    }
}

// MARK: - Supporting Views
struct NewProjectView: View {
    @ObservedObject var projectManager: ProjectManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var projectName = "Untitled"
    @State private var tempo: Double = 120
    @State private var timeSignature = TimeSignature.fourFour
    @State private var sampleRate: Double = 44100
    @State private var animateGradient = false
    @State private var isCreating = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated gradient header
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.8),
                    Color.purple.opacity(0.6),
                    Color.pink.opacity(0.4)
                ],
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .frame(height: 120)
            .overlay(
                VStack(spacing: 12) {
                    // Project icon with glow effect
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 60, height: 60)
                        
                        Circle()
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "music.note")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                    
                    // Title with gradient text
                    Text("New Project")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
            )
            
            // Form content with enhanced styling
            VStack(spacing: 24) {
                VStack(spacing: 20) {
                    // Project Name with icon
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "textformat")
                                .font(.system(size: 14))
                                .foregroundColor(.blue)
                            Text("Project Name")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        TextField("Enter project name", text: $projectName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.controlBackgroundColor))
                                    .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // BPM with icon
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "metronome")
                                .font(.system(size: 14))
                                .foregroundColor(.purple)
                            Text("Tempo (BPM)")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        TextField("120", value: $tempo, format: .number)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.controlBackgroundColor))
                                    .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    // Sample Rate with icon
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.system(size: 14))
                                .foregroundColor(.pink)
                            Text("Sample Rate")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                        
                        Menu {
                            Button("44.1 kHz") { sampleRate = 44100.0 }
                            Button("48 kHz") { sampleRate = 48000.0 }
                            Button("96 kHz") { sampleRate = 96000.0 }
                        } label: {
                            HStack {
                                Text(sampleRateText)
                                    .foregroundColor(.primary)
                                    .font(.system(size: 16))
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color(.controlBackgroundColor))
                                    .stroke(Color.pink.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)
                
                Spacer()
                
                // Enhanced buttons
                HStack(spacing: 16) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(.controlBackgroundColor))
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    
                    Button(action: createProject) {
                        HStack(spacing: 8) {
                            if isCreating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 16))
                            }
                            Text(isCreating ? "Creating..." : "Create Project")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(8)
                        .shadow(color: .blue.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                    .disabled(isCreating || projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .frame(width: 520, height: 480)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
    
    private func createProject() {
        guard !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isCreating = true
        
        // Add a small delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            projectManager.createNewProject(
                name: projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                tempo: tempo
            )
            dismiss()
        }
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

// MARK: - Resizable Panel Handle
struct ResizeHandle: View {
    enum Orientation {
        case horizontal, vertical
    }
    
    let orientation: Orientation
    let onDrag: (CGFloat) -> Void
    
    @State private var isHovered = false
    @State private var isDragging = false
    
    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .background(
                Rectangle()
                    .fill(isHovered || isDragging ? Color.accentColor.opacity(0.6) : Color.clear)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            )
            .overlay(
                Rectangle()
                    .fill(isHovered || isDragging ? Color.white.opacity(0.8) : Color.clear)
                    .frame(
                        width: orientation == .vertical ? 2 : nil,
                        height: orientation == .horizontal ? 2 : nil
                    )
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
            )
            .frame(
                width: orientation == .vertical ? 8 : nil,
                height: orientation == .horizontal ? 8 : nil
            )
            .cursor(orientation == .vertical ? .resizeLeftRight : .resizeUpDown)
            .onHover { hovering in
                isHovered = hovering
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                        }
                        let delta = orientation == .vertical ? value.translation.width : value.translation.height
                        onDrag(delta)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
    }
}

// MARK: - Cursor Extension for Resize Handles
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { isHovered in
            if isHovered {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}