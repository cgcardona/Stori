//
//  ComposerTemplateBuilder.swift
//  Stori
//
//  Template builder UI for crafting optimal AI Composer prompts.
//

import SwiftUI

struct ComposerTemplateBuilder: View {
    @Binding var generatedPrompt: String
    @Binding var isPresented: Bool
    let onGenerate: (String) -> Void
    
    // MARK: - State
    @State private var selectedGenre: String = "Hip-Hop"
    @State private var selectedSubGenre: String = "Lo-Fi"
    @State private var selectedMood: String = "Chill"
    @State private var tempo: Double = 90
    @State private var selectedKey: String = "C minor"
    @State private var selectedInstruments: Set<String> = ["Drums", "Bass"]
    @State private var specificDetails: String = ""
    @State private var chordProgression: String = ""
    
    // MARK: - Options
    
    private let genres = ["Hip-Hop", "Electronic", "Jazz", "R&B", "Pop", "Rock", "Classical", "Ambient", "Funk", "Soul"]
    
    private let subGenres: [String: [String]] = [
        "Hip-Hop": ["Boom Bap", "Lo-Fi", "Trap", "Old School", "Jazz Hop"],
        "Electronic": ["House", "Deep House", "Techno", "Synthwave", "Ambient", "Drum & Bass"],
        "Jazz": ["Smooth Jazz", "Bebop", "Modal", "Fusion", "Latin Jazz"],
        "R&B": ["Neo Soul", "Contemporary", "Classic R&B", "Alternative R&B"],
        "Pop": ["Synth Pop", "Indie Pop", "Dance Pop", "Dream Pop"],
        "Rock": ["Indie Rock", "Alternative", "Progressive", "Classic Rock"],
        "Classical": ["Orchestral", "Piano Solo", "Chamber", "Minimalist"],
        "Ambient": ["Dark Ambient", "Space", "Drone", "Nature"],
        "Funk": ["Classic Funk", "P-Funk", "Electro Funk", "Disco"],
        "Soul": ["Classic Soul", "Northern Soul", "Psychedelic Soul"]
    ]
    
    private let moods = ["Chill", "Energetic", "Melancholic", "Uplifting", "Dark", "Dreamy", "Aggressive", "Romantic", "Mysterious", "Nostalgic"]
    
    private let instruments = ["Drums", "Bass", "Piano", "Rhodes", "Synth", "Guitar", "Strings", "Pad", "Lead", "Organ"]
    
    private let keys = ["C major", "C minor", "D major", "D minor", "E major", "E minor", "F major", "F minor", "G major", "G minor", "A major", "A minor", "B major", "B minor"]
    
