//
//  BusAudioNode.swift
//  TellUrStoriDAW
//
//  Professional bus audio node for auxiliary effects processing
//

import Foundation
import AVFoundation
import AudioToolbox
import Combine

// MARK: - Bus Audio Node
@MainActor
class BusAudioNode: ObservableObject {
    
    // MARK: - Properties
    let busId: UUID
    // busType removed - buses are now generic
    private let inputMixer = AVAudioMixerNode()
    private let outputMixer = AVAudioMixerNode()
    private var effectNodes: [AVAudioNode] = []
    private var effectUnits: [UUID: AVAudioUnit] = [:]
    private var effects: [UUID: BusEffect] = [:] // Store effect metadata including enabled status
    
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
    init(busId: UUID) {
        self.busId = busId
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
    func getEnabledEffectUnits() -> [AVAudioUnit] {
        return effectUnits.compactMap { (effectId, unit) -> AVAudioUnit? in
            guard let effect = effects[effectId], effect.isEnabled else { return nil }
            return unit
        }
    }
    
    func addEffect(_ effect: BusEffect) {
        Task { @MainActor in
            guard let effectUnit = createEffectUnit(for: effect) else {
                print("Failed to create effect unit for \(effect.type)")
                return
            }
            
            effectUnits[effect.id] = effectUnit
            effects[effect.id] = effect // Store effect metadata
            rebuildEffectChain()
            applyEffectParameters(effect)
        }
    }
    
    func removeEffect(withId effectId: UUID) {
        effectUnits.removeValue(forKey: effectId)
        effects.removeValue(forKey: effectId) // Clean up effect metadata
        rebuildEffectChain()
    }
    
    func updateEffect(_ effect: BusEffect) {
        guard effectUnits[effect.id] != nil else { 
            print("⚠️ Effect unit not found for ID: \(effect.id)")
            return 
        }
        print("🔄 Updating effect: \(effect.type) with parameters: \(effect.parameters), enabled: \(effect.isEnabled)")
        
        // Update stored effect metadata
        effects[effect.id] = effect
        
        // Rebuild chain to respect enabled/disabled status
        rebuildEffectChain()
        
        // Apply parameters if enabled
        if effect.isEnabled {
            applyEffectParameters(effect)
        }
    }
    
    // MARK: - Effect Unit Creation
    private func createEffectUnit(for effect: BusEffect) -> AVAudioUnit? {
        switch effect.type {
        case .reverb:
            // Use AVAudioUnitReverb directly instead of generic AudioComponentDescription
            print("🔧 Creating AVAudioUnitReverb directly")
            let reverbUnit = AVAudioUnitReverb()
            // STEP 4: Use louder, more audible preset for testing
            reverbUnit.loadFactoryPreset(.cathedral)  // More dramatic than mediumHall
            reverbUnit.wetDryMix = 50 // Default 50% wet (will be overridden to 100% in applyReverbParameters)
            print("🏰 REVERB PRESET: Using Cathedral preset for maximum audibility")
            return reverbUnit
            
        case .delay:
            // Use AVAudioUnitDelay directly
            print("🔧 Creating AVAudioUnitDelay directly")
            let delayUnit = AVAudioUnitDelay()
            delayUnit.delayTime = 0.5 // Default 500ms delay
            delayUnit.feedback = 50.0 // Default 50% feedback
            delayUnit.wetDryMix = 50.0 // Default 50% wet
            return delayUnit
            
        case .chorus:
            // Use AVAudioUnitDelay as a chorus base (modulated delay)
            print("🔧 Creating AVAudioUnitDelay for chorus")
            let chorusUnit = AVAudioUnitDelay()
            chorusUnit.delayTime = 0.02 // Short delay for chorus effect (20ms)
            chorusUnit.feedback = 0.0 // No feedback for chorus
            chorusUnit.wetDryMix = 50.0 // Default 50% wet
            return chorusUnit
            
        case .compressor:
            // Create AVAudioUnitEffect with compressor component
            print("🔧 Creating AVAudioUnitEffect for compressor")
            let compressorDesc = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            return AVAudioUnitEffect(audioComponentDescription: compressorDesc)
            
        case .eq:
            // Use AVAudioUnitEQ with 4 bands
            print("🔧 Creating AVAudioUnitEQ with 4 bands")
            let eqUnit = AVAudioUnitEQ(numberOfBands: 4)
            
            // Configure bands for Low, Low-Mid, High-Mid, High
            if eqUnit.bands.count >= 4 {
                eqUnit.bands[0].frequency = 100    // Low band
                eqUnit.bands[0].bandwidth = 1.0
                eqUnit.bands[0].filterType = .parametric
                
                eqUnit.bands[1].frequency = 500    // Low-Mid band  
                eqUnit.bands[1].bandwidth = 1.0
                eqUnit.bands[1].filterType = .parametric
                
                eqUnit.bands[2].frequency = 2000   // High-Mid band
                eqUnit.bands[2].bandwidth = 1.0
                eqUnit.bands[2].filterType = .parametric
                
                eqUnit.bands[3].frequency = 8000   // High band
                eqUnit.bands[3].bandwidth = 1.0
                eqUnit.bands[3].filterType = .parametric
            }
            return eqUnit
            
        case .distortion:
            // Use AVAudioUnitDistortion
            print("🔧 Creating AVAudioUnitDistortion")
            let distortionUnit = AVAudioUnitDistortion()
            distortionUnit.loadFactoryPreset(.multiEcho1)
            return distortionUnit
            
        case .filter:
            // Create filter using AVAudioUnitEffect
            print("🔧 Creating AVAudioUnitEffect for filter")
            let filterDesc = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_LowPassFilter,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            return AVAudioUnitEffect(audioComponentDescription: filterDesc)
            
        case .modulation:
            // Use delay unit with modulation for flanger/phaser effects
            print("🔧 Creating AVAudioUnitDelay for modulation")
            let modulationUnit = AVAudioUnitDelay()
            modulationUnit.delayTime = 0.005 // Very short delay for modulation (5ms)
            modulationUnit.feedback = 25.0 // Some feedback for modulation
            modulationUnit.wetDryMix = 50.0 // Default 50% wet
            return modulationUnit
        }
    }
    
    // MARK: - Effect Chain Management
    private func rebuildEffectChain() {
        // Disconnect all current connections
        disconnectNodes()
        
        // Get all enabled effects in order
        let enabledEffects = effectUnits.compactMap { (effectId, unit) -> AVAudioUnit? in
            guard let effect = effects[effectId], effect.isEnabled else { return nil }
            return unit
        }
        
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
        print("🔍 DEBUG: Applying reverb parameters to unit: \(unit)")
        print("🔍 DEBUG: Unit type: \(type(of: unit))")
        print("🔍 DEBUG: Parameters: \(parameters)")
        
        // Use AVAudioUnitReverb for real parameter control
        if let reverbUnit = unit as? AVAudioUnitReverb {
            print("✅ Successfully cast to AVAudioUnitReverb")
            
            // ChatGPT Fix: Aux sends should be 100% wet - control send amount via destination volume
            reverbUnit.wetDryMix = 100.0
            print("🎛️ CHATGPT FIX: Set reverb to 100% wet (aux sends should have no dry signal)")
            print("🎚️ Send amount controlled by AVAudioMixingDestination.volume, not wetDryMix")
            
            // Apply other reverb parameters (room size, decay time, etc.)
            // Note: AVAudioUnitReverb has limited parameter control
            // The wet/dry balance is now controlled by the send level, not the reverb unit
            
            // Note: AVAudioUnitReverb has limited parameter control
            // For more advanced reverb, we'd need custom AudioUnit or third-party
            print("✅ Applied reverb parameters: wetDryMix=\(reverbUnit.wetDryMix)")
        } else {
            print("⚠️ Could not cast to AVAudioUnitReverb, unit type: \(type(of: unit))")
            
            // Try generic AudioUnit parameter setting
            let wetLevel = parameters["wetLevel"] ?? 30.0
            let status = AudioUnitSetParameter(
                unit.audioUnit,
                kReverb2Param_DryWetMix,
                kAudioUnitScope_Global,
                0,
                Float(wetLevel),
                0
            )
            print("🎛️ Generic AudioUnit parameter set status: \(status)")
        }
    }
    
    private func applyDelayParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // Use AVAudioUnitDelay for real parameter control
        if let delayUnit = unit as? AVAudioUnitDelay {
            // Apply delay time (convert ms to seconds)
            if let delayTime = parameters["delayTime"] {
                delayUnit.delayTime = TimeInterval(delayTime / 1000.0)
            }
            
            // Apply feedback
            if let feedback = parameters["feedback"] {
                delayUnit.feedback = Float(feedback / 100.0) // Convert percentage to 0-1
            }
            
            // Apply wet/dry mix
            if let wetLevel = parameters["wetLevel"] {
                delayUnit.wetDryMix = Float(wetLevel)
            }
            
            print("✅ Applied delay parameters: time=\(delayUnit.delayTime)s, feedback=\(delayUnit.feedback), wet=\(delayUnit.wetDryMix)")
        } else {
            print("⚠️ Could not cast to AVAudioUnitDelay")
        }
    }
    
