//
//  ChannelMeter.swift
//  Stori
//
//  Professional stereo level meter with peak hold and clip indicators
//

import SwiftUI

// MARK: - Channel Meter Component
struct ChannelMeter: View {
    let leftLevel: Float    // 0.0 to 1.0 (normalized from dB)
    let rightLevel: Float   // 0.0 to 1.0 (normalized from dB)
    let peakLeft: Float     // Peak hold value
    let peakRight: Float    // Peak hold value
    let isClipping: Bool    // True if signal has clipped
    let height: CGFloat
    let showScale: Bool
    
    @State private var clipIndicatorActive = false
    
    init(
        leftLevel: Float = 0,
        rightLevel: Float = 0,
        peakLeft: Float = 0,
        peakRight: Float = 0,
        isClipping: Bool = false,
        height: CGFloat = 160,
        showScale: Bool = true
    ) {
        self.leftLevel = leftLevel
        self.rightLevel = rightLevel
        self.peakLeft = peakLeft
        self.peakRight = peakRight
        self.isClipping = isClipping
        self.height = height
        self.showScale = showScale
    }
    
    var body: some View {
        HStack(spacing: 1) {
            // Left channel meter
            singleMeter(level: leftLevel, peak: peakLeft)
            
            // Right channel meter  
            singleMeter(level: rightLevel, peak: peakRight)
            
            // dB Scale (optional)
            if showScale {
                dbScale
            }
        }
        .frame(height: height)
    }
    
    // MARK: - Single Channel Meter
    private func singleMeter(level: Float, peak: Float) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background track
                Rectangle()
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 6)
                    .cornerRadius(2)
                
                // Level fill with gradient
                Rectangle()
                    .fill(meterGradient)
                    .frame(width: 6, height: geometry.size.height * CGFloat(min(1.0, max(0, level))))
                    .cornerRadius(2)
                
                // Peak hold indicator
                if peak > 0.01 {
                    Rectangle()
                        .fill(peakColor(for: peak))
                        .frame(width: 6, height: 2)
                        .offset(y: -geometry.size.height * CGFloat(min(1.0, peak)) + 1)
                }
                
                // Clip indicator at top
                if isClipping || clipIndicatorActive {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: 6, height: 4)
                        .offset(y: -geometry.size.height + 2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 8)
    }
    
    // MARK: - dB Scale
    private var dbScale: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                ForEach(scaleMarks, id: \.db) { mark in
                    Text(mark.label)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.7))
                        .offset(y: -geometry.size.height * CGFloat(mark.position) + geometry.size.height / 2 - 4)
                }
            }
        }
        .frame(width: 20)
    }
    
    // MARK: - Scale Marks
    private var scaleMarks: [(db: Int, label: String, position: Float)] {
        [
            (0, "0", 1.0),
            (-6, "-6", 0.75),
            (-12, "-12", 0.5),
            (-24, "-24", 0.25),
            (-48, "-48", 0.08)
        ]
    }
    
    // MARK: - Gradients and Colors
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
        if level >= 1.0 {
            return MixerColors.meterPeak
        } else if level >= 0.9 {
            return MixerColors.meterRed
        } else if level >= 0.75 {
            return MixerColors.meterYellow
        } else {
            return MixerColors.meterGreen
        }
    }
}

// MARK: - Compact Meter (for narrow channel strips)
struct CompactChannelMeter: View {
    let level: Float  // Mono or stereo sum
    let peak: Float
    let height: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Background
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 4)
                    .cornerRadius(2)
                
                // Level
                Rectangle()
                    .fill(compactGradient)
                    .frame(width: 4, height: geometry.size.height * CGFloat(min(1.0, max(0, level))))
                    .cornerRadius(2)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 6, height: height)
    }
    
    private var compactGradient: LinearGradient {
        LinearGradient(
            colors: [MixerColors.meterGreen, MixerColors.meterYellow, MixerColors.meterRed],
            startPoint: .bottom,
            endPoint: .top
        )
    }
}

// MARK: - Mixer Colors (System-aware)
struct MixerColors {
    // Use system colors that adapt to light/dark mode
    static let background = Color(.controlBackgroundColor)
    static let channelBackground = Color(.controlBackgroundColor)
    static let channelSelected = Color.accentColor.opacity(0.15)
    static let faderTrack = Color.primary.opacity(0.1)
    
    // Meter colors (consistent across themes for visibility)
    static let meterGreen = Color.green
    static let meterYellow = Color.yellow
    static let meterRed = Color.red
    static let meterPeak = Color.red
    
    // Transport button colors
    static let muteActive = Color.orange
    static let soloActive = Color.yellow
    static let recordArm = Color.red
    static let inputMonitor = Color.cyan
    
    // Section styling
    static let sectionHeader = Color.secondary.opacity(0.8)
    static let slotBackground = Color.primary.opacity(0.05)
    static let slotBorder = Color.secondary.opacity(0.3)
}
