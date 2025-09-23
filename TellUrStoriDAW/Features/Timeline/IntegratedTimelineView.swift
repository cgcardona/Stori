//
//  IntegratedTimelineView.swift
//  TellUrStoriDAW
//
//  Integrated timeline combining synchronized scrolling with full TellUrStori functionality
//  Merges layout-test-1 scroll sync with existing AudioEngine, project management, and DAW features
//

import SwiftUI

struct IntegratedTimelineView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    
    // Computed property to get current project reactively
    private var project: AudioProject? { projectManager.currentProject }
    @Binding var selectedTrackId: UUID?
    @State private var selectedRegionId: UUID?  // Audio region selection state
    let horizontalZoom: Double
    let verticalZoom: Double
    let onAddTrack: () -> Void
    let onCreateProject: () -> Void
    let onOpenProject: () -> Void
    
    // Scroll synchronization model
    @State private var scrollSync = ScrollSyncModel()
    
    // Force refresh state to trigger UI updates when project changes
    @State private var refreshTrigger: UUID = UUID()
    
    // MARK: - Region Management
    
    /// Move an audio region to a new start time on the timeline
    private func moveRegion(regionId: UUID, newStartTime: TimeInterval) {
        guard var project = projectManager.currentProject else { return }
        
        // Find the track and region to update
        for trackIndex in project.tracks.indices {
            if let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                let region = project.tracks[trackIndex].regions[regionIndex]
                let oldStartTime = region.startTime
                
                print("💾 MOVE REGION: '\(region.audioFile.name)'")
                print("   ⏰ Old startTime: \(String(format: "%.2f", oldStartTime))s")
                print("   ⏰ New startTime: \(String(format: "%.2f", newStartTime))s")
                print("   📏 Duration: \(String(format: "%.2f", region.duration))s")
                print("   📍 Old position: [\(String(format: "%.1f", oldStartTime * 100)), \(String(format: "%.1f", (oldStartTime + region.duration) * 100))]px")
                print("   📍 New position: [\(String(format: "%.1f", newStartTime * 100)), \(String(format: "%.1f", (newStartTime + region.duration) * 100))]px")
                
                // Update the region's start time
                project.tracks[trackIndex].regions[regionIndex].startTime = newStartTime
                project.modifiedAt = Date()
                
                // Update the project manager (AudioEngine will pick up changes automatically)
                projectManager.currentProject = project
                
                // Save the project to persist changes
                projectManager.saveCurrentProject()
                
                print("✅ REGION MOVED: Successfully updated position")
                break
            }
        }
    }
    
    // Layout constants adapted from layout-test-1
    private let headerWidth: CGFloat = 280
    private let rulerHeight: CGFloat = 60
    private let trackRowHeight: CGFloat = 80
    
    // Dynamic sizing based on zoom
    private var effectiveTrackHeight: CGFloat { trackRowHeight * CGFloat(verticalZoom) }
    private var pixelsPerSecond: CGFloat { 100 * CGFloat(horizontalZoom) }
    
    // Content sizing for scroll sync
    private var contentSize: CGSize {
        guard let project = project else {
            return CGSize(width: 3000, height: 1000) // Default size
        }
        
        let width = max(3000, pixelsPerSecond * 60) // At least 60 seconds visible
        let height = CGFloat(project.tracks.count) * effectiveTrackHeight
        return CGSize(width: width, height: height)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if project != nil {
                HStack(spacing: 0) {
                    // LEFT: Track Headers Column (vertical scrolling only)
                    VStack(spacing: 0) {
                        // Header spacer with Logic Pro-style Add Track button
                        HStack(spacing: 0) {
                            // Logic Pro-style Add Track button with hover states
                            Button(action: onAddTrack) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                            .buttonStyle(AddTrackButtonStyle())
                            .frame(width: 32, height: rulerHeight)
                            .help("Add Track (⇧⌘N)")
                            
                            // Remaining header space
                            Rectangle()
                                .fill(Color(NSColor.controlBackgroundColor))
                                .frame(height: rulerHeight)
                        }
                        .overlay(
                            Rectangle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1),
                            alignment: .bottom
                        )
                        
                        // Synchronized track headers
                        SynchronizedScrollView(
                            axes: .vertical,
                            showsIndicators: false,
                            contentSize: CGSize(width: headerWidth, height: contentSize.height),
                            normalizedX: .constant(0),
                            normalizedY: $scrollSync.verticalScrollPosition,
                            isUpdatingX: { false },
                            isUpdatingY: { scrollSync.isUpdatingVertical },
                            onUserScrollX: { _ in },
                            onUserScrollY: { scrollSync.updateVerticalPosition($0) }
                        ) {
                            AnyView(trackHeadersContent)
                        }
                    }
                    .frame(width: headerWidth)
                    
                    // Vertical separator
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 1)
                    
                    // RIGHT: Timeline Ruler + Tracks Area
                    VStack(spacing: 0) {
                        // Timeline ruler (horizontal scrolling only)
                        SynchronizedScrollView(
                            axes: .horizontal,
                            showsIndicators: false,
                            contentSize: CGSize(width: contentSize.width, height: rulerHeight),
                            normalizedX: $scrollSync.horizontalScrollPosition,
                            normalizedY: .constant(0),
                            isUpdatingX: { scrollSync.isUpdatingHorizontal },
                            isUpdatingY: { false },
                            onUserScrollX: { scrollSync.updateHorizontalPosition($0) },
                            onUserScrollY: { _ in }
                        ) {
                            AnyView(timelineRulerContent)
                        }
                        .frame(height: rulerHeight)
                        
                        // Horizontal separator
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                        
                        // Tracks area (both axes - master scroll view)
                        SynchronizedScrollView(
                            axes: .both,
                            showsIndicators: false,
                            contentSize: contentSize,
                            normalizedX: $scrollSync.horizontalScrollPosition,
                            normalizedY: $scrollSync.verticalScrollPosition,
                            isUpdatingX: { scrollSync.isUpdatingHorizontal },
                            isUpdatingY: { scrollSync.isUpdatingVertical },
                            onUserScrollX: { scrollSync.updateHorizontalPosition($0) },
                            onUserScrollY: { scrollSync.updateVerticalPosition($0) }
                        ) {
                            AnyView(tracksAreaContent)
                        }
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
                .onChange(of: scrollSync.verticalScrollPosition) { _, newValue in
                    scrollSync.setVerticalPosition(newValue)
                }
                .onChange(of: scrollSync.horizontalScrollPosition) { _, newValue in
                    scrollSync.setHorizontalPosition(newValue)
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
        .onChange(of: projectManager.currentProject) { _, newProject in
            // Force UI refresh when project changes (including new tracks)
            refreshTrigger = UUID()
            // Project changed, refreshing UI
        }
        .id(refreshTrigger) // Force complete view refresh when project changes
    }
    
    // MARK: - Content Views
    
    private var trackHeadersContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(project?.tracks ?? []) { audioTrack in
                IntegratedTrackHeader(
                    trackId: audioTrack.id,
                    selectedTrackId: $selectedTrackId,
                    selectedRegionId: $selectedRegionId,
                    height: effectiveTrackHeight,
                    audioEngine: audioEngine,
                    projectManager: projectManager,
                    onSelect: {
                        selectedTrackId = audioTrack.id
                    }
                )
                .id("\(audioTrack.id)-\(selectedTrackId?.uuidString ?? "none")")
            }
        }
        .frame(width: headerWidth)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var timelineRulerContent: some View {
        ZStack(alignment: .topLeading) {
            IntegratedTimelineRuler(
                currentPosition: audioEngine.currentPosition.timeInterval,
                pixelsPerSecond: pixelsPerSecond,
                contentWidth: contentSize.width,
                height: rulerHeight
            )
            
            // Cycle overlay - now in the same scroll context as the ruler
            if audioEngine.isCycleEnabled {
                InteractiveCycleOverlay(
                    cycleStartTime: audioEngine.cycleStartTime,
                    cycleEndTime: audioEngine.cycleEndTime,
                    horizontalZoom: Double(pixelsPerSecond / 100.0), // reverse of calc
                    onCycleRegionChanged: { start, end in
                        audioEngine.setCycleRegion(start: start, end: end)
                    }
                )
                // No offsets needed - it's in the same coordinate space as the ruler now
            }
        }
        .frame(width: contentSize.width, height: rulerHeight)
    }
    
    private var tracksAreaContent: some View {
        ZStack(alignment: .topLeading) {
            // Background grid
            IntegratedGridBackground(
                contentSize: contentSize,
                trackHeight: effectiveTrackHeight,
                pixelsPerSecond: pixelsPerSecond,
                trackCount: project?.tracks.count ?? 0
            )
            
            // Track rows with regions
            LazyVStack(spacing: 0) {
                ForEach(project?.tracks ?? []) { audioTrack in
                    IntegratedTrackRow(
                        audioTrack: audioTrack,
                        selectedTrackId: $selectedTrackId,
                        selectedRegionId: $selectedRegionId,
                        height: effectiveTrackHeight,
                        pixelsPerSecond: pixelsPerSecond,
                        audioEngine: audioEngine,
                        projectManager: projectManager,
                        onSelect: {
                            selectedTrackId = audioTrack.id
                        },
                        onRegionMove: moveRegion
                    )
                    .id("\(audioTrack.id)-row-\(selectedTrackId?.uuidString ?? "none")")
                }
            }
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .background(Color(NSColor.textBackgroundColor))
    }
}

// MARK: - Integrated Track Header

struct IntegratedTrackHeader: View {
    let trackId: UUID  // Store ID instead of track snapshot
    @Binding var selectedTrackId: UUID?  // Direct binding for reactive updates
    @Binding var selectedRegionId: UUID?  // Region selection binding
    let height: CGFloat
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let onSelect: () -> Void
    
    // Computed property that will refresh when selectedTrackId binding changes
    private var isSelected: Bool {
        selectedTrackId == trackId
    }
    
    // Computed property to get current track state reactively
    private var audioTrack: AudioTrack {
        projectManager.currentProject?.tracks.first { $0.id == trackId } ?? AudioTrack(name: "Unknown", color: .gray)
    }
    
    // AI Generation state
    @State private var showingAIGeneration = false
    
    var body: some View {
        // let _ = print("🎯 IntegratedTrackHeader: \(audioTrack.name) isSelected=\(isSelected)")
        HStack(spacing: 8) {
            // Track icon and color indicator
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(trackColor)
                    .frame(width: 4, height: height * 0.6)
                
                Image(systemName: trackIcon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 20)
            }
            
            // Track name and type
            VStack(alignment: .leading, spacing: 2) {
                Text(audioTrack.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("Audio")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Control buttons section
            HStack(spacing: 4) {
                // Record button
                recordButton
                
                // Mute button
                muteButton
                
                // Solo button  
                soloButton
                
                // Volume slider (compact)
                VStack(spacing: 2) {
                    Text("Vol")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Slider(
                        value: Binding(
                            get: { Double(audioTrack.mixerSettings.volume) },
                            set: { newValue in
                                audioEngine.updateTrackVolume(trackId: audioTrack.id, volume: Float(newValue))
                                projectManager.saveCurrentProject()
                            }
                        ),
                        in: 0...1
                    )
                    .frame(width: 40)
                    .controlSize(.mini)
                }
                
                // Pan control (compact)
                VStack(spacing: 2) {
                    Text("Pan")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Slider(
                        value: Binding(
                            get: { Double(audioTrack.mixerSettings.pan) },
                            set: { newValue in
                                audioEngine.updateTrackPan(trackId: audioTrack.id, pan: Float(newValue))
                                projectManager.saveCurrentProject()
                            }
                        ),
                        in: -1...1
                    )
                    .frame(width: 40)
                    .controlSize(.mini)
                }
                
                // AI Generation button
                aiGenerationButton
                
                // Delete button
                deleteButton
            }
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .background(trackRowBackground)
        .contentShape(Rectangle())
        .onTapGesture {
            print("🎯 Track Header Tapped: \(audioTrack.name) (\(trackId))")
            selectedRegionId = nil  // Clear region selection when clicking track header
            onSelect()
            print("🎯 Track Header Selection Called")
        }
        .sheet(isPresented: $showingAIGeneration) {
            AIGenerationView(targetTrack: audioTrack, projectManager: projectManager)
        }
    }
    
    private var trackColor: Color {
        // Generate consistent color based on track name/id
        let colors: [Color] = [.red, .orange, .yellow, .green, .mint, .teal, .cyan, .blue, .indigo, .purple, .pink, .brown]
        let index = abs(audioTrack.name.hashValue) % colors.count
        return colors[index].opacity(0.8)
    }
    
    private var trackIcon: String {
        // Choose icon based on track type or name
        let name = audioTrack.name.lowercased()
        if name.contains("kick") || name.contains("drum") { return "music.note" }
        if name.contains("bass") { return "waveform" }
        if name.contains("guitar") { return "guitars" }
        if name.contains("piano") || name.contains("keys") { return "pianokeys" }
        if name.contains("vocal") || name.contains("voice") { return "mic" }
        if name.contains("synth") { return "tuningfork" }
        return "music.quarternote.3"
    }
    
    private var recordButton: some View {
        Button(action: {
            // Toggle record enable for track
            let newState = !audioTrack.mixerSettings.isRecordEnabled
            audioEngine.updateTrackRecordEnabled(trackId: audioTrack.id, isRecordEnabled: newState)
            projectManager.saveCurrentProject()
        }) {
            Image(systemName: "record.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(audioTrack.mixerSettings.isRecordEnabled ? .red : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    private var muteButton: some View {
        Button(action: {
            let newState = !audioTrack.mixerSettings.isMuted
            audioEngine.updateTrackMute(trackId: audioTrack.id, isMuted: newState)
        }) {
            Text("M")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(audioTrack.mixerSettings.isMuted ? .white : .secondary)
                .frame(width: 20, height: 20)
                .background(audioTrack.mixerSettings.isMuted ? .orange : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(audioTrack.mixerSettings.isMuted ? .orange : .gray, lineWidth: 1)
                )
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
    
    private var soloButton: some View {
        Button(action: {
            let newState = !audioTrack.mixerSettings.isSolo
            audioEngine.updateTrackSolo(trackId: audioTrack.id, isSolo: newState)
        }) {
            Text("S")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(audioTrack.mixerSettings.isSolo ? .black : .secondary)
                .frame(width: 20, height: 20)
                .background(audioTrack.mixerSettings.isSolo ? .yellow : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(audioTrack.mixerSettings.isSolo ? .yellow : .gray, lineWidth: 1)
                )
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
    }
    
    private var aiGenerationButton: some View {
        Button(action: {
            showingAIGeneration = true
        }) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.purple)
        }
        .buttonStyle(.plain)
        .help("Generate AI music for this track")
    }
    
    private var deleteButton: some View {
        Button(action: {
            projectManager.removeTrack(audioTrack.id)
        }) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.red)
        }
        .buttonStyle(.plain)
        .help("Delete track")
    }
    
    private var trackRowBackground: some View {
        let backgroundColor = isSelected ? Color.blue.opacity(0.1) : Color.clear
        // let _ = print("🎨 trackRowBackground: \(audioTrack.name) isSelected=\(isSelected) → \(isSelected ? "BLUE" : "CLEAR")")
        return Rectangle()
            .fill(backgroundColor)
            .overlay(
                Rectangle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5),
                alignment: .bottom
            )
    }
}

// MARK: - Integrated Timeline Ruler

struct IntegratedTimelineRuler: View {
    let currentPosition: TimeInterval
    let pixelsPerSecond: CGFloat
    let contentWidth: CGFloat
    let height: CGFloat
    @EnvironmentObject var audioEngine: AudioEngine
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Ruler background
            Rectangle()
                .fill(Color(NSColor.controlBackgroundColor))
            
            // Time markers
            Canvas { context, size in
                drawTimeMarkers(context: context, size: size)
            }
            
            // Playhead
            Rectangle()
                .fill(Color.red)
                .frame(width: 2)
                .offset(x: currentPosition * pixelsPerSecond)
        }
        .frame(width: contentWidth, height: height)
        .contentShape(Rectangle())
        .background(
            GeometryReader { geo in
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let x = value.location.x
                                let targetTime = max(0, Double(x / pixelsPerSecond))
                                audioEngine.seekToPosition(targetTime)
                                print("🎯 RULER CLICK: Seeking to \(String(format: "%.2f", targetTime))s")
                            }
                    )
            }
        )
    }
    
    private func drawTimeMarkers(context: GraphicsContext, size: CGSize) {
        let totalSeconds = Int(contentWidth / pixelsPerSecond)
        
        // All 1-second markers
        for second in 0...totalSeconds {
            let x = CGFloat(second) * pixelsPerSecond
            
            if second % 10 == 0 {
                // Major markers every 10 seconds - tallest with labels
                let majorPath = Path { path in
                    path.move(to: CGPoint(x: x, y: 25))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(majorPath, with: .color(.primary), lineWidth: 1.5)
                
                // Time label for major markers
                let minutes = second / 60
                let seconds = second % 60
                let timeText = String(format: "%d:%02d", minutes, seconds)
                
                context.draw(
                    Text(timeText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.primary),
                    at: CGPoint(x: x + 4, y: 8)
                )
            } else if second % 5 == 0 {
                // Medium markers every 5 seconds
                let mediumPath = Path { path in
                    path.move(to: CGPoint(x: x, y: 35))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(mediumPath, with: .color(.primary.opacity(0.7)), lineWidth: 1)
            } else {
                // Minor markers every 1 second - positioned from top
                let minorPath = Path { path in
                    path.move(to: CGPoint(x: x, y: 45))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(minorPath, with: .color(.primary.opacity(0.4)), lineWidth: 1.0)
            }
        }
    }
}

// MARK: - Integrated Grid Background

struct IntegratedGridBackground: View {
    let contentSize: CGSize
    let trackHeight: CGFloat
    let pixelsPerSecond: CGFloat
    let trackCount: Int
    
    var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
        }
        .frame(width: contentSize.width, height: contentSize.height)
    }
    
    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let totalSeconds = Int(contentSize.width / pixelsPerSecond)
        
        // Vertical grid lines (every 5 seconds)
        for second in stride(from: 0, through: totalSeconds, by: 5) {
            let x = CGFloat(second) * pixelsPerSecond
            let path = Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
        }
        
        // Horizontal grid lines (track separators)
        for trackIndex in 0...trackCount {
            let y = CGFloat(trackIndex) * trackHeight
            let path = Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
        }
    }
}

