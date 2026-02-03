//
//  AudioModels.swift
//  Stori
//
//  Core audio data models for the DAW
//

import Foundation
import AVFoundation
import SwiftUI

// MARK: - Track Type
enum TrackType: String, Codable, CaseIterable {
    case audio = "audio"
    case midi = "midi"
    case instrument = "instrument"
    case bus = "bus"
}

// MARK: - Track Color
enum TrackColor: Codable, Equatable, Hashable {
    case blue
    case red
    case green
    case yellow
    case purple
    case pink
    case orange
    case teal
    case indigo
    case gray
    case custom(String) // Custom hex color
    
    var rawValue: String {
        switch self {
        case .blue: return "#3B82F6"
        case .red: return "#EF4444"
        case .green: return "#10B981"
        case .yellow: return "#F59E0B"
        case .purple: return "#8B5CF6"
        case .pink: return "#EC4899"
        case .orange: return "#F97316"
        case .teal: return "#14B8A6"
        case .indigo: return "#6366F1"
        case .gray: return "#6B7280"
        case .custom(let hex): return hex
        }
    }
    
    var color: Color {
        // Convert hex string to Color
        let hex = rawValue.replacingOccurrences(of: "#", with: "")
        let scanner = Scanner(string: hex)
        var hexNumber: UInt64 = 0
        
        if scanner.scanHexInt64(&hexNumber) {
            let r = Double((hexNumber & 0xff0000) >> 16) / 255
            let g = Double((hexNumber & 0x00ff00) >> 8) / 255
            let b = Double(hexNumber & 0x0000ff) / 255
            return Color(red: r, green: g, blue: b)
        }
        
        return Color.blue // fallback
    }
    
    // Static predefined colors for picker
    static let allPredefinedCases: [TrackColor] = [
        .blue, .red, .green, .yellow, .purple,
        .pink, .orange, .teal, .indigo, .gray
    ]
}

// MARK: - Time Signature
struct TimeSignature: Codable, Equatable {
    var numerator: Int
    var denominator: Int
    
    static let fourFour = TimeSignature(numerator: 4, denominator: 4)
    static let threeFour = TimeSignature(numerator: 3, denominator: 4)
    
    /// Safe initializer that ensures valid values
    init(numerator: Int, denominator: Int) {
        // Ensure numerator is at least 1 to prevent division by zero
        self.numerator = max(1, numerator)
        // Ensure denominator is a valid beat division (at least 1)
        self.denominator = max(1, denominator)
    }
    
    var description: String {
        "\(numerator)/\(denominator)"
    }
    
    var displayString: String {
        "\(numerator)/\(denominator)"
    }
}

// MARK: - Beat Position (Primary Time Unit)

/// Primary time unit for musical positioning throughout the DAW.
/// Beats are the source of truth - seconds are only used at AVAudioEngine boundaries.
struct BeatPosition: Codable, Equatable, Comparable, Hashable {
    /// The position in beats (quarter notes at standard tempo)
    let beats: Double
    
    /// Initialize with a beat value
    init(_ beats: Double) {
        self.beats = max(0, beats)  // Ensure non-negative
    }
    
    /// Zero position
    static let zero = BeatPosition(0)
    
    // MARK: - Conversion to Seconds (for AVAudioEngine)
    
    /// Convert to seconds at a given tempo (BPM)
    /// Only use this when interfacing with AVAudioEngine or AI generation services
    func toSeconds(tempo: Double) -> TimeInterval {
        beats * (60.0 / tempo)
    }
    
    /// Create from seconds at a given tempo
    /// Use sparingly - prefer working in beats throughout
    static func fromSeconds(_ seconds: TimeInterval, tempo: Double) -> BeatPosition {
        BeatPosition(seconds * (tempo / 60.0))
    }
    
    // MARK: - Musical Time Components
    
    /// Get the bar number (1-indexed) for a given time signature
    func bar(timeSignature: TimeSignature = .fourFour) -> Int {
        Int(beats / Double(timeSignature.numerator)) + 1
    }
    
    /// Get the beat within the current bar (1-indexed)
    func beatInBar(timeSignature: TimeSignature = .fourFour) -> Int {
        Int(beats.truncatingRemainder(dividingBy: Double(timeSignature.numerator))) + 1
    }
    
    /// Get the subdivision (0-99, representing percentage of beat)
    var subdivision: Int {
        Int((beats.truncatingRemainder(dividingBy: 1)) * 100)
    }
    
    /// Get the tick position (0-479, at 480 PPQN)
    func tick(ppqn: Int = 480) -> Int {
        Int((beats.truncatingRemainder(dividingBy: 1)) * Double(ppqn))
    }
    
    // MARK: - Arithmetic
    
    static func + (lhs: BeatPosition, rhs: BeatPosition) -> BeatPosition {
        BeatPosition(lhs.beats + rhs.beats)
    }
    
    static func + (lhs: BeatPosition, rhs: Double) -> BeatPosition {
        BeatPosition(lhs.beats + rhs)
    }
    
    static func - (lhs: BeatPosition, rhs: BeatPosition) -> BeatPosition {
        BeatPosition(lhs.beats - rhs.beats)
    }
    
    static func - (lhs: BeatPosition, rhs: Double) -> BeatPosition {
        BeatPosition(lhs.beats - rhs)
    }
    
    static func * (lhs: BeatPosition, rhs: Double) -> BeatPosition {
        BeatPosition(lhs.beats * rhs)
    }
    
    static func / (lhs: BeatPosition, rhs: Double) -> BeatPosition {
        BeatPosition(lhs.beats / rhs)
    }
    
    // MARK: - Comparison
    
    static func < (lhs: BeatPosition, rhs: BeatPosition) -> Bool {
        lhs.beats < rhs.beats
    }
    
    // MARK: - Display
    
