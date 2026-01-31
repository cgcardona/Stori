# Stori Audio Engine Deep-Dive Review

**Date**: January 30, 2026  
**Reviewer**: Senior Audio Systems Engineer  
**Scope**: Core Audio and MIDI Systems (Excluding Web3/Networking)

---

## 1. Executive Summary

### Overall Assessment: **Solid Intermediate with Professional Aspirations**

This codebase demonstrates **above-average architectural awareness** for an MVP DAW. The developer(s) clearly understand audio-specific concerns like real-time safety, threading boundaries, and the peculiarities of AVAudioEngine. Many patterns are correct and would pass review at professional audio companies.

**However**, there are several areas where "it works" masks fragility that will surface under stress, scale, or edge conditions. The architecture is fundamentally sound but needs hardening in specific areas before it can be considered production-grade.

### Maturity Rating: 6.5/10

| Aspect | Rating | Notes |
|--------|--------|-------|
| Architecture | 7/10 | Good separation (TransportController, MixerController, etc.) |
| Real-Time Safety | 6/10 | Most patterns correct, some violations in edge paths |
| Threading Model | 6/10 | Generally correct boundaries, some async hazards |
| Plugin Handling | 7/10 | Robust format negotiation, good crash isolation patterns |
| State Management | 6/10 | Some desync risks between engine and UI |
| MIDI Timing | 5/10 | Timer-based approach has inherent limitations |
| Scalability | 6/10 | Will struggle past 32-64 tracks without optimization |

### Biggest Existential Risks

1. **MIDI Timing Drift**: Timer-based scheduling (1000Hz) is fundamentally less accurate than audio-callback scheduling. This will be audible with complex MIDI arrangements.

2. **Graph Mutation Complexity**: The `modifyGraphSafely` pattern is correct but the blast radius is large. Engine stop/reset/restart on every structural change will cause audible glitches.

3. **Main Thread Audio Operations**: Several operations that touch audio state happen on MainActor without sufficient isolation from the audio thread.

---

## 2. High-Risk Issues (Must Fix)

### H-1: MIDI Scheduler Uses Timer Instead of Audio Callback

**Location**: `SampleAccurateMIDIScheduler.swift`

**Problem**: The scheduler fires at 1000Hz (1ms timer) on a dedicated dispatch queue, polling the beat position atomically. While this sounds precise, timers are inherently subject to system scheduling jitter, especially under CPU load.

```swift
// Current approach (problematic)
let timer = DispatchSource.makeTimerSource(flags: .strict, queue: midiQueue)
timer.schedule(deadline: .now(), repeating: .milliseconds(timerIntervalMs), leeway: .microseconds(100))
```

**Why This Is Dangerous for Audio**:
- GCD timers can experience jitter of 1-5ms under system load
- At 120 BPM, 5ms = ~0.01 beats, which is audible as flamming on fast passages
- The "lookahead window" (0.05 beats) helps but doesn't solve the fundamental issue
- Professional DAWs schedule MIDI from the audio render callback for sample-accurate timing

**How It Manifests**:
- Notes playing slightly early or late relative to audio playback
- Flamming/doubling artifacts on sustained notes
- Drift between audio and MIDI over long playback (30+ minutes)
- Issues become worse when CPU is under load (many tracks, plugins)

**Suggested Fix**:
Implement a render-callback-based MIDI scheduler:
1. During the audio render callback, calculate which MIDI events fall within the current buffer
2. Use `AUScheduleMIDIEventBlock` with calculated sample offsets for each event
3. Keep the current timer as a backup/preview mechanism only

**Priority**: HIGH - This is a core timing issue that affects the fundamental DAW experience.

---

### H-2: Graph Mutations Stop/Reset Entire Engine

**Location**: `AudioEngine.swift` - `modifyGraphSafely()`

**Problem**: Every structural graph change (adding plugin, adding track) stops the entire engine, resets it, performs the change, then restarts.

```swift
case .structural:
    // STRUCTURAL: Full stop, reset, work, restart
    if wasRunning {
        engine.stop()
        engine.reset()  // Clears ALL audio buffers
        
        // Reset all samplers after engine.reset()
        for trackId in trackNodes.keys {
            if let instrument = InstrumentManager.shared.getInstrument(for: trackId) {
                instrument.fullRenderReset()
            }
        }
    }
    
    try work()
    // ... restart
```

