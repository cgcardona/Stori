//
//  AudioRegionPositioning.swift
//  Stori
//
//  Extracted from IntegratedTimelineView.swift
//  Contains audio region positioning and selection isolation for timeline performance
//

import SwiftUI

// MARK: - Audio Regions Layer (Isolated Observer)
/// Isolates audio selection observation from parent views
/// Reads selection ONCE here, passes Bool to children to avoid N observers
struct AudioRegionsLayer: View {
    let regions: [AudioRegion]
    let pixelsPerBeat: CGFloat
    let trackHeight: CGFloat
    var selection: SelectionManager  // Only THIS view observes audio selection
    let onRegionMove: (UUID, TimeInterval) -> Void
    let onRegionMoveToTrack: ((UUID, UUID, TimeInterval) -> Void)?
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    let trackId: UUID
    let snapToGrid: Bool
    let timeDisplayMode: TimeDisplayMode
    
    var body: some View {
        // Read selection ONCE here - only this view becomes an observer
        let selectedIDs = selection.selectedRegionIds
        let anchorID = selection.selectionAnchor
        let isMultiSelected = selectedIDs.count > 1
        
        ForEach(regions) { region in
            let otherIDs = selectedIDs.subtracting([region.id])
            
            PositionedAudioRegion(
                region: region,
                pixelsPerBeat: pixelsPerBeat,
                trackHeight: trackHeight,
                isSelected: selectedIDs.contains(region.id),  // Pass Bool, not SelectionManager
                isAnchor: region.id == anchorID,
                isMultiSelected: isMultiSelected,
                otherSelectedRegionIds: otherIDs,
                onSelect: { selection.selectOnly(region.id) },
                onToggle: { selection.toggle(region.id) },
                onRangeSelect: { ids in selection.selectRange(in: ids, to: region.id) },
                onRegionMove: onRegionMove,
                onRegionMoveToTrack: onRegionMoveToTrack,
                audioEngine: audioEngine,
                projectManager: projectManager,
                trackId: trackId,
                snapToGrid: snapToGrid,
                timeDisplayMode: timeDisplayMode
            )
        }
    }
}

// MARK: - Positioned Audio Region Wrapper

/// Wrapper that handles audio region dragging, repositioning, and cross-track movement
/// Uses shared RegionDragHandler for consistent behavior with MIDI regions
struct PositionedAudioRegion: View {
    let region: AudioRegion
    let pixelsPerBeat: CGFloat
    let trackHeight: CGFloat
    let isSelected: Bool  // Passed from parent - no observation here
    let isAnchor: Bool
    let isMultiSelected: Bool  // True if more than 1 region is selected
    let otherSelectedRegionIds: Set<UUID>  // For batch operations
    let onSelect: () -> Void
    let onToggle: () -> Void
    let onRangeSelect: ([UUID]) -> Void
    let onRegionMove: (UUID, TimeInterval) -> Void
    let onRegionMoveToTrack: ((UUID, UUID, TimeInterval) -> Void)?
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    let trackId: UUID
    let snapToGrid: Bool
    let timeDisplayMode: TimeDisplayMode
    
    // Shared drag state (uses RegionDragState from shared component)
    @State private var dragState = RegionDragState()
    
    private var tempo: Double { projectManager.currentProject?.tempo ?? 120.0 }
    
    // MARK: - Drag Configuration
    
    private var dragConfig: RegionDragConfig {
        RegionDragConfig(
            regionId: region.id,
            trackId: trackId,
            startPositionBeats: region.startBeat,
            pixelsPerBeat: pixelsPerBeat,
            tempo: tempo,
            trackHeight: trackHeight,
            snapToGrid: snapToGrid,
            timeDisplayMode: timeDisplayMode,
            customSnapFunction: smartSnapFunction
        )
    }
    
    /// Smart snap function for audio regions - tries beat alignment first, then grid snap
    private var smartSnapFunction: ((Double) -> Double)? {
        return { [self] proposedBeat in
            // Try smart beat snap first
            if let smartBeat = calculateSmartBeatSnap(
                regionId: region.id,
                proposedStartBeat: proposedBeat,
                regionDurationBeats: region.durationBeats,
                regionBeats: region.detectedBeats
            ) {
                return smartBeat
            }
            // Fall back to grid snap
            return calculateGridSnapInterval(for: proposedBeat, mode: timeDisplayMode, tempo: tempo)
        }
    }
    