    private let chordPresets = [
        "None": "",
        "I-IV-V-I": "I IV V I",
        "ii-V-I": "ii V I",
        "I-V-vi-IV": "I V vi IV",
        "i-VI-III-VII": "i VI III VII",
        "12-Bar Blues": "I I I I IV IV I I V IV I V"
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                
                Spacer()
                
                Text("Build Your Prompt")
                    .font(.headline)
                
                Spacer()
                
                Button("Use Prompt") {
                    onGenerate(buildPrompt())
                    isPresented = false
                }
                .buttonStyle(.plain)
                .foregroundColor(.purple)
                .fontWeight(.semibold)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Genre
                    sectionHeader("Genre")
                    chipSelector(options: genres, selection: $selectedGenre)
                    
                    // Sub-Genre
                    if let subs = subGenres[selectedGenre], !subs.isEmpty {
                        sectionHeader("Style")
                        chipSelector(options: subs, selection: $selectedSubGenre)
                    }
                    
                    // Mood
                    sectionHeader("Mood")
                    chipSelector(options: moods, selection: $selectedMood)
                    
                    // Tempo & Key
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Tempo (BPM)")
                            HStack {
                                Slider(value: $tempo, in: 60...180, step: 5)
                                Text("\(Int(tempo))")
                                    .font(.system(size: 14, weight: .medium))
                                    .frame(width: 40)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Key")
                            Picker("", selection: $selectedKey) {
                                ForEach(keys, id: \.self) { key in
                                    Text(key).tag(key)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 100)
                        }
                    }
                    
                    // Instruments
                    sectionHeader("Instruments (Select Multiple)")
                    multiChipSelector(options: instruments, selection: $selectedInstruments)
                    
                    // Specific Details
                    sectionHeader("Specific Details (Optional)")
                    TextField("e.g., dusty vinyl texture, jazzy 7th chords", text: $specificDetails)
                        .textFieldStyle(.roundedBorder)
                    
                    // Chord Progression
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            sectionHeader("Chord Progression (Optional)")
                            TextField("e.g., Am F C G", text: $chordProgression)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Presets")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Picker("", selection: Binding(
                                get: { chordPresets.first { $0.value == chordProgression }?.key ?? "None" },
                                set: { chordProgression = chordPresets[$0] ?? "" }
                            )) {
                                ForEach(Array(chordPresets.keys.sorted()), id: \.self) { key in
                                    Text(key).tag(key)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 120)
                        }
                    }
                    
                    Divider()
                        .padding(.vertical, 8)
                    
                    // Generated Prompt Preview
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Generated Prompt:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(buildPrompt().count)/500")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Text(buildPrompt())
                            .font(.system(size: 13))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.purple.opacity(0.1))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Generate Button
            Button(action: {
                onGenerate(buildPrompt())
                isPresented = false
            }) {
                HStack {
                    Image(systemName: "wand.and.stars")
                    Text("Generate MIDI")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.purple)
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
            .padding()
        }
        .frame(width: 500, height: 700)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            // Set default sub-genre
            if let subs = subGenres[selectedGenre], !subs.isEmpty {
                selectedSubGenre = subs[0]
            }
        }
        .onChange(of: selectedGenre) { _, newGenre in
            // Update sub-genre when genre changes
            if let subs = subGenres[newGenre], !subs.isEmpty {
                selectedSubGenre = subs[0]
            } else {
                selectedSubGenre = ""
            }
        }
    }
    
    // MARK: - Helpers
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.secondary)
    }
    
    private func chipSelector(options: [String], selection: Binding<String>) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                ChipButton(
                    title: option,
                    isSelected: selection.wrappedValue == option,
                    action: { selection.wrappedValue = option }
                )
            }
        }
    }
    
    private func multiChipSelector(options: [String], selection: Binding<Set<String>>) -> some View {
        FlowLayout(spacing: 8) {
            ForEach(options, id: \.self) { option in
                ChipButton(
                    title: option,
                    isSelected: selection.wrappedValue.contains(option),
                    action: {
                        if selection.wrappedValue.contains(option) {
                            selection.wrappedValue.remove(option)
                        } else {
                            selection.wrappedValue.insert(option)
                        }
                    }
                )
            }
        }
    }
    
    private func buildPrompt() -> String {
        var parts: [String] = []
        
        // Genre and style
        if !selectedSubGenre.isEmpty {
            parts.append("Create a \(selectedMood.lowercased()) \(selectedSubGenre.lowercased()) \(selectedGenre.lowercased()) beat")
        } else {
            parts.append("Create a \(selectedMood.lowercased()) \(selectedGenre.lowercased()) beat")
        }
        
        // Tempo and key
        parts.append("at \(Int(tempo)) BPM in \(selectedKey)")
        
        // Instruments
        if !selectedInstruments.isEmpty {
            let instrumentList = selectedInstruments.sorted().joined(separator: ", ").lowercased()
            parts.append("with \(instrumentList)")
        }
        
        // Chord progression (sanitize in case user edited)
        if !chordProgression.isEmpty {
            parts.append("using \(PromptSanitizer.sanitize(chordProgression)) chord progression")
        }
        
        // Specific details (user free text — sanitize to prevent prompt injection)
        if !specificDetails.isEmpty {
            parts.append(". \(PromptSanitizer.sanitize(specificDetails))")
        }
        
        // Always end with this to ensure complete output
        var prompt = parts.joined(separator: " ")
        prompt += ". Include the actual MIDI notes."
        
        return PromptSanitizer.truncatePrompt(prompt)
    }
}

// MARK: - Chip Button

struct ChipButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.purple : Color(NSColor.controlBackgroundColor))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.clear : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            
            positions.append(CGPoint(x: currentX, y: currentY))
            
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }
        
        return (positions, CGSize(width: maxWidth, height: totalHeight))
    }
}
