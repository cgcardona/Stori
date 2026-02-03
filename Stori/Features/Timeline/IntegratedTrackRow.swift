//
//  IntegratedTrackRow.swift
//  Stori
//
//  Extracted from IntegratedTimelineView.swift
//  Contains the track row view that displays regions and handles track interactions
//

import SwiftUI

// MARK: - Integrated Track Row

struct IntegratedTrackRow: View {
    let audioTrack: AudioTrack
    @Binding var selectedTrackId: UUID?  // Direct binding for reactive updates
    var selection: SelectionManager   // [V2-MULTISELECT] - also manages MIDI selection
    let height: CGFloat
    let pixelsPerBeat: CGFloat  // Beat-based timeline (proper DAW architecture)
    var audioEngine: AudioEngine
    var projectManager: ProjectManager
    let snapToGrid: Bool
    let timeDisplayMode: TimeDisplayMode
    let onSelect: () -> Void
    let onRegionMove: (UUID, Double) -> Void  // Region move callback (position in beats)
    let onRegionMoveToTrack: (UUID, UUID, UUID, Double) -> Void  // Track-to-track move (position in beats)
    let onMIDIRegionDoubleClick: (MIDIRegion, AudioTrack) -> Void  // Open Piano Roll callback
    let onMIDIRegionBounce: (MIDIRegion, AudioTrack) -> Void  // Bounce to audio callback
    let onMIDIRegionDelete: (MIDIRegion, AudioTrack) -> Void  // Delete MIDI region callback
    var scrollOffset: CGFloat = 0  // [PHASE-8] Viewport culling scroll offset
    var viewportWidth: CGFloat = 1200  // [PHASE-8] Viewport culling width
    
    /// Tempo for beat→seconds conversion
    private var tempo: Double { projectManager.currentProject?.tempo ?? 120.0 }
    private var secondsPerBeat: CGFloat { CGFloat(60.0 / tempo) }
    
    /// Legacy compatibility - derived from beats
    private var pixelsPerSecond: CGFloat { pixelsPerBeat / secondsPerBeat }
    
