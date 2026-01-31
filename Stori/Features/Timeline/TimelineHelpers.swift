//
//  TimelineHelpers.swift
//  Stori
//
//  Extracted from IntegratedTimelineView.swift
//  Contains helper structs and isolated observer views for timeline performance
//

import SwiftUI
import AppKit

// MARK: - Batch Analysis State

/// State container for the floating macOS-style analysis HUD.
struct BatchAnalysisState {
    var title: String = "Analyzing Audio…"
    var subtitle: String = ""
    var progress: Double = 0.0
    var totalRegions: Int = 0
    var completedRegions: Int = 0
    
    mutating func reset() {
        title = "Analyzing Audio…"
        subtitle = ""
        progress = 0.0
        totalRegions = 0
        completedRegions = 0
    }
    
    mutating func start(regionCount: Int) {
        totalRegions = regionCount
        completedRegions = 0
        progress = 0.0
        
        if regionCount == 1 {
            title = "Analyzing Region…"
            subtitle = ""
        } else {
            title = "Analyzing \(regionCount) Regions…"
            subtitle = "0 of \(regionCount) analyzed"
        }
    }
    
    mutating func updateProgress(completed: Int) {
        completedRegions = completed
        progress = totalRegions > 0 ? Double(completed) / Double(totalRegions) : 0
        
        if completed < totalRegions {
            subtitle = "\(completed) of \(totalRegions) analyzed"
        } else {
            subtitle = "Complete"
        }
    }
}

// MARK: - Add Track Button Style

struct AddTrackButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Rectangle()
                    .fill(buttonBackgroundColor(configuration: configuration))
                    .overlay(
                        Rectangle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
    
    private func buttonBackgroundColor(configuration: Configuration) -> Color {
        if configuration.isPressed {
            Color(NSColor.controlAccentColor).opacity(0.2)
        } else {
            Color(NSColor.controlBackgroundColor)
        }
    }
}

// MARK: - File-Level Helpers

/// Calculate snap interval based on timeDisplayMode
/// - Parameters:
///   - time: The time to snap
///   - mode: The time display mode (beats or time)
///   - tempo: The project tempo (for beats mode)
/// - Returns: Snapped time interval
func calculateSnapInterval(for time: TimeInterval, mode: TimeDisplayMode, tempo: Double) -> TimeInterval {
    switch mode {
    case .beats:
        // Snap to individual beats (not full bars) for precise placement
        let secondsPerBeat = 60.0 / tempo
        // Round to nearest beat using standard rounding
        let beatNumber = round(time / secondsPerBeat)
        return beatNumber * secondsPerBeat
    case .time:
        // Snap to fixed time intervals
        let snapInterval: TimeInterval
        if time < 10 {
            snapInterval = 0.5  // 500ms for short times
        } else if time < 60 {
            snapInterval = 1.0  // 1 second for medium times
        } else {
            snapInterval = 5.0  // 5 seconds for long times
        }
        return round(time / snapInterval) * snapInterval
    }
}

// MARK: - Timeline Playhead (isolated for performance)
// Uses @Observable AudioEngine for fine-grained updates
// Only this view re-renders when currentPosition changes, not the parent timeline
// NOTE: Triangle head is only in the RulerPlayhead, not here (to avoid duplication)
struct TimelinePlayhead: View {
    @Environment(AudioEngine.self) private var audioEngine
    @Environment(ProjectManager.self) private var projectManager
    let height: CGFloat
    let pixelsPerSecond: CGFloat
    
    private let lineWidth: CGFloat = 2
    
    var body: some View {
        // Convert beats to seconds for pixel calculation (read from ProjectManager for consistency)
        let tempo = projectManager.currentProject?.tempo ?? 120.0
        let timeInSeconds = audioEngine.currentPosition.beats * (60.0 / tempo)
        let playheadX = CGFloat(timeInSeconds) * pixelsPerSecond
        
        Rectangle()
            .fill(Color.red)
            .frame(width: lineWidth, height: height)
            .offset(x: playheadX - lineWidth / 2)  // Center the line at playheadX
            .allowsHitTesting(false)
    }
}

// MARK: - Catch Playhead Observer (isolated for performance)
// CRITICAL PERFORMANCE FIX: This view isolates the audioEngine.currentPosition dependency.
// Without this isolation, the .onChange modifier in IntegratedTimelineView would cause
// the entire view to track currentPosition as a dependency, triggering
// full SwiftUI view re-evaluation on every position update (~60fps = massive CPU spike).
// By moving the observation into this separate struct, only this tiny view re-renders.
struct CatchPlayheadObserver: View {
    let audioEngine: AudioEngine
    let catchPlayheadEnabled: Bool
    let onCatchPlayhead: (Double) -> Void
    
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: audioEngine.currentPosition.beats) { _, newBeats in
                guard catchPlayheadEnabled && audioEngine.transportState.isPlaying else { return }
                onCatchPlayhead(newBeats)
            }
    }
}

