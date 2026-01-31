//
//  AutomationCurveOverlay.swift
//  Stori
//
//  Extracted from IntegratedTimelineView.swift
//  Contains the automation curve overlay view
//

import SwiftUI

// MARK: - Automation Curve Overlay

/// Draws automation curve directly on top of the track content
struct AutomationCurveOverlay: View {
    let lane: AutomationLane
    let pixelsPerBeat: CGFloat  // Beat-based timeline (proper DAW architecture)
    let trackHeight: CGFloat
    let duration: TimeInterval  // Duration in beats
    let currentTrackValue: Float  // Current slider value (e.g., volume) to show when no points
    var onAddPoint: ((Double, Float) -> Void)?  // Callback to add point at (beat, value)
    var onUpdatePoint: ((UUID, Double, Float) -> Void)?  // Callback to update point position/value
    var onDeletePoint: ((UUID) -> Void)?  // Callback to delete a point
    
    // Track which point is being dragged and its live position
    @State private var draggingPointId: UUID? = nil
    @State private var dragLiveBeat: Double = 0
    @State private var dragLiveValue: Float = 0
    
    // Get effective points (with live drag position applied)
    private func effectivePoints() -> [AutomationPoint] {
        lane.points.map { point in
            if point.id == draggingPointId {
                var modified = point
                modified.beat = dragLiveBeat
                modified.value = dragLiveValue
                return modified
            }
            return point
        }.sorted { $0.beat < $1.beat }
    }
    
    // Format value as dB for volume parameter
    private func formatValue(_ value: Float) -> String {
        switch lane.parameter {
        case .volume:
            let db = value > 0.001 ? 20 * log10(value) : -60
            return String(format: "%+.1f dB", db)
        case .pan:
            let panValue = (value - 0.5) * 2
            if abs(panValue) < 0.05 { return "C" }
            return panValue < 0 ? String(format: "L%.0f", abs(panValue * 100)) : String(format: "R%.0f", panValue * 100)
        default:
            return String(format: "%.0f%%", value * 100)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let points = effectivePoints()
            
            ZStack(alignment: .topLeading) {
                // Semi-transparent automation background tint
                Rectangle()
                    .fill(lane.color.opacity(0.08))
                
                // When NO points: show dashed baseline at slider value
                // When points exist: the curve IS the automation (no separate baseline)
                if points.isEmpty {
                    baselinePath(in: geometry)
                        .stroke(lane.color.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    
                    // Label at left edge showing slider value
                    Text(formatValue(currentTrackValue))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(lane.color.opacity(0.8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.3))
                        .cornerRadius(3)
                        .offset(x: 4, y: yPositionForValue(currentTrackValue, in: geometry) - 10)
                } else {
                    // Curve fill (semi-transparent)
                    curveFillPath(points: points, in: geometry)
                        .fill(lane.color.opacity(0.15))
                    
                    // Curve stroke - THIS is the automation line
                    curveStrokePath(points: points, in: geometry)
                        .stroke(lane.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                
                // Draggable breakpoints with value labels
                ForEach(lane.points) { point in
                    let isActive = draggingPointId == point.id
                    let effectivePoint = isActive ? AutomationPoint(id: point.id, beat: dragLiveBeat, value: dragLiveValue, curve: point.curve) : point
                    let pos = pointPosition(effectivePoint, in: geometry)
                    
                    // Value label next to point
                    Text(formatValue(effectivePoint.value))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(lane.color.opacity(0.8))
                        .cornerRadius(2)
                        .position(x: pos.x + 25, y: pos.y)
                    
                    // The breakpoint circle
                    Circle()
                        .fill(isActive ? lane.color.opacity(0.9) : lane.color)
                        .frame(width: isActive ? 14 : 10, height: isActive ? 14 : 10)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: isActive ? 2 : 1)
                        )
                        .shadow(color: isActive ? lane.color.opacity(0.6) : .clear, radius: 4)
                        .position(pos)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    draggingPointId = point.id
                                    let newX = point.beat * pixelsPerBeat + value.translation.width
                                    let newY = geometry.size.height * (1 - CGFloat(point.value)) + value.translation.height
                                    dragLiveBeat = max(0, Double(newX / pixelsPerBeat))
                                    dragLiveValue = max(0, min(1, Float(1 - (newY / geometry.size.height))))
                                }
                                .onEnded { _ in
                                    // Commit the change
                                    onUpdatePoint?(point.id, dragLiveBeat, dragLiveValue)
                                    draggingPointId = nil
                                }
                        )
                        .contextMenu {
                            Button(role: .destructive) {
                                onDeletePoint?(point.id)
                            } label: {
                                Label("Delete Point", systemImage: "trash")
                            }
                        }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                // Click to add a point
                let beat = Double(location.x / pixelsPerBeat)
                let value = Float(1 - (location.y / geometry.size.height))
                let clampedValue = max(0, min(1, value))
                onAddPoint?(beat, clampedValue)
            }
        }
    }
    
