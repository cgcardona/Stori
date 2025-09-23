//
//  DAWTimelineView.swift
//  TellUrStoriDAW
//
//  Professional DAW timeline view with industry-standard track layout and controls
//
// TODO: DEAD CODE - This file can be deleted in future dead code cleanup cycle
// This timeline implementation has been replaced by IntegratedTimelineView.swift
// Keeping for now to avoid disruption, but no longer used in the main app

import SwiftUI

struct DAWTimelineView: View {
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    @Binding var selectedTrackId: UUID?
    
    // Get project directly from audioEngine for real-time updates
    private var project: AudioProject? {
        audioEngine.currentProject
    }
    let horizontalZoom: Double
    let verticalZoom: Double
    let onAddTrack: () -> Void
    let onCreateProject: () -> Void
    let onOpenProject: () -> Void
    
    // MARK: - Constants
    private let trackHeaderWidth: CGFloat = 300
    private let rulerHeight: CGFloat = 30
    
    // Dynamic sizing based on zoom
    private var trackHeight: CGFloat { 60 * CGFloat(verticalZoom) }
    private var pixelsPerSecond: CGFloat { 100 * CGFloat(horizontalZoom) }
    
    var body: some View {
        VStack(spacing: 0) {
            if let project = project {
                // Timeline Ruler
                DAWTimelineRuler(
                    project: project,
                    audioEngine: audioEngine,
                    pixelsPerSecond: pixelsPerSecond,
                    trackHeaderWidth: trackHeaderWidth
                )
                .frame(height: rulerHeight)
                
                // Tracks Area
                ScrollView([.horizontal, .vertical]) {
                    HStack(spacing: 0) {
                        // Track Headers Column
                        VStack(spacing: 0) {
                            ForEach(Array(project.tracks.enumerated()), id: \.element.id) { index, track in
                                DAWTrackHeader(
                                    track: track,
                                    audioEngine: audioEngine,
                                    projectManager: projectManager,
                                    trackNumber: index + 1,
                                    isSelected: selectedTrackId == track.id,
                                    onSelect: { selectedTrackId = track.id },
                                    onDelete: { 
                                        projectManager.removeTrack(track.id)
                                        if selectedTrackId == track.id {
                                            selectedTrackId = nil
                                        }
                                    }
                                )
                                .frame(height: trackHeight)
                            }
                            
                            // Add Track Button
                            DAWAddTrackButton {
                                onAddTrack()
                            }
                            .frame(height: 40)
                        }
                        .frame(width: trackHeaderWidth)
                        .background(Color(.controlBackgroundColor))
                        
                        // Track Content Area
                        VStack(spacing: 0) {
                            ForEach(project.tracks) { track in
                                DAWTrackLane(
                                    track: track,
                                    audioEngine: audioEngine,
                                    isSelected: selectedTrackId == track.id,
                                    pixelsPerSecond: pixelsPerSecond,
                                    trackHeight: trackHeight,
                                    onSelect: { selectedTrackId = track.id }
                                )
                                .frame(height: trackHeight)
                            }
                            
                            // Spacer for add track button alignment
                            Color.clear
                                .frame(height: 40)
                        }
                        .frame(minWidth: max(1000, CGFloat(project.duration) * pixelsPerSecond))
                        .background(DAWTrackBackground())
                    }
                }
                .coordinateSpace(name: "timeline")
                
            } else {
                EmptyTimelineView(
                    onCreateProject: onCreateProject, 
                    onOpenProject: onOpenProject, 
                    projectManager: projectManager
                )
            }
        }
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - DAW Timeline Ruler
struct DAWTimelineRuler: View {
    let project: AudioProject
    @ObservedObject var audioEngine: AudioEngine
    let pixelsPerSecond: CGFloat
    let trackHeaderWidth: CGFloat
    
    var body: some View {
        HStack(spacing: 0) {
            // Ruler header space
            Rectangle()
                .fill(Color(.controlBackgroundColor))
                .frame(width: trackHeaderWidth)
                .overlay(
                    HStack {
                        Text("TRACKS")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                )
            
            // Time ruler
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    Rectangle()
                        .fill(Color(.controlBackgroundColor))
                    
                    // Time markers
                    Canvas { context, size in
                        drawTimeMarkers(context: context, size: size, geometry: geometry)
                    }
                    
                    // Playhead
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 2)
                        .offset(x: CGFloat(audioEngine.currentPosition.timeInterval) * pixelsPerSecond)
                        .animation(.linear(duration: 0.1), value: audioEngine.currentPosition.timeInterval)
                }
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .bottom
        )
    }
    
    private func drawTimeMarkers(context: GraphicsContext, size: CGSize, geometry: GeometryProxy) {
        let totalDuration = max(project.duration, 60.0) // Minimum 60 seconds
        let _ = totalDuration * Double(pixelsPerSecond) // Total width calculation
        
        // Major markers every 4 beats
        let beatsPerSecond = project.tempo / 60.0
        let secondsPerMajorMarker = 4.0 / beatsPerSecond
        let _ = secondsPerMajorMarker * Double(pixelsPerSecond) // Pixels per major marker
        
        var time: Double = 0
        var markerIndex = 0
        
        while time <= totalDuration {
            let x = time * Double(pixelsPerSecond)
            
            if x <= Double(size.width) {
                // Major marker line
                let startPoint = CGPoint(x: x, y: 0)
                let endPoint = CGPoint(x: x, y: Double(size.height))
                
                context.stroke(
                    Path { path in
                        path.move(to: startPoint)
                        path.addLine(to: endPoint)
                    },
                    with: .color(.primary.opacity(0.3)),
                    lineWidth: 1
                )
                
                // Time label
                let minutes = Int(time) / 60
                let seconds = Int(time) % 60
                let timeString = String(format: "%d:%02d", minutes, seconds)
                
                context.draw(
                    Text(timeString)
                        .font(.caption)
                        .foregroundColor(.secondary),
                    at: CGPoint(x: x + 4, y: 8)
                )
            }
            
            markerIndex += 1
            time = Double(markerIndex) * secondsPerMajorMarker
        }
    }
}

// MARK: - DAW Track Lane
struct DAWTrackLane: View {
    let track: AudioTrack
    @ObservedObject var audioEngine: AudioEngine
    let isSelected: Bool
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    let onSelect: () -> Void
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Track background
            Rectangle()
                .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
                .overlay(
                    Rectangle()
                        .stroke(isSelected ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 1)
                )
            