    /// Format as bar.beat.subdivision string (e.g., "1.2.50")
    func displayString(timeSignature: TimeSignature = .fourFour) -> String {
        String(format: "%d.%d.%02d", bar(timeSignature: timeSignature), beatInBar(timeSignature: timeSignature), subdivision)
    }
    
    /// Format as bar.beat.tick string for MIDI (e.g., "1.2.240")
    func midiDisplayString(timeSignature: TimeSignature = .fourFour, ppqn: Int = 480) -> String {
        String(format: "%d.%d.%03d", bar(timeSignature: timeSignature), beatInBar(timeSignature: timeSignature), tick(ppqn: ppqn))
    }
}

// MARK: - Audio Project
// MARK: - Project UI State (Complete state persistence)

/// Complete UI state for project - everything needed to restore exact UI configuration
/// This enables full AI control and perfect state persistence across sessions
struct ProjectUIState: Codable, Equatable {
    // MARK: - Zoom & View State
    var horizontalZoom: Double = 0.8          // Timeline horizontal zoom (0.1x to 10x)
    var verticalZoom: Double = 1.0            // Timeline vertical zoom (0.5x to 3x)
    var timeDisplayMode: String = "beats"     // "beats" or "time"
    
    // MARK: - Timeline Controls
    var snapToGrid: Bool = true               // Snap regions/notes to grid
    var catchPlayheadEnabled: Bool = true     // Auto-scroll to follow playhead
    
    // MARK: - Metronome State
    var metronomeEnabled: Bool = false        // Metronome on/off
    var metronomeVolume: Float = 0.7          // Metronome volume (0.0 - 1.0)
    
    // MARK: - Panel Visibility
    var showingInspector: Bool = false       // Right panel (Composer) - hidden until service is available
    var showingSelection: Bool = false        // Left selection panel
    var showingMixer: Bool = false            // Bottom mixer panel
    var showingStepSequencer: Bool = false    // Step sequencer panel
    var showingPianoRoll: Bool = false        // Piano roll panel
    var showingSynthesizer: Bool = false      // Synthesizer panel
    
    // MARK: - Panel Sizes
    var inspectorWidth: Double = 300          // Right panel width
    var mixerHeight: Double = 600             // Bottom mixer height
    var stepSequencerHeight: Double = 600     // Step sequencer height
    var pianoRollHeight: Double = 600         // Piano roll height
    var synthesizerHeight: Double = 500       // Synthesizer height
    
    // MARK: - Active Tabs/Modes
    var selectedInspectorTab: String = "compose"  // "compose", "track", "region", etc.
    var selectedEditorMode: String = "pianoRoll"  // "pianoRoll" or "stepSequencer"
    
    // MARK: - Playback State
    var playheadPosition: Double = 0.0        // Current playhead in beats
    // TODO: Add loop state when loop functionality is implemented
    // var loopEnabled: Bool = false
    // var loopStart: Double = 0.0
    // var loopEnd: Double = 16.0
    
    /// Default UI state for new projects
    static var `default`: ProjectUIState {
        ProjectUIState()
    }
}

struct AudioProject: Identifiable, Codable, Equatable {
    /// Current project file schema version - increment when making breaking changes
    static let currentVersion = 2  // Bumped to 2 for UI state addition
    
    /// Project file version for migration support
    let version: Int
    let id: UUID
    var name: String
    var tracks: [AudioTrack]
    var buses: [MixerBus]
    var groups: [TrackGroup]  // Track grouping for linked parameters
    var tempo: Double
    var keySignature: String
    var timeSignature: TimeSignature
    var sampleRate: Double
    var bufferSize: Int
    var createdAt: Date
    var modifiedAt: Date
    
    // Project-level image for tokenization
    var projectImageAssetPath: String?
    
    // Project thumbnail for recent projects display
    var projectThumbnailPath: String?
    
    // MARK: - Complete UI State Persistence
    var uiState: ProjectUIState = .default
    
    init(
        name: String,
        tempo: Double = 120.0,
        keySignature: String = "C",
        timeSignature: TimeSignature = .fourFour,
        sampleRate: Double = 48000.0,
        bufferSize: Int = 512
    ) {
        self.version = Self.currentVersion
        self.id = UUID()
        self.name = name
        self.tracks = []
        self.buses = []
        self.groups = []
        self.tempo = tempo
        self.keySignature = keySignature
        self.timeSignature = timeSignature
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.projectImageAssetPath = nil
        self.uiState = .default
    }
    
    // MARK: - Codable with Version Migration
    
    private enum CodingKeys: String, CodingKey {
        case version, id, name, tracks, buses, groups, tempo, keySignature
        case timeSignature, sampleRate, bufferSize, createdAt, modifiedAt
        case projectImageAssetPath, projectThumbnailPath, uiState
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode all fields (no migration needed - we're in dev)
        version = try container.decode(Int.self, forKey: .version)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        tracks = try container.decode([AudioTrack].self, forKey: .tracks)
        buses = try container.decode([MixerBus].self, forKey: .buses)
        groups = try container.decode([TrackGroup].self, forKey: .groups)
        tempo = try container.decode(Double.self, forKey: .tempo)
        keySignature = try container.decode(String.self, forKey: .keySignature)
        timeSignature = try container.decode(TimeSignature.self, forKey: .timeSignature)
        sampleRate = try container.decode(Double.self, forKey: .sampleRate)
        bufferSize = try container.decode(Int.self, forKey: .bufferSize)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        modifiedAt = try container.decode(Date.self, forKey: .modifiedAt)
        projectImageAssetPath = try container.decodeIfPresent(String.self, forKey: .projectImageAssetPath)
        projectThumbnailPath = try container.decodeIfPresent(String.self, forKey: .projectThumbnailPath)
        uiState = try container.decode(ProjectUIState.self, forKey: .uiState)
    }
    
    /// Project duration in beats (maximum end beat across all tracks)
    var durationBeats: Double {
        tracks.compactMap { $0.durationBeats }.max() ?? 0
    }
    
