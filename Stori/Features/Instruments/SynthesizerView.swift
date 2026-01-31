//
//  SynthesizerView.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  Professional synthesizer interface with oscillators, filter, envelope, and LFO.
//  Features preset browser, parameter controls, and on-screen keyboard.
//

import SwiftUI

// MARK: - SynthesizerView

/// Main synthesizer interface for virtual instrument control.
struct SynthesizerView: View {
    let engine: SynthEngine
    @State private var showPresetBrowser = false
    @State private var activeKey: UInt8? = nil
    
    // Local state for UI bindings
    @State private var presetCopy: SynthPreset = .default
    
    // Color theme
    private let accentGradient = LinearGradient(
        colors: [.indigo, .purple, .pink],
        startPoint: .leading,
        endPoint: .trailing
    )
    
    var body: some View {
        VStack(spacing: 0) {
            // Main parameter sections
            HStack(spacing: 16) {
                // Left column: Oscillators + Filter
                VStack(spacing: 12) {
                    oscillatorSection
                    filterSection
                }
                .frame(maxWidth: .infinity)
                
                // Center: Large Envelope
                envelopeSection
                    .frame(width: 320)
                
                // Right column: LFO + Master
                VStack(spacing: 12) {
                    lfoSection
                    masterSection
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
            
            // On-screen keyboard for testing
            MiniKeyboardView(
                activeKey: $activeKey,
                onNoteOn: { pitch in
                    engine.noteOn(pitch: pitch, velocity: 100)
                    activeKey = pitch
                },
                onNoteOff: { pitch in
                    engine.noteOff(pitch: pitch)
                    if activeKey == pitch { activeKey = nil }
                }
            )
            .frame(height: 70)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showPresetBrowser) {
            PresetBrowserView(
                currentPreset: presetCopy,
                onSelect: { preset in
                    presetCopy = preset
                    engine.loadPreset(preset)
                    showPresetBrowser = false
                }
            )
        }
        .onAppear {
            presetCopy = engine.preset
        }
        .onChange(of: presetCopy) { _, newValue in
            engine.preset = newValue
        }
    }
    
    // MARK: - Oscillator Section
    
    private var oscillatorSection: some View {
        SynthCard(title: "OSCILLATORS", icon: "waveform", color: .cyan) {
            VStack(spacing: 14) {
                // OSC 1
                HStack(spacing: 12) {
                    StyledPicker(
                        label: "OSC 1",
                        selection: $presetCopy.oscillator1,
                        options: OscillatorType.allCases,
                        color: .cyan
                    )
                    
                    StyledPicker(
                        label: "OSC 2",
                        selection: $presetCopy.oscillator2,
                        options: OscillatorType.allCases,
                        color: .cyan
                    )
                }
                
                // Mix & Detune sliders
                ParameterSlider(
                    label: "MIX",
                    value: $presetCopy.oscillatorMix,
                    range: 0...1,
                    format: { "OSC1 \(Int((1 - $0) * 100))% / OSC2 \(Int($0 * 100))%" },
                    color: .cyan
                )
                
                HStack(spacing: 12) {
                    ParameterSlider(
                        label: "DETUNE",
                        value: $presetCopy.oscillator2Detune,
                        range: -100...100,
                        format: { String(format: "%.0f¢", $0) },
                        color: .cyan
                    )
                    
                    // Octave selector
                    VStack(alignment: .leading, spacing: 4) {
                        Text("OCTAVE")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                        
                        Picker("", selection: $presetCopy.oscillator2Octave) {
                            ForEach(-2...2, id: \.self) { oct in
                                Text(oct > 0 ? "+\(oct)" : "\(oct)").tag(oct)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 120)
                    }
                }
            }
        }
    }
    
    // MARK: - Filter Section
    
    private var filterSection: some View {
        SynthCard(title: "FILTER", icon: "line.diagonal.arrow", color: .orange) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    StyledPicker(
                        label: "TYPE",
                        selection: $presetCopy.filter.type,
                        options: FilterType.allCases,
                        color: .orange
                    )
                    
                    Spacer()
                }
                
                ParameterSlider(
                    label: "CUTOFF",
                    value: $presetCopy.filter.cutoff,
                    range: 0...1,
                    format: { String(format: "%.0f Hz", $0 * 20000) },
                    color: .orange
                )
                
                HStack(spacing: 12) {
                    ParameterSlider(
                        label: "RESONANCE",
                        value: $presetCopy.filter.resonance,
                        range: 0...1,
                        format: { "\(Int($0 * 100))%" },
                        color: .orange
                    )
                    
                    ParameterSlider(
                        label: "ENV AMT",
                        value: $presetCopy.filter.envelopeAmount,
                        range: -1...1,
                        format: { String(format: "%.0f%%", $0 * 100) },
                        color: .orange
                    )
                }
            }
        }
    }
    
