//
//  DraggableTrackHeader.swift
//  TellUrStoriDAW
//
//  Draggable wrapper for professional track headers with reordering support
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Draggable Track Header
struct DraggableTrackHeader: View {
    let track: TrackHeaderModel
    let isSelected: Bool
    let height: CGFloat
    let headerManager: TrackHeaderManager
    let dragDropHandler: TrackDragDropHandler
    
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    @State private var dragPreviewOpacity: Double = 1.0
    
    var body: some View {
        ProfessionalTrackHeader(
            track: track,
            isSelected: isSelected,
            height: height,
            headerManager: headerManager
        )
        .opacity(isDragging ? 0.5 : 1.0)
        .offset(dragOffset)
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .shadow(color: .black.opacity(isDragging ? 0.3 : 0.1), radius: isDragging ? 8 : 2)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
        .gesture(
            DragGesture(coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        dragDropHandler.handleTrackDragStart(trackID: track.id)
                    }
                    
                    dragOffset = value.translation
                }
                .onEnded { value in
                    handleDragEnd(with: value)
                }
        )
        .onDrop(of: [.text], isTargeted: nil) { providers, location in
            handleTrackDrop(providers: providers, at: location)
        }
    }
    
    private func handleDragEnd(with value: DragGesture.Value) {
        withAnimation(dragDropHandler.animateReorderTransition()) {
            dragOffset = .zero
            isDragging = false
        }
        
        dragDropHandler.handleTrackDragEnd()
        
        // Calculate drop position based on drag translation
        let dragDistance = value.translation.height
        let trackHeight = height
        let positionChange = Int(round(dragDistance / trackHeight))
        
        if abs(positionChange) > 0 {
            if let currentIndex = headerManager.tracks.firstIndex(where: { $0.id == track.id }) {
                let newIndex = max(0, min(headerManager.tracks.count - 1, currentIndex + positionChange))
                if newIndex != currentIndex {
                    let indexSet = IndexSet(integer: currentIndex)
                    _ = dragDropHandler.handleTrackReorder(from: indexSet, to: newIndex)
                }
            }
        }
    }
    
    private func handleTrackDrop(providers: [NSItemProvider], at location: CGPoint) -> Bool {
        // Handle external drops (e.g., audio files)
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.audio.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.audio.identifier, options: nil) { item, error in
                    if let url = item as? URL {
                        // Handle audio file drop
                        Task { @MainActor in
                            // This would integrate with the existing audio import system
                            print("Audio file dropped on track \(track.name): \(url)")
                        }
                    }
                }
                return true
            }
        }
        
        return false
    }
}
