//
//  ResizeHandle.swift
//  Stori
//
//  Extracted from MainDAWView.swift
//

import SwiftUI

// MARK: - Resizable Panel Handle
struct ResizeHandle: View {
    enum Orientation {
        case horizontal, vertical
    }
    
    let orientation: Orientation
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
         onDragStarted: @escaping () -> Void = {},
         onDrag: @escaping (CGFloat) -> Void) {
        self.orientation = orientation
        self.onDragStarted = onDragStarted
        self.onDrag = onDrag
    }
    
    @State private var isHovered = false
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(isHovered || isDragging ? Color.accentColor.opacity(0.3) : Color(.windowBackgroundColor))
                .animation(.easeInOut(duration: 0.15), value: isHovered)
            
            // Always-visible grip indicator
            if orientation == .horizontal {
                // Horizontal grip dots
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle()
                            .fill(isHovered || isDragging ? Color.accentColor : Color(.separatorColor))
                            .frame(width: 4, height: 4)
                    }
                }
            } else {
                // Vertical grip dots
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
        .cursor(orientation == .vertical ? .resizeLeftRight : .resizeUpDown)
        .onHover { hovering in
            isHovered = hovering
        }
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
