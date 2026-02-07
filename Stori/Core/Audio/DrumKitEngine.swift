//
//  DrumKitEngine.swift
//  Stori
//
//  MIDI-compatible drum kit engine for MIDI tracks.
//  Uses the same samples as Step Sequencer for consistent sound.
//

import Foundation
import AVFoundation

// MARK: - Drum Kit Engine

/// A drum kit instrument that plays samples triggered by MIDI notes.
/// Integrates with MIDI tracks and uses the same samples as Step Sequencer.
@MainActor
class DrumKitEngine {
    
    // MARK: - Properties
    
    /// The mixer node that combines all drum player outputs
    private let mixerNode: AVAudioMixerNode
    
    /// Individual players for each drum sound (allows polyphonic triggering)
    private var drumPlayers: [DrumSoundType: AVAudioPlayerNode] = [:]
    
    /// Loaded sample buffers for each drum sound
    private var loadedBuffers: [DrumSoundType: AVAudioPCMBuffer] = [:]
    
    /// Synthesized fallback buffers for each drum sound
    private var synthesizedBuffers: [DrumSoundType: AVAudioPCMBuffer] = [:]
    
    /// The AVAudioEngine this kit is attached to
    private weak var audioEngine: AVAudioEngine?
    
    /// Audio format for playback
    private var audioFormat: AVAudioFormat?
    
    /// Helper to get the DAW AudioEngine for graph validation
    private var dawAudioEngine: AudioEngine? {
        InstrumentManager.shared.audioEngine
    }
    
    /// Currently loaded drum kit
    private(set) var currentKit: DrumKit?
    
    /// Mapping from MIDI note number to DrumSoundType
    private static let midiNoteToSoundType: [UInt8: DrumSoundType] = {
        var mapping: [UInt8: DrumSoundType] = [:]
        for soundType in DrumSoundType.allCases {
            mapping[soundType.midiNote] = soundType
        }
        return mapping
    }()
    
    /// Whether the engine is attached and ready
    var isReady: Bool {
        audioEngine != nil && !drumPlayers.isEmpty
    }
    
    // MARK: - Initialization
    
    init() {
        self.mixerNode = AVAudioMixerNode()
    }
    
    /// Run deinit off the executor to avoid Swift Concurrency task-local bad-free (ASan) when
    /// the runtime deinits this object on MainActor/task-local context.
    nonisolated deinit {}
    
    /// Attach the drum kit to an audio engine
    /// - Parameters:
    ///   - engine: The AVAudioEngine to attach to
    ///   - connectToMixer: If false, caller is responsible for connecting mixerNode
    func attach(to engine: AVAudioEngine, connectToMixer: Bool = false) {
        self.audioEngine = engine
        
        // Get the hardware format
        let format = engine.outputNode.inputFormat(forBus: 0)
        self.audioFormat = format
        
        // Attach mixer node
        engine.attach(mixerNode)
        
        // Create and attach a player for each drum sound type
        for soundType in DrumSoundType.allCases {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixerNode, format: format)
            drumPlayers[soundType] = player
            
            // Pre-generate synthesized fallback
            if let synthesized = generateSynthesizedSound(for: soundType, format: format) {
                synthesizedBuffers[soundType] = synthesized
            }
        }
        
        // Connect to main mixer if requested
        if connectToMixer {
            engine.connect(mixerNode, to: engine.mainMixerNode, format: format)
        }
        
