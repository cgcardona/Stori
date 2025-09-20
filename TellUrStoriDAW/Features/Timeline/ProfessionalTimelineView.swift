//
//  ProfessionalTimelineView.swift
//  TellUrStoriDAW
//
//  Enhanced timeline view with professional track headers and editor area
//

import SwiftUI

struct ProfessionalTimelineView: View {
    let project: AudioProject?
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    @Binding var selectedTrackId: UUID?
    let horizontalZoom: Double
    let verticalZoom: Double
    let onAddTrack: () -> Void
    let onCreateProject: () -> Void
    let onOpenProject: () -> Void
    
    // Professional track header management
    @StateObject private var trackHeaderManager = TrackHeaderManager()
    
    // Layout state
    @State private var trackHeaderWidth: CGFloat = 280
    @State private var defaultTrackHeight: CGFloat = 80
    @State private var verticalScrollOffset: CGFloat = 0
    
    // Dynamic sizing based on zoom
    private var trackHeight: CGFloat { defaultTrackHeight * CGFloat(verticalZoom) }
    private var pixelsPerSecond: CGFloat { 100 * CGFloat(horizontalZoom) }
    
    var body: some View {
        VStack(spacing: 0) {
            if let project = project {
                HStack(spacing: 0) {
                    // Track Headers Panel (fixed width, separate scroll)
                    VStack(spacing: 0) {
                        // Spacer to align with timeline ruler (40px height from MainDAWView)
                        Color.clear
                            .frame(height: 40)
                        
                        // Track headers list
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(spacing: 0) {
                                // Use actual project tracks directly from AudioEngine for real-time updates
                                if let currentProject = audioEngine.currentProject {
                                    ForEach(currentProject.tracks) { audioTrack in
                                        ProfessionalTrackHeaderDirect(
                                            audioTrack: audioTrack,
                                            isSelected: selectedTrackId == audioTrack.id,
                                            height: trackHeight,
                                            audioEngine: audioEngine,
                                            projectManager: projectManager
                                        )
                                        .id(audioTrack.id)
                                        .onTapGesture {
                                            selectedTrackId = audioTrack.id
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Add track button
                        AddTrackButton {
                            onAddTrack()
                        }
                        .frame(height: 40)
                    }
                    .frame(width: trackHeaderWidth)
                    .background(Color(.controlBackgroundColor))
                    .overlay(
                        Rectangle()
                            .fill(Color(.separatorColor))
                            .frame(width: 1),
                        alignment: .trailing
                    )
                    
                    // Timeline Editor Area (starts immediately, no top spacer)
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        VStack(spacing: 0) {
                            // Use actual project tracks directly (like original TimelineView)
                            ForEach(project.tracks) { audioTrack in
                                TrackEditorLane(
                                    track: getTrackHeaderModel(for: audioTrack.id),
                                    audioTrack: audioTrack, // Pass the actual AudioTrack directly
                                    audioEngine: audioEngine,
                                    projectManager: projectManager,
                                    isSelected: selectedTrackId == audioTrack.id,
                                    pixelsPerSecond: pixelsPerSecond,
                                    trackHeight: trackHeight,
                                    onSelect: {
                                        selectedTrackId = audioTrack.id
                                    }
                                )
                                .id(audioTrack.id)
                            }
                            
                            // Spacer for additional content
                            Spacer(minLength: 200)
                        }
                    }
                }
            } else {
                EmptyTimelineView(
                    onCreateProject: onCreateProject, 
                    onOpenProject: onOpenProject, 
                    projectManager: projectManager
                )
            }
        }
        .frame(minHeight: 300)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            setupTrackHeaderManager()
        }
        .onChange(of: project) { _, newProject in
            if let newProject = newProject {
                trackHeaderManager.configure(audioEngine: audioEngine, projectManager: projectManager)
            }
        }
        .onChange(of: audioEngine.currentProject) { _, _ in
            // Sync track headers when the AudioEngine's project changes
            trackHeaderManager.handleProjectUpdate()
        }
    }
    
    
    
    // MARK: - Helper Methods
    private func setupTrackHeaderManager() {
        trackHeaderManager.configure(audioEngine: audioEngine, projectManager: projectManager)
    }
    
    private func getAudioTrack(for trackId: UUID) -> AudioTrack? {
        return project?.tracks.first { $0.id == trackId }
    }
    
    private func getTrackHeaderModel(for trackId: UUID) -> TrackHeaderModel? {
        return trackHeaderManager.tracks.first { $0.id == trackId }
    }
    
    private func refreshTrackData() {
        // Force a refresh of track data when project changes
        if let project = project {
            trackHeaderManager.configure(audioEngine: audioEngine, projectManager: projectManager)
        }
    }
}

// MARK: - Track Editor Lane
struct TrackEditorLane: View {
    let track: TrackHeaderModel?
    let audioTrack: AudioTrack?
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let isSelected: Bool
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    let onSelect: () -> Void
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Lane background
            Rectangle()
                .fill(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
                .overlay(
                    Rectangle()
                        .stroke(Color(.separatorColor), lineWidth: 0.5),
                    alignment: .bottom
                )
            
            // Audio regions
            if let audioTrack = audioTrack {
                ForEach(audioTrack.regions) { region in
                    ProfessionalAudioRegion(
                        region: region,
                        track: audioTrack,
                        trackColor: track?.color ?? audioTrack.color,
                        projectManager: projectManager,
                        pixelsPerSecond: pixelsPerSecond,
                        isSelected: isSelected
                    )
                }
            }
            
            // Grid lines (optional)
            if isSelected {
                GridLinesView(
                    pixelsPerSecond: pixelsPerSecond,
                    trackHeight: trackHeight
                )
                .opacity(0.1)
            }
        }
        .frame(height: trackHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .dropDestination(for: URL.self) { urls, location in
            handleAudioFileDrop(urls: urls, at: location)
            return true
        }
    }
    
    private func handleAudioFileDrop(urls: [URL], at location: CGPoint) {
        guard let url = urls.first,
              let audioTrack = audioTrack else { return }
        
        Task {
            do {
                let audioFile = try await audioEngine.importAudioFile(from: url)
                let startTime = Double(location.x) / Double(pixelsPerSecond)
                
                let region = AudioRegion(
                    audioFile: audioFile,
                    startTime: startTime
                )
                
                await MainActor.run {
                    projectManager.addRegionToTrack(region, trackId: audioTrack.id)
                }
            } catch {
                print("Failed to import audio file: \(error)")
            }
        }
    }
}

// MARK: - Professional Audio Region
struct ProfessionalAudioRegion: View {
    let region: AudioRegion
    let track: AudioTrack
    let trackColor: TrackColor
    @ObservedObject var projectManager: ProjectManager
    let pixelsPerSecond: CGFloat
    let isSelected: Bool
    
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    @State private var isResizing = false
    @State private var isLooping = false
    @State private var selectionRange: ClosedRange<Double>?
    
    private var regionWidth: CGFloat {
        CGFloat(region.duration) * pixelsPerSecond
    }
    
    private var regionX: CGFloat {
        CGFloat(region.startTime) * pixelsPerSecond
    }
    
    var body: some View {
        ZStack {
            // Region background with professional styling
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [
                            trackColor.color.opacity(0.8),
                            trackColor.color.opacity(0.6)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isSelected ? trackColor.color : trackColor.color.opacity(0.7),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
            
            // Waveform visualization
            WaveformView(audioFile: region.audioFile)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(0.8)
            
            // Selection overlay
            if let selectionRange = selectionRange {
                SelectionOverlay(
                    range: selectionRange,
                    regionDuration: region.duration,
                    regionWidth: regionWidth
                )
            }
            
            // Region info overlay
            regionInfoOverlay
            
            // Resize handles
            resizeHandles
            
            // Loop handle
            loopHandle
        }
        .frame(width: regionWidth, height: 60)
        .offset(x: regionX + dragOffset.width, y: dragOffset.height)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .shadow(
            color: .black.opacity(isDragging ? 0.3 : 0.1),
            radius: isDragging ? 6 : 2,
            x: 0,
            y: isDragging ? 3 : 1
        )
        .animation(.easeInOut(duration: 0.15), value: isDragging)
        .gesture(mainDragGesture)
        .contextMenu {
            regionContextMenu
        }
    }
    
    // MARK: - Region Info Overlay
    private var regionInfoOverlay: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(region.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.7), radius: 1)
                
                Spacer()
                
                // Loop indicator
                if region.isLooped {
                    Image(systemName: "repeat")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.7), radius: 1)
                }
            }
            
            Spacer()
            
            HStack {
                Text(region.audioFile.displayDuration)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.8))
                    .shadow(color: .black.opacity(0.7), radius: 1)
                
                Spacer()
                
                // Gain indicator (if not unity)
                if abs(region.gain - 1.0) > 0.01 {
                    Text("\(region.gain > 1.0 ? "+" : "")\(Int((region.gain - 1.0) * 100))%")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.8))
                        .shadow(color: .black.opacity(0.7), radius: 1)
                }
            }
        }
        .padding(6)
    }
    
    // MARK: - Resize Handles
    private var resizeHandles: some View {
        Group {
            // Left resize handle (fade in)
            Rectangle()
                .fill(.clear)
                .frame(width: 8)
                .contentShape(Rectangle())
                .cursor(.resizeLeftRight)
                .position(x: 4, y: 30)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Handle left resize
                        }
                )
            
            // Right resize handle (duration)
            Rectangle()
                .fill(.clear)
                .frame(width: 8)
                .contentShape(Rectangle())
                .cursor(.resizeLeftRight)
                .position(x: regionWidth - 4, y: 30)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Handle right resize
                        }
                )
        }
    }
    
    // MARK: - Loop Handle
    private var loopHandle: some View {
        Circle()
            .fill(.white.opacity(0.8))
            .frame(width: 8, height: 8)
            .position(x: regionWidth - 8, y: 8)
            .opacity(regionWidth > 50 ? 1 : 0) // Only show if region is wide enough
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Handle loop creation
                    }
            )
    }
    
    // MARK: - Gestures
    private var mainDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                }
                
                // Check if this is a selection drag (small initial movement)
                if abs(value.translation.width) < 5 && abs(value.translation.height) < 5 {
                    // Start selection
                    let startPercent = max(0, min(1, value.startLocation.x / regionWidth))
                    let endPercent = max(0, min(1, value.location.x / regionWidth))
                    
                    if startPercent != endPercent {
                        let startTime = Double(startPercent) * region.duration
                        let endTime = Double(endPercent) * region.duration
                        selectionRange = min(startTime, endTime)...max(startTime, endTime)
                    }
                } else {
                    // Regular drag
                    dragOffset = value.translation
                    selectionRange = nil
                }
            }
            .onEnded { value in
                if abs(value.translation.width) > 5 || abs(value.translation.height) > 5 {
                    handleRegionDrop(translation: value.translation)
                }
                
                dragOffset = .zero
                isDragging = false
            }
    }
    
    // MARK: - Context Menu
    private var regionContextMenu: some View {
        Group {
            Button("Cut") {
                // TODO: Implement cut
            }
            
            Button("Copy") {
                // TODO: Implement copy
            }
            
            Button("Delete") {
                projectManager.removeRegionFromTrack(region.id, trackId: track.id)
            }
            
            Divider()
            
            Button("Duplicate") {
                duplicateRegion()
            }
            
            Button("Split at Playhead") {
                // TODO: Implement split
            }
            
            Divider()
            
            Button("Fade In...") {
                // TODO: Implement fade in
            }
            
            Button("Fade Out...") {
                // TODO: Implement fade out
            }
            
            Button("Normalize") {
                // TODO: Implement normalize
            }
            
            Button("Reverse") {
                // TODO: Implement reverse
            }
        }
    }
    
    // MARK: - Helper Methods
    private func handleRegionDrop(translation: CGSize) {
        let newStartTime = max(0, region.startTime + Double(translation.width) / Double(pixelsPerSecond))
        
        var updatedRegion = region
        updatedRegion.startTime = newStartTime
        
        projectManager.updateRegion(updatedRegion, trackId: track.id)
    }
    
    private func duplicateRegion() {
        let duplicatedRegion = AudioRegion(
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

// MARK: - Selection Overlay
struct SelectionOverlay: View {
    let range: ClosedRange<Double>
    let regionDuration: Double
    let regionWidth: CGFloat
    
    var body: some View {
        Rectangle()
            .fill(.blue.opacity(0.3))
            .frame(
                width: CGFloat((range.upperBound - range.lowerBound) / regionDuration) * regionWidth,
                height: 60
            )
            .offset(x: CGFloat(range.lowerBound / regionDuration) * regionWidth - regionWidth/2)
            .overlay(
                Rectangle()
                    .stroke(.blue, lineWidth: 1)
            )
    }
}

// MARK: - Grid Lines View
struct GridLinesView: View {
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    
    var body: some View {
        Canvas { context, size in
            let beatInterval = pixelsPerSecond / 2 // Assuming 120 BPM, 2 beats per second
            
            for x in stride(from: 0, through: size.width, by: beatInterval) {
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                    },
                    with: .color(.gray),
                    lineWidth: 0.5
                )
            }
        }
    }
}

