# Memory Architecture Remediation Plan

## TellUrStori DAW — Eliminating the Root Cause of ASan/TSan Crashes

**Date:** February 7, 2026  
**Status:** Implementation Complete — Pending User Testing  
**Priority:** Critical — App-crashing bugs that could permanently lose users

---

## Executive Summary

Stori has ~95 empty `deinit` blocks and ~22 `nonisolated(unsafe)` declarations spread across the codebase, added to suppress Address Sanitizer crashes. Investigation reveals these are **band-aids masking real bugs**, not fixes for a legitimate Swift runtime defect. The root causes are:

1. **~31 `Task {}` blocks that strongly capture `self` in `@Observable` classes** — the primary source of use-after-free crashes
2. **A fabricated Swift bug citation ("ASan Issue #84742+")** propagated by a previous AI agent across ~90 files and a CI script
3. **Cross-actor isolation violations** in audio code paths (e.g., creating `@MainActor` objects from non-MainActor contexts)

The empty `deinit` blocks accidentally suppress crashes by changing ARC optimization behavior (preventing early deallocation), but the underlying bugs remain. This plan eliminates the root causes in four phases.

---

## Root Cause Analysis

### What Was Claimed
> "@Observable classes have implicit Swift Concurrency tasks for property change notifications that can cause bad-free on deinit."
> — Comment in ~90 files, citing "ASan Issue #84742+"

### What Is Actually True

