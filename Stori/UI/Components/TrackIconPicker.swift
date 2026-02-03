//
//  TrackIconPicker.swift
//  Stori
//
//  Logic-like track icon picker: fixed sidebar (categories) + adaptive icon grid.
//  Paste this file into your project. If you already have your own categories,
//  just pass them into the initializer and remove the defaults if you prefer.
//

import SwiftUI

// MARK: - Model

public struct TrackIconCategory: Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public let icons: [String]
    
    /// All valid track icon names across all categories
    public static var allValidIcons: Set<String> {
        Set(defaults.flatMap { $0.icons })
    }
    
    public static let defaults: [TrackIconCategory] = [
        .init(name: "Instruments", icons: [
            "guitars", "guitars.fill", "pianokeys", "pianokeys.inverse",
            "music.mic", "music.mic.circle", "music.mic.circle.fill",
            "headphones", "headphones.circle", "headphones.circle.fill",
            "hifispeaker", "hifispeaker.fill", "hifispeaker.2", "hifispeaker.2.fill",
            "tuningfork",
            "speaker", "speaker.fill",
            "speaker.wave.2", "speaker.wave.3",
            "speaker.slash", "speaker.slash.fill"
        ]),
        .init(name: "Notes", icons: [
            "music.note", "music.note.list", "music.quarternote.3",
            "music.note.house", "music.note.tv",
            "waveform", "waveform.circle", "waveform.circle.fill",
            "waveform.path", "waveform.path.ecg",
            "music.note.house.fill", "music.note.tv.fill",
            "waveform.and.mic",
            "waveform.badge.mic",
            "waveform.slash"
        ]),
        .init(name: "Effects", icons: [
            "slider.horizontal.3", "slider.vertical.3",
            "sparkles", "wand.and.rays", "wand.and.stars", "wand.and.stars.inverse",
            "bolt", "bolt.fill", "bolt.circle", "bolt.circle.fill",
            "flame", "flame.fill", "metronome", "star", "star.fill",
            "dial.min", "dial.medium", "dial.max",
            "repeat", "repeat.1", "shuffle",
            "ear", "ear.badge.waveform",
            "speaker.wave.2", "speaker.wave.3"
        ])
    ]
}

// MARK: - View

public struct TrackIconPicker: View {
    
    // External API
    public let categories: [TrackIconCategory]
    @Binding public var selectedIcon: String?
    public var onSelect: (String) -> Void
    
    // Internal state
    @State private var selectedCategoryIndex: Int = 0
    
    // Layout
    private let sidebarWidth: CGFloat = 220
    private let tileSize = CGSize(width: 84, height: 72)
    private let gridSpacing: CGFloat = 14
    
    public init(
        categories: [TrackIconCategory] = TrackIconCategory.defaults,
        selectedIcon: Binding<String?>,
        onSelect: @escaping (String) -> Void
    ) {
        self.categories = categories
        self._selectedIcon = selectedIcon
        self.onSelect = onSelect
    }
    
    public var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                categoryList
                    .frame(width: sidebarWidth)
                
                Divider().background(Color.gray.opacity(0.25))
                
                iconGrid
                    .frame(width: proxy.size.width - sidebarWidth)
                    .padding(.horizontal, 16)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)
        }
        // Popover/sheet sizing similar to Logic
        .frame(width: 520, height: 275)
    }
    
    // MARK: Left: Category list
    
    private var categoryList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(categories.enumerated()), id: \.offset) { idx, cat in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedCategoryIndex = idx
                        }
                    } label: {
                        Text(cat.name)
                            .font(.system(size: 14, weight: selectedCategoryIndex == idx ? .semibold : .regular))
                            .foregroundColor(selectedCategoryIndex == idx ? .white : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedCategoryIndex == idx ? Color.accentColor : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
    }
    
    // MARK: Right: Adaptive icon grid
    
    private var iconGrid: some View {
        let icons = categories[safe: selectedCategoryIndex]?.icons ?? []
        // Fixed 3-column layout with consistent spacing
        let columns = Array(repeating: GridItem(.fixed(80), spacing: 16), count: 3)
        
        return ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                ForEach(icons, id: \.self) { iconName in
                    iconTile(iconName)
                }
            }
            .padding(.vertical, 16)
        }
        // Removed grey background to match the white background of the main component
    }
    
    // MARK: Tile
    
    @ViewBuilder
    private func iconTile(_ iconName: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) {
                selectedIcon = iconName
                onSelect(iconName)
            }
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedIcon == iconName ? Color.accentColor
                          : Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedIcon == iconName ? Color.accentColor.opacity(0.6)
                                    : Color.gray.opacity(0.25),
                                    lineWidth: selectedIcon == iconName ? 2 : 1)
                    )
                    .shadow(color: selectedIcon == iconName ? Color.accentColor.opacity(0.25) : .clear,
                            radius: 4, x: 0, y: 2)
                
                // Use SF Symbols by default. Swap this with Image(iconName) if you store assets.
                Image(systemName: iconName)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(selectedIcon == iconName ? .white : .primary)
                    .padding(.bottom, 1)
            }
            .frame(width: tileSize.width, height: tileSize.height)
        }
        .buttonStyle(HoverButtonStyle())
        .help(iconName)
    }
}

// MARK: - Button Style

struct HoverButtonStyle: ButtonStyle {
    @State private var isHovering = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : (isHovering ? 1.05 : 1.0))
            .opacity(configuration.isPressed ? 0.8 : (isHovering ? 0.9 : 1.0))
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

// MARK: - Helpers

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
