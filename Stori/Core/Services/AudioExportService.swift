import Foundation
import AVFoundation
import AppKit
import Combine
import Observation

/// Service for exporting audio regions with and without processing effects
@Observable
@MainActor
class AudioExportService {
    
    @ObservationIgnored
    private let fileManager = FileManager.default


    /// Export directory for comparison files
    private var exportDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let exportDir = documentsPath.appendingPathComponent("TellUrStori_AudioExports")
        
        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: exportDir.path) {
            try? fileManager.createDirectory(at: exportDir, withIntermediateDirectories: true)
        }
        
        return exportDir
    }
    
    /// Export original audio region (before processing)
    func exportOriginal(_ audioFile: AudioFile, regionId: UUID) async throws -> URL {
        let filename = "original_\(regionId.uuidString.prefix(8)).wav"
        let outputURL = exportDirectory.appendingPathComponent(filename)
        
        
        // Load the original audio file
        let inputFile = try AVAudioFile(forReading: audioFile.url)
        
        // Create output file with same format
        let outputFile = try AVAudioFile(forWriting: outputURL, 
                                       settings: inputFile.fileFormat.settings)
        
        // Copy audio data directly (no processing)
        let bufferSize: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, 
                                          frameCapacity: bufferSize) else {
            throw AudioExportError.bufferCreationFailed
        }
        
        while inputFile.framePosition < inputFile.length {
            try inputFile.read(into: buffer)
            try outputFile.write(from: buffer)
        }
        
        return outputURL
    }
    
    /// Export processed audio region (with tempo/pitch adjustments)
    func exportProcessed(_ audioFile: AudioFile, 
                        regionId: UUID,
                        tempoRate: Float = 1.0,
                        pitchShiftCents: Float = 0.0) async throws -> URL {
        
        let filename = "processed_\(regionId.uuidString.prefix(8))_tempo\(String(format: "%.2f", tempoRate))_pitch\(Int(pitchShiftCents))c.wav"
        let outputURL = exportDirectory.appendingPathComponent(filename)
        
        
        // Load input file
        let inputFile = try AVAudioFile(forReading: audioFile.url)
        let inputFormat = inputFile.processingFormat
        
        // Create audio engine for offline processing
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let timePitchUnit = AVAudioUnitTimePitch()
        
        // Configure time/pitch unit with region's settings
        timePitchUnit.rate = tempoRate
        timePitchUnit.pitch = pitchShiftCents / 100.0  // Convert cents to semitones
        
        
        // Build audio graph
        engine.attach(playerNode)
        engine.attach(timePitchUnit)
        
        engine.connect(playerNode, to: timePitchUnit, format: inputFormat)
        engine.connect(timePitchUnit, to: engine.mainMixerNode, format: inputFormat)
        
        
        // Calculate output length (tempo affects duration)
        let outputFrameCount = AVAudioFrameCount(Double(inputFile.length) / Double(tempoRate))
        
        // Start engine FIRST so mixer settles on its final format
        try engine.start()
        
        // NOW get the mixer's actual output format (after engine started)
        let tapFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        
        // Create output file with the tap's format
        let outputFile = try AVAudioFile(forWriting: outputURL, 
                                       settings: tapFormat.settings)
        
        // CRITICAL: Install tap BEFORE scheduling/playing!
        let bufferSize: AVAudioFrameCount = 4096
        var totalFramesProcessed: AVAudioFrameCount = 0
        
        
        // Use nil format to let tap use mixer's actual output format
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { buffer, _ in
            do {
                if totalFramesProcessed == 0 {
                    
                    // Check if buffer has audio data
                    if let channelData = buffer.floatChannelData {
                        var hasNonZero = false
                        for i in 0..<min(Int(buffer.frameLength), 100) {
                            if abs(channelData[0][i]) > 0.0001 {
                                hasNonZero = true
                                break
                            }
                        }
                    }
                }
                
                // Try to write buffer - format should match now
                try outputFile.write(from: buffer)
                totalFramesProcessed += buffer.frameLength
                
                if totalFramesProcessed % (bufferSize * 10) == 0 {
                }
            } catch {
            }
        }
        
        
        // Schedule the entire file for playback
        
        // Give engine a moment to stabilize
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        await MainActor.run {
            playerNode.scheduleFile(inputFile, at: nil)
            
            playerNode.play()
        }
        
        
        // Wait for processing to complete
        let expectedDuration = Double(inputFile.length) / Double(inputFile.processingFormat.sampleRate) / Double(tempoRate)
        let waitTime = expectedDuration + 2.0  // Add 2 seconds buffer
        
        
        try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        
        // Clean up
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
        
        
        // Check output file size
        if let fileSize = try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? UInt64 {
        }
        
        
        return outputURL
    }
    
    /// Export both original and processed versions
    func exportComparison(_ audioFile: AudioFile,
                         regionId: UUID,
                         tempoRate: Float = 1.0,
                         pitchShiftCents: Float = 0.0) async throws -> (original: URL, processed: URL) {
        
        
        async let originalURL = exportOriginal(audioFile, regionId: regionId)
        async let processedURL = exportProcessed(audioFile, 
                                               regionId: regionId,
                                               tempoRate: tempoRate,
                                               pitchShiftCents: pitchShiftCents)
        
        let results = try await (original: originalURL, processed: processedURL)
        
        
        return results
    }
    
    /// Open export directory in Finder
    func revealExportDirectory() {
        NSWorkspace.shared.open(exportDirectory)
    }
    
    /// Clean up old export files (older than 24 hours)
    func cleanupOldExports() {
        let cutoffDate = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago
        
        do {
            let files = try fileManager.contentsOfDirectory(at: exportDirectory, 
                                                          includingPropertiesForKeys: [.creationDateKey])
            
            for fileURL in files {
                if let creationDate = try fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   creationDate < cutoffDate {
                    try fileManager.removeItem(at: fileURL)
                }
            }
        } catch {
        }
    }
    
}

enum AudioExportError: Error, LocalizedError {
    case bufferCreationFailed
    case renderingFailed
    case fileWriteFailed
    
    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .renderingFailed:
            return "Audio rendering failed"
        case .fileWriteFailed:
            return "Failed to write audio file"
        }
    }
}
