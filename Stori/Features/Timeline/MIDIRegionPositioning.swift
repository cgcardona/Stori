//
//  MIDIRegionPositioning.swift
//  Stori
//
//  Extracted from IntegratedTimelineView.swift
//  Contains MIDI region positioning and selection isolation for timeline performance
//

import SwiftUI

// MARK: - MIDI Regions Layer (Isolated Observer)
/// Isolates MIDI selection observation from parent views
/// Reads selection ONCE here, passes Bool to children to avoid N observers
struct MIDIRegionsLayer: View {
    let midiRegions: [MIDIRegion]
    let trackColor: Color
    let pixelsPerBeat: CGFloat
    let trackHeight: CGFloat
    var selection: SelectionManager  // Only THIS view observes MIDI selection
    var projectManager: ProjectManager
    let trackId: UUID
    let snapToGrid: Bool
    let timeDisplayMode: TimeDisplayMode
    let tempo: Double
    var scrollOffset: CGFloat = 0
    var viewportWidth: CGFloat = 1200
    let onDoubleClick: (MIDIRegion) -> Void
    let onBounce: (MIDIRegion) -> Void
    let onDelete: (MIDIRegion) -> Void
    
    var body: some View {
        // Read selection ONCE here - only this view becomes an observer
        let selectedID = selection.selectedMIDIRegionId
        
        ForEach(midiRegions) { midiRegion in
            PositionedMIDIRegion(
                region: midiRegion,
                trackColor: trackColor,
                pixelsPerBeat: pixelsPerBeat,
                trackHeight: trackHeight,
                isSelected: midiRegion.id == selectedID,  // Pass Bool, not SelectionManager
                onSelect: { selection.selectMIDIRegion(midiRegion.id) },
                projectManager: projectManager,
                trackId: trackId,
                snapToGrid: snapToGrid,
                timeDisplayMode: timeDisplayMode,
                tempo: tempo,
                scrollOffset: scrollOffset,
                viewportWidth: viewportWidth,
                onDoubleClick: { onDoubleClick(midiRegion) },
                onBounce: { onBounce(midiRegion) },
                onDelete: { onDelete(midiRegion) }
            )
        }
    }
}

// MARK: - Positioned MIDI Region Wrapper

/// Wrapper that handles MIDI region dragging, repositioning, and cross-track movement
/// Uses shared RegionDragHandler for consistent behavior with audio regions
struct PositionedMIDIRegion: View {
    let region: MIDIRegion
    let trackColor: Color
    let pixelsPerBeat: CGFloat  // Beat-based timeline (proper DAW architecture)
    let trackHeight: CGFloat
    let isSelected: Bool  // Passed from parent - no observation here
    let onSelect: () -> Void  // Closure to select - no SelectionManager access
    var projectManager: ProjectManager
    let trackId: UUID
    let snapToGrid: Bool
    let timeDisplayMode: TimeDisplayMode
    let tempo: Double
    var scrollOffset: CGFloat = 0
    var viewportWidth: CGFloat = 1200
    
    // Callbacks
    let onDoubleClick: () -> Void
    let onBounce: () -> Void
    let onDelete: () -> Void
    
    // Shared drag state (uses RegionDragState from shared component)
    @State private var dragState = RegionDragState()
    
    // MARK: - Track Properties
    
    private var trackName: String {
        guard let track = projectManager.currentProject?.tracks.first(where: { $0.id == trackId }) else {
            return "MIDI Track"
        }
        return track.name
    }
    
    private var trackIcon: String {
        guard let track = projectManager.currentProject?.tracks.first(where: { $0.id == trackId }) else {
            return "pianokeys"
        }
        
        // First check for explicit icon override
        if let explicitIcon = track.iconName, !explicitIcon.isEmpty {
            return explicitIcon
        }
        
        // Use track type icon for MIDI/Instrument tracks
        if track.isMIDITrack {
            return track.trackTypeIcon
        }
        
        return defaultIconName(for: track.name)
    }
    
    private var isDrumTrack: Bool {
        guard let track = projectManager.currentProject?.tracks.first(where: { $0.id == trackId }) else {
            return false
        }
        // Track is a drum track if it has a drumKitId set
        return track.drumKitId != nil
    }
    
    private func defaultIconName(for trackName: String) -> String {
        let name = trackName.lowercased()
        if name.contains("kick") || name.contains("drum") { return "music.note" }
        if name.contains("bass") { return "waveform" }
        if name.contains("guitar") { return "guitars" }
        if name.contains("piano") || name.contains("keys") { return "pianokeys" }
        if name.contains("vocal") || name.contains("voice") { return "mic" }
        if name.contains("synth") { return "tuningfork" }
        return "music.quarternote.3"
    }
    
    // MARK: - Drag Configuration
    
    private var dragConfig: RegionDragConfig {
        RegionDragConfig(
            regionId: region.id,
            trackId: trackId,
            startPositionBeats: region.startTime,  // MIDI startTime is in beats
            pixelsPerBeat: pixelsPerBeat,
            tempo: tempo,
            trackHeight: trackHeight,
            snapToGrid: snapToGrid,
            timeDisplayMode: timeDisplayMode
        )
    }
    
    private var dragHandler: RegionDragHandler {
        RegionDragHandler(
            config: dragConfig,
            dragState: dragState,
            onSelect: onSelect,  // Use closure from parent
            onDragComplete: handleDragComplete,
            getTargetTrack: getTargetMIDITrack
        )
    }
    
