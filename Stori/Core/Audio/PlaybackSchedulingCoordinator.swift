//
//  PlaybackSchedulingCoordinator.swift
//  Stori
//
//  Coordinates playback scheduling for audio tracks and MIDI.
//  Extracted from AudioEngine.swift for better maintainability.
//

import Foundation
import AVFoundation
import Observation

/// Coordinates audio track scheduling and cycle loop handling
@MainActor
final class PlaybackSchedulingCoordinator {
    
    // MARK: - Dependencies (set by AudioEngine)
    
    @ObservationIgnored
    var engine: AVAudioEngine!
    
    @ObservationIgnored
    var getTrackNodes: (() -> [UUID: TrackAudioNode])?
    
    @ObservationIgnored
    var getCurrentProject: (() -> AudioProject?)?
    
    @ObservationIgnored
    var midiPlaybackEngine: MIDIPlaybackEngine?
    
    @ObservationIgnored
    var installedMetronome: MetronomeEngine?
    
    @ObservationIgnored
    var logDebug: ((String, String) -> Void)?
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Public API
    
    /// Handle cycle loop jump - reschedule audio and MIDI from new position
    /// Called by TransportController when playback loops back to cycle start
    func handleCycleJump(toBeat targetBeat: Double) {
        logDebug?("Cycle jump to beat \(targetBeat)", "TRANSPORT")
        
        // CRITICAL: Send note-offs for active notes before seeking MIDI scheduler
        // This prevents stuck notes when notes span the cycle boundary
        midiPlaybackEngine?.seek(toBeat: targetBeat)
        
        // Reschedule all audio tracks from the new position
        rescheduleTracksFromBeat(targetBeat)
        
        // Sync metronome to new position (already in beats)
        if let metronome = installedMetronome, metronome.isEnabled {
            metronome.onTransportSeek(to: targetBeat)
        }
    }
    
    /// Reschedules all audio tracks from a new position without stopping the engine
    /// Called by handleCycleJump when TransportController detects a cycle loop
    func rescheduleTracksFromBeat(_ targetBeat: Double) {
        // Stop and reset only the player nodes (NOT the engine!)
        if let trackNodes = getTrackNodes?() {
            for (_, trackNode) in trackNodes {
                trackNode.playerNode.stop()
                trackNode.playerNode.reset()
            }
        }
        
        // Convert beats to seconds for audio scheduling (AVAudioEngine boundary)
        let tempo = getCurrentProject?()?.tempo ?? 120.0
        let targetTimeSeconds = targetBeat * (60.0 / tempo)
        
        // Re-schedule all tracks from the new position
        guard let project = getCurrentProject?(),
              let trackNodes = getTrackNodes?() else { return }
        
        for track in project.tracks {
            guard let trackNode = trackNodes[track.id] else { continue }
            do {
                // scheduleFromPosition takes seconds for AVAudioEngine scheduling
                try trackNode.scheduleFromPosition(targetTimeSeconds, audioRegions: track.regions, tempo: tempo, skipReset: true)
                if !track.regions.isEmpty {
                    trackNode.play()
                }
            } catch {
                logDebug?("Failed to reschedule track \(track.name): \(error)", "TRANSPORT")
            }
        }
        
        // Seek MIDI playback engine to new position (in beats)
        midiPlaybackEngine?.seek(toBeat: targetBeat)
    }
    
    /// Safe play guard - ensures player has output connections before playing
    func safePlay(_ player: AVAudioPlayerNode) {
        guard player.engine != nil else { return }
        guard engine.isRunning else { return }
        guard engine.attachedNodes.contains(player) else { return }
        
        // Verify output connections exist before playing
        let outputConnections = engine.outputConnectionPoints(for: player, outputBus: 0)
        guard !outputConnections.isEmpty else { return }
        
        player.play()
    }
}
