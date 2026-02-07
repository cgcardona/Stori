//
//  AudioAnalyzer.swift
//  Stori
//
//  Audio analysis and waveform generation utilities
//

import Foundation
import AVFoundation
import Accelerate
import Observation

/// Handles audio file analysis and waveform data generation
@Observable
@MainActor
class AudioAnalyzer {
    
    /// Shared instance for consistent waveform caching across the app
    static let shared = AudioAnalyzer()
    
    /// Represents waveform data for visualization
    struct WaveformData {
        let samples: [Float]
        let sampleRate: Double
        let duration: TimeInterval
        let peakAmplitude: Float
        let rmsAmplitude: Float
        
        /// Number of samples in the waveform data
        var sampleCount: Int { samples.count }
        
        /// Get normalized sample at index (0.0 to 1.0)
        func normalizedSample(at index: Int) -> Float {
            guard index >= 0 && index < samples.count else { return 0.0 }
            return abs(samples[index]) / max(peakAmplitude, 0.001) // Avoid division by zero
        }
        
        /// Get samples for a specific time range
        /// Uses the waveform's effective sample rate (samples.count / duration) rather than
        /// the original audio file's sample rate, since waveform data is downsampled for visualization.
        func samples(in timeRange: ClosedRange<TimeInterval>) -> [Float] {
            guard duration > 0 else { return [] }
            
            // Calculate indices based on waveform data's effective sample rate
            // NOT the original audio file's sample rate (which would give indices way out of bounds)
            let effectiveSampleRate = Double(samples.count) / duration
            let startIndex = Int(timeRange.lowerBound * effectiveSampleRate)
            let endIndex = Int(timeRange.upperBound * effectiveSampleRate)
            
            let clampedStart = max(0, startIndex)
            let clampedEnd = min(samples.count - 1, endIndex)
            
            guard clampedStart <= clampedEnd else { return [] }
            
            return Array(samples[clampedStart...clampedEnd])
        }
    }
    
    /// Cache for analyzed waveform data
    @ObservationIgnored
    private var waveformCache: [URL: WaveformData] = [:]
    
    /// Analyze audio file and generate waveform data
    func analyzeAudioFile(at url: URL, targetSamples: Int = 1000) async throws -> WaveformData {
        
        // Check cache first
        if let cachedData = waveformCache[url] {
            return cachedData
        }
        
        // Load audio file
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)
        
        // Validate file has content
        guard frameCount > 0 else {
            throw AudioAnalysisError.noAudioData
        }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioAnalysisError.bufferCreationFailed
        }
        
        try audioFile.read(into: buffer)
        
        // Extract audio data
        guard let channelData = buffer.floatChannelData?[0] else {
            throw AudioAnalysisError.noAudioData
        }
        
        let sampleCount = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData, count: sampleCount))
        
        // Downsample if necessary for visualization
        let downsampledSamples = downsampleAudio(samples: samples, targetCount: targetSamples)
        
        // Calculate audio statistics
        let peakAmplitude = calculatePeakAmplitude(samples: samples)
        let rmsAmplitude = calculateRMSAmplitude(samples: samples)
        
        let waveformData = WaveformData(
            samples: downsampledSamples,
            sampleRate: format.sampleRate,
            duration: Double(sampleCount) / format.sampleRate,
            peakAmplitude: peakAmplitude,
            rmsAmplitude: rmsAmplitude
        )
        
        // Cache the result
        waveformCache[url] = waveformData
        
        return waveformData
    }
    
    /// Downsample audio data for visualization efficiency
    private func downsampleAudio(samples: [Float], targetCount: Int) -> [Float] {
        guard samples.count > targetCount else { return samples }
        
        let ratio = Float(samples.count) / Float(targetCount)
        var downsampledSamples: [Float] = []
        downsampledSamples.reserveCapacity(targetCount)
        
        for i in 0..<targetCount {
            let startIndex = Int(Float(i) * ratio)
            let endIndex = min(Int(Float(i + 1) * ratio), samples.count)
            
            // Use RMS for each window to preserve energy
            var sum: Float = 0.0
            var count = 0
            
            for j in startIndex..<endIndex {
                sum += samples[j] * samples[j]
                count += 1
            }
            
            let rms = count > 0 ? sqrt(sum / Float(count)) : 0.0
            
            // Preserve sign by checking the original sample with highest absolute value
            var maxSample: Float = 0.0
            for j in startIndex..<endIndex {
                if abs(samples[j]) > abs(maxSample) {
                    maxSample = samples[j]
                }
            }
            
            downsampledSamples.append(maxSample >= 0 ? rms : -rms)
        }
        
        return downsampledSamples
    }
    
    /// Calculate peak amplitude using Accelerate framework
    private func calculatePeakAmplitude(samples: [Float]) -> Float {
        var peak: Float = 0.0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        return peak
    }
    
    /// Calculate RMS amplitude using Accelerate framework
    private func calculateRMSAmplitude(samples: [Float]) -> Float {
        var rms: Float = 0.0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        return rms
    }
    
    /// Clear waveform cache to free memory
    func clearCache() {
        waveformCache.removeAll()
    }
    
    /// Clear cache for specific URL
    func clearCache(for url: URL) {
        waveformCache.removeValue(forKey: url)
    }
    
    /// Get cached waveform data if available
    func getCachedWaveform(for url: URL) -> WaveformData? {
        return waveformCache[url]
    }
    
    // MARK: - Cleanup
}

