//
//  AudioEngine.swift
//  TellUrStoriDAW
//
//  Core audio engine for real-time audio processing
//

import Foundation
import AVFoundation
import Combine

// MARK: - Audio Engine Manager
@MainActor
class AudioEngine: ObservableObject {
    
    // MARK: - Published Properties
    @Published var transportState: TransportState = .stopped
    @Published var currentPosition: PlaybackPosition = PlaybackPosition()
    @Published var isRecording: Bool = false
    @Published var cpuUsage: Double = 0.0
    @Published var audioLevels: [Float] = []
    
    // MARK: - Private Properties
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var trackNodes: [UUID: TrackAudioNode] = [:]
    private var startTime: TimeInterval = 0
    private var pausedTime: TimeInterval = 0
    private var soloTracks: Set<UUID> = []
    
    // MARK: - Current Project
    private var currentProject: AudioProject?
    
    // MARK: - Timer for position updates
    private var positionTimer: Timer?
    
    // MARK: - Initialization
    init() {
        setupAudioEngine()
        setupPositionTimer()
    }
    
    deinit {
        positionTimer?.invalidate()
        // Note: Cannot access @MainActor properties in deinit
        // The engine will be cleaned up automatically
    }
    
    // MARK: - Audio Engine Setup
    private func setupAudioEngine() {
        // Connect mixer to output
        engine.attach(mixer)
        engine.connect(mixer, to: engine.outputNode, format: nil)
        
        // Start the engine
        startAudioEngine()
    }
    
    private func startAudioEngine() {
        guard !engine.isRunning else { return }
        
        do {
            try engine.start()
            print("Audio engine started successfully")
        } catch {
            print("Failed to start audio engine: \(error)")
        }
    }
    
