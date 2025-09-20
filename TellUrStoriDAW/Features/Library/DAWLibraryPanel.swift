//
//  DAWLibraryPanel.swift
//  TellUrStoriDAW
//
//  Professional DAW library panel for sounds, loops, and instruments
//

import SwiftUI

struct DAWLibraryPanel: View {
    @State private var selectedCategory: LibraryCategory = .sounds
    @State private var searchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Library")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "plus")
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .help("Add to Library")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.controlBackgroundColor))
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                
                TextField("Search library...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlColor))
            .cornerRadius(6)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            
            // Category tabs
            HStack(spacing: 0) {
                ForEach(LibraryCategory.allCases, id: \.self) { category in
                    Button(action: {
                        selectedCategory = category
                    }) {
                        Text(category.displayName)
                            .font(.system(size: 11))
                            .foregroundColor(selectedCategory == category ? .primary : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.controlBackgroundColor))
            
            Divider()
            
            // Content area
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(libraryItems, id: \.id) { item in
                        LibraryItemRow(item: item)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            
            Spacer()
        }
        .background(Color(.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(width: 1)
                .foregroundColor(Color(.separatorColor)),
            alignment: .trailing
        )
    }
    
    private var libraryItems: [LibraryItem] {
        // Sample library items based on selected category
        switch selectedCategory {
        case .sounds:
            return [
                LibraryItem(id: UUID(), name: "Kick Drum 01", type: .audio, duration: "0:02"),
                LibraryItem(id: UUID(), name: "Snare Tight", type: .audio, duration: "0:01"),
                LibraryItem(id: UUID(), name: "Hi-Hat Closed", type: .audio, duration: "0:01"),
                LibraryItem(id: UUID(), name: "Bass Drop", type: .audio, duration: "0:03"),
                LibraryItem(id: UUID(), name: "Vocal Chop", type: .audio, duration: "0:02")
            ]
        case .loops:
            return [
                LibraryItem(id: UUID(), name: "House Beat 120", type: .loop, duration: "0:08"),
                LibraryItem(id: UUID(), name: "Trap Loop 140", type: .loop, duration: "0:04"),
                LibraryItem(id: UUID(), name: "Jazz Drums", type: .loop, duration: "0:16"),
                LibraryItem(id: UUID(), name: "Ambient Pad", type: .loop, duration: "0:32")
            ]
        case .instruments:
            return [
                LibraryItem(id: UUID(), name: "Classic Piano", type: .instrument, duration: ""),
                LibraryItem(id: UUID(), name: "Analog Synth", type: .instrument, duration: ""),
                LibraryItem(id: UUID(), name: "Electric Guitar", type: .instrument, duration: ""),
                LibraryItem(id: UUID(), name: "Strings Section", type: .instrument, duration: "")
            ]
        }
    }
}

// MARK: - Library Category
enum LibraryCategory: CaseIterable {
    case sounds, loops, instruments
    
    var displayName: String {
        switch self {
        case .sounds: return "Sounds"
        case .loops: return "Loops"
        case .instruments: return "Instruments"
        }
    }
}

// MARK: - Library Item
struct LibraryItem: Identifiable {
    let id: UUID
    let name: String
    let type: LibraryItemType
    let duration: String
}

enum LibraryItemType {
    case audio, loop, instrument
    
    var iconName: String {
        switch self {
        case .audio: return "waveform"
        case .loop: return "repeat"
        case .instrument: return "pianokeys"
        }
    }
}

// MARK: - Library Item Row
struct LibraryItemRow: View {
    let item: LibraryItem
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: item.type.iconName)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 16)
            
            // Name and duration
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if !item.duration.isEmpty {
                    Text(item.duration)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Play button (on hover)
            if isHovered {
                Button(action: {}) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Preview")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color(.controlAccentColor).opacity(0.1) : Color.clear)
        .cornerRadius(6)
        .onHover { hovering in
            isHovered = hovering
        }
        .draggable(item.name) {
            Text(item.name)
                .padding(8)
                .background(Color(.controlBackgroundColor))
                .cornerRadius(6)
        }
    }
}
