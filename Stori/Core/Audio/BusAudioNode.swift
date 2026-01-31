//
//  BusAudioNode.swift
//  Stori
//
//  Professional bus audio node for auxiliary effects processing
//

import Foundation
import AVFoundation
import AudioToolbox
import Combine
import Accelerate
import Observation

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
    
    // MARK: - Audio Levels (observable for meters)
    var inputLevel: Float = 0.0
    var outputLevel: Float = 0.0
    
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
        
        // PERFORMANCE: Use larger buffers and throttle updates
        inputMixer.installTap(onBus: 0, bufferSize: AudioConstants.masterMeteringBufferSize, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.inputLevelCounter += 1
            guard self.inputLevelCounter >= self.levelUpdateInterval else { return }
            self.inputLevelCounter = 0
            
            let level = self.calculateRMSLevel(buffer: buffer)
            DispatchQueue.main.async {
                self.inputLevel = level
            }
        }
        inputTapInstalled = true
        
        outputMixer.installTap(onBus: 0, bufferSize: AudioConstants.masterMeteringBufferSize, format: nil) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.outputLevelCounter += 1
            guard self.outputLevelCounter >= self.levelUpdateInterval else { return }
            self.outputLevelCounter = 0
            
            let level = self.calculateRMSLevel(buffer: buffer)
            DispatchQueue.main.async {
                self.outputLevel = level
            }
        }
        outputTapInstalled = true
    }
    
    func stopLevelMonitoring() {
        if inputTapInstalled {
            do {
                inputMixer.removeTap(onBus: 0)
                inputTapInstalled = false
            } catch {
                inputTapInstalled = false // Reset flag anyway
            }
        }
        
        if outputTapInstalled {
            do {
                outputMixer.removeTap(onBus: 0)
                outputTapInstalled = false
            } catch {
                outputTapInstalled = false // Reset flag anyway
            }
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
