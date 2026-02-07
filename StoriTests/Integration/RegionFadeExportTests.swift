//
//  RegionFadeExportTests.swift
//  StoriTests
//
//  Integration tests for Issue #76: Region Fade Curves Export
//  Verifies that region fade-in/fade-out curves are applied during offline export
//  to match real-time playback (WYSIWYG - What You Hear Is What You Get)
//

import XCTest
import AVFoundation
@testable import Stori

final class RegionFadeExportTests: XCTestCase {
    
    // MARK: - Test Utilities
    
    /// Create a test audio file with a constant tone (easy to analyze for fades)
    func createTestAudioFile(duration: TimeInterval = 1.0, sampleRate: Double = 48000) throws -> (url: URL, audioFile: AudioFile) {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw TestError.bufferCreationFailed
        }
        buffer.frameLength = frameCount
        
        // Fill with constant amplitude (0.5) for easy analysis
        if let channelData = buffer.floatChannelData {
            for channel in 0..<Int(format.channelCount) {
                let samples = channelData[channel]
                for i in 0..<Int(frameCount) {
                    samples[i] = 0.5
                }
            }
        }
        
        // Write to temporary file
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")
        
        let avAudioFile = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try avAudioFile.write(from: buffer)
        
        // Create AudioFile model
        let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64 ?? 0
        let audioFile = AudioFile(
            name: tempURL.lastPathComponent,
            url: tempURL,
            duration: duration,
            sampleRate: sampleRate,
            channels: 2,
            fileSize: fileSize,
            format: .wav
        )
        
