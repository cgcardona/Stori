//
//  AudioRegressionTestCase.swift
//  StoriTests
//
//  Base class for audio regression tests.
//  Provides golden-file comparison infrastructure for offline render validation.
//
//  Architecture:
//  - Tests load a known .stori project
//  - Perform an offline render/export
//  - Compare the resulting WAV against a golden reference
//  - Comparisons use multiple strategies: duration, peak, RMS, silence detection
//
//  Golden File Strategy:
//  - Golden files live in GoldenProjects/ at the repo root
//  - Each golden consists of: <name>.stori (project) + <name>.golden.wav (reference audio)
//  - When a golden needs updating (intentional change), regenerate with:
//    `STORI_UPDATE_GOLDENS=1 xcodebuild test ...`
//  - Tolerance values account for float rounding but catch real regressions
//

import XCTest
import AVFoundation
@testable import Stori

// MARK: - Audio Comparison Result

/// Detailed comparison result between rendered and golden audio.
struct AudioComparisonResult {
    let durationMatch: Bool
    let durationDelta: TimeInterval      // Seconds difference
    let peakMatch: Bool
    let peakDelta: Float                 // Absolute difference in peak
    let rmsMatch: Bool
    let rmsDelta: Float                  // Absolute difference in RMS
    let silenceDetected: Bool            // True if output is essentially silent
    let channelCountMatch: Bool
    let sampleRateMatch: Bool

    var passed: Bool {
        durationMatch && peakMatch && rmsMatch && !silenceDetected
            && channelCountMatch && sampleRateMatch
    }