**Why This Is Dangerous for Audio**:
- `engine.reset()` clears ALL pending audio buffers across ALL tracks
- This causes audible glitches even on tracks unrelated to the change
- Users inserting a plugin on track 5 shouldn't hear dropout on tracks 1-4
- Professional DAWs use node-level isolation to minimize blast radius

**How It Manifests**:
- Audible pops/clicks when inserting plugins during playback
- Dropout on all tracks when any single track changes
- Inability to "work while playing" - a standard DAW workflow

**Suggested Fix**:
1. Implement a "hot-swap" path for plugin insertion that only disconnects/reconnects the affected chain
2. Use AVAudioEngine's ability to connect/disconnect individual nodes without stopping
3. Reserve full engine reset for catastrophic scenarios (device change, sample rate change)

**Priority**: HIGH - This is a usability issue that will frustrate every user.

---

### H-3: Position Timer on Main Thread with Task Hop

**Location**: `TransportController.swift` - `setupPositionTimer()`

**Problem**: The position timer fires on the main runloop and uses `Task { @MainActor in ... }` to process updates:

```swift
positionTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
    Task { @MainActor in
        self?.updatePosition()
    }
}
```

**Why This Is Dangerous for Audio**:
- Timer callbacks on the main runloop are affected by UI work (scrolling, animations)
- The `Task` wrapper adds additional scheduling latency
- 60 FPS is adequate for UI but the hop introduces non-determinism
- Automation values calculated here may be applied late

**How It Manifests**:
- Playhead jitter during intensive UI operations
- Automation not applied at correct time during heavy drawing
- Position callbacks delayed when user scrolls timeline

**Suggested Fix**:
1. Use a dedicated high-priority timer for position tracking (not main thread)
2. Store position atomically (already done correctly with `atomicBeatPosition`)
3. Only use the main thread timer for UI updates, not automation application
4. Consider using `CADisplayLink` if available on macOS for smoother UI sync

**Priority**: MEDIUM-HIGH - Affects user perception of timing accuracy.

---

### H-4: Async/Await Near Audio Operations

**Location**: Multiple files including `loadTrackInstrument()`, `insertPlugin()`

**Problem**: Several operations that affect the audio graph use async/await:

```swift
func loadTrackInstrument(trackId: UUID, descriptor: PluginDescriptor) async throws {
    // ... async AU instantiation ...
    
    modifyGraphSafely {
        // ... graph mutation inside sync closure
    }
}
```

**Why This Is Dangerous for Audio**:
- async/await can introduce unbounded delays between steps
- The state captured at the start may be stale by the time execution continues
- Graph generation checks help but don't fully protect against races
- "Await points" can be interrupted by other async work

**Good Pattern Already in Place**: The code uses `graphGeneration` counters to detect stale operations. This is correct.

**Suggested Fix**:
1. Continue using generation counters (good)
2. Consider explicit locking for critical sequences rather than relying on async scheduling
3. Document the invariants that must hold across await points
4. Add assertions that validate state consistency after await points

**Priority**: MEDIUM - The generation counter pattern provides protection but is easy to forget.

---

## 3. Medium-Risk / Architectural Smells

### M-1: Plugin Chain Lazy Realization Complexity

**Location**: `PluginChain.swift`

The lazy realization pattern (only creating inputMixer/outputMixer when plugins are inserted) is a good optimization, but it adds significant complexity:

```swift
var isRealized: Bool {
    return _inputMixer != nil && _outputMixer != nil && _inputMixer?.engine != nil
}
```

**Smell**: Multiple places must check `isRealized` before accessing chain nodes:
- `rebuildTrackGraph`
- `rebuildChainConnections`
- `validateTrackConnections`

**Risk**: Easy to forget the check, leading to crashes when accessing uninitialized mixers.

**Recommendation**: Consider using an enum state machine instead:
```swift
enum ChainState {
    case unrealized
    case realized(input: AVAudioMixerNode, output: AVAudioMixerNode)
}
```

---

### M-2: Mixer Bus Accumulation Workaround

**Location**: `PluginChain.swift` - `recreateMixers()`

The code explicitly addresses AVAudioMixerNode bus accumulation:

```swift
// ROOT CAUSE IDENTIFIED: AVAudioMixerNode accumulates input buses when sources are
// reconnected multiple times. After engine.reset(), the mixer's internal bus mapping
// can become inconsistent...
for bus in 0..<oldInputMixer.numberOfInputs {
    engine.disconnectNodeInput(oldInputMixer, bus: bus)
}
```

