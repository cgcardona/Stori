# Audio Engine Test Suite

## Overview

This directory contains comprehensive unit and integration tests for Stori's audio engine. Our goal is **80%+ test coverage** to establish Stori as mission-critical, production-ready software that attracts serious open-source contributors.

## Running Tests

### All Audio Tests
```bash
xcodebuild test \
  -project Stori.xcodeproj \
  -scheme Stori \
  -destination 'platform=macOS' \
  -only-testing:StoriTests/Audio
```

### Specific Test File
```bash
xcodebuild test \
  -project Stori.xcodeproj \
  -scheme Stori \
  -destination 'platform=macOS' \
  -only-testing:StoriTests/SampleAccurateMIDISchedulerTests
```

### With Code Coverage
```bash
xcodebuild test \
  -project Stori.xcodeproj \
  -scheme Stori \
  -destination 'platform=macOS' \
  -only-testing:StoriTests/Audio \
  -enableCodeCoverage YES
```

### View Coverage Report
```bash
# Find latest test result
find ~/Library/Developer/Xcode/DerivedData/Stori-*/Logs/Test/*.xcresult -type d | sort -r | head -n 1

# View coverage
xcrun xccov view --report <path-to-xcresult>
```

## Test Organization

### Existing Test Files

#### Core Engine & Transport
- **TransportControllerTests.swift** (517 lines) - Transport controls, playback, recording
- **PlaybackSchedulingCoordinatorTests.swift** - Playback scheduling coordination
- **MIDITimingReferenceTests.swift** - MIDI timing accuracy
- **SampleAccurateMIDISchedulerTests.swift** (NEW) - Sample-accurate MIDI scheduling

#### Audio Graph & Processing
- **AudioGraphManagerTests.swift** - Audio graph management
- **TrackAudioNodeTests.swift** - Track audio node lifecycle
- **MixerControllerTests.swift** (489 lines) - Mixer functionality (volume, pan, EQ, sends)

#### Monitoring & Health
- **AudioEngineHealthMonitorTests.swift** - Engine health monitoring
- **AudioPerformanceMonitorTests.swift** - Performance monitoring
- **AudioEngineErrorTrackerTests.swift** - Error tracking and recovery
- **AudioResourcePoolTests.swift** - Resource pooling

#### Recording & Automation
- **RecordingControllerTests.swift** - Recording functionality
- **AutomationProcessorTests.swift** - Automation processing (CRITICAL - recently fixed)

#### Plugin System
- **PluginChainStateTests.swift** - Plugin chain state management

#### Configuration
- **DeviceConfigurationManagerTests.swift** - Audio device configuration

### Skipped Tests (Need Activation)
- **MIDIPlaybackEngineTests.swift.skip** - MIDI playback engine (HIGH PRIORITY)
- **ProjectLifecycleManagerTests.swift.skip** - Project lifecycle (HIGH PRIORITY)

### Missing Tests (Need Creation)

See `AUDIO_ENGINE_TEST_STRATEGY.md` for comprehensive roadmap. High-priority missing tests:

- **AudioEngineTests.swift** - Core engine initialization and lifecycle
- **TrackNodeManagerTests.swift** - Track node management (recently enhanced)
- **RecordingBufferPoolTests.swift** - Buffer pool management
- **PluginInstanceTests.swift** - Individual plugin instances
- **PluginChainTests.swift** - Plugin chain processing
- **PluginLatencyManagerTests.swift** - Plugin delay compensation
- **GraphBuildingTests.swift** - Audio graph construction
- **MetronomeEngineTests.swift** - Metronome/click track
- **QuantizationEngineTests.swift** - Quantization logic

## Writing Tests

### Test File Template

