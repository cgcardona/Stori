//
//  MIDIBounceEngine.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  Renders MIDI regions to audio files (Bounce to Audio).
//  Plays MIDI through the track's synth and captures the output.
//

import Foundation
import AVFoundation
import Observation

// MARK: - Bounce State

enum BounceState {
    case idle
    case preparing
    case bouncing(progress: Double)
    case complete
    case failed(Error)
}

// MARK: - Bounce Error

enum BounceError: LocalizedError {
    case noInstrument
    case noNotes
    case renderFailed
    case writeFailed(String)
    case invalidDuration
    
    var errorDescription: String? {
        switch self {
        case .noInstrument:
            return "No instrument found for this track"
        case .noNotes:
            return "MIDI region contains no notes"
        case .renderFailed:
            return "Failed to render audio"
        case .writeFailed(let reason):
            return "Failed to write audio file: \(reason)"
        case .invalidDuration:
            return "Invalid region duration"
        }
    }
}

// MARK: - MIDI Bounce Engine

/// Renders MIDI regions to audio files using offline rendering.
@Observable
@MainActor
class MIDIBounceEngine {
    
    // MARK: - Properties
    
    var state: BounceState = .idle
    var progress: Double = 0
    
    @ObservationIgnored
    private let channels: AVAudioChannelCount = 2
    
    // MARK: - Bounce Method
    
