//
//  StepSequencerModels.swift
//  Stori
//
//  Data models for the Step Sequencer
//

import Foundation
import SwiftUI

// MARK: - Step Pattern

/// A complete step sequencer pattern containing multiple lanes
struct StepPattern: Identifiable, Codable {
    let id: UUID
    var name: String
    var steps: Int  // Number of steps (8, 16, 32, 64)
    var lanes: [SequencerLane]
    var tempo: Double  // BPM, syncs with project (not saved/loaded from JSON)
    var swing: Double  // Swing amount 0.0 (none) to 1.0 (full triplet feel)
    
    // MARK: - Advanced Features
    
    /// Humanization amount for timing (0.0 = none, 1.0 = max timing variation)
    var humanizeTiming: Double
    
    /// Humanization amount for velocity (0.0 = none, 1.0 = max velocity variation)
    var humanizeVelocity: Double
    
    /// Source filename (runtime-only, not encoded)
    var sourceFilename: String?
    
    /// Available step counts
    static let stepOptions = [8, 16, 32]
    
    enum CodingKeys: String, CodingKey {
        case id, name, steps, lanes, swing, humanizeTiming, humanizeVelocity
        // tempo excluded - always uses project tempo
    }
    
    /// Memberwise initializer (needed since we have custom Codable)
    init(id: UUID, name: String, steps: Int, lanes: [SequencerLane], tempo: Double, swing: Double,
         humanizeTiming: Double = 0.0, humanizeVelocity: Double = 0.0, sourceFilename: String? = nil) {
        self.id = id
        self.name = name
        self.steps = steps
        self.lanes = lanes
        self.tempo = tempo
        self.swing = swing
        self.humanizeTiming = humanizeTiming
        self.humanizeVelocity = humanizeVelocity
        self.sourceFilename = sourceFilename
    }
    
    /// Creates a default 16-step pattern with standard drum kit
    static func defaultDrumKit(tempo: Double = 120.0) -> StepPattern {
        StepPattern(
            id: UUID(),
            name: "New Pattern",
            steps: 16,
            lanes: SequencerLane.defaultDrumKit(),
            tempo: tempo,  // Uses current project tempo
            swing: 0.0,
            humanizeTiming: 0.0,
            humanizeVelocity: 0.0
        )
    }
    
    /// Custom decoder to handle missing tempo and optional fields (backward compatible)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        steps = try container.decode(Int.self, forKey: .steps)
        lanes = try container.decode([SequencerLane].self, forKey: .lanes)
        swing = try container.decode(Double.self, forKey: .swing)
        
        // Advanced features (optional, defaults to 0.0 for backward compatibility)
        humanizeTiming = try container.decodeIfPresent(Double.self, forKey: .humanizeTiming) ?? 0.0
        humanizeVelocity = try container.decodeIfPresent(Double.self, forKey: .humanizeVelocity) ?? 0.0
        
