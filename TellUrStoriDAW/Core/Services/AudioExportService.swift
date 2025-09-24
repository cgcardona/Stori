import Foundation
import AVFoundation
import AppKit

/// Service for exporting audio regions with and without processing effects
@MainActor
class AudioExportService: ObservableObject {
    
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
        
        print("🎧 EXPORT: Exporting original audio to \(outputURL.lastPathComponent)")
        
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
        
        print("🎧 EXPORT: Original exported successfully (\(inputFile.length) frames)")
        return outputURL
    }
    
    /// Export processed audio region (with tempo/pitch adjustments)
    func exportProcessed(_ audioFile: AudioFile, 
                        regionId: UUID,
                        tempoRate: Float = 1.0,
                        pitchShiftCents: Float = 0.0) async throws -> URL {
        
        // 🧪 EXPERIMENT: Apply extreme processing for testing
        let extremeTempoRate: Float = 0.5  // Half speed (very slow)
        let extremePitchCents: Float = -1200.0  // Down one full octave
        
        let filename = "processed_\(regionId.uuidString.prefix(8))_EXTREME_tempo\(String(format: "%.2f", extremeTempoRate))_pitch\(Int(extremePitchCents))c.wav"
        let outputURL = exportDirectory.appendingPathComponent(filename)
        
        print("🧪 EXPERIMENT: Exporting with EXTREME processing for testing!")
        print("🎧 EXPORT: Original params - tempo: \(tempoRate), pitch: \(pitchShiftCents)¢")
        print("🎧 EXPORT: EXTREME params - tempo: \(extremeTempoRate), pitch: \(extremePitchCents)¢")
        print("🎧 EXPORT: Exporting to \(outputURL.lastPathComponent)")
        
        // Load input file
        let inputFile = try AVAudioFile(forReading: audioFile.url)
        let inputFormat = inputFile.processingFormat
        
        // Create audio engine for offline processing
        let engine = AVAudioEngine()
        let playerNode = AVAudioPlayerNode()
        let timePitchUnit = AVAudioUnitTimePitch()
        
        // Configure time/pitch unit with EXTREME settings
        timePitchUnit.rate = extremeTempoRate
        timePitchUnit.pitch = extremePitchCents / 100.0  // Convert cents to semitones
        
        print("🎧 PROCESSING: TimePitch unit configured - rate: \(timePitchUnit.rate), pitch: \(timePitchUnit.pitch) semitones")
        
        // Build audio graph
        engine.attach(playerNode)
        engine.attach(timePitchUnit)
        
        engine.connect(playerNode, to: timePitchUnit, format: inputFormat)
        engine.connect(timePitchUnit, to: engine.mainMixerNode, format: inputFormat)
        
        // Calculate output length (tempo affects duration)
        let outputFrameCount = AVAudioFrameCount(Double(inputFile.length) / Double(extremeTempoRate))
        
        // Create output file
        let outputFile = try AVAudioFile(forWriting: outputURL, 
                                       settings: inputFormat.settings)
        
        // Start engine
        try engine.start()
        
        // Schedule the entire file for playback
        await playerNode.scheduleFile(inputFile, at: nil)
        playerNode.play()
        
        print("🎧 PROCESSING: Engine started, processing \(inputFile.length) → \(outputFrameCount) frames")
        
        // Process using manual tap on the mixer output
        let bufferSize: AVAudioFrameCount = 4096
        var totalFramesProcessed: AVAudioFrameCount = 0
        
        // Install tap on mixer output to capture processed audio
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { buffer, _ in
            do {
                try outputFile.write(from: buffer)
                totalFramesProcessed += buffer.frameLength
                
                if totalFramesProcessed % (bufferSize * 10) == 0 {
                    print("🎧 PROGRESS: Processed \(totalFramesProcessed) frames...")
                }
            } catch {
                print("🎧 ERROR: Failed to write buffer - \(error)")
            }
        }
        
        // Wait for processing to complete
        let expectedDuration = Double(inputFile.length) / Double(inputFile.processingFormat.sampleRate) / Double(extremeTempoRate)
        let waitTime = expectedDuration + 2.0  // Add 2 seconds buffer
        
        print("🎧 PROCESSING: Waiting \(String(format: "%.1f", waitTime))s for processing to complete...")
        
        try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        
        // Clean up
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
        
        print("🎧 EXPORT: EXTREME processed exported successfully (\(totalFramesProcessed) frames)")
        print("🎧 RESULT: Should sound MUCH slower and one octave lower!")
        return outputURL
    }
    
    /// Export both original and processed versions
    func exportComparison(_ audioFile: AudioFile,
                         regionId: UUID,
                         tempoRate: Float = 1.0,
                         pitchShiftCents: Float = 0.0) async throws -> (original: URL, processed: URL) {
        
        print("🎧 EXPORT: Starting comparison export for region \(regionId)")
        
        async let originalURL = exportOriginal(audioFile, regionId: regionId)
        async let processedURL = exportProcessed(audioFile, 
                                               regionId: regionId,
                                               tempoRate: tempoRate,
                                               pitchShiftCents: pitchShiftCents)
        
        let results = try await (original: originalURL, processed: processedURL)
        
        print("🎧 EXPORT: Comparison export complete!")
        print("🎧   Original: \(results.original.lastPathComponent)")
        print("🎧   Processed: \(results.processed.lastPathComponent)")
        
        return results
    }
    
    /// Open export directory in Finder
    func revealExportDirectory() {
        NSWorkspace.shared.open(exportDirectory)
        print("🎧 EXPORT: Opened export directory in Finder")
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
                    print("🎧 CLEANUP: Removed old export \(fileURL.lastPathComponent)")
                }
            }
        } catch {
            print("🎧 CLEANUP ERROR: \(error)")
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
