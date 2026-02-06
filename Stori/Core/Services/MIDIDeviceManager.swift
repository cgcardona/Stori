//
//  MIDIDeviceManager.swift
//  Stori
//
//  Created by TellUrStori on 12/18/25.
//
//  CoreMIDI integration for device discovery, connection management,
//  and real-time MIDI input/output handling.
//

import Foundation
import CoreMIDI
import SwiftUI

// MARK: - MIDIDevice

/// Represents a connected MIDI device (input or output).
struct MIDIDevice: Identifiable, Equatable, Hashable {
    let id: MIDIEndpointRef
    let name: String
    let manufacturer: String
    let isInput: Bool
    let isOnline: Bool
    
    static func == (lhs: MIDIDevice, rhs: MIDIDevice) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - MIDIDeviceManager

/// Manages MIDI device discovery, connection, and message routing.
@MainActor
@Observable
class MIDIDeviceManager {
    
    // MARK: - Properties
    
    /// Available MIDI input devices
    var availableInputs: [MIDIDevice] = []
    
    /// Available MIDI output devices
    var availableOutputs: [MIDIDevice] = []
    
    /// Currently connected input devices
    var connectedInputs: Set<MIDIEndpointRef> = []
    
    /// Is the MIDI system initialized
    var isInitialized = false
    
    /// Last error message
    var lastError: String?
    
    // MARK: - Callbacks
    
    /// Called when a Note On is received (pitch, velocity, channel)
    var onNoteOn: ((UInt8, UInt8, UInt8) -> Void)?
    
    /// Called when a Note Off is received (pitch, channel)
    var onNoteOff: ((UInt8, UInt8) -> Void)?
    
    /// Called when a Control Change is received (cc, value, channel)
    var onControlChange: ((UInt8, UInt8, UInt8) -> Void)?
    
    /// Called when Pitch Bend is received (value, channel)
    var onPitchBend: ((Int16, UInt8) -> Void)?
    
    /// Called when Program Change is received (program, channel)
    var onProgramChange: ((UInt8, UInt8) -> Void)?
    
    /// Called when any MIDI message is received (for logging/display)
    var onMIDIMessage: ((String) -> Void)?
    
    // MARK: - Private Properties
    
    private var midiClient: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private var outputPort: MIDIPortRef = 0
    private var virtualSource: MIDIEndpointRef = 0
    private var virtualDestination: MIDIEndpointRef = 0
    
    // MARK: - Initialization
    
    init() {
        setupMIDI()
    }
    
    deinit {
        Task { @MainActor in
            teardownMIDI()
        }
    }
    
    // MARK: - Setup
    
    /// Initialize the MIDI client and ports
    private func setupMIDI() {
        var status: OSStatus
        
        // Create MIDI client
        status = MIDIClientCreateWithBlock("Stori" as CFString, &midiClient) { [weak self] notification in
            Task { @MainActor in
                self?.handleMIDINotification(notification)
            }
        }
        
        guard status == noErr else {
            lastError = "Failed to create MIDI client: \(status)"
            return
        }
        
        // Create input port with protocol (MIDI 1.0)
        status = MIDIInputPortCreateWithProtocol(
            midiClient,
            "Stori Input" as CFString,
            ._1_0,
            &inputPort
        ) { [weak self] eventList, srcConnRefCon in
            // This is called on a MIDI thread, dispatch to main actor
            let eventListCopy = eventList.pointee
            Task { @MainActor in
                self?.processMIDIEventList(eventListCopy)
            }
        }
        
        guard status == noErr else {
            lastError = "Failed to create MIDI input port: \(status)"
            return
        }
        
        // Create output port
        status = MIDIOutputPortCreate(
            midiClient,
            "Stori Output" as CFString,
            &outputPort
        )
        
        guard status == noErr else {
            lastError = "Failed to create MIDI output port: \(status)"
            return
        }
        
        isInitialized = true
        
        // Scan for devices
        scanDevices()
    }
    