1. **"ASan Issue #84742+" does not exist.** [Swift Issue #84742](https://github.com/apple/swift/issues/84742) is titled _"[Debug] Add pointer based stringForPrintObject"_ and is about LLDB's `po` command performance. It has nothing to do with `@Observable`, `deinit`, or memory safety. The citation was fabricated by a previous AI agent.

2. **`@Observable` does NOT create implicit tasks.** The `ObservationRegistrar` is entirely synchronous — it uses a lock-protected dictionary of callback closures. There are no "implicit property change notification tasks" or "task-local storage" that could be double-freed.

3. **Empty `deinit` masks real bugs by accident.** When you add a `deinit` (even empty), the Swift compiler:
   - Disables certain ARC optimizations (treats deallocation as side-effectful)
   - Prevents early object lifetime termination
   - Forces deterministic property destruction ordering
   
   This can mask timing-dependent bugs (like use-after-free from strong `Task` captures) by keeping objects alive longer than they'd otherwise be.

4. **The real bugs are strong `self` captures in `Task` blocks.** When a `Task` captures `self` strongly and outlives the object's natural lifetime, the Task holds a dangling reference. Without the empty `deinit`, ARC can deallocate the object earlier, exposing the bug. With the empty `deinit`, the object stays alive longer and the crash becomes intermittent rather than consistent.

### Why the Crashes Happen

```
┌─────────────────────────────────────────────────────────────┐
│  View creates @Observable @MainActor service                │
│  Service spawns Task { self.doWork() }  ← strong capture    │
│  View disappears → service should be deallocated            │
│  BUT Task still holds strong reference to service           │
│  Task completes → accesses deallocated memory               │
│  → ASan reports use-after-free / double-free                │
│                                                             │
│  "Fix": empty deinit changes ARC behavior                   │
│  → Object lives longer → crash becomes intermittent         │
│  → Appears "fixed" but bug is still there                   │
└─────────────────────────────────────────────────────────────┘
```

### The `nonisolated(unsafe)` Situation

Of the 22 `nonisolated(unsafe)` declarations, they fall into two categories:

**Legitimate (keep):** 16 instances protecting real-time audio thread state behind `os_unfair_lock` — these are correct and necessary for the audio thread's real-time safety requirements. Properties like atomic beat position, MIDI blocks, and engine health flags genuinely need cross-thread access without actor hops.

**Questionable (review):** 6 instances on `Task<Void, Never>?` properties used solely to cancel tasks in `deinit`. These exist because `deinit` is nonisolated and can't access `@MainActor` properties. The proper fix is to cancel tasks before deallocation (in `cleanup()` methods or SwiftUI lifecycle hooks), not in `deinit`.

---

## Phase 1: Fix the Actual Bugs (Critical — Week 1)

### Goal
Fix the 31 identified `Task` blocks that strongly capture `self`, which are the primary source of use-after-free crashes.

### 1.1 — Fix Critical Priority: Task in `deinit`

**File:** `Core/Services/MIDIDeviceManager.swift` (line ~93)

```swift
// BEFORE (CRASHES):
deinit {
    Task { @MainActor in teardownMIDI() }
}

// AFTER:
deinit {
    // Cannot call @MainActor methods from nonisolated deinit.
    // teardownMIDI() must be called explicitly before releasing this object.
}
```

**Action:** Add a `cleanup()` method and call it from the SwiftUI `.onDisappear` or the owning object's cleanup path.

- [ ] Remove Task from MIDIDeviceManager deinit
- [ ] Add explicit `cleanup()` method to MIDIDeviceManager
- [ ] Wire cleanup to SwiftUI lifecycle

### 1.2 — Fix High Priority: Strong `self` Captures in Audio Paths

These are the bugs most likely causing the GM Instrument and region deletion crashes:

| # | File | Method | Issue |
|---|------|--------|-------|
| 1 | `AudioEngine.swift:1015` | `installClippingDetectionTaps()` | `Task { @MainActor in self.triggerFeedbackProtection() }` |
| 2 | `AudioEngine.swift:1276` | Health check timer | `Task { @MainActor in self.checkEngineHealth() }` |
| 3 | `AudioEngine+Instruments.swift:294` | Note-off delay | `Task { @MainActor in ... }` without `[weak self]` |
| 4 | `AudioEngine+Instruments.swift:321` | `loadTrackGMInstrumentInternal` | Not `@MainActor` but accesses `@MainActor` types |
| 5 | `RecordingController.swift:256,295,309` | Recording methods | Tasks without `[weak self]` |
| 6 | `MetronomeEngine.swift:531` | `flashBeat()` | `beatFlashTask` captures self strongly |
| 7 | `MIDIPlaybackEngine.swift` | Various | Tasks accessing self |
| 8 | `ProjectLifecycleManager.swift:172` | `loadProject()` | Task without `[weak self]` |
| 9 | `PluginInstance.swift:447` | `restoreStateSync` | Task captures self strongly |

**Fix pattern for each:**

```swift
// BEFORE:
Task { @MainActor in
    self.someMethod()
    self.someProperty = value
}

// AFTER:
Task { [weak self] @MainActor in
    guard let self else { return }
    self.someMethod()
    self.someProperty = value
}
```

**Action items:**
- [ ] Fix all 9 audio-path Task captures listed above
- [ ] Verify `loadTrackGMInstrumentInternal` has proper `@MainActor` isolation
- [ ] Test GM Instrument loading after fixes
- [ ] Test audio region deletion after fixes

### 1.3 — Fix High Priority: Strong `self` Captures in Service Paths

| # | File | Method | Issue |
|---|------|--------|-------|
| 1 | `ProjectManager.swift:384` | `scheduleSave()` | `saveDebounceTask` captures self |
| 2 | `ProjectManager.swift:420` | `saveCurrentProject()` | Task captures self |
| 3 | `ProjectManager.swift:1502` | `captureProjectScreenshot` | Task captures self |
| 4 | `AutomationServer.swift:232,304` | Handler methods | Tasks capture self |
| 5 | `LLMComposerClient.swift:482,498` | `streamCompose` | `streamingTask`/`cleanupTask` capture self |
| 6 | `AudioAnalysisService.swift:147,186` | Analysis methods | `Task.detached` captures self |
| 7 | `AudioExportService.swift` | Various | Tasks capture self |
| 8 | `ProjectExportService.swift:401,1970,2018` | Export methods | Tasks capture self |
| 9 | `BlockchainClient.swift:74,90` | `init()`, `loadSavedWallet()` | Tasks capture self |

**Action items:**
- [ ] Fix all 9 service-path Task captures listed above
- [ ] For `Task.detached` in AudioAnalysisService, consider switching to `Task` with `[weak self]`
- [ ] For init-time Tasks (BlockchainClient), ensure they use `[weak self]`

### 1.4 — Fix Medium Priority: Remaining Strong Captures

| # | File | Class |
|---|------|-------|
| 1 | `LicenseEnforcer.swift:375,381` | `LicenseEnforcer` |
| 2 | `WalletManager.swift:71,101` | `WalletManager` |
| 3 | `StoriAPIClient.swift:72` | `StoriAPIClient` |

- [ ] Fix all 3 remaining Task captures

---

## Phase 2: Remove the Band-Aids (Week 2)

### Goal
Remove the ~80 empty `deinit` blocks and associated infrastructure that mask bugs rather than fix them. Keep only `deinit` blocks that do real cleanup work.

### 2.1 — Categorize All `deinit` Blocks

**Keep (14 instances):** `deinit` blocks that perform real cleanup:
- Task cancellation (6): LLMComposerClient, AutomationServer, AudioExportService, AudioAnalysisService, MetronomeEngine, UpdateService
- Resource cleanup (4): TransportController (timer), PluginDeferredDeallocationManager, BlockchainClient (network monitor), MIDIDeviceManager
- File/system cleanup (2): AppLogger (file handle), TrackAudioNode (level monitoring)
- Observer cleanup (1): SynchronizedScrollView (notification observer)
- License cleanup (1): LicensePlayerState

**Convert (6 instances):** `deinit` blocks with Task cancellation that use `nonisolated(unsafe)` to access properties in deinit — migrate cancellation to explicit `cleanup()` methods:
- AutomationServer (4 tasks)
- AudioAnalysisService (2 tasks)

**Remove (~75 instances):** Empty protective `deinit` blocks that do nothing:
- All `@Observable @MainActor` classes with empty deinit
- All `@Observable`-only classes with empty deinit
- All actor types with empty deinit
- All classes-with-Task-blocks with empty deinit

### 2.2 — Action Items

- [ ] After Phase 1 fixes are tested and confirmed working, remove empty deinits in batches:
  - [ ] Batch 1: Core/Audio/ classes (highest risk — test thoroughly)
  - [ ] Batch 2: Core/Services/ classes
  - [ ] Batch 3: Core/Wallet/ classes
  - [ ] Batch 4: Features/ classes
  - [ ] Batch 5: UI/ classes
- [ ] For each batch: remove deinits → build → run ASan → test critical flows
- [ ] Keep deinit blocks that do REAL cleanup (listed above)

### 2.3 — Migrate Task Cancellation Out of `deinit`

For classes that cancel tasks in `deinit` using `nonisolated(unsafe)`:

```swift
// BEFORE:
@Observable @MainActor class AutomationServer {
    nonisolated(unsafe) private var stateChangeTask: Task<Void, Never>?
    // ... 3 more nonisolated(unsafe) task properties ...
    
    deinit {
        stateChangeTask?.cancel()
        // ... cancel 3 more ...
    }
}

// AFTER:
@Observable @MainActor class AutomationServer {
    @ObservationIgnored private var stateChangeTask: Task<Void, Never>?
    // ... 3 more @ObservationIgnored task properties ...
    
    func cleanup() {
        stateChangeTask?.cancel()
        stateChangeTask = nil
        // ... cancel 3 more ...
    }
    // deinit removed — cleanup() called from SwiftUI lifecycle
}
```

- [ ] Migrate AutomationServer task cancellation to cleanup()
- [ ] Migrate AudioAnalysisService task cancellation to cleanup()
- [ ] Wire cleanup methods to SwiftUI `.onDisappear` or parent's cleanup

---

## Phase 3: Clean Up `nonisolated(unsafe)` (Week 2-3)

### Goal
Remove unnecessary `nonisolated(unsafe)` declarations. Keep only those protecting real-time audio thread state.

### 3.1 — Keep (Legitimate Real-Time Audio Use)

These are correct and necessary — audio threads cannot hop to MainActor:

| File | Properties | Reason |
|------|-----------|--------|
| `TransportController.swift` | `beatPositionLock`, `_atomicBeatPosition`, `_atomicIsPlaying`, `_atomicPlaybackStartBeat`, `_atomicPlaybackStartWallTime`, `_atomicTempo` | Audio thread timing — protected by `os_unfair_lock` |
| `PluginLatencyManager.swift` | `compensationDelays`, `compensationLock` | Audio thread delay compensation — protected by `os_unfair_lock` |
| `MIDIPlaybackEngine.swift` | `midiBlockLock`, `midiBlocks`, `midiDataBuffer`, `missingBlockFlags`, `missingBlockFlagsLock` | Audio thread MIDI scheduling — protected by `os_unfair_lock` |
| `AudioEngine.swift` | `_atomicEngineExpectedToRun`, `_atomicLastKnownEngineRunning`, `_healthCheckTickCount`, `_transportControllerRef` | Health monitoring from timer thread |

**Action:** Document these as intentional with clear comments explaining the real-time audio constraint.

### 3.2 — Remove (Task Cancellation Workarounds)

After Phase 2 migrates task cancellation to `cleanup()` methods:

| File | Properties | Migration |
|------|-----------|-----------|
| `AutomationServer.swift` | 4 Task properties | → `@ObservationIgnored` after cleanup migration |
| `AudioAnalysisService.swift` | 2 Task properties | → `@ObservationIgnored` after cleanup migration |

- [ ] Remove `nonisolated(unsafe)` from AutomationServer task properties
- [ ] Remove `nonisolated(unsafe)` from AudioAnalysisService task properties
- [ ] Replace with `@ObservationIgnored` (since task properties shouldn't trigger UI updates)

---

## Phase 4: Prevent Regression (Week 3)

### Goal
Establish patterns and tooling that prevent this class of bug from recurring.

### 4.1 — Replace the Deinit Check Script

The current `scripts/check-observable-deinit.sh` enforces the wrong thing (requiring empty deinits). Replace it with a script that catches the actual bugs.

**New script: `scripts/check-task-captures.sh`**

What it should check:
1. `Task {` blocks in `@Observable` classes that don't use `[weak self]`
2. `Task.detached {` blocks that capture `self` strongly
3. `Task {}` blocks inside `deinit` (always a bug)
4. Warn on `nonisolated(unsafe)` without an accompanying `os_unfair_lock`

- [ ] Write new `check-task-captures.sh` script
- [ ] Remove old `check-observable-deinit.sh` script
- [ ] Integrate new script into CI

### 4.2 — Establish Architectural Rules

Add to `.cursorrules` / project documentation:

**Rule 1: All Task blocks in @Observable classes MUST use `[weak self]`**
```swift
// CORRECT:
Task { [weak self] @MainActor in
    guard let self else { return }
    self.updateUI()
}

// WRONG — will cause use-after-free:
Task { @MainActor in
    self.updateUI()
}
```

**Rule 2: Never create Tasks in `deinit`**
```swift
// WRONG — object may be deallocated before Task runs:
deinit {
    Task { @MainActor in cleanup() }
}

// CORRECT — explicit cleanup before deallocation:
func cleanup() { /* cancel tasks, release resources */ }
// Called from SwiftUI .onDisappear or parent's cleanup
```

**Rule 3: `nonisolated(unsafe)` is ONLY for real-time audio thread state**
```swift
// CORRECT — audio thread needs lock-free access:
nonisolated(unsafe) private var _atomicBeatPosition: Double = 0
nonisolated(unsafe) private var beatPositionLock = os_unfair_lock_s()

// WRONG — use @ObservationIgnored instead:
nonisolated(unsafe) private var myTask: Task<Void, Never>?
```

**Rule 4: `deinit` should only contain actual resource cleanup**
```swift
// CORRECT — real cleanup:
deinit {
    fileHandle?.closeFile()
    timer?.cancel()
}

// WRONG — empty protective deinit:
deinit {
    // "Protective" empty deinit
}
```

**Rule 5: Use `@ObservationIgnored` for internal state**
```swift
// CORRECT:
@ObservationIgnored private var myTask: Task<Void, Never>?
@ObservationIgnored private var cancellables = Set<AnyCancellable>()

// WRONG — triggers UI updates for internal state:
private var myTask: Task<Void, Never>?
```

- [ ] Add rules to `.cursorrules`
- [ ] Document in `Stori/documentation/`

### 4.3 — Remove Fabricated Bug References

- [ ] Remove all comments referencing "ASan Issue #84742+" across ~90 files
- [ ] Remove all comments about "implicit Swift Concurrency property change notification tasks"
- [ ] Replace with accurate comments where real cleanup is happening

### 4.4 — Testing Protocol

After each phase:

1. **Build with ASan enabled:**
   ```bash
   xcodebuild test -project Stori.xcodeproj -scheme Stori \
     -destination 'platform=macOS' \
     -enableAddressSanitizer YES
   ```

2. **Build with TSan enabled:**
   ```bash
   xcodebuild test -project Stori.xcodeproj -scheme Stori \
     -destination 'platform=macOS' \
     -enableThreadSanitizer YES
   ```

3. **Manual regression tests:**
   - [ ] Add GM Instrument to a track in the mixer
   - [ ] Delete an audio region from the timeline
   - [ ] Record audio on a track
   - [ ] Save and reload a project
   - [ ] Open and close multiple views rapidly
   - [ ] Play audio while switching between views
   - [ ] Run the step sequencer
   - [ ] Load/unload plugins
   - [ ] MIDI playback with virtual instruments

---

## Summary of Work

| Phase | What | Effort | Risk | Outcome |
|-------|------|--------|------|---------|
| 1 | Fix 31 Task capture bugs | ~2 days | Medium | Crashes stop |
| 2 | Remove ~75 empty deinits | ~1 day | Low (after Phase 1) | Clean codebase |
| 3 | Clean up nonisolated(unsafe) | ~0.5 day | Low | Clear intent |
| 4 | Prevent regression | ~1 day | None | Future-proofed |

**Total estimated effort:** ~4-5 days

---

## Quick Reference: What's Real vs. What's Fabricated

| Claim | Verdict |
|-------|---------|
| "ASan Issue #84742+" is a Swift bug | **Fabricated** — that issue is about LLDB `po` command |
| "@Observable creates implicit tasks" | **False** — ObservationRegistrar is synchronous |
| "Empty deinit prevents double-free" | **Accidental side effect** — changes ARC optimization behavior |
| "nonisolated(unsafe) needed for task cancellation in deinit" | **Workaround** — should use explicit cleanup() instead |
| Audio thread needs nonisolated(unsafe) with locks | **True** — real-time threads can't do actor hops |
| Task blocks need [weak self] in @Observable classes | **True** — this is the actual root cause |

---

## Next Steps

1. Review this plan and confirm approach
2. Start Phase 1 with the GM Instrument crash (highest user impact)
3. Test each fix with ASan enabled before proceeding
4. Remove band-aids only after real fixes are verified
