# Stori Audio Engine Deep Dive Review

**Reviewer**: Senior Audio Systems Engineer  
**Date**: January 30, 2026  
**Scope**: Core Audio and MIDI Systems  
**Codebase Version**: v0.1.4

---

## 1. Executive Summary

### Overall Assessment: **Intermediate-to-Advanced** (Solid MVP Foundation)

This codebase demonstrates a level of audio engineering maturity that is **uncommon for an MVP**. The architecture shows clear understanding of professional DAW requirements: sample-accurate MIDI scheduling, proper thread safety patterns, tiered graph mutation strategies, and thoughtful handling of edge cases like device changes and plugin restoration.

**Key Strengths:**
- Sample-accurate MIDI scheduling using `AUScheduleMIDIEventBlock` with calculated future sample times
- Proper use of `os_unfair_lock` for real-time safe thread synchronization
- Tiered graph mutation system (structural/connection/hot-swap) that minimizes playback disruption
- Centralized timing context (`AudioSchedulingContext`) that prevents scattered sample rate handling
- Plugin Delay Compensation (PDC) infrastructure
- Lazy plugin chain realization that saves 2 nodes per track without plugins

**Biggest Existential Risks:**
1. **Position timer runs on main thread** - The 60 FPS position update timer dispatches to MainActor, creating potential for UI-induced timing jitter
2. **Lock contention in automation value application** - Multiple tracks acquiring `os_unfair_lock` 120 times/second can cause priority inversion
3. **Incomplete cleanup during engine restart** - Some paths through `handleAudioConfigurationChange` may leave orphan taps or nodes

**Verdict**: This is **not** a hobby DAW. The architecture is intentional, the threading model is coherent, and the edge cases are considered. With targeted fixes to the high-risk issues, this could scale to professional use.

---

## 2. High-Risk Issues (Must Fix)

### 2.1 Position Timer on Main Thread with Task Dispatch

**Location**: `TransportController.swift:325-329`

```swift
positionTimer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
    Task { @MainActor in
        self?.updatePosition()
    }
}
```

**Problem**: The position timer fires at 60 FPS and dispatches to MainActor via `Task`. This creates two issues:
1. **Timer fires on RunLoop** - `Timer.scheduledTimer` uses the run loop, which can be delayed by UI work
2. **Task dispatch adds latency** - Each `Task { @MainActor in ... }` hop adds scheduling overhead

**Why It's Dangerous for Audio**:
- Position drives automation (`AutomationEngine.beatPositionProvider`)
- Position drives MIDI scheduling (`SampleAccurateMIDIScheduler.currentBeatProvider`)
- If the main thread is busy rendering a complex UI, the position timer lags, causing:
  - Automation jumps when the timer catches up
  - MIDI events scheduled based on stale position
  - Visible playhead stutter in the UI

**How It Could Manifest**:
- Open a large mixer view with many meters updating
- During playback, automation "lurches" instead of smooth transitions
- MIDI notes feel "late" after UI interactions

**Recommendation**:
The atomic `_atomicBeatPosition` is already there and correctly used. The fix is to calculate position based on wall-clock delta, not timer frequency:

```swift
// In updatePosition():
let elapsedSeconds = CACurrentMediaTime() - playbackStartWallTime
let elapsedBeats = elapsedSeconds * beatsPerSecond
let currentBeat = playbackStartBeat + elapsedBeats
```

This is already implemented. The issue is that the 60 FPS timer's purpose is UI updates, but the **atomic position** should be updated from a **separate high-priority timer** or calculated on-demand. Consider:

1. Move beat calculation to the read site (lazy calculation from wall-clock)
2. Or use `DispatchSourceTimer` on a `.userInteractive` queue (like MIDI scheduler does)

---

### 2.2 Automation Engine Per-Track Lock Contention

**Location**: `AutomationEngine.swift:146-164`, `TrackAudioNode.swift:159-168`

**Problem**: The automation engine at 120 Hz iterates all tracks and for each:
1. Acquires `AutomationProcessor.snapshotLock` to read values
2. Calls `trackNode.setVolumeSmoothed()` which acquires `trackNode.automationLock`

With 32 tracks, that's 32 lock acquisitions per parameter, 120 times per second = **3,840+ lock ops/sec** on a high-priority queue.