```swift
//
//  ComponentTests.swift
//  StoriTests
//
//  Unit tests for Component - Brief description
//

import XCTest
@testable import Stori

final class ComponentTests: XCTestCase {
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        // Setup test environment
    }
    
    override func tearDown() async throws {
        // Clean up resources
    }
    
    // MARK: - Initialization Tests
    
    func testComponentInitialization() {
        // Test basic initialization
    }
    
    // MARK: - Functional Tests
    
    func testComponentBasicOperation() {
        // Test core functionality
    }
    
    // MARK: - Error Handling Tests
    
    func testComponentErrorHandling() {
        // Test error conditions
    }
    
    // MARK: - Real-Time Safety Tests (CRITICAL for audio thread code)
    
    func testComponentRealTimeSafety() {
        // Verify no dynamic memory allocation
        // Verify no MainActor access from audio thread
        // Verify bounded, predictable performance
    }
    
    // MARK: - Performance Tests
    
    func testComponentPerformance() {
        measure {
            // Performance-critical operations
        }
    }
}
```

### Test Naming Conventions

- **testComponentAction()** - Basic functionality test
- **testComponentActionWithCondition()** - Specific scenario
- **testComponentActionFailure()** - Error case
- **testComponentActionPerformance()** - Performance benchmark
- **testComponentRealTimeSafety()** - Real-time safety validation

### Assertions

```swift
// Use XCTest assertions
XCTAssertEqual(actual, expected)
XCTAssertTrue(condition)
XCTAssertFalse(condition)
XCTAssertNil(value)
XCTAssertNotNil(value)
XCTAssertThrowsError(try expression)

// Use custom helpers for floating-point
assertApproximatelyEqual(actual, expected, tolerance: 0.01)

// Use custom helpers for Codable
assertCodableRoundTrip(value)
```

## Test Helpers

### TestHelpers.swift

Located in `StoriTests/Helpers/TestHelpers.swift`:

```swift
// Floating-point comparison
assertApproximatelyEqual(_ actual: Double, _ expected: Double, tolerance: Double = 0.0001)

// Codable round-trip testing
assertCodableRoundTrip<T: Codable & Equatable>(_ value: T)

// Async test helpers
waitForCondition(timeout: TimeInterval, condition: () -> Bool)
```

### Test Audio Buffers

```swift
// Generate test audio
let sineWave = TestAudioBuffers.sineWaveBuffer(
    frequency: 440,
    sampleRate: 48000,
    frameCount: 1024,
    amplitude: 1.0
)

// Measure peak level
let peak = TestAudioBuffers.peakLevel(buffer)
```

### Mock Objects

Located in `StoriTests/Mocks/`:

- **MockAudioEngine.swift** - Lightweight audio engine for testing
- **MockProjectManager.swift** - Project management mock
- **MockFileSystem.swift** - File system mock

## Real-Time Safety Requirements

### CRITICAL: All Audio Thread Code MUST Be Real-Time Safe

**Real-time safe code**:
- ✅ No dynamic memory allocation (malloc, Array resizing, Dictionary operations)
- ✅ No lock contention (use pre-allocated, lock-free structures)
- ✅ No MainActor access (use atomic primitives or cached values)
- ✅ No disk I/O or network operations
- ✅ Bounded, predictable execution time

**How to validate**:
1. Write a test that exercises the audio thread code
2. Run under Instruments (Allocations, Time Profiler)
3. Verify zero allocations in audio callbacks
4. Verify < 10ms execution time for typical workloads

**Example**:
```swift
func testComponentRealTimeSafety() {
    // Pre-allocate buffer
    var buffer: [Int] = []
    buffer.reserveCapacity(32)
    
    // Simulate audio thread work
    for _ in 0..<100 {
        // Fill buffer
        for i in 0..<10 {
            buffer.append(i)
        }
        
        // Clear WITHOUT deallocating
        buffer.removeAll(keepingCapacity: true)
        
        // Verify capacity maintained
        XCTAssertGreaterThanOrEqual(buffer.capacity, 32)
    }
}
```

## Performance Testing

### Performance Test Guidelines

- Use `measure {}` blocks for performance-critical operations
- Run operations 100-10,000 times to get reliable measurements
- Aim for < 10ms latency for real-time audio code
- Aim for < 1ms for timing-critical operations (MIDI scheduling)