    /// Clean up MIDI resources
    private func teardownMIDI() {
        // Disconnect all inputs
        for input in connectedInputs {
            MIDIPortDisconnectSource(inputPort, input)
        }
        connectedInputs.removeAll()
        
        // Dispose of virtual endpoints
        if virtualSource != 0 {
            MIDIEndpointDispose(virtualSource)
        }
        if virtualDestination != 0 {
            MIDIEndpointDispose(virtualDestination)
        }
        
        // Dispose of client (also disposes ports)
        if midiClient != 0 {
            MIDIClientDispose(midiClient)
        }
        
        isInitialized = false
    }
    
    // MARK: - Device Discovery
    
    /// Scan for all available MIDI devices
    func scanDevices() {
        availableInputs = []
        availableOutputs = []
        
        // Scan MIDI sources (inputs)
        let sourceCount = MIDIGetNumberOfSources()
        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            if let device = createDevice(from: source, isInput: true) {
                availableInputs.append(device)
            }
        }
        
        // Scan MIDI destinations (outputs)
        let destCount = MIDIGetNumberOfDestinations()
        for i in 0..<destCount {
            let dest = MIDIGetDestination(i)
            if let device = createDevice(from: dest, isInput: false) {
                availableOutputs.append(device)
            }
        }
        
    }
    
    /// Create a MIDIDevice from an endpoint
    private func createDevice(from endpoint: MIDIEndpointRef, isInput: Bool) -> MIDIDevice? {
        guard endpoint != 0 else { return nil }
        
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        let deviceName = (name?.takeRetainedValue() as String?) ?? "Unknown Device"
        
        var manufacturer: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyManufacturer, &manufacturer)
        let mfr = (manufacturer?.takeRetainedValue() as String?) ?? "Unknown"
        