    /// Bounce a MIDI region to an audio file
    /// - Parameters:
    ///   - region: The MIDI region to bounce
    ///   - instrument: The instrument to render through
    ///   - sampleRate: Sample rate for the output file (should match project sample rate)
    ///   - tailDuration: Extra time after last note for release/reverb tails
    /// - Returns: URL to the rendered audio file
    func bounce(
        region: MIDIRegion,
        instrument: TrackInstrument,
        sampleRate: Double = 48000,
        tailDuration: TimeInterval = 2.0
    ) async throws -> URL {
        
        guard !region.notes.isEmpty else {
            throw BounceError.noNotes
        }
        
        guard region.durationBeats > 0 else {
            throw BounceError.invalidDuration
        }
        
        state = .preparing
        
        // Calculate total duration including tail
        let totalDuration = region.durationBeats + tailDuration
        let totalSamples = Int(totalDuration * sampleRate)
        
        // Create output buffer
        guard let format = AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: channels
        ) else {
            throw BounceError.renderFailed
        }
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(totalSamples)
        ) else {
            throw BounceError.renderFailed
        }
        outputBuffer.frameLength = AVAudioFrameCount(totalSamples)
        
        state = .bouncing(progress: 0)
        
        // Sort notes by start time
        let sortedNotes = region.notes.sorted { $0.startBeat < $1.startBeat }
        
        // Get synth engine
        guard let synth = instrument.synthEngine else {
            throw BounceError.noInstrument
        }
        
        // Render in chunks for progress updates
        let chunkSize = 4096
        let numChunks = (totalSamples + chunkSize - 1) / chunkSize
        
        // Track active notes
        var activeNotes: [UInt8: (endSample: Int, velocity: UInt8)] = [:]
        var noteIndex = 0
        
        // Synth rendering time tracker
        var synthTime: Float = 0
        
        // Get buffer pointers
        guard let leftChannel = outputBuffer.floatChannelData?[0],
              let rightChannel = outputBuffer.floatChannelData?[1] else {
            throw BounceError.renderFailed
        }
        
        // Process in chunks
        for chunkIdx in 0..<numChunks {
            let startSample = chunkIdx * chunkSize
            let endSample = min(startSample + chunkSize, totalSamples)
            let currentTime = Double(startSample) / sampleRate
            let endTime = Double(endSample) / sampleRate
            
            // Trigger notes that start in this chunk
            while noteIndex < sortedNotes.count {
                let note = sortedNotes[noteIndex]
                if note.startBeat >= currentTime && note.startBeat < endTime {
                    // Note starts in this chunk
                    synth.noteOn(pitch: note.pitch, velocity: note.velocity)
                    let noteSampleEnd = Int((note.startBeat + note.durationBeats) * sampleRate)
                    activeNotes[note.pitch] = (endSample: noteSampleEnd, velocity: note.velocity)
                    noteIndex += 1
                } else if note.startBeat >= endTime {
                    break
                } else {
                    noteIndex += 1
                }
            }
            
            // Check for notes that end in this chunk
            for (pitch, noteInfo) in activeNotes {
                if noteInfo.endSample <= endSample {
                    synth.noteOff(pitch: pitch)
                    activeNotes.removeValue(forKey: pitch)
                }
            }
            
            // Render this chunk through the synth
            let chunkLength = endSample - startSample
            let tempBuffer = UnsafeMutablePointer<Float>.allocate(capacity: chunkLength * 2)
            defer { tempBuffer.deallocate() }

            // Get samples from synth
            synth.renderOffline(
                into: tempBuffer,
                frameCount: chunkLength,
                sampleRate: Float(sampleRate),
                currentTime: &synthTime
            )

            // Copy to output buffer (interleaved to non-interleaved)
            for i in 0..<chunkLength {
                leftChannel[startSample + i] = tempBuffer[i * 2]
                rightChannel[startSample + i] = tempBuffer[i * 2 + 1]
            }
            
            // Update progress
            let progressValue = Double(chunkIdx + 1) / Double(numChunks)
            await MainActor.run {
                self.progress = progressValue
                self.state = .bouncing(progress: progressValue)
            }
            
            // Small delay to keep UI responsive
            try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
        }
        
        // Release any remaining notes
        for pitch in activeNotes.keys {
            synth.noteOff(pitch: pitch)
        }
        
        // Normalize audio
        normalizeBuffer(outputBuffer)
        
        // Write to file
        let outputURL = try await writeAudioFile(buffer: outputBuffer, region: region)
        
        state = .complete
        return outputURL
    }
    
    // MARK: - Helpers
    
    /// Normalize the audio buffer to prevent clipping
    private func normalizeBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let left = buffer.floatChannelData?[0],
              let right = buffer.floatChannelData?[1] else { return }
        
        let count = Int(buffer.frameLength)
        var maxSample: Float = 0
        
        // Find max sample
        for i in 0..<count {
            maxSample = max(maxSample, abs(left[i]), abs(right[i]))
        }
        
        // Normalize if needed (leave some headroom)
        if maxSample > 0.9 {
            let scale = 0.85 / maxSample
            for i in 0..<count {
                left[i] *= scale
                right[i] *= scale
            }
        }
    }
    
    /// Write the rendered audio to a file
    private func writeAudioFile(buffer: AVAudioPCMBuffer, region: MIDIRegion) async throws -> URL {
        // Create output directory
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let bouncesDir = documentsURL.appendingPathComponent("Stori/Bounces", isDirectory: true)
        
        try FileManager.default.createDirectory(at: bouncesDir, withIntermediateDirectories: true)
        
        // Create unique filename
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = dateFormatter.string(from: Date())
        let safeName = region.name.replacingOccurrences(of: " ", with: "_")
        let filename = "\(safeName)_\(timestamp).wav"
        let outputURL = bouncesDir.appendingPathComponent(filename)
        
        // Write file
        guard let format = buffer.format as AVAudioFormat? else {
            throw BounceError.writeFailed("Invalid format")
        }
        
        do {
            let file = try AVAudioFile(
                forWriting: outputURL,
                settings: format.settings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )
            try file.write(from: buffer)
        } catch {
            throw BounceError.writeFailed(error.localizedDescription)
        }
        
        return outputURL
    }
    
    // MARK: - Cleanup
    
    deinit {
        // CRITICAL: Protective deinit for @Observable @MainActor class (ASan Issue #84742+)
        // Prevents double-free from implicit Swift Concurrency property change notification tasks
    }
}

// MARK: - SynthEngine Offline Rendering Extension

extension SynthEngine {
    
    /// Render audio offline for bounce
    /// Note: This uses the existing voice rendering system
    func renderOffline(into buffer: UnsafeMutablePointer<Float>, frameCount: Int, sampleRate: Float, currentTime: inout Float) {
        // Allocate temporary mono buffer for voice rendering
        let tempBuffer = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        defer { tempBuffer.deallocate() }
        
        // Clear temp buffer
        memset(tempBuffer, 0, frameCount * MemoryLayout<Float>.size)
        
        // Get active voices and render each
        let currentVoices = activeVoices
        for voice in currentVoices where voice.isActive {
            voice.render(into: tempBuffer, frameCount: frameCount, startTime: currentTime)
        }
        
        // Copy mono to stereo interleaved with master volume
        let volume = preset.masterVolume
        for i in 0..<frameCount {
            let sample = tempBuffer[i] * volume
            buffer[i * 2] = sample        // Left
            buffer[i * 2 + 1] = sample    // Right
        }
        
        // Advance time
        currentTime += Float(frameCount) / sampleRate
    }
}