// MARK: - Integrated Track Row

struct IntegratedTrackRow: View {
    let audioTrack: AudioTrack
    @Binding var selectedTrackId: UUID?  // Direct binding for reactive updates
    @Binding var selectedRegionId: UUID?  // Region selection binding
    let height: CGFloat
    let pixelsPerSecond: CGFloat
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let onSelect: () -> Void
    let onRegionMove: (UUID, TimeInterval) -> Void  // Region move callback
    
    // Computed property that will refresh when selectedTrackId binding changes
    private var isSelected: Bool {
        selectedTrackId == audioTrack.id
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Track background
            Rectangle()
                .fill(isSelected ? Color.blue.opacity(0.05) : Color.clear)
            
            // Audio regions
            ForEach(audioTrack.regions) { region in
                PositionedAudioRegion(
                    region: region,
                    pixelsPerSecond: pixelsPerSecond,
                    trackHeight: height,
                    selectedRegionId: $selectedRegionId,
                    onRegionSelect: { regionId in
                        selectedRegionId = regionId
                        selectedTrackId = audioTrack.id  // Also select the parent track
                    },
                    onRegionMove: onRegionMove,
                    audioEngine: audioEngine,
                    projectManager: projectManager,
                    trackId: audioTrack.id
                )
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedRegionId = nil  // Clear region selection when clicking track
            onSelect()
        }
    }
}