// MARK: - Professional Track Header Direct
struct ProfessionalTrackHeaderDirect: View {
    let audioTrack: AudioTrack
    let isSelected: Bool
    let height: CGFloat
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    
    @State private var isEditingName = false
    @State private var trackName: String
    @State private var showingAIGeneration = false
    
    init(audioTrack: AudioTrack, isSelected: Bool, height: CGFloat, audioEngine: AudioEngine, projectManager: ProjectManager) {
        self.audioTrack = audioTrack
        self.isSelected = isSelected
        self.height = height
        self.audioEngine = audioEngine
        self.projectManager = projectManager
        self._trackName = State(initialValue: audioTrack.name)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Track color indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(audioTrack.color.color)
                .frame(width: 4)
            
            VStack(alignment: .leading, spacing: 8) {
                // Track name
                HStack {
                    if isEditingName {
                        TextField("Track Name", text: $trackName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                var updatedTrack = audioTrack
                                updatedTrack.name = trackName
                                projectManager.updateTrack(updatedTrack)
                                isEditingName = false
                            }
                            .onExitCommand {
                                trackName = audioTrack.name
                                isEditingName = false
                            }
                    } else {
                        Text(audioTrack.name)
                            .font(.headline)
                            .foregroundColor(isSelected ? .accentColor : .primary)
                            .onTapGesture(count: 2) {
                                isEditingName = true
                            }
                    }
                    
                    Spacer()
                }
                
                // Controls row
                HStack(spacing: 8) {
                    // Record enable
                    Button(action: {
                        var updatedTrack = audioTrack
                        updatedTrack.mixerSettings.isRecordEnabled.toggle()
                        projectManager.updateTrack(updatedTrack)
                    }) {
                        Image(systemName: "record.circle")
                            .foregroundColor(audioTrack.mixerSettings.isRecordEnabled ? .red : .secondary)
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    
                    // Mute
                    Button(action: {
                        var updatedTrack = audioTrack
                        updatedTrack.mixerSettings.isMuted.toggle()
                        projectManager.updateTrack(updatedTrack)
                        audioEngine.updateTrackMute(trackId: audioTrack.id, isMuted: updatedTrack.mixerSettings.isMuted)
                    }) {
                        Text("M")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(audioTrack.mixerSettings.isMuted ? .black : .secondary)
                            .frame(width: 20, height: 20)
                            .background(audioTrack.mixerSettings.isMuted ? .orange : Color.clear)
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    // Solo
                    Button(action: {
                        var updatedTrack = audioTrack
                        updatedTrack.mixerSettings.isSolo.toggle()
                        projectManager.updateTrack(updatedTrack)
                        audioEngine.updateTrackSolo(trackId: audioTrack.id, isSolo: updatedTrack.mixerSettings.isSolo)
                    }) {
                        Text("S")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(audioTrack.mixerSettings.isSolo ? .black : .secondary)
                            .frame(width: 20, height: 20)
                            .background(audioTrack.mixerSettings.isSolo ? .yellow : Color.clear)
                            .cornerRadius(4)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    // Volume
                    VStack(spacing: 2) {
                        Text("VOL")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        HSliderView(value: .constant(audioTrack.mixerSettings.volume), range: 0...1) { value in
                            var updatedTrack = audioTrack
                            updatedTrack.mixerSettings.volume = value
                            projectManager.updateTrack(updatedTrack)
                            audioEngine.updateTrackVolume(trackId: audioTrack.id, volume: value)
                        }
                        .frame(width: 60, height: 12)
                        
                        Text("\(Int(audioTrack.mixerSettings.volume * 100))")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    
                    // Pan
                    VStack(spacing: 2) {
                        Text("PAN")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        KnobView(value: .constant(audioTrack.mixerSettings.pan), range: -1...1, sensitivity: 0.02) { value in
                            var updatedTrack = audioTrack
                            updatedTrack.mixerSettings.pan = value
                            projectManager.updateTrack(updatedTrack)
                            audioEngine.updateTrackPan(trackId: audioTrack.id, pan: value)
                        }
                        .frame(width: 24, height: 24)
                        
                        Text(panDisplayText(audioTrack.mixerSettings.pan))
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                    
                    // AI Generation
                    Button(action: {
                        showingAIGeneration = true
                    }) {
                        Image(systemName: "wand.and.stars")
                            .foregroundColor(.purple)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)
                    .help("Generate AI Music")
                    
                    Spacer()
                    
                    // Delete track
                    Button(action: {
                        projectManager.removeTrack(audioTrack.id)
                    }) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .frame(height: height)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
        .overlay(
            Rectangle()
                .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 0.5)
        )
        .sheet(isPresented: $showingAIGeneration) {
            AIGenerationView(targetTrack: audioTrack, projectManager: projectManager)
        }
    }
    
    private func panDisplayText(_ pan: Float) -> String {
        if abs(pan) < 0.01 {
            return "C"
        } else if pan > 0 {
            return "R\(Int(pan * 100))"
        } else {
            return "L\(Int(abs(pan) * 100))"
        }
    }
}
