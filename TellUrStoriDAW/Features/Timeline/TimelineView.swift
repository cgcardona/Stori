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
                    projectManager.addTrack()
                }
                .frame(height: 40)
                
            } else {
                EmptyTimelineView {
                    projectManager.createNewProject(name: "New Project")
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 400)
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
    
    var body: some View {
        // Simplified waveform visualization
        // In a real implementation, you'd analyze the audio file and draw actual waveform data
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width
                let height = geometry.size.height
                let midY = height / 2
                
                // Generate pseudo-waveform
                for x in stride(from: 0, to: width, by: 2) {
                    let amplitude = sin(x * 0.1) * 0.3 + cos(x * 0.05) * 0.2
                    let y1 = midY - (amplitude * midY)
                    let y2 = midY + (amplitude * midY)
                    
                    path.move(to: CGPoint(x: x, y: y1))
                    path.addLine(to: CGPoint(x: x, y: y2))
                }
            }
            .stroke(Color.white.opacity(0.6), lineWidth: 1)
        }
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
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Project Open")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Create a new project to start making music")
                .foregroundColor(.secondary)
            
            Button("Create New Project", action: onCreateProject)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        selectedTrackId: .constant(nil)
    )
    .frame(width: 1000, height: 600)
}
