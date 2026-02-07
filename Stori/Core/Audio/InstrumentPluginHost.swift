//
//  InstrumentPluginHost.swift
//  Stori
//
//  Hosts an Audio Unit instrument plugin (synths, samplers, drum machines)
//  Provides MIDI input and audio output integration with the DAW.
//

import Foundation
import AVFoundation
import AudioToolbox
import Combine
import AppKit
import Observation

/// Hosts an Audio Unit instrument plugin
// PERFORMANCE: Using @Observable for fine-grained SwiftUI updates
@Observable
@MainActor
class InstrumentPluginHost {
    
    // MARK: - Observable Properties
    
    @ObservationIgnored
    let pluginInstance: PluginInstance
    
    private(set) var isLoaded: Bool = false
    private(set) var isActive: Bool = false
    
    /// Currently held notes for activity indicator
    @ObservationIgnored
    private var heldNotes: Set<UInt8> = []
    
    @ObservationIgnored
    private var midiBlock: AUScheduleMIDIEventBlock?
    
    /// Public accessor for MIDI event block (thread-safe, can be called from any thread)
    /// Used for sample-accurate MIDI scheduling
    var midiEventBlock: AUScheduleMIDIEventBlock? { midiBlock }
    
    @ObservationIgnored
    private var renderBlock: AURenderBlock?
    
    @ObservationIgnored
    private var audioEngine: AVAudioEngine?
    
    @ObservationIgnored
    private var volume: Float = 0.8
    
    // MARK: - Initialization
    
    init(descriptor: PluginDescriptor) {
        precondition(descriptor.category == .instrument, "InstrumentPluginHost requires an instrument plugin")
        self.pluginInstance = PluginInstance(descriptor: descriptor)
    }
    
    /// Create from an existing PluginInstance
    init(pluginInstance: PluginInstance) {
        precondition(pluginInstance.descriptor.category == .instrument, "InstrumentPluginHost requires an instrument plugin")
        self.pluginInstance = pluginInstance
    }
    
    // MARK: - Lifecycle
    
    /// Load the instrument plugin and prepare for playback
    /// - Parameters:
    ///   - forStandalonePlayback: If true, creates its own AVAudioEngine for standalone playback (synth panel).
    ///                           If false, just instantiates the AU for use in the main DAW engine.
    ///   - sampleRate: Sample rate for standalone playback
    ///   - maxFrames: Max frames for audio buffer
    func load(forStandalonePlayback: Bool = true, sampleRate: Double = 48000, maxFrames: AVAudioFrameCount = 512) async throws {
        // Load the underlying plugin instance with the specified sample rate
        try await pluginInstance.load(sampleRate: sampleRate)
        
        guard let avAudioUnit = pluginInstance.avAudioUnit,
              let au = pluginInstance.auAudioUnit else {
            throw PluginError.instantiationFailed
        }
        
        // Get the MIDI scheduling block (needed for both modes)
        midiBlock = au.scheduleMIDIEventBlock
        renderBlock = au.renderBlock
        
        if forStandalonePlayback {
            // Create audio engine for standalone playback (synth panel, etc.)
            let engine = AVAudioEngine()
            self.audioEngine = engine
            
            // Attach the AU to the engine
            engine.attach(avAudioUnit)
            
            // Connect AU output to main mixer
            let format = avAudioUnit.outputFormat(forBus: 0)
            engine.connect(avAudioUnit, to: engine.mainMixerNode, format: format)
            
            // Set initial volume
            engine.mainMixerNode.outputVolume = volume
            
            // Start the audio engine
            try engine.start()
        }
        // For DAW integration: don't create our own engine
        // The caller (AudioEngine) will attach to the main DAW engine
        
        isLoaded = true
    }
    
    /// Unload the instrument
    func unload() {
        allNotesOff()
        
        // Stop and cleanup audio engine
        audioEngine?.stop()
        if let avAudioUnit = pluginInstance.avAudioUnit {
            audioEngine?.disconnectNodeOutput(avAudioUnit)
            audioEngine?.detach(avAudioUnit)
        }
        audioEngine = nil
        
        pluginInstance.unload()
        midiBlock = nil
        renderBlock = nil
        isLoaded = false
        isActive = false
    }
    
    // MARK: - MIDI Event Scheduling
    
    /// Send raw MIDI data to the instrument
    func sendMIDI(status: UInt8, data1: UInt8, data2: UInt8, atSampleTime sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        guard let midiBlock = midiBlock else { return }
        
        var midiData: [UInt8] = [status, data1, data2]
        midiBlock(sampleTime, 0, 3, &midiData)
    }
    
    /// Send Note On event
    func noteOn(pitch: UInt8, velocity: UInt8, channel: UInt8 = 0, atSampleTime sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        let status: UInt8 = 0x90 | (channel & 0x0F)
        sendMIDI(status: status, data1: pitch, data2: velocity, atSampleTime: sampleTime)
        
        heldNotes.insert(pitch)
        isActive = true
    }
    
    /// Send Note Off event
    func noteOff(pitch: UInt8, velocity: UInt8 = 0, channel: UInt8 = 0, atSampleTime sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        let status: UInt8 = 0x80 | (channel & 0x0F)
        sendMIDI(status: status, data1: pitch, data2: velocity, atSampleTime: sampleTime)
        
        heldNotes.remove(pitch)
        isActive = !heldNotes.isEmpty
    }
    
