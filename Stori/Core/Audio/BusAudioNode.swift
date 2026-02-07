//
//  BusAudioNode.swift
//  Stori
//
//  Professional bus audio node for auxiliary effects processing
//

import Foundation
@preconcurrency import AVFoundation
import AudioToolbox
import Combine
import Accelerate
import Observation
import os.lock

// MARK: - Bus Audio Node
// PERFORMANCE: Using @Observable for fine-grained SwiftUI updates
@Observable
@MainActor
class BusAudioNode {
    
    // MARK: - Properties (ignored for observation)
    @ObservationIgnored
    let busId: UUID
    @ObservationIgnored
    private let inputMixer = AVAudioMixerNode()
    @ObservationIgnored
    private let outputMixer = AVAudioMixerNode()
    
    // MARK: - Plugin Chain (AU/VST Insert Effects - same as tracks)
    @ObservationIgnored
    let pluginChain: PluginChain
    
    // MARK: - Lock for thread-safe level access
    @ObservationIgnored
    private var inputLevelLock = os_unfair_lock_s()
    @ObservationIgnored
    private var outputLevelLock = os_unfair_lock_s()
    
    // Internal storage for levels (protected by locks)
    @ObservationIgnored
    private var _inputLevel: Float = 0.0
    @ObservationIgnored
    private var _outputLevel: Float = 0.0
    
    // MARK: - Audio Levels (observable for meters)
    var inputLevel: Float {
        get {
            os_unfair_lock_lock(&inputLevelLock)
            defer { os_unfair_lock_unlock(&inputLevelLock) }
            return _inputLevel
        }
        set {
            os_unfair_lock_lock(&inputLevelLock)
            _inputLevel = newValue
            os_unfair_lock_unlock(&inputLevelLock)
        }
    }
    
    var outputLevel: Float {
        get {
            os_unfair_lock_lock(&outputLevelLock)
            defer { os_unfair_lock_unlock(&outputLevelLock) }
            return _outputLevel
        }
        set {
            os_unfair_lock_lock(&outputLevelLock)
            _outputLevel = newValue
            os_unfair_lock_unlock(&outputLevelLock)
        }
    }
    
    // MARK: - Bus Settings
    @ObservationIgnored
    var inputGain: Float = 1.0 {
        didSet { updateInputGain() }
    }
    
    @ObservationIgnored
    var outputGain: Float = 0.75 {
        didSet { updateOutputGain() }
    }
    
    @ObservationIgnored
    var isMuted: Bool = false {
        didSet { updateMute() }
    }
    
    @ObservationIgnored
    var isSolo: Bool = false {
        didSet { updateSolo() }
    }
    
    // MARK: - Initialization
    init(busId: UUID) {
        self.busId = busId
        self.pluginChain = PluginChain(id: UUID(), maxSlots: 8)
        setupAudioChain()
    }
    
    // MARK: - Audio Chain Setup
    private func setupAudioChain() {
        // Configure input mixer for multiple sends
        inputMixer.outputVolume = inputGain
        
        // Configure output mixer for final bus output
        outputMixer.outputVolume = outputGain
        
        // NOTE: Initial connection is handled by AudioEngine.rebuildBusChain()
    }
    
    // MARK: - Node Management
    func getInputNode() -> AVAudioMixerNode {
        return inputMixer
    }
    
    func getOutputNode() -> AVAudioMixerNode {
        return outputMixer
    }
    
    // MARK: - Level Control
    private func updateInputGain() {
        inputMixer.outputVolume = inputGain
    }
    
    private func updateOutputGain() {
        outputMixer.outputVolume = isMuted ? 0.0 : outputGain
    }
    
    private func updateMute() {
        updateOutputGain()
    }
    
    private func updateSolo() {
        // Solo logic will be handled by the parent AudioEngine
    }
    
    // MARK: - Level Monitoring
    private var inputTapInstalled = false
    private var outputTapInstalled = false
    
    // PERFORMANCE: Throttle main thread updates - only update every Nth callback
    // Reduced from 3 to 6 to lower CPU usage
    private var inputLevelCounter: Int = 0
    private var outputLevelCounter: Int = 0
    private let levelUpdateInterval: Int = 6  // Update every 6th buffer callback
    
    func startLevelMonitoring() {
        // Remove any existing taps first to prevent conflicts
        stopLevelMonitoring()
        
        // Calculate dynamic buffer size for consistent ~20ms update interval across sample rates
        // This matches TrackAudioNode behavior and ensures meters respond identically at different rates
        let sampleRate = inputMixer.outputFormat(forBus: 0).sampleRate
        let targetUpdateIntervalMs: Double = 20.0
        let dynamicBufferSize = AVAudioFrameCount((targetUpdateIntervalMs / 1000.0) * sampleRate)
        let bufferSize = max(512, min(4096, dynamicBufferSize))  // Clamp to reasonable range
        
        inputMixer.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.inputLevelCounter += 1
            guard self.inputLevelCounter >= self.levelUpdateInterval else { return }
            self.inputLevelCounter = 0
            
            let level = self.calculateRMSLevel(buffer: buffer)
            // REAL-TIME SAFE: Write level directly with lock - no dispatch to main thread
            os_unfair_lock_lock(&self.inputLevelLock)
            self._inputLevel = level
            os_unfair_lock_unlock(&self.inputLevelLock)
        }
        inputTapInstalled = true
        
        outputMixer.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.outputLevelCounter += 1
            guard self.outputLevelCounter >= self.levelUpdateInterval else { return }
            self.outputLevelCounter = 0
            
            let level = self.calculateRMSLevel(buffer: buffer)
            // REAL-TIME SAFE: Write level directly with lock - no dispatch to main thread
            os_unfair_lock_lock(&self.outputLevelLock)
            self._outputLevel = level
            os_unfair_lock_unlock(&self.outputLevelLock)
        }
        outputTapInstalled = true
    }
    
    func stopLevelMonitoring() {
        if inputTapInstalled {
            inputMixer.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        
        if outputTapInstalled {
            outputMixer.removeTap(onBus: 0)
            outputTapInstalled = false
        }
    }
    
    private func calculateRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0.0 }
        
        // PERFORMANCE: Use Accelerate framework for SIMD-optimized RMS calculation
        var rms: Float = 0.0
        vDSP_rmsqv(channelData, 1, &rms, vDSP_Length(frameCount))
        
        return min(rms, 1.0) // Clamp to 0-1 range
    }
    
    // MARK: - Cleanup
    deinit {
        // Note: Cannot call @MainActor methods in deinit
        // Level monitoring will be cleaned up automatically when nodes are deallocated
    }
}