    // MARK: - Envelope Section (Large Center)
    
    private var envelopeSection: some View {
        SynthCard(title: "ENVELOPE", icon: "arrow.up.right", color: .green) {
            VStack(spacing: 16) {
                // Large ADSR visualization
                EnvelopeVisualization(envelope: presetCopy.envelope)
                    .frame(height: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.2))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
                    )
                
                // ADSR sliders in a grid
                VStack(spacing: 10) {
                    ParameterSlider(
                        label: "ATTACK",
                        value: $presetCopy.envelope.attack,
                        range: 0.001...10,
                        format: { formatTime($0) },
                        color: .green
                    )
                    
                    ParameterSlider(
                        label: "DECAY",
                        value: $presetCopy.envelope.decay,
                        range: 0.001...10,
                        format: { formatTime($0) },
                        color: .green
                    )
                    
                    ParameterSlider(
                        label: "SUSTAIN",
                        value: $presetCopy.envelope.sustain,
                        range: 0...1,
                        format: { "\(Int($0 * 100))%" },
                        color: .green
                    )
                    
                    ParameterSlider(
                        label: "RELEASE",
                        value: $presetCopy.envelope.release,
                        range: 0.001...30,
                        format: { formatTime($0) },
                        color: .green
                    )
                }
            }
        }
    }
    
    // MARK: - LFO Section
    
    private var lfoSection: some View {
        SynthCard(title: "LFO", icon: "waveform.circle", color: .pink) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    StyledPicker(
                        label: "SHAPE",
                        selection: $presetCopy.lfo.shape,
                        options: LFOShape.allCases,
                        color: .pink
                    )
                    
                    StyledPicker(
                        label: "DEST",
                        selection: $presetCopy.lfo.destination,
                        options: LFODestination.allCases,
                        color: .pink
                    )
                }
                
                ParameterSlider(
                    label: "RATE",
                    value: $presetCopy.lfo.rate,
                    range: 0.1...20,
                    format: { String(format: "%.1f Hz", $0) },
                    color: .pink
                )
                
                ParameterSlider(
                    label: "DEPTH",
                    value: $presetCopy.lfo.depth,
                    range: 0...1,
                    format: { "\(Int($0 * 100))%" },
                    color: .pink
                )
            }
        }
    }
    
    // MARK: - Master Section
    
    private var masterSection: some View {
        SynthCard(title: "MASTER", icon: "speaker.wave.3", color: .purple) {
            VStack(spacing: 14) {
                // Preset button
                Button(action: { showPresetBrowser = true }) {
                    HStack {
                        Image(systemName: "folder")
                            .foregroundColor(.purple)
                        Text(presetCopy.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                // Volume slider
                ParameterSlider(
                    label: "VOLUME",
                    value: $presetCopy.masterVolume,
                    range: 0...1,
                    format: { "\(Int($0 * 100))%" },
                    color: .purple
                )
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatTime(_ seconds: Float) -> String {
        if seconds < 1 {
            return String(format: "%.0f ms", seconds * 1000)
        } else {
            return String(format: "%.2f s", seconds)
        }
    }
}

// MARK: - Synth Card Container

struct SynthCard<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
            }
            
            // Content
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Styled Picker

struct StyledPicker<T: Hashable & RawRepresentable & CaseIterable>: View where T.RawValue == String {
    let label: String
    @Binding var selection: T
    let options: [T]
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
            
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .frame(minWidth: 90)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - Parameter Slider

struct ParameterSlider: View {
    let label: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let format: (Float) -> String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(format(value))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
            }
            
            // Custom styled slider
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 6)
                    
                    // Filled portion
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.7), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geometry.size.width * normalizedValue), height: 6)
                    
                    // Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(color: color.opacity(0.5), radius: 3, x: 0, y: 1)
                        .offset(x: max(0, geometry.size.width * normalizedValue - 7))
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            let newValue = Float(gesture.location.x / geometry.size.width)
                            let clampedNormalized = max(0, min(1, newValue))
                            value = range.lowerBound + clampedNormalized * (range.upperBound - range.lowerBound)
                        }
                )
            }
            .frame(height: 18)
        }
    }
    
    private var normalizedValue: CGFloat {
        CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
    }
}

// MARK: - Envelope Visualization

struct EnvelopeVisualization: View {
    let envelope: ADSREnvelope
    
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let padding: CGFloat = 16
            
