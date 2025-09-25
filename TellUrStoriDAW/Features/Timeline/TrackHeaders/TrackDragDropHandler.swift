//
//  TrackDragDropHandler.swift
//  TellUrStoriDAW
//
//  Drag-and-drop functionality for professional track reordering
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Track Drag Drop Handler
@MainActor
struct TrackDragDropHandler {
    let headerManager: TrackHeaderManager
    
    // MARK: - Drag Operations
    func handleTrackDragStart(trackID: UUID) {
        headerManager.handleTrackDragStart(trackID: trackID)
    }
    
    func handleTrackDragEnd() {
        headerManager.handleTrackDragEnd()
    }
    
    func handleTrackReorder(from sourceIndices: IndexSet, to destination: Int) -> Bool {
        guard validateReorderOperation(from: sourceIndices, to: destination) else {
            return false
        }
        
        headerManager.moveTrack(from: sourceIndices, to: destination)
        return true
    }
    
    // MARK: - Validation
    private func validateReorderOperation(from sourceIndices: IndexSet, to destination: Int) -> Bool {
        // Ensure indices are valid
        guard let firstIndex = sourceIndices.first,
              firstIndex >= 0,
              firstIndex < headerManager.tracks.count,
              destination >= 0,
              destination <= headerManager.tracks.count else {
            return false
        }
        
        // Don't allow reordering to the same position
        if sourceIndices.contains(destination) || sourceIndices.contains(destination - 1) {
            return false
        }
        
        return true
    }
    
    func validateDropTarget(_ target: DropTarget) -> Bool {
        // Validate drop target based on track type compatibility
        switch target.targetType {
        case .track:
            return true
        case .bus:
            return false // Don't allow dropping tracks on buses
        case .folder:
            return true // Allow dropping in track folders
        }
    }
    
    func animateReorderTransition() -> Animation {
        .spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.1)
    }
}

// MARK: - Drop Target
enum DropTarget {
    case track(id: UUID)
    case bus(id: UUID)
    case folder(id: UUID)
    
    var targetType: DropTargetType {
        switch self {
        case .track:
            return .track
        case .bus:
            return .bus
        case .folder:
            return .folder
        }
    }
}

enum DropTargetType {
    case track
    case bus
    case folder
}

// MARK: - Draggable Track Header
// Note: DraggableTrackHeader has been moved to its own dedicated file:
// TellUrStoriDAW/Features/Timeline/DraggableTrackHeader.swift

// MARK: - Track List with Drag and Drop
struct DraggableTrackList: View {
    @ObservedObject var headerManager: TrackHeaderManager
    let trackHeight: CGFloat
    
    private let dragDropHandler: TrackDragDropHandler
    
    init(headerManager: TrackHeaderManager, trackHeight: CGFloat = 80) {
        self.headerManager = headerManager
        self.trackHeight = trackHeight
        self.dragDropHandler = TrackDragDropHandler(headerManager: headerManager)
    }
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(headerManager.tracks) { track in
                    DraggableTrackHeader(
                        track: track,
                        isSelected: headerManager.selectedTrackIDs.contains(track.id),
                        height: headerManager.trackHeights[track.id] ?? trackHeight,
                        headerManager: headerManager,
                        dragDropHandler: dragDropHandler
                    )
                    .id(track.id)
                }
            }
        }
        .animation(dragDropHandler.animateReorderTransition(), value: headerManager.tracks)
    }
}

// MARK: - Drop Indicator
struct TrackDropIndicator: View {
    let isVisible: Bool
    let color: Color
    
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 2)
            .opacity(isVisible ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.2), value: isVisible)
    }
}

// MARK: - Drag Preview
struct TrackDragPreview: View {
    let track: TrackHeaderModel
    let height: CGFloat
    
    var body: some View {
        HStack(spacing: 8) {
            // Track color indicator
            Rectangle()
                .fill(track.color.color)
                .frame(width: 4, height: height * 0.8)
                .cornerRadius(2)
            
            // Track info
            VStack(alignment: .leading, spacing: 2) {
                Text(track.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                
                Text("Track \(track.trackNumber)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Track type icon
            Image(systemName: track.typeIcon)
                .font(.system(size: 12))
                .foregroundColor(track.color.color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
    }
}
