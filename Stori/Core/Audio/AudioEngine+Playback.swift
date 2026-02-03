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
import AVFoundation

// MARK: - Playback Extension

extension AudioEngine {
    
    // MARK: - Playback Implementation
    
    func startPlaybackInternal() {
        guard let project = currentProject else {
            logDebug("⚠️ startPlayback: No current project", category: "PLAYBACK")
            return
        }

        let startBeat = currentPosition.beats
        let tempo = project.tempo
        
        logDebug("startPlayback: \(project.tracks.count) tracks, startBeat: \(startBeat), tempo: \(tempo)", category: "PLAYBACK")
        
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
    
    func playTrackInternal(_ track: AudioTrack, from startTime: TimeInterval) {
        // Get the track's dedicated player node
        guard let trackNode = trackNodes[track.id] else {
            return
        }
        
        // Schedule ALL regions - let TrackAudioNode handle timing internally
        // Don't filter by "active" status based on current position
        let allRegions = track.regions
        
        // Schedule audio for each region on this track's player node
        for region in allRegions {
            scheduleRegionInternal(region, on: trackNode, at: startTime)
        }
    }
    
    func scheduleRegionInternal(_ region: AudioRegion, on trackNode: TrackAudioNode, at currentTime: TimeInterval) {
        let playerNode = trackNode.playerNode
        let tempo = currentProject?.tempo ?? 120.0
        
        // SECURITY (H-1): Validate header before passing to AVAudioFile
        guard AudioFileHeaderValidator.validateHeader(at: region.audioFile.url) else { return }
        
        do {
            let audioFile = try AVAudioFile(forReading: region.audioFile.url)
            let regionStartSeconds = region.startTimeSeconds(tempo: tempo)
            let regionEndSeconds = regionStartSeconds + region.durationSeconds(tempo: tempo)
            let offsetInFile = currentTime - regionStartSeconds + region.offset
            let remainingDuration = regionEndSeconds - currentTime
            let framesToPlay = AVAudioFrameCount(remainingDuration * audioFile.processingFormat.sampleRate)
            
            if offsetInFile >= 0 && offsetInFile < region.audioFile.duration {
                let startFrame = AVAudioFramePosition(offsetInFile * audioFile.processingFormat.sampleRate)
                let maxFramesAvailable = audioFile.length - startFrame
                let clampedFrames = AVAudioFrameCount(min(Double(max(0, maxFramesAvailable)), Double(framesToPlay)))
                guard clampedFrames > 0, startFrame < audioFile.length else { return }
                
                // Stop any existing playback on this node first
                if playerNode.isPlaying {
                    playerNode.stop()
                }
                
                // Sample-accurate timing: schedule at (regionStart - currentTime) so no drift over loops
                let playerSampleRate = playerNode.outputFormat(forBus: 0).sampleRate
                let delaySeconds = max(0.0, regionStartSeconds - currentTime)
                let delaySamples = AVAudioFramePosition(delaySeconds * playerSampleRate)
                let when = AVAudioTime(sampleTime: delaySamples, atRate: playerSampleRate)
                playerNode.scheduleSegment(
                    audioFile,
                    startingFrame: startFrame,
                    frameCount: clampedFrames,
                    at: when
                )
                
                // Start playback on this specific track's player node
                playbackScheduler.safePlay(playerNode)
            }
        } catch {
            // File read error - silently skip
        }
    }
    
    func scheduleRegionForSynchronizedPlaybackInternal(_ region: AudioRegion, on trackNode: TrackAudioNode, at currentTime: TimeInterval) -> Bool {
        let playerNode = trackNode.playerNode
        let tempo = currentProject?.tempo ?? 120.0
        
        // SECURITY (H-1): Validate header before passing to AVAudioFile
        guard AudioFileHeaderValidator.validateHeader(at: region.audioFile.url) else { return false }
        
        do {
            let audioFile = try AVAudioFile(forReading: region.audioFile.url)
            let regionStartSeconds = region.startTimeSeconds(tempo: tempo)
            let regionEndSeconds = regionStartSeconds + region.durationSeconds(tempo: tempo)
            let offsetInFile = currentTime - regionStartSeconds + region.offset
            let remainingDuration = regionEndSeconds - currentTime
            let framesToPlay = AVAudioFrameCount(remainingDuration * audioFile.processingFormat.sampleRate)
            
            if offsetInFile >= 0 && offsetInFile < region.audioFile.duration {
                let startFrame = AVAudioFramePosition(offsetInFile * audioFile.processingFormat.sampleRate)
                let maxFramesAvailable = audioFile.length - startFrame
                let clampedFrames = AVAudioFrameCount(min(Double(max(0, maxFramesAvailable)), Double(framesToPlay)))
                guard clampedFrames > 0, startFrame < audioFile.length else { return false }
                
                // Stop any existing playback on this node first
                if playerNode.isPlaying {
                    playerNode.stop()
                }
                
                // Sample-accurate timing: schedule at (regionStart - currentTime)
                let playerSampleRate = playerNode.outputFormat(forBus: 0).sampleRate
                let delaySeconds = max(0.0, regionStartSeconds - currentTime)
                let delaySamples = AVAudioFramePosition(delaySeconds * playerSampleRate)
                let when = AVAudioTime(sampleTime: delaySamples, atRate: playerSampleRate)
                playerNode.scheduleSegment(
                    audioFile,
                    startingFrame: startFrame,
                    frameCount: clampedFrames,
                    at: when
                )
                
                return true
            }
        } catch {
            // File read error - silently skip
        }
        
        return false
    }
    
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
