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
    let onDrag: (CGFloat) -> Void
    
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
            DragGesture()
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
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
