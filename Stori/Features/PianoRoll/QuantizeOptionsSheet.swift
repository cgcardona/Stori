//
//  QuantizeOptionsSheet.swift
//  Stori
//
//  Professional quantize options sheet with stunning visual design.
//  Features custom controls, presets, and smooth animations.
//

import SwiftUI

// MARK: - QuantizeOptionsSheet

/// Beautifully designed sheet for configuring quantize options
struct QuantizeOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var resolution: SnapResolution
    @Binding var strength: Double  // 0-100
    @Binding var swing: Double     // 0-100
    
    var selectedNoteCount: Int
    var onQuantize: () -> Void
    
    @State private var hoveredPreset: QuantizePreset?
    @State private var hoveredResolution: SnapResolution?
    
    var body: some View {
        VStack(spacing: 0) {
            // Gradient header with glassmorphism effect
            VStack(spacing: 12) {
                // Icon and title
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.accentColor.opacity(0.2), Color.accentColor.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.accentColor, .accentColor.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Quantize Options")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 6) {
                            Text("\(selectedNoteCount)")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundColor(.accentColor)
                            Text("note\(selectedNoteCount == 1 ? "" : "s") selected")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                }
                
                // Quick presets
                HStack(spacing: 8) {
                    ForEach(QuantizePreset.allCases, id: \.self) { preset in
                        PresetButton(
                            preset: preset,
                            isHovered: hoveredPreset == preset,
                            action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    strength = preset.strength
                                }
                            }
                        )
                        .onHover { hoveredPreset = $0 ? preset : nil }
                    }
                }
            }
            .padding(24)
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor),
                        Color(nsColor: .controlBackgroundColor).opacity(0.8)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Resolution grid
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Grid Resolution", systemImage: "square.grid.3x3")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 8) {
                            ForEach(SnapResolution.allCases, id: \.self) { res in
                                ResolutionButton(
                                    resolution: res,
                                    isSelected: resolution == res,
                                    isHovered: hoveredResolution == res,
                                    action: {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            resolution = res
                                        }
                                    }
                                )
                                .onHover { hoveredResolution = $0 ? res : nil }
                            }
                        }
                    }
                    
                    // Strength slider with visual feedback
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Quantize Strength", systemImage: "slider.horizontal.3")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("\(Int(strength))%")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(strengthColor)
                                .frame(minWidth: 50)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(strengthColor.opacity(0.15))
                                )
                        }
                        
                        CustomSlider(
                            value: $strength,
                            range: 0...100,
                            color: strengthColor,
                            icon: "arrow.up.and.down.righttriangle.up.righttriangle.down"
                        )
                        
                        Text("100% snaps perfectly to grid • 50% moves halfway • 0% no change")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    )
                    
                    // Swing slider with visual feedback
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Swing Amount", systemImage: "waveform.path")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Text("\(Int(swing))%")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(swingColor)
                                .frame(minWidth: 50)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(swingColor.opacity(0.15))
                                )
                        }
                        
                        CustomSlider(
                            value: $swing,
                            range: 0...100,
                            color: swingColor,
                            icon: "music.note"
                        )
                        
                        Text("Delays off-beat notes for groove • 50% is neutral swing")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    )
                }
                .padding(20)
            }
            
            Divider()
            
            // Action buttons with enhanced styling
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .keyboardShortcut(.escape, modifiers: [])
                
                Button(action: {
                    onQuantize()
                    dismiss()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Apply Quantize")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [])
                .disabled(selectedNoteCount == 0)
            }
            .padding(20)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
        .frame(width: 480, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var strengthColor: Color {
        if strength >= 75 { return .red }
        if strength >= 50 { return .orange }
        if strength >= 25 { return .yellow }
        return .green
    }
    
    private var swingColor: Color {
        if swing > 60 || swing < 40 { return .purple }
        return .blue
    }
}

// MARK: - Quantize Presets

/// Quick quantize presets
enum QuantizePreset: String, CaseIterable {
    case full = "Full"
    case tight = "Tight"
    case loose = "Loose"
    case gentle = "Gentle"
    
    var strength: Double {
        switch self {
        case .full: return 100
        case .tight: return 75
        case .loose: return 50
        case .gentle: return 25
        }
    }
    
    var icon: String {
        switch self {
        case .full: return "bolt.fill"
        case .tight: return "bolt"
        case .loose: return "wind"
        case .gentle: return "leaf.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .full: return .red
        case .tight: return .orange
        case .loose: return .yellow
        case .gentle: return .green
        }
    }
}

// MARK: - Custom Components

/// Preset button with hover effects
private struct PresetButton: View {
    let preset: QuantizePreset
    let isHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: preset.icon)
                    .font(.system(size: 14, weight: .semibold))
                Text(preset.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? preset.color.opacity(0.2) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isHovered ? preset.color : Color.secondary.opacity(0.3),
                        lineWidth: isHovered ? 2 : 1
                    )
            )
            .foregroundColor(isHovered ? preset.color : .secondary)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
    }
}

/// Resolution button with selection state
private struct ResolutionButton: View {
    let resolution: SnapResolution
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(resolution.rawValue)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium, design: .rounded))
                .frame(height: 36)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(
                            isSelected
                            ? LinearGradient(
                                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [
                                    isHovered ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor),
                                    isHovered ? Color.accentColor.opacity(0.1) : Color(nsColor: .controlBackgroundColor)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isSelected ? Color.clear : (isHovered ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.2)),
                            lineWidth: 1
                        )
                )
                .foregroundColor(isSelected ? .white : .primary)
                .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : .clear, radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
        .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isHovered)
    }
}

/// Custom styled slider with gradient track
private struct CustomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let color: Color
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color.opacity(0.8))
                .frame(width: 24)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)
                    
                    // Progress track with gradient
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.8), color],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)), height: 6)
                    
                    // Thumb
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.white, Color(white: 0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 20, height: 20)
                        .shadow(color: color.opacity(0.4), radius: 4, y: 2)
                        .overlay(
                            Circle()
                                .strokeBorder(color, lineWidth: 2)
                        )
                        .offset(x: geometry.size.width * CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound)) - 10)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { gesture in
                                    let percent = max(0, min(1, gesture.location.x / geometry.size.width))
                                    value = range.lowerBound + (range.upperBound - range.lowerBound) * Double(percent)
                                }
                        )
                }
            }
            .frame(height: 20)
        }
    }
}

/// Primary button style with gradient
private struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: configuration.isPressed
                            ? [Color.accentColor.opacity(0.7), Color.accentColor.opacity(0.6)]
                            : [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .foregroundColor(.white)
            .shadow(color: Color.accentColor.opacity(0.3), radius: configuration.isPressed ? 4 : 8, y: configuration.isPressed ? 1 : 2)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary button style
private struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(.primary)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
