//
//  ChannelFader.swift
//  Stori
//
//  Professional channel fader with integrated metering
//

import SwiftUI

// MARK: - Channel Fader
struct ChannelFader: View {
    @Binding var value: Float  // 0.0 to 1.0 (linear)
    let meterLeft: Float
    let meterRight: Float
    let peakLeft: Float
    let peakRight: Float
    let height: CGFloat
    let showMeter: Bool
    let accessibilityLabel: String?
    let onChange: () -> Void
    
    @State private var isDragging = false
    @State private var showingValue = false
    
    init(
        value: Binding<Float>,
        meterLeft: Float = 0,
        meterRight: Float = 0,
        peakLeft: Float = 0,
        peakRight: Float = 0,
        height: CGFloat = 160,
        showMeter: Bool = true,
        accessibilityLabel: String? = nil,
        onChange: @escaping () -> Void
    ) {
        self._value = value
        self.meterLeft = meterLeft
        self.meterRight = meterRight
        self.peakLeft = peakLeft
        self.peakRight = peakRight
        self.height = height
        self.showMeter = showMeter
        self.accessibilityLabel = accessibilityLabel
        self.onChange = onChange
    }
    
    private var displayValue: String {
        if value <= 0.001 {
            return "-∞"
        } else {
            let dB = 20 * log10(value)
            if dB >= -0.5 {
                return "0.0"
            } else {
                return String(format: "%.1f", dB)
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // dB Value display
            Text(displayValue)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(isDragging ? .accentColor : .secondary)
                .frame(height: 14)
            
            // Fader with meters
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    // Left meter
                    if showMeter {
                        singleMeter(level: meterLeft, peak: peakLeft, height: geometry.size.height)
                    }
                    
                    // Fader track
                    faderTrack(height: geometry.size.height)
                    
                    // Right meter
                    if showMeter {
                        singleMeter(level: meterRight, peak: peakRight, height: geometry.size.height)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: height)
            
            // -∞ label
            Text("-∞")
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(0.6))
        }
        // ACCESSIBILITY: Channel Fader
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? "Volume Fader")
        .accessibilityValue("\(displayValue) dB")
        .accessibilityHint("Swipe up or down to adjust volume")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = min(1.0, value + 0.05)
                onChange()
            case .decrement:
                value = max(0.0, value - 0.05)
                onChange()
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - Fader Track
    private func faderTrack(height: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Track background
                RoundedRectangle(cornerRadius: 3)
                    .fill(MixerColors.faderTrack)
                    .frame(width: 8)
                
                // Track fill (optional visual feedback)
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.3),
                                Color.accentColor.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 8, height: geometry.size.height * CGFloat(value))
                
                // Fader cap/thumb
                faderCap
                    .offset(y: -geometry.size.height * CGFloat(value) + 12)
            }
            .frame(maxWidth: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let newValue = 1 - Float(gesture.location.y / geometry.size.height)
                        let clampedValue = max(0, min(1, newValue))
                        if clampedValue != value {
                            value = clampedValue
                            onChange()
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(width: 24)
    }
    
    // MARK: - Fader Cap
    private var faderCap: some View {
        ZStack {
            // Cap body
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: isDragging ? 0.95 : 0.85),
                            Color(white: isDragging ? 0.80 : 0.70),
                            Color(white: isDragging ? 0.70 : 0.60)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.4), radius: isDragging ? 3 : 2, x: 0, y: 1)
            
            // Center groove lines
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 14, height: 1)
                }
            }
            
            // Highlight
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                .frame(width: 24, height: 24)
        }
    }
    
    // MARK: - Single Meter
    private func singleMeter(level: Float, peak: Float, height: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 5)
                    .cornerRadius(2)
                
                // Level fill
                Rectangle()
                    .fill(meterGradient)
                    .frame(width: 5, height: max(0, geometry.size.height * CGFloat(min(1.0, level))))
                    .cornerRadius(2)
                
                // Peak hold
                if peak > 0.01 {
                    Rectangle()
                        .fill(peakColor(for: peak))
                        .frame(width: 5, height: 2)
                        .offset(y: -geometry.size.height * CGFloat(min(1.0, peak)) + 1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 7)
    }
    
    private var meterGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: MixerColors.meterGreen, location: 0.0),
                .init(color: MixerColors.meterGreen, location: 0.6),
                .init(color: MixerColors.meterYellow, location: 0.75),
                .init(color: MixerColors.meterRed, location: 0.9),
                .init(color: MixerColors.meterPeak, location: 1.0)
            ],
            startPoint: .bottom,
            endPoint: .top
        )
    }
    
    private func peakColor(for level: Float) -> Color {
        if level >= 1.0 { return MixerColors.meterPeak }
        if level >= 0.9 { return MixerColors.meterRed }
        if level >= 0.75 { return MixerColors.meterYellow }
        return MixerColors.meterGreen
    }
}

// MARK: - Compact Fader (for narrow mode)
struct CompactFader: View {
    @Binding var value: Float
    let height: CGFloat
    let onChange: () -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Track
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 6)
                    .cornerRadius(3)
                
                // Fill
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.green, .yellow, .red],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 6, height: geometry.size.height * CGFloat(value))
                    .cornerRadius(3)
                
                // Thumb
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .stroke(Color.accentColor, lineWidth: 1)
                    .frame(width: 16, height: 8)
                    .offset(y: -geometry.size.height * CGFloat(value) + 4)
            }
            .frame(maxWidth: .infinity)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let newValue = 1 - Float(gesture.location.y / geometry.size.height)
                        let clampedValue = max(0, min(1, newValue))
                        if clampedValue != value {
                            value = clampedValue
                            onChange()
                        }
                    }
            )
        }
        .frame(height: height)
    }
}
