//
//  AudioAnalysisService.swift
//  Stori
//
//  Audio analysis service for BPM and key detection (Phase 2 scaffolding)
//

import Foundation
import AVFoundation
import Accelerate
import Combine
import Observation

@Observable
@MainActor
final class AudioAnalysisService {

    struct MatchingSuggestion {
        let targetTempo: Double
        let targetKey: String
        let adjustments: [UUID: (pitchShiftCents: Float, tempoRate: Float)]
    }

    // MARK: - Cache Management
    @ObservationIgnored
    private var tempoCache: [UUID: Double] = [:]
    @ObservationIgnored
    private var keyCache: [UUID: String] = [:]
    @ObservationIgnored
    private var analysisCache: [URL: AnalysisResult] = [:]  // Cache per file URL
    
    // MARK: - Task Lifecycle Management
    
    /// Task references — nonisolated(unsafe) so deinit can cancel them.
    /// These are detached tasks for background audio analysis.
    @ObservationIgnored
    nonisolated(unsafe) private var tempoAnalysisTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private var keyAnalysisTask: Task<Void, Never>?
    
    // MARK: - Audio Analysis Constants
    @ObservationIgnored
    private let sampleRate: Double = 48000.0
    @ObservationIgnored
    private let fftSize = 2048
    @ObservationIgnored
    private let hopSize = 512
    @ObservationIgnored
    private let minTempo: Double = 60.0
    @ObservationIgnored
    private let maxTempo: Double = 200.0
    
    // MARK: - Key Detection Constants
    @ObservationIgnored
    private let chromaKeys = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    @ObservationIgnored
    private let majorProfile: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    @ObservationIgnored
    private let minorProfile: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    // MARK: - Public API (Backwards Compatible Wrappers)
    
    /// Detect tempo for a file (thin wrapper around analyzeFile).
    func detectTempo(_ file: AudioFile) async -> Double? {
        let result = await analyzeFile(at: file.url)
        if let tempo = result.tempo {
            tempoCache[file.id] = tempo
        }
        return result.tempo
    }

    /// Detect key for a file (thin wrapper around analyzeFile).
    func detectKey(_ file: AudioFile) async -> String? {
        let result = await analyzeFile(at: file.url)
        if let key = result.key {
            keyCache[file.id] = key
        }
        return result.key
    }
    
    func analyzeRegions(_ regionIds: Set<UUID>) async -> [UUID: (tempo: Double?, key: String?)] {
        let results: [UUID: (tempo: Double?, key: String?)] = [:]
        
        // For now, return empty results - this would be implemented with actual region data
        // TODO: Implement batch analysis with region file access
        
        return results
    }

    func suggestMatching(_ regions: [AudioRegion], projectTempo: Double, projectKey: String) async -> MatchingSuggestion {
        
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
    }
    
    // MARK: - Private Analysis Methods
    
    private func performTempoAnalysis(file: AudioFile) async throws -> Double? {
        // Resolve URL on MainActor; Task.detached runs off MainActor
        let url = await file.resolvedURL(projectDirectory: nil)
        return try await withCheckedThrowingContinuation { continuation in
            // Cancel any existing tempo analysis task
            tempoAnalysisTask?.cancel()
            tempoAnalysisTask = Task.detached { [weak self] in
                do {
                    // Load audio file (url resolved on MainActor above)
                    let audioFile = try AVAudioFile(forReading: url)
                    let format = audioFile.processingFormat
                    let frameCount = AVAudioFrameCount(audioFile.length)
                    
                    // Validate file has content
                    guard frameCount > 0 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    try audioFile.read(into: buffer)
                    
                    // Perform tempo analysis using onset detection + autocorrelation
                    let tempo = await self?.analyzeTempoFromBuffer(buffer)
                    continuation.resume(returning: tempo)
                    await MainActor.run { self?.tempoAnalysisTask = nil }
                    
                } catch {
                    continuation.resume(throwing: error)
                    await MainActor.run { self?.tempoAnalysisTask = nil }
                }
            }
        }
    }
    