        // Load default drum kit samples
        loadDefaultKit()
    }
    
    /// Detach from the audio engine. Disconnects outputs before detach to avoid graph corruption (Issue #81).
    func detach() {
        guard let engine = audioEngine else { return }
        
        // Disconnect mixer output first (downstream-first), then stop and disconnect players
        if engine.attachedNodes.contains(mixerNode) {
            engine.disconnectNodeOutput(mixerNode)
            engine.disconnectNodeInput(mixerNode)
            engine.detach(mixerNode)
        }
        for (_, player) in drumPlayers {
            player.stop()
            if engine.attachedNodes.contains(player) {
                engine.disconnectNodeOutput(player)
                engine.disconnectNodeInput(player)
                engine.detach(player)
            }
        }
        drumPlayers.removeAll()
        audioEngine = nil
    }
    
    /// Verify and reconnect internal nodes if needed (called after engine restart)
    func reconnectNodesIfNeeded() {
        guard let engine = audioEngine, let format = audioFormat else { return }
        
        for (_, player) in drumPlayers {
            // Check if player has output connections
            let connections = engine.outputConnectionPoints(for: player, outputBus: 0)
            if connections.isEmpty {
                // Player lost its connection - reconnect to mixer
                engine.connect(player, to: mixerNode, format: format)
            }
        }
    }
    
    // MARK: - Output Node
    
    /// Get the output node for connection to track plugin chain
    func getOutputNode() -> AVAudioNode {
        return mixerNode
    }
    
    // MARK: - Kit Loading
    
    /// Load the default drum kit from DrumKitLoader
    private func loadDefaultKit() {
        // Use shared DrumKitLoader to get samples
        let loader = DrumKitLoader()
        currentKit = loader.currentKit
        
        // Copy buffers from loader
        for soundType in DrumSoundType.allCases {
            if let buffer = loader.buffer(for: soundType) {
                loadedBuffers[soundType] = buffer
            }
        }
    }
    
    /// Load a specific drum kit
    func loadKit(_ kit: DrumKit) {
        currentKit = kit
        loadedBuffers.removeAll()
        
        guard kit.directory != nil else { return }
        
        // Load samples for each sound type
        for soundType in DrumSoundType.allCases {
            if let url = kit.soundURL(for: soundType),
               let buffer = loadAudioBuffer(from: url) {
                loadedBuffers[soundType] = buffer
            }
        }
    }
    
    /// SECURITY (H-4): Max single audio file size (100 MB) for drum samples - matches DrumKitLoader.
    private static let maxAudioFileSize: Int64 = 100_000_000

    /// Load an audio file into a buffer
    private func loadAudioBuffer(from url: URL) -> AVAudioPCMBuffer? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        // SECURITY (H-4): Check file size before loading
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? Int64,
              fileSize > 0,
              fileSize <= Self.maxAudioFileSize else {
            return nil
        }

        // SECURITY (H-1): Validate header before passing to AVAudioFile
        guard AudioFileHeaderValidator.validateHeader(at: url) else { return nil }

        do {
            let audioFile = try AVAudioFile(forReading: url)
            let frameCount = AVAudioFrameCount(audioFile.length)
            
            guard let buffer = AVAudioPCMBuffer(pcmFormat: audioFile.processingFormat, frameCapacity: frameCount) else {
                return nil
            }
            
            try audioFile.read(into: buffer)
            
            // Convert to standard format if needed
            if let standardFormat = audioFormat,
               audioFile.processingFormat != standardFormat {
                return convertBuffer(buffer, to: standardFormat)
            }
            
            return buffer
        } catch {
            return nil
        }
    }
    
    /// Convert a buffer to the standard format
    private func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
            return buffer
        }
        
        let ratio = format.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: outputFrameCount) else {
            return buffer
        }
        
        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        
        if error != nil {
            return buffer
        }
        
        return outputBuffer
    }
    
    // MARK: - MIDI Note Control
    
    /// Trigger a drum sound from MIDI note
    /// - Parameters:
    ///   - pitch: MIDI note number (0-127)
    ///   - velocity: MIDI velocity (0-127)
    func noteOn(pitch: UInt8, velocity: UInt8) {
        // Map MIDI note to drum sound type
        guard let soundType = DrumKitEngine.midiNoteToSoundType[pitch] else {
            // Note doesn't map to any drum sound - ignore
            return
        }
        
        triggerSound(soundType, velocity: velocity)
    }
    
    /// Stop a drum sound (drums typically don't respond to note-off, but included for API completeness)
    /// - Parameter pitch: MIDI note number (0-127)
    func noteOff(pitch: UInt8) {
        // Drums are one-shot samples - they don't respond to note-off
        // This is intentional and matches real drum machine behavior
    }
    
    /// Trigger a specific drum sound
    /// - Parameters:
    ///   - soundType: The drum sound to trigger
    ///   - velocity: MIDI velocity (0-127)
    func triggerSound(_ soundType: DrumSoundType, velocity: UInt8) {
        guard let player = drumPlayers[soundType] else { return }
        guard let engine = audioEngine else { return }
        
        // GATE 1: Graph must be ready (not during mutations/restart)
        guard dawAudioEngine?.isGraphReadyForPlayback == true else { return }
        
        // GATE 2: Engine must be running
        guard engine.isRunning else { return }
        
        // GATE 3: TRUE render-path check using BFS
        // This catches "attached but not in render graph" (the 'U' nodes issue)
        guard dawAudioEngine?.hasPathToMainMixer(from: player) == true else { return }
        
        // Get buffer: prefer loaded sample, fall back to synthesized
        guard let buffer = loadedBuffers[soundType] ?? synthesizedBuffers[soundType] else { return }
        
        // Convert velocity to volume (0-127 -> 0.0-1.0)
        let volume = Float(velocity) / 127.0
        
        // Stop any currently playing sound on this player
        player.stop()
        
        // Schedule and play the buffer
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.volume = volume
        player.play()
    }
    
    // MARK: - Sound Synthesis (Fallback)
    
    /// Generate a synthesized drum sound as fallback
    private func generateSynthesizedSound(for soundType: DrumSoundType, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        
        // Duration varies by sound type
        let duration: Double
        switch soundType {
        case .kick:
            duration = 0.3
        case .snare, .clap, .rim:
            duration = 0.2
        case .hihatClosed:
            duration = 0.1
        case .hihatOpen, .ride, .shaker, .tambourine:
            duration = 0.4
        case .tomLow, .tomMid, .tomHigh:
            duration = 0.25
        case .crash:
            duration = 0.8
        case .cowbell:
            duration = 0.15
        case .congaLow, .congaHigh:
            duration = 0.3
        }
        
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount
        
        guard let channelData = buffer.floatChannelData else { return nil }
        
        // Generate waveform
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            let sample = synthesizeSample(for: soundType, at: t, duration: duration)
            
            for channel in 0..<Int(format.channelCount) {
                channelData[channel][frame] = Float(sample)
            }
        }
        
        return buffer
    }
    
    /// Synthesize a single sample for a drum sound
    private func synthesizeSample(for soundType: DrumSoundType, at t: Double, duration: Double) -> Double {
        let envelope = calculateEnvelope(for: soundType, at: t, duration: duration)
        
        switch soundType {
        case .kick:
            let pitchEnvelope = exp(-t * 30)
            let freq = 60 + 100 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.8
            
        case .snare:
            let tone = sin(2 * .pi * 200 * t) * exp(-t * 20)
            let noise = (Double.random(in: -1...1)) * exp(-t * 15)
            return (tone * 0.4 + noise * 0.6) * envelope
            
        case .hihatClosed:
            let noise = Double.random(in: -1...1)
            let highPass = noise * sin(2 * .pi * 8000 * t)
            return highPass * envelope * 0.5
            
        case .hihatOpen:
            let noise = Double.random(in: -1...1)
            let highPass = noise * sin(2 * .pi * 6000 * t)
            return highPass * envelope * 0.5
            
        case .clap:
            let noise = Double.random(in: -1...1)
            let filtered = noise * sin(2 * .pi * 1500 * t)
            return filtered * envelope * 0.7
            
        case .tomLow:
            let pitchEnvelope = exp(-t * 15)
            let freq = 80 + 40 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.7
            
        case .tomMid:
            let pitchEnvelope = exp(-t * 15)
            let freq = 120 + 50 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.7
            
        case .tomHigh:
            let pitchEnvelope = exp(-t * 15)
            let freq = 160 + 60 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.7
            
        case .crash:
            let noise = Double.random(in: -1...1)
            let shimmer = sin(2 * .pi * 4000 * t) + sin(2 * .pi * 5000 * t * 1.1)
            return (noise * 0.5 + shimmer * 0.3) * envelope * 0.6
            
        case .ride:
            let bell = sin(2 * .pi * 5000 * t)
            let shimmer = sin(2 * .pi * 3000 * t * 1.05)
            return (bell * 0.6 + shimmer * 0.4) * envelope * 0.5
            
        case .rim:
            let click = sin(2 * .pi * 1000 * t) * exp(-t * 50)
            let body = sin(2 * .pi * 400 * t) * exp(-t * 20)
            return (click * 0.5 + body * 0.5) * envelope
            
        case .cowbell:
            let freq1 = 800.0
            let freq2 = 540.0
            return (sin(2 * .pi * freq1 * t) * 0.6 + sin(2 * .pi * freq2 * t) * 0.4) * envelope * 0.6
            
        case .shaker:
            return Double.random(in: -1...1) * envelope * 0.4
            
        case .tambourine:
            let jingles = Double.random(in: -1...1) * sin(2 * .pi * 5500 * t)
            return jingles * envelope * 0.5
            
        case .congaLow:
            let pitchEnvelope = exp(-t * 10)
            let freq = 180 + 40 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.7
            
        case .congaHigh:
            let pitchEnvelope = exp(-t * 12)
            let freq = 250 + 60 * pitchEnvelope
            return sin(2 * .pi * freq * t) * envelope * 0.7
        }
    }
    
    /// Calculate amplitude envelope for a drum sound
    private func calculateEnvelope(for soundType: DrumSoundType, at t: Double, duration: Double) -> Double {
        let attack: Double
        let decay: Double
        
        switch soundType {
        case .kick:
            attack = 0.005
            decay = 8.0
        case .snare:
            attack = 0.002
            decay = 12.0
        case .hihatClosed:
            attack = 0.001
            decay = 25.0
        case .hihatOpen:
            attack = 0.001
            decay = 5.0
        case .clap:
            attack = 0.01
            decay = 10.0
        case .tomLow, .tomMid, .tomHigh:
            attack = 0.005
            decay = 8.0
        case .crash:
            attack = 0.001
            decay = 2.5
        case .ride:
            attack = 0.001
            decay = 3.0
        case .rim:
            attack = 0.001
            decay = 15.0
        case .cowbell:
            attack = 0.002
            decay = 12.0
        case .shaker:
            attack = 0.005
            decay = 6.0
        case .tambourine:
            attack = 0.002
            decay = 5.0
        case .congaLow, .congaHigh:
            attack = 0.005
            decay = 6.0
        }
        
        // Attack phase
        if t < attack {
            return t / attack
        }
        
        // Decay phase
        return exp(-(t - attack) * decay)
    }
}
