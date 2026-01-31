//
//  ChannelPanKnob.swift
//  Stori
//
//  Professional pan knob with center detent for channel strips
//

import SwiftUI

// MARK: - Channel Pan Knob
struct ChannelPanKnob: View {
    @Binding var value: Float  // -1.0 (L) to +1.0 (R)
    let size: CGFloat
    let onChange: () -> Void
    
    @State private var isDragging = false
    @State private var lastDragValue: CGFloat = 0
    @State private var showingValue = false
    
    private var normalizedValue: Float {
        (value + 1.0) / 2.0  // Convert -1...1 to 0...1
    }
    
    private var angle: Double {
        Double(normalizedValue) * 270 - 135 // -135° to +135°
    }
    
    private var displayValue: String {
        if abs(value) < 0.02 {
            return "C"
        } else if value < 0 {
            return String(format: "%.0fL", abs(value) * 100)
        } else {
            return String(format: "%.0fR", value * 100)
        }
    }
    
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                // Outer ring - shows position arc
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 3)
                
                // Position arc from center
                positionArc
                
                // Knob body with gradient
                Circle()
                    .fill(knobGradient)
                    .frame(width: size - 6, height: size - 6)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                
                // Indicator line
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2, height: size * 0.25)
                    .offset(y: -size * 0.22)
                    .rotationEffect(.degrees(angle))
                
                // Center dot (shows center detent)
                Circle()
                    .fill(abs(value) < 0.02 ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: 4, height: 4)
            }
            .frame(width: size, height: size)
            .gesture(panGesture)
            .onTapGesture(count: 2) {
                // Double-tap to center
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    value = 0
                    onChange()
                }
            }
            
            // Value display (shown on hover/drag)
            if showingValue || isDragging {
                Text(displayValue)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                showingValue = hovering
            }
        }
        .help("Pan: \(displayValue)")
    }
    
    // MARK: - Position Arc
    // Arc extends from center (12 o'clock) towards the indicator direction
    private var positionArc: some View {
        // Use the same angle calculation as the indicator line
        // Center = 0°, full right = +135°, full left = -135°
        let arcAngle = Double(normalizedValue) * 270 - 135
        
        // Convert to trim values (0.0-1.0 range)
        // In SwiftUI Circle: 0.0 = 3 o'clock, 0.25 = 6 o'clock, 0.5 = 9 o'clock, 0.75 = 12 o'clock
        let centerTrim: CGFloat = 0.75  // 12 o'clock position (top)
        let arcTrim = CGFloat(arcAngle / 360.0)
        
        return Circle()
            .trim(
                from: value < 0 ? centerTrim + arcTrim : centerTrim,
                to: value < 0 ? centerTrim : centerTrim + arcTrim
            )
            .stroke(
                arcColor,
                style: StrokeStyle(lineWidth: 3, lineCap: .round)
            )
    }
    
    private var arcColor: Color {
        if value < -0.5 {
            return .blue
        } else if value > 0.5 {
            return .orange
        } else {
            return .accentColor
        }
    }
    
    // MARK: - Pan Gesture
    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { gesture in
                if !isDragging {
                    isDragging = true
                    lastDragValue = gesture.translation.height
                }
                
                // Vertical drag for precision, horizontal for quick pan
                let verticalDelta = Float(lastDragValue - gesture.translation.height) * 0.008
                let horizontalDelta = Float(gesture.translation.width - (lastDragValue * 0.5)) * 0.004
                let delta = verticalDelta + horizontalDelta * 0.5
                
                var newValue = max(-1.0, min(1.0, value + delta))
                
                // Center detent - snap to center when close
                if abs(newValue) < 0.03 && abs(value) >= 0.03 {
                    newValue = 0
                    // Haptic feedback would go here on iOS
                }
                
                if newValue != value {
                    value = newValue
                    onChange()
                }
                
                lastDragValue = gesture.translation.height
            }
            .onEnded { _ in
                isDragging = false
            }
    }
    
    // MARK: - Knob Gradient
    private var knobGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(white: 0.35),
                Color(white: 0.25),
                Color(white: 0.2)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Compact Pan Display
struct CompactPanDisplay: View {
    let value: Float
    
    var body: some View {
        HStack(spacing: 2) {
            // Left indicator
            Rectangle()
                .fill(value < 0 ? Color.blue : Color.gray.opacity(0.2))
                .frame(width: 12, height: 4)
                .overlay(
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: CGFloat(max(0, -value)) * 12)
                        .frame(maxWidth: .infinity, alignment: .trailing),
                    alignment: .trailing
                )
            
            // Center dot
            Circle()
                .fill(abs(value) < 0.02 ? Color.white : Color.gray.opacity(0.5))
                .frame(width: 4, height: 4)
            
            // Right indicator
            Rectangle()
                .fill(value > 0 ? Color.orange : Color.gray.opacity(0.2))
                .frame(width: 12, height: 4)
                .overlay(
                    Rectangle()
                        .fill(Color.orange)
                        .frame(width: CGFloat(max(0, value)) * 12)
                        .frame(maxWidth: .infinity, alignment: .leading),
                    alignment: .leading
                )
        }
    }
}
