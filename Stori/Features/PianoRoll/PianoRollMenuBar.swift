//
//  PianoRollMenuBar.swift
//  Stori
//
//  Logic Pro-style menu bar for the piano roll editor.
//  Provides Edit, Functions, and View dropdown menus.
//

import SwiftUI

// MARK: - PianoRollMenuBar

/// Logic Pro-style dropdown menu bar for piano roll operations
struct PianoRollMenuBar: View {
    // Selection state
    @Binding var selectedNotes: Set<UUID>
    @Binding var region: MIDIRegion
    
    // View options
    @Binding var showScaleHighlight: Bool
    @Binding var currentScale: Scale
    @Binding var showAutomationLanes: Bool
    @Binding var automationLanes: [AutomationLane]
    @Binding var horizontalZoom: CGFloat
    
    // Sheet triggers
    @Binding var showTransformSheet: Bool
    @Binding var showQuantizeOptions: Bool
    
    // Snap resolution for quantize
    var snapResolution: SnapResolution
    
    // Callbacks
    var onSelectAll: () -> Void
    var onDeselectAll: () -> Void
    var onDeleteSelected: () -> Void
    var onQuantize: () -> Void
    var onLegato: () -> Void
    var onCut: () -> Void
    var onCopy: () -> Void
    var onPaste: () -> Void
    
    var body: some View {
        HStack(spacing: 2) {
            editMenu
            functionsMenu
            viewMenu
        }
    }
    
    // MARK: - Edit Menu
    
