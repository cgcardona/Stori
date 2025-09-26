import SwiftUI

struct TrackIconCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icons: [String]

    static let defaultCategories: [TrackIconCategory] = [
        TrackIconCategory(name: "Drums", icons: ["music.quarternote.3", "music.note.list", "metronome", "waveform.path.ecg", "waveform"]),
        TrackIconCategory(name: "Percussion", icons: ["music.note", "waveform.circle", "tuningfork", "speaker.wave.2", "headphones"]),
        TrackIconCategory(name: "Bass", icons: ["waveform", "waveform.path.ecg", "music.quarternote.3", "speaker.wave.3", "music.note.list"]),
        TrackIconCategory(name: "Guitar", icons: ["guitars", "music.note", "waveform", "music.note.list", "headphones"]),
        TrackIconCategory(name: "Keyboards", icons: ["pianokeys", "music.quarternote.3", "waveform.circle", "music.note.list", "metronome"]),
        TrackIconCategory(name: "Strings", icons: ["guitars", "music.quarternote.3", "music.note", "waveform", "headphones"]),
        TrackIconCategory(name: "Wind", icons: ["mic", "mic.fill", "speaker.wave.2", "speaker.wave.3", "music.note.list"]),
        TrackIconCategory(name: "Sound Effects", icons: ["sparkles", "bolt", "flame", "waveform.path.ecg", "music.note"]),
        TrackIconCategory(name: "Other", icons: ["music.note", "music.note.list", "tuningfork", "metronome", "waveform"]),
        TrackIconCategory(name: "Custom Icons", icons: ["star", "heart", "circle", "square", "triangle"])
    ]
}

struct TrackIconPicker: View {
    private let categories: [TrackIconCategory]
    let selectedIcon: String
    let onSelect: (String) -> Void

    @State private var selectedCategoryIndex: Int

    init(selectedIcon: String, onSelect: @escaping (String) -> Void, categories: [TrackIconCategory] = TrackIconCategory.defaultCategories) {
        self.selectedIcon = selectedIcon
        self.onSelect = onSelect
        self.categories = categories

        if let initialIndex = categories.firstIndex(where: { $0.icons.contains(selectedIcon) }) {
            _selectedCategoryIndex = State(initialValue: initialIndex)
        } else {
            _selectedCategoryIndex = State(initialValue: 0)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            categoryList
            Divider()
            iconGrid
        }
        .padding(12)
        .frame(width: 360, height: 260)
    }

    private var categoryList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(categories.enumerated()), id: \.offset) { index, category in
                    Button(action: {
                        selectedCategoryIndex = index
                    }) {
                        HStack {
                            Text(category.name)
                                .font(.system(size: 12, weight: selectedCategoryIndex == index ? .semibold : .regular))
                                .foregroundColor(selectedCategoryIndex == index ? .primary : .secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(selectedCategoryIndex == index ? Color.accentColor.opacity(0.15) : Color.clear)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 130)
    }

    private var iconGrid: some View {
        let icons = categories[selectedCategoryIndex].icons

        return ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                ForEach(icons, id: \.self) { icon in
                    Button(action: {
                        onSelect(icon)
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedIcon == icon ? Color.accentColor : Color.gray.opacity(0.3), lineWidth: selectedIcon == icon ? 1.5 : 1)
                                )

                            Image(systemName: icon)
                                .font(.system(size: 20))
                                .foregroundColor(.primary)
                        }
                        .frame(width: 60, height: 50)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.trailing, 4)
        }
    }
}
