//
//  MixerView.swift
//  TellUrStoriDAW
//
//  Mixer interface for track mixing controls
//

import SwiftUI

struct MixerView: View {
    let project: AudioProject?
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    @Binding var selectedTrackId: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Mixer header
            HStack {
                Text("Mixer")
                    .font(.headline)
                    .padding(.leading)
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.plain)
                .padding(.trailing)
            }
            .frame(height: 40)
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // Mixer channels
            ScrollView {
                VStack(spacing: 8) {
                    if let project = project {
                        ForEach(project.tracks) { track in
                            MixerChannelView(
                                track: track,
                                audioEngine: audioEngine,
                                projectManager: projectManager,
                                isSelected: selectedTrackId == track.id,
                                onSelect: { selectedTrackId = track.id }
                            )
                        }
                        
                        // Master channel
                        MasterChannelView(audioEngine: audioEngine)
                    }
                }
                .padding()
            }
        }
        .background(Color(.windowBackgroundColor))
    }
}

// MARK: - Mixer Channel View
struct MixerChannelView: View {
    let track: AudioTrack
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var projectManager: ProjectManager
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var trackLevel: Float = 0.0
    @State private var levelTimer: Timer?
    
    init(track: AudioTrack, audioEngine: AudioEngine, projectManager: ProjectManager, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.track = track
        self.audioEngine = audioEngine
        self.projectManager = projectManager
        self.isSelected = isSelected
        self.onSelect = onSelect
    }
    
    var body: some View {
        VStack(spacing: 12) {
            trackHeaderView
            eqAndPanControls
            volumeAndMuteControls
            levelMeterView
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        )
        .onTapGesture {
            onSelect()
        }
        .onAppear {
            startLevelMonitoring()
        }
        .onDisappear {
            stopLevelMonitoring()
        }
    }
    
    // MARK: - Subviews
    
    private var trackHeaderView: some View {
        HStack {
            Circle()
                .fill(track.color.color)
                .frame(width: 8, height: 8)
            
            Text(track.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(1)
            
            Spacer()
        }
    }
    
    private var eqAndPanControls: some View {
        VStack(spacing: 8) {
            Text("EQ & PAN")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                highEQKnob
                midEQKnob
                lowEQKnob
                panKnob
            }
        }
    }
    
    private var highEQKnob: some View {
        VStack(spacing: 2) {
            Text("HI")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            KnobView(value: .constant(track.mixerSettings.highEQ), range: -12...12, sensitivity: 0.03) { value in
                var updatedTrack = track
                updatedTrack.mixerSettings.highEQ = value
                projectManager.updateTrack(updatedTrack)
                audioEngine.updateTrackEQ(trackId: track.id, highEQ: value, midEQ: track.mixerSettings.midEQ, lowEQ: track.mixerSettings.lowEQ)
            }
            .frame(width: 32, height: 32)
        }
    }
    
    private var midEQKnob: some View {
        VStack(spacing: 2) {
            Text("MID")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            KnobView(value: .constant(track.mixerSettings.midEQ), range: -12...12, sensitivity: 0.03) { value in
                var updatedTrack = track
                updatedTrack.mixerSettings.midEQ = value
                projectManager.updateTrack(updatedTrack)
                audioEngine.updateTrackEQ(trackId: track.id, highEQ: track.mixerSettings.highEQ, midEQ: value, lowEQ: track.mixerSettings.lowEQ)
            }
            .frame(width: 32, height: 32)
        }
    }
    
    private var lowEQKnob: some View {
        VStack(spacing: 2) {
            Text("LO")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            KnobView(value: .constant(track.mixerSettings.lowEQ), range: -12...12, sensitivity: 0.03) { value in
                var updatedTrack = track
                updatedTrack.mixerSettings.lowEQ = value
                projectManager.updateTrack(updatedTrack)
                audioEngine.updateTrackEQ(trackId: track.id, highEQ: track.mixerSettings.highEQ, midEQ: track.mixerSettings.midEQ, lowEQ: value)
            }
            .frame(width: 32, height: 32)
        }
    }
    
