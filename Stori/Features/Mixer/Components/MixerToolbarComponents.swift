//
//  MixerToolbarComponents.swift
//  Stori
//
//  Toolbar components for the professional mixer
//

import SwiftUI

// MARK: - Filter Toggle Button
struct FilterToggle: View {
    let label: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack(spacing: 4) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10))
                    .foregroundColor(isOn ? .accentColor : .secondary)
                
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(isOn ? .primary : .secondary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isOn ? Color.accentColor.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mixer Section Header
struct MixerSectionHeader: View {
    let title: String
    let count: Int
    @Binding var isExpanded: Bool
    
    var body: some View {
        Button(action: { 
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundColor(.secondary)
                
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .cornerRadius(4)
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Width Mode Picker
struct ChannelWidthPicker: View {
    @Binding var selectedWidth: ChannelStripWidth
    let onChange: (ChannelStripWidth) -> Void
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(ChannelStripWidth.allCases, id: \.self) { width in
                Button(action: {
                    selectedWidth = width
                    onChange(width)
                }) {
                    Image(systemName: iconFor(width))
                        .font(.system(size: 10))
                        .foregroundColor(selectedWidth == width ? .white : .secondary)
                        .frame(width: 24, height: 20)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .fill(selectedWidth == width ? Color.accentColor : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .help(width.rawValue)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(.controlBackgroundColor))
        )
    }
    
    private func iconFor(_ width: ChannelStripWidth) -> String {
        switch width {
        case .narrow: return "rectangle.split.3x1"
        case .standard: return "rectangle.split.2x1"
        case .wide: return "rectangle"
        }
    }
}

// MARK: - Mixer Zoom Control
struct MixerZoomControl: View {
    @Binding var zoomLevel: Double
    let range: ClosedRange<Double>
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: { 
                zoomLevel = max(range.lowerBound, zoomLevel - 0.1)
            }) {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .disabled(zoomLevel <= range.lowerBound)
            
            Slider(value: $zoomLevel, in: range)
                .frame(width: 60)
                .controlSize(.mini)
            
            Button(action: {
                zoomLevel = min(range.upperBound, zoomLevel + 0.1)
            }) {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .disabled(zoomLevel >= range.upperBound)
        }
    }
}

// MARK: - Solo/Mute All Buttons
struct GlobalMuteControls: View {
    let hasSoloedTracks: Bool
    let hasMutedTracks: Bool
    let onClearSolo: () -> Void
    let onClearMute: () -> Void
    
    var body: some View {
        HStack(spacing: 4) {
            if hasSoloedTracks {
                Button(action: onClearSolo) {
                    HStack(spacing: 2) {
                        Text("S")
                            .font(.system(size: 9, weight: .bold))
                        Image(systemName: "xmark")
                            .font(.system(size: 7))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(MixerColors.soloActive)
                    .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help("Clear All Solos")
            }
            
            if hasMutedTracks {
                Button(action: onClearMute) {
                    HStack(spacing: 2) {
                        Text("M")
                            .font(.system(size: 9, weight: .bold))
                        Image(systemName: "xmark")
                            .font(.system(size: 7))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(MixerColors.muteActive)
                    .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help("Clear All Mutes")
            }
        }
    }
}