    // MARK: - Resize Handlers
    
    private func handleMIDIRegionLoop(regionId: UUID, newDuration: TimeInterval) {
        guard var project = projectManager.currentProject else { return }
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) else {
            return
        }
        
        let region = project.tracks[trackIndex].midiRegions[regionIndex]
        let loopUnit = region.contentLength > 0 ? region.contentLength : region.duration
        let originalNotes = region.notes
        
        let loopCount = Int(ceil(newDuration / loopUnit))
        
        var loopedNotes: [MIDINote] = []
        for loopIndex in 0..<loopCount {
            let timeOffset = loopUnit * Double(loopIndex)
            
            for note in originalNotes {
                if note.startTime >= loopUnit { continue }
                
                let newNote = MIDINote(
                    id: UUID(),
                    pitch: note.pitch,
                    velocity: note.velocity,
                    startTime: note.startTime + timeOffset,
                    duration: note.duration,
                    channel: note.channel
                )
                
                if newNote.startTime < newDuration {
                    loopedNotes.append(newNote)
                }
            }
        }
        
        project.tracks[trackIndex].midiRegions[regionIndex].notes = loopedNotes
        project.tracks[trackIndex].midiRegions[regionIndex].duration = newDuration
        project.tracks[trackIndex].midiRegions[regionIndex].isLooped = newDuration > loopUnit
        
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    private func handleMIDIRegionResize(regionId: UUID, newDuration: TimeInterval) {
        guard var project = projectManager.currentProject else { return }
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let regionIndex = project.tracks[trackIndex].midiRegions.firstIndex(where: { $0.id == regionId }) else {
            return
        }
        
        let safeDuration = max(0.1, newDuration)
        project.tracks[trackIndex].midiRegions[regionIndex].duration = safeDuration
        project.tracks[trackIndex].midiRegions[regionIndex].contentLength = safeDuration
        project.tracks[trackIndex].midiRegions[regionIndex].isLooped = false
        
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
    }
    
    // MARK: - Drag Completion Handler
    
    private func handleDragComplete(_ result: RegionDragResult) {
        let newPositionBeats = result.newPositionBeats
        
        if let targetTrackId = result.targetTrackId {
            // Moving to different track
            if result.isDuplication {
                projectManager.duplicateMIDIRegionToTrack(
                    result.regionId,
                    from: result.originalTrackId,
                    to: targetTrackId,
                    at: newPositionBeats
                )
            } else {
                projectManager.moveMIDIRegionToTrack(
                    result.regionId,
                    from: result.originalTrackId,
                    to: targetTrackId,
                    newStartTime: newPositionBeats
                )
            }
        } else {
            // Same track movement
            if result.isDuplication {
                projectManager.duplicateMIDIRegion(
                    result.regionId,
                    on: result.originalTrackId,
                    at: newPositionBeats
                )
            } else {
                projectManager.moveMIDIRegion(
                    result.regionId,
                    on: result.originalTrackId,
                    to: newPositionBeats
                )
            }
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        let baseX = CGFloat(region.startTime) * pixelsPerBeat
        
        return ZStack(alignment: .topLeading) {
            // Ghost region at original position (only visible when dragging)
            if dragState.isDragging {
            MIDIRegionView(
                region: region,
                trackColor: trackColor.opacity(0.3),
                pixelsPerBeat: pixelsPerBeat,
                trackHeight: trackHeight,
                isSelected: false,
                onSelect: {},
                onDoubleClick: {},
                trackName: trackName,
                trackIcon: trackIcon,
                isDrumTrack: isDrumTrack
            )
                .opacity(0.5)
                .offset(x: baseX, y: RegionLayout.verticalMargin)
            }
            
            // Actual draggable region with shared drag behavior
            MIDIRegionView(
                region: region,
                trackColor: trackColor,
                pixelsPerBeat: pixelsPerBeat,
                trackHeight: trackHeight,
                isSelected: isSelected,
                onSelect: onSelect,  // Use closure from parent
                onDoubleClick: onDoubleClick,
                onBounceToAudio: onBounce,
                onDelete: onDelete,
                onLoop: handleMIDIRegionLoop,
                onResize: handleMIDIRegionResize,
                trackName: trackName,
                trackIcon: trackIcon,
                isDrumTrack: isDrumTrack,
                snapToGrid: snapToGrid,
                tempo: tempo,
                scrollOffset: scrollOffset,
                viewportWidth: viewportWidth
            )
            .offset(
                x: baseX + dragState.dragOffset,
                y: RegionLayout.verticalMargin + dragState.verticalDragOffset
            )
            .zIndex(dragState.isDragging ? 100 : 10)
            .gesture(makeRegionDragGesture(handler: dragHandler))
        }
    }
    
    // MARK: - Target Track Helper
    
    private func getTargetMIDITrack(currentTrackId: UUID, offset: Int) -> UUID? {
        guard let project = projectManager.currentProject else { return nil }
        guard let currentIndex = project.tracks.firstIndex(where: { $0.id == currentTrackId }) else { return nil }
        
        let targetIndex = currentIndex + offset
        guard targetIndex >= 0 && targetIndex < project.tracks.count else { return nil }
        
        let targetTrack = project.tracks[targetIndex]
        
        // Only allow dropping on MIDI tracks
        guard targetTrack.isMIDITrack else {
            return nil
        }
        
        return targetTrack.id
    }
}