    private func performKeyAnalysis(file: AudioFile) async throws -> String? {
        // Resolve URL on MainActor; Task.detached runs off MainActor
        let url = await file.resolvedURL(projectDirectory: nil)
        return try await withCheckedThrowingContinuation { continuation in
            // Cancel any existing key analysis task
            keyAnalysisTask?.cancel()
            keyAnalysisTask = Task.detached { [weak self] in
                do {
                    // Load audio file (url resolved on MainActor above)
                    let audioFile = try AVAudioFile(forReading: url)
                    let format = audioFile.processingFormat
                    let frameCount = AVAudioFrameCount(audioFile.length)
                    
                    // Validate file has content
                    guard frameCount > 0 else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    try audioFile.read(into: buffer)
                    
                    // Perform key analysis using chroma features + template matching
                    let key = await self?.analyzeKeyFromBuffer(buffer)
                    continuation.resume(returning: key)
                    await MainActor.run { self?.keyAnalysisTask = nil }
                    
                } catch {
                    continuation.resume(throwing: error)
                    await MainActor.run { self?.keyAnalysisTask = nil }
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
            return nil
        }
        
        // Find most common interval using histogram
        let tempo = findDominantTempo(from: intervals)
        
        // Validate tempo range
        if tempo >= minTempo && tempo <= maxTempo {
            return tempo
        } else {
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
        let windowSize = 2048  // Larger window for better frequency resolution
        let hopSize = 512
        
        var spectralFluxHistory: [Float] = []
        let historyLength = 10  // For adaptive thresholding
        
        for windowStart in stride(from: 0, to: frameCount - windowSize, by: hopSize) {
            let windowEnd = min(windowStart + windowSize, frameCount)
            let windowSamples = Array(UnsafeBufferPointer(start: samples + windowStart, count: windowEnd - windowStart))
            
            // Calculate RMS energy (more stable than sum of squares)
            let rmsEnergy = sqrt(windowSamples.map { $0 * $0 }.reduce(0, +) / Float(windowSamples.count))
            
            // Calculate spectral flux (difference from previous frame)
            let spectralFlux: Float
            if let lastEnergy = spectralFluxHistory.last {
                spectralFlux = max(0, rmsEnergy - lastEnergy)  // Only positive changes
            } else {
                spectralFlux = rmsEnergy
            }
            
            spectralFluxHistory.append(rmsEnergy)
            if spectralFluxHistory.count > historyLength {
                spectralFluxHistory.removeFirst()
            }
            
            // Adaptive threshold based on recent history
            let meanFlux = spectralFluxHistory.reduce(0, +) / Float(spectralFluxHistory.count)
            let threshold = meanFlux * 0.3  // Much lower threshold for onset detection
            
            // Detect onset with minimum time separation
            let timeStamp = Double(windowStart) / Double(sampleRate)
            let minOnsetSeparation = 0.1  // Minimum 100ms between onsets
            
            if spectralFlux > threshold && 
               spectralFlux > 0.005 &&  // Lower minimum energy threshold
               (onsets.isEmpty || timeStamp - onsets.last! > minOnsetSeparation) {
                onsets.append(timeStamp)
            }
            
            // Debug: Log first few windows to diagnose thresholding
            if windowStart < 5 * hopSize {
            }
        }
        
        return onsets
    }
    
    private func findDominantTempo(from intervals: [Double]) -> Double {
        // Convert intervals to BPM and filter reasonable range
        let bpms = intervals.map { 60.0 / $0 }.filter { $0 >= 60.0 && $0 <= 200.0 }
        
        guard !bpms.isEmpty else { return 120.0 }
        
        // Create histogram with smaller bins for better accuracy
        let binSize: Double = 1.0
        var histogram: [Double: Int] = [:]
        
        for bpm in bpms {
            let bin = round(bpm / binSize) * binSize
            histogram[bin, default: 0] += 1
        }
        
        // Find most frequent BPM with tie-breaking
        let sortedBins = histogram.sorted { 
            if $0.value == $1.value {
                // Prefer tempos closer to common ranges (120-140 BPM)
                let idealRange = 120.0...140.0
                let dist0 = idealRange.contains($0.key) ? 0 : min(abs($0.key - 120), abs($0.key - 140))
                let dist1 = idealRange.contains($1.key) ? 0 : min(abs($1.key - 120), abs($1.key - 140))
                return dist0 < dist1
            }
            return $0.value > $1.value
        }
        
        return sortedBins.first?.key ?? 120.0
    }
    
    private func extractChromaFeatures(_ samples: UnsafePointer<Float>, frameCount: Int, sampleRate: Float) -> [Float] {
        // Simplified chroma extraction - in a real implementation, this would use FFT and pitch class mapping
        var chroma = Array(repeating: Float(0), count: 12)
        
        // This is a placeholder - real chroma extraction requires:
        // 1. FFT analysis
        // 2. Frequency to pitch class mapping
        // 3. Accumulation over time
        
        // For now, return a normalized random-ish distribution based on audio content
        let energy = Array(UnsafeBufferPointer(start: samples, count: min(frameCount, 48000))).map { abs($0) }.reduce(0, +)
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
    
    // MARK: - Unified Analysis
    
    /// Analyze an audio file at a given URL and return AnalysisResult.
    /// Uses cache when available.
    func analyzeFile(at url: URL) async -> AnalysisResult {
        if let cached = analysisCache[url] {
            return cached
        }
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let file = try AVAudioFile(forReading: url)
            guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: file.fileFormat.sampleRate,
                                             channels: 1,
                                             interleaved: false) else {
                return .empty
            }
            
            let frameCount = AVAudioFrameCount(file.length)
            guard frameCount > 0 else {
                return .empty
            }
            
            let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                          frameCapacity: frameCount)!
            buffer.frameLength = frameCount
            
            // Read and mixdown to mono
            let engineFile = try AVAudioFile(forReading: url)
            try engineFile.read(into: buffer)
            
            let duration = Double(buffer.frameLength) / format.sampleRate
            let minimumDurationMet = duration >= 2.0  // threshold for reliable analysis
            
            // Tempo detection (reuse existing logic)
            var tempo: Double? = nil
            var tempoConfidence: Float? = nil
            if minimumDurationMet {
                tempo = await analyzeTempoFromBuffer(buffer)
                tempoConfidence = nil  // TODO: Implement confidence estimation
            }
            
            // Key detection via chroma
            var key: String? = nil
            var keyConfidence: Float? = nil
            var chroma: [Float]? = nil
            
            if minimumDurationMet {
                let chromaVec = basicChroma(from: buffer, sampleRate: format.sampleRate)
                let (detectedKey, keyConf) = detectKey(fromChroma: chromaVec)
                key = detectedKey
                keyConfidence = keyConf
                chroma = chromaVec
            }
            
            let analysisTime = CFAbsoluteTimeGetCurrent() - startTime
            
            // Calculate beat positions from tempo
            var beats: [TimeInterval]? = nil
            var downbeatIndices: [Int]? = nil
            if let detectedTempo = tempo, detectedTempo > 0 {
                let beatInterval = 60.0 / detectedTempo // seconds per beat
                var beatPositions: [TimeInterval] = []
                var downbeats: [Int] = []
                var time: TimeInterval = 0
                var beatIndex = 0
                
                // Generate beats for the duration of the audio
                while time < duration {
                    beatPositions.append(time)
                    // Assume 4/4 time signature - every 4th beat is a downbeat
                    if beatIndex % 4 == 0 {
                        downbeats.append(beatIndex)
                    }
                    time += beatInterval
                    beatIndex += 1
                }
                
                beats = beatPositions
                downbeatIndices = downbeats
            }
            
            let result = AnalysisResult(
                tempo: tempo,
                tempoConfidence: tempoConfidence,
                key: key,
                keyConfidence: keyConfidence,
                analysisTime: analysisTime,
                minimumDurationMet: minimumDurationMet,
                chroma: chroma,
                tempoMap: nil,  // tempo map can be added in a later phase
                beats: beats,
                downbeatIndices: downbeatIndices
            )
            
            analysisCache[url] = result
            if let tempo = result.tempo {
            }
            if let key = result.key {
            }
            return result
            
        } catch {
            return .empty
        }
    }
    
    /// Convenience method for analyzing a region.
    func analyzeRegion(_ region: AudioRegion) async -> AnalysisResult {
        let url = region.audioFile.url
        return await analyzeFile(at: url)
    }
    
    // MARK: - Key Detection (FFT + Chroma + Krumhansl)
    
    /// Compute a simple 12-bin chroma vector (C..B) from a mono PCM buffer.
    private func basicChroma(from buffer: AVAudioPCMBuffer,
                             sampleRate: Double) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        
        // Require a power-of-two FFT size; otherwise, truncate.
        let n = 1 << Int(floor(log2(Double(frameCount))))
        if n <= 0 { return Array(repeating: 0, count: 12) }
        
        // Prepare real + imaginary arrays
        var real = [Float](repeating: 0, count: n)
        var imag = [Float](repeating: 0, count: n)
        
        // Copy first channel samples into real
        if let src = buffer.floatChannelData?.pointee {
            for i in 0..<n {
                real[i] = src[i]
            }
        } else {
            return Array(repeating: 0, count: 12)
        }
        
        // Create split complex using withUnsafeMutablePointer
        let log2n = vDSP_Length(log2(Float(n)))
        var split = DSPSplitComplex(realp: &real, imagp: &imag)
        
        guard let fft = vDSP.FFT(log2n: log2n,
                                 radix: .radix2,
                                 ofType: DSPSplitComplex.self) else {
            return Array(repeating: 0, count: 12)
        }
        
        fft.forward(input: split, output: &split)
        
        // Magnitudes for positive frequencies
        var magnitudes = [Float](repeating: 0, count: n / 2)
        vDSP.absolute(split, result: &magnitudes)
        
        // Build 12-bin chroma vector
        var chroma = [Float](repeating: 0, count: 12)
        
        for i in 1..<magnitudes.count {
            let freq = Double(i) * (sampleRate / Double(n))
            if freq < 50 || freq > 5000 { continue }  // ignore very low/high
            
            // Map frequency to nearest MIDI note
            let midi = 69.0 + 12.0 * log2(freq / 440.0)
            let rounded = Int(round(midi))
            let pc = (rounded % 12 + 12) % 12  // ensure [0,11]
            
            chroma[pc] += magnitudes[i]
        }
        
        // Normalize to sum = 1
        let sum = chroma.reduce(0, +)
        if sum > 0 {
            chroma = chroma.map { $0 / sum }
        }
        
        return chroma
    }
    