// MARK: - Selection Count Badge (Isolated Observer)
/// Isolated view that observes selection without triggering parent re-renders
/// This prevents the entire IntegratedTimelineView from rebuilding when selection changes
struct SelectionCountBadge: View {
    var selection: SelectionManager
    
    var body: some View {
        Group {
            if selection.selectedRegionIds.count > 1 {
                HStack {
                    Spacer()
                    Text("\(selection.selectedRegionIds.count) regions selected")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                    Spacer()
                }
                .padding(.top, 8)
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Audio Selection Observer (Isolated)
/// Observes audio region selection changes without causing parent view re-renders
/// Updates the selectedRegionId binding for inspector display
struct AudioSelectionObserver: View {
    var selection: SelectionManager
    @Binding var selectedRegionId: UUID?
    
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: selection.selectedRegionIds) { _, newSelection in
                // Only update binding, no other side effects
                // Cross-clearing is handled by SelectionManager methods
                selectedRegionId = newSelection.first
            }
    }
}

// MARK: - Marquee Overlay (Isolated)
/// Isolated view that observes marquee state without causing parent view re-renders
/// This prevents IntegratedTimelineView from being invalidated when marquee state changes
struct MarqueeOverlay: View {
    var selection: SelectionManager
    
    var body: some View {
        Group {
            if selection.isMarqueeActive {
                Rectangle()
                    .fill(Color.blue.opacity(0.10))
                    .overlay(
                        Rectangle()
                            .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundColor(.blue)
                    )
                    .frame(width: selection.marqueeRect.width, height: selection.marqueeRect.height)
                    .position(x: selection.marqueeRect.midX, y: selection.marqueeRect.midY)
            }
        }
    }
}

// MARK: - Timeline Editing Notifications Modifier

/// ViewModifier that consolidates editing notification handlers
/// This helps reduce type-checking complexity in IntegratedTimelineView
struct TimelineEditingNotifications: ViewModifier {
    let onSplit: () -> Void
    let onJoin: () -> Void
    let onTrimStart: () -> Void
    let onTrimEnd: () -> Void
    let onNudgeLeft: () -> Void
    let onNudgeRight: () -> Void
    let onSelectNext: () -> Void
    let onSelectPrevious: () -> Void
    let onSelectAbove: () -> Void
    let onSelectBelow: () -> Void
    let onCreateCrossfade: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .splitAtPlayhead)) { _ in
                onSplit()
            }
            .onReceive(NotificationCenter.default.publisher(for: .joinRegions)) { _ in
                onJoin()
            }
            .onReceive(NotificationCenter.default.publisher(for: .trimRegionStart)) { _ in
                onTrimStart()
            }
            .onReceive(NotificationCenter.default.publisher(for: .trimRegionEnd)) { _ in
                onTrimEnd()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nudgeRegionsLeft)) { _ in
                onNudgeLeft()
            }
            .onReceive(NotificationCenter.default.publisher(for: .nudgeRegionsRight)) { _ in
                onNudgeRight()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectNextRegion)) { _ in
                onSelectNext()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectPreviousRegion)) { _ in
                onSelectPrevious()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectRegionAbove)) { _ in
                onSelectAbove()
            }
            .onReceive(NotificationCenter.default.publisher(for: .selectRegionBelow)) { _ in
                onSelectBelow()
            }
            .onReceive(NotificationCenter.default.publisher(for: .createCrossfade)) { _ in
                onCreateCrossfade()
            }
    }
}

/// ViewModifier for navigation notification handlers
struct TimelineNavigationNotifications: ViewModifier {
    let onZoomToSelection: () -> Void
    let onGoToNextRegion: () -> Void
    let onGoToPreviousRegion: () -> Void
    let onMoveBeatForward: () -> Void
    let onMoveBeatBackward: () -> Void
    let onMoveBarForward: () -> Void
    let onMoveBarBackward: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .zoomToSelection)) { _ in
                onZoomToSelection()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goToNextRegion)) { _ in
                onGoToNextRegion()
            }
            .onReceive(NotificationCenter.default.publisher(for: .goToPreviousRegion)) { _ in
                onGoToPreviousRegion()
            }
            .onReceive(NotificationCenter.default.publisher(for: .moveBeatForward)) { _ in
                onMoveBeatForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .moveBeatBackward)) { _ in
                onMoveBeatBackward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .moveBarForward)) { _ in
                onMoveBarForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .moveBarBackward)) { _ in
                onMoveBarBackward()
            }
    }
}