// MARK: - Positioned Audio Region Wrapper

struct PositionedAudioRegion: View {
    let region: AudioRegion
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    @Binding var selectedRegionId: UUID?
    let onRegionSelect: (UUID) -> Void
    let onRegionMove: (UUID, TimeInterval) -> Void
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let trackId: UUID
    
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging: Bool = false
    
    var body: some View {
        let baseX = region.startTime * pixelsPerSecond
        // let regionWidth = region.duration * pixelsPerSecond // Unused - calculated in IntegratedAudioRegion
        
        // Debug logging for region positioning (simplified)
        // if isDragging {
        //     let totalX = baseX + dragOffset
        //     print("🎯 DRAG: '\(region.audioFile.name)' @ \(String(format: "%.1f", totalX))px")
        // }
        
        return IntegratedAudioRegion(
            region: region,
            pixelsPerSecond: pixelsPerSecond,
            trackHeight: trackHeight,
            selectedRegionId: $selectedRegionId,
            onRegionSelect: onRegionSelect,
            onRegionMove: onRegionMove,
            dragOffset: $dragOffset,
            isDragging: $isDragging,
            audioEngine: audioEngine,
            projectManager: projectManager,
            trackId: trackId
        )
        .offset(
            x: baseX + (isDragging ? dragOffset : 0),
            y: 8
        )
    }
}

