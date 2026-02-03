//
//  AutomationModeButton.swift
//  Stori
//
//  Compact automation mode button for track headers.
//  Displays current mode and allows cycling through modes.
//

import SwiftUI

// MARK: - Automation Mode Button

/// Compact button showing automation mode with color indicator
struct AutomationModeButton: View {
    @Binding var mode: AutomationMode
    let trackId: UUID
    var projectManager: ProjectManager
    
    // Get current mode directly from project for accurate menu state
    private var currentMode: AutomationMode {
        projectManager.currentProject?.tracks.first(where: { $0.id == trackId })?.automationMode ?? mode
    }
    
    var body: some View {
        Menu {
            ForEach(AutomationMode.allCases, id: \.self) { modeOption in
                Button(action: {
                    updateMode(to: modeOption)
                }) {
                    let isSelected = currentMode == modeOption
                    Label {
                        Text(modeOption.rawValue + (isSelected ? "  ✓" : ""))
                    } icon: {
                        Image(systemName: modeOption.icon)
                    }
                }
            }
            
            Divider()
            
            Text(currentMode.description)
                .font(.caption)
                .foregroundColor(.secondary)
        } label: {
            // Green button for active automation mode
            HStack(spacing: 4) {
                Text(currentMode.rawValue)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.green)
            )
        }
        .menuStyle(.borderlessButton)
        .help("Automation Mode: \(currentMode.rawValue)")
    }
    
    private func updateMode(to newMode: AutomationMode) {
        mode = newMode
        
        // Update project
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        
        project.tracks[trackIndex].automationMode = newMode
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
}

// MARK: - Automation Disclosure Button

/// Button to show/hide automation lanes for a track
struct AutomationDisclosureButton: View {
    let trackId: UUID
    var projectManager: ProjectManager
    
    // Computed property to get current expanded state
    private var isExpanded: Bool {
        projectManager.currentProject?.tracks.first(where: { $0.id == trackId })?.automationExpanded ?? false
    }
    
    private var hasAutomation: Bool {
        guard let lanes = projectManager.currentProject?.tracks.first(where: { $0.id == trackId })?.automationLanes else {
            return false
        }
        return !lanes.isEmpty
    }
    
    var body: some View {
        Button(action: {
            toggleExpanded()
        }) {
            ZStack {
                // Background for better visibility
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.8))
                    .frame(width: 18, height: 18)
                
                // Chevron icon
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(hasAutomation ? .orange : .primary)
                
                // Automation indicator dot when collapsed but has data
                if !isExpanded && hasAutomation {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .offset(x: 7, y: -7)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 20, height: 20)
        .help(isExpanded ? "Hide Automation" : "Show Automation")
    }
    
    private func toggleExpanded() {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        
        // Toggle the expanded state
        project.tracks[trackIndex].automationExpanded.toggle()
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
}

// MARK: - Inline Automation Lane

/// Compact automation lane for display in the timeline
/// Note: This is legacy - new automation uses AutomationCurveOverlay in IntegratedTimelineView
struct InlineAutomationLane: View {
    @Binding var lane: AutomationLane
    let duration: TimeInterval  // Duration in beats
    let pixelsPerBeat: CGFloat
    let height: CGFloat
    let trackId: UUID
    var projectManager: ProjectManager
    
    // Legacy compatibility
    var pixelsPerSecond: CGFloat { pixelsPerBeat }  // Assuming 1:1 for legacy code
    
    @State private var selectedCurveType: CurveType = .linear
    
    var body: some View {
        HStack(spacing: 0) {
            // Lane header (narrow)
            laneHeader
                .frame(width: 100)
            
            // Lane content
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Rectangle()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    
                    // Grid lines
                    gridLines(in: geometry)
                    
                    // Curve fill
                    curveFill(in: geometry)
                    
                    // Curve stroke
                    curveStroke(in: geometry)
                    
                    // Breakpoints
                    breakpoints(in: geometry)
                }
                .contentShape(Rectangle())
                .gesture(drawGesture(in: geometry))
            }
        }
        .frame(height: height)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Lane Header
    
