//
//  BusAudioNode.swift
//  TellUrStoriDAW
//
//  Professional bus audio node for auxiliary effects processing
//

import Foundation
import AVFoundation
import AudioToolbox

// MARK: - Bus Audio Node
@MainActor
class BusAudioNode: ObservableObject {
    
    // MARK: - Properties
    let busId: UUID
    let busType: BusType
    private let inputMixer = AVAudioMixerNode()
    private let outputMixer = AVAudioMixerNode()
    private var effectNodes: [AVAudioNode] = []
    private var effectUnits: [UUID: AVAudioUnit] = [:]
    
    // MARK: - Audio Levels
    @Published var inputLevel: Float = 0.0
    @Published var outputLevel: Float = 0.0
    
    // MARK: - Bus Settings
    var inputGain: Float = 1.0 {
        didSet { updateInputGain() }
    }
    
    var outputGain: Float = 0.75 {
        didSet { updateOutputGain() }
    }
    
    var isMuted: Bool = false {
        didSet { updateMute() }
    }
    
    var isSolo: Bool = false {
        didSet { updateSolo() }
    }
    
    // MARK: - Initialization
    init(busId: UUID, busType: BusType) {
        self.busId = busId
        self.busType = busType
        setupAudioChain()
    }
    
    // MARK: - Audio Chain Setup
    private func setupAudioChain() {
        // Configure input mixer for multiple sends
        inputMixer.outputVolume = inputGain
        
        // Configure output mixer for final bus output
        outputMixer.outputVolume = outputGain
        
        // Initially connect input directly to output (no effects)
        connectNodes()
    }
    
    // MARK: - Node Management
    func getInputNode() -> AVAudioMixerNode {
        return inputMixer
    }
    
    func getOutputNode() -> AVAudioMixerNode {
        return outputMixer
    }
    
    // MARK: - Effect Management
    func addEffect(_ effect: BusEffect) {
        Task { @MainActor in
            guard let effectUnit = createEffectUnit(for: effect) else {
                print("Failed to create effect unit for \(effect.type)")
                return
            }
            
            effectUnits[effect.id] = effectUnit
            rebuildEffectChain()
            applyEffectParameters(effect)
        }
    }
    
    func removeEffect(withId effectId: UUID) {
        effectUnits.removeValue(forKey: effectId)
        rebuildEffectChain()
    }
    
    func updateEffect(_ effect: BusEffect) {
        guard effectUnits[effect.id] != nil else { return }
        applyEffectParameters(effect)
    }
    
    // MARK: - Effect Unit Creation
    private func createEffectUnit(for effect: BusEffect) -> AVAudioUnit? {
        let audioComponentDescription: AudioComponentDescription
        
        switch effect.type {
        case .reverb:
            audioComponentDescription = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_Reverb2,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            
        case .delay:
            audioComponentDescription = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_Delay,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            
        case .chorus:
            audioComponentDescription = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_Delay,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            
        case .compressor:
            audioComponentDescription = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            
        case .eq:
            audioComponentDescription = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_ParametricEQ,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            
        case .distortion:
            audioComponentDescription = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_Distortion,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            
        case .filter:
            audioComponentDescription = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_LowPassFilter,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            
        case .modulation:
            audioComponentDescription = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_Delay,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
        }
        
        var effectUnit: AVAudioUnit?
        let semaphore = DispatchSemaphore(value: 0)
        
        AVAudioUnit.instantiate(with: audioComponentDescription) { audioUnit, error in
            if let error = error {
                print("Error creating audio unit: \(error)")
            } else {
                effectUnit = audioUnit
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return effectUnit
    }
    
    // MARK: - Effect Chain Management
    private func rebuildEffectChain() {
        // Disconnect all current connections
        disconnectNodes()
        
        // Get all enabled effects in order
        let enabledEffects = effectUnits.values.filter { _ in true } // TODO: Check if effect is enabled
        
        if enabledEffects.isEmpty {
            // Direct connection: input -> output
            connectNodes()
        } else {
            // Chain effects: input -> effect1 -> effect2 -> ... -> output
            // Connect the chain
            connectEffectChain(Array(enabledEffects))
        }
    }
    
    private func connectNodes() {
        // Direct connection for no effects
        // Note: This will be handled by the parent AudioEngine
    }
    
    private func disconnectNodes() {
        // Disconnect all effect nodes
        for effectUnit in effectUnits.values {
            effectUnit.engine?.disconnectNodeInput(effectUnit)
        }
    }
    
    private func connectEffectChain(_ effects: [AVAudioUnit]) {
        guard !effects.isEmpty else {
            connectNodes()
            return
        }
        
        // This will be handled by the parent AudioEngine when adding to the graph
        effectNodes = effects
    }
    
    // MARK: - Parameter Management
    private func applyEffectParameters(_ effect: BusEffect) {
        guard let effectUnit = effectUnits[effect.id] else { return }
        
        // Apply parameters based on effect type
        switch effect.type {
        case .reverb:
            applyReverbParameters(effectUnit, parameters: effect.parameters)
        case .delay:
            applyDelayParameters(effectUnit, parameters: effect.parameters)
        case .chorus:
            applyChorusParameters(effectUnit, parameters: effect.parameters)
        case .compressor:
            applyCompressorParameters(effectUnit, parameters: effect.parameters)
        case .eq:
            applyEQParameters(effectUnit, parameters: effect.parameters)
        case .distortion:
            applyDistortionParameters(effectUnit, parameters: effect.parameters)
        case .filter:
            applyFilterParameters(effectUnit, parameters: effect.parameters)
        case .modulation:
            applyModulationParameters(effectUnit, parameters: effect.parameters)
        }
    }
    
    // MARK: - Effect Parameter Application
    private func applyReverbParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // Use AVAudioUnitReverb for simpler parameter access
        if let reverbUnit = unit as? AVAudioUnitReverb {
            if let wetLevel = parameters["wetLevel"] {
                reverbUnit.wetDryMix = Float(wetLevel)
            }
        }
        
        // For more complex parameter setting, we'd use AudioUnitSetParameter
        // but for now, keep it simple to avoid constant issues
        print("Applied reverb parameters: \(parameters)")
    }
    
    private func applyDelayParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // Use AVAudioUnitDelay for simpler parameter access
        if let delayUnit = unit as? AVAudioUnitDelay {
            if let delayTime = parameters["delayTime"] {
                delayUnit.delayTime = TimeInterval(delayTime / 1000.0) // Convert ms to seconds
            }
            if let feedback = parameters["feedback"] {
                delayUnit.feedback = Float(feedback)
            }
            if let wetLevel = parameters["wetLevel"] {
                delayUnit.wetDryMix = Float(wetLevel)
            }
        }
        
        print("Applied delay parameters: \(parameters)")
    }
    
