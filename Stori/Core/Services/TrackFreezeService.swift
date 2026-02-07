//
//  TrackFreezeService.swift
//  Stori
//
//  Track Freeze service - renders a track with all plugins to an audio file.
//  Frozen tracks use minimal CPU by playing back pre-rendered audio instead of
//  processing plugins in real-time.
//
//  Architecture:
//  1. Freeze: Render track → audio file, store path, disable plugins
//  2. Playback: Use frozen audio file instead of original regions + plugins
//  3. Unfreeze: Restore original regions, re-enable plugins, delete frozen file
//

import Foundation
import AVFoundation

// MARK: - Track Freeze Error

enum TrackFreezeError: LocalizedError {
    case noProject
    case trackNotFound
    case noRegions
    case exportFailed(String)
    case alreadyFrozen
    case notFrozen
    
    var errorDescription: String? {
        switch self {
        case .noProject: return "No project loaded"
        case .trackNotFound: return "Track not found"
        case .noRegions: return "Track has no audio regions to freeze"
        case .exportFailed(let reason): return "Export failed: \(reason)"
        case .alreadyFrozen: return "Track is already frozen"
        case .notFrozen: return "Track is not frozen"
        }
    }
}

// MARK: - Track Freeze Service

/// Service for freezing and unfreezing tracks.
/// Freezing renders a track with all its plugins to a single audio file,
/// reducing CPU usage during playback.
@MainActor
class TrackFreezeService {
    
    // MARK: - Singleton
    
    static let shared = TrackFreezeService()
    
    // MARK: - Properties
    
    private let fileManager = FileManager.default
    
    /// Progress callback for UI updates
    var onProgress: ((Double, String) -> Void)?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Freeze Track
    
    /// Freeze a track by rendering it with all plugins to an audio file.
    /// - Parameters:
    ///   - trackId: The track to freeze
    ///   - audioEngine: The audio engine (for offline rendering)
    ///   - projectManager: The project manager
    /// - Returns: The path to the frozen audio file
    func freezeTrack(
        trackId: UUID,
        audioEngine: AudioEngine,
        projectManager: ProjectManager
    ) async throws -> URL {
        guard let project = projectManager.currentProject else {
            throw TrackFreezeError.noProject
        }
        
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            throw TrackFreezeError.trackNotFound
        }
        
        let track = project.tracks[trackIndex]
        
        guard !track.isFrozen else {
            throw TrackFreezeError.alreadyFrozen
        }
        
        // Calculate the track's content range
        let trackRange = calculateTrackRange(track: track, tempo: project.tempo)
        guard trackRange.duration > 0 else {
            throw TrackFreezeError.noRegions
        }
        
        onProgress?(0.1, "Preparing to freeze '\(track.name)'...")
        
        // Create frozen audio directory if needed
        let frozenDir = try createFrozenAudioDirectory(for: project)
        
        // Generate output file path
        let filename = "frozen_\(track.id.uuidString)_\(Date().timeIntervalSince1970).wav"
        let outputURL = frozenDir.appendingPathComponent(filename)
        
        onProgress?(0.2, "Rendering track...")
        
        // Perform offline render
        try await renderTrackOffline(
            track: track,
            trackId: trackId,
            range: trackRange,
            outputURL: outputURL,
            audioEngine: audioEngine,
            project: project
        )
        
        onProgress?(0.9, "Finalizing freeze...")
        
        // Update project with frozen state
        var updatedProject = project
        updatedProject.tracks[trackIndex].isFrozen = true
        updatedProject.tracks[trackIndex].frozenAudioPath = "Frozen/\(filename)"
        projectManager.currentProject = updatedProject
        
