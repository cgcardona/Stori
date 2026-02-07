//
//  AudioEngine+Playback.swift
//  Stori
//
//  Extension containing playback scheduling and implementation logic.
//  Separated from main AudioEngine.swift for better maintainability.
//
//  ARCHITECTURE:
//  - Audio region scheduling
//  - Track playback start/stop
//  - MIDI playback coordination
//  - Audio file import
//

import Foundation
@preconcurrency import AVFoundation

// MARK: - Playback Extension

extension AudioEngine {
    
    // MARK: - Playback Implementation
    
    /// Prepare all plugin chains for playback to prevent first-note latency (BUG FIX Issue #54)
    /// Must be called before startPlaybackInternal() to ensure AU render resources are allocated
    private func preparePluginsForPlayback() {
        var preparedCount = 0
        var failedCount = 0
        
        for (trackId, trackNode) in trackNodes {
            let pluginChain = trackNode.pluginChain
            
            // Only prepare chains with active plugins
            guard pluginChain.hasActivePlugins else {
                continue
            }
            
            let prepared = pluginChain.prepareForPlayback()
            if prepared {
                preparedCount += 1
            } else {
                failedCount += 1
                logDebug("⚠️ preparePluginsForPlayback: Failed to prepare plugins for track=\(trackId)", category: "PLAYBACK")
            }
        }
        
        if preparedCount > 0 || failedCount > 0 {
            logDebug("preparePluginsForPlayback: Prepared \(preparedCount) plugin chains, \(failedCount) failed", category: "PLAYBACK")
        }
    }
    
    func startPlaybackInternal() {
        guard let project = currentProject else {
            logDebug("⚠️ startPlayback: No current project", category: "PLAYBACK")
            return
        }

        let startBeat = currentPosition.beats
        let tempo = project.tempo
        
        logDebug("startPlayback: \(project.tracks.count) tracks, startBeat: \(startBeat), tempo: \(tempo)", category: "PLAYBACK")
        
        // BUG FIX (Issue #54): Prepare all plugin chains before playback to prevent first-note latency
        // This ensures Audio Unit render resources are allocated before the first audio callback,
        // preventing 10-100ms delays on the first note (especially with heavy synth plugins)
        preparePluginsForPlayback()
        
        // SEAMLESS CYCLE LOOPS: Update PlaybackSchedulingCoordinator with cycle state
        // This enables pre-scheduling of multiple cycle iterations for gap-free looping
        playbackScheduler.isCycleEnabled = isCycleEnabled
        playbackScheduler.cycleStartBeat = cycleStartBeat
        playbackScheduler.cycleEndBeat = cycleEndBeat
        
        // Schedule all tracks using the coordinator (handles cycle-aware scheduling if enabled)
        playbackScheduler.scheduleAllTracks(fromBeat: startBeat)

        // Start MIDI playback with tempo for beats→seconds conversion
        // FIX: Call directly (both are @MainActor) - Task wrapper caused async delay
        // which missed notes at beat 0 on initial playback
        // Note: MIDI engine always runs - it only plays if MIDI regions exist
        logDebug("Configuring MIDI playback engine", category: "PLAYBACK")
        midiPlaybackEngine.configure(with: InstrumentManager.shared, audioEngine: self)
        midiPlaybackEngine.loadRegions(from: project.tracks, tempo: project.tempo)
        midiPlaybackEngine.play(fromBeat: startBeat)
        logDebug("MIDI playback started", category: "PLAYBACK")
    }
    
    func stopPlaybackInternal() {
        // Stop MIDI playback - call directly (both are @MainActor)
        midiPlaybackEngine.stop()
        
        // Stop all player nodes via the scheduler (resets cycle state too)
        playbackScheduler.stopAllTracks()
    }
    
    // DEADCODE REMOVAL (Phase 3 beats-first cleanup):
    // Removed: playTrackInternal, scheduleRegionInternal, scheduleRegionForSynchronizedPlaybackInternal
    // These used seconds-based APIs and duplicated logic in TrackAudioNode.
    // All scheduling now goes through TrackAudioNode.scheduleFromBeat() which
    // handles beat→seconds conversion at the AVAudioEngine boundary.
    
    // MARK: - Audio Region Loading
    
    func loadAudioRegionInternal(_ region: AudioRegion, trackNode: TrackAudioNode) {
        let audioFile = region.audioFile
        logDebug("Loading audio region '\(region.id)' with file '\(audioFile.name)' at beat \(region.startBeat)", category: "REGION")
        
        do {
            try trackNode.loadAudioFile(audioFile)
            logDebug("Audio file loaded successfully: \(audioFile.url.lastPathComponent)", category: "REGION")
        } catch {
            logDebug("⚠️ Failed to load audio file: \(error)", category: "REGION")
        }
    }
    
    // MARK: - Audio File Import
    
    func importAudioFileInternal(from url: URL) async throws -> AudioFile {
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        guard fileSize <= Self.maxAudioImportFileSize else {
            throw NSError(domain: "AudioEngine", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Audio file too large (\(fileSize / 1_000_000) MB). Maximum is \(Self.maxAudioImportFileSize / 1_000_000) MB."
            ])
        }
        // SECURITY (H-1): Validate header before passing to AVAudioFile
        guard AudioFileHeaderValidator.validateHeader(at: url) else {
            throw NSError(domain: "AudioEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid or unsupported audio file format"])
        }

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        
        let audioFileFormat: AudioFileFormat
        switch url.pathExtension.lowercased() {
        case "wav": audioFileFormat = .wav
        case "aiff", "aif": audioFileFormat = .aiff
        case "mp3", "m4a": audioFileFormat = .m4a  // MP3 not supported, treat as M4A
        case "flac": audioFileFormat = .flac
        default: audioFileFormat = .wav
        }
        
        return AudioFile(
            name: url.deletingPathExtension().lastPathComponent,
            url: url,
            duration: Double(audioFile.length) / format.sampleRate,
            sampleRate: format.sampleRate,
            channels: Int(format.channelCount),
            bitDepth: 16, // Simplified
            fileSize: fileSize,
            format: audioFileFormat
        )
    }
    
}
