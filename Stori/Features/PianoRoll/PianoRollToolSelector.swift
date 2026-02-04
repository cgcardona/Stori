//
//  PianoRollToolSelector.swift
//  Stori
//
//  Logic Pro-style icon-only tool selector for the piano roll editor.
//  Provides compact tool buttons with keyboard shortcuts.
//

import SwiftUI

// MARK: - PianoRollToolSelector

/// Icon-only tool selector for piano roll editing tools
struct PianoRollToolSelector: View {
    @Binding var selection: PianoRollEditMode
    
    /// Tools to display in the toolbar (subset of all modes)
    /// Legato and Velocity are moved to Functions menu
    private let toolbarModes: [PianoRollEditMode] = [
        .select, .draw, .erase, .slice, .glue, .brush
    ]
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(toolbarModes, id: \.self) { mode in
                ToolButton(
                    mode: mode,
                    isSelected: selection == mode,
                    action: { selection = mode }
                )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

// MARK: - Tool Button

/// Individual tool button with icon and hover state
private struct ToolButton: View {
    let mode: PianoRollEditMode
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: mode.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(foregroundColor)
                .frame(width: 26, height: 22)
                .background(backgroundColor)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("\(mode.rawValue) (\(mode.shortcut))")
    }
    
    private var foregroundColor: Color {
        if isSelected {
            return .white
        } else if isHovered {
            return .primary
        } else {
            return .secondary
        }
    }
    
    private var backgroundColor: Color {
        if isSelected {
            return Color.accentColor
        } else if isHovered {
            return Color(nsColor: .controlBackgroundColor)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Keyboard Shortcut Handler

/// View modifier to handle tool keyboard shortcuts
struct ToolShortcutHandler: ViewModifier {
    @Binding var editMode: PianoRollEditMode
    
    func body(content: Content) -> some View {
        content
            .onKeyPress(.init("v")) { editMode = .select; return .handled }
            .onKeyPress(.init("p")) { editMode = .draw; return .handled }
            .onKeyPress(.init("e")) { editMode = .erase; return .handled }
            .onKeyPress(.init("s")) { editMode = .slice; return .handled }
            .onKeyPress(.init("g")) { editMode = .glue; return .handled }
            .onKeyPress(.init("b")) { editMode = .brush; return .handled }
            .onKeyPress(.init("l")) { editMode = .legato; return .handled }
            .onKeyPress(.init("u")) { editMode = .velocity; return .handled }
    }
}

extension View {
    /// Adds keyboard shortcut handling for piano roll tools
    func toolShortcuts(editMode: Binding<PianoRollEditMode>) -> some View {
        modifier(ToolShortcutHandler(editMode: editMode))
    }
}