        // Tempo not decoded from JSON - will be set from current project tempo
        tempo = 120.0  // Placeholder, overridden when loaded
        sourceFilename = nil
    }
    
    /// Duration of one complete pattern cycle in seconds
    var duration: TimeInterval {
        // steps / 4 = number of beats
        // Duration = (60 / bpm) * beats
        let beats = Double(steps) / 4.0
        return (60.0 / tempo) * beats
    }
    
    /// Duration of one step in seconds (without swing)
    var stepDuration: TimeInterval {
        duration / Double(steps)
    }
    
    /// Calculate actual step time with swing applied
    func stepTime(for stepIndex: Int) -> TimeInterval {
        let baseTime = Double(stepIndex) * stepDuration
        
        // Swing affects off-beat steps (1, 3, 5, 7, 9, 11, 13, 15 for 16-step)
        let isOffBeat = stepIndex % 2 == 1
        
        if isOffBeat && swing > 0 {
            // Push off-beats later (up to 33% of step duration for triplet feel)
            let swingDelay = stepDuration * swing * 0.33
            return baseTime + swingDelay
        }
        
        return baseTime
    }
    
    /// Number of bars in this pattern
    var bars: Int {
        steps / 16
    }
    
    /// Whether this pattern uses the legacy 8-lane format
    var isLegacyFormat: Bool {
        lanes.count == 8
    }
    
    /// Migrates an 8-lane pattern to 16-lane extended kit format
    /// Preserves all existing step data and adds empty extended lanes
    mutating func migrateToExtendedKit() {
        guard lanes.count == 8 else { return }
        
        // The legacy format had crash at index 7 (last position)
        // We need to reorganize: insert Mid Tom at position 6, move crash to position 8
        
        // Save the crash lane data (currently at index 7)
        let crashVelocities = lanes[7].stepVelocities
        let crashVolume = lanes[7].volume
        let crashMuted = lanes[7].isMuted
        let crashSolo = lanes[7].isSolo
        
        // Replace position 7 with High Tom (was at position 6 in legacy)
        // Position 6 becomes Mid Tom (new)
        let highTomData = lanes[6]  // Save High Tom data
        
        // Insert Mid Tom at position 6 (empty)
        lanes[6] = SequencerLane(name: "Mid Tom", soundType: .tomMid)
        
        // Position 7 is now High Tom with preserved data
        lanes[7] = SequencerLane(
            name: "High Tom",
            soundType: .tomHigh,
            stepVelocities: highTomData.stepVelocities,
            volume: highTomData.volume,
            isMuted: highTomData.isMuted,
            isSolo: highTomData.isSolo
        )
        
        // Add extended kit lanes (positions 8-15)
        let extendedLanes: [SequencerLane] = [
            // Crash with preserved data from legacy position 7
            SequencerLane(
                name: "Crash",
                soundType: .crash,
                stepVelocities: crashVelocities,
                volume: crashVolume,
                isMuted: crashMuted,
                isSolo: crashSolo
            ),
            SequencerLane(name: "Ride", soundType: .ride),
            SequencerLane(name: "Rim", soundType: .rim),
            SequencerLane(name: "Cowbell", soundType: .cowbell),
            SequencerLane(name: "Shaker", soundType: .shaker),
            SequencerLane(name: "Tambourine", soundType: .tambourine),
            SequencerLane(name: "Low Conga", soundType: .congaLow),
            SequencerLane(name: "High Conga", soundType: .congaHigh),
        ]
        
        lanes.append(contentsOf: extendedLanes)
    }
    
    /// Creates a migrated copy of this pattern (non-mutating version)
    func migratedToExtendedKit() -> StepPattern {
        var copy = self
        copy.migrateToExtendedKit()
        return copy
    }
}

// MARK: - Sequencer Lane

