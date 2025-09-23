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
    
    // [V2-ANALYSIS] Audio analysis service for tempo/pitch detection
    @StateObject private var analysisService = AudioAnalysisService()
    
    // Computed property to get current project reactively
    private var project: AudioProject? { projectManager.currentProject }
    @Binding var selectedTrackId: UUID?
    @StateObject private var selection = SelectionManager() // [V2-MULTISELECT]
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

    // TEMP: Build-unblock wrappers. These will be replaced by the Environment actions.
    private func matchTempoToRegion(_ targetRegionId: UUID) {
        // TODO: wire to real analysis
        print("matchTempoToRegion(_:) called for \(targetRegionId)")
    }

    private func matchPitchToRegion(_ targetRegionId: UUID) {
        // TODO: wire to real analysis
        print("matchPitchToRegion(_:) called for \(targetRegionId)")
    }

    private func autoMatchSelectedRegions() {
        // TODO: wire to real analysis
        print("autoMatchSelectedRegions() called")
    }
    
    // Layout constants adapted from layout-test-1
    private let headerWidth: CGFloat = 280
    private let rulerHeight: CGFloat = 60
    private let trackRowHeight: CGFloat = 80
    
    // Dynamic sizing based on zoom
    private var effectiveTrackHeight: CGFloat { trackRowHeight * CGFloat(verticalZoom) }
    private var pixelsPerSecond: CGFloat { 100 * CGFloat(horizontalZoom) }
    
    // [V2-MULTISELECT] Marquee selection state
    @State private var marqueeStart: CGPoint? = nil
    
    // Content sizing for scroll sync
    private var contentSize: CGSize {
        guard let project = project else {
            return CGSize(width: 3000, height: 1000) // Default size
        }
        
        let width = max(3000, pixelsPerSecond * 60) // At least 60 seconds visible
        let height = CGFloat(project.tracks.count) * effectiveTrackHeight
        return CGSize(width: width, height: height)
    }
    
    // [V2-MULTISELECT] Marquee drag gesture
    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .modifiers(.command) // Cmd+drag for marquee
            .onChanged { value in
                if marqueeStart == nil {
                    marqueeStart = value.startLocation
                    selection.isMarqueeActive = true
                }
                let origin = marqueeStart!
                let rect = CGRect(
                    x: min(origin.x, value.location.x),
                    y: min(origin.y, value.location.y),
                    width: abs(value.location.x - origin.x),
                    height: abs(value.location.y - origin.y)
                )
                selection.marqueeRect = rect
            }
            .onEnded { _ in
                defer {
                    selection.isMarqueeActive = false
                    selection.marqueeRect = .zero
                    marqueeStart = nil
                }
                // Hit-test regions
                let ids = (project?.tracks ?? []).flatMap { track -> [UUID] in
                    track.regions.compactMap { region in
                        let frame = CGRect(
                            x: region.startTime * pixelsPerSecond,
                            y: CGFloat(indexOfTrack(track)) * effectiveTrackHeight + CGFloat(8),
                            width: region.duration * pixelsPerSecond,
                            height: effectiveTrackHeight - 16
                        )
                        return frame.intersects(selection.marqueeRect) ? region.id : nil
                    }
                }
                selection.selectedRegionIds.formUnion(ids)
                if selection.selectionAnchor == nil {
                    selection.selectionAnchor = selection.selectedRegionIds.first
                }
            }
    }
    
    // [V2-MULTISELECT] Helper to find track index
    private func indexOfTrack(_ track: AudioTrack) -> Int {
        (project?.tracks.firstIndex(where: { $0.id == track.id }) ?? 0)
    }
    
    var body: some View {
        // [V2-ANALYSIS] Create TimelineActions bundle with real functions
        let actions = TimelineActions(
            matchTempoToRegion: matchTempoToRegion,
            matchPitchToRegion: matchPitchToRegion,
            autoMatchSelectedRegions: autoMatchSelectedRegions
        )
        
        ZStack(alignment: .top) {
            // Main timeline content
            VStack(spacing: 0) {
                if project != nil {
                HStack(spacing: 0) {
                    // LEFT: Track Headers Column (vertical scrolling only)
                    VStack(spacing: 0) {
                        // Header spacer with professional Add Track button
                        HStack(spacing: 0) {
                            // Professional Add Track button with hover states
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
                    .coordinateSpace(name: "timelineRoot")
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
            
            // [V2-MULTISELECT] Selection count badge - FIXED POSITION at top
            if selection.selectedRegionIds.count > 1 {
                HStack {
                    Spacer()
                    Text("\(selection.selectedRegionIds.count) regions selected")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    Spacer()
                }
                .padding(.top, 8)
                .allowsHitTesting(false)
            }
        }
        .environment(\.timelineActions, actions) // [V2-ANALYSIS] Provide actions to all child views
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
        ProfessionalTimelineRuler(
            pixelsPerSecond: pixelsPerSecond,
            contentWidth: contentSize.width,
            height: rulerHeight  // keep at 60
        )
        .environmentObject(audioEngine)
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
                        selection: selection, // [V2-MULTISELECT]
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
            
            // [V2-MULTISELECT] Marquee selection overlay
            if selection.isMarqueeActive {
                Rectangle()
                    .fill(Color.blue.opacity(0.10))
                    .overlay(
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4,3]))
                            .foregroundColor(.blue)
                    )
                    .frame(width: selection.marqueeRect.width, height: selection.marqueeRect.height)
                    .position(x: selection.marqueeRect.midX, y: selection.marqueeRect.midY)
            }
            
        }
        .frame(width: contentSize.width, height: contentSize.height)
        .background(Color(NSColor.textBackgroundColor))
        .contentShape(Rectangle())
        .gesture(marqueeGesture)
        .onReceive(NotificationCenter.default.publisher(for: .init("SelectAllRegions"))) { _ in
            // [V2-MULTISELECT] Select All
            let allIds = (project?.tracks.flatMap { $0.regions.map(\.id) } ?? [])
            selection.selectAll(allIds)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("ClearSelection"))) { _ in
            // [V2-MULTISELECT] Clear Selection
            selection.clear()
        }
    }
}