    // MARK: - Timer for Position Updates
    private func setupPositionTimer() {
        positionTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updatePosition()
            }
        }
    }
    
    private func updatePosition() {
        guard transportState.isPlaying else { return }
        
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - startTime + pausedTime
        
        if let project = currentProject {
            currentPosition = PlaybackPosition(
                timeInterval: elapsed,
                tempo: project.tempo,
                timeSignature: project.timeSignature
            )
        }
        
        // Update CPU usage (simplified)
        updateCPUUsage()
    }
    
    private func updateCPUUsage() {
        // This is a simplified CPU usage calculation
        // In a real implementation, you'd measure actual audio processing load
        cpuUsage = Double.random(in: 0.05...0.25) // Simulated 5-25% usage
    }
    
    // MARK: - Project Management
    func loadProject(_ project: AudioProject) {
        transportState = .stopped
        stopPlayback()
        currentProject = project
        
        // Ensure engine is running before setting up tracks
        startAudioEngine()
        
        // Small delay to ensure engine is fully ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.setupTracksForProject(project)
        }
    }
    
    private func setupTracksForProject(_ project: AudioProject) {
        // Clear existing track nodes
        clearAllTracks()
        
        // Create track nodes for each track
        for track in project.tracks {
            let trackNode = createTrackNode(for: track)
            trackNodes[track.id] = trackNode
        }
        
        // Update solo state
        updateSoloState()
    }
    
    private func createTrackNode(for track: AudioTrack) -> TrackAudioNode {
        let playerNode = AVAudioPlayerNode()
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        
        // Ensure engine is running before attaching nodes
        startAudioEngine()
        
        // Attach nodes to engine
        engine.attach(playerNode)
        engine.attach(volumeNode)
        engine.attach(panNode)
        
        // Connect the audio chain: player -> volume -> pan -> main mixer
        do {
            engine.connect(playerNode, to: volumeNode, format: nil)
            engine.connect(volumeNode, to: panNode, format: nil)
            engine.connect(panNode, to: mixer, format: nil)
        } catch {
            print("Failed to connect audio nodes: \(error)")
        }
        
        let trackNode = TrackAudioNode(
            id: track.id,
            playerNode: playerNode,
            volumeNode: volumeNode,
            panNode: panNode,
            volume: track.mixerSettings.volume,
            pan: track.mixerSettings.pan,
            isMuted: track.mixerSettings.isMuted,
            isSolo: track.mixerSettings.isSolo
        )
        
        // Apply initial settings
        trackNode.setVolume(track.mixerSettings.volume)
        trackNode.setPan(track.mixerSettings.pan)
        trackNode.setMuted(track.mixerSettings.isMuted)
        trackNode.setSolo(track.mixerSettings.isSolo)
        
        // Load audio regions for this track
        for region in track.regions {
            loadAudioRegion(region, trackNode: trackNode)
        }
        
        return trackNode
    }
    
    private func clearAllTracks() {
        for (_, trackNode) in trackNodes {
            // Safely disconnect and remove nodes
            do {
                if engine.attachedNodes.contains(trackNode.panNode) {
                    engine.disconnectNodeInput(trackNode.panNode)
                    engine.detach(trackNode.panNode)
                }
                if engine.attachedNodes.contains(trackNode.volumeNode) {
                    engine.disconnectNodeInput(trackNode.volumeNode)
                    engine.detach(trackNode.volumeNode)
                }
                if engine.attachedNodes.contains(trackNode.playerNode) {
                    engine.disconnectNodeInput(trackNode.playerNode)
                    engine.detach(trackNode.playerNode)
                }
            } catch {
                print("Error clearing track nodes: \(error)")
            }
        }
        trackNodes.removeAll()
        soloTracks.removeAll()
    }
    
    // MARK: - Transport Controls
    func play() {
        guard currentProject != nil else { return }
        
        switch transportState {
        case .stopped:
            startTime = CACurrentMediaTime()
            pausedTime = 0
            transportState = .playing
            
        case .paused:
            startTime = CACurrentMediaTime()
            transportState = .playing
            
        case .playing, .recording:
            return // Already playing
        }
        
        startPlayback()
    }
    
    func pause() {
        guard transportState.isPlaying else { return }
        
        pausedTime = currentPosition.timeInterval
        transportState = .paused
        stopPlayback()
    }
    
    func stop() {
        transportState = .stopped
        pausedTime = 0
        currentPosition = PlaybackPosition()
        stopPlayback()
    }
    
    func record() {
        guard currentProject != nil else { return }
        
        if transportState != .playing {
            play()
        }
        
        transportState = .recording
        isRecording = true
        startRecording()
    }
    
    func stopRecording() {
        if transportState == .recording {
            transportState = .stopped
            isRecording = false
            stopPlayback()
        }
    }
    
    // MARK: - Playback Implementation
    private func startPlayback() {
        guard let project = currentProject else { return }
        
        // Start all player nodes
        for track in project.tracks {
            playTrack(track, from: currentPosition.timeInterval)
        }
    }
    
    private func stopPlayback() {
        // Stop all player nodes
        for node in engine.attachedNodes {
            if let playerNode = node as? AVAudioPlayerNode {
                playerNode.stop()
            }
        }
    }
    
    private func playTrack(_ track: AudioTrack, from startTime: TimeInterval) {
        // Find regions that should be playing at the current time
        let activeRegions = track.regions.filter { region in
            region.startTime <= startTime && region.endTime > startTime
        }
        
        // Schedule audio for each active region
        for region in activeRegions {
            scheduleRegion(region, at: startTime)
        }
    }
    
    private func scheduleRegion(_ region: AudioRegion, at currentTime: TimeInterval) {
        // This is a simplified implementation
        // In a real DAW, you'd need more sophisticated scheduling
        
        guard let playerNode = findPlayerNodeForRegion(region) else { return }
        
        do {
            let audioFile = try AVAudioFile(forReading: region.audioFile.url)
            let offsetInFile = currentTime - region.startTime + region.offset
            let framesToPlay = AVAudioFrameCount((region.endTime - currentTime) * audioFile.processingFormat.sampleRate)
            
            if offsetInFile >= 0 && offsetInFile < region.audioFile.duration {
                let startFrame = AVAudioFramePosition(offsetInFile * audioFile.processingFormat.sampleRate)
                
                playerNode.scheduleSegment(
                    audioFile,
                    startingFrame: startFrame,
                    frameCount: framesToPlay,
                    at: nil
                )
                
                if !playerNode.isPlaying {
                    playerNode.play()
                }
            }
        } catch {
            print("Failed to schedule region: \(error)")
        }
    }
    
    private func findPlayerNodeForRegion(_ region: AudioRegion) -> AVAudioPlayerNode? {
        // In a real implementation, you'd maintain a mapping between regions and player nodes
        return engine.attachedNodes.compactMap { $0 as? AVAudioPlayerNode }.first
    }
    
    // MARK: - Recording Implementation
    private func startRecording() {
        // Implement recording logic
        // This would involve setting up input nodes and recording to files
        print("Recording started")
    }
    
    private func stopRecordingInternal() {
        // Implement stop recording logic
        print("Recording stopped")
    }
    
    // MARK: - Position Control
    func seek(to position: TimeInterval) {
        let wasPlaying = transportState.isPlaying
        
        if wasPlaying {
            stopPlayback()
        }
        
        pausedTime = position
        
        if let project = currentProject {
            currentPosition = PlaybackPosition(
                timeInterval: position,
                tempo: project.tempo,
                timeSignature: project.timeSignature
            )
        }
        
        if wasPlaying {
            startTime = CACurrentMediaTime()
            startPlayback()
        }
    }
    
    // MARK: - Mixer Controls
    func setTrackVolume(_ trackId: UUID, volume: Float) {
        guard let project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            var updatedProject = project
            updatedProject.tracks[trackIndex].mixerSettings.volume = volume
            currentProject = updatedProject
            
            // Update the actual audio node volume
            updateTrackMixerSettings(trackId, settings: updatedProject.tracks[trackIndex].mixerSettings)
        }
    }
    
    func setTrackPan(_ trackId: UUID, pan: Float) {
        guard let project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            var updatedProject = project
            updatedProject.tracks[trackIndex].mixerSettings.pan = pan
            currentProject = updatedProject
            
            updateTrackMixerSettings(trackId, settings: updatedProject.tracks[trackIndex].mixerSettings)
        }
    }
    
    func muteTrack(_ trackId: UUID, muted: Bool) {
        guard let project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            var updatedProject = project
            updatedProject.tracks[trackIndex].isMuted = muted
            currentProject = updatedProject
            
            // Update actual mute state in audio engine
            updateTrackMuteState(trackId, muted: muted)
        }
    }
    
    func soloTrack(_ trackId: UUID, solo: Bool) {
        guard let project = currentProject else { return }
        
        var updatedProject = project
        
        if solo {
            // Mute all other tracks
            for i in 0..<updatedProject.tracks.count {
                updatedProject.tracks[i].isSolo = updatedProject.tracks[i].id == trackId
            }
        } else {
            // Un-solo this track
            if let trackIndex = updatedProject.tracks.firstIndex(where: { $0.id == trackId }) {
                updatedProject.tracks[trackIndex].isSolo = false
            }
        }
        
        currentProject = updatedProject
        updateAllTrackStates()
    }
    
    private func updateTrackMixerSettings(_ trackId: UUID, settings: MixerSettings) {
        // Find and update the mixer node for this track
        // Implementation would depend on how you map tracks to nodes
    }
    
    private func updateTrackMuteState(_ trackId: UUID, muted: Bool) {
        // Update the mute state in the audio engine
    }
    
    private func updateAllTrackStates() {
        // Update all track states in the audio engine
    }
    
    // MARK: - Audio File Import
    func importAudioFile(from url: URL) async throws -> AudioFile {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = fileAttributes[.size] as? Int64 ?? 0
        
        let audioFileFormat: AudioFileFormat
        switch url.pathExtension.lowercased() {
        case "wav": audioFileFormat = .wav
        case "aiff", "aif": audioFileFormat = .aiff
        case "mp3": audioFileFormat = .mp3
        case "m4a": audioFileFormat = .m4a
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
    
    // MARK: - Audio Region Loading
    private func loadAudioRegion(_ region: AudioRegion, trackNode: TrackAudioNode) {
        let audioFile = region.audioFile
        
        do {
            try trackNode.loadAudioFile(audioFile)
        } catch {
            print("Failed to load audio file: \(error)")
        }
    }
    
    // MARK: - Mixer Controls
    func updateTrackVolume(trackId: UUID, volume: Float) {
        guard let trackNode = trackNodes[trackId] else { return }
        trackNode.setVolume(volume)
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.volume = volume
        }
    }
    
    func updateTrackPan(trackId: UUID, pan: Float) {
        guard let trackNode = trackNodes[trackId] else { return }
        trackNode.setPan(pan)
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.pan = pan
        }
    }
    
    func updateTrackMute(trackId: UUID, isMuted: Bool) {
        guard let trackNode = trackNodes[trackId] else { return }
        trackNode.setMuted(isMuted)
        
        // Update the project model
        updateProjectTrackMixerSettings(trackId: trackId) { settings in
            settings.isMuted = isMuted
        }
    }
    
    func updateTrackSolo(trackId: UUID, isSolo: Bool) {
        guard let trackNode = trackNodes[trackId] else { return }
        
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
    }
    
    private func updateSoloState() {
        let hasSoloTracks = !soloTracks.isEmpty
        
        for (trackId, trackNode) in trackNodes {
            if hasSoloTracks {
                // If there are solo tracks, mute all non-solo tracks
                let shouldBeMuted = !soloTracks.contains(trackId)
                trackNode.setMuted(shouldBeMuted || trackNode.isMuted)
            } else {
                // If no solo tracks, restore original mute state
                if let project = currentProject,
                   let track = project.tracks.first(where: { $0.id == trackId }) {
                    trackNode.setMuted(track.mixerSettings.isMuted)
                }
            }
        }
    }
    
    private func updateProjectTrackMixerSettings(trackId: UUID, update: (inout MixerSettings) -> Void) {
        guard var project = currentProject else { return }
        
        if let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            update(&project.tracks[trackIndex].mixerSettings)
            currentProject = project
        }
    }
    

    
    func removeTrack(trackId: UUID) {
        guard var project = currentProject else { return }
        
        // Remove from project
        project.tracks.removeAll { $0.id == trackId }
        currentProject = project
        
        // Remove track node
        if let trackNode = trackNodes[trackId] {
            engine.disconnectNodeInput(trackNode.panNode)
            engine.disconnectNodeInput(trackNode.volumeNode)
            engine.disconnectNodeInput(trackNode.playerNode)
            
            engine.detach(trackNode.panNode)
            engine.detach(trackNode.volumeNode)
            engine.detach(trackNode.playerNode)
            
            trackNodes.removeValue(forKey: trackId)
        }
        
        // Remove from solo tracks if present
        soloTracks.remove(trackId)
        updateSoloState()
    }
    
    // MARK: - Level Monitoring
    func getTrackLevels() -> [UUID: (current: Float, peak: Float)] {
        var levels: [UUID: (current: Float, peak: Float)] = [:]
        
        for (trackId, trackNode) in trackNodes {
            levels[trackId] = (current: trackNode.currentLevel, peak: trackNode.peakLevel)
        }
        
        return levels
    }
}

// MARK: - Audio Engine Extensions
extension AudioEngine {
    
    var isPlaying: Bool {
        transportState.isPlaying
    }
    
    var currentTimeString: String {
        let minutes = Int(currentPosition.timeInterval) / 60
        let seconds = Int(currentPosition.timeInterval) % 60
        let milliseconds = Int((currentPosition.timeInterval.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    var currentMusicalTimeString: String {
        guard let project = currentProject else { return "1.1.00" }
        return currentPosition.displayString(timeSignature: project.timeSignature)
    }
}
