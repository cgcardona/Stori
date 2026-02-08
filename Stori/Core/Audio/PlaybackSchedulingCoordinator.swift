//
//  PlaybackSchedulingCoordinator.swift
//  Stori
//
//  Coordinates playback scheduling for audio tracks and MIDI.
//  Extracted from AudioEngine.swift for better maintainability.
//
//  SEAMLESS CYCLE LOOPS:
//  When cycle mode is enabled, we pre-schedule multiple iterations ahead.
//  This means audio for the next iteration is already queued before the
//  current iteration ends, eliminating gaps during loop jumps.
//

import Foundation
@preconcurrency import AVFoundation
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
    
    // MARK: - Cycle State (set by AudioEngine before playback)
    
    /// Whether cycle mode is currently active
    var isCycleEnabled: Bool = false
    
    /// Cycle region start in beats
    var cycleStartBeat: Double = 0
    
    /// Cycle region end in beats
    var cycleEndBeat: Double = 4
    
    /// Number of cycle iterations to pre-schedule (more = smoother but more memory)
    private let cycleIterationsAhead: Int = 3
    
    /// Tracks whether we're using pre-scheduled cycle mode
    private var usingPreScheduledCycle: Bool = false
    
    // MARK: - Initialization
    
    init() {}
    
    
    // MARK: - Primary Scheduling API
    
    /// Schedule all tracks for playback from a given beat position.
    /// If cycle mode is enabled, uses pre-scheduling for seamless loops.
    /// 
    /// ARCHITECTURE: Beats-First
    /// All positions are in beats. Conversion to seconds happens at AVAudioEngine boundary.
    func scheduleAllTracks(fromBeat startBeat: Double) {
        guard let project = getCurrentProject?(),
              let trackNodes = getTrackNodes?() else { return }
        
        if isCycleEnabled && startBeat >= cycleStartBeat && startBeat < cycleEndBeat {
            // Use pre-scheduled cycle mode for seamless loops
            scheduleCycleAwareTracks(
                fromBeat: startBeat,
                project: project,
                trackNodes: trackNodes
            )
            usingPreScheduledCycle = true
        } else {
            // Standard scheduling (no cycle or outside cycle region)
            scheduleTracksStandard(
                fromBeat: startBeat,
                project: project,
                trackNodes: trackNodes
            )
            usingPreScheduledCycle = false
        }
    }
    
    /// Standard (non-cycle) scheduling
    /// Uses beats-first architecture - conversion to seconds happens in TrackAudioNode
    private func scheduleTracksStandard(
        fromBeat startBeat: Double,
        project: AudioProject,
        trackNodes: [UUID: TrackAudioNode]
    ) {
        for track in project.tracks {
            guard let trackNode = trackNodes[track.id] else { continue }
            do {
                try trackNode.scheduleFromBeat(startBeat, audioRegions: track.regions, tempo: project.tempo)
            } catch {
                logDebug?("Failed to schedule track \(track.name): \(error)", "TRANSPORT")
            }
        }
    }
    
    /// Cycle-aware scheduling that pre-schedules multiple iterations
    /// Uses beats-first architecture - conversion to seconds happens in TrackAudioNode
    private func scheduleCycleAwareTracks(
        fromBeat startBeat: Double,
        project: AudioProject,
        trackNodes: [UUID: TrackAudioNode]
    ) {
        logDebug?("Scheduling cycle-aware: \(cycleStartBeat)-\(cycleEndBeat) beats, \(cycleIterationsAhead) iterations ahead", "TRANSPORT")
        
        for track in project.tracks {
            guard let trackNode = trackNodes[track.id] else { continue }
            do {
                try trackNode.scheduleCycleAware(
                    fromBeat: startBeat,
                    audioRegions: track.regions,
                    tempo: project.tempo,
                    cycleStartBeat: cycleStartBeat,
                    cycleEndBeat: cycleEndBeat,
                    iterationsAhead: cycleIterationsAhead
                )
            } catch {
                logDebug?("Failed to schedule track \(track.name) cycle-aware: \(error)", "TRANSPORT")
            }
        }
    }
    
    // MARK: - Cycle Jump Handling
    
    /// Handle cycle loop jump
    /// Called by TransportController when playback loops back to cycle start
    func handleCycleJump(toBeat targetBeat: Double) {
        logDebug?("Cycle jump to beat \(targetBeat)", "TRANSPORT")
        
        // CRITICAL: Send note-offs for active notes before seeking MIDI scheduler
        // This prevents stuck notes when notes span the cycle boundary
        midiPlaybackEngine?.seek(toBeat: targetBeat)
        
        if usingPreScheduledCycle {
            // PRE-SCHEDULED MODE: Audio is already playing seamlessly!
            // We just need to refill more iterations as they're consumed.
            // For now, we reschedule to add more iterations.
            // A production system would use completion callbacks for true seamless refill.
            refillCycleIterations(fromBeat: targetBeat)
        } else {
            // STANDARD MODE: Must reschedule (will have small gap)
            rescheduleTracksFromBeat(targetBeat)
        }
        
        // Sync metronome to new position (already in beats)
        if let metronome = installedMetronome, metronome.isEnabled {
            metronome.onTransportSeek(to: targetBeat)
        }
    }
    
    /// Refill more cycle iterations without stopping playback
    /// This is called when we've consumed iterations and need to schedule more ahead
    private func refillCycleIterations(fromBeat targetBeat: Double) {
        guard let project = getCurrentProject?(),
              let trackNodes = getTrackNodes?() else { return }
        
        let tempo = project.tempo
        let cycleStartSeconds = cycleStartBeat * (60.0 / tempo)
        let cycleEndSeconds = cycleEndBeat * (60.0 / tempo)
        
        // Schedule more iterations ahead without stopping current playback
        // This uses the player's current timeline to add future segments
        for track in project.tracks {
            guard let trackNode = trackNodes[track.id] else { continue }
            
            // Get the player's current sample time for accurate future scheduling
            guard let lastRenderTime = trackNode.playerNode.lastRenderTime,
                  lastRenderTime.isSampleTimeValid else { continue }
            
            let playerSampleRate = trackNode.playerNode.outputFormat(forBus: 0).sampleRate
            guard playerSampleRate > 0 else { continue }
            
            let cycleDurationSeconds = cycleEndSeconds - cycleStartSeconds
            let cycleDurationSamples = AVAudioFramePosition(cycleDurationSeconds * playerSampleRate)
            
            // Schedule future iterations from the current player time
            for iterationOffset in 1...cycleIterationsAhead {
                let futureOffsetSamples = AVAudioFramePosition(iterationOffset) * cycleDurationSamples
                let futureTime = AVAudioTime(
                    sampleTime: lastRenderTime.sampleTime + futureOffsetSamples,
                    atRate: playerSampleRate
                )
                
                // Schedule each region for this future iteration
                for region in track.regions {
                    scheduleRegionAtFutureTime(
                        trackNode: trackNode,
                        region: region,
                        tempo: tempo,
                        cycleStartSeconds: cycleStartSeconds,
                        cycleEndSeconds: cycleEndSeconds,
                        futureTime: futureTime,
                        playerSampleRate: playerSampleRate
                    )
                }
            }
        }
    }
    
    /// Schedule a region at a specific future player-time
    private func scheduleRegionAtFutureTime(
        trackNode: TrackAudioNode,
        region: AudioRegion,
        tempo: Double,
        cycleStartSeconds: TimeInterval,
        cycleEndSeconds: TimeInterval,
        futureTime: AVAudioTime,
        playerSampleRate: Double
    ) {
        // Load audio file
        guard let audioFile = try? AVAudioFile(forReading: region.audioFile.url) else { return }
        
        let fileSampleRate = audioFile.processingFormat.sampleRate
        let fileDuration = Double(audioFile.length) / fileSampleRate
        guard fileDuration > 0 else { return }
        
        // Region timing
        let regionStart = region.startTimeSeconds(tempo: tempo)
        let regionEnd = regionStart + region.durationSeconds(tempo: tempo)
        
        // Clamp to cycle
        let effectiveStart = max(regionStart, cycleStartSeconds)
        let effectiveEnd = min(regionEnd, cycleEndSeconds)
        guard effectiveEnd > effectiveStart else { return }
        
        let offsetIntoRegion = effectiveStart - regionStart + region.offset
        guard offsetIntoRegion < fileDuration else { return }
        
        let startFrameInFile = AVAudioFramePosition(offsetIntoRegion * fileSampleRate)
        let durationToPlay = min(effectiveEnd - effectiveStart, fileDuration - offsetIntoRegion)
        guard durationToPlay > 0 else { return }
        
        let frameCount = AVAudioFrameCount(durationToPlay * fileSampleRate)
        guard frameCount > 0 else { return }
        
        // Calculate delay from cycle start to this region
        let delayFromCycleStart = effectiveStart - cycleStartSeconds
        let delaySamples = AVAudioFramePosition(delayFromCycleStart * playerSampleRate)
        
        // Add to the future time
        let scheduleTime = AVAudioTime(
            sampleTime: futureTime.sampleTime + delaySamples,
            atRate: playerSampleRate
        )
        
        trackNode.playerNode.scheduleSegment(
            audioFile,
            startingFrame: startFrameInFile,
            frameCount: frameCount,
            at: scheduleTime
        )
    }
    
    /// Fallback: Reschedule all tracks from beat (has gap, used when pre-scheduling fails)
    /// Reschedule all tracks from a specific beat position.
    /// Uses beats-first architecture - conversion to seconds happens in TrackAudioNode.
    func rescheduleTracksFromBeat(_ targetBeat: Double) {
        if let trackNodes = getTrackNodes?() {
            for (_, trackNode) in trackNodes {
                // Stop first to ensure isPlaying becomes false, then reset to clear buffers
                trackNode.playerNode.stop()
                trackNode.playerNode.reset()
            }
        }
        
        guard let project = getCurrentProject?(),
              let trackNodes = getTrackNodes?() else { return }
        
        for track in project.tracks {
            guard let trackNode = trackNodes[track.id] else { continue }
            do {
                // BEATS-FIRST: Use scheduleFromBeat - conversion to seconds happens at AVAudioEngine boundary
                try trackNode.scheduleFromBeat(targetBeat, audioRegions: track.regions, tempo: project.tempo, skipReset: true)
                if !track.regions.isEmpty {
                    trackNode.play()
                }
            } catch {
                logDebug?("Failed to reschedule track \(track.name): \(error)", "TRANSPORT")
            }
        }
        
        midiPlaybackEngine?.seek(toBeat: targetBeat)
    }
    
    // MARK: - Stop All
    
    /// Stop all track playback
    func stopAllTracks() {
        if let trackNodes = getTrackNodes?() {
            for (_, trackNode) in trackNodes {
                trackNode.stop()
            }
        }
        usingPreScheduledCycle = false
    }
    
    // MARK: - Utility
    
    /// Safe play guard - ensures player has output connections before playing
    func safePlay(_ player: AVAudioPlayerNode) {
        guard player.engine != nil else { return }
        guard engine.isRunning else { return }
        guard engine.attachedNodes.contains(player) else { return }
        
        let outputConnections = engine.outputConnectionPoints(for: player, outputBus: 0)
        guard !outputConnections.isEmpty else { return }
        
        player.play()
    }
    
    // MARK: - Cleanup
    
    /// Explicit deinit to prevent Swift Concurrency task leak
    /// @MainActor classes can have implicit tasks from the Swift Concurrency runtime
    /// that cause memory corruption during deallocation if not properly cleaned up
}