    /// Project duration in seconds at current tempo
    func durationSeconds(tempo: Double) -> TimeInterval {
        durationBeats * (60.0 / tempo)
    }
    
    var trackCount: Int {
        tracks.count
    }
    
    mutating func addTrack(_ track: AudioTrack) {
        tracks.append(track)
        modifiedAt = Date()
    }
    
    mutating func removeTrack(withId id: UUID) {
        tracks.removeAll { $0.id == id }
        modifiedAt = Date()
    }
}

// MARK: - Audio Track
struct AudioTrack: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var regions: [AudioRegion]
    var mixerSettings: MixerSettings
    var sends: [TrackSend]
    var trackType: TrackType
    var color: TrackColor
    var iconName: String?
    var isFrozen: Bool
    var frozenAudioPath: String?  // Relative path to frozen audio file (when track is frozen)
    var isEnabled: Bool
    var createdAt: Date
    
    // MARK: - MIDI Support
    var midiRegions: [MIDIRegion]  // MIDI regions for instrument/midi tracks
    var voicePreset: String?  // Display name only (e.g., "Electric Piano 1", "TR-909")
    
    // MARK: - Instrument Configuration (Numeric - Machine Friendly)
    var gmProgram: Int?       // GM program number 0-127 (nil = not a GM sampler)
    var drumKitId: String?    // Drum kit identifier (nil = not a drum kit)
    var synthPresetId: Int?   // Synth preset index (nil = not a synth, or use default)
    
    // MARK: - Visual/Image Properties (Phase 5)
    var imageAssetPath: String?  // Relative path to current track image within project bundle
    var imageGenerations: [ImageGeneration]  // History of generated images for this track
    
    // MARK: - Automation
    var automationLanes: [AutomationLane]  // Automation lanes for this track
    var automationMode: AutomationMode     // Current automation mode (Off/Read/Touch/Latch/Write)
    var automationExpanded: Bool           // Whether automation lanes are visible in timeline
    
    // MARK: - Input Monitoring
    var inputMonitorEnabled: Bool          // Whether live input monitoring is enabled
    
    // MARK: - Professional Mixer Channel Strip
    var collapsedSections: Set<ChannelStripSection>  // Which sections are collapsed in mixer
    var channelStripWidth: ChannelStripWidth         // Display width preference
    
    // MARK: - AU Plugin Persistence
    var pluginConfigs: [PluginConfiguration]  // AU plugin configurations for track's insert chain
    
    // MARK: - I/O Routing
    var inputSource: TrackInputSource      // Where audio input comes from
    var outputDestination: TrackOutputDestination  // Where track output goes
    
    // MARK: - Grouping
    var groupId: UUID?  // ID of the TrackGroup this track belongs to (nil = ungrouped)
    
    init(id: UUID = UUID(), name: String, trackType: TrackType = .audio, color: TrackColor = .blue, iconName: String? = nil) {
        self.id = id
        self.name = name
        self.regions = []
        self.midiRegions = []
        self.voicePreset = nil
        self.gmProgram = nil
        self.drumKitId = nil
        self.synthPresetId = nil
        self.mixerSettings = MixerSettings()
        self.sends = []
        self.trackType = trackType
        self.color = color
        self.iconName = iconName
        self.isFrozen = false
        self.frozenAudioPath = nil
        self.isEnabled = true
        self.createdAt = Date()
        self.imageAssetPath = nil
        self.imageGenerations = []
        // Create default Volume automation lane for every track
        self.automationLanes = [AutomationLane(parameter: .volume)]
        self.automationMode = .read
        self.automationExpanded = false
        self.inputMonitorEnabled = false
        self.collapsedSections = []
        self.channelStripWidth = .standard
        self.pluginConfigs = []
        self.inputSource = .systemDefault
        self.outputDestination = .stereoOut
        self.groupId = nil
    }
    
    // MARK: - Track Type Helpers
    
    /// Whether this is a MIDI or Instrument track (can hold MIDI regions)
    var isMIDITrack: Bool {
        trackType == .midi || trackType == .instrument
    }
    
    /// Whether this is an Audio track (can hold audio regions)
    var isAudioTrack: Bool {
        trackType == .audio
    }
    
    /// Icon for the track type
    var trackTypeIcon: String {
        switch trackType {
        case .audio: return "waveform"
        case .midi: return "pianokeys"
        case .instrument: return "pianokeys.inverse"
        case .bus: return "arrow.triangle.branch"
        }
    }
    
    /// Whether this track has any automation data recorded
    var hasAutomationData: Bool {
        automationLanes.contains { !$0.points.isEmpty }
    }
    
    /// Count of automation lanes with data
    var automationLaneCount: Int {
        automationLanes.filter { !$0.points.isEmpty }.count
    }
    
    /// Label for the track type
    var trackTypeLabel: String {
        switch trackType {
        case .audio: return "Audio"
        case .midi: return "MIDI"
        case .instrument: return "Instrument"
        case .bus: return "Bus"
        }
    }
    
    // MARK: - Duration & Content
    
    /// Track duration in beats (requires tempo for audio region conversion)
    func durationInBeats(tempo: Double) -> Double? {
        let audioEndBeat = regions.isEmpty ? nil : regions.map { $0.endBeat }.max()
        let midiEndBeat = midiRegions.isEmpty ? nil : midiRegions.map { $0.endBeat }.max()
        
        switch (audioEndBeat, midiEndBeat) {
        case (nil, nil): return nil
        case (let a?, nil): return a
        case (nil, let m?): return m
        case (let a?, let m?): return max(a, m)
        }
    }
    
    /// Track duration in beats (using 120 BPM as fallback)
    /// Prefer durationInBeats(tempo:) when tempo is available
    /// Note: Returns beats, not seconds (despite TimeInterval type)
    var durationBeats: Double? {
        durationInBeats(tempo: 120.0)
    }
    
