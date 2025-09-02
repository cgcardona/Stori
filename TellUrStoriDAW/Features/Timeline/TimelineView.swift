//
//  TimelineView.swift
//  TellUrStoriDAW
//
//  Timeline view for track and region management
//

import SwiftUI

struct TimelineView: View {
    let project: AudioProject?
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    @Binding var selectedTrackId: UUID?
    let onAddTrack: () -> Void
    let onCreateProject: () -> Void
    let onOpenProject: () -> Void
    
    private let trackHeight: CGFloat = 80
    private let pixelsPerSecond: CGFloat = 100
    
    var body: some View {
        VStack(spacing: 0) {
            if let project = project {
                ForEach(project.tracks) { track in
                    TrackLaneView(
                        track: track,
                        audioEngine: audioEngine,
                        projectManager: projectManager,
                        isSelected: selectedTrackId == track.id,
                        pixelsPerSecond: pixelsPerSecond,
                        onSelect: { selectedTrackId = track.id }
                    )
                    .frame(height: trackHeight)
                }
                
                // Add track button
                AddTrackButton {
                    onAddTrack()
                }
                .frame(height: 40)
                
                // Fill remaining space
                Spacer()
                
            } else {
                EmptyTimelineView(onCreateProject: onCreateProject, onOpenProject: onOpenProject)
            }
        }
        .frame(minHeight: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Track Lane View
struct TrackLaneView: View {
    let track: AudioTrack
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let isSelected: Bool
    let pixelsPerSecond: CGFloat
    let onSelect: () -> Void
    
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Track header
            TrackHeaderView(
                track: track,
                audioEngine: audioEngine,
                projectManager: projectManager,
                isSelected: isSelected,
                onSelect: onSelect
            )
            .frame(width: 200)
            
            // Track content area
            ZStack(alignment: .leading) {
                // Background
                Rectangle()
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                    .border(Color.gray.opacity(0.3), width: 0.5)
                
                // Audio regions
                ForEach(track.regions) { region in
                    AudioRegionView(
                        region: region,
                        track: track,
                        projectManager: projectManager,
                        pixelsPerSecond: pixelsPerSecond
                    )
                }
            }
            .onTapGesture {
                onSelect()
            }
            .dropDestination(for: URL.self) { urls, location in
                handleAudioFileDrop(urls: urls, at: location)
                return true
            }
        }
    }
    
    private func handleAudioFileDrop(urls: [URL], at location: CGPoint) {
        guard let url = urls.first else { return }
        
        Task {
            do {
                let audioFile = try await audioEngine.importAudioFile(from: url)
                let startTime = Double(location.x) / Double(pixelsPerSecond)
                
                let region = AudioRegion(
                    audioFile: audioFile,
                    startTime: startTime
                )
                
                await MainActor.run {
                    projectManager.addRegionToTrack(region, trackId: track.id)
                }
            } catch {
                print("Failed to import audio file: \(error)")
            }
        }
    }
}

// MARK: - Track Header View
struct TrackHeaderView: View {
    let track: AudioTrack
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isEditingName = false
    @State private var trackName: String
    @State private var showingAIGeneration = false
    
