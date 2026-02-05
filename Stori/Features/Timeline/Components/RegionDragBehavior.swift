// RegionDragBehavior.swift
// Stori
//
// Shared drag behavior for audio and MIDI regions
// Features: visual snap during drag, ghost region, track-to-track movement, duplication

import SwiftUI
import AppKit

// MARK: - Shared Region Layout Constants
// These ensure consistent visual appearance between audio and MIDI regions

enum RegionLayout {
    /// Vertical margin above and below regions within a track
    /// Set to 0 for regions to fill full track height
    static let verticalMargin: CGFloat = 0
    
    /// Total height reduction from track height (verticalMargin * 2)
    static let heightReduction: CGFloat = 0
    
    /// Corner radius for region containers
    static let cornerRadius: CGFloat = 4
    
    /// Header height for region name bar
    static let headerHeight: CGFloat = 20
    
    /// Border width for region outline
    static let borderWidth: CGFloat = 1
    
    /// Selection stroke width
    static let selectionStrokeWidth: CGFloat = 3
    
    /// Calculate region height from track height
    static func regionHeight(for trackHeight: CGFloat) -> CGFloat {
        trackHeight - heightReduction
    }
}

// MARK: - Region Drag Configuration

/// Configuration for region drag behavior
struct RegionDragConfig {
    let regionId: UUID
    let trackId: UUID
    let startPositionBeats: Double    // Current position in beats
    let pixelsPerBeat: CGFloat
    let tempo: Double
    let trackHeight: CGFloat
    let snapToGrid: Bool
    let timeDisplayMode: TimeDisplayMode
    
    /// Optional custom snap function for advanced snapping (e.g., smart beat snap for audio regions)
    /// Takes proposed beats and returns snapped beats
    var customSnapFunction: ((Double) -> Double)?
    
    var secondsPerBeat: Double { 60.0 / tempo }
    var pixelsPerSecond: CGFloat { pixelsPerBeat / CGFloat(secondsPerBeat) }
    
    init(
        regionId: UUID,
        trackId: UUID,
        startPositionBeats: Double,
        pixelsPerBeat: CGFloat,
        tempo: Double,
        trackHeight: CGFloat,
        snapToGrid: Bool,
        timeDisplayMode: TimeDisplayMode,
        customSnapFunction: ((Double) -> Double)? = nil
    ) {
        self.regionId = regionId
        self.trackId = trackId
        self.startPositionBeats = startPositionBeats
        self.pixelsPerBeat = pixelsPerBeat
        self.tempo = tempo
        self.trackHeight = trackHeight
        self.snapToGrid = snapToGrid
        self.timeDisplayMode = timeDisplayMode
        self.customSnapFunction = customSnapFunction
    }
}

// MARK: - Region Drag Result

/// Result of a completed drag operation
struct RegionDragResult {
    let regionId: UUID
    let originalTrackId: UUID
    let targetTrackId: UUID?          // nil if staying on same track
    let newPositionBeats: Double      // New start position in beats
    let isDuplication: Bool           // Option key was held
    let trackOffset: Int              // Number of tracks moved (can be negative)
}

// MARK: - Region Drag State

/// Observable state for region drag operations
@Observable
final class RegionDragState {
    var isDragging: Bool = false
    var dragOffset: CGFloat = 0
    var verticalDragOffset: CGFloat = 0
    
    func reset() {
        isDragging = false
        dragOffset = 0
        verticalDragOffset = 0
    }
    
    // MARK: - Cleanup
    
    deinit {
        // CRITICAL: Protective deinit for @Observable class (ASan Issue #84742+)
        // Root cause: @Observable classes have implicit Swift Concurrency tasks
        // for property change notifications that can cause double-free on deinit.
        // See: MetronomeEngine, ProjectExportService, AutomationServer, LLMComposerClient,
        //      AudioAnalysisService, AudioExportService, SelectionManager, ScrollSyncModel
        // https://github.com/cgcardona/Stori/issues/AudioEngine-MemoryBug
    }
}

// MARK: - Region Drag Handler

/// Shared drag handling logic for audio and MIDI regions
/// Encapsulates all the drag gesture behavior in one place
struct RegionDragHandler {
    let config: RegionDragConfig
    let dragState: RegionDragState
    let onSelect: () -> Void
    let onDragComplete: (RegionDragResult) -> Void
    let getTargetTrack: (UUID, Int) -> UUID?
    
    // MARK: - Drag Changed
    