            // Audio regions
            ForEach(track.regions) { region in
                DAWAudioRegion(
                    region: region,
                    track: track,
                    pixelsPerSecond: pixelsPerSecond,
                    trackHeight: trackHeight
                )
                .offset(x: CGFloat(region.startTime) * pixelsPerSecond)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
    }
}

// MARK: - DAW Audio Region
struct DAWAudioRegion: View {
    let region: AudioRegion
    let track: AudioTrack
    let pixelsPerSecond: CGFloat
    let trackHeight: CGFloat
    
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    
    var regionWidth: CGFloat {
        CGFloat(region.duration) * pixelsPerSecond
    }
    
    var body: some View {
        ZStack {
            // Region background
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: track.color.rawValue),
                            Color(hex: track.color.rawValue).opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color(hex: track.color.rawValue).opacity(0.5), lineWidth: 1)
                )
            
            // Waveform visualization
            let audioFile = region.audioFile
                DAWWaveformView(
                    audioFile: audioFile,
                    color: Color.white.opacity(0.8)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .padding(2)
            
            // Region name
            VStack {
                HStack {
                    Text(region.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1)
                    Spacer()
                }
                Spacer()
            }
            .padding(6)
        }
        .frame(width: regionWidth, height: trackHeight - 4)
        .offset(dragOffset)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isDragging ? 0.3 : 0.1), radius: isDragging ? 8 : 2)
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation
                    isDragging = true
                }
                .onEnded { value in
                    // Handle region repositioning
                    handleRegionDrop(offset: value.translation)
                    dragOffset = .zero
                    isDragging = false
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
    }
    
    private func handleRegionDrop(offset: CGSize) {
        // Calculate new position based on drag offset
        let newStartTime = max(0, region.startTime + Double(offset.width / pixelsPerSecond))
        
        // TODO: Update region position in project
        print("🎵 Moving region '\(region.displayName)' to \(newStartTime)s")
    }
}

// MARK: - DAW Waveform View
struct DAWWaveformView: View {
    let audioFile: AudioFile
    let color: Color
    
    var body: some View {
        // Placeholder waveform - in a real implementation, this would analyze the audio file
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let midY = height / 2
                
                // Generate a simple waveform pattern
                for x in stride(from: 0, to: width, by: 2) {
                    let amplitude = sin(x * 0.1) * (height * 0.3) * Double.random(in: 0.3...1.0)
                    path.move(to: CGPoint(x: x, y: midY - amplitude))
                    path.addLine(to: CGPoint(x: x, y: midY + amplitude))
                }
            }
            .stroke(color, lineWidth: 1)
        }
    }
}

// MARK: - DAW Track Background
struct DAWTrackBackground: View {
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Draw grid lines
                let gridSpacing: CGFloat = 50
                
                // Vertical grid lines
                for x in stride(from: 0, to: size.width, by: gridSpacing) {
                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: size.height))
                        },
                        with: .color(.gray.opacity(0.1)),
                        lineWidth: 1
                    )
                }
                
                // Horizontal grid lines (track separators)
                let trackHeight: CGFloat = 60
                for y in stride(from: trackHeight, to: size.height, by: trackHeight) {
                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: y))
                            path.addLine(to: CGPoint(x: size.width, y: y))
                        },
                        with: .color(.gray.opacity(0.2)),
                        lineWidth: 1
                    )
                }
            }
        }
        .background(Color(.textBackgroundColor))
    }
}

// MARK: - DAW Add Track Button
struct DAWAddTrackButton: View {
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                Text("Add Track")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}