    var hasAudio: Bool {
        !regions.isEmpty
    }
    
    var hasMIDI: Bool {
        !midiRegions.isEmpty
    }
    
    var hasContent: Bool {
        hasAudio || hasMIDI
    }
    
    // MARK: - Region Management
    
    mutating func addRegion(_ region: AudioRegion) {
        regions.append(region)
    }
    
    mutating func removeRegion(withId id: UUID) {
        regions.removeAll { $0.id == id }
    }
    
    mutating func addMIDIRegion(_ region: MIDIRegion) {
        midiRegions.append(region)
    }
    
    mutating func removeMIDIRegion(withId id: UUID) {
        midiRegions.removeAll { $0.id == id }
    }
}

// MARK: - Audio Region
struct AudioRegion: Identifiable, Codable, Equatable {
    let id: UUID
    var audioFile: AudioFile
    var startBeat: Double             // Position on timeline in BEATS (musical time)
    var durationBeats: Double         // Region length in BEATS (musical time) - WYSIWYG!
    var fadeIn: TimeInterval          // Fade in time (seconds)
    var fadeOut: TimeInterval         // Fade out time (seconds)
    var gain: Float
    var isLooped: Bool
    var offset: TimeInterval          // Offset within the audio file (seconds)
    
    /// Content length for one loop iteration in seconds. Defaults to audioFile.duration.
    /// When resized with empty space, this becomes larger than audioFile.duration.
    /// Looping repeats this contentLength, not audioFile.duration.
    var contentLength: TimeInterval
    
    /// Original tempo at which durationBeats was calculated.
    /// Used to recalculate beat positions when project tempo changes.
    var originalTempo: Double
    
    // MARK: - Clip-Level Effects (Per-Region Processing)
    
    /// Effects applied to this region only (not the whole track).
    /// Processed before the audio enters the track's plugin chain.
    /// Use cases: pitch correction on specific vocal takes, EQ for individual clips.
    var clipEffects: [ClipEffect]
    
    /// Whether clip effects are enabled for this region
    var clipEffectsEnabled: Bool
    
    init(
        audioFile: AudioFile,
        startBeat: Double = 0,
        durationBeats: Double? = nil,
        tempo: Double = 120.0,
        fadeIn: TimeInterval = 0,
        fadeOut: TimeInterval = 0,
        gain: Float = 1.0,
        isLooped: Bool = false,
        offset: TimeInterval = 0,
        contentLength: TimeInterval? = nil,
        clipEffects: [ClipEffect] = [],
        clipEffectsEnabled: Bool = true
    ) {
        self.id = UUID()
        self.audioFile = audioFile
        // Ensure non-negative timeline values
        self.startBeat = max(0, startBeat)
        // Convert audio file duration from seconds to beats at the given tempo
        let computedDuration = durationBeats ?? (audioFile.duration * (tempo / 60.0))
        self.durationBeats = max(0, computedDuration)
        self.fadeIn = max(0, fadeIn)
        self.fadeOut = max(0, fadeOut)
        // Clamp gain to reasonable range (0.0 to 2.0, where 1.0 = unity gain)
        self.gain = max(0.0, min(2.0, gain))
        self.isLooped = isLooped
        self.offset = max(0, offset)
        self.contentLength = contentLength ?? audioFile.duration
        self.clipEffects = clipEffects
        self.clipEffectsEnabled = clipEffectsEnabled
        self.originalTempo = tempo
    }
    
    /// Whether this region has any active clip effects
    var hasActiveClipEffects: Bool {
        clipEffectsEnabled && !clipEffects.isEmpty
    }
    
    // MARK: - Computed Properties
    
    /// End position in beats (musical time)
    /// NOTE: Use endBeat(currentTempo:) for tempo-aware calculations
    var endBeat: Double {
        startBeat + durationBeats
    }
    
    /// Calculate duration in beats adjusted for current tempo.
    /// Audio regions are time-locked: their duration in seconds is constant,
    /// but beat representation changes with tempo.
    func durationBeats(currentTempo: Double) -> Double {
        // Get duration in seconds (constant for audio content)
        let durationInSeconds = durationBeats * (60.0 / originalTempo)
        // Convert back to beats at current tempo
        return durationInSeconds * (currentTempo / 60.0)
    }
    
    /// Calculate end beat adjusted for current tempo.
    /// Use this when tempo has changed from originalTempo.
    func endBeat(currentTempo: Double) -> Double {
        startBeat + durationBeats(currentTempo: currentTempo)
    }
    
    /// Update durationBeats when project tempo changes.
    /// Call this to keep beat positions synchronized with tempo.
    mutating func updateForTempoChange(newTempo: Double) {
        // Recalculate durationBeats for new tempo
        let durationInSeconds = durationBeats * (60.0 / originalTempo)
        durationBeats = durationInSeconds * (newTempo / 60.0)
        originalTempo = newTempo
    }
    
    /// Convert duration from beats to seconds at given tempo (for AVAudioEngine)
    func durationSeconds(tempo: Double) -> TimeInterval {
        durationBeats * (60.0 / tempo)
    }
    
    /// Convert beat position to seconds at given tempo (for AVAudioEngine)
    func startTimeSeconds(tempo: Double) -> TimeInterval {
        startBeat * (60.0 / tempo)
    }
    
    /// End position in seconds at given tempo (for AVAudioEngine)
    func endTimeSeconds(tempo: Double) -> TimeInterval {
        startTimeSeconds(tempo: tempo) + durationSeconds(tempo: tempo)
    }
    
    var displayName: String {
        audioFile.name
    }
    
    // MARK: [V2-MULTISELECT] Analysis + Matching
    var detectedTempo: Double? = nil
    var detectedKey: String? = nil   // e.g. "C Major", "A Minor"
    
    /// Optional confidence for tempo estimate [0, 1].
    var tempoConfidence: Float? = nil
    
