//
//  AudioModels.swift
//  TellUrStoriDAW
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
enum TrackColor: String, Codable, CaseIterable {
    case blue = "#3B82F6"
    case red = "#EF4444"
    case green = "#10B981"
    case yellow = "#F59E0B"
    case purple = "#8B5CF6"
    case pink = "#EC4899"
    case orange = "#F97316"
    case teal = "#14B8A6"
    case indigo = "#6366F1"
    case gray = "#6B7280"
    
    var color: Color {
        Color(hex: self.rawValue)
    }
}

// MARK: - Time Signature
struct TimeSignature: Codable, Equatable {
    var numerator: Int
    var denominator: Int
    
    static let fourFour = TimeSignature(numerator: 4, denominator: 4)
    static let threeFour = TimeSignature(numerator: 3, denominator: 4)
    
    // TODO do we need both?
    var description: String {
        "\(numerator)/\(denominator)"
    }
    
    var displayString: String {
        "\(numerator)/\(denominator)"
    }
}

// MARK: - Audio Project
struct AudioProject: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var tracks: [AudioTrack]
    var buses: [MixerBus]
    var tempo: Double
    var keySignature: String
    var timeSignature: TimeSignature
    var sampleRate: Double
    var bufferSize: Int
    var createdAt: Date
    var modifiedAt: Date
    
    init(
        name: String,
        tempo: Double = 120.0,
        keySignature: String = "C",
        timeSignature: TimeSignature = .fourFour,
        sampleRate: Double = 44100.0,
        bufferSize: Int = 512
    ) {
        self.id = UUID()
        self.name = name
        self.tracks = []
        self.buses = []
        self.tempo = tempo
        self.keySignature = keySignature
        self.timeSignature = timeSignature
        self.sampleRate = sampleRate
        self.bufferSize = bufferSize
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
    
    var duration: TimeInterval {
        tracks.compactMap { $0.duration }.max() ?? 0
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
    var effects: [AudioEffect]
    var sends: [TrackSend]
    var trackType: TrackType
    var color: TrackColor
    var isFrozen: Bool
    var isEnabled: Bool
    var createdAt: Date
    
    init(name: String, trackType: TrackType = .audio, color: TrackColor = .blue) {
        self.id = UUID()
        self.name = name
        self.regions = []
        self.mixerSettings = MixerSettings()
        self.effects = []
        self.sends = []
        self.trackType = trackType
        self.color = color
        self.isFrozen = false
        self.isEnabled = true
        self.createdAt = Date()
    }
    
    var duration: TimeInterval? {
        guard !regions.isEmpty else { return nil }
        return regions.map { $0.endTime }.max()
    }
    
    var hasAudio: Bool {
        !regions.isEmpty
    }
    
    mutating func addRegion(_ region: AudioRegion) {
        regions.append(region)
    }
    
    mutating func removeRegion(withId id: UUID) {
        regions.removeAll { $0.id == id }
    }
}

// MARK: - Audio Region
struct AudioRegion: Identifiable, Codable, Equatable {
    let id: UUID
    var audioFile: AudioFile
    var startTime: TimeInterval
    var duration: TimeInterval
    var fadeIn: TimeInterval
    var fadeOut: TimeInterval
    var gain: Float
    var isLooped: Bool
    var offset: TimeInterval // Offset within the audio file
    
    init(
        audioFile: AudioFile,
        startTime: TimeInterval = 0,
        duration: TimeInterval? = nil,
        fadeIn: TimeInterval = 0,
        fadeOut: TimeInterval = 0,
        gain: Float = 1.0,
        isLooped: Bool = false,
        offset: TimeInterval = 0
    ) {
        self.id = UUID()
        self.audioFile = audioFile
        self.startTime = startTime
        self.duration = duration ?? audioFile.duration
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.gain = gain
        self.isLooped = isLooped
        self.offset = offset
    }
    
    var endTime: TimeInterval {
        startTime + duration
    }
    
    var displayName: String {
        audioFile.name
    }
}

// MARK: - Audio File
struct AudioFile: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let url: URL
    let duration: TimeInterval
    let sampleRate: Double
    let channels: Int
    let bitDepth: Int
    let fileSize: Int64
    let format: AudioFileFormat
    let createdAt: Date
    
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
        self.url = url
        self.duration = duration
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitDepth = bitDepth
        self.fileSize = fileSize
        self.format = format
        self.createdAt = Date()
    }
    
    var displayDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - Audio File Format
enum AudioFileFormat: String, Codable, CaseIterable {
    case wav = "wav"
    case aiff = "aiff"
    case mp3 = "mp3"
    case m4a = "m4a"
    case flac = "flac"
    
    var displayName: String {
        switch self {
        case .wav: return "WAV"
        case .aiff: return "AIFF"
        case .mp3: return "MP3"
        case .m4a: return "M4A"
        case .flac: return "FLAC"
        }
    }
    