// MARK: - Integrated Track Header

struct IntegratedTrackHeader: View {
    let trackId: UUID  // Store ID instead of track snapshot
    @Binding var selectedTrackId: UUID?  // Direct binding for reactive updates
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
// TODO: DEAD CODE - This struct can be deleted in future dead code cleanup cycle
// This timeline ruler has been replaced by ProfessionalTimelineRuler
// Keeping for now to avoid disruption, but no longer used in the main app

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
    @ObservedObject var selection: SelectionManager   // [V2-MULTISELECT]
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
                    selection: selection, // [V2-MULTISELECT]
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
            selection.clear()  // [V2-MULTISELECT] Clear region selection when clicking track
            onSelect()
        }
    }
}

// MARK: - Positioned Audio Region Wrapper

struct PositionedAudioRegion: View {
    let region: AudioRegion
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    @ObservedObject var selection: SelectionManager // [V2-MULTISELECT]
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
            selection: selection, // [V2-MULTISELECT]
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
    @ObservedObject var selection: SelectionManager // [V2-MULTISELECT]
    let onRegionMove: (UUID, TimeInterval) -> Void  // Drag callback
    
    // Drag state (now passed from parent)
    @Binding var dragOffset: CGFloat
    @Binding var isDragging: Bool
    
    // Context menu dependencies
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let trackId: UUID
    
    // [V2-ANALYSIS] Access to timeline actions via Environment
    @Environment(\.timelineActions) var timelineActions
    
    private var regionWidth: CGFloat {
        region.duration * pixelsPerSecond
    }
    
    private var regionHeight: CGFloat {
        trackHeight - 16 // 8pt margin top and bottom
    }
    
    // Computed property for selection state
    private var isSelected: Bool {
        let selected = selection.isSelected(region.id) // [V2-MULTISELECT]
        // Debug logging for selection state
        if selected {
            print("🔵 REGION SELECTED: \(region.audioFile.name) - ID: \(region.id)")
        }
        return selected
    }
    
    // [V2-MULTISELECT] Helper to get ordered region IDs in this track
    private func audioTrackRegionOrder() -> [UUID] {
        (projectManager.currentProject?
            .tracks.first(where: { $0.id == trackId })?
            .regions.sorted(by: { $0.startTime < $1.startTime })
            .map(\.id)) ?? []
    }
    