    /// Optional confidence for key estimate [0, 1].
    var keyConfidence: Float? = nil
    
    var pitchShiftCents: Float = 0.0 // -2400...+2400 (2 oct)
    var tempoRate: Float = 1.0       // 0.5...2.0
    
    // MARK: - Beat Detection
    /// Detected beat positions (in seconds from region start), calculated from detected tempo
    var detectedBeats: [TimeInterval]? = nil
    
    /// Which beats are downbeats (first beat of measure). Indices into detectedBeats array.
    var downbeatIndices: [Int]? = nil
    
    // MARK: - AI Generation Metadata
    /// Metadata for AI-generated audio regions
    var aiGenerationMetadata: AIGenerationMetadata? = nil
    
    // MARK: - Step Sequencer Metadata
    /// Metadata for audio regions exported from the step sequencer
    var stepSequencerMetadata: StepSequencerMetadata? = nil
}

// MARK: - Generation Type
/// Type of AI generation (for provenance tracking)
enum GenerationType: String, CaseIterable, Codable {
    case music = "Music"
    case effects = "Sound Effects"
    
    /// Display name for the generation type
    var displayName: String {
        return rawValue
    }
}

// MARK: - AI Generation Metadata
/// Stores information about how an audio region was generated using AI
struct AIGenerationMetadata: Codable, Equatable {
    /// The prompt used to generate the audio
    var prompt: String
    
    /// Generation job ID from the Music Generation service (e.g., "gen_27f6e9018c41")
    var jobId: String
    
    /// Seed used for deterministic generation
    var seed: Int
    
    /// Model used for generation (e.g., "facebook/musicgen-small")
    var model: String
    
    /// Type of generation (music or sound effects)
    var generationType: GenerationType
    
    /// Temperature parameter used (if applicable)
    var temperature: Double?
    
    /// Top-k parameter used (if applicable)
    var topK: Int?
    
    /// Top-p parameter used (if applicable)
    var topP: Double?
    
    /// Timestamp when generation was initiated
    var createdAt: Date
    
    /// Time taken to generate (in seconds)
    var generationTime: TimeInterval?
    
    init(
        prompt: String,
        jobId: String,
        seed: Int,
        model: String = "facebook/musicgen-small",
        generationType: GenerationType,
        temperature: Double? = nil,
        topK: Int? = nil,
        topP: Double? = nil,
        createdAt: Date = Date(),
        generationTime: TimeInterval? = nil
    ) {
        self.prompt = prompt
        self.jobId = jobId
        self.seed = seed
        self.model = model
        self.generationType = generationType
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.createdAt = createdAt
        self.generationTime = generationTime
    }
}

// MARK: - Step Sequencer Metadata
/// Stores the step sequencer pattern for exported audio regions
struct StepSequencerMetadata: Codable, Equatable {
    /// N rows x M columns pattern (16 rows for extended kit, 16 columns for 1 bar)
    /// Row order matches DrumSoundType.allCases (kick, snare, closedHat, etc.)
    var pattern: [[Bool]]
    
    /// BPM at time of export
    var tempo: Double
    
    /// Kit name used
    var kitName: String
    
    /// Timestamp when exported
    var exportedAt: Date
    
    init(pattern: [[Bool]], tempo: Double, kitName: String, exportedAt: Date = Date()) {
        self.pattern = pattern
        self.tempo = tempo
        self.kitName = kitName
        self.exportedAt = exportedAt
    }
}

// MARK: - Audio File
struct AudioFile: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let duration: TimeInterval
    let sampleRate: Double
    let channels: Int
    var bitDepth: Int = 16
    let fileSize: Int64
    let format: AudioFileFormat
    var createdAt: Date = Date()
    
    // MARK: - Path Storage (Refactored for Portability)
    
    /// Stored path - can be relative (within project) or absolute (external file).
    /// - Internal: "Audio/filename.wav"
    /// - External: "/Users/user/Music/filename.wav"
    var storedPath: String
    
    /// Securely resolved absolute URL to the audio file.
    /// - Security: All path validation handled by AudioFileReferenceManager
    /// - Validates: Path traversal prevention, project boundaries, null bytes
    /// - Fallback: Returns safe blocked path if validation fails
    var url: URL {
        let manager = AudioFileReferenceManager.shared
        
        // Single unified secure resolution
        if let secureURL = manager.resolveURL(for: storedPath, projectDirectory: nil) {
            return secureURL
        }
        
        // Security fallback: blocked path instead of potentially malicious path
        return URL(fileURLWithPath: "/tmp/blocked-audio-path-\(id.uuidString)")
    }
    
    // MARK: - Initialization
    
    /// Create an AudioFile from an absolute URL
    init(
        name: String,
        url: URL,
        duration: TimeInterval,
        sampleRate: Double,
        channels: Int,
        bitDepth: Int = 16,
        fileSize: Int64,
        format: AudioFileFormat
    ) {
        self.id = UUID()
        self.name = name
        self.storedPath = url.path
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
        self.fileSize = fileSize
        self.format = format
        self.createdAt = Date()
    }
    
    /// Create an AudioFile with a relative path (preferred for project-bundled files)
    init(
        name: String,
        relativePath: String,
        duration: TimeInterval,
        sampleRate: Double,
        channels: Int,
        bitDepth: Int = 16,
        fileSize: Int64,
        format: AudioFileFormat
    ) {
        self.id = UUID()
        self.name = name
        self.storedPath = relativePath
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
        self.fileSize = fileSize
        self.format = format
        self.createdAt = Date()
    }
    
    // MARK: - Display Properties
    
    var displayDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
    
    /// Whether this file uses a relative path (within project bundle)
    var isRelativePath: Bool {
        return !storedPath.hasPrefix("/") && !storedPath.hasPrefix("file://")
    }
}

// MARK: - Audio File Format
enum AudioFileFormat: String, Codable, CaseIterable {
    case wav = "wav"
    case aiff = "aiff"
    case m4a = "m4a"
    case flac = "flac"
    
