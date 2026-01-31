//
//  SidechainPickerView.swift
//  Stori
//
//  Sidechain source picker for dynamics plugins
//

import SwiftUI

// MARK: - Sidechain Picker View

/// A popover view for selecting sidechain sources for dynamics plugins
struct SidechainPickerView: View {
    let currentSource: SidechainSource
    let availableTracks: [AudioTrack]
    let availableBuses: [MixerBus]
    let currentTrackId: UUID  // The track containing the plugin (excluded from sources)
    let onSelect: (SidechainSource) -> Void
    
    @State private var searchText = ""
    
    // Filter out the current track from sources
    private var otherTracks: [AudioTrack] {
        availableTracks.filter { $0.id != currentTrackId }
    }
    
    private var filteredTracks: [AudioTrack] {
        if searchText.isEmpty {
            return otherTracks
        }
        return otherTracks.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    private var filteredBuses: [MixerBus] {
        if searchText.isEmpty {
            return availableBuses
        }
        return availableBuses.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "link")
                    .foregroundColor(.orange)
                Text("Sidechain Source")
                    .font(.headline)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            Divider()
            
            // Search field
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .textBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // None option
                    sourceButton(
                        title: "None",
                        subtitle: "Disable sidechain",
                        icon: "xmark.circle",
                        isSelected: !currentSource.isEnabled,
                        source: .none
                    )
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    // Tracks section
                    if !filteredTracks.isEmpty {
                        sectionHeader("TRACKS")
                        
                        ForEach(filteredTracks) { track in
                            // Post-fader option
                            sourceButton(
                                title: track.name,
                                subtitle: "Post-fader",
                                icon: track.trackType == .midi ? "pianokeys" : "waveform",
                                iconColor: track.color.color,
                                isSelected: isTrackSelected(track.id, preFader: false),
                                source: .track(trackId: track.id)
                            )
                            
                            // Pre-fader option (indented)
                            sourceButton(
                                title: "  └ Pre-fader",
                                subtitle: nil,
                                icon: "arrow.up.right",
                                iconColor: .secondary,
                                isSelected: isTrackSelected(track.id, preFader: true),
                                source: .trackPreFader(trackId: track.id),
                                isIndented: true
                            )
                        }
                    }
                    
                    // Buses section
                    if !filteredBuses.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                        
                        sectionHeader("BUSES")
                        
                        ForEach(filteredBuses) { bus in
                            sourceButton(
                                title: bus.name,
                                subtitle: nil,
                                icon: "arrow.triangle.branch",
                                iconColor: .purple,  // Default color for buses
                                isSelected: isBusSelected(bus.id),
                                source: .bus(busId: bus.id)
                            )
                        }
                    }
                    
                    // External inputs (if available)
                    // Note: Not yet implemented in AudioEngine
                    /*
                    Divider()
                        .padding(.vertical, 4)
                    
                    sectionHeader("EXTERNAL INPUTS")
                    
                    ForEach(1...2, id: \.self) { channel in
                        sourceButton(
                            title: "Input \(channel)",
                            subtitle: nil,
                            icon: "cable.connector",
                            isSelected: isExternalInputSelected(channel),
                            source: .externalInput(channel: channel)
                        )
                    }
                    */
                }
                .padding(.vertical, 4)
            }
        }
        .frame(width: 240, height: 340)
        .background(Color(.windowBackgroundColor))
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
    
    // MARK: - Source Button
    
    private func sourceButton(
        title: String,
        subtitle: String?,
        icon: String,
        iconColor: Color = .accentColor,
        isSelected: Bool,
        source: SidechainSource,
        isIndented: Bool = false
    ) -> some View {
        Button(action: { onSelect(source) }) {
            HStack(spacing: 8) {
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .accentColor : .secondary.opacity(0.5))
                
                // Icon
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(iconColor)
                    .frame(width: 16)
                
                // Title and subtitle
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, isIndented ? 20 : 12)
            .padding(.vertical, 5)
            .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Selection Helpers
    
    private func isTrackSelected(_ trackId: UUID, preFader: Bool) -> Bool {
        switch currentSource {
        case .track(let id) where !preFader:
            return id == trackId
        case .trackPreFader(let id) where preFader:
            return id == trackId
        default:
            return false
        }
    }
    
    private func isBusSelected(_ busId: UUID) -> Bool {
        if case .bus(let id) = currentSource {
            return id == busId
        }
        return false
    }
    
    private func isExternalInputSelected(_ channel: Int) -> Bool {
        if case .externalInput(let ch) = currentSource {
            return ch == channel
        }
        return false
    }
}

// MARK: - Compact Sidechain Button

/// A small button that shows current sidechain status and opens the picker
struct SidechainButton: View {
    let isEnabled: Bool
    let sourceName: String?
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 3) {
                Image(systemName: isEnabled ? "link.circle.fill" : "link")
                    .font(.system(size: 9))
                    .foregroundColor(isEnabled ? .orange : .secondary.opacity(0.5))
                
                if let name = sourceName, isEnabled {
                    Text(name)
                        .font(.system(size: 8))
                        .foregroundColor(.orange)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(isEnabled ? Color.orange.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(isHovered ? Color.orange.opacity(0.5) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(isEnabled ? "Sidechain: \(sourceName ?? "Unknown")" : "Set sidechain source")
    }
}

// MARK: - Helper Extension

extension SidechainSource {
    /// Get a display name for the source given track and bus lists
    func displayName(tracks: [AudioTrack], buses: [MixerBus]) -> String {
        switch self {
        case .none:
            return "None"
        case .track(let trackId):
            if let track = tracks.first(where: { $0.id == trackId }) {
                return track.name
            }
            return "Track"
        case .trackPreFader(let trackId):
            if let track = tracks.first(where: { $0.id == trackId }) {
                return "\(track.name) (Pre)"
            }
            return "Track (Pre)"
        case .bus(let busId):
            if let bus = buses.first(where: { $0.id == busId }) {
                return bus.name
            }
            return "Bus"
        case .externalInput(let channel):
            return "Input \(channel)"
        }
    }
}