/// A single lane (row) in the sequencer representing one instrument/sound
struct SequencerLane: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var soundType: DrumSoundType
    var stepVelocities: [Int: Float]  // Step index -> velocity (0.0-1.0), absent = off
    var stepProbabilities: [Int: Float]  // Step index -> probability (0.0-1.0), absent = 100%
    var volume: Float  // Master volume for lane 0.0 - 1.0
    var isMuted: Bool
    var isSolo: Bool
    
    /// Which steps are active (convenience accessor)
    var activeSteps: Set<Int> {
        Set(stepVelocities.keys)
    }
    
    /// Creates a lane with default settings
    init(
        id: UUID = UUID(),
        name: String,
        soundType: DrumSoundType,
        stepVelocities: [Int: Float] = [:],
        stepProbabilities: [Int: Float] = [:],
        volume: Float = 0.8,
        isMuted: Bool = false,
        isSolo: Bool = false
    ) {
        self.id = id
        self.name = name
        self.soundType = soundType
        self.stepVelocities = stepVelocities
        self.stepProbabilities = stepProbabilities
        self.volume = volume
        self.isMuted = isMuted
        self.isSolo = isSolo
    }
    
    /// Get probability for a step (1.0 if not set)
    func probability(for step: Int) -> Float {
        stepProbabilities[step] ?? 1.0
    }
    
    /// Set probability for a step
    mutating func setProbability(_ step: Int, probability: Float) {
        if probability >= 1.0 {
            stepProbabilities.removeValue(forKey: step)  // 100% is the default
        } else {
            stepProbabilities[step] = max(0, min(1, probability))
        }
    }
    
    /// Default 16-lane drum kit configuration (Core Kit + Extended Kit)
    /// Optimized for maximum coverage across vintage drum machines:
    /// - Universal (6/6 kits): kick, snare, closed hat
    /// - Nearly Universal (5/6): crash, toms
    /// - Common (4/6): open hat, clap, ride
    /// - Specialty (2-3/6): rim, cowbell, congas
    static func defaultDrumKit() -> [SequencerLane] {
        [
            // Core Kit (Rows 1-8) - Most universal sounds
            SequencerLane(name: "Kick", soundType: .kick),              // 6/6 kits
            SequencerLane(name: "Snare", soundType: .snare),            // 6/6 kits
            SequencerLane(name: "Closed Hat", soundType: .hihatClosed), // 6/6 kits
            SequencerLane(name: "Open Hat", soundType: .hihatOpen),     // 4/6 kits
            SequencerLane(name: "Clap", soundType: .clap),              // 4/6 kits
            SequencerLane(name: "Low Tom", soundType: .tomLow),         // 5/6 kits
            SequencerLane(name: "Mid Tom", soundType: .tomMid),         // 5/6 kits
            SequencerLane(name: "High Tom", soundType: .tomHigh),       // 5/6 kits
            
            // Extended Kit (Rows 9-16) - Common to specialty sounds
            SequencerLane(name: "Crash", soundType: .crash),            // 5/6 kits
            SequencerLane(name: "Ride", soundType: .ride),              // 4/6 kits
            SequencerLane(name: "Rim", soundType: .rim),                // 3/6 kits
            SequencerLane(name: "Cowbell", soundType: .cowbell),        // 3/6 kits
            SequencerLane(name: "Low Conga", soundType: .congaLow),     // 2/6 kits
            SequencerLane(name: "High Conga", soundType: .congaHigh),   // 1/6 kits (LinnDrum)
            SequencerLane(name: "Shaker", soundType: .shaker),          // 1/6 kits (LinnDrum)
            SequencerLane(name: "Tambourine", soundType: .tambourine),  // 0/6 kits (reserved)
        ]
    }
    
    /// Legacy 8-lane drum kit configuration (for backward compatibility)
    static func legacyDrumKit() -> [SequencerLane] {
        [
            SequencerLane(name: "Kick", soundType: .kick),
            SequencerLane(name: "Snare", soundType: .snare),
            SequencerLane(name: "Closed Hat", soundType: .hihatClosed),
            SequencerLane(name: "Open Hat", soundType: .hihatOpen),
            SequencerLane(name: "Clap", soundType: .clap),
            SequencerLane(name: "Low Tom", soundType: .tomLow),
            SequencerLane(name: "High Tom", soundType: .tomHigh),
            SequencerLane(name: "Crash", soundType: .crash)
        ]
    }
    
    /// Get velocity for a step (nil if step is off)
    func velocity(for step: Int) -> Float? {
        stepVelocities[step]
    }
    
    /// Toggle a step on/off (default velocity 0.8)
    mutating func toggleStep(_ step: Int) {
        if stepVelocities[step] != nil {
            stepVelocities.removeValue(forKey: step)
        } else {
            stepVelocities[step] = 0.8  // Default velocity
        }
    }
    
    /// Set step with specific velocity
    mutating func setStep(_ step: Int, velocity: Float) {
        stepVelocities[step] = max(0, min(1, velocity))
    }
    
    /// Adjust velocity for an existing step
    mutating func adjustVelocity(for step: Int, delta: Float) {
        if let current = stepVelocities[step] {
            let newVelocity = max(0.1, min(1.0, current + delta))
            stepVelocities[step] = newVelocity
        }
    }
    
    /// Adjust probability for a step by delta amount
    mutating func adjustProbability(for step: Int, delta: Float) {
        let current = stepProbabilities[step] ?? 1.0
        let newProbability = max(0.0, min(1.0, current + delta))
        setProbability(step, probability: newProbability)
    }
    
    /// Clear all steps
    mutating func clearAllSteps() {
        stepVelocities.removeAll()
    }
    
    /// Copy steps to clipboard format
    func copySteps() -> [Int: Float] {
        stepVelocities
    }
    
    /// Paste steps from clipboard
    mutating func pasteSteps(_ steps: [Int: Float]) {
        stepVelocities = steps
    }
}

// MARK: - Drum Sound Types

/// Enumeration of available drum sounds (16 total for extended kit)
enum DrumSoundType: String, Codable, CaseIterable {
    // Core Kit (Rows 1-8)
    case kick = "kick"
    case snare = "snare"
    case hihatClosed = "hihat_closed"
    case hihatOpen = "hihat_open"
    case clap = "clap"
    case tomLow = "tom_low"
    case tomMid = "tom_mid"
    case tomHigh = "tom_high"
    
