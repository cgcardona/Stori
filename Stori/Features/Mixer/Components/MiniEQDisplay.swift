//
//  MiniEQDisplay.swift
//  Stori
//
//  Compact EQ curve visualization for channel strips
//

import SwiftUI

// MARK: - Mini EQ Display
struct MiniEQDisplay: View {
    let highEQ: Float   // -20 to +20 dB
    let midEQ: Float    // -20 to +20 dB
    let lowEQ: Float    // -20 to +20 dB
    let isEnabled: Bool
    let width: CGFloat
    let height: CGFloat
    
    init(
        highEQ: Float = 0,
        midEQ: Float = 0,
        lowEQ: Float = 0,
        isEnabled: Bool = true,
        width: CGFloat = 70,
        height: CGFloat = 30
    ) {
        self.highEQ = highEQ
        self.midEQ = midEQ
        self.lowEQ = lowEQ
        self.isEnabled = isEnabled
        self.width = width
        self.height = height
    }
    
    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.3))
            
            // EQ Curve
            if isEnabled {
                eqCurvePath
                    .stroke(
                        eqGradient,
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
            } else {
                eqCurvePath
                    .stroke(
                        Color.gray.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                    .opacity(0.5)
            }
            
            // Center line (0 dB reference)
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 0.5)
            
            // Bypass indicator
            if !isEnabled {
                Image(systemName: "line.diagonal")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: width, height: height)
    }
    
    // MARK: - EQ Curve Path
    private var eqCurvePath: Path {
        Path { path in
            let centerY = height / 2
            let maxDeviation = height / 2 - 4  // Leave padding
            
            // Normalize EQ values to curve positions
            let lowY = centerY - CGFloat(lowEQ / 20.0) * maxDeviation
            let midY = centerY - CGFloat(midEQ / 20.0) * maxDeviation
            let highY = centerY - CGFloat(highEQ / 20.0) * maxDeviation
            
            // Control points for smooth curve
            let x1: CGFloat = 4
            let x2 = width * 0.25
            let x3 = width * 0.5
            let x4 = width * 0.75
            let x5 = width - 4
            
            path.move(to: CGPoint(x: x1, y: lowY))
            path.addCurve(
                to: CGPoint(x: x3, y: midY),
                control1: CGPoint(x: x2, y: lowY),
                control2: CGPoint(x: x2 + 10, y: midY)
            )
            path.addCurve(
                to: CGPoint(x: x5, y: highY),
                control1: CGPoint(x: x4 - 10, y: midY),
                control2: CGPoint(x: x4, y: highY)
            )
        }
    }
    
    private var eqGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.blue.opacity(0.8),
                Color.cyan.opacity(0.8),
                Color.purple.opacity(0.8)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

// MARK: - EQ Knobs Section
struct EQKnobsSection: View {
    @Binding var highEQ: Float
    @Binding var midEQ: Float
    @Binding var lowEQ: Float
    @Binding var isEnabled: Bool
    let onUpdate: () -> Void
    
    var body: some View {
        VStack(spacing: 4) {
            // Section Header with bypass toggle
            HStack {
                Text("EQ")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(MixerColors.sectionHeader)
                
                Spacer()
                
                Button(action: {
                    isEnabled.toggle()
                    onUpdate()
                }) {
                    Image(systemName: isEnabled ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 10))
                        .foregroundColor(isEnabled ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help(isEnabled ? "Bypass EQ" : "Enable EQ")
            }
            .padding(.horizontal, 4)
            
            // Mini EQ Display
            MiniEQDisplay(
                highEQ: highEQ,
                midEQ: midEQ,
                lowEQ: lowEQ,
                isEnabled: isEnabled
            )
            .padding(.horizontal, 4)
            
            // EQ Knobs
            HStack(spacing: 6) {
                VStack(spacing: 2) {
                    EQRotaryKnob(
                        value: $lowEQ,
                        range: -20...20,
                        size: 22,
                        color: .blue
                    ) { onUpdate() }
                    Text("Lo")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 2) {
                    EQRotaryKnob(
                        value: $midEQ,
                        range: -20...20,
                        size: 22,
                        color: .cyan
                    ) { onUpdate() }
                    Text("Mid")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
                
                VStack(spacing: 2) {
                    EQRotaryKnob(
                        value: $highEQ,
                        range: -20...20,
                        size: 22,
                        color: .purple
                    ) { onUpdate() }
                    Text("Hi")
                        .font(.system(size: 7))
                        .foregroundColor(.secondary)
                }
            }
            .opacity(isEnabled ? 1.0 : 0.5)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(MixerColors.slotBackground)
        )
    }
}

// MARK: - EQ Rotary Knob
struct EQRotaryKnob: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let size: CGFloat
    let color: Color
    let onChange: () -> Void
    
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
            // Outer ring showing value
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 2)
            
            // Value arc
            Circle()
                .trim(from: 0.125, to: CGFloat(0.125 + normalizedValue * 0.75))
                .stroke(color, lineWidth: 2)
                .rotationEffect(.degrees(90))
            
            // Knob body
            Circle()
                .fill(Color(.controlBackgroundColor))
                .frame(width: size - 4, height: size - 4)
            
            // Indicator line
            Rectangle()
                .fill(color)
                .frame(width: 2, height: size * 0.25)
                .offset(y: -size * 0.2)
                .rotationEffect(.degrees(angle))
            
            // Center dot
            Circle()
                .fill(Color.primary.opacity(0.3))
                .frame(width: 3, height: 3)
        }
        .frame(width: size, height: size)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    if !isDragging {
                        isDragging = true
                        lastDragValue = gesture.translation.height
                    }
                    
                    let delta = Float(lastDragValue - gesture.translation.height) * 0.3
                    let newValue = max(range.lowerBound, min(range.upperBound, value + delta))
                    
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
            // Double-tap to reset to 0
            value = 0
            onChange()
        }
        .help(String(format: "%.1f dB", value))
    }
}
