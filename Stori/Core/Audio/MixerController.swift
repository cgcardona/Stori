//
//  MixerController.swift
//  Stori
//
//  Manages track and master mixer controls: volume, pan, mute, solo, and EQ.
//  Extracted from AudioEngine for better separation of concerns.
//

import Foundation
import AVFoundation

// MARK: - MixerInstrumentManaging Protocol

/// Minimal protocol for InstrumentManager methods used by MixerController.
/// Enables dependency injection for testing without requiring the full InstrumentManager.
@MainActor
protocol MixerInstrumentManaging {
    func setVolume(_ volume: Float, forTrack trackId: UUID)
    func setPan(_ pan: Float, forTrack trackId: UUID)
    func setMuted(_ muted: Bool, forTrack trackId: UUID)
}

/// Default implementation using InstrumentManager.shared
extension InstrumentManager: MixerInstrumentManaging {}

// MARK: - MixerController

/// Mixer controller manages track and master mixing controls.
/// It coordinates with AudioEngine for actual audio node updates and project model persistence.
@MainActor
class MixerController {
    
    // MARK: - Solo Tracking
    
    /// Set of currently soloed track IDs
    private(set) var soloTracks: Set<UUID> = []
    
    // MARK: - Debug Logging
    
    /// Uses centralized debug config (see AudioDebugConfig)
    private var debugMixer: Bool { AudioDebugConfig.logMixerState }
    
    /// Debug logging with autoclosure to prevent string allocation when disabled
    /// PERFORMANCE: When debugMixer is false, the message closure is never evaluated
    private func logDebug(_ message: @autoclosure () -> String) {
        guard debugMixer else { return }
        AppLogger.shared.debug("[MIXER] \(message())", category: .audio)
    }
    
    // MARK: - Dependencies (injected via closures for loose coupling)
    
    /// Returns current project
    private var getProject: () -> AudioProject?
    
    /// Updates the current project
    private var setProject: (AudioProject) -> Void
    
    /// Returns track nodes dictionary
    private var getTrackNodes: () -> [UUID: TrackAudioNode]
    
    /// Returns the main mixer node
    private var getMainMixer: () -> AVAudioMixerNode
    
    /// Returns the master EQ node
    private var getMasterEQ: () -> AVAudioUnitEQ
    
    /// Callback to reload MIDI regions (for mute/solo changes)
    private var onReloadMIDIRegions: () -> Void
    
    /// Callback to safely disconnect a track node
    private var onSafeDisconnectTrackNode: (TrackAudioNode) -> Void
    
    /// Instrument manager for MIDI track volume/pan/mute (injectable for testing)
    private var instrumentManager: MixerInstrumentManaging
    
    /// O(1) track lookup: cache of trackId → index. Rebuilt when project track count changes or on miss.
    private var trackIndexCache: [UUID: Int] = [:]
    
    // MARK: - Initialization
    
    init(
        getProject: @escaping () -> AudioProject?,
        setProject: @escaping (AudioProject) -> Void,
        getTrackNodes: @escaping () -> [UUID: TrackAudioNode],
        getMainMixer: @escaping () -> AVAudioMixerNode,
        getMasterEQ: @escaping () -> AVAudioUnitEQ,
        onReloadMIDIRegions: @escaping () -> Void,
        onSafeDisconnectTrackNode: @escaping (TrackAudioNode) -> Void,
        instrumentManager: MixerInstrumentManaging? = nil
    ) {
        self.getProject = getProject
        self.setProject = setProject
        self.getTrackNodes = getTrackNodes
        self.getMainMixer = getMainMixer
        self.getMasterEQ = getMasterEQ
        self.onReloadMIDIRegions = onReloadMIDIRegions
        self.onSafeDisconnectTrackNode = onSafeDisconnectTrackNode
        self.instrumentManager = instrumentManager ?? InstrumentManager.shared
    }
    
    // MARK: - Track Volume
    
