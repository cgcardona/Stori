//
//  ProfessionalTimelineRuler.swift
//  TellUrStoriDAW
//
//  Professional two-layer timeline ruler with cycle overlay and playhead control
//

import SwiftUI

struct ProfessionalTimelineRuler: View {
    // Inputs
    @EnvironmentObject var audioEngine: AudioEngine
    let pixelsPerSecond: CGFloat
    let contentWidth: CGFloat
    let height: CGFloat  // expect 60
    
    // Height split
    private let topCycleHeight: CGFloat = 30
    private var bottomPlayheadHeight: CGFloat { height - topCycleHeight }
    

    var body: some View {
        ZStack(alignment: .topLeading) {

            // BASE BACKGROUND
            Rectangle()
                .fill(Color(NSColor.controlBackgroundColor))

            // --- TOP: CYCLE LANE -------------------------------------------------
            ZStack(alignment: .topLeading) {
                // Subtle separation background for cycle lane
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(0.08),
                                Color.black.opacity(0.04)
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 0.5),
                        alignment: .bottom
                    )

                if audioEngine.isCycleEnabled {
                    CycleOverlay(
                        cycleStartTime: audioEngine.cycleStartTime,
                        cycleEndTime: audioEngine.cycleEndTime,
                        pixelsPerSecond: pixelsPerSecond,
                        maxWidth: contentWidth,
                        onCycleRegionChanged: { start, end in
                            audioEngine.setCycleRegion(start: start, end: end)
                        }
                    )
                    .onAppear {
                        // print("🟡 CYCLE OVERLAY: isCycleEnabled=\(audioEngine.isCycleEnabled)")
                        // print("🟡 CYCLE OVERLAY: cycleStart=\(audioEngine.cycleStartTime), cycleEnd=\(audioEngine.cycleEndTime)")
                        // print("🟡 CYCLE OVERLAY: pixelsPerSecond=\(pixelsPerSecond), contentWidth=\(contentWidth)")
                    }
                }
            }
            .frame(width: contentWidth, height: topCycleHeight)
            .accessibilityLabel("Cycle lane")
            .accessibilityHint("Drag to move or resize the cycle region")

            // --- BOTTOM: PLAYHEAD + TICKS ---------------------------------------
            VStack(spacing: 0) {
                Spacer().frame(height: topCycleHeight)

                ZStack(alignment: .topLeading) {
                    // Ticks/labels
                    Canvas { ctx, size in
                        drawTimeMarkers(ctx: ctx, size: size)
                    }

                    // Click-to-seek (only bottom lane responds)
                    Rectangle().fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let x = max(0, value.location.x)
                                    let t = Double(x / pixelsPerSecond)
                                    audioEngine.seekToPosition(t)
                                }
                        )
                        .accessibilityLabel("Timeline")
                        .accessibilityHint("Click or tap to move playhead")
                        .accessibilityAddTraits(.isButton)
                }
                .frame(width: contentWidth, height: bottomPlayheadHeight)
            }

            // --- PLAYHEAD (spans both layers) -----------------------------------
            Rectangle()
                .fill(Color.red)
                .frame(width: 2, height: height)
                .offset(x: CGFloat(audioEngine.currentPosition.timeInterval) * pixelsPerSecond)
                .accessibilityHidden(true)
        }
        .frame(width: contentWidth, height: height)
    }

    // MARK: Ticks/Labels (bottom lane)
    private func drawTimeMarkers(ctx: GraphicsContext, size: CGSize) {
        // Marker style similar to your current implementation but packed into bottom lane
        let pps = pixelsPerSecond
        guard pps > 0 else { return }
        let totalSeconds = Int(ceil(contentWidth / pps))

        for second in 0...totalSeconds {
            let x = CGFloat(second) * pps
            if second % 10 == 0 {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(.primary), lineWidth: 1.25)

                let m = second / 60, s = second % 60
                let label = String(format: "%d:%02d", m, s)
                ctx.draw(
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary),
                    at: CGPoint(x: x + 4, y: 10),
                    anchor: .topLeading
                )
            } else if second % 5 == 0 {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 6))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(.primary.opacity(0.7)), lineWidth: 1)
            } else {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 12))
                p.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(p, with: .color(.primary.opacity(0.35)), lineWidth: 0.8)
            }
        }
    }
}