    // [V2-MULTISELECT] Get all regions across all tracks, ordered by start time
    private func allRegionsOrder() -> [UUID] {
        guard let project = projectManager.currentProject else { return [] }
        
        let allRegions = project.tracks.flatMap { track in
            track.regions.map { region in
                (id: region.id, startTime: region.startTime)
            }
        }
        
        return allRegions
            .sorted(by: { $0.startTime < $1.startTime })
            .map(\.id)
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
            
            // Selection border overlay (professional style)
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
        // [V2-MULTISELECT] Exclusive gesture handling to prevent conflicts
        .gesture(
            // Cmd+click = toggle (highest priority)
            TapGesture().modifiers(.command).onEnded {
                print("🔄 CMD+CLICK: Toggling region \(region.id)")
                selection.toggle(region.id)
            }
            .exclusively(before:
                // Shift+click = range selection
                TapGesture().modifiers(.shift).onEnded {
                    print("🔄 SHIFT+CLICK: Range selecting to region \(region.id)")
                    let ids = allRegionsOrder()
                    selection.selectRange(in: ids, to: region.id)
                }
                .exclusively(before:
                    // Plain click = select only (lowest priority)
                    TapGesture().onEnded {
                        print("🔄 PLAIN CLICK: Selecting only region \(region.id)")
                        selection.selectOnly(region.id)
                    }
                )
            )
        )
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        // [V2-MULTISELECT] Select region when drag starts (if not already selected)
                        if !selection.isSelected(region.id) {
                            selection.selectOnly(region.id)
                        }
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
            
            // [V2-MULTISELECT] Pitch/Tempo Matching (only show when multiple regions selected)
            if selection.selectedRegionIds.count > 1 {
                Menu("Pitch & Tempo Matching") {
                    Button("Match Tempo to This Region") {
                        timelineActions.matchTempoToRegion(region.id)
                    }
                    
                    Button("Match Pitch to This Region") {
                        timelineActions.matchPitchToRegion(region.id)
                    }
                    
                    Divider()
                    
                    Button("Auto-Match All Selected") {
                        timelineActions.autoMatchSelectedRegions()
                    }
                    
                    Divider()
                    
                    Menu("Advanced Matching") {
                        Button("Sync to Project Tempo") {
                            syncSelectedToProjectTempo()
                        }
                        
                        Button("Harmonize Selected Regions") {
                            harmonizeSelectedRegions()
                        }
                        
                        Button("Reset Pitch & Tempo") {
                            resetPitchTempoForSelected()
                        }
                    }
                }
                
                Divider()
            }
            
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
    
    // MARK: [V2-MULTISELECT] Pitch/Tempo Matching Actions
    
    private func matchTempoToRegion(_ targetRegionId: UUID) {
        print("🎵 TEMPO MATCH: Starting tempo matching to region \(targetRegionId)")
        print("   Selected regions: \(selection.selectedRegionIds)")
        
        Task { @MainActor in
            guard let project = projectManager.currentProject else {
                print("🎵 TEMPO MATCH: No project available")
                return
            }
            
            // Find target region and its audio file
            guard let targetRegion = findRegion(targetRegionId, in: project) else {
                print("🎵 TEMPO MATCH: Target region not found")
                return
            }
            let targetFile = targetRegion.audioFile
            
            // Analyze target region tempo
            print("🎵 TEMPO MATCH: Analyzing target region tempo...")
            // TODO: Implement real analysis - temporarily stubbed
            let targetTempo: Double? = 120.0 // Stub tempo
            guard let targetTempo = targetTempo else {
                print("🎵 TEMPO MATCH: Could not detect target tempo")
                return
            }
            
            // Update target region with detected tempo
            updateRegionTempo(targetRegionId, tempo: targetTempo)
            
            // Process other selected regions
            let otherRegionIds = selection.selectedRegionIds.subtracting([targetRegionId])
            print("🎵 TEMPO MATCH: Processing \(otherRegionIds.count) other regions...")
            
            for regionId in otherRegionIds {
                guard let region = findRegion(regionId, in: project) else {
                    print("🎵 TEMPO MATCH: Skipping region \(regionId) - not found")
                    continue
                }
                let audioFile = region.audioFile
                
                // Detect region's current tempo
                // TODO: Implement real analysis - temporarily stubbed
                let regionTempo: Double? = 120.0 // Stub tempo
                updateRegionTempo(regionId, tempo: regionTempo)
                
                // Calculate tempo adjustment
                let tempoRate: Float
                if let regionTempo = regionTempo {
                    tempoRate = Float(targetTempo / regionTempo)
                    print("🎵 TEMPO MATCH: Region \(regionId) - detected: \(regionTempo) BPM, rate: \(tempoRate)")
                } else {
                    tempoRate = 1.0
                    print("🎵 TEMPO MATCH: Region \(regionId) - could not detect tempo, using rate: 1.0")
                }
                
                // Apply tempo adjustment to the track
                updateRegionTempoRate(regionId, rate: tempoRate)
                applyTempoRateToTrack(regionId, rate: tempoRate)
            }
            
            print("🎵 TEMPO MATCH: Completed tempo matching to \(targetTempo) BPM")
        }
    }
    
    private func matchPitchToRegion(_ targetRegionId: UUID) {
        print("🎵 PITCH MATCH: Starting pitch matching to region \(targetRegionId)")
        print("   Selected regions: \(selection.selectedRegionIds)")
        
        Task { @MainActor in
            guard let project = projectManager.currentProject else {
                print("🎵 PITCH MATCH: No project available")
                return
            }
            
            // Find target region and its audio file
            guard let targetRegion = findRegion(targetRegionId, in: project) else {
                print("🎵 PITCH MATCH: Target region not found")
                return
            }
            let targetFile = targetRegion.audioFile
            
            // Analyze target region key
            print("🎵 PITCH MATCH: Analyzing target region key...")
            // TODO: Implement real analysis - temporarily stubbed
            let targetKey: String? = "C Major" // Stub key
            guard let targetKey = targetKey else {
                print("🎵 PITCH MATCH: Could not detect target key")
                return
            }
            
            // Update target region with detected key
            updateRegionKey(targetRegionId, key: targetKey)
            
            // Process other selected regions
            let otherRegionIds = selection.selectedRegionIds.subtracting([targetRegionId])
            print("🎵 PITCH MATCH: Processing \(otherRegionIds.count) other regions...")
            
            for regionId in otherRegionIds {
                guard let region = findRegion(regionId, in: project) else {
                    print("🎵 PITCH MATCH: Skipping region \(regionId) - not found")
                    continue
                }
                let audioFile = region.audioFile
                
                // Detect region's current key
                // TODO: Implement real analysis - temporarily stubbed
                let regionKey: String? = "C Major" // Stub key
                updateRegionKey(regionId, key: regionKey)
                
                // Calculate pitch adjustment (simplified - real implementation would need music theory)
                let pitchShift: Float
                if let regionKey = regionKey {
                    pitchShift = calculatePitchShift(from: regionKey, to: targetKey)
                    print("🎵 PITCH MATCH: Region \(regionId) - detected: \(regionKey), shift: \(pitchShift) cents")
                } else {
                    pitchShift = 0.0
                    print("🎵 PITCH MATCH: Region \(regionId) - could not detect key, using shift: 0.0")
                }
                
                // Apply pitch adjustment to the track
                updateRegionPitchShift(regionId, cents: pitchShift)
                applyPitchShiftToTrack(regionId, cents: pitchShift)
            }
            
            print("🎵 PITCH MATCH: Completed pitch matching to \(targetKey)")
        }
    }
    
    private func autoMatchSelectedRegions() {
        print("🎵 [STUB] Auto-Match Selected Regions")
        print("   Selected regions: \(selection.selectedRegionIds)")
        // TODO Phase 3: Implement intelligent auto-matching
        // 1. Analyze all selected regions for tempo and key
        // 2. Determine optimal target tempo and key
        // 3. Apply smart adjustments to create harmonic/rhythmic coherence
    }
    
    // MARK: - Helper Functions for Audio Analysis
    
    private func findRegion(_ regionId: UUID, in project: AudioProject) -> AudioRegion? {
        for track in project.tracks {
            if let region = track.regions.first(where: { $0.id == regionId }) {
                return region
            }
        }
        return nil
    }
    
    private func updateRegionTempo(_ regionId: UUID, tempo: Double?) {
        guard let project = projectManager.currentProject else { return }
        
        for trackIndex in project.tracks.indices {
            if let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].detectedTempo = tempo
                print("🎵 UPDATE: Region \(regionId) tempo set to \(tempo?.description ?? "nil")")
                return
            }
        }
    }
    
    private func updateRegionKey(_ regionId: UUID, key: String?) {
        guard let project = projectManager.currentProject else { return }
        
        for trackIndex in project.tracks.indices {
            if let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].detectedKey = key
                print("🎵 UPDATE: Region \(regionId) key set to \(key ?? "nil")")
                return
            }
        }
    }
    
    private func updateRegionTempoRate(_ regionId: UUID, rate: Float) {
        guard let project = projectManager.currentProject else { return }
        
        for trackIndex in project.tracks.indices {
            if let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].tempoRate = rate
                print("🎵 UPDATE: Region \(regionId) tempo rate set to \(rate)")
                return
            }
        }
    }
    
    private func updateRegionPitchShift(_ regionId: UUID, cents: Float) {
        guard let project = projectManager.currentProject else { return }
        
        for trackIndex in project.tracks.indices {
            if let regionIndex = project.tracks[trackIndex].regions.firstIndex(where: { $0.id == regionId }) {
                projectManager.currentProject?.tracks[trackIndex].regions[regionIndex].pitchShiftCents = cents
                print("🎵 UPDATE: Region \(regionId) pitch shift set to \(cents) cents")
                return
            }
        }
    }
    
    private func applyTempoRateToTrack(_ regionId: UUID, rate: Float) {
        guard let project = projectManager.currentProject else { return }
        
        // Find which track contains this region
        for track in project.tracks {
            if track.regions.contains(where: { $0.id == regionId }) {
                if let trackNode = audioEngine.getTrackNode(for: track.id) {
                    trackNode.setPlaybackRate(rate)
                    print("🎵 APPLY: Applied tempo rate \(rate) to track \(track.name)")
                } else {
                    print("🎵 APPLY: Warning - no audio node found for track \(track.id)")
                }
                return
            }
        }
    }
    
    private func applyPitchShiftToTrack(_ regionId: UUID, cents: Float) {
        guard let project = projectManager.currentProject else { return }
        
        // Find which track contains this region
        for track in project.tracks {
            if track.regions.contains(where: { $0.id == regionId }) {
                if let trackNode = audioEngine.getTrackNode(for: track.id) {
                    trackNode.setPitchShift(cents)
                    print("🎵 APPLY: Applied pitch shift \(cents) cents to track \(track.name)")
                } else {
                    print("🎵 APPLY: Warning - no audio node found for track \(track.id)")
                }
                return
            }
        }
    }
    
    private func calculatePitchShift(from sourceKey: String, to targetKey: String) -> Float {
        // Simplified pitch shift calculation - real implementation would use music theory
        // This is a placeholder that returns 0 for same key, random shift for different keys
        
        if sourceKey == targetKey {
            return 0.0
        }
        
        // Extract root notes (simplified)
        let sourceRoot = String(sourceKey.prefix(1))
        let targetRoot = String(targetKey.prefix(1))
        
        let noteOrder = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        
        guard let sourceIndex = noteOrder.firstIndex(of: sourceRoot),
              let targetIndex = noteOrder.firstIndex(of: targetRoot) else {
            return 0.0
        }
        
        // Calculate semitone difference
        var semitones = targetIndex - sourceIndex
        if semitones > 6 { semitones -= 12 }
        if semitones < -6 { semitones += 12 }
        
        // Convert to cents (100 cents per semitone)
        return Float(semitones * 100)
    }
    
    private func syncSelectedToProjectTempo() {
        print("🎵 [STUB] Sync Selected to Project Tempo")
        print("   Selected regions: \(selection.selectedRegionIds)")
        // TODO Phase 2: Implement project tempo sync
        // 1. Get project tempo from ProjectManager
        // 2. Calculate tempo adjustments for each selected region
        // 3. Apply tempo rate changes to match project BPM
    }
    
    private func harmonizeSelectedRegions() {
        print("🎵 [STUB] Harmonize Selected Regions")
        print("   Selected regions: \(selection.selectedRegionIds)")
        // TODO Phase 3: Implement harmonic analysis and adjustment
        // 1. Analyze keys of all selected regions
        // 2. Determine optimal harmonic relationships
        // 3. Apply pitch shifts to create musical harmony
    }
    
    private func resetPitchTempoForSelected() {
        print("🎵 [STUB] Reset Pitch & Tempo for Selected")
        print("   Selected regions: \(selection.selectedRegionIds)")
        // TODO Phase 2: Implement reset functionality
        // 1. Set pitchShiftCents = 0.0 for all selected regions
        // 2. Set tempoRate = 1.0 for all selected regions
        // 3. Apply changes via TrackAudioNode pitch/tempo controls
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
