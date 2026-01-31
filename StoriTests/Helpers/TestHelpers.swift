//
//  TestHelpers.swift
//  StoriTests
//
//  Common test utilities and helpers for the Stori test suite.
//  Provides async helpers, comparison utilities, and mock factories.
//

import XCTest
@testable import Stori

// MARK: - Async Test Helpers

extension XCTestCase {
    /// Wait for an async operation with timeout
    func awaitAsync<T>(
        timeout: TimeInterval = 5.0,
        _ operation: @escaping () async throws -> T
    ) throws -> T {
        let expectation = expectation(description: "Async operation")
        var result: Result<T, Error>?
        
        Task {
            do {
                let value = try await operation()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: timeout)
        
        switch result {
        case .success(let value):
            return value
        case .failure(let error):
            throw error
        case .none:
            throw TestError.timeout
        }
    }
    
    /// Run an async test with proper error handling
    func runAsyncTest(
        timeout: TimeInterval = 5.0,
        file: StaticString = #file,
        line: UInt = #line,
        _ test: @escaping () async throws -> Void
    ) {
        let expectation = expectation(description: "Async test")
        
        Task {
            do {
                try await test()
            } catch {
                XCTFail("Async test failed: \(error)", file: file, line: line)
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: timeout)
    }
}

// MARK: - Test Errors

enum TestError: Error, LocalizedError {
    case timeout
    case unexpectedNil
    case mockFailure(String)
    case invalidTestData(String)
    
    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Test operation timed out"
        case .unexpectedNil:
            return "Unexpected nil value"
        case .mockFailure(let message):
            return "Mock failure: \(message)"
        case .invalidTestData(let message):
            return "Invalid test data: \(message)"
        }
    }
}

// MARK: - Floating Point Comparison

extension XCTestCase {
    /// Assert two floats are approximately equal
    func assertApproximatelyEqual(
        _ lhs: Float,
        _ rhs: Float,
        tolerance: Float = 0.0001,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            abs(lhs - rhs) <= tolerance,
            "Expected \(lhs) to be approximately equal to \(rhs) (tolerance: \(tolerance))",
            file: file,
            line: line
        )
    }
    
    /// Assert two doubles are approximately equal (also works with TimeInterval since it's a typealias)
    func assertApproximatelyEqual(
        _ lhs: Double,
        _ rhs: Double,
        tolerance: Double = 0.0001,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            abs(lhs - rhs) <= tolerance,
            "Expected \(lhs) to be approximately equal to \(rhs) (tolerance: \(tolerance))",
            file: file,
            line: line
        )
    }
}

// MARK: - Audio Buffer Helpers

/// Utilities for working with audio buffers in tests
struct TestAudioBuffers {
    /// Generate a silent buffer of specified size
    static func silentBuffer(frameCount: Int, channels: Int = 2) -> [[Float]] {
        Array(repeating: Array(repeating: 0.0, count: frameCount), count: channels)
    }
    
    /// Generate a sine wave buffer for testing
    static func sineWaveBuffer(
        frequency: Float,
        sampleRate: Float,
        frameCount: Int,
        amplitude: Float = 1.0,
        channels: Int = 2
    ) -> [[Float]] {
        var buffer: [[Float]] = []
        
        for _ in 0..<channels {
            var channelData: [Float] = []
            for frame in 0..<frameCount {
                let phase = Float(frame) / sampleRate * frequency * 2 * .pi
                let sample = sin(phase) * amplitude
                channelData.append(sample)
            }
            buffer.append(channelData)
        }
        
        return buffer
    }
    
    /// Compare two audio buffers with tolerance
    static func buffersAreEqual(
        _ lhs: [[Float]],
        _ rhs: [[Float]],
        tolerance: Float = 0.0001
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        
        for (leftChannel, rightChannel) in zip(lhs, rhs) {
            guard leftChannel.count == rightChannel.count else { return false }
            
            for (leftSample, rightSample) in zip(leftChannel, rightChannel) {
                if abs(leftSample - rightSample) > tolerance {
                    return false
                }
            }
        }
        
        return true
    }
    