**Why It's Dangerous**:
- `os_unfair_lock` is fast but not free
- If the main thread is holding any of these locks (e.g., during project save), the automation queue blocks
- This is classic **priority inversion** waiting to happen

**How It Could Manifest**:
- Random 5-10ms audio stutters during automation playback
- Worse with many tracks or complex automation curves
- Intermittent and hard to reproduce

**Recommendation**:

**Option A (Minimal change)**: Batch all value reads under a single lock hold:

```swift
private func processAutomation() {
    guard let currentBeat = beatPositionProvider?(),
          let trackIds = trackIdsProvider?(),
          let processor = processor else { return }
    
    // Single lock acquisition for all reads
    let allValues = processor.getAllValuesForTracks(trackIds, atBeat: currentBeat)
    
    // Apply without locks (trackNode applies are atomic)
    for (trackId, values) in allValues {
        trackNodes[trackId]?.applyAutomationValues(...)
    }
}
```

**Option B (More invasive)**: Pre-compute automation curves per-buffer and apply in the render callback (true sample-accurate automation). This is how professional DAWs do it but requires render tap architecture.

---

### 2.3 Engine Health Watchdog Uses `Timer` (RunLoop-Based)

**Location**: `AudioEngine.swift:962-970`

```swift
engineHealthTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
    Task { @MainActor in
        self?.checkEngineHealth()
    }
}
```

**Problem**: Same issue as position timer - uses RunLoop-based timer that can be delayed by UI work. If the main thread is blocked (e.g., waiting for plugin state serialization), the health check doesn't fire.

**Why It's Dangerous**: The health watchdog exists to detect engine crashes and trigger recovery. If it's blocked by the same main thread that's causing issues, it can't do its job.

**Recommendation**: Use `DispatchSourceTimer` on a background queue:

```swift
private func setupEngineHealthMonitoring() {
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(deadline: .now() + 2.0, repeating: 2.0, leeway: .seconds(1))
    timer.setEventHandler { [weak self] in
        Task { @MainActor in
            self?.checkEngineHealth()
        }
    }
    timer.resume()
    engineHealthTimer = timer
}
```

---

### 2.4 Graph Mutation During Active Playback Can Orphan Scheduled Audio

**Location**: `AudioEngine.swift:1700-1743` (structural mutation path)

**Problem**: During a structural mutation:
1. `midiPlaybackEngine.stop()` is called
2. `engine.stop()` and `engine.reset()` are called
3. Work is performed
4. Engine restarts
5. `playFromBeat(currentPosition.beats)` reschedules

But between steps 2 and 5, any **audio player nodes** have their scheduled segments cleared by `reset()`, and the rescheduling in step 5 uses `currentPosition.beats` which may have drifted during the mutation.

**How It Could Manifest**:
- During plugin insertion while playing: audio resumes from slightly wrong position
- Clicking sounds at the transition point
- Especially noticeable on long sessions with many mutations

**Recommendation**:
Capture position **before** stopping:

```swift
case .structural:
    let savedBeat = currentPosition.beats  // Capture before mutation
    let savedSampleTime = CACurrentMediaTime()
    
    // ... mutation work ...
    
    if wasPlaying {
        // Calculate actual beat accounting for mutation duration
        let mutationDuration = CACurrentMediaTime() - savedSampleTime
        let driftBeats = (project.tempo / 60.0) * mutationDuration
        let correctedBeat = savedBeat + driftBeats
        playFromBeat(correctedBeat)
    }
```

---

### 2.5 Plugin State Restoration Timeout Blocks Thread

**Location**: `PluginInstance.swift:380-390`

```swift
let semaphore = DispatchSemaphore(value: 0)
var stateApplied = false

DispatchQueue.global(qos: .userInitiated).async {
    auUnit.fullState = fullState
    stateApplied = true
    semaphore.signal()
}

let result = semaphore.wait(timeout: .now() + Self.stateRestoreTimeout)
```

**Problem**: This blocks the calling thread (likely MainActor) with a semaphore wait. If many plugins are being restored, this serializes plugin loading and can freeze the UI for several seconds.

**Why It's Dangerous**: While the timeout prevents infinite hangs, 5 seconds × 10 plugins = 50 seconds of blocked main thread during project load.

