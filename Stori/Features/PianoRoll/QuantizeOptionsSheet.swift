//
//  QuantizeOptionsSheet.swift
//  Stori
//
//  Quantize options sheet for the piano roll editor.
//  Allows adjusting quantize strength and swing.
//

import SwiftUI

// MARK: - QuantizeOptionsSheet

/// Sheet for configuring quantize options before applying
struct QuantizeOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    @Binding var resolution: SnapResolution
    @Binding var strength: Double  // 0-100
    @Binding var swing: Double     // 0-100
    
    var selectedNoteCount: Int
    var onQuantize: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Quantize Options")
                        .font(.headline)
                    Text("\(selectedNoteCount) note\(selectedNoteCount == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Divider()
            
            // Resolution picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Resolution")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Picker("", selection: $resolution) {
                    ForEach(SnapResolution.allCases, id: \.self) { res in
                        Text(res.rawValue).tag(res)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }
            
            // Strength slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Strength")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(strength))%")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.primary)
                }
                
                Slider(value: $strength, in: 0...100, step: 1)
                
                Text("100% = Full quantize, 50% = Halfway to grid")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Swing slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Swing")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(swing))%")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.primary)
                }
                
                Slider(value: $swing, in: 0...100, step: 1)
                
                Text("Shifts off-beat notes for groove feel")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Divider()
            
            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                
                Spacer()
                
                Button("Apply Quantize") {
                    onQuantize()
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(selectedNoteCount == 0)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}

// MARK: - Quantize Presets

/// Quick quantize presets
enum QuantizePreset: String, CaseIterable {
    case full = "Full (100%)"
    case tight = "Tight (75%)"
    case loose = "Loose (50%)"
    case gentle = "Gentle (25%)"
    
    var strength: Double {
        switch self {
        case .full: return 100
        case .tight: return 75
        case .loose: return 50
        case .gentle: return 25
        }
    }
}
