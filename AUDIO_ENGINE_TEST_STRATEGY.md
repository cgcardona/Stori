# Audio Engine Test Coverage Strategy
## Mission: Achieve 80%+ Test Coverage for Production-Grade DAW

**Goal**: Establish comprehensive test coverage for all audio engine components to signal to open-source contributors that Stori is mission-critical, production-ready software.

---

## Current State Analysis

### Existing Test Files (14)
✅ **AudioEngineErrorTrackerTests.swift** - Error tracking and recovery  
✅ **AudioEngineHealthMonitorTests.swift** - Health monitoring  
✅ **AudioGraphManagerTests.swift** - Audio graph management  
✅ **AudioPerformanceMonitorTests.swift** - Performance monitoring  
✅ **AudioResourcePoolTests.swift** - Resource pooling  
✅ **AutomationProcessorTests.swift** - Automation processing  
✅ **DeviceConfigurationManagerTests.swift** - Device configuration  
✅ **MIDITimingReferenceTests.swift** - MIDI timing  
✅ **MixerControllerTests.swift** - Mixer functionality  
✅ **PlaybackSchedulingCoordinatorTests.swift** - Playback scheduling  
✅ **PluginChainStateTests.swift** - Plugin chain state  
✅ **RecordingControllerTests.swift** - Recording functionality  
✅ **TrackAudioNodeTests.swift** - Track audio node  
✅ **TransportControllerTests.swift** - Transport controls  

### Skipped Tests (2)
⏸️ **MIDIPlaybackEngineTests.swift.skip** - NEEDS ACTIVATION  
⏸️ **ProjectLifecycleManagerTests.swift.skip** - NEEDS ACTIVATION  

### Audio Source Files Needing Tests (33)

#### 🔴 CRITICAL - Core Engine Components (High Priority)
1. **AudioEngine.swift** (2409 lines) - MAIN ENGINE
2. **AudioEngine+GraphBuilding.swift** - Graph construction
3. **AudioEngine+Instruments.swift** - Instrument management
4. **AudioEngine+Playback.swift** - Playback logic
5. **AudioEngine+Automation.swift** (200 lines) - Automation integration
6. **MIDIPlaybackEngine.swift** (387 lines) - MIDI playback ⚠️ PARTIALLY COVERED (skipped)
7. **SampleAccurateMIDIScheduler.swift** (804 lines) - MIDI scheduling
8. **RecordingBufferPool.swift** - Buffer management
9. **TrackNodeManager.swift** (271 lines) - Track node lifecycle
10. **ProjectLifecycleManager.swift** - Project lifecycle ⚠️ PARTIALLY COVERED (skipped)

#### 🟡 HIGH - Audio Processing & Effects
11. **PluginInstance.swift** - Individual plugin instances
12. **PluginChain.swift** - Plugin chain processing
13. **TrackPluginManager.swift** - Plugin management per track
14. **PluginLatencyManager.swift** - PDC (Plugin Delay Compensation)
15. **InstrumentPluginHost.swift** - Instrument hosting
16. **SandboxedPluginHost.swift** - Sandboxed plugin execution
17. **BusAudioNode.swift** - Bus audio processing
18. **BusManager.swift** - Bus management

#### 🟢 MEDIUM - Specialized Engines & Services
19. **MetronomeEngine.swift** - Click track
20. **SequencerEngine.swift** - Step sequencer
21. **SynthEngine.swift** - Built-in synth
22. **SamplerEngine.swift** - Built-in sampler
23. **DrumKitEngine.swift** - Drum machine
24. **StepInputEngine.swift** - Step recording
25. **MIDIBounceEngine.swift** - MIDI to audio bounce
26. **QuantizationEngine.swift** - Quantization logic
27. **MeteringService.swift** - Level metering
28. **AudioAnalyzer.swift** - Audio analysis
29. **EffectTypeMapping.swift** - Effect type utilities