**Recommendation**: Make `restoreState` async and use structured concurrency:

```swift
func restoreState(from data: Data) async -> Bool {
    // ... validation ...
    
    do {
        try await withTimeout(seconds: Self.stateRestoreTimeout) {
            await Task.detached {
                auUnit.fullState = fullState
            }.value
        }
        return true
    } catch {
        return false
    }
}
```

---

## 3. Medium-Risk / Architectural Smells

### 3.1 `@MainActor` Isolation on AudioEngine is Too Broad

**Location**: `AudioEngine.swift:20`

```swift
@Observable
@MainActor
class AudioEngine: AudioEngineContext { ... }
```

**Issue**: The entire `AudioEngine` class is `@MainActor` isolated, but many operations (graph mutation, format queries) should be safe from any context. This forces unnecessary main thread hops and complicates async code.

**Tradeoff**: The `@Observable` macro requires MainActor isolation for property observation to work correctly. The design intentionally trades off some flexibility for type-safe concurrency.

**Recommendation**: Extract non-UI state into a separate, non-isolated manager:

```swift
// AudioGraphManager (non-isolated, owns AVAudioEngine)
// AudioEngineUI (MainActor, owns observable state)
```

This is a significant refactor but would clean up the threading model.

---

### 3.2 Closure-Based Dependency Injection Creates Retain Cycles Risk

**Location**: Throughout controllers (`TransportController`, `MixerController`, `TrackPluginManager`)

```swift
init(
    getProject: @escaping () -> AudioProject?,
    setProject: @escaping (AudioProject) -> Void,
    getTrackNodes: @escaping () -> [UUID: TrackAudioNode],
    ...
)
```

**Issue**: These closures capture `self` (AudioEngine) strongly. While `[weak self]` is used, the pattern is fragile and every new callback must remember to use weak capture.

**Recommendation**: Consider using a protocol + weak reference pattern:

```swift
protocol AudioEngineDataSource: AnyObject {
    var currentProject: AudioProject? { get }
    var trackNodes: [UUID: TrackAudioNode] { get }
}

class TransportController {
    weak var dataSource: AudioEngineDataSource?
}
```

---

### 3.3 `isGraphStable` Flag is Manually Managed

**Location**: `AudioEngine.swift:72`, set in many places

**Issue**: `isGraphStable` is set to `false` at the start of mutations and `true` at the end, but there's no compiler enforcement. A forgotten `= true` leaves the DAW in an unusable state.

**Recommendation**: Use RAII pattern with defer:

```swift
private func withGraphUnstable<T>(_ work: () throws -> T) rethrows -> T {
    isGraphStable = false
    defer { isGraphStable = true }
    return try work()
}
```

Or use a token-based system that auto-releases.

---

### 3.4 MIDIPlaybackEngine Has Two Dispatch Paths

**Location**: `MIDIPlaybackEngine.swift:291-341`

The engine has both `sampleAccurateMIDIHandler` and `midiOutputHandler` as fallbacks. The fallback path (`dispatchMIDIDirect`) dispatches to main thread, creating timing inconsistency.

**Issue**: If `midiBlocks` cache is stale, MIDI silently falls back to the laggy path without warning.

**Recommendation**: Log when fallback is used, and ensure cache is always valid:

```swift
nonisolated private func dispatchMIDIDirect(...) {
    #if DEBUG
    AppLogger.shared.warning("MIDI fallback path used for track \(trackId) - timing degraded")
    #endif
    ...
}
```

---

### 3.5 Hardcoded 48kHz in Several Fallback Paths

**Locations**:
- `AudioSchedulingContext.default` (line 87): 48kHz hardcoded
- `PluginChain.swift:200`: `AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!`
- Various fallbacks in format negotiation

**Issue**: While 48kHz is a good default, these fallbacks could cause format mismatches if the actual sample rate differs.

**Recommendation**: Use `engine.outputNode.outputFormat(forBus: 0).sampleRate` as the source of truth, and panic/log if the fallback is ever reached:

```swift
let connectionFormat = chainFormat ?? {
    assertionFailure("chainFormat should never be nil at this point")
    return AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
}()
```

---

### 3.6 PluginChain State Machine Allows Invalid Transitions

**Location**: `PluginChain.swift:86-92`