    init(track: AudioTrack, audioEngine: AudioEngine, projectManager: ProjectManager, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.track = track
        self.audioEngine = audioEngine
        self.projectManager = projectManager
        self.isSelected = isSelected
        self.onSelect = onSelect
        self._trackName = State(initialValue: track.name)
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Track name
            HStack {
                if isEditingName {
                    TextField("Track Name", text: $trackName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            var updatedTrack = track
                            updatedTrack.name = trackName
                            projectManager.updateTrack(updatedTrack)
                            isEditingName = false
                        }
                } else {
                    Text(track.name)
                        .font(.headline)
                        .foregroundColor(isSelected ? .accentColor : .primary)
                        .onTapGesture(count: 2) {
                            isEditingName = true
                        }
                }
                
                Spacer()
                
                // Track color indicator
                Circle()
                    .fill(Color(hex: track.colorHex))
                    .frame(width: 12, height: 12)
            }
            
            // Control buttons
            HStack(spacing: 8) {
                // Record enable
                Button(action: {
                    var updatedTrack = track
                    updatedTrack.isRecordEnabled.toggle()
                    projectManager.updateTrack(updatedTrack)
                }) {
                    Image(systemName: "record.circle")
                        .foregroundColor(track.isRecordEnabled ? .red : .secondary)
                }
                .buttonStyle(.plain)
                
                // Mute
                Button(action: {
                    audioEngine.muteTrack(track.id, muted: !track.isMuted)
                }) {
                    Image(systemName: track.isMuted ? "speaker.slash" : "speaker")
                        .foregroundColor(track.isMuted ? .orange : .secondary)
                }
                .buttonStyle(.plain)
                
                // Solo
                Button(action: {
                    audioEngine.soloTrack(track.id, solo: !track.isSolo)
                }) {
                    Image(systemName: "headphones")
                        .foregroundColor(track.isSolo ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                
                // AI Generation
                Button(action: {
                    showingAIGeneration = true
                }) {
                    Image(systemName: "wand.and.stars")
                        .foregroundColor(.purple)
                }
                .buttonStyle(.plain)
                .help("Generate AI Music")
                
                Spacer()
                
                // Delete track
                Button(action: {
                    projectManager.removeTrack(track.id)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .font(.caption)
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
        .border(Color.gray.opacity(0.3), width: 0.5)
        .onTapGesture {
            onSelect()
        }
        .sheet(isPresented: $showingAIGeneration) {
            AIGenerationView(targetTrack: track, projectManager: projectManager)
        }
    }
}

// MARK: - Audio Region View
struct AudioRegionView: View {
    let region: AudioRegion
    let track: AudioTrack
    @ObservedObject var projectManager: ProjectManager
    let pixelsPerSecond: CGFloat
    
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    @State private var isResizing = false
    
    private var regionWidth: CGFloat {
        CGFloat(region.duration) * pixelsPerSecond
    }
    
    private var regionX: CGFloat {
        CGFloat(region.startTime) * pixelsPerSecond
    }
    
    var body: some View {
        ZStack {
            // Region background
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(
                    colors: [
                        Color(hex: track.colorHex).opacity(0.8),
                        Color(hex: track.colorHex).opacity(0.6)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(hex: track.colorHex), lineWidth: 1)
                )
            
            // Waveform visualization (simplified)
            WaveformView(audioFile: region.audioFile)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            
            // Region info
            VStack(alignment: .leading) {
                HStack {
                    Text(region.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                    
                    Spacer()
                }
                
                Spacer()
                
                HStack {
                    Text(region.audioFile.displayDuration)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.5), radius: 1)
                    
                    Spacer()
                }
            }
            .padding(4)
        }
        .frame(width: regionWidth, height: 60)
        .offset(x: regionX + dragOffset.width, y: dragOffset.height)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isDragging)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                    }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    handleRegionDrop(translation: value.translation)
                    dragOffset = .zero
                    isDragging = false
                }
        )
        .contextMenu {
            Button("Delete") {
                projectManager.removeRegionFromTrack(region.id, trackId: track.id)
            }
            
            Button("Duplicate") {
                var duplicatedRegion = region
                duplicatedRegion = AudioRegion(
                    audioFile: region.audioFile,
                    startTime: region.startTime + region.duration,
                    duration: region.duration,
                    fadeIn: region.fadeIn,
                    fadeOut: region.fadeOut,
                    gain: region.gain,
                    isLooped: region.isLooped,
                    offset: region.offset
                )
                projectManager.addRegionToTrack(duplicatedRegion, trackId: track.id)
            }
        }
    }
    