#### 🔵 LOW - Infrastructure & Utilities
30. **AudioEngineContext.swift** - Context management
31. **AudioEngineDiagnostics.swift** - Diagnostic tools
32. **AudioEngineError.swift** - Error types
33. **AudioFormatCoordinator.swift** - Format coordination
34. **AudioSchedulingContext.swift** - Scheduling context
35. **TransportDependencies.swift** - Transport dependencies

---

## Test Coverage Roadmap

### Phase 1: CRITICAL - Core Engine (Week 1)
**Target**: Cover the audio engine backbone - playback, recording, graph management

#### 1.1 AudioEngineTests.swift
**Focus**: Core engine initialization, start/stop, error handling
```swift
- testEngineInitialization()
- testEngineStartStop()
- testEngineStartWithInvalidConfiguration()
- testEngineStop WhenNotRunning()
- testEngineSampleRateChange()
- testEngineDeviceChange()
- testEngineErrorRecovery()
- testEngineMemoryCleanup()
```

#### 1.2 SampleAccurateMIDISchedulerTests.swift
**Focus**: MIDI timing accuracy, real-time safety (CRITICAL - 804 lines, just fixed for real-time safety)
```swift
- testScheduleMIDINoteOnOff()
- testScheduleMIDITiming Accuracy()
- testScheduleMIDIConcurrentEvents()
- testScheduleMIDIBufferOverflow()
- testScheduleMIDIEventCancellation()
- testScheduleMIDIRealTimeSafety() // NO ALLOCATION
- testScheduleMIDIPerformanceUnder Load()
```

#### 1.3 MIDIPlaybackEngineTests.swift (UNSKIP + ENHANCE)
**Focus**: MIDI playback, region scheduling, loop handling
```swift
- testMIDIPlaybackBasic()
- testMIDIPlaybackWithLoop()
- testMIDIPlaybackWithAutomation()
- testMIDIPlaybackRealTimeSafety() // NEW - validate recent fixes
- testMIDIPlaybackMissingAUBlock() // NEW - error path
```

#### 1.4 TrackNodeManagerTests.swift
**Focus**: Track lifecycle, node creation/destruction, cache updates
```swift
- testCreateTrackNode()
- testRemoveTrackNode()
- testAutomationCacheUpdate() // NEW - validate recent fix
- testConcurrentTrackOperations()
- testTrackNodeCleanup()
```

#### 1.5 RecordingBufferPoolTests.swift
**Focus**: Buffer allocation, reuse, memory management
```swift
- testBufferAcquisition()
- testBufferRelease()
- testBufferPoolExhaustion()
- testBufferPoolRealTimeSafety()
- testBufferPoolPerformance()
```

### Phase 2: HIGH - Plugin System & Audio Graph (Week 2)
**Target**: Plugin hosting, chain processing, latency compensation

#### 2.1 PluginInstanceTests.swift
```swift
- testPluginInstantiation()
- testPluginParameterChange()
- testPluginPresetLoad()
- testPluginStateSerialize()
- testPluginBypass()
- testPluginCrashRecovery()
```

#### 2.2 PluginChainTests.swift
```swift
- testPluginChainProcessing()
- testPluginChainInsert()
- testPluginChainRemove()
- testPluginChainReorder()
- testPluginChainBypass()
- testPluginChainSerialize()
```

#### 2.3 PluginLatencyManagerTests.swift (PDC)
```swift
- testLatencyCompensation()
- testLatencyCalculation()
- testLatencyWithMultiplePlugins()
- testLatencyDynamicUpdate()
- testPDCAccuracy()
```

#### 2.4 GraphBuildingTests.swift
```swift
- testGraphConstruction()
- testGraphConnectionValidation()
- testGraphReconnectionOnChange()
- testGraphDisconnection()
- testGraphCycleDetection()
```

### Phase 3: MEDIUM - Specialized Engines (Week 3)
**Target**: Built-in instruments, sequencer, quantization

#### 3.1 MetronomeEngineTests.swift
```swift
- testMetronomeClick()
- testMetronomeTiming()
- testMetronomeAccent()
- testMetronomeVolumeControl()
```