```swift
private func transition(to newState: ChainState) {
    guard state.canTransition(to: newState) else {
        assertionFailure("Invalid ChainState transition: \(state) → \(newState)")
        return
    }
    state = newState
}
```

**Issue**: In release builds, `assertionFailure` is a no-op, so invalid transitions are silently ignored. The chain ends up in an undefined state.

**Recommendation**: Either throw an error or use `fatalError` for truly impossible states:

```swift
private func transition(to newState: ChainState) throws {
    guard state.canTransition(to: newState) else {
        throw PluginChainError.invalidTransition(from: state, to: newState)
    }
    state = newState
}
```

---

## 4. Low-Risk Polish / Professionalism Gaps

### 4.1 Missing `engine.detach()` Verification Before Detach

**Location**: `safeDisconnectTrackNode` and similar

When detaching nodes, you check `engine.attachedNodes.contains(node)`, which is correct. However, some paths call `detach` without this check.

**Recommendation**: Create a safe detach helper:

```swift
private func safeDetach(_ node: AVAudioNode) {
    guard engine.attachedNodes.contains(node) else { return }
    engine.disconnectNodeInput(node)
    engine.disconnectNodeOutput(node)
    engine.detach(node)
}
```

---

### 4.2 Level Tap Buffer Size is Fixed

**Location**: `TrackAudioNode.swift:356`

```swift
volumeNode.installTap(onBus: 0, bufferSize: AudioConstants.trackMeteringBufferSize, ...)
```

**Issue**: 1024 samples at 96kHz gives ~10.7ms resolution, while at 44.1kHz it's ~23ms. Meter responsiveness varies with sample rate.

**Recommendation**: Calculate buffer size based on desired time resolution:

```swift
let desiredResolutionMs: Double = 20.0
let bufferSize = AVAudioFrameCount((desiredResolutionMs / 1000.0) * sampleRate)
```

---

### 4.3 No Headroom/Clipping Protection on Master

**Location**: Master EQ connects directly to output node

**Issue**: There's no limiter or soft clipper on the master bus. User can easily clip the output.

**Recommendation**: Add a final stage limiter or at minimum, peak detection with visual warning:

```swift
// After masterEQ, before outputNode:
let masterLimiter = AVAudioUnitEffect(...)  // Or use AUDynamicsProcessor with limiting
```

---

### 4.4 Metronome Reconnection is Scattered

**Location**: `installedMetronome?.reconnectNodes(dawMixer: mixer)` appears in many places

**Issue**: It's easy to forget to reconnect the metronome after a graph change. Some paths may miss it.

**Recommendation**: Call metronome reconnection from a single, guaranteed location (e.g., end of `modifyGraph`):

```swift
private func modifyGraph(_ type: GraphMutationType, _ work: () throws -> Void) rethrows {
    defer {
        installedMetronome?.reconnectNodes(dawMixer: mixer)
    }
    // ... existing logic ...
}
```

---

### 4.5 Debug Logging Uses String Interpolation in Release

**Location**: Various `logDebug()` calls

```swift
logDebug("Created track node for '\(track.name)' (id: \(track.id), type: \(track.trackType))")
```

**Issue**: String interpolation happens before `debugAudioFlow` is checked, causing allocation even when logging is disabled.

**Recommendation**: Use autoclosure or check flag first:

```swift
private func logDebug(_ message: @autoclosure () -> String, category: String = "AUDIO") {
    guard debugAudioFlow else { return }
    AppLogger.shared.debug("[\(category)] \(message())", category: .audio)
}
```

---

## 5. Positive Callouts

### 5.1 Sample-Accurate MIDI Scheduling is Professional Grade

**Location**: `SampleAccurateMIDIScheduler.swift`

The architecture here is excellent:
- Uses `AUScheduleMIDIEventBlock` with calculated future sample times
- Maintains timing reference (`MIDITimingReference`) that accounts for tempo and sample rate
- Uses `os_unfair_lock` for thread-safe state access
- Timer fires at 500Hz to push events ahead, while AU handles sub-sample timing

This is how professional MIDI engines work. The lookahead window of 50ms absorbs timer jitter while maintaining sample accuracy.

### 5.2 Tiered Graph Mutation is Thoughtful

