//
//  ProfessionalMasterChannelStrip.swift
//  Stori
//
//  Professional master channel strip with comprehensive metering
//

import SwiftUI

// MARK: - Professional Master Channel Strip
struct ProfessionalMasterChannelStrip: View {
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    let meterData: ChannelMeterData
    
    @State private var masterHiEQ: Float = 0.5
    @State private var masterMidEQ: Float = 0.5
    @State private var masterLoEQ: Float = 0.5
    @State private var showingLoudnessMeter = false
    @State private var masterVolumeBeforeDrag: Double = 0.8
    
    var body: some View {
        VStack(spacing: 0) {
            // Master Header
            masterHeader
            
            // Master EQ Section
            masterEQSection
            
            Spacer(minLength: 8)
            
            // Master Fader with Meters
            masterFaderSection
            
            // LUFS Loudness Display
            lufsSection
            
            // Master Controls
            masterControlsSection
            
            // Master Label
            masterLabel
        }
        .frame(width: 110)
        .background(masterBackground)
    }
    
    // MARK: - Master Header
    private var masterHeader: some View {
        VStack(spacing: 4) {
            // Master gradient strip
            LinearGradient(
                colors: [.orange, .red],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 4)
            
            // Master icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [.orange, .red.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                    .shadow(color: .orange.opacity(0.4), radius: 4, x: 0, y: 2)
                
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.vertical, 6)
        }
    }
    
    // MARK: - Master EQ Section
    private var masterEQSection: some View {
        VStack(spacing: 4) {
            // Section Header
            HStack {
                Text("MASTER EQ")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(MixerColors.sectionHeader)
                Spacer()
            }
            .padding(.horizontal, 6)
            
            // EQ Curve Display
            MiniEQDisplay(
                highEQ: (masterHiEQ - 0.5) * 24,
                midEQ: (masterMidEQ - 0.5) * 24,
                lowEQ: (masterLoEQ - 0.5) * 24,
                isEnabled: true,
                width: 90,
                height: 30
            )
            .padding(.horizontal, 6)
            
            // EQ Knobs
            HStack(spacing: 10) {
                VStack(spacing: 2) {
                    MasterEQKnob(
                        value: $masterLoEQ,
                        color: .blue
                    ) {
                        audioEngine.updateMasterLoEQ(masterLoEQ)
                    }
                    Text("Lo")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 2) {
                    MasterEQKnob(
                        value: $masterMidEQ,
                        color: .cyan
                    ) {
                        audioEngine.updateMasterMidEQ(masterMidEQ)
                    }
                    Text("Mid")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 2) {
                    MasterEQKnob(
                        value: $masterHiEQ,
                        color: .purple
                    ) {
                        audioEngine.updateMasterHiEQ(masterHiEQ)
                    }
                    Text("Hi")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(MixerColors.slotBackground)
        )
        .padding(.horizontal, 6)
    }
    
    // MARK: - Master Fader Section
    private var masterFaderSection: some View {
        VStack(spacing: 4) {
            // dB Display
            Text(masterVolumeDisplayText)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.orange)
                .frame(height: 16)
            
            // Fader with wide meters
            HStack(spacing: 3) {
                // Left meter
                MasterMeter(
                    level: meterData.leftLevel,
                    peak: meterData.peakLeft,
                    isClipping: meterData.isClipping,
                    height: 180
                )
                
                // Master Fader
                MasterFader(
                    value: Binding(
                        get: { Float(audioEngine.masterVolume) },
                        set: { audioEngine.updateMasterVolume($0) }
                    ),
                    height: 180,
                    onDragStart: { initialValue in
                        masterVolumeBeforeDrag = Double(initialValue)
                    },
                    onDragEnd: { finalValue in
                        // Register undo for master volume change
                        UndoService.shared.registerMasterVolumeChange(from: masterVolumeBeforeDrag, to: Double(finalValue), audioEngine: audioEngine)
                    }
                )
                
                // Right meter
                MasterMeter(
                    level: meterData.rightLevel,
                    peak: meterData.peakRight,
                    isClipping: meterData.isClipping,
                    height: 180
                )
            }
            .padding(.horizontal, 6)
            
            // -∞ label
            Text("-∞")
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.6))
        }
    }
    
    private var masterVolumeDisplayText: String {
        let volume = Float(audioEngine.masterVolume)
        if volume <= 0.001 {
            return "-∞ dB"
        } else {
            let dB = 20 * log10(volume)
            if dB >= -0.5 {
                return "0.0 dB"
            } else {
                return String(format: "%.1f dB", dB)
            }
        }
    }
    
    // MARK: - LUFS Section
    private var lufsSection: some View {
        VStack(spacing: 2) {
            // Section Header
            HStack {
                Text("LOUDNESS")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(MixerColors.sectionHeader)
                Spacer()
                
                // Toggle expanded view
                Button(action: { showingLoudnessMeter.toggle() }) {
                    Image(systemName: showingLoudnessMeter ? "chevron.up" : "chevron.down")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 6)
            
            if showingLoudnessMeter {
                // Expanded LUFS display
                VStack(spacing: 4) {
                    LUFSRow(label: "M", value: meterData.loudnessMomentary, color: .cyan)
                    LUFSRow(label: "S", value: meterData.loudnessShortTerm, color: .blue)
                    LUFSRow(label: "I", value: meterData.loudnessIntegrated, color: .green)
                    LUFSRow(label: "TP", value: meterData.truePeak, color: meterData.truePeak > -1 ? .red : .orange)
                }
                .padding(.horizontal, 6)
            } else {
                // Compact display - just momentary
                HStack(spacing: 4) {
                    Text(String(format: "%.1f", meterData.loudnessMomentary))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(loudnessColor(meterData.loudnessMomentary))
                    Text("LUFS")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.2))
                .padding(.horizontal, 4)
        )
    }
    
    private func loudnessColor(_ lufs: Float) -> Color {
        if lufs > -8 { return .red }
        if lufs > -14 { return .orange }
        if lufs > -20 { return .yellow }
        return .green
    }
    
    // MARK: - Master Controls
    private var masterControlsSection: some View {
        HStack(spacing: 8) {
            // Dim button (reduce output by -20dB)
            Button(action: { /* TODO: Implement dim */ }) {
                Text("DIM")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Dim Output (-20dB)")
            
            // Mono button
            Button(action: { /* TODO: Implement mono */ }) {
                Text("MONO")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Sum to Mono")
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Master Label
    private var masterLabel: some View {
        VStack(spacing: 2) {
            Text("Master")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.orange)
            
            Text("Stereo Out")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
    
    // MARK: - Background
    private var masterBackground: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(MixerColors.channelBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        LinearGradient(
                            colors: [.orange.opacity(0.5), .red.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2
                    )
            )
    }
}

// MARK: - Master EQ Knob
struct MasterEQKnob: View {
    @Binding var value: Float
    let color: Color
    let onChange: () -> Void
    
    @State private var isDragging = false
    @State private var lastDragValue: CGFloat = 0
    
    private var angle: Double {
        Double(value) * 270 - 135
    }
    
    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
            
            // Value arc
            Circle()
                .trim(from: 0.125, to: CGFloat(0.125 + value * 0.75))
                .stroke(color, lineWidth: 2)
                .rotationEffect(.degrees(90))
            
            // Knob body
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.4), Color(white: 0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 22, height: 22)
            
            // Indicator
            Rectangle()
                .fill(color)
                .frame(width: 2, height: 6)
                .offset(y: -7)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: 26, height: 26)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        lastDragValue = gesture.translation.height
                    }
                    
                    let delta = Float(lastDragValue - gesture.translation.height) * 0.005
                    let newValue = max(0, min(1, value + delta))
                    
                    if newValue != value {
                        value = newValue
                        onChange()
                    }
                    
                    lastDragValue = gesture.translation.height
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onTapGesture(count: 2) {
            value = 0.5  // Reset to center
            onChange()
        }
    }
}

// MARK: - Master Meter
struct MasterMeter: View {
    let level: Float
    let peak: Float
    let isClipping: Bool
    let height: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background with segment lines
                ZStack {
                    Rectangle()
                        .fill(Color.black.opacity(0.7))
                    
                    // Segment lines
                    ForEach(segmentPositions, id: \.self) { position in
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 1)
                            .offset(y: -geometry.size.height * CGFloat(position) + geometry.size.height / 2)
                    }
                }
                .frame(width: 8)
                .cornerRadius(2)
                
                // Level fill
                Rectangle()
                    .fill(masterMeterGradient)
                    .frame(width: 8, height: max(0, geometry.size.height * CGFloat(min(1.0, level))))
                    .cornerRadius(2)
                
                // Peak hold
                if peak > 0.01 {
                    Rectangle()
                        .fill(peakColor)
                        .frame(width: 8, height: 3)
                        .offset(y: -geometry.size.height * CGFloat(min(1.0, peak)) + 1.5)
                }
                
                // Clip indicator
                if isClipping {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 8, height: 6)
                        .offset(y: -geometry.size.height + 3)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 12, height: height)
    }
    
    private var segmentPositions: [Float] {
        [0.0, 0.25, 0.5, 0.75, 0.9, 1.0]
    }
    
    private var masterMeterGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: MixerColors.meterGreen, location: 0.0),
                .init(color: MixerColors.meterGreen, location: 0.5),
                .init(color: MixerColors.meterYellow, location: 0.7),
                .init(color: MixerColors.meterYellow, location: 0.85),
                .init(color: MixerColors.meterRed, location: 0.95),
                .init(color: MixerColors.meterPeak, location: 1.0)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
    
    private var peakColor: Color {
        if peak >= 1.0 { return MixerColors.meterPeak }
        if peak >= 0.9 { return MixerColors.meterRed }
        if peak >= 0.75 { return MixerColors.meterYellow }
        return MixerColors.meterGreen
    }
}

