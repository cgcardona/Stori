//
//  AudioAnalysisService.swift
//  TellUrStoriDAW
//
//  Audio analysis service for BPM and key detection (Phase 2 scaffolding)
//

import Foundation
import AVFoundation
import Accelerate

@MainActor
final class AudioAnalysisService: ObservableObject {

    struct MatchingSuggestion {
        let targetTempo: Double
        let targetKey: String
        let adjustments: [UUID: (pitchShiftCents: Float, tempoRate: Float)]
    }
    
    struct AnalysisResult {
        let tempo: Double?
        let key: String?
        let confidence: Float
        let analysisTime: TimeInterval
    }

    // MARK: - Cache Management
    private var tempoCache: [UUID: Double] = [:]
    private var keyCache: [UUID: String] = [:]
    private var analysisCache: [UUID: AnalysisResult] = [:]
    
    // MARK: - Audio Analysis Constants
    private let sampleRate: Double = 44100.0
    private let fftSize = 2048
    private let hopSize = 512
    private let minTempo: Double = 60.0
    private let maxTempo: Double = 200.0
    
    // MARK: - Key Detection Constants
    private let chromaKeys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    // MARK: - Public API
    func detectTempo(_ file: AudioFile) async -> Double? {
        if let cached = tempoCache[file.id] { 
            print("🎵 TEMPO: Using cached tempo \(cached) BPM for \(file.name)")
            return cached 
        }
        
        print("🎵 TEMPO: Analyzing \(file.name)...")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let tempo = try await performTempoAnalysis(file: file)
            let analysisTime = CFAbsoluteTimeGetCurrent() - startTime
            
            if let tempo = tempo {
                tempoCache[file.id] = tempo
                print("🎵 TEMPO: Detected \(String(format: "%.1f", tempo)) BPM for \(file.name) (took \(String(format: "%.2f", analysisTime))s)")
            } else {
                print("🎵 TEMPO: Could not detect tempo for \(file.name)")
            }
            
            return tempo
        } catch {
            print("🎵 TEMPO: Error analyzing \(file.name): \(error)")
            return nil
        }
    }

    func detectKey(_ file: AudioFile) async -> String? {
        if let cached = keyCache[file.id] { 
            print("🎵 KEY: Using cached key \(cached) for \(file.name)")
            return cached 
        }
        
        print("🎵 KEY: Analyzing \(file.name)...")
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let key = try await performKeyAnalysis(file: file)
            let analysisTime = CFAbsoluteTimeGetCurrent() - startTime
            
            if let key = key {
                keyCache[file.id] = key
                print("🎵 KEY: Detected \(key) for \(file.name) (took \(String(format: "%.2f", analysisTime))s)")
            } else {
                print("🎵 KEY: Could not detect key for \(file.name)")
            }
            
            return key
        } catch {
            print("🎵 KEY: Error analyzing \(file.name): \(error)")
            return nil
        }
    }
    
    func analyzeRegions(_ regionIds: Set<UUID>) async -> [UUID: (tempo: Double?, key: String?)] {
        print("🎵 ANALYSIS: Batch analyzing \(regionIds.count) regions...")
        let results: [UUID: (tempo: Double?, key: String?)] = [:]
        
        // For now, return empty results - this would be implemented with actual region data
        // TODO: Implement batch analysis with region file access
        
        return results
    }

    func suggestMatching(_ regions: [AudioRegion], projectTempo: Double, projectKey: String) async -> MatchingSuggestion {
        print("🎵 MATCHING: Generating suggestions for \(regions.count) regions...")
        
        // Use project settings as default target
        var targetTempo = projectTempo
        var targetKey = projectKey
        
        // If we have analyzed regions, use the first one as reference
        if let firstRegion = regions.first,
           let detectedTempo = firstRegion.detectedTempo {
            targetTempo = detectedTempo
        }
        
        if let firstRegion = regions.first,
           let detectedKey = firstRegion.detectedKey {
            targetKey = detectedKey
        }
        
        // Calculate adjustments for each region
        var adjustments: [UUID: (pitchShiftCents: Float, tempoRate: Float)] = [:]
        
        for region in regions {
            let tempoRate: Float
            let pitchShift: Float = 0.0 // Key matching not implemented yet
            
            if let regionTempo = region.detectedTempo {
                tempoRate = Float(targetTempo / regionTempo)
            } else {
                tempoRate = 1.0
            }
            
            adjustments[region.id] = (pitchShift, tempoRate)
        }
        
        print("🎵 MATCHING: Target tempo: \(targetTempo) BPM, key: \(targetKey)")
        
        return MatchingSuggestion(
            targetTempo: targetTempo,
            targetKey: targetKey,
            adjustments: adjustments
        )
    }
    
    // MARK: - Clear Cache
    func clearCache() {
        tempoCache.removeAll()
        keyCache.removeAll()
        analysisCache.removeAll()
        print("🎵 CACHE: Cleared analysis cache")
    }
    
    // MARK: - Private Analysis Methods
    
    private func performTempoAnalysis(file: AudioFile) async throws -> Double? {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    // Load audio file
                    let audioFile = try AVAudioFile(forReading: file.url)
                    let format = audioFile.processingFormat
                    let frameCount = AVAudioFrameCount(audioFile.length)
                    
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    try audioFile.read(into: buffer)
                    
                    // Perform tempo analysis using onset detection + autocorrelation
                    let tempo = await self.analyzeTempoFromBuffer(buffer)
                    continuation.resume(returning: tempo)
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func performKeyAnalysis(file: AudioFile) async throws -> String? {
        return try await withCheckedThrowingContinuation { continuation in
            Task.detached {
                do {
                    // Load audio file
                    let audioFile = try AVAudioFile(forReading: file.url)
                    let format = audioFile.processingFormat
                    let frameCount = AVAudioFrameCount(audioFile.length)
                    
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    try audioFile.read(into: buffer)
                    
                    // Perform key analysis using chroma features + template matching
                    let key = await self.analyzeKeyFromBuffer(buffer)
                    continuation.resume(returning: key)
                    
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    @MainActor
    private func analyzeTempoFromBuffer(_ buffer: AVAudioPCMBuffer) async -> Double? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(buffer.frameLength)
        
        // Simple onset detection using spectral flux
        let onsets = detectOnsets(channelData, frameCount: frameCount, sampleRate: Float(buffer.format.sampleRate))
        
        if onsets.count < 4 {
            print("🎵 TEMPO: Not enough onsets detected (\(onsets.count))")
            return nil
        }
        
        // Calculate inter-onset intervals
        var intervals: [Double] = []
        for i in 1..<onsets.count {
            let interval = onsets[i] - onsets[i-1]
            if interval > 0.2 && interval < 2.0 { // Filter reasonable intervals (30-300 BPM)
                intervals.append(interval)
            }
        }
        
        if intervals.isEmpty {
            print("🎵 TEMPO: No valid intervals found")
            return nil
        }
        
        // Find most common interval using histogram
        let tempo = findDominantTempo(from: intervals)
        
        // Validate tempo range
        if tempo >= minTempo && tempo <= maxTempo {
            return tempo
        } else {
            print("🎵 TEMPO: Detected tempo \(tempo) outside valid range (\(minTempo)-\(maxTempo))")
            return nil
        }
    }
    
    @MainActor
    private func analyzeKeyFromBuffer(_ buffer: AVAudioPCMBuffer) async -> String? {
        guard let channelData = buffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(buffer.frameLength)
        
        // Extract chroma features
        let chromaVector = extractChromaFeatures(channelData, frameCount: frameCount, sampleRate: Float(buffer.format.sampleRate))
        
        // Template matching with major/minor profiles
        var bestKey = "C Major"
        var bestScore: Float = -Float.infinity
        
        for (i, key) in chromaKeys.enumerated() {
            // Test major key
            let majorScore = correlateWithTemplate(chromaVector, template: shiftTemplate(majorProfile, shift: i))
            if majorScore > bestScore {
                bestScore = majorScore
                bestKey = "\(key) Major"
            }
            
            // Test minor key
            let minorScore = correlateWithTemplate(chromaVector, template: shiftTemplate(minorProfile, shift: i))
            if minorScore > bestScore {
                bestScore = minorScore
                bestKey = "\(key) Minor"
            }
        }
        
        // Only return if confidence is reasonable
        return bestScore > 0.3 ? bestKey : nil
    }
    
    // MARK: - Signal Processing Helpers
    
    private func detectOnsets(_ samples: UnsafePointer<Float>, frameCount: Int, sampleRate: Float) -> [Double] {
        var onsets: [Double] = []
        let windowSize = 1024
        let hopSize = 512
        
        var previousSpectralEnergy: Float = 0
        
        for windowStart in stride(from: 0, to: frameCount - windowSize, by: hopSize) {
            let windowEnd = min(windowStart + windowSize, frameCount)
            let windowSamples = Array(UnsafeBufferPointer(start: samples + windowStart, count: windowEnd - windowStart))
            
            // Calculate spectral energy
            let spectralEnergy = windowSamples.map { $0 * $0 }.reduce(0, +)
            
            // Detect onset as significant increase in spectral energy
            if spectralEnergy > previousSpectralEnergy * 1.5 && spectralEnergy > 0.001 {
                let timeStamp = Double(windowStart) / Double(sampleRate)
                onsets.append(timeStamp)
            }
            
            previousSpectralEnergy = spectralEnergy
        }
        
        return onsets
    }
    
    private func findDominantTempo(from intervals: [Double]) -> Double {
        // Convert intervals to BPM
        let bpms = intervals.map { 60.0 / $0 }
        
        // Create histogram bins
        let binSize: Double = 2.0
        var histogram: [Double: Int] = [:]
        
        for bpm in bpms {
            let bin = round(bpm / binSize) * binSize
            histogram[bin, default: 0] += 1
        }
        
        // Find most frequent BPM
        let dominantBin = histogram.max { $0.value < $1.value }?.key ?? 120.0
        return dominantBin
    }
    
    private func extractChromaFeatures(_ samples: UnsafePointer<Float>, frameCount: Int, sampleRate: Float) -> [Float] {
        // Simplified chroma extraction - in a real implementation, this would use FFT and pitch class mapping
        var chroma = Array(repeating: Float(0), count: 12)
        
        // This is a placeholder - real chroma extraction requires:
        // 1. FFT analysis
        // 2. Frequency to pitch class mapping
        // 3. Accumulation over time
        
        // For now, return a normalized random-ish distribution based on audio content
        let energy = Array(UnsafeBufferPointer(start: samples, count: min(frameCount, 44100))).map { abs($0) }.reduce(0, +)
        let seed = Int(energy * 1000) % 12
        
        for i in 0..<12 {
            chroma[i] = Float.random(in: 0.1...1.0) * (i == seed ? 2.0 : 1.0)
        }
        
        // Normalize
        let sum = chroma.reduce(0, +)
        return chroma.map { $0 / sum }
    }
    
    private func shiftTemplate(_ template: [Float], shift: Int) -> [Float] {
        var shifted = Array(repeating: Float(0), count: template.count)
        for i in 0..<template.count {
            shifted[(i + shift) % template.count] = template[i]
        }
        return shifted
    }
    
    private func correlateWithTemplate(_ chroma: [Float], template: [Float]) -> Float {
        guard chroma.count == template.count else { return 0 }
        
        var correlation: Float = 0
        for i in 0..<chroma.count {
            correlation += chroma[i] * template[i]
        }
        
        return correlation
    }
}
