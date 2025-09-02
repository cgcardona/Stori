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
    @Published var isCycleEnabled: Bool = false
    @Published var cycleStartTime: TimeInterval = 0.0
    @Published var cycleEndTime: TimeInterval = 8.0
    
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
        
        // Set default master volume to 60%
        mixer.outputVolume = 0.6
        
        // Start the engine
        startAudioEngine()
    }
    
    private func startAudioEngine() {
        guard !engine.isRunning else { 
            print("Audio engine already running")
            return 
        }
        
        do {
            // Ensure we have proper audio format
            let format = engine.outputNode.outputFormat(forBus: 0)
            print("Starting audio engine with format: \(format)")
            
            try engine.start()
            print("Audio engine started successfully")
            
            // Verify it's actually running
            if !engine.isRunning {
                print("Warning: Engine reports not running after start attempt")
            }
        } catch {
            print("Failed to start audio engine: \(error)")
            
            // Try to reset and start again
            engine.stop()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                do {
                    try self.engine.start()
                    print("Audio engine started on retry")
                } catch {
                    print("Failed to start audio engine on retry: \(error)")
                }
            }
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
        guard transportState.isPlaying else { 
            // print("⏸️ Not playing, skipping position update")
            return 
        }
        
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - startTime + pausedTime
        
        if let project = currentProject {
            currentPosition = PlaybackPosition(
                timeInterval: elapsed,
                tempo: project.tempo,
                timeSignature: project.timeSignature
            )
        }
        
        // Position updates happen at 60fps for smooth playback tracking
        
        // Check for cycle loop
        checkCycleLoop()
        
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
        
        // Wait a bit longer to ensure engine is fully ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            // Double-check engine is still running
            if self.engine.isRunning {
                self.setupTracksForProject(project)
            } else {
                print("Engine not running, retrying...")
                self.startAudioEngine()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.setupTracksForProject(project)
                }
            }
        }
    }
    
    func updateCurrentProject(_ project: AudioProject) {
        // Update the project reference without stopping playback or rebuilding everything
        let oldProject = currentProject
        currentProject = project
        
        // Check for new tracks that need audio node setup
        if let oldProject = oldProject {
            let oldTrackIds = Set(oldProject.tracks.map { $0.id })
            let newTrackIds = Set(project.tracks.map { $0.id })
            let addedTrackIds = newTrackIds.subtracting(oldTrackIds)
            
            // Set up audio nodes for new tracks
            for trackId in addedTrackIds {
                if let newTrack = project.tracks.first(where: { $0.id == trackId }) {
                    print("🎵 Setting up audio node for new track: \(newTrack.name)")
                    let trackNode = createTrackNode(for: newTrack)
                    trackNodes[trackId] = trackNode
                }
            }
            
            // Clean up removed tracks
            let removedTrackIds = oldTrackIds.subtracting(newTrackIds)
            for trackId in removedTrackIds {
                if let trackNode = trackNodes[trackId] {
                    print("🗑️ Removing audio node for deleted track: \(trackId)")
                    engine.disconnectNodeInput(trackNode.panNode)
                    engine.disconnectNodeInput(trackNode.volumeNode)
                    engine.disconnectNodeInput(trackNode.eqNode)
                    engine.disconnectNodeInput(trackNode.playerNode)
                    trackNodes.removeValue(forKey: trackId)
                }
            }
            
            // Update solo state in case new tracks affect it
            updateSoloState()
        }
        
        print("📝 Updated current project without stopping playback - handled \(project.tracks.count) tracks")
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
        let eqNode = AVAudioUnitEQ(numberOfBands: 3)
        let volumeNode = AVAudioMixerNode()
        let panNode = AVAudioMixerNode()
        
        // Ensure engine is running before attaching nodes
        if !engine.isRunning {
            print("Warning: Engine not running, starting it now...")
            startAudioEngine()
            // Give it a moment to start
            Thread.sleep(forTimeInterval: 0.15)
            if !engine.isRunning {
                print("Error: Audio engine failed to start")
                return TrackAudioNode(
                    id: track.id,
                    playerNode: playerNode,
                    volumeNode: volumeNode,
                    panNode: panNode,
                    eqNode: eqNode,
                    volume: track.mixerSettings.volume,
                    pan: track.mixerSettings.pan,
                    isMuted: track.mixerSettings.isMuted,
                    isSolo: track.mixerSettings.isSolo
                )
            }
        }
        
        // Attach nodes to engine
        engine.attach(playerNode)
        engine.attach(eqNode)
        engine.attach(volumeNode)
        engine.attach(panNode)
        
        // Connect the audio chain: player -> EQ -> volume -> pan -> main mixer
        do {
            engine.connect(playerNode, to: eqNode, format: nil)
            engine.connect(eqNode, to: volumeNode, format: nil)
            engine.connect(volumeNode, to: panNode, format: nil)
            engine.connect(panNode, to: mixer, format: nil)
            print("Successfully created and connected track node with EQ for: \(track.name)")
        } catch {
            print("Failed to connect audio nodes: \(error)")
            // Return a basic track node without connections if connection fails
            return TrackAudioNode(
                id: track.id,
                playerNode: playerNode,
                volumeNode: volumeNode,
                panNode: panNode,
                eqNode: eqNode,
                volume: track.mixerSettings.volume,
                pan: track.mixerSettings.pan,
                isMuted: track.mixerSettings.isMuted,
                isSolo: track.mixerSettings.isSolo
            )
        }
        
        let trackNode = TrackAudioNode(
            id: track.id,
            playerNode: playerNode,
            volumeNode: volumeNode,
            panNode: panNode,
            eqNode: eqNode,
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
        print("Clearing \(trackNodes.count) track nodes...")
        
        // First, explicitly clean up each track node to remove taps safely
        for (trackId, trackNode) in trackNodes {
            print("Cleaning up track node: \(trackId)")
            
            // The TrackAudioNode deinit will handle tap removal safely now
            // Just disconnect and detach the nodes from the engine
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
                print("Successfully cleaned up track node: \(trackId)")
            } catch {
                print("Error clearing track node \(trackId): \(error)")
            }
        }
        
        // Clear the collections
        trackNodes.removeAll()
        soloTracks.removeAll()
        print("All track nodes cleared")
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
        
        let startTime = currentPosition.timeInterval
        var scheduledNodes: [AVAudioPlayerNode] = []
        
        // First, schedule all tracks without starting playback
        for track in project.tracks {
            if let trackNode = trackNodes[track.id] {
                let activeRegions = track.regions.filter { region in
                    region.startTime <= startTime && region.endTime > startTime
                }
                
                for region in activeRegions {
                    if scheduleRegionForSynchronizedPlayback(region, on: trackNode, at: startTime) {
                        scheduledNodes.append(trackNode.playerNode)
                    }
                }
            }
        }
        
        // Now start all scheduled nodes simultaneously for perfect sync
        for playerNode in scheduledNodes {
            playerNode.play() // Start immediately
        }
        
        print("🎵 Started \(scheduledNodes.count) tracks simultaneously")
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
        // Get the track's dedicated player node
        guard let trackNode = trackNodes[track.id] else {
            print("No track node found for track: \(track.name)")
            return
        }
        
        // Find regions that should be playing at the current time
        let activeRegions = track.regions.filter { region in
            region.startTime <= startTime && region.endTime > startTime
        }
        
        // Schedule audio for each active region on this track's player node
        for region in activeRegions {
            scheduleRegion(region, on: trackNode, at: startTime)
        }
    }
    
    private func scheduleRegion(_ region: AudioRegion, on trackNode: TrackAudioNode, at currentTime: TimeInterval) {
        let playerNode = trackNode.playerNode
        
        do {
            let audioFile = try AVAudioFile(forReading: region.audioFile.url)
            let offsetInFile = currentTime - region.startTime + region.offset
            let remainingDuration = region.endTime - currentTime
            let framesToPlay = AVAudioFrameCount(remainingDuration * audioFile.processingFormat.sampleRate)
            
            if offsetInFile >= 0 && offsetInFile < region.audioFile.duration {
                let startFrame = AVAudioFramePosition(offsetInFile * audioFile.processingFormat.sampleRate)
                
                // Stop any existing playback on this node first
                if playerNode.isPlaying {
                    playerNode.stop()
                }
                
                // Schedule the audio segment
                playerNode.scheduleSegment(
                    audioFile,
                    startingFrame: startFrame,
                    frameCount: framesToPlay,
                    at: nil
                )
                
                // Start playback on this specific track's player node
                playerNode.play()
                
                print("🎵 Scheduled region '\(region.displayName)' on track '\(trackNode.id)' from \(offsetInFile)s")
            }
        } catch {
            print("❌ Failed to schedule region '\(region.displayName)': \(error)")
        }
    }
    
    private func scheduleRegionForSynchronizedPlayback(_ region: AudioRegion, on trackNode: TrackAudioNode, at currentTime: TimeInterval) -> Bool {
        let playerNode = trackNode.playerNode
        
        do {
            let audioFile = try AVAudioFile(forReading: region.audioFile.url)
            let offsetInFile = currentTime - region.startTime + region.offset
            let remainingDuration = region.endTime - currentTime
            let framesToPlay = AVAudioFrameCount(remainingDuration * audioFile.processingFormat.sampleRate)
            
            if offsetInFile >= 0 && offsetInFile < region.audioFile.duration {
                let startFrame = AVAudioFramePosition(offsetInFile * audioFile.processingFormat.sampleRate)
                
                // Stop any existing playback on this node first
                if playerNode.isPlaying {
                    playerNode.stop()
                }
                
                // Schedule the audio segment (but don't start playing yet)
                playerNode.scheduleSegment(
                    audioFile,
                    startingFrame: startFrame,
                    frameCount: framesToPlay,
                    at: nil
                )
                
                print("🎵 Scheduled region '\(region.displayName)' for synchronized playback")
                return true
            }
        } catch {
            print("❌ Failed to schedule region '\(region.displayName)' for sync: \(error)")
        }
        
        return false
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
    
    func updateTrackEQ(trackId: UUID, highEQ: Float, midEQ: Float, lowEQ: Float) {
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
    
    func updateTrackRecordEnabled(trackId: UUID, isRecordEnabled: Bool) {
        // Update the project model
        if let project = currentProject,
           let trackIndex = project.tracks.firstIndex(where: { $0.id == trackId }) {
            currentProject?.tracks[trackIndex].isRecordEnabled = isRecordEnabled
        }
        
        print("🔴 Record \(isRecordEnabled ? "enabled" : "disabled") for track \(trackId)")
    }
    
    // MARK: - Master Volume Control
    func updateMasterVolume(_ volume: Float) {
        let clampedVolume = max(0.0, min(1.0, volume))
        mixer.outputVolume = clampedVolume
        print("🔊 Master volume updated to \(Int(clampedVolume * 100))%")
    }
    
    func getMasterVolume() -> Float {
        return mixer.outputVolume
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
    
    func getMasterLevel() -> (current: Float, peak: Float) {
        // Get the actual master bus level from the main mixer node
        // This represents the combined output of all tracks after mixing
        
        // Get current master volume setting
        let masterVolume = getMasterVolume()
        
        // If master volume is 0, return silent levels
        guard masterVolume > 0.0 else {
            return (current: 0.0, peak: 0.0)
        }
        
        // Calculate RMS of all active (non-muted) tracks
        let trackLevels = getTrackLevels()
        let activeTracks = trackLevels.values.filter { $0.current > 0.0 }
        
        guard !activeTracks.isEmpty else {
            return (current: 0.0, peak: 0.0)
        }
        
        // Calculate RMS (Root Mean Square) for more accurate master level
        let sumOfSquares = activeTracks.map { $0.current * $0.current }.reduce(0, +)
        let rms = sqrt(sumOfSquares / Float(activeTracks.count))
        
        let maxPeak = activeTracks.map { $0.peak }.max() ?? 0.0
        
        // Apply master volume to the calculated levels (post-fader metering)
        let postFaderRMS = rms * masterVolume
        let postFaderPeak = maxPeak * masterVolume
        
        return (current: postFaderRMS, peak: postFaderPeak)
    }
    
    // MARK: - Timeline Navigation
    
    func seekToPosition(_ timeInterval: TimeInterval) {
        let wasPlaying = transportState == .playing
        let newTime = max(0, timeInterval)
        
        print("🎯 Seeking to position: \(String(format: "%.2f", newTime))s, wasPlaying=\(wasPlaying)")
        
        // Stop all current playback
        if wasPlaying {
            pause()
        }
        
        // Update position
        currentPosition = PlaybackPosition(
            timeInterval: newTime,
            tempo: currentProject?.tempo ?? 120,
            timeSignature: currentProject?.timeSignature ?? .fourFour
        )
        
        // Update timer tracking variables to keep position calculation in sync
        pausedTime = newTime
        startTime = CACurrentMediaTime()
        
        // If we were playing, resume playback from the new position
        if wasPlaying {
            playFromPosition(newTime)
        }
        
        print("🎵 Seeked to position: \(currentTimeString)")
    }
    
    private func playFromPosition(_ startTime: TimeInterval) {
        guard let project = currentProject else { return }
        
        print("🎯 Starting playback from position: \(String(format: "%.2f", startTime))s")
        
        // Set transport state
        transportState = .playing
        
        // Schedule and start all tracks from the specified position
        var tracksStarted = 0
        
        for track in project.tracks {
            guard let trackNode = trackNodes[track.id] else { continue }
            
            // Only play tracks that have audio regions at or after the start time
            let relevantRegions = track.regions.filter { region in
                region.startTime + region.duration > startTime
            }
            
            if !relevantRegions.isEmpty {
                do {
                    try trackNode.scheduleFromPosition(startTime, audioRegions: track.regions)
                    trackNode.play()
                    tracksStarted += 1
                } catch {
                    print("❌ Failed to schedule track \(track.name) from position \(startTime): \(error)")
                }
            }
        }
        
        if tracksStarted > 0 {
            print("🎵 Started \(tracksStarted) tracks from position \(String(format: "%.2f", startTime))s")
        } else {
            print("⚠️ No tracks to play from position \(String(format: "%.2f", startTime))s")
        }
    }
    
    func rewind(_ seconds: TimeInterval = 1.0) {
        let newTime = max(0, currentPosition.timeInterval - seconds)
        seekToPosition(newTime)
    }
    
    func fastForward(_ seconds: TimeInterval = 1.0) {
        let newTime = currentPosition.timeInterval + seconds
        seekToPosition(newTime)
    }
    
    func skipToBeginning() {
        seekToPosition(0)
    }
    
    func skipToEnd() {
        // Skip to end of longest track or 10 seconds forward if no tracks
        guard let project = currentProject else {
            seekToPosition(currentPosition.timeInterval + 10)
            return
        }
        
        let maxDuration = project.tracks.compactMap { track in
            track.regions.map { region in
                region.startTime + region.duration
            }.max()
        }.max() ?? currentPosition.timeInterval + 10
        
        seekToPosition(maxDuration)
    }
    
    // MARK: - Cycle Controls
    
    func toggleCycle() {
        isCycleEnabled.toggle()
        print("🔄 Cycle \(isCycleEnabled ? "enabled" : "disabled"): \(cycleStartTime)s - \(cycleEndTime)s")
    }
    
    func setCycleRegion(start: TimeInterval, end: TimeInterval) {
        cycleStartTime = max(0, start)
        cycleEndTime = max(cycleStartTime + 0.1, end) // Ensure minimum 0.1s cycle length
        // Cycle region updated silently for smooth interaction
    }
    
    private func checkCycleLoop() {
        guard isCycleEnabled else { 
            // print("🔄 Cycle disabled, skipping loop check")
            return 
        }
        
        guard transportState.isPlaying else { 
            // print("🔄 Not playing, skipping loop check")
            return 
        }
        
        let currentTime = currentPosition.timeInterval
        
        // Check if we've reached the cycle end point
        
        if currentTime >= cycleEndTime {
            print("🔄 LOOPING! Cycling back to start: \(cycleStartTime)s")
            seekToPosition(cycleStartTime)
        }
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
