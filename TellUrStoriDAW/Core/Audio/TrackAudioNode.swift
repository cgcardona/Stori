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
        volume: Float = 0.8,
        pan: Float = 0.0,
        isMuted: Bool = false,
        isSolo: Bool = false
    ) {
        self.id = id
        self.playerNode = playerNode
        self.volumeNode = volumeNode
        self.panNode = panNode
        self.volume = volume
        self.pan = pan
        self.isMuted = isMuted
        self.isSolo = isSolo
        
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
        if levelTapInstalled {
            volumeNode.removeTap(onBus: 0)
            levelTapInstalled = false
        }
    }
    
    // MARK: - Audio File Loading
    func loadAudioFile(_ audioFile: AudioFile) throws {
        let url = audioFile.url
        
        let audioFileRef = try AVAudioFile(forReading: url)
        playerNode.scheduleFile(audioFileRef, at: nil)
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
}

// MARK: - Audio Engine Error
enum AudioEngineError: Error {
    case invalidFilePath
    case audioFileNotFound
    case unsupportedFormat
    case engineNotRunning
}
