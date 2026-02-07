# Concurrency Architecture Diagnosis

## The Problem Pattern (You're Right to Be Suspicious)

We have a repeating anti-pattern across the codebase:

```swift
@Observable @MainActor
class SomeEngine {
    @ObservationIgnored
    private nonisolated(unsafe) var timer: DispatchSourceTimer?
    
    deinit {
        // Need to cancel timer, but:
        // - deinit is nonisolated
        // - timer is MainActor property
        // - Forces nonisolated(unsafe)
        timer?.cancel()
    }
}
```

**Files affected:**
- AudioEngine (RT error flush timer, health monitor timer)
- TransportController (position timer)
- MetronomeEngine (timing timer)
- AutomationEngine (120Hz automation timer)
- AutomationServer (Network tasks)
- AudioAnalysisService (Analysis tasks)
- Many more...

## Root Cause Analysis

### What's Actually Happening

1. **`@Observable` macro** creates implicit observation machinery
2. **`@MainActor`** isolates the entire class to main thread
3. **Cleanup resources** (timers, tasks) need explicit cancellation
4. **deinit is nonisolated** (Swift language requirement)
5. **Can't access MainActor properties from deinit** → Swift concurrency error
6. **Forced to use `nonisolated(unsafe)`** → back where we started

### The Apple Bug (or Feature?)

This is a **known Swift issue**: https://github.com/apple/swift/issues/84742

**Problem:** `@Observable` classes with `@MainActor` and cleanup resources create an impossible situation:
- Properties need to be MainActor for observation
- deinit needs access for cleanup
- Swift forbids actor-isolated access in deinit

## Why This Matters

### Symptoms We're Seeing:
1. ✅ ASan crashes without explicit deinit
2. ✅ Timer/task leaks without manual cancellation
3. ✅ Forced `nonisolated(unsafe)` for cleanup
4. ✅ Scattered deinit blocks everywhere
5. ✅ `@ObservationIgnored` workarounds

### The Real Issue:
We're using **`@Observable` + `@MainActor` together**, which creates lifecycle problems when cleanup resources exist.

## Correct Architectural Solutions

### Solution 1: Separate Actor Isolation from Cleanup (RECOMMENDED)

**Don't make the whole class @MainActor.**

```swift
@Observable  // No @MainActor here
class AudioEngine {
    // Only MainActor-isolated properties that need it
    @MainActor
    var engineState: EngineState
    
    @MainActor
    var tracks: [Track]
    
    // Cleanup resources: NOT actor-isolated
    @ObservationIgnored
    private var rtErrorFlushTimer: DispatchSourceTimer?
    
    @ObservationIgnored
    private var healthMonitorTimer: DispatchSourceTimer?
    
    // deinit can now access timers (no actor isolation)
    deinit {
        rtErrorFlushTimer?.cancel()
        healthMonitorTimer?.cancel()
    }
    
    // Methods that need MainActor: annotate individually
    @MainActor
    func setupAudioEngine() {
        // ...
    }
}
```

**Benefits:**
- ✅ No `nonisolated(unsafe)` needed
- ✅ Clean deinit without workarounds
- ✅ Explicit about what needs MainActor
- ✅ Cleanup resources are nonisolated by default

**Tradeoffs:**
- ⚠️ More verbose (need to annotate methods)
- ⚠️ Requires careful audit of what needs MainActor

---

### Solution 2: Move Cleanup to Separate Non-Actor Type

```swift
@Observable @MainActor
class AudioEngine {
    @ObservationIgnored
    private let timerManager = TimerManager()  // Not actor-isolated
    
    // ... rest of class
}

// Separate type handles cleanup
final class TimerManager {
    private var timers: [DispatchSourceTimer] = []
    
    func addTimer(_ timer: DispatchSourceTimer) {
        timers.append(timer)
    }
    
    deinit {
        timers.forEach { $0.cancel() }
    }
}
```

**Benefits:**
- ✅ Keeps `@MainActor` on main class
- ✅ Clean separation of concerns
- ✅ No `nonisolated(unsafe)`

**Tradeoffs:**
- ⚠️ More boilerplate
- ⚠️ Less obvious ownership

---

### Solution 3: Use MainActor.run in deinit (Swift 6+)

```swift
@Observable @MainActor
class AudioEngine {
    private var timer: DispatchSourceTimer?
    
    deinit {
        // Dispatch cleanup to MainActor
        // NOTE: This is fire-and-forget - can't await in deinit
        Task { @MainActor in
            self.timer?.cancel()
        }
    }
}
```

**Benefits:**
- ✅ No `nonisolated(unsafe)`
- ✅ Respects actor isolation

**Tradeoffs:**
- ❌ **deinit completes before cleanup** (fire-and-forget)
- ❌ Timer may not be cancelled in time
- ❌ Can cause the very ASan crashes we're trying to prevent

**Verdict:** ❌ Don't use this for cleanup

---

## Diagnosis Tools

### 1. Thread Sanitizer (TSan)
Detects data races, including:
- Concurrent access to non-atomic variables
- Race conditions in observation machinery
- Timer/task lifetime issues

```bash
xcodebuild test -scheme Stori -enableThreadSanitizer YES
```

### 2. Address Sanitizer (ASan) - Already Using
Detects:
- Use-after-free
- Buffer overflows
- Memory leaks

### 3. Xcode Memory Graph Debugger
Visual tool to find retain cycles:
1. Run app in Xcode
2. Debug → View Memory Graph
3. Look for cycles involving timers/observables

### 4. Instruments - Leaks & Allocations
Profile memory over time:
```bash
instruments -t Leaks -D leaks.trace Stori.app
```

### 5. Print Deallocation

Add temporary logging to verify cleanup:

```swift
deinit {
    print("🧹 AudioEngine deinit - cleaning up timers")
    rtErrorFlushTimer?.cancel()
    print("✅ AudioEngine deinit complete")
}
```

Then watch console during app lifetime. If you never see the deinit logs, you have a retain cycle.

---

## Recommended Action Plan

### Phase 1: Diagnose (10 minutes)
1. Add deinit logging to AudioEngine, TransportController, MetronomeEngine
2. Run app normally, then quit
3. Check if deinit logs appear
4. If they don't → retain cycle (observation machinery holding references)

### Phase 2: Test Theory (30 minutes)
Pick ONE class (e.g., TransportController) and refactor it:
- Remove `@MainActor` from class
- Add `@MainActor` to individual methods/properties
- Remove `nonisolated(unsafe)` from cleanup resources
- Verify deinit runs and timers are cancelled
- Run tests to ensure behavior unchanged

### Phase 3: Systematic Refactor (if Phase 2 succeeds)
Apply same pattern to:
- AudioEngine
- MetronomeEngine
- AutomationEngine
- MIDIPlaybackEngine
- All other classes with the pattern

---

## What We Learned

### The Real Problem:
**Mixing `@Observable` + `@MainActor` + cleanup resources** creates an impossible lifecycle.

### The Correct Pattern:
**Use `@MainActor` granularly, not at class level**, when cleanup resources exist.

### Why This Matters:
- ✅ No `nonisolated(unsafe)` anti-pattern
- ✅ Clean deinit without hacks
- ✅ Explicit concurrency boundaries
- ✅ Respects Swift's actor model

---

## Next Steps

1. **Run deinit logging test** (see Phase 1 above)
2. **If deinit never runs** → we have observation retain cycles
3. **If deinit runs but crashes** → cleanup order issue
4. **Refactor one class** to Solution 1 pattern
5. **Verify fix with ASan/TSan**
6. **Apply systematically**

This is the **root cause fix**, not another symptom patch.