    private var panKnob: some View {
        VStack(spacing: 2) {
            Text("PAN")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            KnobView(value: .constant(track.mixerSettings.pan), range: -1...1, sensitivity: 0.02) { value in
                var updatedTrack = track
                updatedTrack.mixerSettings.pan = value
                projectManager.updateTrack(updatedTrack)
                audioEngine.updateTrackPan(trackId: track.id, pan: value)
            }
            .frame(width: 32, height: 32)
            
            Text(panDisplayText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var volumeAndMuteControls: some View {
        VStack(spacing: 8) {
            Divider()
            
            volumeSlider
            controlButtons
        }
    }
    
    private var volumeSlider: some View {
        VStack(spacing: 6) {
            Text("VOLUME")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            HSliderView(value: .constant(track.mixerSettings.volume), range: 0...1) { value in
                var updatedTrack = track
                updatedTrack.mixerSettings.volume = value
                projectManager.updateTrack(updatedTrack)
                audioEngine.updateTrackVolume(trackId: track.id, volume: value)
            }
            .frame(height: 20)
            
            Text("\(Int(track.mixerSettings.volume * 100))%")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var controlButtons: some View {
        HStack(spacing: 8) {
            muteButton
            soloButton
            recordButton
        }
    }
    
    private var muteButton: some View {
        Button(action: {
            var updatedTrack = track
            updatedTrack.mixerSettings.isMuted.toggle()
            projectManager.updateTrack(updatedTrack)
            audioEngine.updateTrackMute(trackId: track.id, isMuted: updatedTrack.mixerSettings.isMuted)
        }) {
            Text("M")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(track.mixerSettings.isMuted ? Color.orange : Color.gray.opacity(0.3))
                .foregroundColor(track.mixerSettings.isMuted ? .white : .primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private var soloButton: some View {
        Button(action: {
            var updatedTrack = track
            updatedTrack.mixerSettings.isSolo.toggle()
            projectManager.updateTrack(updatedTrack)
            audioEngine.updateTrackSolo(trackId: track.id, isSolo: updatedTrack.mixerSettings.isSolo)
        }) {
            Text("S")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(track.mixerSettings.isSolo ? Color.yellow : Color.gray.opacity(0.3))
                .foregroundColor(track.mixerSettings.isSolo ? .black : .primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private var recordButton: some View {
        Button(action: {
            var updatedTrack = track
            updatedTrack.mixerSettings.isRecordEnabled.toggle()
            projectManager.updateTrack(updatedTrack)
            audioEngine.updateTrackRecordEnabled(trackId: track.id, isRecordEnabled: updatedTrack.mixerSettings.isRecordEnabled)
        }) {
            Text("R")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(track.mixerSettings.isRecordEnabled ? Color.red : Color.gray.opacity(0.3))
                .foregroundColor(track.mixerSettings.isRecordEnabled ? .white : .primary)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }
    
    private var levelMeterView: some View {
        HorizontalLevelMeterView(level: trackLevel)
            .frame(height: 8)
    }
    
    private var panDisplayText: String {
        let pan = track.mixerSettings.pan
        if abs(pan) < 0.05 {
            return "C"
        } else if pan > 0 {
            return "R\(Int(pan * 100))"
        } else {
            return "L\(Int(abs(pan) * 100))"
        }
    }
    
    private func startLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            let levels = audioEngine.getTrackLevels()
            if let level = levels[track.id] {
                trackLevel = level.current
            }
        }
    }
    
    private func stopLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}

// MARK: - Master Channel View
struct MasterChannelView: View {
    @ObservedObject var audioEngine: AudioEngine
    @State private var masterVolume: Float = 0.8
    @State private var masterLevel: Float = 0.0
    @State private var levelTimer: Timer?
    
    var body: some View {
        VStack(spacing: 12) {
            // Master label
            Text("MASTER")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.accentColor)
            
            Divider()
            
            // Master Volume Slider (Horizontal)
            VStack(spacing: 6) {
                Text("VOLUME")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                HSliderView(value: $masterVolume, range: 0...1) { value in
                    audioEngine.updateMasterVolume(value)
                }
                .frame(height: 20)
                
                Text("\(Int(masterVolume * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Master Level Meters (Stereo - Horizontal)
            VStack(spacing: 4) {
                Text("LEVELS")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 2) {
                    HorizontalLevelMeterView(level: masterLevel)
                        .frame(height: 6)
                    HorizontalLevelMeterView(level: masterLevel * 0.9) // Slightly different for stereo effect
                        .frame(height: 6)
                }
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor, lineWidth: 1)
        )
        .onAppear {
            // Initialize master volume from audio engine
            masterVolume = audioEngine.getMasterVolume()
            startMasterLevelMonitoring()
        }
        .onDisappear {
            stopMasterLevelMonitoring()
        }
    }
    
    private func startMasterLevelMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            // Get actual master bus level (RMS of active tracks)
            let masterLevelData = audioEngine.getMasterLevel()
            masterLevel = masterLevelData.current
        }
    }
    
    private func stopMasterLevelMonitoring() {
        levelTimer?.invalidate()
        levelTimer = nil
    }
}

// MARK: - Knob View
struct KnobView: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let sensitivity: Float
    let onChange: (Float) -> Void
    
    @State private var isDragging = false
    @State private var lastDragValue: CGFloat = 0
    
    init(value: Binding<Float>, range: ClosedRange<Float>, sensitivity: Float = 0.01, onChange: @escaping (Float) -> Void) {
        self._value = value
        self.range = range
        self.sensitivity = sensitivity
        self.onChange = onChange
    }
    
    private var normalizedValue: Float {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
    
    private var angle: Double {
        Double(normalizedValue) * 270 - 135 // -135° to +135°
    }
    
    var body: some View {
        ZStack {
            // Knob background
            Circle()
                .fill(Color(.controlBackgroundColor))
                .overlay(
                    Circle()
                        .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                )
            
            // Knob indicator
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 2, height: 8)
                .offset(y: -12)
                .rotationEffect(.degrees(angle))
            
            // Center dot
            Circle()
                .fill(Color.primary)
                .frame(width: 4, height: 4)
        }
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        lastDragValue = gesture.translation.height
                    }
                    
                    let delta = Float(lastDragValue - gesture.translation.height) * sensitivity
                    let newValue = max(range.lowerBound, min(range.upperBound, value + delta))
                    
                    if newValue != value {
                        value = newValue
                        onChange(newValue)
                    }
                    
                    lastDragValue = gesture.translation.height
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}

// MARK: - Vertical Slider View
struct VSliderView: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let onChange: (Float) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Track
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 4)
                
                // Fill
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 4, height: geometry.size.height * CGFloat(normalizedValue))
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .offset(y: -geometry.size.height * CGFloat(normalizedValue) + 8)
            }
            .frame(maxWidth: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = 1 - Float(gesture.location.y / geometry.size.height)
                        let clampedValue = max(range.lowerBound, min(range.upperBound, 
                            range.lowerBound + newValue * (range.upperBound - range.lowerBound)))
                        
                        if clampedValue != value {
                            value = clampedValue
                            onChange(clampedValue)
                        }
                    }
            )
        }
    }
    