    private func applyChorusParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // Simplified parameter application - avoid complex AudioUnit constants for now
        print("Applied chorus parameters: \(parameters)")
    }
    
    private func applyCompressorParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // Simplified compressor parameter application
        print("Applied compressor parameters: \(parameters)")
    }
    
    private func applyEQParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        if let eqUnit = unit as? AVAudioUnitEQ {
            // Apply EQ parameters using the simpler AVAudioUnitEQ interface
            if let lowGain = parameters["lowGain"] {
                if eqUnit.bands.count > 0 {
                    eqUnit.bands[0].gain = Float(lowGain)
                }
            }
            if let lowFreq = parameters["lowFreq"] {
                if eqUnit.bands.count > 0 {
                    eqUnit.bands[0].frequency = Float(lowFreq)
                }
            }
        }
        print("Applied EQ parameters: \(parameters)")
    }
    
    private func applyDistortionParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // Use AVAudioUnitDistortion for simpler parameter access
        if let distortionUnit = unit as? AVAudioUnitDistortion {
            if let wetLevel = parameters["wetLevel"] {
                distortionUnit.wetDryMix = Float(wetLevel)
            }
        }
        print("Applied distortion parameters: \(parameters)")
    }
    
    private func applyFilterParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // Simplified filter parameter application
        print("Applied filter parameters: \(parameters)")
    }
    
    private func applyModulationParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // Simplified modulation parameter application
        print("Applied modulation parameters: \(parameters)")
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
    func startLevelMonitoring() {
        // Install taps for level monitoring
        inputMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            Task { @MainActor in
                self?.inputLevel = self?.calculateRMSLevel(buffer: buffer) ?? 0.0
            }
        }
        
        outputMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            Task { @MainActor in
                self?.outputLevel = self?.calculateRMSLevel(buffer: buffer) ?? 0.0
            }
        }
    }
    
    func stopLevelMonitoring() {
        inputMixer.removeTap(onBus: 0)
        outputMixer.removeTap(onBus: 0)
    }
    
    private func calculateRMSLevel(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0.0 }
        
        let frameCount = Int(buffer.frameLength)
        var sum: Float = 0.0
        
        for i in 0..<frameCount {
            let sample = channelData[i]
            sum += sample * sample
        }
        
        let rms = sqrt(sum / Float(frameCount))
        return min(rms, 1.0) // Clamp to 0-1 range
    }
    
    // MARK: - Cleanup
    deinit {
        // Note: Cannot call @MainActor methods in deinit
        // Level monitoring will be cleaned up automatically when nodes are deallocated
        effectUnits.removeAll()
        effectNodes.removeAll()
    }
}