    private var editMenu: some View {
        Menu {
            // Undo/Redo (handled by system)
            Button(action: { NSApp.sendAction(#selector(UndoManager.undo), to: nil, from: nil) }) {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: .command)
            
            Button(action: { NSApp.sendAction(#selector(UndoManager.redo), to: nil, from: nil) }) {
                Label("Redo", systemImage: "arrow.uturn.forward")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            
            Divider()
            
            // Cut/Copy/Paste
            Button(action: onCut) {
                Label("Cut", systemImage: "scissors")
            }
            .keyboardShortcut("x", modifiers: .command)
            .disabled(selectedNotes.isEmpty)
            
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)
            .disabled(selectedNotes.isEmpty)
            
            Button(action: onPaste) {
                Label("Paste", systemImage: "doc.on.clipboard")
            }
            .keyboardShortcut("v", modifiers: .command)
            
            Button(role: .destructive, action: onDeleteSelected) {
                Label("Delete", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(selectedNotes.isEmpty)
            
            Divider()
            
            // Selection
            Button(action: onSelectAll) {
                Label("Select All", systemImage: "checkmark.square")
            }
            .keyboardShortcut("a", modifiers: .command)
            
            Button(action: onDeselectAll) {
                Label("Deselect All", systemImage: "square")
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(selectedNotes.isEmpty)
            
        } label: {
            menuLabel("Edit")
        }
        .menuStyle(.borderlessButton)
    }
    
    // MARK: - Functions Menu
    
    private var functionsMenu: some View {
        Menu {
            // Quantize
            Button(action: onQuantize) {
                Label("Quantize to \(snapResolution.rawValue)", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .keyboardShortcut("q", modifiers: [])
            .disabled(selectedNotes.isEmpty)
            
            Button(action: { showQuantizeOptions = true }) {
                Label("Quantize Options...", systemImage: "slider.horizontal.3")
            }
            
            Divider()
            
            // Note operations
            Button(action: onLegato) {
                Label("Legato", systemImage: "arrow.right.to.line")
            }
            .keyboardShortcut("l", modifiers: [])
            .disabled(selectedNotes.isEmpty)
            
            // Velocity submenu
            Menu {
                Button("Set to 127 (fff)") { setSelectedVelocity(127) }
                Button("Set to 100 (f)") { setSelectedVelocity(100) }
                Button("Set to 80 (mf)") { setSelectedVelocity(80) }
                Button("Set to 64 (mp)") { setSelectedVelocity(64) }
                Button("Set to 50 (p)") { setSelectedVelocity(50) }
                Button("Set to 32 (pp)") { setSelectedVelocity(32) }
            } label: {
                Label("Velocity", systemImage: "speedometer")
            }
            .disabled(selectedNotes.isEmpty)
            
            Divider()
            
            // Transform
            Button(action: { showTransformSheet = true }) {
                Label("Transform...", systemImage: "wand.and.stars")
            }
            .disabled(selectedNotes.isEmpty)
            
        } label: {
            menuLabel("Functions")
        }
        .menuStyle(.borderlessButton)
    }
    
    // MARK: - View Menu
    
    private var viewMenu: some View {
        Menu {
            // Scale overlay
            Toggle(isOn: $showScaleHighlight) {
                Label("Scale Overlay", systemImage: "music.note.list")
            }
            
            if showScaleHighlight {
                Menu {
                    ForEach(Scale.allScales, id: \.id) { scale in
                        Button(scale.name) {
                            currentScale = scale
                        }
                    }
                } label: {
                    Label("Scale: \(currentScale.name)", systemImage: "music.quarternote.3")
                }
            }
            
            Divider()
            
            // Automation lanes
            Toggle(isOn: $showAutomationLanes) {
                Label("Automation Lanes", systemImage: "slider.horizontal.3")
            }
            
            // MIDI CC automation lane options (submenu like scales)
            if showAutomationLanes {
                Menu {
                    ForEach(midiCCLaneOptions, id: \.self) { param in
                        Toggle(isOn: Binding(
                            get: { hasLane(for: param) },
                            set: { enabled in toggleLane(for: param, enabled: enabled) }
                        )) {
                            HStack {
                                Image(systemName: param.icon)
                                Text(param.rawValue)
                            }
                        }
                    }
                    
                    Divider()
                    
                    Button(role: .destructive, action: removeAllLanes) {
                        Label("Remove All Lanes", systemImage: "trash")
                    }
                    .disabled(automationLanes.isEmpty)
                } label: {
                    Label("MIDI CC Lanes", systemImage: "slider.horizontal.below.rectangle")
                }
            }
            
            Divider()
            
            // Zoom
            Button(action: { horizontalZoom = min(4.0, horizontalZoom + 0.25) }) {
                Label("Zoom In", systemImage: "plus.magnifyingglass")
            }
            .keyboardShortcut("=", modifiers: .command)
            
            Button(action: { horizontalZoom = max(0.25, horizontalZoom - 0.25) }) {
                Label("Zoom Out", systemImage: "minus.magnifyingglass")
            }
            .keyboardShortcut("-", modifiers: .command)
            
            Button(action: { horizontalZoom = 1.0 }) {
                Label("Zoom to 100%", systemImage: "1.magnifyingglass")
            }
            .keyboardShortcut("0", modifiers: .command)
            
        } label: {
            menuLabel("View")
        }
        .menuStyle(.borderlessButton)
    }
    
    // MARK: - Helpers
    
    private func menuLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.01)) // Invisible but clickable
            .contentShape(Rectangle())
    }
    
    private func setSelectedVelocity(_ velocity: UInt8) {
        for noteId in selectedNotes {
            if let index = region.notes.firstIndex(where: { $0.id == noteId }) {
                region.notes[index].velocity = velocity
            }
        }
    }
    
    // MARK: - Automation Lane Management
    
    /// Available MIDI CC automation parameters for piano roll
    private var midiCCLaneOptions: [AutomationParameter] {
        [
            .pitchBend,
            .midiCC1,    // Mod Wheel
            .midiCC11,   // Expression
            .midiCC64,   // Sustain
            .midiCC74,   // Filter Cutoff
            .midiCC10,   // Pan
            .midiCC7     // Volume
        ]
    }
    
    /// Check if a lane exists for the given parameter
    private func hasLane(for parameter: AutomationParameter) -> Bool {
        automationLanes.contains(where: { $0.parameter == parameter })
    }
    
    /// Toggle a MIDI CC automation lane on/off
    private func toggleLane(for parameter: AutomationParameter, enabled: Bool) {
        if enabled {
            // Add lane if it doesn't exist
            if !hasLane(for: parameter) {
                let newLane = AutomationLane(
                    parameter: parameter,
                    points: [],
                    initialValue: parameter.defaultValue,
                    color: parameter.color
                )
                automationLanes.append(newLane)
            }
        } else {
            // Remove lane
            automationLanes.removeAll(where: { $0.parameter == parameter })
        }
    }
    
    /// Remove all automation lanes
    private func removeAllLanes() {
        automationLanes.removeAll()
    }
}