    private var normalizedValue: Float {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

// MARK: - Horizontal Slider View
struct HSliderView: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let onChange: (Float) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)
                    .cornerRadius(2)
                
                // Fill
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * CGFloat(normalizedValue), height: 4)
                    .cornerRadius(2)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .offset(x: geometry.size.width * CGFloat(normalizedValue) - 8)
            }
            .frame(maxHeight: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = Float(gesture.location.x / geometry.size.width)
                        let clampedValue = max(range.lowerBound, min(range.upperBound, 
                            range.lowerBound + newValue * (range.upperBound - range.lowerBound)))
                        
                        if clampedValue != value {
                            value = clampedValue
                            onChange(clampedValue)
                        }
                    }
            )
        }
    }
    
    private var normalizedValue: Float {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

// MARK: - Horizontal Level Meter View
struct HorizontalLevelMeterView: View {
    let level: Float
    
    private let segments = 20
    
    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<segments, id: \.self) { index in
                let segmentLevel = Float(index + 1) / Float(segments)
                // Conservative level scaling for proper dynamic range
                // RMS values are typically very small (0.001-0.1), so we need gentle amplification
                let scaledLevel = level * 8.0 // Conservative 8x amplification
                let normalizedLevel = min(1.0, scaledLevel)
                let isActive = normalizedLevel >= segmentLevel
                
                Rectangle()
                    .fill(segmentColor(for: segmentLevel, isActive: isActive))
                    .frame(width: 2)
            }
        }
    }
    
    private func segmentColor(for segmentLevel: Float, isActive: Bool) -> Color {
        if !isActive {
            return Color.gray.opacity(0.3)
        }
        
        // More realistic level meter colors
        if segmentLevel > 0.9 {
            return .red      // Only the top 2 segments are red (clipping zone)
        } else if segmentLevel > 0.75 {
            return .yellow   // Yellow for loud but safe levels
        } else {
            return .green    // Green for normal operating levels
        }
    }
}

// MARK: - Level Meter View (Vertical - for Master)
struct LevelMeterView: View {
    let level: Float
    
    private let segments = 20
    
    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<segments, id: \.self) { index in
                let segmentLevel = Float(segments - index) / Float(segments)
                // Conservative level scaling for proper dynamic range
                // RMS values are typically very small (0.001-0.1), so we need gentle amplification
                let scaledLevel = level * 8.0 // Conservative 8x amplification
                let normalizedLevel = min(1.0, scaledLevel)
                let isActive = normalizedLevel >= segmentLevel
                
                Rectangle()
                    .fill(segmentColor(for: segmentLevel, isActive: isActive))
                    .frame(height: 2)
            }
        }
    }
    
    private func segmentColor(for segmentLevel: Float, isActive: Bool) -> Color {
        if !isActive {
            return Color.gray.opacity(0.3)
        }
        
        // More realistic level meter colors
        if segmentLevel > 0.9 {
            return .red      // Only the top 2 segments are red (clipping zone)
        } else if segmentLevel > 0.75 {
            return .yellow   // Yellow for loud but safe levels
        } else {
            return .green    // Green for normal operating levels
        }
    }
}
