//
//  CycleOverlay.swift
//  Stori
//
//  Professional cycle overlay with interactive drag controls
//

import SwiftUI

struct CycleOverlay: View {
    // Inputs - ALL IN BEATS (not seconds) for consistency with rest of app
    let cycleStartBeat: Double
    let cycleEndBeat: Double
    let pixelsPerBeat: CGFloat  // Beat-based timeline (proper DAW architecture)
    let maxWidth: CGFloat
    let tempo: Double  // BPM for beat→seconds conversion
    let snapToGrid: Bool  // Whether to snap to bars
    let onCycleRegionChanged: (Double, Double) -> Void  // Callback returns BEATS
    

    // Internal state during gestures (in BEATS)
    @State private var dragMode: DragMode? = nil
    @State private var tempStartBeat: Double = 0
    @State private var tempEndBeat: Double = 0
    @State private var hoveringLeft = false
    @State private var hoveringRight = false
    @State private var hoveringBody = false
    @State private var isSnapped = false  // Visual feedback for snap

    // Constants
    private let minLenBeats: Double = 0.25  // Minimum 1/4 beat
    private let handleW: CGFloat = 8
    private let laneH: CGFloat = 30
    
    // Conversion helpers
    private var secondsPerBeat: TimeInterval { 60.0 / tempo }
    private let beatsPerBar: Double = 4.0  // 4/4 time

    enum DragMode { case left, right, body }
    