    var summary: String {
        var lines: [String] = []
        lines.append("Duration: \(durationMatch ? "PASS" : "FAIL") (delta: \(String(format: "%.4f", durationDelta))s)")
        lines.append("Peak: \(peakMatch ? "PASS" : "FAIL") (delta: \(String(format: "%.6f", peakDelta)))")
        lines.append("RMS: \(rmsMatch ? "PASS" : "FAIL") (delta: \(String(format: "%.6f", rmsDelta)))")
        lines.append("Silence: \(silenceDetected ? "FAIL (silent output)" : "PASS")")
        lines.append("Channels: \(channelCountMatch ? "PASS" : "FAIL")")
        lines.append("Sample Rate: \(sampleRateMatch ? "PASS" : "FAIL")")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Tolerance Configuration

/// Tolerance thresholds for golden file comparison.
/// These are intentionally tight — the render pipeline should be deterministic.
struct AudioTolerances {
    /// Maximum duration difference in seconds (default: 50ms — accounts for tail rounding).
    var durationTolerance: TimeInterval = 0.05

    /// Maximum peak level difference (linear, 0–1 scale).
    var peakTolerance: Float = 0.005

    /// Maximum RMS level difference (linear).
    var rmsTolerance: Float = 0.005

    /// Minimum RMS threshold below which the output is considered silent.
    var silenceThreshold: Float = 0.0001

    /// Default tolerances — tight enough to catch real regressions.
    static let `default` = AudioTolerances()

    /// Relaxed tolerances for tests involving plugins or non-deterministic processing.
    static let relaxed = AudioTolerances(
        durationTolerance: 0.2,
        peakTolerance: 0.02,
        rmsTolerance: 0.02,
        silenceThreshold: 0.0001
    )
}

// MARK: - Audio Regression Base Class

class AudioRegressionTestCase: XCTestCase {

    /// Path to the GoldenProjects directory.
    var goldenProjectsPath: String {
        // Navigate from the test bundle to the repo root
        let bundle = Bundle(for: type(of: self))
        let bundlePath = bundle.bundlePath
        // Test bundle is at: <DerivedData>/.../StoriTests.xctest
        // We need to find the source repo's GoldenProjects/ directory
        // Use an environment variable or a known relative path
        if let envPath = ProcessInfo.processInfo.environment["STORI_GOLDEN_PATH"] {
            return envPath
        }
        // Fallback: look relative to source root (set via build setting)
        if let sourceRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            return "\(sourceRoot)/GoldenProjects"
        }
        // Last resort: use the bundle path and navigate up
        return (bundlePath as NSString)
            .deletingLastPathComponent  // StoriTests.xctest
            .appending("/../../../GoldenProjects")
    }

    /// Whether to update golden files instead of comparing against them.
    var shouldUpdateGoldens: Bool {
        ProcessInfo.processInfo.environment["STORI_UPDATE_GOLDENS"] == "1"
    }

    // MARK: - Audio Analysis

    /// Analyze a WAV file and return its characteristics.
    func analyzeAudioFile(at url: URL) throws -> (
        duration: TimeInterval,
        peak: Float,
        rms: Float,
        channels: Int,
        sampleRate: Double
    ) {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0 else {
            return (0, 0, 0, Int(format.channelCount), format.sampleRate)
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            throw TestError.invalidTestData("Failed to create buffer for \(url.lastPathComponent)")
        }

        try audioFile.read(into: buffer)

        let channelCount = Int(format.channelCount)
        var globalPeak: Float = 0
        var globalSumOfSquares: Float = 0
        let totalSamples = Int(buffer.frameLength) * channelCount

        for channel in 0..<channelCount {
            guard let channelData = buffer.floatChannelData?[channel] else { continue }
            let frameLength = Int(buffer.frameLength)

            for i in 0..<frameLength {
                let sample = abs(channelData[i])
                globalPeak = max(globalPeak, sample)
                globalSumOfSquares += channelData[i] * channelData[i]
            }
        }

        let rms = totalSamples > 0 ? sqrt(globalSumOfSquares / Float(totalSamples)) : 0
        let duration = Double(audioFile.length) / format.sampleRate

        return (duration, globalPeak, rms, channelCount, format.sampleRate)
    }

    // MARK: - Golden File Comparison

    /// Compare a rendered audio file against a golden reference.
    func compareAudio(
        rendered: URL,
        golden: URL,
        tolerances: AudioTolerances = .default
    ) throws -> AudioComparisonResult {
        let renderedInfo = try analyzeAudioFile(at: rendered)
        let goldenInfo = try analyzeAudioFile(at: golden)

        let durationDelta = abs(renderedInfo.duration - goldenInfo.duration)
        let peakDelta = abs(renderedInfo.peak - goldenInfo.peak)
        let rmsDelta = abs(renderedInfo.rms - goldenInfo.rms)

        return AudioComparisonResult(
            durationMatch: durationDelta <= tolerances.durationTolerance,
            durationDelta: durationDelta,
            peakMatch: peakDelta <= tolerances.peakTolerance,
            peakDelta: peakDelta,
            rmsMatch: rmsDelta <= tolerances.rmsTolerance,
            rmsDelta: rmsDelta,
            silenceDetected: renderedInfo.rms < tolerances.silenceThreshold,
            channelCountMatch: renderedInfo.channels == goldenInfo.channels,
            sampleRateMatch: renderedInfo.sampleRate == goldenInfo.sampleRate
        )
    }

    // MARK: - Golden File Management

    /// Update a golden file with a new render.
    func updateGoldenFile(rendered: URL, goldenPath: String) throws {
        let goldenURL = URL(fileURLWithPath: goldenPath)
        let fm = FileManager.default

        // Create directory if needed
        let dir = goldenURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Remove old golden
        if fm.fileExists(atPath: goldenPath) {
            try fm.removeItem(atPath: goldenPath)
        }

        // Copy new render as golden
        try fm.copyItem(at: rendered, to: goldenURL)
        print("🔄 Updated golden file: \(goldenPath)")
    }

    // MARK: - Assertion Helpers

    /// Assert that a rendered file matches its golden reference.
    func assertAudioMatchesGolden(
        rendered: URL,
        goldenName: String,
        tolerances: AudioTolerances = .default,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let goldenPath = "\(goldenProjectsPath)/\(goldenName).golden.wav"
        let goldenURL = URL(fileURLWithPath: goldenPath)

        if shouldUpdateGoldens {
            try updateGoldenFile(rendered: rendered, goldenPath: goldenPath)
            return
        }

        guard FileManager.default.fileExists(atPath: goldenPath) else {
            XCTFail(
                "Golden file not found: \(goldenPath). Run with STORI_UPDATE_GOLDENS=1 to create it.",
                file: file, line: line
            )
            return
        }

        let result = try compareAudio(rendered: rendered, golden: goldenURL, tolerances: tolerances)

        if !result.passed {
            // Attach both files as test artifacts for debugging
            let renderedAttachment = XCTAttachment(contentsOfFile: rendered)
            renderedAttachment.name = "rendered-\(goldenName).wav"
            renderedAttachment.lifetime = .keepAlways
            add(renderedAttachment)

            let goldenAttachment = XCTAttachment(contentsOfFile: goldenURL)
            goldenAttachment.name = "golden-\(goldenName).wav"
            goldenAttachment.lifetime = .keepAlways
            add(goldenAttachment)

            XCTFail(
                "Audio regression detected for '\(goldenName)':\n\(result.summary)",
                file: file, line: line
            )
        }
    }

    /// Assert a rendered audio file is not silent.
    func assertNotSilent(
        _ url: URL,
        threshold: Float = 0.0001,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let info = try analyzeAudioFile(at: url)
        XCTAssertGreaterThan(
            info.rms, threshold,
            "Audio file appears to be silent (RMS: \(info.rms))",
            file: file, line: line
        )
    }

    /// Assert a rendered audio file has the expected duration.
    func assertDuration(
        _ url: URL,
        expected: TimeInterval,
        tolerance: TimeInterval = 0.05,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let info = try analyzeAudioFile(at: url)
        let delta = abs(info.duration - expected)
        XCTAssertLessThanOrEqual(
            delta, tolerance,
            "Duration mismatch: expected \(expected)s, got \(info.duration)s (delta: \(delta)s)",
            file: file, line: line
        )
    }

    // MARK: - Temp File Management

    /// Create a temporary directory for test outputs.
    func createTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StoriAudioRegression")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDir,
            withIntermediateDirectories: true
        )
        return tempDir
    }

    /// Clean up a temporary directory.
    func cleanupTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
