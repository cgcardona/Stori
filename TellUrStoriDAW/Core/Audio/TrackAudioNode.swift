//
//  TrackAudioNode.swift
//  TellUrStoriDAW
//
//  Audio node representation for individual tracks
//

import Foundation
import AVFoundation

// MARK: - Track Audio Node
class TrackAudioNode {
    
    // MARK: - Properties
    let id: UUID
    let playerNode: AVAudioPlayerNode
    let volumeNode: AVAudioMixerNode
    let panNode: AVAudioMixerNode
    let eqNode: AVAudioUnitEQ
    let effectsChain: [AVAudioNode] = []
    
    // MARK: - Audio State
    private(set) var volume: Float
    private(set) var pan: Float
    private(set) var isMuted: Bool
    private(set) var isSolo: Bool
    
    // MARK: - Level Monitoring
    private var levelTapInstalled: Bool = false
    var currentLevel: Float = 0.0
    var peakLevel: Float = 0.0
    
    // MARK: - Initialization
    init(
        id: UUID,
        playerNode: AVAudioPlayerNode,
        volumeNode: AVAudioMixerNode,
        panNode: AVAudioMixerNode,
        eqNode: AVAudioUnitEQ,
        volume: Float = 0.8,
        pan: Float = 0.0,
        isMuted: Bool = false,
        isSolo: Bool = false
    ) {
        self.id = id
        self.playerNode = playerNode
        self.volumeNode = volumeNode
        self.panNode = panNode
        self.eqNode = eqNode
        self.volume = volume
        self.pan = pan
        self.isMuted = isMuted
        self.isSolo = isSolo
        
        setupEQ()
        setupLevelMonitoring()
    }
    
    deinit {
        removeLevelMonitoring()
    }
    