// MARK: - Audio Analysis Errors

enum AudioAnalysisError: LocalizedError {
    case bufferCreationFailed
    case noAudioData
    case fileReadError
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .noAudioData:
            return "No audio data found in file"
        case .fileReadError:
            return "Failed to read audio file"
        case .unsupportedFormat:
            return "Unsupported audio format"
        }
    }
}

// MARK: - Waveform Visualization Helpers

extension AudioAnalyzer.WaveformData {
    
    /// Generate path points for SwiftUI Path drawing
    func pathPoints(for size: CGSize, timeRange: ClosedRange<TimeInterval>? = nil) -> [CGPoint] {
        let relevantSamples: [Float]
        
        if let timeRange = timeRange {
            relevantSamples = samples(in: timeRange)
        } else {
            relevantSamples = samples
        }
        
        guard !relevantSamples.isEmpty else { return [] }
        
        let width = size.width
        let height = size.height
        let midY = height / 2
        
        var points: [CGPoint] = []
        points.reserveCapacity(relevantSamples.count * 2) // Top and bottom points
        
        for (index, sample) in relevantSamples.enumerated() {
            let x = CGFloat(index) / CGFloat(relevantSamples.count - 1) * width
            let normalizedAmplitude = abs(sample) / max(peakAmplitude, 0.001)
            let amplitude = CGFloat(normalizedAmplitude) * midY * 0.8 // Scale to 80% of available height
            
            // Add top and bottom points for waveform
            points.append(CGPoint(x: x, y: midY - amplitude))
            points.append(CGPoint(x: x, y: midY + amplitude))
        }
        
        return points
    }
    
    /// Generate bars for bar-style waveform visualization
    func barHeights(for width: CGFloat, barCount: Int, timeRange: ClosedRange<TimeInterval>? = nil) -> [CGFloat] {
        let relevantSamples: [Float]
        
        if let timeRange = timeRange {
            relevantSamples = samples(in: timeRange)
        } else {
            relevantSamples = samples
        }
        
        guard !relevantSamples.isEmpty else { return Array(repeating: 0, count: barCount) }
        
        let samplesPerBar = max(1, relevantSamples.count / barCount)
        var barHeights: [CGFloat] = []
        barHeights.reserveCapacity(barCount)
        
        for i in 0..<barCount {
            let startIndex = i * samplesPerBar
            
            // Ensure startIndex is within bounds
            guard startIndex < relevantSamples.count else {
                barHeights.append(0)
                continue
            }
            
            let endIndex = min(startIndex + samplesPerBar, relevantSamples.count)
            
            var maxAmplitude: Float = 0.0
            for j in startIndex..<endIndex {
                maxAmplitude = max(maxAmplitude, abs(relevantSamples[j]))
            }
            
            let normalizedHeight = CGFloat(maxAmplitude / max(peakAmplitude, 0.001))
            barHeights.append(normalizedHeight)
        }
        
        return barHeights
    }
    
    /// Generate professional waveform visualization optimized for DAW use
    /// - Parameters:
    ///   - size: The size of the waveform view
    ///   - style: The waveform visualization style
    ///   - timeRange: Optional time range to display (for split regions). If nil, displays entire file.
    func professionalWaveformBars(for size: CGSize, style: WaveformStyle = .bars, timeRange: ClosedRange<TimeInterval>? = nil) -> [WaveformBar] {
        let barCount = Int(size.width / 2) // 2 pixels per bar for crisp rendering
        let barHeights = self.barHeights(for: size.width, barCount: barCount, timeRange: timeRange)
        
        return barHeights.enumerated().map { index, height in
            WaveformBar(
                x: CGFloat(index) * (size.width / CGFloat(barCount)),
                height: height * size.height * 0.8, // 80% of available height
                amplitude: Float(height)
            )
        }
    }
}

// MARK: - Professional Waveform Components

/// Represents a single bar in the waveform visualization
struct WaveformBar {
    let x: CGFloat
    let height: CGFloat
    let amplitude: Float // 0.0 to 1.0
}

/// Waveform visualization styles
enum WaveformStyle {
    case bars       // Vertical bars (professional DAW style)
    case line       // Continuous line
    case filled     // Filled area under curve
}