// MARK: - Master Fader
struct MasterFader: View {
    @Binding var value: Float
    let height: CGFloat
    var onDragStart: ((Float) -> Void)? = nil  // Called when drag starts with initial value
    var onDragEnd: ((Float) -> Void)? = nil    // Called when drag ends with final value
    
    @State private var isDragging = false
    @State private var valueAtDragStart: Float = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Fader track
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 10)
                
                // Track fill
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.orange.opacity(0.4), .orange.opacity(0.1)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 10, height: geometry.size.height * CGFloat(value))
                
                // Fader cap
                masterFaderCap
                    .offset(y: -geometry.size.height * CGFloat(value) + 16)
            }
            .frame(maxWidth: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            valueAtDragStart = value
                            onDragStart?(value)
                        }
                        let newValue = 1 - Float(gesture.location.y / geometry.size.height)
                        value = max(0, min(1, newValue))
                    }
                    .onEnded { _ in
                        isDragging = false
                        // Only call onDragEnd if value actually changed
                        if abs(value - valueAtDragStart) > 0.001 {
                            onDragEnd?(value)
                        }
                    }
            )
        }
        .frame(width: 32, height: height)
    }
    
    private var masterFaderCap: some View {
        ZStack {
            // Cap body with orange accent
            RoundedRectangle(cornerRadius: 5)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: isDragging ? 0.95 : 0.85),
                            Color(white: isDragging ? 0.75 : 0.65)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 28, height: 32)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(Color.orange.opacity(0.6), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: isDragging ? 4 : 2, x: 0, y: 2)
            
            // Grip lines
            VStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 16, height: 1)
                }
            }
            
            // Orange indicator line
            Rectangle()
                .fill(Color.orange)
                .frame(width: 20, height: 2)
        }
    }
}

// MARK: - LUFS Row Display
struct LUFSRow: View {
    let label: String
    let value: Float
    let color: Color
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary)
                .frame(width: 16, alignment: .trailing)
            
            // Mini bar meter
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.black.opacity(0.5))
                    
                    // Level bar (mapped from -60 to 0 LUFS)
                    let normalizedValue = max(0, min(1, (value + 60) / 60))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.7))
                        .frame(width: geometry.size.width * CGFloat(normalizedValue))
                }
            }
            .frame(height: 8)
            
            // Value
            Text(String(format: "%.1f", value))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(color)
                .frame(width: 32, alignment: .trailing)
        }
    }
}