// MARK: - Integrated Audio Region

struct IntegratedAudioRegion: View {
    let region: AudioRegion
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    @Binding var selectedRegionId: UUID?  // Selection binding
    let onRegionSelect: (UUID) -> Void    // Selection callback
    let onRegionMove: (UUID, TimeInterval) -> Void  // Drag callback
    
    // Drag state (now passed from parent)
    @Binding var dragOffset: CGFloat
    @Binding var isDragging: Bool
    
    // Context menu dependencies
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let trackId: UUID
    
    private var regionWidth: CGFloat {
        region.duration * pixelsPerSecond
    }
    
    private var regionHeight: CGFloat {
        trackHeight - 16 // 8pt margin top and bottom
    }
    
    // Computed property for selection state
    private var isSelected: Bool {
        selectedRegionId == region.id
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Main region background
            RoundedRectangle(cornerRadius: 4)
                .fill(regionColor.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(regionColor, lineWidth: 1)
                )
            
            // Selection border overlay (Logic Pro style)
            if isSelected {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.blue, lineWidth: 3)
                    .background(
                        // Subtle glow effect
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 6)
                            .blur(radius: 2)
                    )
                    .overlay(
                        // Selection header bar (inverted style)
                        VStack {
                            Rectangle()
                                .fill(Color.blue)
                                .frame(height: 20)
                                .overlay(
                                    HStack {
                                        Text(region.audioFile.name)
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Spacer()
                                        // Add duration in selection header
                                        Text(formatDuration(region.duration))
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                    .padding(.horizontal, 6)
                                )
                            Spacer()
                        }
                    )
            }
            