        var isOffline: Int32 = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyOffline, &isOffline)
        
        return MIDIDevice(
            id: endpoint,
            name: deviceName,
            manufacturer: mfr,
            isInput: isInput,
            isOnline: isOffline == 0
        )
    }
    
    // MARK: - Connection Management
    
    /// Connect to a MIDI input device
    func connect(to input: MIDIEndpointRef) {
        guard isInitialized else {
            return
        }
        
        let status = MIDIPortConnectSource(inputPort, input, nil)
        if status == noErr {
            connectedInputs.insert(input)
        } else {
        }
    }
    
    /// Connect to a MIDI input device by device struct
    func connect(to device: MIDIDevice) {
        guard device.isInput else {
            return
        }
        connect(to: device.id)
    }
    
    /// Disconnect from a MIDI input device
    func disconnect(from input: MIDIEndpointRef) {
        let status = MIDIPortDisconnectSource(inputPort, input)
        if status == noErr {
            connectedInputs.remove(input)
        } else {
        }
    }
    
    /// Disconnect from a MIDI input device by device struct
    func disconnect(from device: MIDIDevice) {
        disconnect(from: device.id)
    }
    
    /// Connect to all available MIDI inputs
    func connectToAllInputs() {
        for device in availableInputs where device.isOnline {
            connect(to: device.id)
        }
    }
    
    /// Disconnect from all MIDI inputs
    func disconnectFromAllInputs() {
        for input in connectedInputs {
            disconnect(from: input)
        }
    }
    
    /// Check if a device is connected
    func isConnected(_ device: MIDIDevice) -> Bool {
        connectedInputs.contains(device.id)
    }
    
    // MARK: - MIDI Output
    
    /// Send a Note On message
    func sendNoteOn(pitch: UInt8, velocity: UInt8, channel: UInt8, to destination: MIDIEndpointRef? = nil) {
        let message: [UInt8] = [
            MIDIHelper.noteOnStatus(channel: channel),
            pitch,
            velocity
        ]
        sendMIDIMessage(message, to: destination)
    }
    
    /// Send a Note Off message
    func sendNoteOff(pitch: UInt8, channel: UInt8, to destination: MIDIEndpointRef? = nil) {
        let message: [UInt8] = [
            MIDIHelper.noteOffStatus(channel: channel),
            pitch,
            0
        ]
        sendMIDIMessage(message, to: destination)
    }
    
    /// Send a Control Change message
    func sendControlChange(controller: UInt8, value: UInt8, channel: UInt8, to destination: MIDIEndpointRef? = nil) {
        let message: [UInt8] = [
            MIDIHelper.controlChangeStatus(channel: channel),
            controller,
            value
        ]
        sendMIDIMessage(message, to: destination)
    }
    
    /// Send a Pitch Bend message
    func sendPitchBend(value: Int16, channel: UInt8, to destination: MIDIEndpointRef? = nil) {
        // Convert to 14-bit value with center at 8192
        let bendValue = Int(value) + 8192
        let lsb = UInt8(bendValue & 0x7F)
        let msb = UInt8((bendValue >> 7) & 0x7F)
        
        let message: [UInt8] = [
            MIDIHelper.pitchBendStatus(channel: channel),
            lsb,
            msb
        ]
        sendMIDIMessage(message, to: destination)
    }
    
    /// Send an All Notes Off message
    func sendAllNotesOff(channel: UInt8, to destination: MIDIEndpointRef? = nil) {
        sendControlChange(controller: 123, value: 0, channel: channel, to: destination)
    }
    
    /// Send raw MIDI message
    private func sendMIDIMessage(_ message: [UInt8], to destination: MIDIEndpointRef?) {
        guard isInitialized else { return }
        
        // Get all destinations if none specified
        let destinations: [MIDIEndpointRef]
        if let dest = destination {
            destinations = [dest]
        } else {
            destinations = availableOutputs.map(\.id)
        }
        
        for dest in destinations {
            var packetList = MIDIPacketList()
            var packet = MIDIPacketListInit(&packetList)
            packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, message.count, message)
            
            let status = MIDISend(outputPort, dest, &packetList)
            if status != noErr {
            }
        }
    }
    
    // MARK: - MIDI Event Processing
    
    /// Process incoming MIDI event list
    private func processMIDIEventList(_ eventList: MIDIEventList) {
        // Copy the event list to a mutable variable to iterate through packets
        var mutableEventList = eventList
        
        withUnsafeMutablePointer(to: &mutableEventList.packet) { firstPacketPtr in
            var packetPtr: UnsafeMutablePointer<MIDIEventPacket> = firstPacketPtr
            
            for _ in 0..<eventList.numPackets {
                let packet = packetPtr.pointee
                let words = Mirror(reflecting: packet.words).children.map { $0.value as! UInt32 }
                processMIDIPacket(words: words, wordCount: Int(packet.wordCount))
                
                packetPtr = MIDIEventPacketNext(packetPtr)
            }
        }
    }
    
    /// Process a single MIDI packet (Universal MIDI Packet format)
    private func processMIDIPacket(words: [UInt32], wordCount: Int) {
        guard wordCount > 0 else { return }
        
        let word = words[0]
        let messageType = (word >> 28) & 0xF
        
        // MIDI 1.0 Channel Voice Messages (MT = 0x2)
        if messageType == 0x2 {
            let status = UInt8((word >> 16) & 0xFF)
            let channel = status & 0x0F
            let data1 = UInt8((word >> 8) & 0x7F)
            let data2 = UInt8(word & 0x7F)
            
            let messageCategory = status & 0xF0
            
            switch messageCategory {
            case 0x90: // Note On
                if data2 > 0 {
                    onNoteOn?(data1, data2, channel)
                    onMIDIMessage?("Note On: \(MIDIHelper.noteName(for: data1)) vel=\(data2) ch=\(channel + 1)")
                } else {
                    // Note On with velocity 0 = Note Off
                    onNoteOff?(data1, channel)
                    onMIDIMessage?("Note Off: \(MIDIHelper.noteName(for: data1)) ch=\(channel + 1)")
                }
                
            case 0x80: // Note Off
                onNoteOff?(data1, channel)
                onMIDIMessage?("Note Off: \(MIDIHelper.noteName(for: data1)) ch=\(channel + 1)")
                
            case 0xB0: // Control Change
                onControlChange?(data1, data2, channel)
                onMIDIMessage?("CC\(data1): \(data2) ch=\(channel + 1)")
                
            case 0xE0: // Pitch Bend
                let bendValue = Int16(data1) | (Int16(data2) << 7) - 8192
                onPitchBend?(bendValue, channel)
                onMIDIMessage?("Pitch Bend: \(bendValue) ch=\(channel + 1)")
                
            case 0xC0: // Program Change
                onProgramChange?(data1, channel)
                onMIDIMessage?("Program Change: \(data1) ch=\(channel + 1)")
                
            default:
                break
            }
        }
    }
    
    // MARK: - MIDI Notifications
    
    /// Handle MIDI setup change notifications
    private func handleMIDINotification(_ notification: UnsafePointer<MIDINotification>) {
        switch notification.pointee.messageID {
        case .msgSetupChanged:
            scanDevices()
            
        case .msgObjectAdded:
            scanDevices()
            
        case .msgObjectRemoved:
            scanDevices()
            
        case .msgPropertyChanged:
            break
            
        default:
            break
        }
    }
}

