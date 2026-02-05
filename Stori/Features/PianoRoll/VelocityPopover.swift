//
//  VelocityPopover.swift
//  Stori
//
//  On-demand velocity editor popover for the piano roll.
//  Provides slider and quick presets for setting note velocity.
//

import SwiftUI

// MARK: - VelocityPopover

/// Popover for editing velocity of selected notes
struct VelocityPopover: View {
    @Binding var selectedNotes: Set<UUID>
    @Binding var notes: [MIDINote]
    
    @State private var velocityValue: Double = 80
    @State private var hasSetInitial = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "speedometer")
                    .foregroundColor(.accentColor)
                Text("Velocity")
                    .font(.headline)
                Spacer()
                Text("\(Int(velocityValue))")
                    .font(.system(.title2, design: .monospaced))
                    .fontWeight(.semibold)
            }
            
            // Slider
            Slider(value: $velocityValue, in: 1...127, step: 1) { editing in
                if !editing {
                    applyVelocity()
                }
            }
            
            // Quick presets
            HStack(spacing: 8) {
                ForEach(VelocityPreset.allCases, id: \.self) { preset in
                    PresetButton(preset: preset) {
                        velocityValue = Double(preset.value)
                        applyVelocity()
                    }
                }
            }
            
            // Info
            if selectedNotes.isEmpty {
                Text("No notes selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("\(selectedNotes.count) note\(selectedNotes.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .frame(width: 260)
        .onAppear {
            initializeFromSelection()
        }
        .onChange(of: selectedNotes) { _, _ in
            initializeFromSelection()
        }
    }
    
    private func initializeFromSelection() {
        guard !hasSetInitial else { return }
        
        // Get average velocity of selected notes
        let selectedVelocities = notes
            .filter { selectedNotes.contains($0.id) }
            .map { Double($0.velocity) }
        
        if !selectedVelocities.isEmpty {
            velocityValue = selectedVelocities.reduce(0, +) / Double(selectedVelocities.count)
            hasSetInitial = true
        }
    }
    
    private func applyVelocity() {
        let velocity = UInt8(velocityValue)
        for i in notes.indices {
            if selectedNotes.contains(notes[i].id) {
                notes[i].velocity = velocity
            }
        }
    }
}

// MARK: - Velocity Preset

/// Quick velocity presets based on musical dynamics
enum VelocityPreset: String, CaseIterable {
    case pp = "pp"
    case p = "p"
    case mp = "mp"
    case mf = "mf"
    case f = "f"
    case ff = "ff"
    
    var value: UInt8 {
        switch self {
        case .pp: return 20
        case .p: return 45
        case .mp: return 64
        case .mf: return 80
        case .f: return 100
        case .ff: return 120
        }
    }
    
    var fullName: String {
        switch self {
        case .pp: return "Pianissimo"
        case .p: return "Piano"
        case .mp: return "Mezzo-piano"
        case .mf: return "Mezzo-forte"
        case .f: return "Forte"
        case .ff: return "Fortissimo"
        }
    }
}

// MARK: - Preset Button

private struct PresetButton: View {
    let preset: VelocityPreset
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Text(preset.rawValue)
                .font(.system(size: 11, weight: .medium, design: .serif))
                .italic()
                .foregroundColor(isHovered ? .white : .secondary)
                .frame(width: 32, height: 24)
                .background(isHovered ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("\(preset.fullName) (\(preset.value))")
    }
}