**Assessment**: This is a known AVAudioEngine bug/behavior. The workaround is correct but indicates the complexity of working with this API.

**Recommendation**: Add regression tests that detect bus accumulation by checking `numberOfInputs` after reconnection sequences.

---

### M-3: Solo State Reconstruction After Clear

**Location**: `AudioEngine.swift`

```swift
private func clearAllTracks() {
    // First, explicitly clean up each track node
    // ...
    mixerController.clearSoloTracks()  // Clears state
}

private func setupTracksForProject(_ project: AudioProject) {
    // ...
    // CRITICAL FIX: Rebuild soloTracks set from project data
    mixerController.updateAllTrackStates()  // Must restore
}
```

**Smell**: State is cleared and then must be restored. If `updateAllTrackStates()` is forgotten (or fails), solo state is lost.

**Recommendation**: Make state reconstruction atomic or avoid clearing in the first place.

---

### M-4: Dual Sample Rate Handling

**Location**: `TrackAudioNode.swift` - `scheduleFromPosition()`

The comments extensively document the dual sample rate system:

```swift
// TODO: DUAL SAMPLE RATE SYSTEM - CRITICAL FOR ACCURATE TIMING
// We use TWO different sample rates in audio scheduling:
// 1. playerSampleRate (from playerNode.outputFormat) - Used for TIMING
// 2. fileSampleRate (sr, from audioFile.processingFormat) - Used for FRAME POSITIONS
```

**Assessment**: This is correctly implemented, but the 40+ line comment indicates complexity that could lead to future bugs.

**Recommendation**: Extract this into a dedicated `AudioScheduler` type with explicit sample rate handling methods.

---

### M-5: Callback-Based Dependency Injection in Controllers

**Location**: `TransportController.swift`, `MixerController.swift`, etc.

Each controller receives 5-10 closures for accessing shared state:

```swift
init(
    getProject: @escaping () -> AudioProject?,
    isInstallingPlugin: @escaping () -> Bool,
    isGraphStable: @escaping () -> Bool,
    getSampleRate: @escaping () -> Double,
    onStartPlayback: @escaping (_ fromBeat: Double) -> Void,
    // ... more closures
)
```

**Assessment**: This is a reasonable pattern for decoupling, but it has drawbacks:
- Easy to pass stale closures
- Debugging which closure does what is difficult
- No compile-time checking that all dependencies are satisfied

**Recommendation**: Consider a `AudioEngineContext` protocol that controllers receive instead.

---

### M-6: InstrumentManager Singleton Pattern

**Location**: `InstrumentManager.shared`

The codebase correctly identifies this as a concern:

```swift
// NOTE: Track instruments are now accessed via InstrumentManager.shared (single source of truth)
```

**Risk**: Singletons make testing difficult and create hidden dependencies.

**Recommendation**: For an MVP this is acceptable, but plan for dependency injection in v2.

---

### M-7: DispatchQueue.main.asyncAfter in Audio Paths

**Location**: Multiple locations including `MIDIPlaybackEngine.swift`

```swift
func previewNote(pitch: UInt8, velocity: UInt8 = 100, duration: TimeInterval = 0.3) {
    instrumentManager?.noteOn(pitch: pitch, velocity: velocity)
    
    // Schedule note off
    DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
        self?.instrumentManager?.noteOff(pitch: pitch)
    }
}
```

**Assessment**: This is fine for preview but would be problematic for production playback. The comment context suggests this is preview-only.

**Recommendation**: Ensure this pattern is never used in the main playback path.

---

### M-8: 60Hz Automation Update Rate

**Location**: `TransportController.swift`

Automation is applied at 60 FPS (16.7ms intervals):

```swift
positionTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true)
```

**Assessment**: 60Hz is adequate for volume/pan automation but may cause audible stepping on fast automation curves.

**Recommendation**: 
- For MVP this is acceptable
- Consider moving to audio-rate automation for v2 (apply in render callback)
- Document the limitation in user-facing docs

---

### M-9: Plugin Parameter Rate Limiting

**Location**: `PluginInstance.swift`

```swift
/// M-9: Per-instance rate limit using token bucket (no Date allocations).
private var parameterTokens: Int = 120
private static let maxParameterUpdatesPerSecond = 120
```