#### 3.2 SequencerEngineTests.swift
```swift
- testSequencerPlayback()
- testSequencerLoop()
- testSequencerStepEdit()
- testSequencerPatternSwitch()
```

#### 3.3 QuantizationEngineTests.swift
```swift
- testQuantizeToGrid()
- testQuantizeWithStrength()
- testQuantizeWithSwing()
- testQuantizePreserveVelocity()
- testQuantizeDifferentResolutions()
```

#### 3.4 Built-in Instrument Tests
- **SynthEngineTests.swift** - Oscillator, filter, envelope
- **SamplerEngineTests.swift** - Sample playback, loop, pitch
- **DrumKitEngineTests.swift** - Drum sample triggering

### Phase 4: LOW - Utilities & Infrastructure (Week 4)
**Target**: Supporting infrastructure, diagnostics, utilities

#### 4.1 AudioAnalyzerTests.swift
```swift
- testPeakDetection()
- testRMSCalculation()
- testSpectrumAnalysis()
- testPhaseCorrelation()
```

#### 4.2 MeteringServiceTests.swift
```swift
- testLevelMetering()
- testPeakHold()
- testMeteringPerformance() // Validate O(n) loops acceptable
```

#### 4.3 BusManagerTests.swift
```swift
- testBusCreation()
- testBusRouting()
- testBusSendLevels()
- testBusPrePostFader()
```

---

## Test Quality Standards

### Real-Time Safety Tests (MANDATORY for audio threads)
Every audio thread component MUST have tests validating:
```swift
func testComponentRealTimeSafety() {
    // 1. No dynamic memory allocation
    // 2. No lock contention under load
    // 3. No MainActor access from audio thread
    // 4. Bounded, predictable performance
}
```

### Performance Benchmarks (MANDATORY for critical paths)
```swift
func testComponentPerformance() {
    measure {
        // Run typical operations 10K-100K times
        // Must complete in < 10ms for real-time code
    }
}
```

### Error Path Coverage
```swift
func testComponentErrorHandling() {
    // Test all error conditions
    // Ensure graceful degradation, no crashes
}
```

### Integration Tests
```swift
func testComponentIntegration() {
    // Test interaction with real components
    // Validate end-to-end workflows
}
```

---

## Test Helpers & Infrastructure

### Essential Test Utilities
1. **TestAudioBuffers** - Sine wave, noise, silence generators ✅ EXISTS
2. **MockAudioEngine** - Lightweight engine mock ✅ EXISTS
3. **TestAudioFormat** - Standard test formats
4. **RealTimeValidator** - Instrument allocation/locks
5. **TimingValidator** - Verify sample-accurate timing
6. **AudioFileFactory** - Generate test audio files
7. **PluginFactory** - Create test plugins
8. **ProjectFactory** - Generate test projects

### Coverage Measurement
```bash
# Run audio tests with coverage
xcodebuild test -project Stori.xcodeproj -scheme Stori \
  -destination 'platform=macOS' \
  -only-testing:StoriTests/Audio \
  -enableCodeCoverage YES

# Extract coverage report
xcrun xccov view --report \
  <DerivedData>/Logs/Test/*.xcresult
```

---

## Success Criteria

### Minimum Coverage Targets
- ✅ **Critical Components**: 90%+ coverage
  - AudioEngine, MIDIPlaybackEngine, SampleAccurateMIDIScheduler, RecordingController
- ✅ **High Priority Components**: 80%+ coverage
  - Plugin system, automation, graph building, transport
- ✅ **Medium Priority Components**: 70%+ coverage
  - Specialized engines, metering, analysis
- ✅ **Low Priority Components**: 50%+ coverage
  - Utilities, error types, context objects

### Overall Target
- 🎯 **80%+ line coverage** across all Core/Audio components
- 🎯 **90%+ branch coverage** for error handling paths
- 🎯 **100% coverage** of real-time audio thread code

