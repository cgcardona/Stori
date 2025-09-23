//
//  InteractiveCycleOverlay.swift
//  TellUrStoriDAW
//
//  Interactive cycle region with dragging and resizing capabilities
//
// TODO: DEAD CODE - This file can be deleted in future dead code cleanup cycle
// This cycle overlay has been replaced by CycleOverlay
// Keeping for now to avoid disruption, but no longer used in the main app

import SwiftUI

struct InteractiveCycleOverlay: View {
    let cycleStartTime: TimeInterval
    let cycleEndTime: TimeInterval
    let horizontalZoom: Double
    let onCycleRegionChanged: (TimeInterval, TimeInterval) -> Void
    
    @State private var isDraggingRegion = false
    @State private var isDraggingStartHandle = false
    @State private var isDraggingEndHandle = false
    @State private var tempStartTime: TimeInterval = 0
    @State private var tempEndTime: TimeInterval = 0
    
    // Constants
    private var pixelsPerSecond: CGFloat { 100 * CGFloat(horizontalZoom) }
    private let handleWidth: CGFloat = 8
    private let regionHeight: CGFloat = 40
    private let minCycleLength: TimeInterval = 0.1
    
    var body: some View {
        // Calculate display values
        let displayStartTime = isDraggingRegion ? tempStartTime : 
                              (isDraggingStartHandle ? tempStartTime : cycleStartTime)
        let displayEndTime = isDraggingRegion ? tempEndTime : 
                            (isDraggingEndHandle ? tempEndTime : cycleEndTime)
        
        let startX = CGFloat(displayStartTime) * pixelsPerSecond
        let endX = CGFloat(displayEndTime) * pixelsPerSecond
        let width = endX - startX
        
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.yellow.opacity(0.4),
                        Color.yellow.opacity(0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: width, height: regionHeight)
            .position(x: startX + width/2, y: regionHeight/2)
            .overlay(
                // Time display
                Text("\(formatTime(displayStartTime)) - \(formatTime(displayEndTime))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.yellow.opacity(0.8))
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .position(x: width/2, y: regionHeight/2)
            )
            .overlay(
                // Start handle with hover detection
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: handleWidth, height: regionHeight)
                    .position(x: handleWidth/2, y: regionHeight/2)
                    .scaleEffect(isDraggingStartHandle ? 1.1 : 1.0)
                    .shadow(
                        color: isDraggingStartHandle ? Color.yellow.opacity(0.8) : Color.clear,
                        radius: isDraggingStartHandle ? 4 : 0
                    )
                    .cursor(.resizeLeftRight)
                    .onHover { hovering in
                        print("🟢 LEFT HANDLE HOVER: \(hovering)")
                    }
            )
            .overlay(
                // End handle
                Rectangle()
                    .fill(Color.yellow)
                    .frame(width: handleWidth, height: regionHeight)
                    .position(x: width - handleWidth/2, y: regionHeight/2)
                    .scaleEffect(isDraggingEndHandle ? 1.1 : 1.0)
                    .shadow(
                        color: isDraggingEndHandle ? Color.yellow.opacity(0.8) : Color.clear,
                        radius: isDraggingEndHandle ? 4 : 0
                    )
                    .cursor(.resizeLeftRight)
            )
            .overlay(
                // Region border
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 2)
                    .frame(width: width, height: regionHeight)
            )
            .scaleEffect(isDraggingRegion ? 1.02 : 1.0)
            .shadow(
                color: isDraggingRegion ? Color.yellow.opacity(0.5) : Color.clear,
                radius: isDraggingRegion ? 8 : 0
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let localX = value.startLocation.x
                        
                        // Determine interaction type based on click location
                        if localX <= handleWidth {
                            // Start handle drag - EXTENSIVE LOGGING
                            print("🟢 LEFT HANDLE DRAG - localX: \(localX), handleWidth: \(handleWidth)")
                            print("🟢 LEFT HANDLE DRAG - translation.width: \(value.translation.width)")
                            print("🟢 LEFT HANDLE DRAG - pixelsPerSecond: \(pixelsPerSecond)")
                            
                            if !isDraggingStartHandle {
                                isDraggingStartHandle = true
                                tempStartTime = cycleStartTime
                                print("🟢 LEFT HANDLE - ✅ STARTED DRAGGING from: \(cycleStartTime)")
                                print("🟢 LEFT HANDLE - Current cycle: \(cycleStartTime) - \(cycleEndTime)")
                            }
                            
                            let timeOffset = Double(value.translation.width) / Double(pixelsPerSecond)
                            let newStartTime = max(0, cycleStartTime + timeOffset)
                            
                            print("🟢 LEFT HANDLE - timeOffset: \(timeOffset)")
                            print("🟢 LEFT HANDLE - newStartTime: \(newStartTime)")
                            print("🟢 LEFT HANDLE - cycleEndTime: \(cycleEndTime)")
                            print("🟢 LEFT HANDLE - minCycleLength: \(minCycleLength)")
                            print("🟢 LEFT HANDLE - remaining length: \(cycleEndTime - newStartTime)")
                            
                            if cycleEndTime - newStartTime >= minCycleLength {
                                tempStartTime = newStartTime
                                print("🟢 LEFT HANDLE - ✅ UPDATED tempStartTime to: \(tempStartTime)")
                            } else {
                                print("🟢 LEFT HANDLE - ❌ REJECTED: would make cycle too short")
                            }
                            
                        } else if localX >= width - handleWidth {
                            // End handle drag
                            print("🔴 END HANDLE DRAG - localX: \(localX), translation: \(value.translation.width)")
                            
                            if !isDraggingEndHandle {
                                isDraggingEndHandle = true
                                tempEndTime = cycleEndTime
                                print("🔴 END HANDLE - Started dragging")
                            }
                            
                            let timeOffset = Double(value.translation.width) / Double(pixelsPerSecond)
                            let newEndTime = cycleEndTime + timeOffset
                            
                            if newEndTime - cycleStartTime >= minCycleLength {
                                tempEndTime = newEndTime
                                print("🔴 END HANDLE - Updated tempEndTime to: \(tempEndTime)")
                            }
                            
                        } else {
                            // Region drag
                            print("🟡 REGION DRAG - localX: \(localX), translation: \(value.translation.width)")
                            
                            if !isDraggingRegion {
                                isDraggingRegion = true
                                tempStartTime = cycleStartTime
                                tempEndTime = cycleEndTime
                                print("🟡 REGION - Started dragging")
                            }
                            
                            let timeOffset = Double(value.translation.width) / Double(pixelsPerSecond)
                            let cycleDuration = cycleEndTime - cycleStartTime
                            
                            let newStartTime = max(0, cycleStartTime + timeOffset)
                            tempStartTime = newStartTime
                            tempEndTime = newStartTime + cycleDuration
                            
                            print("🟡 REGION - Updated times: start=\(tempStartTime), end=\(tempEndTime)")
                        }
                    }
                    .onEnded { value in
                        if isDraggingStartHandle {
                            print("🟢 LEFT HANDLE DRAG ENDED - Final translation: \(value.translation.width)")
                            let timeOffset = Double(value.translation.width) / Double(pixelsPerSecond)
                            let newStartTime = max(0, cycleStartTime + timeOffset)
                            
                            print("🟢 LEFT HANDLE END - Final timeOffset: \(timeOffset)")
                            print("🟢 LEFT HANDLE END - Final newStartTime: \(newStartTime)")
                            print("🟢 LEFT HANDLE END - Original cycle: \(cycleStartTime) - \(cycleEndTime)")
                            
                            if cycleEndTime - newStartTime >= minCycleLength {
                                onCycleRegionChanged(newStartTime, cycleEndTime)
                                print("🟢 LEFT HANDLE END - ✅ APPLIED CHANGE: \(newStartTime) - \(cycleEndTime)")
                                print("🟢 LEFT HANDLE END - New cycle length: \(cycleEndTime - newStartTime)")
                            } else {
                                print("🟢 LEFT HANDLE END - ❌ REJECTED: final cycle would be too short")
                            }
                            
                            isDraggingStartHandle = false
                            tempStartTime = cycleStartTime
                            print("🟢 LEFT HANDLE END - Reset tempStartTime to: \(cycleStartTime)")
                            
                        } else if isDraggingEndHandle {
                            print("🔴 END HANDLE DRAG ENDED")
                            let timeOffset = Double(value.translation.width) / Double(pixelsPerSecond)
                            let newEndTime = cycleEndTime + timeOffset
                            
                            if newEndTime - cycleStartTime >= minCycleLength {
                                onCycleRegionChanged(cycleStartTime, newEndTime)
                                print("🔴 END HANDLE - Applied change: \(newEndTime)")
                            }
                            
                            isDraggingEndHandle = false
                            tempEndTime = cycleEndTime
                            
                        } else if isDraggingRegion {
                            print("🟡 REGION DRAG ENDED")
                            let timeOffset = Double(value.translation.width) / Double(pixelsPerSecond)
                            let cycleDuration = cycleEndTime - cycleStartTime
                            
                            let newStartTime = max(0, cycleStartTime + timeOffset)
                            let newEndTime = newStartTime + cycleDuration
                            
                            onCycleRegionChanged(newStartTime, newEndTime)
                            print("🟡 REGION - Applied change: start=\(newStartTime), end=\(newEndTime)")
                            
                            isDraggingRegion = false
                            tempStartTime = cycleStartTime
                            tempEndTime = cycleEndTime
                        }
                    }
            )
            .animation(.easeInOut(duration: 0.1), value: isDraggingRegion)
            .animation(.easeInOut(duration: 0.1), value: isDraggingStartHandle)
            .animation(.easeInOut(duration: 0.1), value: isDraggingEndHandle)
            .frame(height: regionHeight)
            .clipped()
            .onAppear {
                print("🟡 CYCLE OVERLAY APPEARED - cycleStartTime: \(cycleStartTime), cycleEndTime: \(cycleEndTime)")
                print("🟡 CYCLE OVERLAY APPEARED - horizontalZoom: \(horizontalZoom)")
                let startX = CGFloat(cycleStartTime) * pixelsPerSecond
                let endX = CGFloat(cycleEndTime) * pixelsPerSecond
                let width = endX - startX
                let centerX = startX + width/2
                print("🟡 CYCLE OVERLAY APPEARED - startX: \(startX), endX: \(endX), width: \(width)")
                print("🟡 CYCLE OVERLAY APPEARED - centerX: \(centerX), pixelsPerSecond: \(pixelsPerSecond)")
                print("🟡 CYCLE OVERLAY APPEARED - NOTE: This overlay will be offset by +280px in MainDAWView")
            }
            .onChange(of: cycleStartTime) { _, newValue in
                print("🟡 CYCLE OVERLAY CHANGED - cycleStartTime: \(newValue)")
            }
            .onChange(of: cycleEndTime) { _, newValue in
                print("🟡 CYCLE OVERLAY CHANGED - cycleEndTime: \(newValue)")
            }
    }
    
    // MARK: - Helper Functions
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }
}
