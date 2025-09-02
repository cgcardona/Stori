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
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var volume: Float
    @State private var pan: Float
    @State private var highEQ: Float
    @State private var midEQ: Float
    @State private var lowEQ: Float
    @State private var isMuted: Bool
    @State private var isSolo: Bool
    @State private var isRecordEnabled: Bool
    @State private var trackLevel: Float = 0.0
    @State private var levelTimer: Timer?
    
    init(track: AudioTrack, audioEngine: AudioEngine, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.track = track
        self.audioEngine = audioEngine
        self.isSelected = isSelected
        self.onSelect = onSelect
        
        // Initialize state with track's mixer settings
        self._volume = State(initialValue: track.mixerSettings.volume)
        self._pan = State(initialValue: track.mixerSettings.pan)
        self._highEQ = State(initialValue: track.mixerSettings.highEQ)
        self._midEQ = State(initialValue: track.mixerSettings.midEQ)
        self._lowEQ = State(initialValue: track.mixerSettings.lowEQ)
        self._isMuted = State(initialValue: track.mixerSettings.isMuted)
        self._isSolo = State(initialValue: track.mixerSettings.isSolo)
        self._isRecordEnabled = State(initialValue: track.isRecordEnabled)
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Track name and color
            HStack {
                Circle()
                    .fill(Color(hex: track.colorHex))
                    .frame(width: 8, height: 8)
                
                Text(track.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Spacer()
            }
            
            // EQ Section
            VStack(spacing: 8) {
                Text("EQ")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // High EQ
                VStack(spacing: 2) {
                    Text("HI")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    KnobView(value: $highEQ, range: -12...12) { value in
                        print("🎛️ High EQ changed to: \(value)")
                        audioEngine.updateTrackEQ(trackId: track.id, highEQ: value, midEQ: midEQ, lowEQ: lowEQ)
                    }
                    .frame(width: 40, height: 40)
                }
                
                // Mid EQ
                VStack(spacing: 2) {
                    Text("MID")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    KnobView(value: $midEQ, range: -12...12) { value in
                        print("🎛️ Mid EQ changed to: \(value)")
                        audioEngine.updateTrackEQ(trackId: track.id, highEQ: highEQ, midEQ: value, lowEQ: lowEQ)
                    }
                    .frame(width: 40, height: 40)
                }
                
                // Low EQ
                VStack(spacing: 2) {
                    Text("LO")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    KnobView(value: $lowEQ, range: -12...12) { value in
                        print("🎛️ Low EQ changed to: \(value)")
                        audioEngine.updateTrackEQ(trackId: track.id, highEQ: highEQ, midEQ: midEQ, lowEQ: value)
                    }
                    .frame(width: 40, height: 40)
                }
            }
            
            Divider()
            
            // Pan Control
            VStack(spacing: 4) {
                Text("PAN")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                KnobView(value: $pan, range: -1...1) { value in
                    audioEngine.updateTrackPan(trackId: track.id, pan: value)
                }
                .frame(width: 40, height: 40)
                
                Text(panDisplayText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Volume Fader
            VStack(spacing: 8) {
                Text("VOLUME")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                VSliderView(value: $volume, range: 0...1) { value in
                    audioEngine.updateTrackVolume(trackId: track.id, volume: value)
                }
                .frame(width: 30, height: 120)
                
                Text("\(Int(volume * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Control Buttons
            HStack(spacing: 8) {
                // Mute
                Button(action: {
                    isMuted.toggle()
                    audioEngine.updateTrackMute(trackId: track.id, isMuted: isMuted)
                }) {
                    Text("M")
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(width: 24, height: 24)
                        .background(isMuted ? Color.orange : Color.gray.opacity(0.3))
                        .foregroundColor(isMuted ? .white : .primary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                // Solo
                Button(action: {
                    isSolo.toggle()
                    audioEngine.updateTrackSolo(trackId: track.id, isSolo: isSolo)
                }) {
                    Text("S")
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(width: 24, height: 24)
                        .background(isSolo ? Color.yellow : Color.gray.opacity(0.3))
                        .foregroundColor(isSolo ? .black : .primary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
                
                // Record
                Button(action: {
                    isRecordEnabled.toggle()
                    audioEngine.updateTrackRecordEnabled(trackId: track.id, isRecordEnabled: isRecordEnabled)
                }) {
                    Text("R")
                        .font(.caption)
                        .fontWeight(.bold)
                        .frame(width: 24, height: 24)
                        .background(isRecordEnabled ? Color.red : Color.gray.opacity(0.3))
                        .foregroundColor(isRecordEnabled ? .white : .primary)
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
            
            // Level Meter
            LevelMeterView(level: trackLevel)
                .frame(width: 8, height: 60)
        }
        .padding(12)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color(.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onTapGesture {
            onSelect()
        }
        .onAppear {
            // Start level monitoring
            startLevelMonitoring()
        }
        .onDisappear {
            // Stop level monitoring
            stopLevelMonitoring()
        }
    }
    
    private var panDisplayText: String {
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
            
            // Master Volume Fader
            VStack(spacing: 8) {
                Text("VOLUME")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                VSliderView(value: $masterVolume, range: 0...1) { value in
                    audioEngine.updateMasterVolume(value)
                }
                .frame(width: 40, height: 120)
                
                Text("\(Int(masterVolume * 100))%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Master Level Meters (Stereo)
            HStack(spacing: 4) {
                LevelMeterView(level: masterLevel)
                    .frame(width: 8, height: 80)
                LevelMeterView(level: masterLevel * 0.9) // Slightly different for stereo effect
                    .frame(width: 8, height: 80)
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
            // Calculate average level from all tracks for master level
            let levels = audioEngine.getTrackLevels()
            let averageLevel = levels.values.map { $0.current }.reduce(0, +) / Float(max(levels.count, 1))
            masterLevel = averageLevel
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
    let onChange: (Float) -> Void
    
    @State private var isDragging = false
    @State private var lastDragValue: CGFloat = 0
    
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
                    
                    let delta = Float(lastDragValue - gesture.translation.height) * 0.01
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

// MARK: - Level Meter View
struct LevelMeterView: View {
    let level: Float
    
    private let segments = 20
    
    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<segments, id: \.self) { index in
                let segmentLevel = Float(segments - index) / Float(segments)
                let isActive = level >= segmentLevel
                
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
        
        if segmentLevel > 0.8 {
            return .red
        } else if segmentLevel > 0.6 {
            return .yellow
        } else {
            return .green
        }
    }
}