**Location**: `AudioEngine.swift:1644-1813`

The three-tier approach (structural/connection/hot-swap) shows deep understanding of AVAudioEngine:
- **Structural**: Full stop/reset for global changes
- **Connection**: Pause/resume for routing changes
- **Hot-swap**: Track-scoped for plugin changes

This minimizes disruption during editing. Most DAWs use a single "stop everything" approach.

### 5.3 Lazy Plugin Chain Realization Saves Resources

**Location**: `PluginChain.swift`

The decision to only create inputMixer/outputMixer when plugins are actually inserted is smart:
- Saves 2 nodes per track for typical projects
- Explicit state machine (`uninstalled` → `installed` → `realized`)
- Clean unrealization when last plugin is removed

### 5.4 AudioSchedulingContext is a Clean Abstraction

**Location**: `AudioSchedulingContext.swift`

Centralizing timing calculations in a `Sendable` value type is excellent:
- Pre-computed `samplesPerBeat`, `secondsPerBeat` for hot paths
- `@inlinable` for zero-cost abstraction
- Can be safely captured across threads

This prevents the scattered sample rate handling that plagues many DAWs.

### 5.5 Plugin Parameter Rate Limiting is Forward-Thinking

**Location**: `PluginInstance.swift:601-691`

The global rate limiter with per-instance token bucket is sophisticated:
- Prevents DoS from automation with many plugins
- Uses `mach_absolute_time()` for zero-allocation timing
- Throttled warning logging to avoid log spam
- Cached `mach_timebase_info` for efficiency

### 5.6 Plugin Greylist for Crash Isolation

**Location**: Referenced in `TrackPluginManager.swift:199-203`

Tracking plugins that have crashed and loading them sandboxed (`loadOutOfProcess`) is a professional feature that most DAWs lack. This prevents one bad plugin from taking down the entire DAW.

### 5.7 Generation Counter Pattern for Async Safety

**Location**: `AudioEngine.swift:119-153`, `TransportController.swift:97-102`

Using generation counters to detect stale async operations is the correct pattern:

```swift
guard isGraphGenerationValid(capturedGeneration, context: "plugin load") else {
    return  // Graph changed during async operation, abort
}
```

This prevents race conditions when project loads are cancelled or superseded.

### 5.8 Comprehensive Graph Validation

**Location**: `AudioEngine.swift:1929-1989`

The `validateTrackConnections` method that checks for orphan nodes is excellent for debugging. Most DAWs silently break when graph connections fail.

---

## 6. Summary Recommendations

### Immediate Priorities (Before Next Release)

1. **Fix position timer to use wall-clock calculation** - Already implemented, just needs verification
2. **Add limiter on master bus** - Prevents user-facing clipping
3. **Move engine health timer off RunLoop** - Use DispatchSourceTimer

### Next Sprint

4. **Batch automation value reads** - Reduce lock contention
5. **Make plugin state restoration async** - Prevent UI freeze during project load
6. **Add RAII wrapper for isGraphStable** - Prevent stuck states

### Future Refactors

7. **Split AudioEngine into non-isolated graph manager** - Cleaner threading model
8. **Sample-accurate automation in render callback** - True professional automation
9. **Dynamic metering buffer size** - Consistent responsiveness across sample rates

---

## 7. Appendix: Thread Safety Map

| Component | Isolation | Access Pattern |
|-----------|-----------|----------------|
| `AudioEngine` | `@MainActor` | UI state observable |
| `TransportController` | `@MainActor` + atomic | Atomic beat position for schedulers |
| `SampleAccurateMIDIScheduler` | `os_unfair_lock` | High-priority queue |
| `AutomationProcessor` | `os_unfair_lock` | Shared between MainActor and automation queue |
| `AutomationEngine` | `.userInteractive` queue | Reads from processor, writes to TrackAudioNode |
| `TrackAudioNode` | `os_unfair_lock` for levels/automation | Level tap writes, main thread reads |
| `PluginChain` | `@MainActor` | Only mutated from main thread |
| `MIDIPlaybackEngine` | `@MainActor` + `os_unfair_lock` for blocks | MIDI block cache thread-safe |

---

*This review reflects the codebase as of January 30, 2026. Issues identified should be prioritized based on user-facing impact and development resources.*