### Quality Gates
- [ ] All tests pass consistently (no flaky tests)
- [ ] All real-time safety tests validate zero allocation
- [ ] All performance tests meet timing requirements
- [ ] All error paths tested with graceful failure
- [ ] All public APIs documented and tested

---

## Execution Plan

### Week 1: Core Engine (Phase 1)
- **Day 1-2**: AudioEngine core tests
- **Day 3**: SampleAccurateMIDIScheduler tests
- **Day 4**: Unskip + enhance MIDI playback tests
- **Day 5**: TrackNodeManager + RecordingBufferPool tests

### Week 2: Plugin System (Phase 2)
- **Day 1-2**: PluginInstance + PluginChain tests
- **Day 3**: PluginLatencyManager (PDC) tests
- **Day 4-5**: Graph building + integration tests

### Week 3: Specialized Engines (Phase 3)
- **Day 1**: Metronome + Sequencer tests
- **Day 2**: Quantization tests
- **Day 3-5**: Built-in instruments (Synth, Sampler, DrumKit)

### Week 4: Infrastructure (Phase 4)
- **Day 1**: Analyzer + Metering tests
- **Day 2**: Bus management tests
- **Day 3-4**: Integration tests + cleanup
- **Day 5**: Coverage report + documentation

---

## Open Source Contributor Onboarding

### Test Documentation (README in StoriTests/Audio/)
Create a comprehensive guide:
```markdown
# Audio Engine Testing Guide

## Running Tests
## Writing New Tests
## Test Helpers
## Real-Time Safety Guidelines
## Performance Benchmarking
## Common Patterns
```

### Test Template
Provide a starter template for new test files:
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
        // Setup
    }
    
    override func tearDown() async throws {
        // Cleanup
    }
    
    // MARK: - Initialization Tests
    
    func testComponentInitialization() {
        // Test
    }
    
    // MARK: - Functional Tests
    
    // MARK: - Error Handling Tests
    
    // MARK: - Real-Time Safety Tests
    
    // MARK: - Performance Tests
}
```

---

## Metrics & Tracking

### Weekly Progress Dashboard
Track and report:
- [ ] Lines of code covered
- [ ] Test files created
- [ ] Critical bugs found via testing
- [ ] Performance regressions caught
- [ ] Real-time violations detected

### GitHub Issue Template: Test Coverage Task
```markdown
## Test Coverage Task: [Component Name]

**Component**: `Stori/Core/Audio/ComponentName.swift`
**Priority**: [CRITICAL | HIGH | MEDIUM | LOW]
**Target Coverage**: [90% | 80% | 70% | 50%]

**Tests to Write**:
- [ ] Initialization tests
- [ ] Functional tests (core behavior)
- [ ] Error handling tests
- [ ] Edge case tests
- [ ] Real-time safety tests (if applicable)
- [ ] Performance tests

**Estimated Effort**: [Small | Medium | Large]
**Dependencies**: [List any blockers or prerequisites]
```

---

## Next Steps

1. **IMMEDIATE**: Unskip and fix `MIDIPlaybackEngineTests.swift` and `ProjectLifecycleManagerTests.swift`
2. **THIS WEEK**: Create `AudioEngineTests.swift` and `SampleAccurateMIDISchedulerTests.swift`
3. **ONGOING**: Add one new test file per day following the roadmap
4. **CONTINUOUS**: Run tests in CI/CD on every commit
5. **MONTHLY**: Generate coverage reports and track progress

---

## Conclusion

This testing strategy transforms Stori from "promising project" to "production-ready DAW." With 80%+ test coverage, clear documentation, and real-time safety validation, we signal to the open-source community:

> **"This is mission-critical software. We take quality seriously. Your contributions will be built on a solid foundation."**

The comprehensive test suite becomes our competitive advantage—open-source contributors will choose Stori over Ardour because our modern Swift codebase is well-tested, well-documented, and easy to extend.

---

**Status**: READY TO EXECUTE  
**Owner**: Audio Engine Team  
**Timeline**: 4 weeks to 80% coverage  
**Success Metric**: Test coverage report showing 80%+ for Core/Audio components