    var isLossless: Bool {
        switch self {
        case .wav, .aiff, .flac: return true
        case .mp3, .m4a: return false
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
    
    init(
        volume: Float = 0.8,
        pan: Float = 0.0,
        highEQ: Float = 0.0,
        midEQ: Float = 0.0,
        lowEQ: Float = 0.0,
        sendLevel: Float = 0.0,
        isMuted: Bool = false,
        isSolo: Bool = false,
        isRecordEnabled: Bool = false,
        inputMonitoring: Bool = false
    ) {
        self.volume = volume
        self.pan = pan
        self.highEQ = highEQ
        self.midEQ = midEQ
        self.lowEQ = lowEQ
        self.sendLevel = sendLevel
        self.isMuted = isMuted
        self.isSolo = isSolo
        self.isRecordEnabled = isRecordEnabled
        self.inputMonitoring = inputMonitoring
    }
}

// MARK: - Audio Effect
struct AudioEffect: Identifiable, Codable, Equatable {
    let id: UUID
    let type: EffectType
    var parameters: [String: Float]
    var isEnabled: Bool
    var bypass: Bool
    
    init(type: EffectType, parameters: [String: Float] = [:]) {
        self.id = UUID()
        self.type = type
        self.parameters = parameters
        self.isEnabled = true
        self.bypass = false
    }
}

// MARK: - Audio Effect Type (replaced by EffectType below)

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
struct PlaybackPosition: Codable {
    var timeInterval: TimeInterval
    var beats: Double
    var bars: Int
    var beatInBar: Int
    
    init(timeInterval: TimeInterval = 0, tempo: Double = 120, timeSignature: TimeSignature = .fourFour) {
        self.timeInterval = timeInterval
        
        // Calculate musical time
        let beatsPerSecond = tempo / 60.0
        let totalBeats = timeInterval * beatsPerSecond
        
        self.beats = totalBeats
        self.bars = Int(totalBeats / Double(timeSignature.numerator))
        self.beatInBar = Int(totalBeats.truncatingRemainder(dividingBy: Double(timeSignature.numerator))) + 1
    }
    
    func displayString(timeSignature: TimeSignature) -> String {
        "\(bars + 1).\(beatInBar).\(Int((beats.truncatingRemainder(dividingBy: 1)) * 100))"
    }
}

// MARK: - Effects Models

// Effect Type
enum EffectType: String, Codable, CaseIterable {
    case reverb = "reverb"
    case delay = "delay"
    case chorus = "chorus"
    case compressor = "compressor"
    case eq = "eq"
    case distortion = "distortion"
    case filter = "filter"
    case modulation = "modulation"
    
    var displayName: String {
        switch self {
        case .reverb: return "Reverb"
        case .delay: return "Delay"
        case .chorus: return "Chorus"
        case .compressor: return "Compressor"
        case .eq: return "EQ"
        case .distortion: return "Distortion"
        case .filter: return "Filter"
        case .modulation: return "Modulation"
        }
    }
    
    var defaultParameters: [String: Double] {
        switch self {
        case .reverb:
            return [
                "wetLevel": 30.0,
                "dryLevel": 70.0,
                "roomSize": 50.0,
                "decayTime": 2.0,
                "predelay": 0.0
            ]
        case .delay:
            return [
                "delayTime": 250.0,
                "feedback": 25.0,
                "lowCut": 100.0,
                "highCut": 8000.0,
                "dryLevel": 70.0,
                "wetLevel": 30.0
            ]
        case .chorus:
            return [
                "rate": 2.0,
                "depth": 50.0,
                "voices": 4.0,
                "spread": 180.0,
                "dryLevel": 70.0,
                "wetLevel": 30.0
            ]
        case .compressor:
            return [
                "threshold": -12.0,
                "ratio": 4.0,
                "attack": 10.0,
                "release": 100.0,
                "makeupGain": 0.0,
                "knee": 2.0
            ]
        case .eq:
            return [
                "lowGain": 0.0,
                "lowFreq": 100.0,
                "lowMidGain": 0.0,
                "highMidGain": 0.0,
                "highGain": 0.0,
                "highFreq": 10000.0
            ]
        case .distortion:
            return [
                "drive": 25.0,
                "tone": 50.0,
                "output": 0.0
            ]
        case .filter:
            return [
                "cutoff": 1000.0,
                "resonance": 10.0,
                "filterType": 0.0 // 0 = Low Pass, 1 = High Pass, 2 = Band Pass
            ]
        case .modulation:
            return [
                "rate": 1.0,
                "depth": 25.0,
                "feedback": 10.0,
                "wetLevel": 30.0
            ]
        }
    }
}

// Mixer Bus
struct MixerBus: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var inputLevel: Double
    var outputLevel: Double
    var effects: [BusEffect]
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
        self.effects = []
        self.isMuted = false
        self.isSolo = false
        self.createdAt = Date()
    }
}

// Bus Effect
struct BusEffect: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let type: EffectType
    var isEnabled: Bool
    var parameters: [String: Double]
    var presetName: String
    
    init(
        name: String,
        type: EffectType,
        parameters: [String: Double] = [:],
        presetName: String = "Default"
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.isEnabled = true
        self.parameters = parameters
        self.presetName = presetName
    }
}

// Track Send
struct TrackSend: Identifiable, Codable, Equatable {
    let id: UUID
    let busId: UUID
    var sendLevel: Double
    var isPreFader: Bool
    
    init(busId: UUID, sendLevel: Double = 0.0, isPreFader: Bool = false) {
        self.id = UUID()
        self.busId = busId
        self.sendLevel = sendLevel
        self.isPreFader = isPreFader
    }
}
