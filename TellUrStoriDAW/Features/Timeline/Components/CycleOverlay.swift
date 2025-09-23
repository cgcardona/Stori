//
//  CycleOverlay.swift
//  TellUrStoriDAW
//
//  Professional cycle overlay with interactive drag controls
//

import SwiftUI

struct CycleOverlay: View {
    // Inputs
    let cycleStartTime: TimeInterval
    let cycleEndTime: TimeInterval
    let pixelsPerSecond: CGFloat
    let maxWidth: CGFloat
    let onCycleRegionChanged: (TimeInterval, TimeInterval) -> Void
    

    // Internal state during gestures
    @State private var dragMode: DragMode? = nil
    @State private var tempStart: TimeInterval = 0
    @State private var tempEnd: TimeInterval = 0
    @State private var hoveringLeft = false
    @State private var hoveringRight = false
    @State private var hoveringBody = false

    // Constants
    private let minLen: TimeInterval = 0.10
    private let handleW: CGFloat = 8
    private let laneH: CGFloat = 30

    enum DragMode { case left, right, body }

    var body: some View {
        let start = min(cycleStartTime, cycleEndTime)
        let end   = max(cycleStartTime, cycleEndTime)
        let x0    = CGFloat(start) * pixelsPerSecond
        let x1    = CGFloat(end)   * pixelsPerSecond
        let w     = max(1, min(x1 - x0, maxWidth - x0))
        
        // let _ = print("🟡 CYCLE OVERLAY RENDER: start=\(start), end=\(end), x0=\(x0), x1=\(x1), w=\(w)")
        // let _ = print("🟡 CYCLE OVERLAY DEBUG: cycleStartTime=\(cycleStartTime), cycleEndTime=\(cycleEndTime), pixelsPerSecond=\(pixelsPerSecond)")
        // let _ = print("🟡 CYCLE OVERLAY POSITION: maxWidth=\(maxWidth), laneH=\(laneH), x0=\(x0), w=\(w)")

        // Entire overlay lives in top lane coordinate space
        ZStack(alignment: .topLeading) {
            // Cycle body (yellow/amber with depth)
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [Color.yellow.opacity(0.45), Color.yellow.opacity(0.25)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.yellow.opacity(0.9), lineWidth: 1.5)
                )
                .frame(width: w, height: laneH - 6)
                .offset(x: x0, y: 3) // Use x0 directly without contentOriginX adjustment
                .shadow(color: .black.opacity(0.5), radius: 5, x: 0, y: 3) // STRONGER SHADOW
                .overlay(timeBadge(width: w).offset(x: x0, y: 3)) // Use x0 directly
                .onHover { hoveringBody = $0 }
                .gesture(bodyDragGesture())

            // Left handle (higher priority - drawn last)
            Rectangle()
                .fill(Color.yellow)
                .frame(width: handleW, height: laneH - 6)
                .offset(x: x0, y: 3) // Use x0 directly
                .opacity(hoveringLeft ? 1.0 : 0.9)
                .shadow(color: hoveringLeft ? .yellow.opacity(0.8) : .clear, radius: 4)
                .cursor(.resizeLeftRight)
                .accessibilityLabel("Cycle start handle")
                .accessibilityHint("Drag to change cycle start")
                .onHover { hoveringLeft = $0 }
                .gesture(leftHandleDragGesture().exclusively(before: bodyDragGesture()))
                .allowsHitTesting(true)

            // Right handle (higher priority - drawn last)
            Rectangle()
                .fill(Color.yellow)
                .frame(width: handleW, height: laneH - 6)
                .offset(x: x0 + w - handleW, y: 3) // Use x0 + width - handle width
                .opacity(hoveringRight ? 1.0 : 0.9)
                .shadow(color: hoveringRight ? .yellow.opacity(0.8) : .clear, radius: 4)
                .cursor(.resizeLeftRight)
                .accessibilityLabel("Cycle end handle")
                .accessibilityHint("Drag to change cycle end")
                .onHover { hoveringRight = $0 }
                .gesture(rightHandleDragGesture().exclusively(before: bodyDragGesture()))
                .allowsHitTesting(true)
        }
        .frame(width: maxWidth, height: laneH)
        .animation(.easeInOut(duration: 0.2), value: dragMode)
        .animation(.easeInOut(duration: 0.2), value: hoveringLeft || hoveringRight || hoveringBody)
    }

    // MARK: - Drag Gestures
    
    private func leftHandleDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = .left
                    tempStart = cycleStartTime
                    tempEnd = cycleEndTime
                }
                let dt = Double(value.translation.width / pixelsPerSecond)
                let newStart = max(0, tempStart + dt)
                if (cycleEndTime - newStart) >= minLen {
                    onCycleRegionChanged(newStart, cycleEndTime)
                }
            }
            .onEnded { _ in
                dragMode = nil
            }
    }
    
    private func rightHandleDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = .right
                    tempStart = cycleStartTime
                    tempEnd = cycleEndTime
                }
                let dt = Double(value.translation.width / pixelsPerSecond)
                let newEnd = max(minLen, tempEnd + dt)
                if (newEnd - cycleStartTime) >= minLen {
                    onCycleRegionChanged(cycleStartTime, newEnd)
                }
            }
            .onEnded { _ in
                dragMode = nil
            }
    }
    
    private func bodyDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = .body
                    tempStart = cycleStartTime
                    tempEnd = cycleEndTime
                }
                let dt = Double(value.translation.width / pixelsPerSecond)
                let duration = cycleEndTime - cycleStartTime
                var newStart = max(0, tempStart + dt)
                var newEnd = newStart + duration
                
                // Clamp within timeline bounds
                let maxTime = Double(maxWidth / pixelsPerSecond)
                if newEnd > maxTime {
                    let overshoot = newEnd - maxTime
                    newStart -= overshoot
                    newEnd = maxTime
                    newStart = max(0, newStart)
                }
                
                onCycleRegionChanged(newStart, newEnd)
            }
            .onEnded { _ in
                dragMode = nil
            }
    }

    // MARK: - Time Badge
    @ViewBuilder
    private func timeBadge(width: CGFloat) -> some View {
        let s = min(cycleStartTime, cycleEndTime)
        let e = max(cycleStartTime, cycleEndTime)
        let label = "\(fmt(s)) – \(fmt(e))  (\(fmt(e - s)))"

        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(.black.opacity(0.85))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(
                Capsule().fill(Color.yellow.opacity(0.9))
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            )
            .frame(width: width, alignment: .center)
            .accessibilityLabel("Cycle time range")
            .accessibilityValue(label)
    }

    private func fmt(_ t: TimeInterval) -> String {
        let m = Int(t) / 60, s = Int(t) % 60, cs = Int((t.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", m, s, cs)
    }
}