    func updateTrackVolume(trackId: UUID, volume: Float) {
        let trackNodes = getTrackNodes()
        
        // Update audio track node (for audio regions)
        if let trackNode = trackNodes[trackId] {
            trackNode.setVolume(volume)
        }
        
        // Update instrument volume (for MIDI tracks)
        instrumentManager.setVolume(volume, forTrack: trackId)
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.volume = volume
        }
    }
    
    // MARK: - Track Pan
    
    func updateTrackPan(trackId: UUID, pan: Float) {
        let trackNodes = getTrackNodes()
        
        // Update audio track node (for audio regions)
        if let trackNode = trackNodes[trackId] {
            trackNode.setPan(pan)
        }
        
        // Update instrument pan (for MIDI tracks)
        instrumentManager.setPan(pan, forTrack: trackId)
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.pan = pan
        }
    }
    
    // MARK: - Track Mute
    
    func updateTrackMute(trackId: UUID, isMuted: Bool) {
        let trackNodes = getTrackNodes()
        
        // Update audio track node (for audio regions)
        if let trackNode = trackNodes[trackId] {
            trackNode.setMuted(isMuted)
        }
        
        // Update instrument mute state (for MIDI tracks - immediate effect)
        instrumentManager.setMuted(isMuted, forTrack: trackId)
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.isMuted = isMuted
        }
        
        // Reload MIDI regions to respect mute state
        onReloadMIDIRegions()
    }
    
    // MARK: - Track Solo
    
    func updateTrackSolo(trackId: UUID, isSolo: Bool) {
        let trackNodes = getTrackNodes()
        
        guard let trackNode = trackNodes[trackId] else {
            return
        }
        
        if isSolo {
            soloTracks.insert(trackId)
        } else {
            soloTracks.remove(trackId)
        }
        
        trackNode.setSolo(isSolo)
        updateSoloState()
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.isSolo = isSolo
        }
        
        // Reload MIDI regions to respect solo state
        onReloadMIDIRegions()
    }
    
    /// Updates the effective mute state for all tracks based on solo status
    ///
    /// PERFORMANCE: Uses O(n) dictionary lookup instead of O(n²) nested search.
    /// Previous implementation used `project.tracks.first(where:)` inside the loop.
    private func updateSoloState() {
        let trackNodes = getTrackNodes()
        let hasSoloTracks = !soloTracks.isEmpty
        
        // Build track lookup dictionary once (O(n)) instead of searching per-track (O(n²))
        guard let project = getProject() else { return }
        let trackMuteStates: [UUID: Bool] = Dictionary(
            uniqueKeysWithValues: project.tracks.map { ($0.id, $0.mixerSettings.isMuted) }
        )
        
        for (trackId, trackNode) in trackNodes {
            // O(1) dictionary lookup instead of O(n) array search
            guard let isExplicitlyMuted = trackMuteStates[trackId] else {
                continue
            }
            
            if hasSoloTracks {
                // If there are solo tracks:
                // - Soloed tracks are audible (unless explicitly muted)
                // - Non-soloed tracks are muted
                let isSoloed = soloTracks.contains(trackId)
                let shouldBeMuted = !isSoloed || isExplicitlyMuted
                trackNode.setMuted(shouldBeMuted)
            } else {
                // If no solo tracks, restore original mute state from project
                trackNode.setMuted(isExplicitlyMuted)
            }
        }
    }
    
    // MARK: - Track EQ
    
    func updateTrackEQ(trackId: UUID, highEQ: Float, midEQ: Float, lowEQ: Float) {
        let trackNodes = getTrackNodes()
        
        guard let trackNode = trackNodes[trackId] else { return }
        
        // Apply EQ to the audio node
        trackNode.setEQ(highGain: highEQ, midGain: midEQ, lowGain: lowEQ)
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.highEQ = highEQ
            settings.midEQ = midEQ
            settings.lowEQ = lowEQ
        }
    }
    
    func updateTrackHighEQ(trackId: UUID, value: Float) {
        let trackNodes = getTrackNodes()
        guard let trackNode = trackNodes[trackId] else { return }
        guard let project = getProject(), let idx = trackIndex(for: trackId) else { return }
        let m = project.tracks[idx].mixerSettings
        
        trackNode.setEQ(highGain: value, midGain: m.midEQ, lowGain: m.lowEQ)
        
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.highEQ = value
        }
    }
    
    func updateTrackMidEQ(trackId: UUID, value: Float) {
        let trackNodes = getTrackNodes()
        guard let trackNode = trackNodes[trackId] else { return }
        guard let project = getProject(), let idx = trackIndex(for: trackId) else { return }
        let m = project.tracks[idx].mixerSettings
        
        trackNode.setEQ(highGain: m.highEQ, midGain: value, lowGain: m.lowEQ)
        
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.midEQ = value
        }
    }
    
    func updateTrackLowEQ(trackId: UUID, value: Float) {
        let trackNodes = getTrackNodes()
        guard let trackNode = trackNodes[trackId] else { return }
        guard let project = getProject(), let idx = trackIndex(for: trackId) else { return }
        let m = project.tracks[idx].mixerSettings
        
        trackNode.setEQ(highGain: m.highEQ, midGain: m.midEQ, lowGain: value)
        
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.lowEQ = value
        }
    }
    
    func updateTrackEQEnabled(trackId: UUID, enabled: Bool) {
        let trackNodes = getTrackNodes()
        
        guard let trackNode = trackNodes[trackId] else { return }
        
        if enabled {
            // Re-apply current EQ values
            if let track = getProject()?.tracks.first(where: { $0.id == trackId }) {
                trackNode.setEQ(
                    highGain: track.mixerSettings.highEQ,
                    midGain: track.mixerSettings.midEQ,
                    lowGain: track.mixerSettings.lowEQ
                )
            }
        } else {
            // Bypass EQ by setting all bands to 0
            trackNode.setEQ(highGain: 0, midGain: 0, lowGain: 0)
        }
        
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.eqEnabled = enabled
        }
    }
    
    // MARK: - Track Record Enable
    
    func updateTrackRecordEnabled(trackId: UUID, isRecordEnabled: Bool) {
        // Update the project model
        if let project = getProject(),
           let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            var updatedProject = project
            updatedProject.tracks[trackIndex].mixerSettings.isRecordEnabled = isRecordEnabled
            setProject(updatedProject)
        }
    }
    
    // MARK: - Track Icon
    
    func updateTrackIcon(trackId: UUID, iconName: String) {
        // Validate icon exists in our approved list
        guard TrackIconCategory.allValidIcons.contains(iconName) else {
            AppLogger.shared.warning("Invalid track icon: \(iconName), using default", category: .audio)
            return
        }
        
        guard let project = getProject() else { return }
        
        var updatedProject = project
        if let trackIndex = updatedProject.tracks.firstIndex(where: { $0.id == trackId }) {
            updatedProject.tracks[trackIndex].iconName = iconName
            setProject(updatedProject)
        }
    }
    
    // MARK: - Master Volume
    
    /// Master volume value (0.0 to 1.0)
    var masterVolume: Double = 0.8
    
    func updateMasterVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        let mixer = getMainMixer()
        mixer.outputVolume = clampedVolume
        masterVolume = Double(clampedVolume)
    }
    
    func getMasterVolume() -> Float {
        return getMainMixer().outputVolume
    }
    
    // MARK: - Master EQ
    
    func updateMasterEQ(hi: Float, mid: Float, lo: Float) {
        let masterEQ = getMasterEQ()
        guard masterEQ.bands.count >= 3 else { return }
        
        // Convert 0.0-1.0 range to dB gain (-12 to +12 dB)
        let hiGain = (hi - 0.5) * 24.0  // 0.0→-12dB, 0.5→0dB, 1.0→+12dB
        let midGain = (mid - 0.5) * 24.0
        let loGain = (lo - 0.5) * 24.0
        
        masterEQ.bands[0].gain = hiGain  // High shelf
        masterEQ.bands[1].gain = midGain  // Mid parametric
        masterEQ.bands[2].gain = loGain  // Low shelf
    }
    
    func updateMasterHiEQ(_ value: Float) {
        let masterEQ = getMasterEQ()
        guard masterEQ.bands.count >= 1 else { return }
        let gain = (value - 0.5) * 24.0
        masterEQ.bands[0].gain = gain
    }
    
    func updateMasterMidEQ(_ value: Float) {
        let masterEQ = getMasterEQ()
        guard masterEQ.bands.count >= 2 else { return }
        let gain = (value - 0.5) * 24.0
        masterEQ.bands[1].gain = gain
    }
    
    func updateMasterLoEQ(_ value: Float) {
        let masterEQ = getMasterEQ()
        guard masterEQ.bands.count >= 3 else { return }
        let gain = (value - 0.5) * 24.0
        masterEQ.bands[2].gain = gain
    }
    
    // MARK: - Track Removal
    
    /// Removes a track from the mixer (updates solo state tracking)
    func removeTrackFromMixer(trackId: UUID) {
        // Remove from solo tracks if present
        soloTracks.remove(trackId)
        updateSoloState()
    }
    
    /// Clears all solo track tracking (called when clearing all tracks)
    /// NOTE: This is intended for internal use. Prefer atomicResetTracks for project loads.
    func clearSoloTracks() {
        soloTracks.removeAll()
    }
    
    // MARK: - All Track States Update
    
    /// Updates mute/solo states for all tracks based on project model
    func updateAllTrackStates() {
        guard let project = getProject() else { return }
        let trackNodes = getTrackNodes()
        
        // Update mute/solo states for all tracks
        for track in project.tracks {
            if let trackNode = trackNodes[track.id] {
                trackNode.setMuted(track.mixerSettings.isMuted)
                trackNode.setSolo(track.mixerSettings.isSolo)
            }
        }
        
        // Rebuild solo tracking
        soloTracks.removeAll()
        for track in project.tracks where track.mixerSettings.isSolo {
            soloTracks.insert(track.id)
        }
        
        updateSoloState()
    }
    
    /// Atomically resets all track states from project data.
    /// This combines clearing solo state and restoring it in a single operation,
    /// preventing any window where the mixer state is inconsistent with the project.
    ///
    /// - Parameter tracks: The track data to restore state from
    func atomicResetTrackStates(from tracks: [AudioTrack]) {
        let trackNodes = getTrackNodes()
        
        // ATOMIC OPERATION: Clear and rebuild solo tracking in one pass
        soloTracks.removeAll()
        
        for track in tracks {
            // Rebuild solo set
            if track.mixerSettings.isSolo {
                soloTracks.insert(track.id)
            }
            
            // Apply states to track nodes (if they exist yet)
            if let trackNode = trackNodes[track.id] {
                trackNode.setMuted(track.mixerSettings.isMuted)
                trackNode.setSolo(track.mixerSettings.isSolo)
            }
        }
        
        updateSoloState()
    }
    
    // MARK: - Private Helpers
    
    /// Rebuild trackId → index map from current project. Call when track count changes or on cache miss.
    private func rebuildTrackIndexCache() {
        guard let project = getProject() else { return }
        trackIndexCache = Dictionary(uniqueKeysWithValues: project.tracks.enumerated().map { ($0.element.id, $0.offset) })
    }
    
    /// Release the track index cache (e.g. on memory pressure). Next lookup will rebuild automatically.
    func invalidateTrackIndexCache() {
        trackIndexCache.removeAll()
    }
    
    /// Return track index for trackId, rebuilding cache if needed (count mismatch or miss).
    private func trackIndex(for trackId: UUID) -> Int? {
        guard let project = getProject() else { return nil }
        if trackIndexCache.count != project.tracks.count {
            rebuildTrackIndexCache()
        }
        guard let index = trackIndexCache[trackId], index < project.tracks.count, project.tracks[index].id == trackId else {
            rebuildTrackIndexCache()
            return trackIndexCache[trackId]
        }
        return index
    }
    
    private func updateProjectTrackMixerSettings(trackId: UUID, update: (inout MixerSettings) -> Void) {
        guard var project = getProject() else { return }
        guard let trackIndex = trackIndex(for: trackId) else { return }
        
        update(&project.tracks[trackIndex].mixerSettings)
        project.modifiedAt = Date()
        setProject(project)
        
        // Notify that project has been updated so SwiftUI views refresh
        NotificationCenter.default.post(name: .projectUpdated, object: project)
    }
}