    // MARK: - Volume Control
    func setVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
        let actualVolume = isMuted ? 0.0 : volume
        volumeNode.outputVolume = actualVolume
    }
    
    // MARK: - Pan Control
    func setPan(_ newPan: Float) {
        pan = max(-1.0, min(1.0, newPan))
        panNode.pan = pan
    }
    
    // MARK: - Mute Control
    func setMuted(_ muted: Bool) {
        isMuted = muted
        let actualVolume = muted ? 0.0 : volume
        volumeNode.outputVolume = actualVolume
    }
    
    // MARK: - Solo Control
    func setSolo(_ solo: Bool) {
        isSolo = solo
        // Solo logic will be handled at the engine level
    }
    
    // MARK: - EQ Control
    private func setupEQ() {
        // Configure 3-band EQ with standard frequencies
        eqNode.bands[0].filterType = .highShelf
        eqNode.bands[0].frequency = 10000 // High: 10kHz
        eqNode.bands[0].gain = 0
        eqNode.bands[0].bypass = false
        
        eqNode.bands[1].filterType = .parametric
        eqNode.bands[1].frequency = 1000 // Mid: 1kHz
        eqNode.bands[1].bandwidth = 1.0
        eqNode.bands[1].gain = 0
        eqNode.bands[1].bypass = false
        
        eqNode.bands[2].filterType = .lowShelf
        eqNode.bands[2].frequency = 100 // Low: 100Hz
        eqNode.bands[2].gain = 0
        eqNode.bands[2].bypass = false
        
        print("🎛️ EQ setup complete for track \(id)")
    }
    
    func setEQ(highGain: Float, midGain: Float, lowGain: Float) {
        // Clamp values to reasonable EQ range
        let clampedHigh = max(-12.0, min(12.0, highGain))
        let clampedMid = max(-12.0, min(12.0, midGain))
        let clampedLow = max(-12.0, min(12.0, lowGain))
        
        eqNode.bands[0].gain = clampedHigh // High
        eqNode.bands[1].gain = clampedMid  // Mid
        eqNode.bands[2].gain = clampedLow  // Low
        
        print("🎛️ EQ updated for track \(id): High=\(clampedHigh)dB, Mid=\(clampedMid)dB, Low=\(clampedLow)dB")
    }
    
    // MARK: - Level Monitoring
    private func setupLevelMonitoring() {
        guard !levelTapInstalled else { return }
        
        // Delay level monitoring setup to avoid engine issues
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.installLevelTap()
        }
    }
    
    private func installLevelTap() {
        guard !levelTapInstalled else { return }
        
        do {
            let format = volumeNode.outputFormat(forBus: 0)
            
            volumeNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self = self else { return }
                
                let channelData = buffer.floatChannelData?[0]
                let frameCount = Int(buffer.frameLength)
                
                var sum: Float = 0.0
                var peak: Float = 0.0
                
                for i in 0..<frameCount {
                    let sample = abs(channelData?[i] ?? 0.0)
                    sum += sample * sample
                    peak = max(peak, sample)
                }
                
                let rms = sqrt(sum / Float(frameCount))
                
                DispatchQueue.main.async {
                    self.currentLevel = rms
                    self.peakLevel = max(self.peakLevel * 0.95, peak) // Decay peak hold
                }
            }
            
            levelTapInstalled = true
        } catch {
            print("Failed to install level tap: \(error)")
        }
    }
    
    private func removeLevelMonitoring() {
        guard levelTapInstalled else { return }
        
        // Safety check: only remove tap if the node is still attached to an engine
        if volumeNode.engine != nil {
            do {
                volumeNode.removeTap(onBus: 0)
                print("Successfully removed level monitoring tap for track \(id)")
            } catch {
                print("Error removing level monitoring tap for track \(id): \(error)")
            }
        } else {
            print("Skipping tap removal for track \(id) - node not attached to engine")
        }
        
        levelTapInstalled = false
    }
    
    // MARK: - Audio File Loading
    func loadAudioFile(_ audioFile: AudioFile) throws {
        let url = audioFile.url
        
        let audioFileRef = try AVAudioFile(forReading: url)
        playerNode.scheduleFile(audioFileRef, at: nil)
    }
    
    func scheduleFromPosition(_ startTime: TimeInterval, audioRegions: [AudioRegion]) throws {
        // Stop any current playback
        playerNode.stop()
        
        // Schedule audio regions that are active at the given start time
        for region in audioRegions {
            let regionEndTime = region.startTime + region.duration
            
            // Only schedule regions that are playing at or after the start time
            if regionEndTime > startTime {
                let audioFile = try AVAudioFile(forReading: region.audioFile.url)
                let sampleRate = audioFile.processingFormat.sampleRate
                
                // Calculate the offset within the region
                let offsetInRegion = max(0, startTime - region.startTime)
                let startFrame = AVAudioFramePosition(offsetInRegion * sampleRate)
                let totalFrames = audioFile.length
                let framesToPlay = max(0, totalFrames - startFrame)
                
                if framesToPlay > 0 {
                    print("🎵 Scheduling region '\(region.audioFile.name)' from frame \(startFrame)/\(totalFrames)")
                    
                    playerNode.scheduleSegment(
                        audioFile,
                        startingFrame: startFrame,
                        frameCount: AVAudioFrameCount(framesToPlay),
                        at: nil
                    )
                }
            }
        }
    }
    
    // MARK: - Playback Control
    func play() {
        if !playerNode.isPlaying {
            playerNode.play()
        }
    }
    
    func pause() {
        if playerNode.isPlaying {
            playerNode.pause()
        }
    }
    
    func stop() {
        playerNode.stop()
    }
    
    // MARK: - Additional Methods for DAWTrackHeader
    func setRecordEnabled(_ enabled: Bool) {
        // Implementation for record enable functionality
        // This would typically involve setting up input monitoring and recording paths
        print("🎙️ TrackAudioNode record enable: \(enabled)")
    }
    
    func setInputMonitoring(_ enabled: Bool) {
        // Implementation for input monitoring functionality
        // This would typically involve routing input to output for zero-latency monitoring
        print("🎧 TrackAudioNode input monitoring: \(enabled)")
    }
    
    func setFrozen(_ frozen: Bool) {
        // Implementation for track freezing functionality
        // This would typically involve bouncing the track to audio and disabling real-time processing
        print("❄️ TrackAudioNode frozen: \(frozen)")
    }
}

// MARK: - Audio Engine Error
enum AudioEngineError: Error {
    case invalidFilePath
    case audioFileNotFound
    case unsupportedFormat
    case engineNotRunning
}