            ZStack {
                // Grid lines
                Path { path in
                    // Horizontal lines
                    for i in 0...4 {
                        let y = padding + CGFloat(i) * (h - 2 * padding) / 4
                        path.move(to: CGPoint(x: padding, y: y))
                        path.addLine(to: CGPoint(x: w - padding, y: y))
                    }
                }
                .stroke(Color.gray.opacity(0.15), lineWidth: 0.5)
                
                // ADSR labels
                HStack {
                    ForEach(["A", "D", "S", "R"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.green.opacity(0.4))
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, padding)
                .offset(y: h / 2 - 30)
                
                // Envelope path fill
                Path { path in
                    let points = envelopePoints(w: w, h: h, padding: padding)
                    path.move(to: points.start)
                    path.addLine(to: points.attackPeak)
                    path.addLine(to: points.decayEnd)
                    path.addLine(to: points.sustainEnd)
                    path.addLine(to: points.releaseEnd)
                    path.addLine(to: CGPoint(x: w - padding, y: h - padding))
                    path.addLine(to: CGPoint(x: padding, y: h - padding))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [
                            Color.green.opacity(0.3),
                            Color.cyan.opacity(0.2),
                            Color.purple.opacity(0.1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                
                // Envelope path stroke
                Path { path in
                    let points = envelopePoints(w: w, h: h, padding: padding)
                    path.move(to: points.start)
                    path.addLine(to: points.attackPeak)
                    path.addLine(to: points.decayEnd)
                    path.addLine(to: points.sustainEnd)
                    path.addLine(to: points.releaseEnd)
                }
                .stroke(
                    LinearGradient(
                        colors: [.green, .cyan, .blue, .purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                )
                
                // Control points
                let points = envelopePoints(w: w, h: h, padding: padding)
                ForEach([points.attackPeak, points.decayEnd, points.sustainEnd, points.releaseEnd], id: \.x) { point in
                    Circle()
                        .fill(Color.white)
                        .frame(width: 8, height: 8)
                        .shadow(color: .green.opacity(0.5), radius: 4)
                        .position(point)
                }
            }
        }
    }
    
    private func envelopePoints(w: CGFloat, h: CGFloat, padding: CGFloat) -> (start: CGPoint, attackPeak: CGPoint, decayEnd: CGPoint, sustainEnd: CGPoint, releaseEnd: CGPoint) {
        let totalTime = CGFloat(envelope.attack + envelope.decay + 1.0 + envelope.release)
        let drawWidth = w - 2 * padding
        let drawHeight = h - 2 * padding
        
        let attackWidth = CGFloat(envelope.attack) / totalTime * drawWidth
        let decayWidth = CGFloat(envelope.decay) / totalTime * drawWidth
        let sustainWidth = 1.0 / totalTime * drawWidth
        
        let sustainY = padding + (1 - CGFloat(envelope.sustain)) * drawHeight
        
        let start = CGPoint(x: padding, y: h - padding)
        let attackPeak = CGPoint(x: padding + attackWidth, y: padding)
        let decayEnd = CGPoint(x: padding + attackWidth + decayWidth, y: sustainY)
        let sustainEnd = CGPoint(x: padding + attackWidth + decayWidth + sustainWidth, y: sustainY)
        let releaseEnd = CGPoint(x: w - padding, y: h - padding)
        
        return (start, attackPeak, decayEnd, sustainEnd, releaseEnd)
    }
}

// MARK: - Mini Keyboard View

struct MiniKeyboardView: View {
    @Binding var activeKey: UInt8?
    let onNoteOn: (UInt8) -> Void
    let onNoteOff: (UInt8) -> Void
    
    private let startOctave = 4
    private let numOctaves = 3
    
    var body: some View {
        GeometryReader { geometry in
            let whiteKeyWidth = geometry.size.width / CGFloat(numOctaves * 7)
            let blackKeyWidth = whiteKeyWidth * 0.55
            let blackKeyHeight = geometry.size.height * 0.58
            
            ZStack(alignment: .topLeading) {
                whiteKeysView(whiteKeyWidth: whiteKeyWidth, height: geometry.size.height)
                blackKeysView(whiteKeyWidth: whiteKeyWidth, blackKeyWidth: blackKeyWidth, blackKeyHeight: blackKeyHeight)
            }
        }
        .background(Color.gray.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    @ViewBuilder
    private func whiteKeysView(whiteKeyWidth: CGFloat, height: CGFloat) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<(numOctaves * 7), id: \.self) { i in
                SynthWhiteKey(
                    index: i,
                    pitch: pitchForWhiteKey(i),
                    isActive: activeKey == pitchForWhiteKey(i),
                    startOctave: startOctave,
                    height: height,
                    onNoteOn: { pitch in
                        if let prev = activeKey { onNoteOff(prev) }
                        onNoteOn(pitch)
                    },
                    onNoteOff: onNoteOff
                )
            }
        }
    }
    
    @ViewBuilder
    private func blackKeysView(whiteKeyWidth: CGFloat, blackKeyWidth: CGFloat, blackKeyHeight: CGFloat) -> some View {
        HStack(spacing: 1) {
            ForEach(0..<(numOctaves * 7), id: \.self) { i in
                if isBlackKeyPosition(i) {
                    SynthBlackKey(
                        pitch: pitchForBlackKey(i),
                        isActive: activeKey == pitchForBlackKey(i),
                        width: blackKeyWidth,
                        height: blackKeyHeight,
                        onNoteOn: { pitch in
                            if let prev = activeKey { onNoteOff(prev) }
                            onNoteOn(pitch)
                        },
                        onNoteOff: onNoteOff
                    )
                    .frame(width: whiteKeyWidth)
                } else {
                    Color.clear
                        .frame(width: whiteKeyWidth)
                }
            }
        }
    }
    
    private func isBlackKeyPosition(_ i: Int) -> Bool {
        [1, 2, 4, 5, 6].contains(i % 7)
    }
    
    private func pitchForWhiteKey(_ index: Int) -> UInt8 {
        let octave = startOctave + index / 7
        let whiteKeyOffsets = [0, 2, 4, 5, 7, 9, 11]
        let noteInOctave = whiteKeyOffsets[index % 7]
        return UInt8((octave + 1) * 12 + noteInOctave)
    }
    
    private func pitchForBlackKey(_ whiteKeyIndex: Int) -> UInt8 {
        let octave = startOctave + whiteKeyIndex / 7
        let offsets: [Int: Int] = [1: 1, 2: 3, 4: 6, 5: 8, 6: 10]
        let noteOffset = offsets[whiteKeyIndex % 7] ?? 0
        return UInt8((octave + 1) * 12 + noteOffset)
    }
}

// MARK: - Synth White Key

private struct SynthWhiteKey: View {
    let index: Int
    let pitch: UInt8
    let isActive: Bool
    let startOctave: Int
    let height: CGFloat
    let onNoteOn: (UInt8) -> Void
    let onNoteOff: (UInt8) -> Void
    
    var body: some View {
        Rectangle()
            .fill(isActive ? Color.purple.opacity(0.5) : Color.white)
            .overlay(
                Rectangle()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
            )
            .overlay(noteLabel)
            .gesture(keyGesture)
    }
    
    @ViewBuilder
    private var noteLabel: some View {
        if index % 7 == 0 {
            Text("C\(startOctave + index / 7)")
                .font(.system(size: 8))
                .foregroundColor(.gray)
                .offset(y: height / 2 - 4)
        }
    }
    
    private var keyGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in onNoteOn(pitch) }
            .onEnded { _ in onNoteOff(pitch) }
    }
}

// MARK: - Synth Black Key

private struct SynthBlackKey: View {
    let pitch: UInt8
    let isActive: Bool
    let width: CGFloat
    let height: CGFloat
    let onNoteOn: (UInt8) -> Void
    let onNoteOff: (UInt8) -> Void
    