**Assessment**: Good defensive pattern against automation spam.

**Potential Issue**: The per-instance limit of 120/sec combined with global 1000/sec limit could starve legitimate automation on projects with many plugins.

**Recommendation**: Log when rate limiting kicks in so users can diagnose "automation not responding" issues.

---

## 4. Low-Risk Polish / Professionalism Gaps

### L-1: Hardcoded Buffer Sizes

**Location**: Multiple files

```swift
volumeNode.installTap(onBus: 0, bufferSize: 1024, format: format)
```

**Recommendation**: Make buffer size configurable or at least define as a constant.

---

### L-2: Missing Error Recovery on Engine Start Failure

**Location**: `AudioEngine.swift`

```swift
do {
    try engine.start()
} catch {
    // Try to reset and start again
    engine.stop()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        // One retry
    }
}
```

**Recommendation**: Add exponential backoff and user notification on persistent failure.

---

### L-3: Incomplete Sidechain Implementation

**Location**: `TrackPluginManager.swift`

```swift
func getSidechainSource(trackId: UUID, slot: Int) -> SidechainSource {
    if sidechainConnections[trackId]?[slot] != nil {
        return .track(trackId: UUID()) // Placeholder
    }
    return .none
}
```

**Recommendation**: Either complete the implementation or remove the API.

---

### L-4: Debug Logging Still Present

**Location**: Multiple files

```swift
private let debugAudioFlow = false
private let debugPlugin = false
```

**Assessment**: Good that these are disabled, but should be removed or moved to build configuration.

---

### L-5: Magic Numbers in Automation

**Location**: `AutomationProcessor.swift`

```swift
case .exponential:
    let expT = pow(t, 2.5)  // Why 2.5?
```

**Recommendation**: Document or extract these curve coefficients.

---

### L-6: SoundFont Size Limit

**Location**: `SamplerEngine.swift`

```swift
private static let maxSoundFontFileSize: Int64 = 300_000_000
```

**Assessment**: 300MB is reasonable for an MVP. Professional SoundFonts can be larger.

**Recommendation**: Document this limit in user-facing docs.

---

## 5. Positive Callouts

### P-1: Real-Time Safe Metering (Excellent)

**Location**: `TrackAudioNode.swift`, `MeteringService.swift`

The metering implementation is textbook correct:

```swift
/// REAL-TIME SAFE: Level metering uses `os_unfair_lock` protected storage.
/// The audio tap callback writes levels with lock (never blocks), and the main thread
/// reads via public properties with lock.
private var levelLock = os_unfair_lock_s()
```

- Uses `os_unfair_lock` (audio-safe, never blocks)
- SIMD-optimized level calculation via Accelerate
- No DispatchQueue.main.async in the tap callback
- Peak decay correctly implemented

**This is professional-grade metering code.**

---

### P-2: Pre-Allocated Recording Buffer Pool

**Location**: `RecordingBufferPool.swift`

```swift
/// A lock-free buffer pool for real-time audio recording.
/// Pre-allocates AVAudioPCMBuffer instances to avoid allocation on the audio thread.
```

- Pre-allocates buffers upfront
- Uses `os_unfair_lock` for acquisition
- Includes pool health statistics (`isLow`, `isExhausted`)
- Has periodic fsync for crash protection

**This shows understanding of real-time constraints.**

---

### P-3: Beats-First Architecture

**Location**: Throughout the codebase

The consistent use of beats as the primary time unit shows good architectural discipline:

```swift
/// ARCHITECTURE: Beats-First
/// - All positions are stored and tracked in beats (musical time)
/// - Seconds are only used when interfacing with AVAudioEngine callbacks
```

This makes tempo changes and time signature handling much cleaner.

---

### P-4: Thread-Safe Atomic Beat Position

**Location**: `TransportController.swift`

```swift
/// Thread-safe read of current beat position (for MIDI scheduler)
nonisolated var atomicBeatPosition: Double {
    var lock = beatPositionLock
    os_unfair_lock_lock(&lock)
    defer { os_unfair_lock_unlock(&lock) }
    return _atomicBeatPosition
}
```

This allows the MIDI scheduler (on its own queue) to read position without MainActor hop.

---

### P-5: Plugin Crash Isolation (Greylist Pattern)

**Location**: `PluginInstance.swift`, `PluginGreylist`