    // Computed property that will refresh when selectedTrackId binding changes
    private var isSelected: Bool {
        selectedTrackId == audioTrack.id
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Track background
            Rectangle()
                .fill(isSelected ? Color.blue.opacity(0.05) : Color.clear)
            
            // Audio regions
            // PERFORMANCE: Observe selection ONCE here, pass Bool to children to avoid N observers
            AudioRegionsLayer(
                regions: audioTrack.regions,
                pixelsPerBeat: pixelsPerBeat,
                trackHeight: height,
                selection: selection,
                onRegionMove: onRegionMove,
                onRegionMoveToTrack: { regionId, targetTrackId, newStartBeat in
                    onRegionMoveToTrack(regionId, audioTrack.id, targetTrackId, newStartBeat)
                },
                audioEngine: audioEngine,
                projectManager: projectManager,
                trackId: audioTrack.id,
                snapToGrid: snapToGrid,
                timeDisplayMode: timeDisplayMode
            )
            
            // MIDI regions (for MIDI/Instrument tracks) - rendered on top of audio regions
            // PERFORMANCE: Observe selection ONCE here, pass Bool to children to avoid N observers
            MIDIRegionsLayer(
                midiRegions: audioTrack.midiRegions,
                trackColor: audioTrack.color.color,
                pixelsPerBeat: pixelsPerBeat,
                trackHeight: height,
                selection: selection,
                projectManager: projectManager,
                trackId: audioTrack.id,
                snapToGrid: snapToGrid,
                timeDisplayMode: timeDisplayMode,
                tempo: tempo,
                scrollOffset: scrollOffset,
                viewportWidth: viewportWidth,
                onDoubleClick: { region in onMIDIRegionDoubleClick(region, audioTrack) },
                onBounce: { region in onMIDIRegionBounce(region, audioTrack) },
                onDelete: { region in onMIDIRegionDelete(region, audioTrack) }
            )
            
            // Automation curve overlay (on top of regions)
            if audioTrack.automationExpanded {
                ForEach(audioTrack.automationLanes.filter { $0.isVisible }) { lane in
                    AutomationCurveOverlay(
                        lane: lane,
                        pixelsPerBeat: pixelsPerBeat,
                        trackHeight: height,
                        durationBeats: projectManager.currentProject?.durationBeats ?? 60,
                        currentTrackValue: liveTrackValue(for: lane.parameter, trackId: audioTrack.id),
                        onAddPoint: { beat, value in
                            addAutomationPoint(toLane: lane.id, trackId: audioTrack.id, beat: beat, value: value)
                        },
                        onUpdatePoint: { pointId, newBeat, newValue in
                            updateAutomationPoint(pointId: pointId, laneId: lane.id, trackId: audioTrack.id, beat: newBeat, value: newValue)
                        },
                        onDeletePoint: { pointId in
                            deleteAutomationPoint(pointId: pointId, laneId: lane.id, trackId: audioTrack.id)
                        }
                    )
                    .frame(maxWidth: .infinity) // Extend full width
                    .zIndex(200) // Above regions and generations
                }
            }
        }
        .frame(height: height)
        .contentShape(Rectangle())
        .onTapGesture {
            // Clear region selection when clicking empty track area
            // Note: Do NOT call onSelect() here - tracks should only be selected via header clicks
            selection.clear()
            
            // CRITICAL: Also clear MIDI region selection
            selection.clearMIDISelection()
        }
    }
    
    /// Add an automation point to a lane
    private func addAutomationPoint(toLane laneId: UUID, trackId: UUID, beat: Double, value: Float) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let laneIndex = project.tracks[trackIndex].automationLanes.firstIndex(where: { $0.id == laneId }) else {
            return
        }
        
        // Add the new point
        let newPoint = AutomationPoint(beat: beat, value: value)
        project.tracks[trackIndex].automationLanes[laneIndex].points.append(newPoint)
        
        // Sort points by beat
        project.tracks[trackIndex].automationLanes[laneIndex].points.sort { $0.beat < $1.beat }
        
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Update audio engine automation
        audioEngine.updateTrackAutomation(project.tracks[trackIndex])
    }
    
    /// Update an existing automation point's position and value
    private func updateAutomationPoint(pointId: UUID, laneId: UUID, trackId: UUID, beat: Double, value: Float) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let laneIndex = project.tracks[trackIndex].automationLanes.firstIndex(where: { $0.id == laneId }),
              let pointIndex = project.tracks[trackIndex].automationLanes[laneIndex].points.firstIndex(where: { $0.id == pointId }) else {
            return
        }
        
        // Update the point
        project.tracks[trackIndex].automationLanes[laneIndex].points[pointIndex].beat = beat
        project.tracks[trackIndex].automationLanes[laneIndex].points[pointIndex].value = value
        
        // Re-sort points by beat
        project.tracks[trackIndex].automationLanes[laneIndex].points.sort { $0.beat < $1.beat }
        
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Update audio engine automation
        audioEngine.updateTrackAutomation(project.tracks[trackIndex])
    }
    
    /// Delete an automation point
    private func deleteAutomationPoint(pointId: UUID, laneId: UUID, trackId: UUID) {
        guard var project = projectManager.currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }),
              let laneIndex = project.tracks[trackIndex].automationLanes.firstIndex(where: { $0.id == laneId }),
              let pointIndex = project.tracks[trackIndex].automationLanes[laneIndex].points.firstIndex(where: { $0.id == pointId }) else {
            return
        }
        
        // Remove the point
        project.tracks[trackIndex].automationLanes[laneIndex].points.remove(at: pointIndex)
        
        project.modifiedAt = Date()
        projectManager.currentProject = project
        projectManager.hasUnsavedChanges = true  // Mark as unsaved, don't auto-save
        
        // Update audio engine automation
        audioEngine.updateTrackAutomation(project.tracks[trackIndex])
    }
    
    /// Get the current value for a parameter from the track's mixer settings
    private func currentValueForLane(_ lane: AutomationLane, track: AudioTrack) -> Float {
        switch lane.parameter {
        case .volume:
            return track.mixerSettings.volume
        case .pan:
            // Convert pan from -1...1 to 0...1
            return (track.mixerSettings.pan + 1) / 2
        default:
            return lane.parameter.defaultValue
        }
    }
    
    /// Get the LIVE track value from ProjectManager (single source of truth)
    private func liveTrackValue(for parameter: AutomationParameter, trackId: UUID) -> Float {
        // Read from ProjectManager for reactive SwiftUI updates
        guard let project = projectManager.currentProject,
              let track = project.tracks.first(where: { $0.id == trackId }) else {
            return parameter.defaultValue
        }
        
        switch parameter {
        case .volume:
            return track.mixerSettings.volume
        case .pan:
            // Convert pan from -1...1 to 0...1
            return (track.mixerSettings.pan + 1) / 2
        default:
            return parameter.defaultValue
        }
    }
}
