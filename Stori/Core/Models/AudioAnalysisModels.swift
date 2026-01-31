//
//  AudioAnalysisModels.swift
//  Stori
//
//  Models for audio analysis results (tempo, key, chroma, etc.)
//

import Foundation

/// Result of analyzing an audio file or region.
struct AnalysisResult: Codable, Equatable {
    /// Estimated global tempo in BPM (if detected).
    var tempo: Double?
    
    /// Confidence for the tempo estimate in [0, 1].
    var tempoConfidence: Float?
    
    /// Estimated key as a string, e.g. "C Major", "A Minor".
    var key: String?
    
    /// Confidence for the key estimate in [0, 1].
    var keyConfidence: Float?
    
    /// How long the analysis took (seconds).
    var analysisTime: TimeInterval
    
    /// Whether the minimum duration threshold for reliable analysis was met.
    var minimumDurationMet: Bool
    
    /// Optional normalized chroma vector (12 bins, C..B).
    /// Only populated if key analysis runs.
    var chroma: [Float]?
    
    /// Optional tempo map for future advanced features (per-time BPM).
    var tempoMap: [TempoEvent]?
    
    /// Beat positions in seconds (derived from tempo). Used for beat grid visualization.
    var beats: [TimeInterval]?
    
    /// Indices of downbeats (first beat of each measure) within the beats array.
    var downbeatIndices: [Int]?
    
    struct TempoEvent: Codable, Equatable {
        /// Time (in seconds from region start).
        var time: TimeInterval
        /// Tempo (BPM) starting at `time`.
        var bpm: Double
    }
    
    /// Convenience empty result.
    static let empty = AnalysisResult(
        tempo: nil,
        tempoConfidence: nil,
        key: nil,
        keyConfidence: nil,
        analysisTime: 0,
        minimumDurationMet: false,
        chroma: nil,
        tempoMap: nil,
        beats: nil,
        downbeatIndices: nil
    )
}