// MARK: - MIDIRecordingEngine

/// Engine for recording MIDI input to regions.
@MainActor
@Observable
class MIDIRecordingEngine {
    
    // MARK: - Properties
    
    /// Is recording active
    var isRecording = false
    
    /// Recorded notes so far
    var recordedNotes: [MIDINote] = []
    
    /// Recorded CC events
    var recordedCCEvents: [MIDICCEvent] = []
    
    /// Recorded pitch bend events
    var recordedPitchBendEvents: [MIDIPitchBendEvent] = []
    
    /// Currently held notes (pitch -> note being held)
    var activeNotes: [UInt8: MIDINote] = [:]
    
    /// Recording quantization
    var quantization: SnapResolution = .off
    
    /// Time signature for quantization (Issue #64). Defaults to 4/4.
    var timeSignature: TimeSignature = .fourFour
    
    /// Replace or overdub mode
    var isOverdubMode = true
    
    // MARK: - Private Properties
    
    private var recordStartBeat: Double = 0
    private var currentBeatProvider: (() -> Double)?
    private weak var midiDeviceManager: MIDIDeviceManager?
    
    // MARK: - Initialization
    
    init(midiDeviceManager: MIDIDeviceManager) {
        self.midiDeviceManager = midiDeviceManager
        setupCallbacks()
    }
    
    // MARK: - Setup
    
    /// Set the current position provider in beats (e.g., from AudioEngine currentPosition.beats)
    func setBeatProvider(_ provider: @escaping () -> Double) {
        currentBeatProvider = provider
    }
    
    /// Setup MIDI callbacks for recording
    private func setupCallbacks() {
        midiDeviceManager?.onNoteOn = { [weak self] pitch, velocity, channel in
            Task { @MainActor in
                self?.handleNoteOn(pitch: pitch, velocity: velocity, channel: channel)
            }
        }
        
        midiDeviceManager?.onNoteOff = { [weak self] pitch, channel in
            Task { @MainActor in
                self?.handleNoteOff(pitch: pitch, channel: channel)
            }
        }
        
        midiDeviceManager?.onControlChange = { [weak self] cc, value, channel in
            Task { @MainActor in
                self?.handleControlChange(cc: cc, value: value, channel: channel)
            }
        }
        
        midiDeviceManager?.onPitchBend = { [weak self] value, channel in
            Task { @MainActor in
                self?.handlePitchBend(value: value, channel: channel)
            }
        }
    }
    
    // MARK: - Recording Control
    
