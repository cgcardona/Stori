//
//  SynchronizedTimelineView.swift
//  TellUrStoriDAW
//
//  Professional timeline with perfect scroll synchronization
//  Integrates the scroll sync solution from layout-test-1 with TellUrStori's architecture
//

import SwiftUI

struct SynchronizedTimelineView: View {
    let project: AudioProject?
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    @Binding var selectedTrackId: UUID?
    let horizontalZoom: Double
    let verticalZoom: Double
    let onAddTrack: () -> Void
    let onCreateProject: () -> Void
    let onOpenProject: () -> Void
    
    // Scroll synchronization model
    @State private var scrollSync = ScrollSyncModel()
    
    // Professional track header management
    @StateObject private var trackHeaderManager = TrackHeaderManager()
    
    // Dynamic sizing based on zoom
    private var trackHeight: CGFloat { 80 * CGFloat(verticalZoom) }
    private var pixelsPerSecond: CGFloat { 100 * CGFloat(horizontalZoom) }
    
    var body: some View {
        VStack(spacing: 0) {
            if let project = project {
                HStack(spacing: 0) {
                    // LEFT: Track Headers Column (vertical scrolling only)
                    VStack(spacing: 0) {
                        // Spacer to align with timeline ruler
                        Rectangle()
                            .fill(Color(NSColor.controlBackgroundColor))
                            .frame(height: scrollSync.rulerHeight)
                            .overlay(
                                Rectangle()
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1),
                                alignment: .bottom
                            )
                        
                        // Synchronized track headers
                        SynchronizedScrollView<AnyView>.trackHeaders(
                            contentSize: scrollSync.contentSize(
                                for: project,
                                horizontalZoom: horizontalZoom,
                                verticalZoom: verticalZoom
                            ),
                            normalizedY: $scrollSync.verticalScrollPosition,
                            isUpdatingY: { scrollSync.isUpdatingVertical },
                            onUserScrollY: { scrollSync.updateVerticalPosition($0) }
                        ) {
                            AnyView(trackHeadersContent)
                        }
                    }
                    .frame(width: scrollSync.trackHeaderWidth)
                    
                    // Vertical separator
                    Rectangle()
                        .fill(Color(NSColor.separatorColor))
                        .frame(width: 1)
                    
                    // RIGHT: Timeline Ruler + Tracks Area
                    VStack(spacing: 0) {
                        // Timeline ruler (horizontal scrolling only)
                        SynchronizedScrollView<AnyView>.timelineRuler(
                            contentSize: CGSize(
                                width: scrollSync.contentSize(
                                    for: project,
                                    horizontalZoom: horizontalZoom,
                                    verticalZoom: verticalZoom
                                ).width,
                                height: scrollSync.rulerHeight
                            ),
                            normalizedX: $scrollSync.horizontalScrollPosition,
                            isUpdatingX: { scrollSync.isUpdatingHorizontal },
                            onUserScrollX: { scrollSync.updateHorizontalPosition($0) }
                        ) {
                            AnyView(timelineRulerContent)
                        }
                        .frame(height: scrollSync.rulerHeight)
                        
                        // Horizontal separator
                        Rectangle()
                            .fill(Color(NSColor.separatorColor))
                            .frame(height: 1)
                        
                        // Tracks area (both axes - master scroll view)
                        SynchronizedScrollView<AnyView>.tracksArea(
                            contentSize: scrollSync.contentSize(
                                for: project,
                                horizontalZoom: horizontalZoom,
                                verticalZoom: verticalZoom
                            ),
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
                .onChange(of: scrollSync.verticalScrollPosition) { _, newY in
                    scrollSync.setVerticalPosition(newY)
                }
                .onChange(of: scrollSync.horizontalScrollPosition) { _, newX in
                    scrollSync.setHorizontalPosition(newX)
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
            trackHeaderManager.handleProjectUpdate()
        }
    }
    
    // MARK: - Content Views
    
    @ViewBuilder
    private var trackHeadersContent: some View {
        LazyVStack(spacing: 0) {
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
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    private var timelineRulerContent: some View {
        TimelineRuler(
            duration: project?.duration ?? 60.0,
            pixelsPerSecond: pixelsPerSecond,
            currentPosition: audioEngine.currentPosition.timeInterval
        )
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    @ViewBuilder
    private var tracksAreaContent: some View {
        ZStack(alignment: .topLeading) {
            // Background grid
            TimelineGrid(
                duration: project?.duration ?? 60.0,
                trackCount: project?.tracks.count ?? 0,
                pixelsPerSecond: pixelsPerSecond,
                trackHeight: trackHeight
            )
            
            // Track lanes with audio regions
            LazyVStack(spacing: 0) {
                if let project = project {
                    ForEach(project.tracks) { audioTrack in
                        TrackEditorLane(
                            track: getTrackHeaderModel(for: audioTrack.id),
                            audioTrack: audioTrack,
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
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
    }
    
    // MARK: - Helper Methods
    
    private func setupTrackHeaderManager() {
        trackHeaderManager.configure(audioEngine: audioEngine, projectManager: projectManager)
    }
    
    private func getTrackHeaderModel(for trackId: UUID) -> TrackHeaderModel {
        // Find the track header model by ID, or create a default one
        if let trackHeader = trackHeaderManager.tracks.first(where: { $0.id == trackId }) {
            return trackHeader
        } else {
            // Create a default track header model if not found
            return TrackHeaderModel(name: "Track", trackType: .audio, color: .blue, trackNumber: 1)
        }
    }
}

// MARK: - Timeline Components

struct TimelineRuler: View {
    let duration: TimeInterval
    let pixelsPerSecond: CGFloat
    let currentPosition: TimeInterval
    
    private var contentWidth: CGFloat {
        duration * pixelsPerSecond
    }
    
    var body: some View {
        Canvas { context, size in
            drawRuler(context: context, size: size)
        }
        .frame(width: contentWidth, height: 40)
        .overlay(
            // Playhead
            Rectangle()
                .fill(Color.red)
                .frame(width: 2)
                .offset(x: currentPosition * pixelsPerSecond)
                .animation(.linear(duration: 0.1), value: currentPosition),
            alignment: .leading
        )
    }
    
    private func drawRuler(context: GraphicsContext, size: CGSize) {
        // Draw background
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(Color(NSColor.controlBackgroundColor))
        )
        
        // Draw time markers
        let totalSeconds = Int(duration)
        for second in 0...totalSeconds {
            let x = CGFloat(second) * pixelsPerSecond
            let isMajorTick = second % 10 == 0
            let isMinorTick = second % 5 == 0
            
            if isMajorTick {
                // Major tick (every 10 seconds)
                drawTick(context: context, x: x, height: size.height * 0.8, color: .primary)
                drawTimeLabel(context: context, x: x, y: 4, time: second)
            } else if isMinorTick {
                // Minor tick (every 5 seconds)
                drawTick(context: context, x: x, height: size.height * 0.6, color: .secondary)
            }
        }
        
        // Draw bottom border
        let bottomPath = Path { path in
            path.move(to: CGPoint(x: 0, y: size.height - 1))
            path.addLine(to: CGPoint(x: size.width, y: size.height - 1))
        }
        context.stroke(bottomPath, with: .color(Color(NSColor.separatorColor)), lineWidth: 1)
    }
    
    private func drawTick(context: GraphicsContext, x: CGFloat, height: CGFloat, color: Color) {
        let path = Path { path in
            path.move(to: CGPoint(x: x, y: 40 - height))
            path.addLine(to: CGPoint(x: x, y: 40))
        }
        context.stroke(path, with: .color(color), lineWidth: 1)
    }
    
    private func drawTimeLabel(context: GraphicsContext, x: CGFloat, y: CGFloat, time: Int) {
        let minutes = time / 60
        let seconds = time % 60
        let timeString = String(format: "%d:%02d", minutes, seconds)
        
        let font = Font.system(size: 10, weight: .medium, design: .monospaced)
        
        context.draw(
            Text(timeString)
                .font(font)
                .foregroundColor(.primary),
            at: CGPoint(x: x + 4, y: y + 6),
            anchor: .topLeading
        )
    }
}

struct TimelineGrid: View {
    let duration: TimeInterval
    let trackCount: Int
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    
    private var contentWidth: CGFloat {
        duration * pixelsPerSecond
    }
    
    private var contentHeight: CGFloat {
        CGFloat(trackCount) * trackHeight
    }
    
    var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
        }
        .frame(width: contentWidth, height: contentHeight)
    }
    
    private func drawGrid(context: GraphicsContext, size: CGSize) {
        // Vertical grid lines (every 5 seconds)
        let totalSeconds = Int(duration)
        for second in stride(from: 0, through: totalSeconds, by: 5) {
            let x = CGFloat(second) * pixelsPerSecond
            let path = Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(.gray.opacity(0.4)), lineWidth: 0.5)
        }
        
        // Horizontal grid lines (track separators)
        for trackIndex in 0...trackCount {
            let y = CGFloat(trackIndex) * trackHeight
            let path = Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.gray.opacity(0.3)), lineWidth: 0.5)
        }
    }
}