    private var dragHandler: RegionDragHandler {
        RegionDragHandler(
            config: dragConfig,
            dragState: dragState,
            onSelect: {
                if !isSelected {
                    onSelect()
                }
            },
            onDragComplete: handleDragComplete,
            getTargetTrack: getTargetAudioTrack
        )
    }
    
    // MARK: - Drag Completion Handler
    
    private func handleDragComplete(_ result: RegionDragResult) {
        let newPositionBeats = result.newPositionBeats
        
        if let targetTrackId = result.targetTrackId {
            // Moving to different track
            if result.isDuplication {
                duplicateRegionToTrack(targetTrackId: targetTrackId, startBeat: newPositionBeats)
            } else {
                onRegionMoveToTrack?(result.regionId, targetTrackId, newPositionBeats)
            }
        } else {
            // Same track movement
            if result.isDuplication {
                duplicateRegionAt(startBeat: newPositionBeats)
            } else {
                onRegionMove(result.regionId, newPositionBeats)
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        let baseX = region.startBeat * pixelsPerBeat
        
        return ZStack(alignment: .topLeading) {
            // Ghost region at original position (only visible when dragging)
            if dragState.isDragging {
                IntegratedAudioRegion(
                    region: region,
                    pixelsPerBeat: pixelsPerBeat,
                    tempo: tempo,
                    trackHeight: trackHeight,
                    isSelected: isSelected,
                    isMultiSelected: isMultiSelected,
                    otherSelectedRegionIds: otherSelectedRegionIds,
                    onSelect: onSelect,
                    onToggle: onToggle,
                    onRangeSelect: onRangeSelect,
                    timeDisplayMode: timeDisplayMode,
                    audioEngine: audioEngine,
                    projectManager: projectManager,
                    trackId: trackId,
                    snapToGrid: snapToGrid,
                    isAnchor: isAnchor
                )
                .opacity(0.3)
                .allowsHitTesting(false)
                .offset(x: baseX, y: RegionLayout.verticalMargin)
            }
            
            // Actual draggable region with shared drag behavior
            IntegratedAudioRegion(
                region: region,
                pixelsPerBeat: pixelsPerBeat,
                tempo: tempo,
                trackHeight: trackHeight,
                isSelected: isSelected,
                isMultiSelected: isMultiSelected,
                otherSelectedRegionIds: otherSelectedRegionIds,
                onSelect: onSelect,
                onToggle: onToggle,
                onRangeSelect: onRangeSelect,
                timeDisplayMode: timeDisplayMode,
                audioEngine: audioEngine,
                projectManager: projectManager,
                trackId: trackId,
                snapToGrid: snapToGrid,
                isAnchor: isAnchor
            )
            .offset(
                x: baseX + (dragState.isDragging ? dragState.dragOffset : 0),
                y: RegionLayout.verticalMargin + (dragState.isDragging ? dragState.verticalDragOffset : 0)
            )
            .zIndex(dragState.isDragging ? 100 : 10)
            .gesture(makeRegionDragGesture(handler: dragHandler))
        }
    }
    
    // MARK: - Helper Functions
    
    private func getTargetAudioTrack(currentTrackId: UUID, offset: Int) -> UUID? {
        guard let project = projectManager.currentProject else { return nil }
        guard let currentIndex = project.tracks.firstIndex(where: { $0.id == currentTrackId }) else { return nil }
        
        let targetIndex = currentIndex + offset
        guard targetIndex >= 0 && targetIndex < project.tracks.count else { return nil }
        
        let targetTrack = project.tracks[targetIndex]
        
        // Only allow dropping on audio tracks
        guard !targetTrack.isMIDITrack else {
            return nil
        }
        
        return targetTrack.id
    }
    
    private func duplicateRegionAt(startBeat: Double) {
        let tempo = projectManager.currentProject?.tempo ?? 120.0
        var duplicatedRegion = AudioRegion(
            audioFile: region.audioFile,
            startBeat: startBeat,
            durationBeats: region.durationBeats,
            tempo: tempo,
            fadeIn: region.fadeIn,
            fadeOut: region.fadeOut,
            gain: region.gain,
            isLooped: region.isLooped,
            offset: region.offset
        )
        duplicatedRegion.detectedBeats = region.detectedBeats
        duplicatedRegion.detectedTempo = region.detectedTempo
        duplicatedRegion.detectedKey = region.detectedKey
        projectManager.addRegionToTrack(duplicatedRegion, trackId: trackId)
    }
    
    private func duplicateRegionToTrack(targetTrackId: UUID, startBeat: Double) {
        let tempo = projectManager.currentProject?.tempo ?? 120.0
        var duplicatedRegion = AudioRegion(
            audioFile: region.audioFile,
            startBeat: startBeat,
            durationBeats: region.durationBeats,
            tempo: tempo,
            fadeIn: region.fadeIn,
            fadeOut: region.fadeOut,
            gain: region.gain,
            isLooped: region.isLooped,
            offset: region.offset
        )
        duplicatedRegion.detectedBeats = region.detectedBeats
        duplicatedRegion.detectedTempo = region.detectedTempo
        duplicatedRegion.detectedKey = region.detectedKey
        projectManager.addRegionToTrack(duplicatedRegion, trackId: targetTrackId)
    }
    
    /// Smart beat snap for audio regions - aligns beats between adjacent regions
    private func calculateSmartBeatSnap(
        regionId: UUID,
        proposedStartBeat: Double,
        regionDurationBeats: Double,
        regionBeats: [TimeInterval]?
    ) -> Double? {
        guard timeDisplayMode == .beats else { return nil }
        guard let project = projectManager.currentProject else { return nil }
        guard let regionBeats = regionBeats, !regionBeats.isEmpty else { return nil }
        
        let secondsPerBeat = 60.0 / tempo
        let proposedEndBeat = proposedStartBeat + regionDurationBeats
        
        // Find adjacent regions
        for track in project.tracks {
            for otherRegion in track.regions where otherRegion.id != regionId {
                guard let otherBeats = otherRegion.detectedBeats, !otherBeats.isEmpty else { continue }
                
                let otherEndBeat = otherRegion.endBeat
                
                // Check if regions are adjacent (within 2 beats)
                let gapAfterOther = proposedStartBeat - otherEndBeat
                let gapBeforeOther = otherRegion.startBeat - proposedEndBeat
                
                if abs(gapAfterOther) < 2.0 {
                    // This region follows the other - try to align first beats
                    if let firstBeat = regionBeats.first, let lastOtherBeat = otherBeats.last {
                        let firstBeatInBeats = firstBeat / secondsPerBeat
                        let lastOtherBeatInBeats = lastOtherBeat / secondsPerBeat
                        
                        let otherRegionEndBeat = otherEndBeat
                        let lastOtherBeatAbsolute = otherRegion.startBeat + lastOtherBeatInBeats
                        
                        // Calculate beat interval from other region
                        if otherBeats.count >= 2 {
                            let beatInterval = (otherBeats[1] - otherBeats[0]) / secondsPerBeat
                            let nextExpectedBeat = lastOtherBeatAbsolute + beatInterval
                            
                            // Align our first beat to the expected position
                            let adjustment = nextExpectedBeat - (proposedStartBeat + firstBeatInBeats)
                            if abs(adjustment) < 1.0 {
                                return proposedStartBeat + adjustment
                            }
                        }
                    }
                } else if abs(gapBeforeOther) < 2.0 {
                    // This region precedes the other - try to align last beats
                    if let lastBeat = regionBeats.last, let firstOtherBeat = otherBeats.first {
                        let lastBeatInBeats = lastBeat / secondsPerBeat
                        let firstOtherBeatInBeats = firstOtherBeat / secondsPerBeat
                        
                        let firstOtherBeatAbsolute = otherRegion.startBeat + firstOtherBeatInBeats
                        
                        // Calculate beat interval from our region
                        if regionBeats.count >= 2 {
                            let beatInterval = (regionBeats[1] - regionBeats[0]) / secondsPerBeat
                            let ourLastBeatAbsolute = proposedStartBeat + lastBeatInBeats
                            let expectedNextBeat = ourLastBeatAbsolute + beatInterval
                            
                            // Align so our beat grid continues to other region's first beat
                            let adjustment = firstOtherBeatAbsolute - expectedNextBeat
                            if abs(adjustment) < 1.0 {
                                return proposedStartBeat + adjustment
                            }
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    /// Grid snap helper (local to avoid name collision with file-level helper)
    private func calculateGridSnapInterval(for beats: Double, mode: TimeDisplayMode, tempo: Double) -> Double {
        switch mode {
        case .beats:
            return round(beats)
        case .time:
            let secondsPerBeat = 60.0 / tempo
            let seconds = beats * secondsPerBeat
            let snappedSeconds = round(seconds * 10) / 10
            return snappedSeconds / secondsPerBeat
        }
    }
}