**Example**:
```swift
func testMIDISchedulingPerformance() {
    measure {
        // Schedule 1000 MIDI events
        for i in 0..<1000 {
            let beat = Double(i) * 0.25
            let note = UInt8(60 + (i % 12))
            // ... schedule event
        }
    }
}
```

## Integration Testing

### Integration Test Patterns

Integration tests verify that components work correctly together:

```swift
func testMIDIPlaybackIntegration() async throws {
    // Setup: Create real AudioEngine + MIDIPlaybackEngine
    let engine = AudioEngine()
    try await engine.start()
    
    // Action: Play MIDI region
    let region = MIDIRegion(...)
    try await engine.playMIDIRegion(region)
    
    // Verify: Check that notes were scheduled and played
    try await Task.sleep(nanoseconds: 100_000_000) // 100ms
    
    // Cleanup
    engine.stop()
}
```

## Coverage Goals

### Target Coverage by Component Type

- **CRITICAL** (AudioEngine, MIDI scheduling, recording): **90%+**
- **HIGH** (Plugin system, automation, mixing): **80%+**
- **MEDIUM** (Specialized engines, analysis): **70%+**
- **LOW** (Utilities, error types): **50%+**

### Overall Target

🎯 **80%+ line coverage** across all `Stori/Core/Audio/` components

## Continuous Integration

### CI Test Requirements

All PRs must:
1. Pass all existing tests
2. Maintain or improve code coverage
3. Include tests for new functionality
4. Pass real-time safety validation (no allocations in audio thread)

### Pre-Commit Checklist

- [ ] All tests pass locally
- [ ] New functionality has corresponding tests
- [ ] Real-time safety tests added for audio thread code
- [ ] Performance tests added for critical paths
- [ ] Coverage report shows no decrease in coverage

## Common Issues & Solutions

### Issue: Tests are slow
**Solution**: Run only relevant test files during development:
```bash
xcodebuild test -only-testing:StoriTests/YourTests
```

### Issue: Flaky async tests
**Solution**: Use proper async/await patterns and XCTestExpectation:
```swift
func testAsync() async throws {
    let expectation = expectation(description: "Callback fired")
    
    await withCheckedContinuation { continuation in
        // Async operation
        continuation.resume()
    }
    
    await fulfillment(of: [expectation], timeout: 1.0)
}
```

### Issue: Real-time safety violations
**Solution**: Profile with Instruments (Allocations tool):
1. Run test with Instruments attached
2. Look for allocations in audio thread
3. Replace dynamic allocation with pre-allocated buffers

### Issue: Performance regressions
**Solution**: Run performance tests regularly:
```bash
xcodebuild test -only-testing:StoriTests/Audio -run-order random
```

## Contributing

### How to Add New Tests

1. Identify untested component in `AUDIO_ENGINE_TEST_STRATEGY.md`
2. Create test file following template above
3. Implement tests covering:
   - Initialization
   - Core functionality
   - Error handling
   - Real-time safety (if applicable)
   - Performance (if applicable)
4. Run tests and verify coverage
5. Submit PR with tests and coverage report

### Test Review Checklist

Reviewers should verify:
- [ ] Tests follow naming conventions
- [ ] Tests are focused and atomic (one thing per test)
- [ ] Real-time safety tests for audio thread code
- [ ] Performance tests for critical paths
- [ ] Error cases covered
- [ ] No test interdependencies (tests can run in any order)
- [ ] Proper cleanup in tearDown()

## Resources

- [XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [Core Audio Programming Guide](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/)
- [Real-Time Audio Programming Best Practices](https://www.rossbencina.com/code/real-time-audio-programming-101-time-waits-for-nothing)
- [Stori Test Strategy](../../AUDIO_ENGINE_TEST_STRATEGY.md)

---

**Last Updated**: 2026-02-04  
**Coverage Status**: 🟡 In Progress - Target 80%+  
**Priority**: 🔴 CRITICAL - Foundation for open-source contributions