    var displayName: String {
        switch self {
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .m4a: return "M4A"
        case .flac: return "FLAC"
        }
    }
    
    var isLossless: Bool {
        switch self {
        case .wav, .aiff, .flac: return true
        case .m4a: return false
        }
    }
}

// MARK: - Mixer Settings
struct MixerSettings: Codable, Equatable {
    var volume: Float
    var pan: Float
    var highEQ: Float
    var midEQ: Float
    var lowEQ: Float
    var sendLevel: Float
    var isMuted: Bool
    var isSolo: Bool
    var isRecordEnabled: Bool
    var inputMonitoring: Bool
    
    // MARK: - Professional Mixer Enhancements
    var eqEnabled: Bool              // Master EQ bypass toggle
    var phaseInverted: Bool          // Phase invert (Ø)
    var soloSafe: Bool               // Prevents track from being muted when other tracks solo
    var inputTrim: Float             // Input gain trim in dB (-20 to +20)
    var outputTrim: Float            // Output gain trim in dB (-20 to +20)
    
    init(
        volume: Float = 0.8,
        pan: Float = 0.5,  // 0.5 = center in 0-1 range (converts to 0.0 in -1 to +1 range)
        highEQ: Float = 0.0,
        midEQ: Float = 0.0,
        lowEQ: Float = 0.0,
        sendLevel: Float = 0.0,
        isMuted: Bool = false,
        isSolo: Bool = false,
        isRecordEnabled: Bool = false,
        inputMonitoring: Bool = false,
        eqEnabled: Bool = true,
        phaseInverted: Bool = false,
        soloSafe: Bool = false,
        inputTrim: Float = 0.0,
        outputTrim: Float = 0.0
    ) {
        // Clamp values to valid ranges to prevent audio issues
        self.volume = max(0.0, min(1.0, volume))
        self.pan = max(0.0, min(1.0, pan))
        self.highEQ = highEQ
        self.midEQ = midEQ
        self.lowEQ = lowEQ
        self.sendLevel = max(0.0, min(1.0, sendLevel))
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.isRecordEnabled = isRecordEnabled
        self.inputMonitoring = inputMonitoring
        self.eqEnabled = eqEnabled
        self.phaseInverted = phaseInverted
        self.soloSafe = soloSafe
        self.inputTrim = max(-20.0, min(20.0, inputTrim))
        self.outputTrim = max(-20.0, min(20.0, outputTrim))
    }
}

// MARK: - Channel Strip Display Mode
// MARK: - I/O Routing Configuration
enum TrackInputSource: Codable, Equatable, Hashable {
    case none                           // No input (playback only)
    case systemDefault                  // Default system input device
    case input(channel: Int)            // Specific input channel (1, 2, 3, etc.)
    case stereoInput(left: Int, right: Int)  // Stereo pair
    case busReturn(busId: UUID)         // Return from a bus
    
    var displayName: String {
        switch self {
        case .none: return "No Input"
        case .systemDefault: return "System Input"
        case .input(let channel): return "Input \(channel)"
        case .stereoInput(let left, let right): return "Input \(left)/\(right)"
        case .busReturn: return "Bus Return"
        }
    }
    
    var shortName: String {
        switch self {
        case .none: return "—"
        case .systemDefault: return "Sys"
        case .input(let channel): return "In \(channel)"
        case .stereoInput(let left, let right): return "\(left)/\(right)"
        case .busReturn: return "Bus"
        }
    }
}

enum TrackOutputDestination: Codable, Equatable, Hashable {
    case stereoOut                      // Main stereo output (default)
    case bus(busId: UUID)               // Route to a specific bus
    case output(channel: Int)           // Direct hardware output
    case stereoOutput(left: Int, right: Int)  // Stereo hardware output pair
    
    var displayName: String {
        switch self {
        case .stereoOut: return "Stereo Out"
        case .bus: return "Bus"
        case .output(let channel): return "Output \(channel)"
        case .stereoOutput(let left, let right): return "Output \(left)/\(right)"
        }
    }
    
    var shortName: String {
        switch self {
        case .stereoOut: return "St Out"
        case .bus: return "Bus"
        case .output(let channel): return "Out \(channel)"
        case .stereoOutput(let left, let right): return "\(left)/\(right)"
        }
    }
}

// MARK: - Sidechain Source Configuration
enum SidechainSource: Codable, Equatable, Hashable {
    case none                           // No sidechain (disabled)
    case track(trackId: UUID)           // Another track's post-fader output
    case trackPreFader(trackId: UUID)   // Another track's pre-fader output
    case bus(busId: UUID)               // A bus output
    case externalInput(channel: Int)    // External hardware input
    
    var displayName: String {
        switch self {
        case .none: return "None"
        case .track: return "Track"
        case .trackPreFader: return "Track (Pre)"
        case .bus: return "Bus"
        case .externalInput(let channel): return "Input \(channel)"
        }
    }
    
    var isEnabled: Bool {
        switch self {
        case .none: return false
        default: return true
        }
    }
}

// MARK: - Plugin Slot with Sidechain
/// Represents a plugin slot with optional sidechain routing
struct PluginSlotConfig: Codable, Equatable {
    let pluginDescriptorId: UUID?       // Reference to PluginDescriptor (nil = empty slot)
    var isBypassed: Bool
    var sidechainSource: SidechainSource
    var presetData: Data?               // Saved plugin state
    
    init() {
        self.pluginDescriptorId = nil
        self.isBypassed = false
        self.sidechainSource = .none
        self.presetData = nil
    }
    
    init(pluginDescriptorId: UUID, isBypassed: Bool = false, sidechainSource: SidechainSource = .none) {
        self.pluginDescriptorId = pluginDescriptorId
        self.isBypassed = isBypassed
        self.sidechainSource = sidechainSource
        self.presetData = nil
    }
}