    private var laneHeader: some View {
        HStack(spacing: 4) {
            // Parameter icon
            Image(systemName: lane.parameter.icon)
                .font(.system(size: 10))
                .foregroundColor(lane.color)
            
            // Parameter name
            Text(lane.parameter.rawValue)
                .font(.system(size: 10))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            Spacer()
            
            // Delete button
            Button(action: deleteLane) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Grid Lines
    
    private func gridLines(in geometry: GeometryProxy) -> some View {
        Canvas { context, size in
            // Horizontal center line
            let y = size.height / 2
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 0.5)
        }
    }
    
    // MARK: - Curve Drawing
    
    private func curveFill(in geometry: GeometryProxy) -> some View {
        Path { path in
            guard !lane.points.isEmpty else { return }
            
            let sortedPoints = lane.sortedPoints
            
            path.move(to: CGPoint(x: 0, y: geometry.size.height))
            
            if let first = sortedPoints.first {
                let x = first.beat * pixelsPerBeat
                path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                path.addLine(to: pointPosition(first, in: geometry))
            }
            
            for i in 1..<sortedPoints.count {
                addCurveSegment(from: sortedPoints[i-1], to: sortedPoints[i], in: geometry, to: &path)
            }
            
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
            
            let sortedPoints = lane.sortedPoints
            
            if let first = sortedPoints.first {
                path.move(to: pointPosition(first, in: geometry))
            }
            
            for i in 1..<sortedPoints.count {
                addCurveSegment(from: sortedPoints[i-1], to: sortedPoints[i], in: geometry, to: &path)
            }
        }
        .stroke(lane.color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
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
        let y = geometry.size.height * (1 - CGFloat(point.value))
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Breakpoints
    
    private func breakpoints(in geometry: GeometryProxy) -> some View {
        ForEach(lane.points) { point in
            let position = pointPosition(point, in: geometry)
            
            Circle()
                .fill(lane.color)
                .frame(width: 8, height: 8)
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
                
                addOrUpdatePoint(atBeat: beat, value: normalizedValue)
            }
    }
    
    private func addOrUpdatePoint(atBeat beat: Double, value: Float) {
        let threshold = 0.1 / pixelsPerBeat  // Beat threshold (how close points need to be to merge)
        
        if let existingIndex = lane.points.firstIndex(where: { abs($0.beat - beat) < threshold }) {
            lane.points[existingIndex].value = max(0, min(1, value))
        } else {
            let newPoint = AutomationPoint(beat: max(0, beat), value: max(0, min(1, value)), curve: selectedCurveType)
            lane.points.append(newPoint)
        }
        
        // Save changes
        saveChanges()
    }
    
    private func deleteLane() {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let laneIndex = project.tracks[trackIndex].automationLanes.firstIndex(where: { $0.id == lane.id }) else {
            return
        }
        
        project.tracks[trackIndex].automationLanes.remove(at: laneIndex)
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    private func saveChanges() {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let laneIndex = project.tracks[trackIndex].automationLanes.firstIndex(where: { $0.id == lane.id }) else {
            return
        }
        
        project.tracks[trackIndex].automationLanes[laneIndex] = lane
        project.modifiedAt = Date()
        projectManager.currentProject = project
        // Note: Not calling saveCurrentProject() on every point change to avoid performance issues
    }
}

// MARK: - Add Automation Lane Menu

/// Menu for adding new automation lanes to a track
struct AddAutomationLaneMenu: View {
    let trackId: UUID
    var projectManager: ProjectManager
    let existingParameters: Set<AutomationParameter>
    
    var body: some View {
        Menu {
            Section("Mixer") {
                ForEach(AutomationParameter.mixerParameters, id: \.self) { param in
                    if !existingParameters.contains(param) {
                        Button(action: { addLane(for: param) }) {
                            Label(param.rawValue, systemImage: param.icon)
                        }
                    }
                }
            }
            
            Section("Synth") {
                ForEach(AutomationParameter.synthParameters, id: \.self) { param in
                    if !existingParameters.contains(param) {
                        Button(action: { addLane(for: param) }) {
                            Label(param.rawValue, systemImage: param.icon)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "plus.circle")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 16, height: 16)
        .help("Add Automation Lane")
    }
    
    private func addLane(for parameter: AutomationParameter) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        
        let track = project.tracks[trackIndex]
        let newLane = AutomationLane(
            parameter: parameter,
            points: [],
            initialValue: track.mixerValue(for: parameter),
            color: parameter.color
        )
        project.tracks[trackIndex].automationLanes.append(newLane)
        project.tracks[trackIndex].automationExpanded = true
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
}