    func handleDragChanged(_ value: DragGesture.Value) {
        if !dragState.isDragging {
            dragState.isDragging = true
            onSelect()
        }
        
        // Calculate raw offsets
        let absoluteOffset = value.location.x - value.startLocation.x
        let absoluteVerticalOffset = value.location.y - value.startLocation.y
        
        // Check modifier keys
        let isCommandPressed = NSEvent.modifierFlags.contains(.command)
        let shouldSnap = config.snapToGrid && !isCommandPressed
        
        // Horizontal offset with visual snapping
        if shouldSnap {
            // Calculate snapped position in beats
            let beatOffset = absoluteOffset / config.pixelsPerBeat
            let newPositionBeats = max(0, config.startPositionBeats + beatOffset)
            let snappedBeats = calculateSnapInterval(
                for: newPositionBeats,
                mode: config.timeDisplayMode,
                tempo: config.tempo
            )
            let snappedOffset = snappedBeats - config.startPositionBeats
            dragState.dragOffset = snappedOffset * config.pixelsPerBeat
        } else {
            // Smooth movement without snap
            dragState.dragOffset = absoluteOffset
        }
        
        // Vertical offset snaps to track lanes in real-time
        let trackOffset = round(absoluteVerticalOffset / config.trackHeight)
        dragState.verticalDragOffset = trackOffset * config.trackHeight
    }
    
    // MARK: - Drag Ended
    
    func handleDragEnded(_ value: DragGesture.Value) {
        let absoluteOffset = value.location.x - value.startLocation.x
        let verticalOffset = value.location.y - value.startLocation.y
        
        // Check modifier keys
        let isOptionPressed = NSEvent.modifierFlags.contains(.option)
        let isCommandPressed = NSEvent.modifierFlags.contains(.command)
        let shouldSnap = config.snapToGrid && !isCommandPressed
        
        // Calculate new position in beats
        let beatOffset = absoluteOffset / config.pixelsPerBeat
        let newPositionBeats = max(0, config.startPositionBeats + beatOffset)
        
        // Apply snapping (custom function takes priority if provided)
        let snappedPositionBeats: Double
        if shouldSnap {
            if let customSnap = config.customSnapFunction {
                // Use custom snap function (e.g., smart beat snap for audio regions)
                snappedPositionBeats = customSnap(newPositionBeats)
            } else {
                // Default grid snap
                snappedPositionBeats = calculateSnapInterval(
                    for: newPositionBeats,
                    mode: config.timeDisplayMode,
                    tempo: config.tempo
                )
            }
        } else {
            snappedPositionBeats = newPositionBeats
        }
        
        // Round to avoid floating-point precision errors
        let roundedPositionBeats = round(snappedPositionBeats * 1000000) / 1000000
        
        // Calculate track offset
        let trackOffset = Int(round(verticalOffset / config.trackHeight))
        let targetTrackId = trackOffset != 0 ? getTargetTrack(config.trackId, trackOffset) : nil
        
        // Create result
        let result = RegionDragResult(
            regionId: config.regionId,
            originalTrackId: config.trackId,
            targetTrackId: targetTrackId,
            newPositionBeats: roundedPositionBeats,
            isDuplication: isOptionPressed,
            trackOffset: trackOffset
        )
        
        // Reset state before callback (prevents visual glitch)
        dragState.reset()
        
        // Notify completion
        onDragComplete(result)
    }
    
    // MARK: - Snap Calculation
    
    /// Calculate snapped position (returns beats). Timeline is beat-based only.
    private func calculateSnapInterval(for beats: Double, mode: TimeDisplayMode, tempo: Double) -> Double {
        return round(beats)
    }
}

// MARK: - Region Drag Gesture

/// A DragGesture wrapper that uses RegionDragHandler
/// Use this to create a consistent drag gesture for any region
func makeRegionDragGesture(handler: RegionDragHandler) -> some Gesture {
    DragGesture(coordinateSpace: .global)
        .onChanged { value in
            handler.handleDragChanged(value)
        }
        .onEnded { value in
            handler.handleDragEnded(value)
        }
}

// MARK: - Region Drag View Modifier

/// ViewModifier that adds shared drag behavior to any region view
struct RegionDragModifier: ViewModifier {
    let config: RegionDragConfig
    let dragState: RegionDragState
    let onSelect: () -> Void
    let onDragComplete: (RegionDragResult) -> Void
    let getTargetTrack: (UUID, Int) -> UUID?
    
    private var handler: RegionDragHandler {
        RegionDragHandler(
            config: config,
            dragState: dragState,
            onSelect: onSelect,
            onDragComplete: onDragComplete,
            getTargetTrack: getTargetTrack
        )
    }
    
    func body(content: Content) -> some View {
        content
            .offset(x: dragState.dragOffset, y: dragState.verticalDragOffset)
            .zIndex(dragState.isDragging ? 100 : 10)
            .gesture(makeRegionDragGesture(handler: handler))
    }
}

// MARK: - View Extension