    /// Send Control Change (CC) event
    func controlChange(controller: UInt8, value: UInt8, channel: UInt8 = 0, atSampleTime sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        let status: UInt8 = 0xB0 | (channel & 0x0F)
        sendMIDI(status: status, data1: controller, data2: value, atSampleTime: sampleTime)
    }
    
    /// Send Pitch Bend event (14-bit value: 0-16383, center is 8192)
    func pitchBend(value: UInt16, channel: UInt8 = 0, atSampleTime sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        let status: UInt8 = 0xE0 | (channel & 0x0F)
        let lsb = UInt8(value & 0x7F)
        let msb = UInt8((value >> 7) & 0x7F)
        sendMIDI(status: status, data1: lsb, data2: msb, atSampleTime: sampleTime)
    }
    
    /// Send Program Change
    func programChange(program: UInt8, channel: UInt8 = 0, atSampleTime sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        let status: UInt8 = 0xC0 | (channel & 0x0F)
        guard let midiBlock = midiBlock else { return }
        var midiData: [UInt8] = [status, program]
        midiBlock(sampleTime, 0, 2, &midiData)
    }
    
    /// Send Channel Aftertouch
    func channelAftertouch(pressure: UInt8, channel: UInt8 = 0, atSampleTime sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        let status: UInt8 = 0xD0 | (channel & 0x0F)
        guard let midiBlock = midiBlock else { return }
        var midiData: [UInt8] = [status, pressure]
        midiBlock(sampleTime, 0, 2, &midiData)
    }
    
    /// Send Poly Aftertouch (per-note pressure)
    func polyAftertouch(note: UInt8, pressure: UInt8, channel: UInt8 = 0, atSampleTime sampleTime: AUEventSampleTime = AUEventSampleTimeImmediate) {
        let status: UInt8 = 0xA0 | (channel & 0x0F)
        sendMIDI(status: status, data1: note, data2: pressure, atSampleTime: sampleTime)
    }
    
    // MARK: - Note Control
    
    /// Stop all currently playing notes
    func allNotesOff(channel: UInt8 = 0) {
        // Send All Notes Off (CC 123)
        controlChange(controller: 123, value: 0, channel: channel)
        
        // Also send individual note offs for any held notes
        for pitch in heldNotes {
            noteOff(pitch: pitch, channel: channel)
        }
        
        heldNotes.removeAll()
        isActive = false
    }
    
    /// Panic - stop all sounds immediately
    func panic() {
        // All Sound Off (CC 120)
        controlChange(controller: 120, value: 0)
        // All Notes Off (CC 123)
        controlChange(controller: 123, value: 0)
        // Reset All Controllers (CC 121)
        controlChange(controller: 121, value: 0)
        
        heldNotes.removeAll()
        isActive = false
    }
    
    // MARK: - Audio Node Access
    
    /// Get the AVAudioUnit node for connecting to the audio graph
    var audioNode: AVAudioUnit? {
        return pluginInstance.avAudioUnit
    }
    
    // MARK: - Volume Control
    
    /// Set the output volume (0.0 - 1.0)
    func setVolume(_ newVolume: Float) {
        volume = max(0.0, min(1.0, newVolume))
        audioEngine?.mainMixerNode.outputVolume = volume
    }
    
    /// Get the current volume
    func getVolume() -> Float {
        return volume
    }
    
    // MARK: - UI Access
    
    /// Request the plugin's custom view controller for UI hosting
    func requestViewController() async -> NSViewController? {
        return await pluginInstance.requestViewController()
    }
    
    /// Get the plugin descriptor for display purposes
    var descriptor: PluginDescriptor {
        return pluginInstance.descriptor
    }
    
    /// Get the plugin name
    var name: String {
        return pluginInstance.descriptor.name
    }
    
    /// Get the plugin manufacturer
    var manufacturer: String {
        return pluginInstance.descriptor.manufacturer
    }
    
    // MARK: - Cleanup
    
    // No async resources owned.
    // No deinit required.
}

// MARK: - InstrumentPluginHost Manager

/// Manages all loaded instrument plugin hosts
@MainActor
class InstrumentPluginHostManager {
    static let shared = InstrumentPluginHostManager()
    
    private var hosts: [UUID: InstrumentPluginHost] = [:]
    
    private init() {}
    
    /// Get or create a host for a track
    func getHost(for trackId: UUID) -> InstrumentPluginHost? {
        return hosts[trackId]
    }
    
    /// Create a new host for a track with the given plugin descriptor
    func createHost(for trackId: UUID, descriptor: PluginDescriptor) async throws -> InstrumentPluginHost {
        // Remove existing host if any
        removeHost(for: trackId)
        
        // Create and load new host
        let host = InstrumentPluginHost(descriptor: descriptor)
        try await host.load()
        
        hosts[trackId] = host
        return host
    }
    
    /// Remove the host for a track
    func removeHost(for trackId: UUID) {
        if let host = hosts[trackId] {
            host.unload()
            hosts.removeValue(forKey: trackId)
        }
    }
    
    /// Stop all notes on all hosts
    func allNotesOff() {
        for host in hosts.values {
            host.allNotesOff()
        }
    }
    
    /// Panic all hosts
    func panicAll() {
        for host in hosts.values {
            host.panic()
        }
    }
    
    // CRITICAL: Protective deinit for @MainActor class (ASan Issue #84742+)
    // Root cause: @MainActor creates implicit actor isolation task-local storage
    deinit {
    }
}