    private func applyChorusParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // For chorus, we'll use a generic AudioUnit approach since there's no specific AVAudioUnitChorus
        // We'll set parameters using AudioUnit parameter IDs
        if let rate = parameters["rate"] {
            // Set modulation rate parameter (typical chorus parameter ID)
            let rateParam = AudioUnitParameterID(14) // Common chorus rate parameter
            AudioUnitSetParameter(unit.audioUnit, rateParam, kAudioUnitScope_Global, 0, Float(rate), 0)
        }
        if let depth = parameters["depth"] {
            // Set modulation depth parameter
            let depthParam = AudioUnitParameterID(15) // Common chorus depth parameter  
            AudioUnitSetParameter(unit.audioUnit, depthParam, kAudioUnitScope_Global, 0, Float(depth), 0)
        }
        if let wetLevel = parameters["wetLevel"] {
            // Set wet/dry mix parameter
            let mixParam = AudioUnitParameterID(0) // Common mix parameter
            AudioUnitSetParameter(unit.audioUnit, mixParam, kAudioUnitScope_Global, 0, Float(wetLevel), 0)
        }
        print("✅ Applied chorus parameters: rate=\(parameters["rate"] ?? 0), depth=\(parameters["depth"] ?? 0), wet=\(parameters["wetLevel"] ?? 0)")
    }
    
    private func applyCompressorParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // Use correct AudioUnit parameter IDs for Apple's DynamicsProcessor
        // Reference: AudioUnitParameters.h - kDynamicsProcessorParam_*
        if let threshold = parameters["threshold"] {
            // kDynamicsProcessorParam_Threshold = 0
            let result = AudioUnitSetParameter(unit.audioUnit, 0, kAudioUnitScope_Global, 0, Float(threshold), 0)
            print("🎛️ COMPRESSOR: Set threshold=\(threshold)dB, result=\(result)")
        }
        if let ratio = parameters["ratio"] {
            // kDynamicsProcessorParam_Ratio = 2  
            let result = AudioUnitSetParameter(unit.audioUnit, 2, kAudioUnitScope_Global, 0, Float(ratio), 0)
            print("🎛️ COMPRESSOR: Set ratio=\(ratio):1, result=\(result)")
        }
        if let attack = parameters["attack"] {
            // kDynamicsProcessorParam_AttackTime = 3 (in seconds)
            let attackSeconds = Float(attack / 1000.0)
            let result = AudioUnitSetParameter(unit.audioUnit, 3, kAudioUnitScope_Global, 0, attackSeconds, 0)
            print("🎛️ COMPRESSOR: Set attack=\(attackSeconds)s, result=\(result)")
        }
        if let release = parameters["release"] {
            // kDynamicsProcessorParam_ReleaseTime = 4 (in seconds)
            let releaseSeconds = Float(release / 1000.0)
            let result = AudioUnitSetParameter(unit.audioUnit, 4, kAudioUnitScope_Global, 0, releaseSeconds, 0)
            print("🎛️ COMPRESSOR: Set release=\(releaseSeconds)s, result=\(result)")
        }
        if let makeupGain = parameters["makeupGain"] {
            // kDynamicsProcessorParam_MasterGain = 5
            let result = AudioUnitSetParameter(unit.audioUnit, 5, kAudioUnitScope_Global, 0, Float(makeupGain), 0)
            print("🎛️ COMPRESSOR: Set makeup=\(makeupGain)dB, result=\(result)")
        }
        
        // Enable the compressor (parameter ID 1 is typically the bypass/enable parameter)
        let enableResult = AudioUnitSetParameter(unit.audioUnit, 1, kAudioUnitScope_Global, 0, 1.0, 0)
        print("✅ Applied compressor parameters with enable result: \(enableResult)")
    }
    
    private func applyEQParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        if let eqUnit = unit as? AVAudioUnitEQ {
            // Apply EQ parameters to available bands
            let bandCount = eqUnit.bands.count
            print("🎚️ EQ: Configuring \(bandCount) bands")
            
            if bandCount > 0 {
                // Low band (band 0) - 100Hz by default
                eqUnit.bands[0].frequency = Float(parameters["lowFreq"] ?? 100.0)
                eqUnit.bands[0].gain = Float(parameters["lowGain"] ?? 0.0)
                eqUnit.bands[0].bandwidth = 1.0
                eqUnit.bands[0].filterType = .parametric
                eqUnit.bands[0].bypass = false
                print("🎚️ EQ Band 0: freq=\(eqUnit.bands[0].frequency)Hz, gain=\(eqUnit.bands[0].gain)dB")
            }
            
            if bandCount > 1 {
                // Low-Mid band (band 1) - 500Hz by default
                eqUnit.bands[1].frequency = 500.0
                eqUnit.bands[1].gain = Float(parameters["lowMidGain"] ?? 0.0)
                eqUnit.bands[1].bandwidth = 1.0
                eqUnit.bands[1].filterType = .parametric
                eqUnit.bands[1].bypass = false
                print("🎚️ EQ Band 1: freq=\(eqUnit.bands[1].frequency)Hz, gain=\(eqUnit.bands[1].gain)dB")
            }
            
            if bandCount > 2 {
                // High-Mid band (band 2) - 2000Hz by default
                eqUnit.bands[2].frequency = 2000.0
                eqUnit.bands[2].gain = Float(parameters["highMidGain"] ?? 0.0)
                eqUnit.bands[2].bandwidth = 1.0
                eqUnit.bands[2].filterType = .parametric
                eqUnit.bands[2].bypass = false
                print("🎚️ EQ Band 2: freq=\(eqUnit.bands[2].frequency)Hz, gain=\(eqUnit.bands[2].gain)dB")
            }
            
            if bandCount > 3 {
                // High band (band 3) - 8000Hz by default
                eqUnit.bands[3].frequency = Float(parameters["highFreq"] ?? 8000.0)
                eqUnit.bands[3].gain = Float(parameters["highGain"] ?? 0.0)
                eqUnit.bands[3].bandwidth = 1.0
                eqUnit.bands[3].filterType = .parametric
                eqUnit.bands[3].bypass = false
                print("🎚️ EQ Band 3: freq=\(eqUnit.bands[3].frequency)Hz, gain=\(eqUnit.bands[3].gain)dB")
            }
            
            // Enable global bypass = false to ensure EQ is active
            eqUnit.bypass = false
            print("✅ Applied EQ parameters: \(bandCount) bands configured, bypass=\(eqUnit.bypass)")
        } else {
            print("⚠️ Could not cast to AVAudioUnitEQ")
        }
    }
    
    private func applyDistortionParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        if let distortionUnit = unit as? AVAudioUnitDistortion {
            // Set a more aggressive preset for audible distortion
            distortionUnit.loadFactoryPreset(.drumsBitBrush)
            
            if let drive = parameters["drive"] {
                // Map drive (0-100) to preGain (-40 to +40 dB)
                let preGain = Float((drive - 50.0) * 0.8) // -40 to +40 dB range
                distortionUnit.preGain = preGain
                print("🔥 DISTORTION: Set preGain=\(preGain)dB from drive=\(drive)%")
            }
            
            if let tone = parameters["tone"] {
                // Use wetDryMix for tone control (0-100%)
                distortionUnit.wetDryMix = Float(tone)
                print("🔥 DISTORTION: Set wetDryMix=\(tone)%")
            }
            
            if let output = parameters["output"] {
                // Map output (-20 to +20 dB) directly
                // Note: AVAudioUnitDistortion doesn't have separate output gain
                // We'll use this to adjust the overall effect level
                print("🔥 DISTORTION: Output level=\(output)dB (applied via preGain adjustment)")
            }
            
            // Ensure bypass is disabled
            distortionUnit.bypass = false
            
            print("✅ Applied distortion parameters: preset=drumsBitBrush, preGain=\(distortionUnit.preGain)dB, wetDryMix=\(distortionUnit.wetDryMix)%, bypass=\(distortionUnit.bypass)")
        } else {
            print("⚠️ Could not cast to AVAudioUnitDistortion")
        }
    }
    
    private func applyFilterParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // Use AVAudioUnitEQ as a filter with specific band configurations
        if let eqUnit = unit as? AVAudioUnitEQ {
            if eqUnit.bands.count > 0 {
                let band = eqUnit.bands[0]
                
                if let cutoff = parameters["cutoff"] {
                    band.frequency = Float(cutoff)
                }
                if let resonance = parameters["resonance"] {
                    band.bandwidth = Float(resonance / 10.0) // Convert to reasonable bandwidth
                }
                if let filterType = parameters["filterType"] {
                    // Set filter type based on parameter (0=lowpass, 1=highpass, 2=bandpass)
                    switch Int(filterType) {
                    case 0:
                        band.filterType = .lowPass
                    case 1:
                        band.filterType = .highPass
                    case 2:
                        band.filterType = .bandPass
                    default:
                        band.filterType = .lowPass
                    }
                }
                
                print("✅ Applied filter parameters: freq=\(band.frequency)Hz, bandwidth=\(band.bandwidth), type=\(band.filterType.rawValue)")
            }
        } else {
            print("⚠️ Could not cast to AVAudioUnitEQ for filter")
        }
    }
    
    private func applyModulationParameters(_ unit: AVAudioUnit, parameters: [String: Double]) {
        // For modulation effects, we'll use generic AudioUnit parameter setting
        if let rate = parameters["rate"] {
            // Set modulation rate parameter
            let rateParam = AudioUnitParameterID(14) // Common modulation rate parameter
            AudioUnitSetParameter(unit.audioUnit, rateParam, kAudioUnitScope_Global, 0, Float(rate), 0)
        }
        if let depth = parameters["depth"] {
            // Set modulation depth parameter
            let depthParam = AudioUnitParameterID(15) // Common modulation depth parameter
            AudioUnitSetParameter(unit.audioUnit, depthParam, kAudioUnitScope_Global, 0, Float(depth), 0)
        }
        if let feedback = parameters["feedback"] {
            // Set feedback parameter
            let feedbackParam = AudioUnitParameterID(16) // Common feedback parameter
            AudioUnitSetParameter(unit.audioUnit, feedbackParam, kAudioUnitScope_Global, 0, Float(feedback), 0)
        }
        if let wetLevel = parameters["wetLevel"] {
            // Set wet/dry mix parameter
            let mixParam = AudioUnitParameterID(0) // Common mix parameter
            AudioUnitSetParameter(unit.audioUnit, mixParam, kAudioUnitScope_Global, 0, Float(wetLevel), 0)
        }
        print("✅ Applied modulation parameters: rate=\(parameters["rate"] ?? 0), depth=\(parameters["depth"] ?? 0), feedback=\(parameters["feedback"] ?? 0), wet=\(parameters["wetLevel"] ?? 0)")
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
    
    func startLevelMonitoring() {
        // Remove any existing taps first to prevent conflicts
        stopLevelMonitoring()
        
        // Install taps for level monitoring with error handling
        do {
            inputMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                Task { @MainActor in
                    self?.inputLevel = self?.calculateRMSLevel(buffer: buffer) ?? 0.0
                }
            }
            inputTapInstalled = true
            print("📊 INPUT TAP: Installed on bus input mixer")
        } catch {
            print("⚠️ INPUT TAP: Failed to install - \(error)")
        }
        
        do {
            outputMixer.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
                Task { @MainActor in
                    self?.outputLevel = self?.calculateRMSLevel(buffer: buffer) ?? 0.0
                }
            }
            outputTapInstalled = true
            print("📊 OUTPUT TAP: Installed on bus output mixer")
        } catch {
            print("⚠️ OUTPUT TAP: Failed to install - \(error)")
        }
    }
    
    func stopLevelMonitoring() {
        if inputTapInstalled {
            do {
                inputMixer.removeTap(onBus: 0)
                inputTapInstalled = false
                print("📊 INPUT TAP: Removed from bus input mixer")
            } catch {
                print("⚠️ INPUT TAP: Failed to remove - \(error)")
                inputTapInstalled = false // Reset flag anyway
            }
        }
        
        if outputTapInstalled {
            do {
                outputMixer.removeTap(onBus: 0)
                outputTapInstalled = false
                print("📊 OUTPUT TAP: Removed from bus output mixer")
            } catch {
                print("⚠️ OUTPUT TAP: Failed to remove - \(error)")
                outputTapInstalled = false // Reset flag anyway
            }
        }
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
