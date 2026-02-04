//
//  TransportDependencies.swift
//  Stori
//
//  Protocol-based dependencies for TransportController.
//  Replaces closure-based injection for better testability and clarity.
//

import Foundation
import AVFoundation

// MARK: - Transport Delegate Protocol

/// Protocol for AudioEngine to implement transport callbacks.
/// This replaces the closure-based dependency injection pattern.
@MainActor
protocol TransportDelegate: AnyObject {
    // MARK: - State Queries
    
    var currentProject: AudioProject? { get }
    var isInstallingPlugin: Bool { get }
    var isGraphStable: Bool { get }
    var currentSampleRate: Double { get }
    
    // MARK: - Playback Control
    
    func performStartPlayback(fromBeat: Double)
    func performStopPlayback()
    
    // MARK: - State Change Notifications
    
    func handleTransportStateChanged(_ state: TransportState)
    func handlePositionChanged(_ position: PlaybackPosition)
    func handleCycleJump(toBeat: Double)
}

// NOTE: AudioEngine will conform to TransportDelegate in a future refactor.
// The protocol is defined here for documentation purposes.
// All required methods exist as private methods in AudioEngine.
// For now, closure-based injection continues to work.

// MARK: - Recording Delegate Protocol

/// Protocol for AudioEngine to implement recording callbacks.
@MainActor
protocol RecordingDelegate: AnyObject {
    var currentProject: AudioProject? { get set }
    var currentPosition: PlaybackPosition { get }
    var selectedTrackId: UUID? { get }
    var mixer: AVAudioMixerNode { get }
    
    func startRecordingMode()
    func stopRecordingMode()
    func startPlayback()
    func stopPlayback()
    func reconnectMetronome()
    func reloadProject(_ project: AudioProject)
}

// MARK: - Mixer Delegate Protocol

/// Protocol for AudioEngine to implement mixer callbacks.
@MainActor
protocol MixerDelegate: AnyObject {
    var currentProject: AudioProject? { get set }
    var trackNodes: [UUID: TrackAudioNode] { get }
    var mainMixer: AVAudioMixerNode { get }
    var masterEQ: AVAudioUnitEQ { get }
    
    func reloadMIDIRegions()
    func safeDisconnectTrackNode(_ trackNode: TrackAudioNode)
}

// MARK: - Graph Manager Delegate Protocol

/// Protocol for AudioEngine to implement graph manager callbacks.
@MainActor
protocol GraphManagerDelegate: AnyObject {
    var currentProject: AudioProject? { get }
    var currentPosition: PlaybackPosition { get }
    var transportState: TransportState { get }
    var trackNodes: [UUID: TrackAudioNode] { get }
    var isGraphReadyForPlayback: Bool { get set }
    
    func playFromBeat(_ beat: Double)
}

// MARK: - Track Node Manager Delegate Protocol

/// Protocol for AudioEngine to implement track node manager callbacks.
@MainActor
protocol TrackNodeManagerDelegate: AnyObject {
    var graphFormat: AVAudioFormat? { get }
    var engine: AVAudioEngine { get }
    var mixer: AVAudioMixerNode { get }
    
    func ensureEngineRunning()
    func rebuildTrackGraph(trackId: UUID)
    func safeDisconnectTrackNode(_ trackNode: TrackAudioNode)
    func loadAudioRegion(_ region: AudioRegion, trackNode: TrackAudioNode)
}

// NOTE: AudioEngine already implements all these methods.
// These protocols formalize the contracts and make dependencies explicit.
// Future refactor: Pass protocol references instead of closures.