extension View {
    /// Apply shared drag behavior to a region
    func regionDragBehavior(
        config: RegionDragConfig,
        dragState: RegionDragState,
        onSelect: @escaping () -> Void,
        onDragComplete: @escaping (RegionDragResult) -> Void,
        getTargetTrack: @escaping (UUID, Int) -> UUID?
    ) -> some View {
        modifier(RegionDragModifier(
            config: config,
            dragState: dragState,
            onSelect: onSelect,
            onDragComplete: onDragComplete,
            getTargetTrack: getTargetTrack
        ))
    }
}

// MARK: - Draggable Region Container

/// A container that shows a ghost region at the original position during drag
/// Use this to wrap your region content for consistent ghost behavior
struct DraggableRegionContainer<RegionContent: View, GhostContent: View>: View {
    let baseX: CGFloat
    let baseY: CGFloat
    let dragState: RegionDragState
    @ViewBuilder let ghostContent: () -> GhostContent
    @ViewBuilder let regionContent: () -> RegionContent
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Ghost at original position (only visible when dragging)
            if dragState.isDragging {
                ghostContent()
                    .opacity(0.3)
                    .allowsHitTesting(false)
                    .offset(x: baseX, y: baseY)
            }
            
            // Actual region (offset applied by drag modifier)
            regionContent()
                .offset(x: baseX, y: baseY)
        }
    }
}

// MARK: - Shared Region Header

/// A shared header component for both audio and MIDI regions
/// Handles selection-aware background coloring consistently
struct RegionHeaderView<Content: View>: View {
    let isSelected: Bool
    let baseColor: Color
    let height: CGFloat
    let cornerRadius: CGFloat
    @ViewBuilder let content: () -> Content
    
    init(
        isSelected: Bool,
        baseColor: Color,
        height: CGFloat = 20,
        cornerRadius: CGFloat = 4,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.isSelected = isSelected
        self.baseColor = baseColor
        self.height = height
        self.cornerRadius = cornerRadius
        self.content = content
    }
    
    var body: some View {
        content()
            .frame(height: height)
            .background(
                Rectangle()
                    .fill(isSelected ? Color.blue : baseColor.opacity(0.8))
            )
            .clipShape(
                RoundedCorners(radius: cornerRadius, corners: [.topLeft, .topRight])
            )
    }
}

// MARK: - Shared Selection Border

/// A shared selection border overlay for regions
/// Includes the glow effect for consistent selection visualization
struct RegionSelectionBorder: View {
    let isSelected: Bool
    let cornerRadius: CGFloat
    let strokeWidth: CGFloat
    
    init(
        isSelected: Bool,
        cornerRadius: CGFloat = 4,
        strokeWidth: CGFloat = 3
    ) {
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
        self.strokeWidth = strokeWidth
    }
    
    var body: some View {
        Group {
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.blue, lineWidth: strokeWidth)
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(Color.blue.opacity(0.3), lineWidth: 6)
                            .blur(radius: 2)
                    )
            }
        }
    }
}

// MARK: - Shared Hover Highlight

/// A shared hover highlight overlay for regions
struct RegionHoverHighlight: View {
    let isHovering: Bool
    let isSelected: Bool
    let cornerRadius: CGFloat
    
    init(
        isHovering: Bool,
        isSelected: Bool,
        cornerRadius: CGFloat = 4
    ) {
        self.isHovering = isHovering
        self.isSelected = isSelected
        self.cornerRadius = cornerRadius
    }
    
    var body: some View {
        Group {
            if isHovering && !isSelected {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.4), lineWidth: 1)
            }
        }
    }
}

/// Helper shape for rounded corners on specific corners only
struct RoundedCorners: Shape {
    var radius: CGFloat
    var corners: UIRectCorner
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let tl = corners.contains(.topLeft) ? radius : 0
        let tr = corners.contains(.topRight) ? radius : 0
        let bl = corners.contains(.bottomLeft) ? radius : 0
        let br = corners.contains(.bottomRight) ? radius : 0
        
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        if tr > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr),
                       radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - br))
        if br > 0 {
            path.addArc(center: CGPoint(x: rect.maxX - br, y: rect.maxY - br),
                       radius: br, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + bl, y: rect.maxY - bl),
                       radius: bl, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 {
            path.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl),
                       radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        }
        path.closeSubpath()
        
        return path
    }
}

/// Corner options for macOS (mirrors UIKit's UIRectCorner)
struct UIRectCorner: OptionSet {
    let rawValue: UInt
    
    static let topLeft = UIRectCorner(rawValue: 1 << 0)
    static let topRight = UIRectCorner(rawValue: 1 << 1)
    static let bottomLeft = UIRectCorner(rawValue: 1 << 2)
    static let bottomRight = UIRectCorner(rawValue: 1 << 3)
    static let allCorners: UIRectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}