    /// Start recording at the given position (in beats)
    func startRecording(atBeat beat: Double) {
        isRecording = true
        recordStartBeat = beat
        
        if !isOverdubMode {
            // Replace mode: clear existing notes
            recordedNotes = []
            recordedCCEvents = []
            recordedPitchBendEvents = []
        }
        
        activeNotes = [:]
        
    }
    
    /// Stop recording and return the recorded region
    func stopRecording() -> MIDIRegion? {
        guard isRecording else { return nil }
        
        isRecording = false
        
        // Close any notes still being held (positions in beats relative to region start)
        let currentBeat = currentBeatProvider?() ?? 0
        let relativeCurrentBeat = currentBeat - recordStartBeat
        for (pitch, var note) in activeNotes {
            note.durationBeats = max(0.01, relativeCurrentBeat - note.startBeat)
            recordedNotes.append(note)
        }
        activeNotes = [:]
        
        // Don't create empty regions
        guard !recordedNotes.isEmpty else {
            return nil
        }
        
        // Calculate region duration (max end of notes; notes are relative to region start)
        let endBeat = recordedNotes.map(\.endBeat).max() ?? 0
        
        let region = MIDIRegion(
            id: UUID(),
            name: "MIDI Recording",
            notes: recordedNotes,
            startBeat: recordStartBeat,
            durationBeats: endBeat,
            instrumentId: nil,
            color: .blue,
            isLooped: false,
            loopCount: 1,
            isMuted: false,
            controllerEvents: recordedCCEvents,
            pitchBendEvents: recordedPitchBendEvents
        )
        
        
        // Clear for next recording
        recordedNotes = []
        recordedCCEvents = []
        recordedPitchBendEvents = []
        
        return region
    }
    
    /// Cancel recording without saving
    func cancelRecording() {
        isRecording = false
        activeNotes = [:]
        recordedNotes = []
        recordedCCEvents = []
        recordedPitchBendEvents = []
    }
    
    // MARK: - Event Handlers
    
    private var currentRecordBeat: Double {
        guard let provider = currentBeatProvider else { return 0 }
        return provider() - recordStartBeat
    }
    
    private func handleNoteOn(pitch: UInt8, velocity: UInt8, channel: UInt8) {
        guard isRecording else { return }
        
        var startBeat = currentRecordBeat
        
        // Apply quantization
        if quantization != .off {
            startBeat = quantization.quantize(beat: startBeat, timeSignature: timeSignature)
        }
        
        let note = MIDINote(
            id: UUID(),
            pitch: pitch,
            velocity: velocity,
            startBeat: startBeat,
            durationBeats: 0, // Will be set on note off
            channel: channel
        )
        
        activeNotes[pitch] = note
    }
    
    private func handleNoteOff(pitch: UInt8, channel: UInt8) {
        guard isRecording else { return }
        guard var note = activeNotes[pitch] else { return }
        
        var endBeat = currentRecordBeat
        
        // Apply quantization to duration
        if quantization != .off {
            endBeat = quantization.quantize(beat: endBeat, timeSignature: timeSignature)
        }
        
        note.durationBeats = max(0.01, endBeat - note.startBeat) // Minimum duration
        recordedNotes.append(note)
        activeNotes.removeValue(forKey: pitch)
        
    }
    
    private func handleControlChange(cc: UInt8, value: UInt8, channel: UInt8) {
        guard isRecording else { return }
        
        let event = MIDICCEvent(
            id: UUID(),
            controller: cc,
            value: value,
            beat: currentRecordBeat,
            channel: channel
        )
        recordedCCEvents.append(event)
    }
    
    private func handlePitchBend(value: Int16, channel: UInt8) {
        guard isRecording else { return }
        
        let event = MIDIPitchBendEvent(
            id: UUID(),
            value: value,
            beat: currentRecordBeat,
            channel: channel
        )
        recordedPitchBendEvents.append(event)
    }
    
    // CRITICAL: Protective deinit for @Observable @MainActor class (ASan Issue #84742+)
    // Prevents double-free from implicit Swift Concurrency property change notification tasks
    deinit {
    }
}

