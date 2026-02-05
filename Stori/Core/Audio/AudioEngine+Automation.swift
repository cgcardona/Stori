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
        
        // REAL-TIME SAFETY: Initialize cached track IDs instead of allocating at 120Hz
        // The cache is updated when tracks change (see updateAutomationTrackCache)
        updateAutomationTrackCache()
        
        // Thread-safe automation value applier (merge with mixer for nil params = deterministic, no pops on first point)
        automationEngine.applyValuesHandler = { [weak self] trackId, values in
            guard let self = self, let trackNode = self.trackNodes[trackId] else { return }
            guard let track = self.currentProject?.tracks.first(where: { $0.id == trackId }) else { return }
            
            let volume = values.volume ?? track.mixerSettings.volume
            let pan = values.pan ?? track.mixerSettings.pan
            let eqLow = values.eqLow ?? 0.5
            let eqMid = values.eqMid ?? 0.5
            let eqHigh = values.eqHigh ?? 0.5
            
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
            
            // Get all automation values for this track at current beat position (deterministic: uses initialValue/lane before first point)
            if let values = automationProcessor.getAllValues(for: track.id, atBeat: timeInBeats) {
                // Merge with mixer for nil params (empty lanes = use mixer)
                let volume = values.volume ?? track.mixerSettings.volume
                node.setVolumeSmoothed(volume)
                
                let pan = values.pan ?? track.mixerSettings.pan
                node.setPanSmoothed(pan * 2 - 1)
                
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
                startBeat: startBeat,
                endBeat: endBeat,
                mode: track.automationMode
            )
        } else {
            // Create new lane with the recorded points; set initialValue from mixer for deterministic playback before first point
            let mixerValue = Self.mixerValueForAutomationParameter(parameter, track: track)
            var newLane = AutomationLane(
                parameter: parameter,
                points: points,
                initialValue: mixerValue,
                color: parameter.color
            )
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
    
    /// Returns mixer value (0–1) for an automation parameter; used for lane initialValue (deterministic WYSIWYG).
    private static func mixerValueForAutomationParameter(_ parameter: AutomationParameter, track: AudioTrack) -> Float {
        let m = track.mixerSettings
        switch parameter {
        case .volume: return m.volume
        case .pan: return m.pan
        case .eqLow: return max(0, min(1, (m.lowEQ / 24) + 0.5))
        case .eqMid: return max(0, min(1, (m.midEQ / 24) + 0.5))
        case .eqHigh: return max(0, min(1, (m.highEQ / 24) + 0.5))
        default: return parameter.defaultValue
        }
    }
    
    /// Update the cached track IDs in the automation engine
    /// REAL-TIME SAFETY: Call this whenever tracks are added/removed
    /// This prevents array allocation at 120Hz in the automation timer
    func updateAutomationTrackCache() {
        automationEngine.updateTrackIds(Array(trackNodes.keys))
    }
}