    /// Calculate RMS level of a buffer
    static func rmsLevel(_ buffer: [Float]) -> Float {
        guard !buffer.isEmpty else { return 0 }
        let sumOfSquares = buffer.reduce(0) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(buffer.count))
    }
    
    /// Calculate peak level of a buffer
    static func peakLevel(_ buffer: [Float]) -> Float {
        buffer.reduce(0) { max($0, abs($1)) }
    }
}

// MARK: - Test Data Factories

/// Factory for creating test data instances
struct TestDataFactory {
    /// Create a minimal test project
    static func createProject(
        name: String = "Test Project",
        tempo: Double = 120.0,
        trackCount: Int = 0
    ) -> AudioProject {
        var project = AudioProject(
            name: name,
            tempo: tempo
        )
        
        for i in 0..<trackCount {
            let track = AudioTrack(name: "Track \(i + 1)")
            project.addTrack(track)
        }
        
        return project
    }
    
    /// Create a test track with basic configuration
    static func createTrack(
        name: String = "Test Track",
        type: TrackType = .audio,
        color: TrackColor = .blue
    ) -> AudioTrack {
        AudioTrack(name: name, trackType: type, color: color)
    }
    
    /// Create a test MIDI note
    static func createMIDINote(
        pitch: UInt8 = 60,
        velocity: UInt8 = 100,
        startTime: TimeInterval = 0,
        duration: TimeInterval = 1.0
    ) -> MIDINote {
        MIDINote(
            pitch: pitch,
            velocity: velocity,
            startTime: startTime,
            duration: duration
        )
    }
    
    /// Create a test MIDI region with notes
    static func createMIDIRegion(
        name: String = "Test Region",
        noteCount: Int = 4,
        startTime: TimeInterval = 0,
        duration: TimeInterval = 4.0
    ) -> MIDIRegion {
        var region = MIDIRegion(
            name: name,
            startTime: startTime,
            duration: duration
        )
        
        for i in 0..<noteCount {
            let note = MIDINote(
                pitch: UInt8(60 + i),
                velocity: 100,
                startTime: TimeInterval(i),
                duration: 0.5
            )
            region.addNote(note)
        }
        
        return region
    }
    
    /// Create a test automation lane with points
    static func createAutomationLane(
        parameter: AutomationParameter = .volume,
        pointCount: Int = 4
    ) -> AutomationLane {
        var lane = AutomationLane(parameter: parameter)
        
        for i in 0..<pointCount {
            let beat = Double(i * 4)
            let value = Float(i) / Float(pointCount)
            lane.addPoint(atBeat: beat, value: value)
        }
        
        return lane
    }
}

// MARK: - Codable Test Helpers

extension XCTestCase {
    /// Test that a Codable type can round-trip through encode/decode
    func assertCodableRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(value)
            
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(T.self, from: data)
            
            XCTAssertEqual(value, decoded, "Codable round-trip failed", file: file, line: line)
        } catch {
            XCTFail("Codable round-trip failed with error: \(error)", file: file, line: line)
        }
    }
    
    /// Test that a Codable type produces valid JSON
    func assertProducesValidJSON<T: Encodable>(
        _ value: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(value)
            
            // Verify it's valid JSON
            _ = try JSONSerialization.jsonObject(with: data)
        } catch {
            XCTFail("Failed to produce valid JSON: \(error)", file: file, line: line)
        }
    }
}

// MARK: - Performance Test Helpers

extension XCTestCase {
    /// Measure execution time of a block
    func measureExecutionTime(_ block: () -> Void) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        block()
        let end = CFAbsoluteTimeGetCurrent()
        return end - start
    }
    
    /// Assert that an operation completes within a time limit
    func assertCompletesWithin(
        _ timeLimit: TimeInterval,
        file: StaticString = #file,
        line: UInt = #line,
        _ block: () -> Void
    ) {
        let duration = measureExecutionTime(block)
        XCTAssertLessThan(
            duration, timeLimit,
            "Operation took \(duration)s, expected less than \(timeLimit)s",
            file: file, line: line
        )
    }
}
