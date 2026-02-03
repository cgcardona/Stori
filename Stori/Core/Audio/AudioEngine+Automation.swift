//
//  AudioEngine+Automation.swift
//  Stori
//
//  Extension containing automation processing and application logic.
//  Separated from main AudioEngine.swift for better maintainability.
//
//  ARCHITECTURE:
//  - Automation engine configuration
//  - Automation value application during playback
//  - Track automation updates
//  - Recorded automation commit
//

import Foundation
import AVFoundation

// MARK: - Automation Extension

extension AudioEngine {
    
    // MARK: - Automation Engine Configuration
    
    /// Configure the high-priority automation engine
    func configureAutomationEngineInternal() {
        automationEngine.processor = automationProcessor
        
        // Thread-safe beat position provider (uses atomic accessor)
        automationEngine.beatPositionProvider = { [weak self] in
            self?.transportController?.atomicBeatPosition ?? 0
        }
        
        // Unified scheduling context provider (preferred for multi-value access)
        automationEngine.schedulingContextProvider = { [weak self] in
            self?.schedulingContext ?? .default
        }
        
        // Track IDs provider
        automationEngine.trackIdsProvider = { [weak self] in
            guard let self = self else { return [] }
            return Array(self.trackNodes.keys)
        }
        
        // Thread-safe automation value applier
        automationEngine.applyValuesHandler = { [weak self] trackId, volume, pan, eqLow, eqMid, eqHigh in
            guard let trackNode = self?.trackNodes[trackId] else { return }
            
            // Apply automation values (TrackAudioNode methods are thread-safe)
            trackNode.applyAutomationValues(
                volume: volume,
                pan: pan,
                eqLow: eqLow,
                eqMid: eqMid,
                eqHigh: eqHigh
            )
        }
    }
    
    // MARK: - Automation Application
    
    /// Apply automation values to track parameters at the current playback position
    func applyAutomationInternal(at timeInSeconds: TimeInterval) {
        guard let project = currentProject else { return }
        
        // Convert seconds to beats for automation lookup (automation is stored in beats)
        let beatsPerSecond = project.tempo / 60.0
        let timeInBeats = timeInSeconds * beatsPerSecond
        
        for track in project.tracks {
            guard let node = trackNodes[track.id] else { continue }
            
            // Skip if automation is off for this track
            guard track.automationMode.canRead else { continue }
            
            // Get all automation values for this track at current beat position
            if let values = automationProcessor.getAllValues(for: track.id, atBeat: timeInBeats) {
                // Apply volume automation with smoothing to prevent zippering
                // Fall back to mixer settings if nil (before first breakpoint)
                let volume = values.volume ?? track.mixerSettings.volume
                node.setVolumeSmoothed(volume)
                
                // Apply pan automation with smoothing
                // Pan: mixer stores 0-1, automation stores 0-1, convert to -1..+1 for node
                let pan = values.pan ?? track.mixerSettings.pan
                node.setPanSmoothed(pan * 2 - 1)
                
                // Apply EQ automation (convert 0-1 to -12..+12 dB)
                // EQ parameters can change without smoothing (band gains are less sensitive to zippering)
                let eqLow = ((values.eqLow ?? 0.5) - 0.5) * 24
                let eqMid = ((values.eqMid ?? 0.5) - 0.5) * 24
                let eqHigh = ((values.eqHigh ?? 0.5) - 0.5) * 24
                
                node.setEQ(
                    highGain: eqHigh,
                    midGain: eqMid,
                    lowGain: eqLow
                )
            } else {
                // No automation data at all for this track - apply mixer settings (no smoothing needed)
                node.setVolume(track.mixerSettings.volume)
                node.setPan(track.mixerSettings.pan * 2 - 1)
                node.setEQ(highGain: 0, midGain: 0, lowGain: 0)
            }
        }
    }
    
    // MARK: - Track Automation Updates
    
    /// Update automation processor with track's automation data
    func updateTrackAutomationInternal(_ track: AudioTrack) {
        automationProcessor.updateAutomation(
            for: track.id,
            lanes: track.automationLanes,
            mode: track.automationMode
        )
    }
    
    /// Commit recorded automation points to a track
    /// Called by AutomationRecorder when recording stops
    /// - Parameters:
    ///   - points: The recorded automation points
    ///   - parameter: The parameter that was automated
    ///   - trackId: The track to add automation to
    ///   - projectUpdateHandler: Callback to update the project state
    func commitRecordedAutomationInternal(
        points: [AutomationPoint],
        parameter: AutomationParameter,
        trackId: UUID,
        projectUpdateHandler: @escaping (inout AudioProject) -> Void
    ) {
        guard var project = currentProject,
              let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            return
        }
        
        var track = project.tracks[trackIndex]
        
        // Find or create the automation lane for this parameter
        if let laneIndex = track.automationLanes.firstIndex(where: { $0.parameter == parameter }) {
            // Merge points into existing lane
            let startBeat = points.first?.beat ?? 0
            let endBeat = points.last?.beat ?? 0
            
            AutomationRecorder.mergePoints(
                recorded: points,
                into: &track.automationLanes[laneIndex].points,
                startTime: startBeat,
                endTime: endBeat,
                mode: track.automationMode
            )
        } else {
            // Create new lane with the recorded points
            var newLane = AutomationLane(
                parameter: parameter,
                color: parameter.color
            )
            newLane.points = points
            track.automationLanes.append(newLane)
        }
        
        project.tracks[trackIndex] = track
        currentProject = project
        
        // Update the automation processor with new data
        updateTrackAutomationInternal(track)
        
        // Call the project update handler to persist changes
        projectUpdateHandler(&project)
    }
    
    /// Update automation for all tracks in current project
    func updateAllTrackAutomationInternal() {
        guard let project = currentProject else { return }
        for track in project.tracks {
            updateTrackAutomationInternal(track)
        }
    }
}
