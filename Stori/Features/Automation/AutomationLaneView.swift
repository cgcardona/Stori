//
//  AutomationLaneView.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  Automation lane UI for parameter automation.
//  Features breakpoint editing, curve types, and real-time visualization.
//
//  Models are defined in Core/Models/AutomationModels.swift
//

import SwiftUI

// MARK: - AutomationLaneView

struct AutomationLaneView: View {
    @Binding var lane: AutomationLane
    let duration: TimeInterval
    let pixelsPerBeat: CGFloat
    let height: CGFloat
    
    @State private var selectedPoints: Set<UUID> = []
    @State private var isDrawing = false
    @State private var selectedCurveType: CurveType = .linear
    
    var body: some View {
        VStack(spacing: 0) {
            // Lane header
            laneHeader
            
            // Automation curve
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    
                    // Grid lines
                    gridLines(in: geometry)
                    
                    // Curve path (filled)
                    curveFill(in: geometry)
                    
                    // Curve path (stroke)
                    curveStroke(in: geometry)
                    
                    // Breakpoints
                    breakpoints(in: geometry)
                }
                .contentShape(Rectangle())
                .gesture(drawGesture(in: geometry))
            }
            .frame(height: height)
        }
        .opacity(lane.isVisible ? 1 : 0.5)
    }
    
    // MARK: - Lane Header
    
    private var laneHeader: some View {
        HStack(spacing: 8) {
            // Visibility toggle
            Button(action: { lane.isVisible.toggle() }) {
                Image(systemName: lane.isVisible ? "eye" : "eye.slash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            // Parameter icon and name
            HStack(spacing: 4) {
                Image(systemName: lane.parameter.icon)
                    .foregroundColor(lane.color)
                
                Text(lane.parameter.rawValue)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            
            Spacer()
            
            // Curve type selector
            Picker("", selection: $selectedCurveType) {
                ForEach(CurveType.allCases, id: \.self) { type in
                    Image(systemName: type.icon).tag(type)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            
            // Lock toggle
            Button(action: { lane.isLocked.toggle() }) {
                Image(systemName: lane.isLocked ? "lock.fill" : "lock.open")
                    .foregroundColor(lane.isLocked ? .orange : .secondary)
            }
            .buttonStyle(.plain)
            
            // Clear button
            Button(action: clearLane) {
                Image(systemName: "trash")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(lane.isLocked)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Grid Lines
    
    private func gridLines(in geometry: GeometryProxy) -> some View {
        Canvas { context, size in
            // Horizontal lines at 25%, 50%, 75%
            for fraction in [0.25, 0.5, 0.75] {
                let y = size.height * (1 - CGFloat(fraction))
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
            }
            
            // Vertical beat lines
            var x: CGFloat = 0
            while x < size.width {
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                context.stroke(path, with: .color(.gray.opacity(0.1)), lineWidth: 0.5)
                x += pixelsPerBeat
            }
        }
    }
    
    // MARK: - Curve Drawing
    
    private func curveFill(in geometry: GeometryProxy) -> some View {
        Path { path in
            guard !lane.points.isEmpty else { return }
            
            let sortedPoints = lane.points.sorted { $0.beat < $1.beat }
            
            // Start from bottom left
            path.move(to: CGPoint(x: 0, y: geometry.size.height))
            
            // Line to first point's x at bottom
            if let first = sortedPoints.first {
                let x = first.beat * pixelsPerBeat
                path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                path.addLine(to: pointPosition(first, in: geometry))
            }
            
            // Draw through all points
            for i in 1..<sortedPoints.count {
                addCurveSegment(from: sortedPoints[i-1], to: sortedPoints[i], in: geometry, to: &path)
            }
            
            // Close to bottom
            if let last = sortedPoints.last {
                let lastPos = pointPosition(last, in: geometry)
                path.addLine(to: CGPoint(x: lastPos.x, y: geometry.size.height))
            }
            
            path.closeSubpath()
        }
        .fill(lane.color.opacity(0.15))
    }
    
    private func curveStroke(in geometry: GeometryProxy) -> some View {
        Path { path in
            guard !lane.points.isEmpty else { return }
            
            let sortedPoints = lane.points.sorted { $0.beat < $1.beat }
            
            if let first = sortedPoints.first {
                path.move(to: pointPosition(first, in: geometry))
            }
            
            for i in 1..<sortedPoints.count {
                addCurveSegment(from: sortedPoints[i-1], to: sortedPoints[i], in: geometry, to: &path)
            }
        }
        .stroke(lane.color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }
    
    private func addCurveSegment(from p1: AutomationPoint, to p2: AutomationPoint, in geometry: GeometryProxy, to path: inout Path) {
        let pos1 = pointPosition(p1, in: geometry)
        let pos2 = pointPosition(p2, in: geometry)
        
        switch p1.curve {
        case .linear:
            path.addLine(to: pos2)
        case .smooth:
            let controlX = (pos1.x + pos2.x) / 2
            path.addCurve(
                to: pos2,
                control1: CGPoint(x: controlX, y: pos1.y),
                control2: CGPoint(x: controlX, y: pos2.y)
            )
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
        let y = geometry.size.height * (1 - CGFloat(point.value))
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Breakpoints
    
    private func breakpoints(in geometry: GeometryProxy) -> some View {
        ForEach(lane.points) { point in
            let position = pointPosition(point, in: geometry)
            let isSelected = selectedPoints.contains(point.id)
            
            BreakpointView(
                point: point,
                isSelected: isSelected,
                color: lane.color,
                onSelect: { selectedPoints = [point.id] },
                onMove: { newBeat, newValue in
                    guard !lane.isLocked else { return }
                    updatePoint(point.id, beat: newBeat, value: newValue)
                },
                onDelete: {
                    guard !lane.isLocked else { return }
                    deletePoint(point.id)
                }
            )
            .position(position)
        }
    }
    
    // MARK: - Gestures
    
    private func drawGesture(in geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard !lane.isLocked else { return }
                
                let beat = value.location.x / pixelsPerBeat
                let normalizedValue = Float(1 - value.location.y / geometry.size.height)
                
                if isDrawing {
                    // Update or add point
                    addOrUpdatePoint(atBeat: beat, value: normalizedValue)
                } else {
                    isDrawing = true
                    addPoint(atBeat: beat, value: normalizedValue)
                }
            }
            .onEnded { _ in
                isDrawing = false
            }
    }
    
    // MARK: - Point Management
    
    private func addPoint(atBeat beat: Double, value: Float) {
        let newPoint = AutomationPoint(
            beat: max(0, beat),
            value: max(0, min(1, value)),
            curve: selectedCurveType
        )
        lane.points.append(newPoint)
        selectedPoints = [newPoint.id]
    }
    
    private func addOrUpdatePoint(atBeat beat: Double, value: Float) {
        // Find existing point near this beat
        let threshold = 0.1 // beats
        if let existingIndex = lane.points.firstIndex(where: { abs($0.beat - beat) < threshold }) {
            lane.points[existingIndex].value = max(0, min(1, value))
        } else {
            addPoint(atBeat: beat, value: value)
        }
    }
    
    private func updatePoint(_ id: UUID, beat: Double, value: Float) {
        if let index = lane.points.firstIndex(where: { $0.id == id }) {
            lane.points[index].beat = max(0, beat)
            lane.points[index].value = max(0, min(1, value))
        }
    }
    
    private func deletePoint(_ id: UUID) {
        lane.points.removeAll { $0.id == id }
        selectedPoints.remove(id)
    }
    
    private func clearLane() {
        lane.points.removeAll()
        selectedPoints.removeAll()
    }
}

// MARK: - BreakpointView

struct BreakpointView: View {
    let point: AutomationPoint
    let isSelected: Bool
    let color: Color
    let onSelect: () -> Void
    let onMove: (Double, Float) -> Void  // (beat, value)
    let onDelete: () -> Void
    
    @State private var isDragging = false
    
    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .fill(color)
                .frame(width: isSelected ? 14 : 10, height: isSelected ? 14 : 10)
                .shadow(color: color.opacity(0.5), radius: isDragging ? 4 : 2)
            
            // Inner dot
            Circle()
                .fill(isSelected ? Color.white : color.opacity(0.8))
                .frame(width: 6, height: 6)
            
            // Curve type indicator
            if isSelected {
                Image(systemName: point.curve.icon)
                    .font(.system(size: 8))
                    .foregroundColor(.white)
                    .offset(y: -16)
            }
        }
        .gesture(dragGesture)
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Delete", role: .destructive, action: onDelete)
            Divider()
            Text("Beat: \(String(format: "%.2f", point.beat))")
            Text("Value: \(Int(point.value * 100))%")
        }
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                // Note: In real implementation, would convert translation to time/value
            }
            .onEnded { _ in
                isDragging = false
            }
    }
}

// MARK: - AutomationEditorView

/// Full automation editor with multiple lanes
struct AutomationEditorView: View {
    @Binding var lanes: [AutomationLane]
    let duration: TimeInterval
    let pixelsPerBeat: CGFloat
    
    @State private var selectedLaneId: UUID?
    @State private var showAddLane = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Automation")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { showAddLane = true }) {
                    Label("Add Lane", systemImage: "plus")
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Lanes
            ScrollView {
                VStack(spacing: 1) {
                    ForEach($lanes) { $lane in
                        AutomationLaneView(
                            lane: $lane,
                            duration: duration,
                            pixelsPerBeat: pixelsPerBeat,
                            height: 80
                        )
                    }
                }
            }
        }
        .sheet(isPresented: $showAddLane) {
            addLaneSheet
        }
    }
    
    private var addLaneSheet: some View {
        VStack(spacing: 16) {
            Text("Add Automation Lane")
                .font(.headline)
            
            List(AutomationParameter.allCases, id: \.self) { param in
                Button(action: {
                    let newLane = AutomationLane(parameter: param, color: param.color)
                    lanes.append(newLane)
                    showAddLane = false
                }) {
                    HStack {
                        Image(systemName: param.icon)
                            .foregroundColor(param.color)
                        Text(param.rawValue)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            
            Button("Cancel") { showAddLane = false }
                .keyboardShortcut(.escape)
        }
        .padding()
        .frame(width: 300, height: 400)
    }
}