```swift
// SMART SANDBOXING: Check if plugin should be loaded out-of-process
let shouldSandbox = sandboxed || PluginGreylist.shared.shouldSandbox(descriptor)
```

Recording plugin crashes and auto-sandboxing them is a professional pattern.

---

### P-6: Format Negotiation with Fallback

**Location**: `PluginInstance.swift`

```swift
private func negotiateFormat(for audioUnit: AVAudioUnit, targetRate: Double) throws {
    // Try preferred format first
    // Fall back to plugin's native rate
    // Last resort: exact native formats
}
```

This multi-tier negotiation is robust against plugin quirks.

---

### P-7: Lazy Plugin Chain Realization

**Location**: `PluginChain.swift`

```swift
/// ARCHITECTURE NOTE (Lazy Node Attachment):
/// To reduce node count, the inputMixer and outputMixer are only created
/// when plugins are actually inserted.
```

This optimization saves 2 nodes per track for typical projects.

---

### P-8: Graph Validation After Rebuild

**Location**: `AudioEngine.swift`

```swift
/// Validates that a track's audio graph connections are properly established
private func validateTrackConnections(trackId: UUID) {
    // Check panNode has output connections
    // Check volumeNode → panNode connection
    // Check eqNode → volumeNode connection
}
```

Post-rebuild validation is a professional defensive pattern.

---

### P-9: Generation Counter for Stale Operations

**Location**: `AudioEngine.swift`, `TransportController.swift`

```swift
// Check if graph was rebuilt while we were waiting (stale operation)
guard currentGeneration == self.graphGeneration else { return }
```

Using generation counters to detect stale async operations is the correct pattern.

---

### P-10: Plugin Delay Compensation (PDC)

**Location**: `PluginLatencyManager.swift`, `TrackPluginManager.swift`

PDC is implemented and updates when plugins change:

```swift
/// Recalculate and apply delay compensation for all tracks
func updateDelayCompensation() {
    let compensation = PluginLatencyManager.shared.calculateCompensation(trackPlugins: trackPlugins)
    // Apply to each track node
}
```

---

## 6. Prioritized Action Items

### Immediate (Before Beta)

1. **[H-1]** Evaluate render-callback MIDI scheduling or document the limitation
2. **[H-2]** Implement node-level plugin hot-swap without full engine reset
3. **[H-3]** Move automation application off the UI timer path

### Short-Term (Before Public Release)

4. **[H-4]** Add assertions after await points for state consistency
5. **[M-1]** Simplify plugin chain state with explicit enum
6. **[M-3]** Make state reconstruction atomic in clearAllTracks

### Medium-Term (Post-Release Polish)

7. **[M-4]** Extract dual sample rate handling to dedicated type
8. **[M-5]** Consider protocol-based dependency injection
9. **[M-8]** Document 60Hz automation limitation

---

## 7. Testing Recommendations

### Unit Tests Needed

1. **MIDI Timing Test**: Record timestamps of scheduled vs actual MIDI events under CPU load
2. **Graph Mutation Stress Test**: Add/remove plugins rapidly during playback
3. **Sample Rate Switching Test**: Change audio device during playback
4. **Long Session Test**: Run playback for 60+ minutes, measure cumulative drift
5. **Bus Accumulation Test**: Reconnect sources repeatedly, verify bus count

### Integration Tests Needed

1. **Plugin Chain Rebuild**: Insert plugin during playback on track N, verify no dropout on track M
2. **Cycle Loop Accuracy**: Verify loop point timing with audio analysis
3. **Automation Accuracy**: Record automation curves, verify playback matches

---

## 8. Conclusion

This DAW codebase shows **strong foundational understanding** of audio software requirements. The architecture is modular, the real-time patterns are mostly correct, and the code is well-documented.

The main areas for improvement are:

1. **Timing precision** - Moving from timer-based to render-callback-based scheduling
2. **Graph mutation granularity** - Reducing blast radius of changes
3. **Testing coverage** - Especially for edge cases and stress scenarios

For an MVP, this codebase is **ready for internal testing** but should address at least H-1 and H-2 before external beta testing. The positive patterns in place provide a solid foundation for iteration.

**Final Grade: B+** (Strong foundations, needs polish in timing subsystem)

---

*This review reflects the codebase state as of January 30, 2026. Subsequent changes should be evaluated against these recommendations.*