// MARK: - Channel Strip Display Settings
enum ChannelStripWidth: String, Codable, CaseIterable {
    case narrow = "Narrow"      // 60px - Minimal: fader + M/S only
    case standard = "Standard"  // 90px - Default view
    case wide = "Wide"          // 120px - Full controls visible
    
    var width: CGFloat {
        switch self {
        case .narrow: return 60
        case .standard: return 90
        case .wide: return 120
        }
    }
}

// MARK: - Channel Strip Section
enum ChannelStripSection: String, Codable, CaseIterable, Hashable {
    case io = "I/O"
    case inserts = "Inserts"
    case eq = "EQ"
    case sends = "Sends"
    
    var icon: String {
        switch self {
        case .io: return "arrow.left.arrow.right"
        case .inserts: return "fx"
        case .eq: return "slider.horizontal.3"
        case .sends: return "arrow.triangle.branch"
        }
    }
}

// MARK: - Clip Effect (Per-Region Processing)

/// Effect configuration for clip-level (per-region) processing.
/// Unlike track-level effects, clip effects only apply to a specific audio region.
/// Processed before the audio enters the track's plugin chain.
struct ClipEffect: Identifiable, Codable, Equatable {
    let id: UUID
    
    /// Type of effect (uses PluginDescriptor for AU plugins)
    var effectType: ClipEffectType
    
    /// Whether this effect is enabled
    var isEnabled: Bool
    
    /// Whether the effect is bypassed (different from disabled - bypassed still shows in chain)
    var isBypassed: Bool
    
    /// Effect parameters (for built-in effects)
    var parameters: [String: Float]
    
    /// Full AU state data (for AU plugin effects)
    var auStateData: Data?
    
    init(effectType: ClipEffectType, parameters: [String: Float] = [:]) {
        self.id = UUID()
        self.effectType = effectType
        self.isEnabled = true
        self.isBypassed = false
        self.parameters = parameters
        self.auStateData = nil
    }
}

/// Types of effects available at the clip level.
/// Includes built-in effects optimized for per-region processing.
enum ClipEffectType: Codable, Equatable {
    /// Pitch shift (semitones)
    case pitchShift(semitones: Float)
    
    /// Time stretch (ratio, 1.0 = original speed)
    case timeStretch(ratio: Float)
    
    /// Gain adjustment (dB)
    case gain(dB: Float)
    
    /// High-pass filter
    case highPassFilter(frequencyHz: Float)
    
    /// Low-pass filter
    case lowPassFilter(frequencyHz: Float)
    
    /// Polarity invert (phase flip)
    case polarityInvert
    
    /// Reverse playback
    case reverse
    
    /// Audio Unit plugin effect
    case audioUnit(descriptor: PluginDescriptor)
    
    /// Display name for UI
    var displayName: String {
        switch self {
        case .pitchShift(let semitones):
            return "Pitch Shift (\(String(format: "%.1f", semitones)) st)"
        case .timeStretch(let ratio):
            return "Time Stretch (\(String(format: "%.2fx", ratio)))"
        case .gain(let dB):
            return "Gain (\(String(format: "%.1f", dB)) dB)"
        case .highPassFilter(let freq):
            return "HP Filter (\(Int(freq)) Hz)"
        case .lowPassFilter(let freq):
            return "LP Filter (\(Int(freq)) Hz)"
        case .polarityInvert:
            return "Polarity Invert"
        case .reverse:
            return "Reverse"
        case .audioUnit(let descriptor):
            return descriptor.name
        }
    }
    
    /// System icon for UI
    var iconName: String {
        switch self {
        case .pitchShift: return "arrow.up.arrow.down"
        case .timeStretch: return "timer"
        case .gain: return "speaker.wave.3"
        case .highPassFilter, .lowPassFilter: return "waveform"
        case .polarityInvert: return "arrow.up.and.down.circle"
        case .reverse: return "arrow.uturn.backward"
        case .audioUnit: return "puzzlepiece.extension"
        }
    }
}

// MARK: - AU Plugin Configuration (for persistence)

/// Stores AU plugin configuration for project persistence
struct PluginConfiguration: Identifiable, Codable, Equatable {
    let id: UUID
    var slotIndex: Int
    
    // AU Component identification (uses existing Codable wrapper from PluginModels)
    var componentDescription: AudioComponentDescriptionCodable
    
    // Plugin metadata
    var pluginName: String
    var manufacturerName: String
    
    // State
    var isBypassed: Bool
    var fullState: Data?  // Serialized AU fullState dictionary (PropertyList)
    
    init(slotIndex: Int, componentDescription: AudioComponentDescriptionCodable,
         pluginName: String, manufacturerName: String, isBypassed: Bool = false, fullState: Data? = nil) {
        self.id = UUID()
        self.slotIndex = slotIndex
        self.componentDescription = componentDescription
        self.pluginName = pluginName
        self.manufacturerName = manufacturerName
        self.isBypassed = isBypassed
        self.fullState = fullState
    }
    
    /// Create from a PluginDescriptor and current state
    init(slotIndex: Int, descriptor: PluginDescriptor, isBypassed: Bool = false, fullState: Data? = nil) {
        self.id = UUID()
        self.slotIndex = slotIndex
        self.componentDescription = descriptor.componentDescription
        self.pluginName = descriptor.name
        self.manufacturerName = descriptor.manufacturer
        self.isBypassed = isBypassed
        self.fullState = fullState
    }
}

// MARK: - Transport State
enum TransportState: Codable {
    case stopped
    case playing
    case recording
    case paused
    
    var isPlaying: Bool {
        self == .playing || self == .recording
    }
}

// MARK: - Playback Position

/// Represents the current playback position in musical time.
/// Beats are the source of truth - all other values are derived.
struct PlaybackPosition: Codable {
    /// Primary time unit - beats (quarter notes)
    var beats: Double
    
    /// Bar number (0-indexed internally, displayed as 1-indexed)
    var bars: Int
    