        onProgress?(1.0, "Track frozen successfully")
        
        
        return outputURL
    }
    
    // MARK: - Unfreeze Track
    
    /// Unfreeze a track, restoring original regions and plugins.
    /// - Parameters:
    ///   - trackId: The track to unfreeze
    ///   - projectManager: The project manager
    ///   - deleteFrozenFile: Whether to delete the frozen audio file
    func unfreezeTrack(
        trackId: UUID,
        projectManager: ProjectManager,
        deleteFrozenFile: Bool = true
    ) throws {
        guard var project = projectManager.currentProject else {
            throw TrackFreezeError.noProject
        }
        
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) else {
            throw TrackFreezeError.trackNotFound
        }
        
        guard project.tracks[trackIndex].isFrozen else {
            throw TrackFreezeError.notFrozen
        }
        
        let track = project.tracks[trackIndex]
        
        // Delete frozen audio file if requested
        if deleteFrozenFile, let frozenPath = track.frozenAudioPath {
            let projectDir = getProjectDirectory(for: project)
            let frozenURL = projectDir.appendingPathComponent(frozenPath)
            try? fileManager.removeItem(at: frozenURL)
        }
        
        // Update project state
        project.tracks[trackIndex].isFrozen = false
        project.tracks[trackIndex].frozenAudioPath = nil
        projectManager.currentProject = project
        
    }
    
    // MARK: - Private Helpers
    
    /// Calculate the time range of a track's content
    private func calculateTrackRange(track: AudioTrack, tempo: Double) -> (start: TimeInterval, duration: TimeInterval) {
        let secondsPerBeat = 60.0 / tempo
        
        // Find earliest and latest content
        var earliestBeat: Double = .greatestFiniteMagnitude
        var latestBeat: Double = 0
        
        // Check audio regions
        for region in track.regions {
            earliestBeat = min(earliestBeat, region.startBeat)
            latestBeat = max(latestBeat, region.startBeat + region.durationBeats)
        }
        
        // Check MIDI regions
        for region in track.midiRegions {
            earliestBeat = min(earliestBeat, region.startBeat)
            latestBeat = max(latestBeat, region.startBeat + region.durationBeats)
        }
        
        // Handle empty tracks
        if earliestBeat == .greatestFiniteMagnitude {
            return (start: 0, duration: 0)
        }
        
        let startTime = earliestBeat * secondsPerBeat
        let duration = (latestBeat - earliestBeat) * secondsPerBeat
        
        // Add a small tail for reverb/delay tails (2 seconds)
        let tailDuration = 2.0
        
        return (start: startTime, duration: duration + tailDuration)
    }
    
    /// Perform offline rendering of a track
    private func renderTrackOffline(
        track: AudioTrack,
        trackId: UUID,
        range: (start: TimeInterval, duration: TimeInterval),
        outputURL: URL,
        audioEngine: AudioEngine,
        project: AudioProject
    ) async throws {
        // Create an offline render engine with project sample rate
        let offlineEngine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: project.sampleRate, channels: 2)!
        
        // Calculate total samples
        let totalSamples = Int(range.duration * format.sampleRate)
        let bufferSize: AVAudioFrameCount = 4096
        
        // Create output file
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVLinearPCMBitDepthKey: 24,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        )
        
        // Clone plugins for offline rendering
        let clonedPlugins = try await audioEngine.getPluginChain(for: trackId)?.cloneActivePlugins() ?? []
        
        // Setup offline render graph
        let playerNode = AVAudioPlayerNode()
        offlineEngine.attach(playerNode)
        
        var lastNode: AVAudioNode = playerNode
        
        // Attach cloned plugins
        for plugin in clonedPlugins {
            offlineEngine.attach(plugin)
            offlineEngine.connect(lastNode, to: plugin, format: format)
            lastNode = plugin
        }
        
        // Connect to main mixer
        offlineEngine.connect(lastNode, to: offlineEngine.mainMixerNode, format: format)
        
        // Enable manual rendering
        try offlineEngine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: bufferSize)
        
        // Start engine
        try offlineEngine.start()
        playerNode.play()
        
        // Schedule audio from the track's regions
        for region in track.regions {
            let regionStartBeat = region.startBeat
            let regionStartTime = regionStartBeat * (60.0 / project.tempo)
            
            // Only include regions in the render range
            guard regionStartTime >= range.start else { continue }
            
            let audioFile = try AVAudioFile(forReading: region.audioFile.url)
            let startFrame = AVAudioFramePosition((regionStartTime - range.start) * format.sampleRate)
            playerNode.scheduleFile(audioFile, at: AVAudioTime(sampleTime: startFrame, atRate: format.sampleRate), completionHandler: nil)
        }
        
        // Render audio
        let renderBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize)!
        var samplesRendered: Int = 0
        
        while samplesRendered < totalSamples {
            let framesToRender = min(bufferSize, AVAudioFrameCount(totalSamples - samplesRendered))
            
            let status = try offlineEngine.renderOffline(framesToRender, to: renderBuffer)
            
            switch status {
            case .success:
                try outputFile.write(from: renderBuffer)
                samplesRendered += Int(renderBuffer.frameLength)
                
                // Update progress
                let progress = 0.2 + (Double(samplesRendered) / Double(totalSamples)) * 0.7
                onProgress?(progress, "Rendering... \(Int(progress * 100))%")
                
            case .insufficientDataFromInputNode:
                // Write silence for regions without content
                renderBuffer.frameLength = framesToRender
                for channel in 0..<Int(format.channelCount) {
                    if let channelData = renderBuffer.floatChannelData?[channel] {
                        memset(channelData, 0, Int(framesToRender) * MemoryLayout<Float>.size)
                    }
                }
                try outputFile.write(from: renderBuffer)
                samplesRendered += Int(framesToRender)
                
            case .cannotDoInCurrentContext:
                throw TrackFreezeError.exportFailed("Cannot render in current context")
                
            case .error:
                throw TrackFreezeError.exportFailed("Render error")
                
            @unknown default:
                break
            }
        }
        
        // Cleanup
        offlineEngine.stop()
        offlineEngine.disableManualRenderingMode()
        
        // Detach cloned plugins
        for plugin in clonedPlugins {
            offlineEngine.detach(plugin)
        }
    }
    
    /// Create the Frozen audio directory in the project bundle
    private func createFrozenAudioDirectory(for project: AudioProject) throws -> URL {
        let projectDir = getProjectDirectory(for: project)
        let frozenDir = projectDir.appendingPathComponent("Frozen")
        
        if !fileManager.fileExists(atPath: frozenDir.path) {
            try fileManager.createDirectory(at: frozenDir, withIntermediateDirectories: true)
        }
        
        return frozenDir
    }
    
    /// Get the project directory
    private func getProjectDirectory(for project: AudioProject) -> URL {
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sanitizedName = project.name.replacingOccurrences(of: "/", with: "_")
        return documentsDir.appendingPathComponent("Stori/Projects/\(sanitizedName).stori_assets")
    }
    
    // Root cause: @MainActor creates implicit actor isolation task-local storage
}

// NOTE: frozenAudioPath property is defined in AudioTrack model (AudioModels.swift)