    private func handleRegionDrop(translation: CGSize) {
        let newStartTime = max(0, region.startTime + Double(translation.width) / Double(pixelsPerSecond))
        
        var updatedRegion = region
        updatedRegion.startTime = newStartTime
        
        projectManager.updateRegion(updatedRegion, trackId: track.id)
    }
}

// MARK: - Waveform View
struct WaveformView: View {
    let audioFile: AudioFile
    @StateObject private var audioAnalyzer = AudioAnalyzer()
    @State private var waveformData: AudioAnalyzer.WaveformData?
    @State private var isLoading = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let waveformData = waveformData {
                    // Real waveform visualization
                    RealWaveformPath(waveformData: waveformData, size: geometry.size)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                } else if isLoading {
                    // Loading indicator
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.5)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Fallback placeholder
                    PlaceholderWaveform(size: geometry.size)
                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                }
            }
        }
        .task {
            await loadWaveformData()
        }
        .onChange(of: audioFile.url) { _, _ in
            Task {
                await loadWaveformData()
            }
        }
    }
    
    private func loadWaveformData() async {
        guard !isLoading else { return }
        
        // Check cache first
        if let cachedData = audioAnalyzer.getCachedWaveform(for: audioFile.url) {
            await MainActor.run {
                self.waveformData = cachedData
            }
            return
        }
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let data = try await audioAnalyzer.analyzeAudioFile(at: audioFile.url, targetSamples: 500)
            await MainActor.run {
                self.waveformData = data
                self.isLoading = false
            }
        } catch {
            print("Failed to analyze audio file: \(error)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}

// MARK: - Real Waveform Path
struct RealWaveformPath: Shape {
    let waveformData: AudioAnalyzer.WaveformData
    let size: CGSize
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let points = waveformData.pathPoints(for: size)
        guard !points.isEmpty else { return path }
        
        // Draw waveform as vertical lines from center
        let midY = rect.height / 2
        
        for i in stride(from: 0, to: points.count, by: 2) {
            guard i + 1 < points.count else { break }
            
            let topPoint = points[i]
            let bottomPoint = points[i + 1]
            
            path.move(to: CGPoint(x: topPoint.x, y: midY - abs(topPoint.y - midY)))
            path.addLine(to: CGPoint(x: bottomPoint.x, y: midY + abs(bottomPoint.y - midY)))
        }
        
        return path
    }
}

// MARK: - Placeholder Waveform
struct PlaceholderWaveform: Shape {
    let size: CGSize
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let width = rect.width
        let height = rect.height
        let midY = height / 2
        
        // Generate simple placeholder waveform
        for x in stride(from: 0, to: width, by: 3) {
            let normalizedX = x / width
            let amplitude = sin(normalizedX * .pi * 8) * 0.3 + cos(normalizedX * .pi * 12) * 0.2
            let y1 = midY - (amplitude * midY * 0.5)
            let y2 = midY + (amplitude * midY * 0.5)
            
            path.move(to: CGPoint(x: x, y: y1))
            path.addLine(to: CGPoint(x: x, y: y2))
        }
        
        return path
    }
}

// MARK: - Add Track Button
struct AddTrackButton: View {
    let onAdd: () -> Void
    
    var body: some View {
        Button(action: onAdd) {
            HStack {
                Image(systemName: "plus.circle")
                Text("Add Track")
            }
            .foregroundColor(.accentColor)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .padding()
        .background(Color(.controlBackgroundColor))
        .border(Color.gray.opacity(0.3), width: 0.5)
    }
}

// MARK: - Empty Timeline View
struct EmptyTimelineView: View {
    let onCreateProject: () -> Void
    let onOpenProject: () -> Void
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
        VStack {
            if true { // Replace with actual recent projects check
                VStack(spacing: 16) {
                    Image(systemName: "clock")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No Recent Projects")
                        .font(.title3)
                        .fontWeight(.medium)
                    
                    Text("Your recently opened projects will appear here")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
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

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    TimelineView(
        project: nil,
        audioEngine: AudioEngine(),
        projectManager: ProjectManager(),
        selectedTrackId: .constant(nil),
        onAddTrack: {},
        onCreateProject: {},
        onOpenProject: {}
    )
    .frame(width: 1000, height: 600)
}