    // Extended Kit (Rows 9-16)
    case crash = "crash"
    case ride = "ride"
    case rim = "rim"  // Backend uses "rim", not "rimshot"
    case cowbell = "cowbell"
    case shaker = "shaker"
    case tambourine = "tambourine"
    case congaLow = "conga_low"
    case congaHigh = "conga_high"
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .kick: return "Kick"
        case .snare: return "Snare"
        case .hihatClosed: return "Closed Hat"
        case .hihatOpen: return "Open Hat"
        case .clap: return "Clap"
        case .tomLow: return "Low Tom"
        case .tomMid: return "Mid Tom"
        case .tomHigh: return "High Tom"
        case .crash: return "Crash"
        case .ride: return "Ride"
        case .rim: return "Rim"
        case .cowbell: return "Cowbell"
        case .shaker: return "Shaker"
        case .tambourine: return "Tambourine"
        case .congaLow: return "Low Conga"
        case .congaHigh: return "High Conga"
        }
    }
    
    /// Short name for compact UI
    var shortName: String {
        switch self {
        case .kick: return "KCK"
        case .snare: return "SNR"
        case .hihatClosed: return "CHH"
        case .hihatOpen: return "OHH"
        case .clap: return "CLP"
        case .tomLow: return "LTM"
        case .tomMid: return "MTM"
        case .tomHigh: return "HTM"
        case .crash: return "CRS"
        case .ride: return "RDE"
        case .rim: return "RIM"
        case .cowbell: return "COW"
        case .shaker: return "SHK"
        case .tambourine: return "TMB"
        case .congaLow: return "LCG"
        case .congaHigh: return "HCG"
        }
    }
    
    /// Color for visual identification
    var color: Color {
        switch self {
        case .kick: return .red
        case .snare: return .orange
        case .hihatClosed: return .cyan
        case .hihatOpen: return .teal
        case .clap: return .yellow
        case .tomLow: return .purple
        case .tomMid: return .blue
        case .tomHigh: return .indigo
        case .crash: return .pink
        case .ride: return .mint
        case .rim: return .brown
        case .cowbell: return .gray
        case .shaker: return .green
        case .tambourine: return Color(hue: 0.55, saturation: 0.6, brightness: 0.8)
        case .congaLow: return Color(hue: 0.08, saturation: 0.7, brightness: 0.7)
        case .congaHigh: return Color(hue: 0.05, saturation: 0.8, brightness: 0.8)
        }
    }
    
    /// System symbol for UI
    var systemImage: String {
        switch self {
        case .kick: return "circle.fill"
        case .snare: return "square.fill"
        case .hihatClosed: return "triangle.fill"
        case .hihatOpen: return "triangle"
        case .clap: return "hands.clap.fill"
        case .tomLow: return "cylinder.fill"
        case .tomMid: return "cylinder.split.1x2.fill"
        case .tomHigh: return "cylinder"
        case .crash: return "burst.fill"
        case .ride: return "bell.fill"
        case .rim: return "circle.lefthalf.filled"
        case .cowbell: return "bell"
        case .shaker: return "waveform"
        case .tambourine: return "circle.grid.cross.fill"
        case .congaLow: return "oval.bottomhalf.filled"
        case .congaHigh: return "oval.tophalf.filled"
        }
    }
    
    /// Audio frequency range for synthesis (Hz) - used for generating sounds
    var baseFrequency: Double {
        switch self {
        case .kick: return 60
        case .snare: return 200
        case .hihatClosed: return 8000
        case .hihatOpen: return 6000
        case .clap: return 1500
        case .tomLow: return 100
        case .tomMid: return 140
        case .tomHigh: return 180
        case .crash: return 4000
        case .ride: return 5000
        case .rim: return 1000
        case .cowbell: return 800
        case .shaker: return 7000
        case .tambourine: return 5500
        case .congaLow: return 200
        case .congaHigh: return 275
        }
    }
    
    /// General MIDI drum note number for MIDI export
    var midiNote: UInt8 {
        switch self {
        case .kick: return 36       // C2 - Bass Drum 1
        case .snare: return 38      // D2 - Acoustic Snare
        case .hihatClosed: return 42 // F#2 - Closed Hi-Hat
        case .hihatOpen: return 46  // A#2 - Open Hi-Hat
        case .clap: return 39       // D#2 - Hand Clap
        case .tomLow: return 45     // A2 - Low Tom
        case .tomMid: return 47     // B2 - Low-Mid Tom
        case .tomHigh: return 50    // D3 - High Tom
        case .crash: return 49      // C#3 - Crash Cymbal 1
        case .ride: return 51       // D#3 - Ride Cymbal 1
        case .rim: return 37    // C#2 - Side Stick/Rim
        case .cowbell: return 56    // G#3 - Cowbell
        case .shaker: return 82     // A#5 - Shaker
        case .tambourine: return 54 // F#3 - Tambourine
        case .congaLow: return 64   // E4 - Low Conga
        case .congaHigh: return 63  // D#4 - Open Hi Conga
        }
    }
    
    /// Whether this sound is part of the core kit (first 8) or extended kit
    var isExtendedKit: Bool {
        switch self {
        case .kick, .snare, .hihatClosed, .hihatOpen, .clap, .tomLow, .tomMid, .tomHigh:
            return false
        case .crash, .ride, .rim, .cowbell, .shaker, .tambourine, .congaLow, .congaHigh:
            return true
        }
    }
}