            // Region content (only show when not selected to avoid overlap)
            if !isSelected {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(region.audioFile.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        
                        Text(formatDuration(region.duration))
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.leading, 6)
                    .padding(.top, 4)
                    
                    Spacer()
                }
            }
            
            // Waveform visualization (placeholder for now)
            // TODO: Implement waveform data extraction from AudioRegion
            WaveformVisualization(data: generatePlaceholderWaveform())
                .opacity(isSelected ? 0.2 : 0.4)
                .padding(.horizontal, 4)
                .padding(.top, isSelected ? 20 : 0) // Offset for selection header
        }
        .frame(width: regionWidth, height: regionHeight)
        .shadow(
            color: isSelected ? Color.blue.opacity(0.4) : Color.black.opacity(0.1),
            radius: isSelected ? 6 : 2,
            x: 0, y: isSelected ? 3 : 1
        )
        .scaleEffect(isSelected ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .contentShape(Rectangle())
        .onTapGesture {
            onRegionSelect(region.id)
        }
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        onRegionSelect(region.id)  // Select region when drag starts
                        // print("🚀 DRAG STARTED: '\(region.audioFile.name)' at startTime: \(String(format: "%.2f", region.startTime))s")
                    }
                    
                    // Use absolute position difference instead of translation to avoid feedback loop
                    let absoluteOffset = value.location.x - value.startLocation.x
                    dragOffset = absoluteOffset
                }
                .onEnded { value in
                    let absoluteOffset = value.location.x - value.startLocation.x
                    print("🏁 DRAG ENDED: final absolute offset: \(String(format: "%.1f", absoluteOffset))px")
                    
                    isDragging = false
                    
                    // Calculate new start time based on absolute position difference
                    let timeOffset = absoluteOffset / pixelsPerSecond
                    let newStartTime = max(0, region.startTime + timeOffset)
                    
                    // Snap to grid (optional - can be refined later)
                    let snappedStartTime = round(newStartTime * 4) / 4  // Snap to quarter seconds
                    
                    print("⏰ TIME CALC: timeOffset: \(String(format: "%.2f", timeOffset))s, newStartTime: \(String(format: "%.2f", newStartTime))s, snapped: \(String(format: "%.2f", snappedStartTime))s")
                    
                    // Reset visual offset and apply actual position change
                    dragOffset = 0
                    onRegionMove(region.id, snappedStartTime)
                }
        )
        .contextMenu {
            regionContextMenu
        }
        .clipped()
    }
    
    private var regionColor: Color {
        // Generate consistent color based on region name
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .cyan, .pink, .yellow]
        let index = abs(region.audioFile.name.hashValue) % colors.count
        return colors[index]
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private func generatePlaceholderWaveform() -> [Float] {
        // Generate placeholder waveform data for visualization
        let sampleCount = 100
        return (0..<sampleCount).map { _ in Float.random(in: -1...1) }
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
            
            Button("Split at Playhead") {
                let playheadTime = audioEngine.currentPosition.timeInterval
                splitRegionAtPlayhead(playheadTime)
            }
            .disabled(!canSplitAtPlayhead)
            
            Divider()
            
            Button("Delete") {
                projectManager.removeRegionFromTrack(region.id, trackId: trackId)
            }
            
            Divider()
            
            Button("Duplicate") {
                duplicateRegion()
            }
            
            Divider()
            
            Button("Fade In...") {
                // TODO: Implement fade in
            }
            Button("Fade Out...") {
                // TODO: Implement fade out
            }
        }
    }
    
    // MARK: - Context Menu Helpers
    private var canSplitAtPlayhead: Bool {
        let playheadTime = audioEngine.currentPosition.timeInterval
        let regionEndTime = region.startTime + region.duration
        return playheadTime > region.startTime && playheadTime < regionEndTime
    }
    
    private func splitRegionAtPlayhead(_ playheadTime: TimeInterval) {
        projectManager.splitRegionAtPosition(region.id, trackId: trackId, splitTime: playheadTime)
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
        projectManager.addRegionToTrack(duplicatedRegion, trackId: trackId)
    }
}

// MARK: - Waveform Visualization

struct WaveformVisualization: View {
    let data: [Float]
    
    var body: some View {
        Canvas { context, size in
            let sampleCount = min(data.count, Int(size.width / 2))
            let centerY = size.height / 2
            let widthPerSample = size.width / CGFloat(sampleCount)
            
            for i in 0..<sampleCount {
                let x = CGFloat(i) * widthPerSample
                let amplitude = CGFloat(abs(data[i])) * centerY
                
                let path = Path { path in
                    path.move(to: CGPoint(x: x, y: centerY - amplitude))
                    path.addLine(to: CGPoint(x: x, y: centerY + amplitude))
                }
                
                context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1)
            }
        }
    }
}

// MARK: - Add Track Button Style

struct AddTrackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle()
                    .fill(buttonBackgroundColor(configuration: configuration))
                    .overlay(
                        Rectangle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private func buttonBackgroundColor(configuration: Configuration) -> Color {
        if configuration.isPressed {
            Color(NSColor.controlAccentColor).opacity(0.2)
        } else {
            Color(NSColor.controlBackgroundColor)
        }
    }
}