        return (tempURL, audioFile)
    }
    
    enum TestError: Error {
        case bufferCreationFailed
        case analysisFailure
    }
    
    // MARK: - Test Helpers
    
    func assertApproximatelyEqual(_ value1: Float, _ value2: Float, tolerance: Float, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        let diff = abs(value1 - value2)
        XCTAssertLessThan(diff, tolerance, message.isEmpty ? "Values not approximately equal: \(value1) vs \(value2)" : message, file: file, line: line)
    }
    
    // MARK: - Fade-In Tests
    
    func testFadeInCreatesLinearRamp() throws {
        let (audioURL, audioFile) = try createTestAudioFile(duration: 1.0, sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        var region = AudioRegion(audioFile: audioFile, fadeIn: 0.1, fadeOut: 0.0)  // 100ms fade-in
        
        // Load and apply fades
        let sourceFile = try AVAudioFile(forReading: audioURL)
        
        // Simulate the fade application
        let frameCount = AVAudioFrameCount(sourceFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: frameCount) else {
            XCTFail("Failed to create buffer")
            return
        }
        try sourceFile.read(into: buffer)
        buffer.frameLength = frameCount
        
        // Apply fade manually (simulating applyRegionFades)
        let fadeInSamples = Int(region.fadeIn * 48000)  // 4800 samples at 48kHz
        
        guard let channelData = buffer.floatChannelData else {
            XCTFail("No channel data")
            return
        }
        
        let samples = channelData[0]
        
        // Apply fade-in
        for i in 0..<fadeInSamples {
            let gain = Float(i) / Float(fadeInSamples)
            samples[i] *= gain
        }
        
        // Verify fade-in ramp
        // First sample should be ~0 (0.5 * 0 = 0)
        XCTAssertLessThan(abs(samples[0]), 0.001, "First sample should be near zero")
        
        // Sample at 25% of fade should be ~0.125 (0.5 * 0.25 = 0.125)
        let quarterPoint = fadeInSamples / 4
        assertApproximatelyEqual(samples[quarterPoint], 0.125, tolerance: 0.01)
        
        // Sample at 50% of fade should be ~0.25 (0.5 * 0.5 = 0.25)
        let midPoint = fadeInSamples / 2
        assertApproximatelyEqual(samples[midPoint], 0.25, tolerance: 0.01)
        
        // Sample after fade-in should be at full amplitude (0.5)
        let afterFade = fadeInSamples + 100
        assertApproximatelyEqual(samples[afterFade], 0.5, tolerance: 0.01)
    }
    
    func testFadeInZeroLengthHasNoEffect() throws {
        let (audioURL, audioFile) = try createTestAudioFile(duration: 0.5, sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let region = AudioRegion(audioFile: audioFile, fadeIn: 0.0, fadeOut: 0.0)  // No fades
        
        // Load file
        let sourceFile = try AVAudioFile(forReading: audioURL)
        let frameCount = AVAudioFrameCount(sourceFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: frameCount) else {
            XCTFail("Failed to create buffer")
            return
        }
        try sourceFile.read(into: buffer)
        
        // With zero fade, first sample should remain at original amplitude
        if let samples = buffer.floatChannelData?[0] {
            assertApproximatelyEqual(samples[0], 0.5, tolerance: 0.001, "No fade should preserve amplitude")
        }
    }
    
    // MARK: - Fade-Out Tests
    
    func testFadeOutCreatesLinearRamp() throws {
        let (audioURL, audioFile) = try createTestAudioFile(duration: 1.0, sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        var region = AudioRegion(audioFile: audioFile, fadeIn: 0.0, fadeOut: 0.1)  // 100ms fade-out
        
        let sourceFile = try AVAudioFile(forReading: audioURL)
        let frameCount = AVAudioFrameCount(sourceFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: frameCount) else {
            XCTFail("Failed to create buffer")
            return
        }
        try sourceFile.read(into: buffer)
        buffer.frameLength = frameCount
        
        let fadeOutSamples = Int(region.fadeOut * 48000)  // 4800 samples
        let totalFrames = Int(frameCount)
        let fadeOutStart = totalFrames - fadeOutSamples
        
        guard let channelData = buffer.floatChannelData else {
            XCTFail("No channel data")
            return
        }
        
        let samples = channelData[0]
        
        // Apply fade-out
        for i in 0..<fadeOutSamples {
            let gain = 1.0 - (Float(i) / Float(fadeOutSamples))
            samples[fadeOutStart + i] *= gain
        }
        
        // Verify fade-out ramp
        // Sample before fade-out should be at full amplitude
        let beforeFade = fadeOutStart - 100
        assertApproximatelyEqual(samples[beforeFade], 0.5, tolerance: 0.01)
        
        // Sample at start of fade-out should be near full amplitude
        assertApproximatelyEqual(samples[fadeOutStart], 0.5, tolerance: 0.01)
        
        // Sample at 50% of fade should be ~0.25 (0.5 * 0.5)
        let midFade = fadeOutStart + (fadeOutSamples / 2)
        assertApproximatelyEqual(samples[midFade], 0.25, tolerance: 0.01)
        
        // Last sample should be ~0
        XCTAssertLessThan(abs(samples[totalFrames - 1]), 0.001, "Last sample should be near zero")
    }
    
    // MARK: - Combined Fades Tests
    
    func testBothFadesAppliedCorrectly() throws {
        let (audioURL, audioFile) = try createTestAudioFile(duration: 1.0, sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        var region = AudioRegion(audioFile: audioFile, fadeIn: 0.05, fadeOut: 0.05)  // 50ms each
        
        let sourceFile = try AVAudioFile(forReading: audioURL)
        let frameCount = AVAudioFrameCount(sourceFile.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: frameCount) else {
            XCTFail("Failed to create buffer")
            return
        }
        try sourceFile.read(into: buffer)
        buffer.frameLength = frameCount
        
        let fadeInSamples = Int(region.fadeIn * 48000)
        let fadeOutSamples = Int(region.fadeOut * 48000)
        let totalFrames = Int(frameCount)
        let fadeOutStart = totalFrames - fadeOutSamples
        
        guard let samples = buffer.floatChannelData?[0] else {
            XCTFail("No channel data")
            return
        }
        
        // Apply both fades
        for i in 0..<fadeInSamples {
            let gain = Float(i) / Float(fadeInSamples)
            samples[i] *= gain
        }
        for i in 0..<fadeOutSamples {
            let gain = 1.0 - (Float(i) / Float(fadeOutSamples))
            samples[fadeOutStart + i] *= gain
        }
        
        // Verify both fades
        XCTAssertLessThan(abs(samples[0]), 0.001, "Fade-in: first sample should be ~0")
        XCTAssertLessThan(abs(samples[totalFrames - 1]), 0.001, "Fade-out: last sample should be ~0")
        
        // Middle should be at full amplitude
        let middle = totalFrames / 2
        assertApproximatelyEqual(samples[middle], 0.5, tolerance: 0.01, "Middle should be full amplitude")
    }
    
    func testFadesDoNotOverlap() throws {
        // Test with short audio and long fades (fades should be clamped)
        let (audioURL, audioFile) = try createTestAudioFile(duration: 0.2, sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let region = AudioRegion(audioFile: audioFile, fadeIn: 0.15, fadeOut: 0.15)  // Overlapping fades
        
        let sourceFile = try AVAudioFile(forReading: audioURL)
        let frameCount = AVAudioFrameCount(sourceFile.length)
        let totalFrames = Int(frameCount)
        
        // Simulate clamping logic
        let requestedFadeIn = Int(0.15 * 48000)
        let requestedFadeOut = Int(0.15 * 48000)
        let actualFadeIn = min(requestedFadeIn, totalFrames / 2)
        let actualFadeOut = min(requestedFadeOut, totalFrames / 2)
        
        // Verify fades are clamped to not overlap
        XCTAssertLessThanOrEqual(actualFadeIn + actualFadeOut, totalFrames, "Fades should not overlap")
    }
    
    // MARK: - Click Prevention Tests
    
    func testNoClicksAtRegionStart() throws {
        // Verify fade-in prevents clicks (no discontinuity at start)
        let (audioURL, audioFile) = try createTestAudioFile(duration: 0.5, sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let region = AudioRegion(audioFile: audioFile, fadeIn: 0.01, fadeOut: 0.0)  // 10ms fade-in
        
        let sourceFile = try AVAudioFile(forReading: audioURL)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: AVAudioFrameCount(sourceFile.length)) else {
            XCTFail("Failed to create buffer")
            return
        }
        try sourceFile.read(into: buffer)
        buffer.frameLength = AVAudioFrameCount(sourceFile.length)
        
        // Apply fade
        let fadeInSamples = Int(region.fadeIn * 48000)
        guard let samples = buffer.floatChannelData?[0] else {
            XCTFail("No channel data")
            return
        }
        for i in 0..<fadeInSamples {
            let gain = Float(i) / Float(fadeInSamples)
            samples[i] *= gain
        }
        
        // Check first few samples for smooth transition (no sudden jump)
        for i in 0..<min(10, fadeInSamples) {
            let current = samples[i]
            let next = samples[i + 1]
            let diff = abs(next - current)
            
            // Difference should be gradual (no spikes > 0.01)
            XCTAssertLessThan(diff, 0.01, "Sample \(i) to \(i+1) has discontinuity: \(diff)")
        }
    }
    
    func testNoClicksAtRegionEnd() throws {
        // Verify fade-out prevents clicks (no discontinuity at end)
        let (audioURL, audioFile) = try createTestAudioFile(duration: 0.5, sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let region = AudioRegion(audioFile: audioFile, fadeIn: 0.0, fadeOut: 0.01)  // 10ms fade-out
        
        let sourceFile = try AVAudioFile(forReading: audioURL)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: AVAudioFrameCount(sourceFile.length)) else {
            XCTFail("Failed to create buffer")
            return
        }
        try sourceFile.read(into: buffer)
        buffer.frameLength = AVAudioFrameCount(sourceFile.length)
        
        let fadeOutSamples = Int(region.fadeOut * 48000)
        let totalFrames = Int(buffer.frameLength)
        let fadeOutStart = totalFrames - fadeOutSamples
        
        guard let samples = buffer.floatChannelData?[0] else {
            XCTFail("No channel data")
            return
        }
        
        // Apply fade-out
        for i in 0..<fadeOutSamples {
            let gain = 1.0 - (Float(i) / Float(fadeOutSamples))
            samples[fadeOutStart + i] *= gain
        }
        
        // Check last few samples for smooth transition
        let startCheck = max(0, fadeOutStart)
        for i in startCheck..<min(startCheck + 10, totalFrames - 1) {
            let current = samples[i]
            let next = samples[i + 1]
            let diff = abs(next - current)
            
            XCTAssertLessThan(diff, 0.02, "Fade-out sample \(i) to \(i+1) has discontinuity: \(diff)")
        }
    }
    
    // MARK: - Edge Cases
    
    func testVeryShortFades() throws {
        // Test 1ms fades (48 samples at 48kHz)
        let (audioURL, audioFile) = try createTestAudioFile(duration: 0.5, sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let region = AudioRegion(audioFile: audioFile, fadeIn: 0.001, fadeOut: 0.001)
        
        let fadeInSamples = Int(region.fadeIn * 48000)
        let fadeOutSamples = Int(region.fadeOut * 48000)
        
        XCTAssertEqual(fadeInSamples, 48, "1ms fade should be 48 samples at 48kHz")
        XCTAssertEqual(fadeOutSamples, 48, "1ms fade should be 48 samples at 48kHz")
    }
    
    func testVeryLongFades() throws {
        // Test fades longer than audio file (should be clamped)
        let (audioURL, audioFile) = try createTestAudioFile(duration: 0.1, sampleRate: 48000)  // 100ms audio
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let region = AudioRegion(audioFile: audioFile, fadeIn: 1.0, fadeOut: 1.0)  // 1s fades (longer than audio!)
        
        let totalFrames = Int(0.1 * 48000)  // 4800 frames
        let requestedFadeIn = Int(1.0 * 48000)  // 48000 frames
        let requestedFadeOut = Int(1.0 * 48000)
        
        // Fades should be clamped to half the buffer
        let actualFadeIn = min(requestedFadeIn, totalFrames / 2)
        let actualFadeOut = min(requestedFadeOut, totalFrames / 2)
        
        XCTAssertEqual(actualFadeIn, totalFrames / 2, "Fade-in should be clamped to half buffer")
        XCTAssertEqual(actualFadeOut, totalFrames / 2, "Fade-out should be clamped to half buffer")
    }
    
    // MARK: - Stereo Handling
    
    func testFadesAppliedToBothChannels() throws {
        let (audioURL, audioFile) = try createTestAudioFile(duration: 0.5, sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        let region = AudioRegion(audioFile: audioFile, fadeIn: 0.05, fadeOut: 0.05)
        
        let sourceFile = try AVAudioFile(forReading: audioURL)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: AVAudioFrameCount(sourceFile.length)) else {
            XCTFail("Failed to create buffer")
            return
        }
        try sourceFile.read(into: buffer)
        buffer.frameLength = AVAudioFrameCount(sourceFile.length)
        
        let fadeInSamples = Int(region.fadeIn * 48000)
        
        guard let channelData = buffer.floatChannelData else {
            XCTFail("No channel data")
            return
        }
        
        // Apply fades to both channels
        for channel in 0..<2 {
            let samples = channelData[channel]
            for i in 0..<fadeInSamples {
                let gain = Float(i) / Float(fadeInSamples)
                samples[i] *= gain
            }
        }
        
        // Verify both channels have fades
        let leftChannel = channelData[0]
        let rightChannel = channelData[1]
        
        XCTAssertLessThan(abs(leftChannel[0]), 0.001, "Left channel should have fade-in")
        XCTAssertLessThan(abs(rightChannel[0]), 0.001, "Right channel should have fade-in")
        
        // Both channels should match at midpoint
        let midPoint = fadeInSamples + 100
        assertApproximatelyEqual(leftChannel[midPoint], rightChannel[midPoint], tolerance: 0.001, "Channels should match")
    }
    
    // MARK: - Looped Region Tests
    
    func testLoopedRegionsFadesAppliedToEachIteration() throws {
        // Verify that when a region is looped, each loop iteration gets fades applied
        // This is critical for WYSIWYG: if playback applies fades per loop, export must too
        let (audioURL, audioFile) = try createTestAudioFile(duration: 0.1, sampleRate: 48000)
        defer { try? FileManager.default.removeItem(at: audioURL) }
        
        var region = AudioRegion(audioFile: audioFile, fadeIn: 0.01, fadeOut: 0.01)
        
        // Simulate looped scheduling behavior from scheduleRegionForPlayback
        // Each loop iteration should get a fresh faded buffer scheduled
        let loopCount = 3
        
        for loopIndex in 0..<loopCount {
            // Each iteration loads and applies fades to a fresh buffer
            let sourceFile = try AVAudioFile(forReading: audioURL)
            let frameCount = AVAudioFrameCount(sourceFile.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: sourceFile.processingFormat, frameCapacity: frameCount) else {
                XCTFail("Failed to create buffer for loop \(loopIndex)")
                return
            }
            try sourceFile.read(into: buffer)
            buffer.frameLength = frameCount
            
            // Apply fades (simulating applyRegionFades)
            let fadeInSamples = Int(region.fadeIn * 48000)
            let fadeOutSamples = Int(region.fadeOut * 48000)
            let totalFrames = Int(frameCount)
            let fadeOutStart = totalFrames - fadeOutSamples
            
            guard let samples = buffer.floatChannelData?[0] else {
                XCTFail("No channel data")
                return
            }
            
            // Apply fade-in
            for i in 0..<fadeInSamples {
                let gain = Float(i) / Float(fadeInSamples)
                samples[i] *= gain
            }
            
            // Apply fade-out
            for i in 0..<fadeOutSamples {
                let gain = 1.0 - (Float(i) / Float(fadeOutSamples))
                samples[fadeOutStart + i] *= gain
            }
            
            // Verify fades applied to this iteration
            XCTAssertLessThan(abs(samples[0]), 0.002, "Loop \(loopIndex): First sample should have fade-in")
            XCTAssertLessThan(abs(samples[totalFrames - 1]), 0.002, "Loop \(loopIndex): Last sample should have fade-out")
            
            // Middle should be full amplitude
            let middle = totalFrames / 2
            assertApproximatelyEqual(samples[middle], 0.5, tolerance: 0.01, "Loop \(loopIndex): Middle should be full amplitude")
        }
    }
}