    var body: some View {
        Rectangle()
            .fill(isActive ? Color.purple : Color.black)
            .frame(width: width, height: height)
            .cornerRadius(2)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
            .offset(x: -width / 2 + 0.5)
            .gesture(keyGesture)
    }
    
    private var keyGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in onNoteOn(pitch) }
            .onEnded { _ in onNoteOff(pitch) }
    }
}

// MARK: - Preset Browser

struct PresetBrowserView: View {
    let currentPreset: SynthPreset
    let onSelect: (SynthPreset) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    
    private var filteredPresets: [SynthPreset] {
        if searchText.isEmpty {
            return SynthPreset.allPresets
        }
        return SynthPreset.allPresets.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundColor(.purple)
                Text("Synth Presets")
                    .font(.headline)
                
                Spacer()
                
                Button("Close") { dismiss() }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search presets...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(8)
            .padding()
            
            // Preset list
            List(filteredPresets) { preset in
                Button(action: { onSelect(preset) }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.name)
                                .fontWeight(.medium)
                            
                            HStack(spacing: 6) {
                                Label(preset.oscillator1.rawValue, systemImage: "waveform")
                                Text("+")
                                    .foregroundColor(.secondary)
                                Label(preset.oscillator2.rawValue, systemImage: "waveform")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if preset.id == currentPreset.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.purple)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 400, height: 500)
    }
}

