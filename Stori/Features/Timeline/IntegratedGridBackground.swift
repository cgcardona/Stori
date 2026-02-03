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
    let pixelsPerBeat: CGFloat  // Beat-based timeline
    let trackCount: Int
    
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
        let pixelsPerBar = pixelsPerBeat * 4  // 4/4
        let totalBeats = Int(ceil(contentSize.width / pixelsPerBeat))
        
        // Vertical grid lines (every bar = 4 beats)
        for beat in stride(from: 0, through: totalBeats, by: 4) {
            let x = CGFloat(beat) * pixelsPerBeat
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