    /// Beat within the current bar (1-indexed)
    var beatInBar: Int
    
    /// The time signature used for bar/beat calculation
    private var timeSignatureNumerator: Int = 4
    
    // MARK: - Beats-First Initialization (Primary)
    
    /// Initialize from beats (beats are the source of truth, time is always computed)
    init(beats: Double = 0, timeSignature: TimeSignature = .fourFour, tempo: Double = 120.0) {
        self.beats = beats
        self.timeSignatureNumerator = timeSignature.numerator
        self.bars = Int(beats / Double(timeSignature.numerator))
        self.beatInBar = Int(beats.truncatingRemainder(dividingBy: Double(timeSignature.numerator))) + 1
        // NOTE: tempo parameter is kept for API compatibility but not cached
        // Use timeInterval(atTempo:) to convert beats to seconds
    }
    
    // MARK: - Seconds Conversion (for AVAudioEngine boundary)
    
    /// Get time interval in seconds at a specific tempo
    /// IMPORTANT: Always provide the current project tempo to get accurate time values
    func timeInterval(atTempo tempo: Double) -> TimeInterval {
        beats * (60.0 / tempo)
    }
    
    /// Create from seconds - use only when receiving time from AVAudioEngine
    static func fromSeconds(_ seconds: TimeInterval, tempo: Double, timeSignature: TimeSignature = .fourFour) -> PlaybackPosition {
        let beats = seconds * (tempo / 60.0)
        return PlaybackPosition(beats: beats, timeSignature: timeSignature, tempo: tempo)
    }
    
    // MARK: - BeatPosition Conversion
    
    /// Convert to BeatPosition
    var beatPosition: BeatPosition {
        BeatPosition(beats)
    }
    
    /// Initialize from BeatPosition
    init(beatPosition: BeatPosition, timeSignature: TimeSignature = .fourFour) {
        self.init(beats: beatPosition.beats, timeSignature: timeSignature)
    }
    
    // MARK: - Display
    
    func displayString(timeSignature: TimeSignature) -> String {
        let subdivision = Int((beats.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d.%d.%02d", bars + 1, beatInBar, subdivision)
    }
    
    /// Convenience display using stored time signature
    var displayStringDefault: String {
        let subdivision = Int((beats.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d.%d.%02d", bars + 1, beatInBar, subdivision)
    }
}

// MARK: - Effects Models

// MARK: - Mixer Bus
struct MixerBus: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var inputLevel: Double
    var outputLevel: Double
    var pluginConfigs: [PluginConfiguration]  // AU plugins for buses (consistent with tracks)
    var isMuted: Bool
    var isSolo: Bool
    var createdAt: Date
    
    init(
        name: String,
        inputLevel: Double = 0.0,
        outputLevel: Double = 0.75
    ) {
        self.id = UUID()
        self.name = name
        self.inputLevel = inputLevel
        self.outputLevel = outputLevel
        self.pluginConfigs = []
        self.isMuted = false
        self.isSolo = false
        self.createdAt = Date()
    }
}

// MARK: - Track Grouping
/// Represents a group of tracks with linked parameters
struct TrackGroup: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String
    var linkedParameters: Set<GroupLinkedParameter>
    var isEnabled: Bool
    
    /// SwiftUI Color accessor
    var color: Color {
        get { Color(hex: colorHex) ?? .purple }
        set { colorHex = newValue.toHex() }
    }
    
    init(name: String, color: Color = .purple, linkedParameters: Set<GroupLinkedParameter> = [.volume, .mute, .solo]) {
        self.id = UUID()
        self.name = name
        self.colorHex = color.toHex()
        self.linkedParameters = linkedParameters
        self.isEnabled = true
    }
}

/// Parameters that can be linked within a track group
enum GroupLinkedParameter: String, Codable, CaseIterable {
    case volume = "Volume"
    case pan = "Pan"
    case mute = "Mute"
    case solo = "Solo"
    case record = "Record"
    case automation = "Automation Mode"
}

// Track Send
struct TrackSend: Identifiable, Codable, Equatable {
    let id: UUID
    let busId: UUID
    var sendLevel: Double
    var isPreFader: Bool
    var pan: Float  // -1.0 (left) to 1.0 (right), 0.0 = center
    var isMuted: Bool  // Mute this individual send
    
    init(busId: UUID, sendLevel: Double = 0.0, isPreFader: Bool = false, pan: Float = 0.0, isMuted: Bool = false) {
        self.id = UUID()
        self.busId = busId
        self.sendLevel = sendLevel
        self.isPreFader = isPreFader
        self.pan = pan
        self.isMuted = isMuted
    }
}

// MARK: - Image Generation (Phase 5)
/// Represents a generated image for a track with metadata
struct ImageGeneration: Identifiable, Codable, Equatable {
    let id: UUID
    var prompt: String
    var enhancedPrompt: String?  // LLM-enhanced version of prompt
    var imagePath: String  // Relative path within project bundle
    var width: Int
    var height: Int
    var model: String  // e.g., "SDXL-Turbo"
    var generationTime: TimeInterval  // Time taken to generate
    var timestamp: Date
    
    init(
        prompt: String,
        enhancedPrompt: String? = nil,
        imagePath: String,
        width: Int = 1024,
        height: Int = 1024,
        model: String = "SDXL-Turbo",
        generationTime: TimeInterval
    ) {
        self.id = UUID()
        self.prompt = prompt
        self.enhancedPrompt = enhancedPrompt
        self.imagePath = imagePath
        self.width = width
        self.height = height
        self.model = model
        self.generationTime = generationTime
        self.timestamp = Date()
    }
    
    var displayDimensions: String {
        "\(width) × \(height)"
    }
    
    var displayGenerationTime: String {
        String(format: "%.1fs", generationTime)
    }
    
    var thumbnailURL: URL {
        URL(fileURLWithPath: imagePath)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}