// MARK: - Sequencer Playback State

/// Current playback state of the sequencer
enum SequencerPlaybackState: Equatable {
    case stopped
    case playing
    case paused
}

// MARK: - Step Event

/// Represents a single step trigger event (for audio callback)
struct StepEvent {
    let laneId: UUID
    let soundType: DrumSoundType
    let velocity: Float  // 0.0 - 1.0, always 1.0 for MVP
    let stepIndex: Int
}

// MARK: - MIDI Event (Sequencer Output)

/// MIDI event generated by the step sequencer
struct SequencerMIDIEvent: Identifiable, Equatable {
    let id = UUID()
    let note: UInt8           // MIDI note number (0-127)
    let velocity: UInt8       // Velocity (0-127)
    let channel: UInt8        // MIDI channel (0-15, drums typically = 9)
    let timestamp: Double     // Time in beats from pattern start
    let duration: Double      // Duration in beats (typically 1/16th = 0.25)
    let laneId: UUID          // Source lane for per-lane routing
    let soundType: DrumSoundType  // Original drum sound type
    
    /// Creates a MIDI event from step sequencer data
    init(note: UInt8, velocity: UInt8, channel: UInt8 = 9, timestamp: Double, 
         duration: Double = 0.25, laneId: UUID, soundType: DrumSoundType) {
        self.note = note
        self.velocity = velocity
        self.channel = channel
        self.timestamp = timestamp
        self.duration = duration
        self.laneId = laneId
        self.soundType = soundType
    }
    
    /// Creates a MIDI event from a lane and step
    static func from(lane: SequencerLane, step: Int, stepVelocity: Float, totalSteps: Int) -> SequencerMIDIEvent {
        // Convert step to timestamp in beats (16th notes)
        let beatsPerStep = 0.25  // 16th note = 1/4 beat
        let timestamp = Double(step) * beatsPerStep
        
        // Convert velocity from 0.0-1.0 to 0-127
        let midiVelocity = UInt8(min(127, max(1, Int(stepVelocity * 127))))
        
        return SequencerMIDIEvent(
            note: lane.soundType.midiNote,
            velocity: midiVelocity,
            channel: 9,  // MIDI channel 10 (0-indexed = 9) for drums
            timestamp: timestamp,
            duration: 0.25,
            laneId: lane.id,
            soundType: lane.soundType
        )
    }
}

// MARK: - Sequencer Routing

/// Routing mode for step sequencer MIDI output
enum SequencerRoutingMode: String, Codable, CaseIterable {
    /// Internal sampler playback (instant feedback, no MIDI routing)
    case preview = "preview"
    
    /// Route all lanes to a single MIDI track
    case singleTrack = "single_track"
    
    /// Route each lane to a different MIDI track
    case multiTrack = "multi_track"
    
    /// Output to external MIDI device
    case external = "external"
    
    var displayName: String {
        switch self {
        case .preview: return "Preview (Built-in Sounds)"
        case .singleTrack: return "Single Track"
        case .multiTrack: return "Multi-Track"
        case .external: return "External MIDI"
        }
    }
    
    var description: String {
        switch self {
        case .preview: return "Instant playback using built-in drum samples"
        case .singleTrack: return "Send all drums to one MIDI track"
        case .multiTrack: return "Route each drum to a different track"
        case .external: return "Send MIDI to external hardware"
        }
    }
}

/// Configuration for sequencer MIDI routing
struct SequencerRouting: Codable, Equatable {
    /// Current routing mode
    var mode: SequencerRoutingMode = .preview
    
    /// Target track ID for single-track mode
    var targetTrackId: UUID?
    
    /// Per-lane routing for multi-track mode (laneId → trackId)
    var perLaneRouting: [UUID: UUID] = [:]
    
    /// External MIDI device identifier
    var externalDeviceId: String?
    
    /// Whether preview mode should also send MIDI (for monitoring)
    var previewSendsMIDI: Bool = false
    
    /// Default routing (preview mode)
    static let `default` = SequencerRouting()
    
    /// Check if we should trigger internal sampler
    var shouldPlayInternally: Bool {
        mode == .preview || previewSendsMIDI
    }
    
    /// Check if we should send MIDI events
    var shouldSendMIDI: Bool {
        mode != .preview || previewSendsMIDI
    }
}