    // Update cursor based on hover state
    private func updateCursor() {
        if hoveringLeft || hoveringRight {
            NSCursor.resizeLeftRight.set()
        } else if hoveringBody {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
    
    // Snap to nearest bar (in BEATS)
    private func snapToBar(_ beats: Double) -> Double {
        guard snapToGrid else { return beats }
        return round(beats / beatsPerBar) * beatsPerBar
    }
    
    // Snap to nearest beat
    private func snapToBeat(_ beats: Double) -> Double {
        guard snapToGrid else { return beats }
        return round(beats)
    }

    var body: some View {
        // Convert beats to pixels for display
        let startBeat = min(cycleStartBeat, cycleEndBeat)
        let endBeat = max(cycleStartBeat, cycleEndBeat)
        let x0 = CGFloat(startBeat) * pixelsPerBeat
        let x1 = CGFloat(endBeat) * pixelsPerBeat
        let w = max(1, min(x1 - x0, maxWidth - x0))
        
        // Use Canvas for precise pixel-perfect positioning (same as time markers)
        Canvas { context, size in
            // Draw cycle body - simplified flat style to match piano roll
            let bodyRect = CGRect(x: x0, y: 3, width: w, height: laneH - 6)
            
            // Fill entire region with uniform solid color (no separate handles, no stroke)
            context.fill(Path(bodyRect), with: .color(Color.yellow))
            
            // [PHASE-2] Measure badge label (e.g., "1.1 – 5.1  (4 bars)")
            // Just draw text directly on the uniform yellow bar - no separate background
            let label = "\(formatMeasure(startBeat)) – \(formatMeasure(endBeat))  (\(formatDuration(endBeat - startBeat)))"
            let text = Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.black.opacity(0.85))
            
            // Draw text centered on the cycle bar
            context.draw(text, at: CGPoint(x: x0 + w / 2, y: 3 + (laneH - 6) / 2), anchor: .center)
        }
        .frame(width: maxWidth, height: laneH)
        // Single overlay for all gestures - determine action based on click location
        .overlay(
            GeometryReader { _ in
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: w, height: laneH)
                    .position(x: x0 + w / 2, y: laneH / 2)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                // Determine drag mode on first touch based on location
                                if dragMode == nil {
                                    let localX = value.startLocation.x
                                    let leftHandleEnd = x0 + handleW
                                    let rightHandleStart = x0 + w - handleW
                                    
                                    if localX < leftHandleEnd {
                                        dragMode = .left
                                        NSCursor.resizeLeftRight.set()
                                    } else if localX > rightHandleStart {
                                        dragMode = .right
                                        NSCursor.resizeLeftRight.set()
                                    } else {
                                        dragMode = .body
                                        NSCursor.closedHand.set()
                                    }
                                    tempStartBeat = cycleStartBeat
                                    tempEndBeat = cycleEndBeat
                                }
                                
                                // Convert pixel drag to beats
                                let dtBeats = Double(value.translation.width / pixelsPerBeat)
                                
                                // Detect modifier keys for snap behavior
                                let flags = NSEvent.modifierFlags
                                let isCommandPressed = flags.contains(.command)
                                let isShiftPressed = flags.contains(.shift)
                                
                                // Snap function (all in BEATS)
                                func applySnap(_ beats: Double) -> Double {
                                    if isCommandPressed {
                                        isSnapped = false
                                        return beats
                                    } else if isShiftPressed {
                                        isSnapped = true
                                        return snapToBeat(beats)
                                    } else if snapToGrid {
                                        isSnapped = true
                                        return snapToBar(beats)
                                    }
                                    isSnapped = false
                                    return beats
                                }
                                
                                switch dragMode {
                                case .left:
                                    var newStart = max(0, tempStartBeat + dtBeats)
                                    newStart = applySnap(newStart)
                                    if (cycleEndBeat - newStart) >= minLenBeats {
                                        onCycleRegionChanged(newStart, cycleEndBeat)
                                    }
                                case .right:
                                    var newEnd = max(minLenBeats, tempEndBeat + dtBeats)
                                    newEnd = applySnap(newEnd)
                                    if (newEnd - cycleStartBeat) >= minLenBeats {
                                        onCycleRegionChanged(cycleStartBeat, newEnd)
                                    }
                                case .body:
                                    let duration = tempEndBeat - tempStartBeat
                                    var newStart = max(0, tempStartBeat + dtBeats)
                                    newStart = applySnap(newStart)
                                    
                                    var newEnd = newStart + duration
                                    
                                    // Clamp within timeline bounds (convert to beats)
                                    let maxBeats = Double(maxWidth / pixelsPerBeat)
                                    if newEnd > maxBeats {
                                        let overshoot = newEnd - maxBeats
                                        newStart -= overshoot
                                        newEnd = maxBeats
                                        newStart = max(0, newStart)
                                    }
                                    onCycleRegionChanged(newStart, newEnd)
                                case .none:
                                    break
                                }
                            }
                            .onEnded { _ in
                                dragMode = nil
                                isSnapped = false
                                NSCursor.arrow.set()
                            }
                    )
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            let leftHandleEnd = x0 + handleW
                            let rightHandleStart = x0 + w - handleW
                            
                            hoveringLeft = location.x >= x0 && location.x < leftHandleEnd
                            hoveringRight = location.x > rightHandleStart && location.x <= x0 + w
                            hoveringBody = location.x >= leftHandleEnd && location.x <= rightHandleStart
                            updateCursor()
                        case .ended:
                            hoveringLeft = false
                            hoveringRight = false
                            hoveringBody = false
                            NSCursor.arrow.set()
                        }
                    }
            }
        )
        .animation(.easeInOut(duration: 0.2), value: dragMode)
    }
    
    // [PHASE-2] Format beat position as measure.beat (e.g., "1.1", "2.3")
    private func formatMeasure(_ beats: Double) -> String {
        let measure = Int(beats / beatsPerBar) + 1  // 1-indexed measures
        let beat = Int(beats.truncatingRemainder(dividingBy: beatsPerBar)) + 1  // 1-indexed beats
        return "\(measure).\(beat)"
    }
    
    // [PHASE-2] Calculate duration in bars (duration is in BEATS)
    private func formatDuration(_ durationBeats: Double) -> String {
        let bars = durationBeats / beatsPerBar
        if bars >= 1 {
            let wholeB = Int(bars)
            return wholeB == 1 ? "1 bar" : "\(wholeB) bars"
        } else {
            // Less than a bar - show beats
            let beats = Int(durationBeats)
            return beats == 1 ? "1 beat" : "\(beats) beats"
        }
    }

    // MARK: - Drag Gestures (all work in BEATS)
    
    private func leftHandleDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragMode == nil {
                    dragMode = .left
                    tempStartBeat = cycleStartBeat
                    tempEndBeat = cycleEndBeat
                }
                let dtBeats = Double(value.translation.width / pixelsPerBeat)
                let newStart = max(0, tempStartBeat + dtBeats)
                if (cycleEndBeat - newStart) >= minLenBeats {
                    onCycleRegionChanged(newStart, cycleEndBeat)
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
                    tempStartBeat = cycleStartBeat
                    tempEndBeat = cycleEndBeat
                }
                let dtBeats = Double(value.translation.width / pixelsPerBeat)
                let newEnd = max(minLenBeats, tempEndBeat + dtBeats)
                if (newEnd - cycleStartBeat) >= minLenBeats {
                    onCycleRegionChanged(cycleStartBeat, newEnd)
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
                    tempStartBeat = cycleStartBeat
                    tempEndBeat = cycleEndBeat
                }
                let dtBeats = Double(value.translation.width / pixelsPerBeat)
                let duration = cycleEndBeat - cycleStartBeat
                var newStart = max(0, tempStartBeat + dtBeats)
                var newEnd = newStart + duration
                
                // Clamp within timeline bounds (in beats)
                let maxBeats = Double(maxWidth / pixelsPerBeat)
                if newEnd > maxBeats {
                    let overshoot = newEnd - maxBeats
                    newStart -= overshoot
                    newEnd = maxBeats
                    newStart = max(0, newStart)
                }
                
                onCycleRegionChanged(newStart, newEnd)
            }
            .onEnded { _ in
                dragMode = nil
            }
    }

}