    /// Detect key from a normalized chroma vector using Krumhansl profiles.
    /// Returns (e.g. "C Major", confidence in [0,1]).
    private func detectKey(fromChroma chroma: [Float]) -> (String?, Float?) {
        guard chroma.count == 12 else { return (nil, nil) }
        
        let pitchClasses = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
        
        func rotatedProfile(_ profile: [Float], by semitones: Int) -> [Float] {
            var result = [Float](repeating: 0, count: 12)
            for i in 0..<12 {
                result[(i + semitones) % 12] = profile[i]
            }
            return result
        }
        
        func correlation(_ a: [Float], _ b: [Float]) -> Float {
            var sum: Float = 0
            for i in 0..<12 {
                sum += a[i] * b[i]
            }
            return sum
        }
        
        var bestKey: String?
        var bestMode: String?
        var bestScore: Float = -Float.greatestFiniteMagnitude
        var scores: [Float] = []
        
        for semitone in 0..<12 {
            let majTemplate = rotatedProfile(majorProfile, by: semitone)
            let minTemplate = rotatedProfile(minorProfile, by: semitone)
            
            let majScore = correlation(chroma, majTemplate)
            let minScore = correlation(chroma, minTemplate)
            
            scores.append(majScore)
            scores.append(minScore)
            
            if majScore > bestScore {
                bestScore = majScore
                bestKey = pitchClasses[semitone]
                bestMode = "Major"
            }
            if minScore > bestScore {
                bestScore = minScore
                bestKey = pitchClasses[semitone]
                bestMode = "Minor"
            }
        }
        
        guard let key = bestKey, let mode = bestMode else {
            return (nil, nil)
        }
        
        // Simple confidence heuristic: normalize bestScore vs total energy.
        let total = scores.reduce(0, +)
        let confidence: Float = total > 0 ? max(0, min(1, bestScore / total)) : 0
        
        return ("\(key) \(mode)", confidence)
    }
    
    // MARK: - Cleanup
    
    nonisolated deinit {
        // Cancel pending analysis tasks to prevent use-after-free.
        // These are nonisolated(unsafe) so safe to access in nonisolated deinit.
        tempoAnalysisTask?.cancel()
        keyAnalysisTask?.cancel()
    }
}