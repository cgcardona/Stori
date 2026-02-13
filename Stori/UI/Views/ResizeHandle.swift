//
//  ResizeHandle.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - Optional Accessibility Modifier
private struct OptionalAccessibilityModifier: ViewModifier {
    let identifier: String?
    let label: String?
    let hint: String?

    func body(content: Content) -> some View {
        content
            .accessibilityIdentifier(identifier ?? "")
            .accessibilityLabel(label ?? "")
            .accessibilityHint(hint ?? "")
    }
}

// MARK: - Resizable Panel Handle
struct ResizeHandle: View {
    enum Orientation {
        case horizontal, vertical
    }

    let orientation: Orientation
    var accessibilityIdentifier: String?
    var accessibilityLabel: String?
    var accessibilityHint: String?
    /// Called once when the drag gesture begins.
    let onDragStarted: () -> Void
    /// Called on every drag movement with the **cumulative** delta from
    /// the gesture start. Callers should use a captured start-value
    /// (snapshotted in `onDragStarted`) so they never depend on reading
    /// back the current model value mid-drag.
    let onDrag: (CGFloat) -> Void

    /// Convenience initialiser that omits `onDragStarted` for call sites
    /// that don't need it (e.g. the inspector width handle).
    init(orientation: Orientation,
         accessibilityIdentifier: String? = nil,
         accessibilityLabel: String? = nil,
         accessibilityHint: String? = nil,
         onDragStarted: @escaping () -> Void = {},
         onDrag: @escaping (CGFloat) -> Void) {
        self.orientation = orientation
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.onDragStarted = onDragStarted
        self.onDrag = onDrag
    }
    
    @State private var isHovered = false
    @State private var isDragging = false
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Background (semantic colors for high-contrast compatibility)
            Rectangle()
                .fill(isHovered || isDragging ? Color.accentColor.opacity(0.3) : Color(.windowBackgroundColor))
                .animation(.easeInOut(duration: 0.15), value: isHovered)

            // Always-visible grip indicator (separatorColor/accentColor adapt to Increase Contrast)
            if orientation == .horizontal {
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle()
                            .fill(isHovered || isDragging ? Color.accentColor : Color(.separatorColor))
                            .frame(width: 4, height: 4)
                    }
                }
            } else {
                VStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle()
                            .fill(isHovered || isDragging ? Color.accentColor : Color(.separatorColor))
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
        .frame(
            width: orientation == .vertical ? 10 : nil,
            height: orientation == .horizontal ? 10 : nil
        )
        .contentShape(Rectangle())
        .overlay(
            // High-contrast: always-visible border so handle bounds are clear (Increase Contrast / Reduce Transparency)
            Rectangle()
                .strokeBorder(Color(.separatorColor), lineWidth: 1)
        )
        .overlay(
            // Focus order: visible focus ring when handle has keyboard focus (Tab navigation)
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isFocused ? 1 : 0)
        )
        .focusable(true)
        .focused($isFocused)
        .cursor(orientation == .vertical ? .resizeLeftRight : .resizeUpDown)
        .onHover { hovering in
            isHovered = hovering
        }
        .modifier(OptionalAccessibilityModifier(
            identifier: accessibilityIdentifier,
            label: accessibilityLabel,
            hint: accessibilityHint
        ))
        .gesture(
            // IMPORTANT: Use .global coordinate space. The handle lives
            // inside the panel it resizes. With the default .local space,
            // each height change shifts the coordinate origin, corrupting
            // the cumulative translation and causing oscillation / jitter.
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        onDragStarted()
                    }
                    let delta = orientation == .vertical ? value.translation.width : value.translation.height
                    onDrag(delta)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}

// MARK: - Custom Cursor Extension for Resize Handles
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { isHovered in
            if isHovered {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Custom Cursors
extension NSCursor {
    /// Custom loop/repeat cursor using SF Symbol
    static var loop: NSCursor {
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        guard let symbolImage = NSImage(systemSymbolName: "arrow.circlepath", accessibilityDescription: "Loop")?
            .withSymbolConfiguration(config) else {
            return .crosshair
        }
        
        let hotSpot = NSPoint(x: symbolImage.size.width / 2, y: symbolImage.size.height / 2)
        return NSCursor(image: symbolImage, hotSpot: hotSpot)
    }
    
    /// Custom regenerate cursor for AI-generated regions
    static var regenerate: NSCursor {
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        guard let symbolImage = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Regenerate")?
            .withSymbolConfiguration(config) else {
            return .crosshair
        }
        
        let hotSpot = NSPoint(x: symbolImage.size.width / 2, y: symbolImage.size.height / 2)
        return NSCursor(image: symbolImage, hotSpot: hotSpot)
    }
}