    /// Baseline path at the current track value - syncs with slider
    private func baselinePath(in geometry: GeometryProxy) -> Path {
        Path { path in
            let y = yPositionForValue(currentTrackValue, in: geometry)
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: geometry.size.width, y: y))
        }
    }
    
    private func curveStrokePath(points: [AutomationPoint], in geometry: GeometryProxy) -> Path {
        Path { path in
            guard !points.isEmpty, let first = points.first, let last = points.last else { return }
            
            let firstPos = pointPosition(first, in: geometry)
            let lastPos = pointPosition(last, in: geometry)
            let width = geometry.size.width
            let sliderY = yPositionForValue(currentTrackValue, in: geometry)
            
            // Start at left edge at SLIDER value (baseline before first point follows slider)
            path.move(to: CGPoint(x: 0, y: sliderY))
            
            // Line to first point
            path.addLine(to: firstPos)
            
            // Draw through all points
            for i in 1..<points.count {
                addCurveSegment(from: points[i-1], to: points[i], in: geometry, to: &path)
            }
            
            // Extend right to the edge at LAST POINT's value (stays at final automation level)
            path.addLine(to: CGPoint(x: width, y: lastPos.y))
        }
    }
    
    private func curveFillPath(points: [AutomationPoint], in geometry: GeometryProxy) -> Path {
        Path { path in
            guard !points.isEmpty, let first = points.first, let last = points.last else { return }
            
            let firstPos = pointPosition(first, in: geometry)
            let lastPos = pointPosition(last, in: geometry)
            let width = geometry.size.width
            let height = geometry.size.height
            let sliderY = yPositionForValue(currentTrackValue, in: geometry)
            
            // Start at bottom-left corner
            path.move(to: CGPoint(x: 0, y: height))
            
            // Go up to SLIDER value (baseline before first point follows slider)
            path.addLine(to: CGPoint(x: 0, y: sliderY))
            
            // Line to first point
            path.addLine(to: firstPos)
            
            // Draw through all points
            for i in 1..<points.count {
                addCurveSegment(from: points[i-1], to: points[i], in: geometry, to: &path)
            }
            
            // Extend right to the edge at LAST POINT's value (stays at final automation level)
            path.addLine(to: CGPoint(x: width, y: lastPos.y))
            
            // Go down to bottom-right corner
            path.addLine(to: CGPoint(x: width, y: height))
            
            // Close back to bottom-left
            path.closeSubpath()
        }
    }
    
    private func addCurveSegment(from p1: AutomationPoint, to p2: AutomationPoint, in geometry: GeometryProxy, to path: inout Path) {
        let pos1 = pointPosition(p1, in: geometry)
        let pos2 = pointPosition(p2, in: geometry)
        
        switch p1.curve {
        case .linear:
            path.addLine(to: pos2)
        case .smooth:
            let controlX = (pos1.x + pos2.x) / 2
            path.addCurve(to: pos2, control1: CGPoint(x: controlX, y: pos1.y), control2: CGPoint(x: controlX, y: pos2.y))
        case .step:
            path.addLine(to: CGPoint(x: pos2.x, y: pos1.y))
            path.addLine(to: pos2)
        case .exponential:
            let controlX = pos1.x + (pos2.x - pos1.x) * 0.8
            path.addQuadCurve(to: pos2, control: CGPoint(x: controlX, y: pos1.y))
        case .logarithmic:
            let controlX = pos1.x + (pos2.x - pos1.x) * 0.2
            path.addQuadCurve(to: pos2, control: CGPoint(x: controlX, y: pos2.y))
        case .sCurve:
            let controlX1 = pos1.x + (pos2.x - pos1.x) * 0.25
            let controlX2 = pos1.x + (pos2.x - pos1.x) * 0.75
            path.addCurve(to: pos2, control1: CGPoint(x: controlX1, y: pos1.y), control2: CGPoint(x: controlX2, y: pos2.y))
        }
    }
    
    private func pointPosition(_ point: AutomationPoint, in geometry: GeometryProxy) -> CGPoint {
        let x = point.beat * pixelsPerBeat
        let y = yPositionForValue(point.value, in: geometry)
        return CGPoint(x: x, y: y)
    }
    
    private func yPositionForValue(_ value: Float, in geometry: GeometryProxy) -> CGFloat {
        // Invert Y: value 1.0 = top, value 0.0 = bottom
        geometry.size.height * (1 - CGFloat(value))
    }
}
