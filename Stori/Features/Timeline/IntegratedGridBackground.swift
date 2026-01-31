//
//  IntegratedGridBackground.swift
//  Stori
//
//  Extracted from IntegratedTimelineView.swift
//  Contains the grid background view for the timeline
//

import SwiftUI

// MARK: - Integrated Grid Background

struct IntegratedGridBackground: View {
    let contentSize: CGSize
    let trackHeight: CGFloat
    let pixelsPerBeat: CGFloat  // Beat-based timeline (proper DAW architecture)
    let trackCount: Int
    let tempo: Double  // For beat→seconds conversion when needed
    
    // Derived for time-mode display
    private var secondsPerBeat: Double { 60.0 / tempo }
    private var pixelsPerSecond: CGFloat { pixelsPerBeat / CGFloat(secondsPerBeat) }
    
    // Unique ID for forcing Canvas redraw when zoom changes
    private var zoomId: String {
        "\(pixelsPerBeat)-\(trackHeight)-\(contentSize.width)-\(contentSize.height)"
    }
    
    var body: some View {
        Canvas { context, size in
            drawGrid(context: context, size: size)
        }
        .id(zoomId)  // Force redraw when zoom changes
        .frame(width: contentSize.width, height: contentSize.height)
    }
    
    private func drawGrid(context: GraphicsContext, size: CGSize) {
        let totalSeconds = Int(contentSize.width / pixelsPerSecond)
        
        // Vertical grid lines (every 5 seconds)
        for second in stride(from: 0, through: totalSeconds, by: 5) {
            let x = CGFloat(second) * pixelsPerSecond
            let path = Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
        }
        
        // Horizontal grid lines (track separators)
        for trackIndex in 0...trackCount {
            let y = CGFloat(trackIndex) * trackHeight
            let path = Path { path in
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
        }
    }
}
