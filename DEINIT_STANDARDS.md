# Deinit Standards (DAW-Grade)

## The Rule (One Sentence) - REVISED AFTER ASAN DISCOVERY

**If a type owns async resources, it cancels them explicitly in `deinit`. For `@MainActor + @Observable` classes that can be deallocated, use an empty protective deinit (Swift Issue #84742). Otherwise, no `deinit` at all.**

---

## The Seven Laws - REVISED AFTER ASAN DISCOVERY

1. **`@MainActor + @Observable` + can deallocate → empty protective deinit (Swift Issue #84742).**
2. **Async resources → explicit `deinit { cancels.cancelAll() }`.**
3. **Singletons or never-deallocated types → no deinit.**
4. **Never rely on property teardown order for cancellation.**
5. **`CancellationBag.deinit` is a backstop, not the primary mechanism.**
6. **`@Observable` does not change ARC fundamentals.**
7. **All async closures must use `[weak self]` unless retention is intentional.**

---

## Canonical Patterns (Copy-Paste Templates)

### Pattern A: Zero Async Resources

**When to use:** Type has no timers, tasks, observers, or other async work.

```swift
@Observable
@MainActor
final class MIDIPlaybackEngine {
    
    /// Cached MIDI blocks for each track (RT-safe dictionary)
    @ObservationIgnored
    private let midiBlocks = RTSafeDictionary<UUID, AUScheduleMIDIEventBlock>()
    
    /// Atomic flag for tracking missing MIDI blocks
    @ObservationIgnored
    private let missingBlockFlags = AtomicInt(0)
    
    @ObservationIgnored
    private weak var instrumentManager: InstrumentManager?
    
    // ... MIDI dispatch logic ...
    
    // ❌ NO deinit
    // This type owns no async resources.
    // ARC teardown is sufficient and correct.
}
```

**What NOT to include:**
- ❌ Empty `deinit {}`
- ❌ "Protective deinit" comments
- ❌ References to "ASan Issue #84742"
- ❌ "Implicit Swift Concurrency tasks"

---

### Pattern B: Owns Async Resources (CancellationBag)

**When to use:** Type owns timers, tasks, observers, or other async work.

```swift
@Observable
@MainActor
final class AudioEngine {
    
    /// Real-Time Safe Error Tracking
    @ObservationIgnored
    private let rtClippingCounter = RTSafeCounter()
    
    /// Centralized cancellation for all async resources
    @ObservationIgnored
    private let cancels = CancellationBag()
    
    func startRTErrorFlushTimer() {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.setEventHandler { [weak self] in  // ✅ MUST use [weak self]
            guard let self else { return }
            self.flushRTErrors()
        }
        timer.schedule(deadline: .now(), repeating: 0.5)
        timer.resume()
        
        cancels.insert(timer: timer)
    }
    
    deinit {
        // Deterministic early cancellation of async resources.
        // CancellationBag is nonisolated and safe to call from deinit.
        cancels.cancelAll()
    }
}
```

**Critical requirements:**
- ✅ `[weak self]` in all timer/task closures
- ✅ `timer.resume()` before `cancels.insert()`
- ✅ Explicit `deinit { cancels.cancelAll() }` (one line, no folklore)

---

### Pattern C: @MainActor + @Observable Without Explicit Async Resources

**When to use:** Class is `@MainActor + @Observable`, can be deallocated (not a singleton), but owns no explicit timers/tasks.

**ASan Discovery:** Swift Issue #84742 - `@MainActor + @Observable` creates implicit TaskLocal storage. Without an empty deinit, ASan detects bad-free during `swift::TaskLocal::StopLookupScope::~StopLookupScope()`.

```swift
@Observable
@MainActor
final class AudioExportService {
    
    /// Async functions create transient tasks that complete with the function call
    func exportOriginal(_ audioFile: AudioFile, regionId: UUID) async throws -> URL {
        // ... implementation ...
    }
    
    deinit {
        // REQUIRED: @MainActor + @Observable creates implicit Swift Concurrency TaskLocal storage.
        // Empty deinit changes teardown codegen to avoid ASan bad-free (Issue #84742).
    }
}
```

**Examples that need this pattern:**
- AudioExportService (instantiated in IntegratedTimelineView)
- SelectionManager (instantiated in IntegratedTimelineView)
- ScrollSyncModel (instantiated in IntegratedTimelineView)
- AudioAnalyzer (instantiated in ProfessionalWaveformView)
- VirtualKeyboardState (instantiated in VirtualKeyboardView)
- RegionDragBehavior (@Observable without @MainActor, still needs protective deinit)

**Examples that DON'T need this (singletons):**
- AudioEngine (SharedAudioEngine.shared)
- ProjectManager (singleton)
- Most Core/Services classes (singletons or never deallocated)

---

### Pattern D: Singleton

**Singletons follow the same rules as normal types.**

```swift
final class SharedAudioEngine {
    static let shared = AudioEngine()
    private init() {}
}
```

**Why singletons still need `deinit`:**
1. Unit tests may create/destroy instances
2. Refactors happen (singletons don't always stay singletons)
3. App termination still runs deinitialization paths
4. ASan and CI need deterministic cleanup semantics

---

## Comment Policy

### ❌ Banned Comments (Delete These)

- "Protective deinit" (without explaining WHY)
- "Ensures Swift Concurrency cleanup order" (vague)
- "Workaround for ASan Issue #84742" (not a workaround, it's the fix!)
- "Implicit @Observable tasks" (misleading - it's TaskLocal storage, not tasks)
- "Prevents double-free from implicit Swift Concurrency property change notification tasks" (wrong - it's TaskLocal, not tasks)
- "Empty deinit ensures proper Swift Concurrency / TaskLocal cleanup order" (vague)

**Why these are banned:**
- Encode uncertain folklore or incorrect mental models
- Age badly
- Confuse future maintainers
- Invite cargo-cult coding

### ✅ Allowed Comments (Factual Ownership Only)

**For async resource owners:**
```swift
// Deterministic early cancellation of async resources.
// CancellationBag is nonisolated and safe to call from deinit.
```

**For @MainActor + @Observable without async resources:**
```swift
// REQUIRED: @MainActor + @Observable creates implicit Swift Concurrency TaskLocal storage.
// Empty deinit changes teardown codegen to avoid ASan bad-free (Issue #84742).
```

**For singletons or classes without async resources:**
```swift
// No async resources owned.
// No deinit required.
```

**For synchronous resource cleanup:**
```swift
// Synchronous cleanup of file handle.
```

**Rule:** If a comment does not describe **ownership** or **WHY** the deinit exists, it does not belong.

---

## What Counts as "Async Resources"?

### ✅ Requires `CancellationBag` + `deinit`:

- `DispatchSourceTimer` instances
- `Task<...>` instances
- NotificationCenter observers (unless using modern closure-based APIs that auto-remove)
- KVO observations
- Audio engine taps / MIDI callbacks (if removable)
- Network connections / streams
- File descriptors / sockets
- AsyncSequence consumers
- Anything that can call you back after teardown starts

### ❌ Does NOT require cleanup:

- `RTSafeAtomic` wrappers (RTSafeCounter, AtomicBool, AtomicInt, etc.)
- `RTSafeDictionary` / `RTSafeMaxTracker` / other atomic containers
- `weak` references
- Regular stored properties (ARC handles these)
- `@Published` / `@ObservationIgnored` properties (unless they contain async resources)

---

## Migration Checklist

When refactoring a class:

### Step 1: Identify Async Resources
- [ ] Does it have timers? (`DispatchSourceTimer`)
- [ ] Does it have tasks? (`Task<...>`)
- [ ] Does it have observers? (NotificationCenter, KVO)
- [ ] Does it have other async work? (streams, callbacks, etc.)

### Step 2: Apply Pattern
- **If YES to any above:** Use Pattern B (CancellationBag)
- **If NO to all above:** Use Pattern A (no deinit)

### Step 3: Verify Closure Capture
- [ ] All timer/task closures use `[weak self]`
- [ ] All closures have `guard let self else { return }`

### Step 4: Clean Up Comments
- [ ] Delete all "protective deinit" folklore
- [ ] Add factual ownership comment if needed
- [ ] Keep only what describes the *what*, not the *why* of folklore

---

## Testing Strategy

### Test 1: Deallocation Stress Test

```swift
func testDeallocatesUnderStress() {
    for _ in 0..<10_000 {
        autoreleasepool {
            let engine = AudioEngine()
            engine.start()
            engine.stop()
            // Occasionally yield to flush runloop
            if Int.random(in: 0..<100) == 0 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.001))
            }
        }
    }
    // If we get here without crashing, deallocation is correct
}
```

### Test 2: No Retain Cycle

```swift
func testNoRetainCycle() {
    weak var weakEngine: AudioEngine?
    
    autoreleasepool {
        let engine = AudioEngine()
        weakEngine = engine
        engine.startHealthMonitor()  // ✅ Start async work
        engine.stopHealthMonitor()   // ✅ Stop async work
    }
    
    XCTAssertNil(weakEngine, "Engine should deallocate (no retain cycle)")
}
```

### Test 3: Timer Stops After Deallocation

```swift
func testTimerStopsAfterDeallocation() {
    let counter = AtomicInt(0)
    
    autoreleasepool {
        let engine = AudioEngine()
        engine.startHealthMonitor { counter.increment() }
    }
    
    let initialCount = counter.read()
    Thread.sleep(forTimeInterval: 0.1)
    let finalCount = counter.read()
    
    XCTAssertEqual(initialCount, finalCount, "Timer should not fire after deallocation")
}
```

### Test 4: Run Under Address Sanitizer

```bash
# Enable Address Sanitizer in Xcode scheme or command line:
xcodebuild test -scheme Stori \
  -destination 'platform=macOS' \
  -enableAddressSanitizer YES
```

**The test suite completing without crashes IS the assertion.**

---

## Common Pitfalls

### ❌ Pitfall 1: Empty Deinit as "Safety Fence"

```swift
// ❌ WRONG: Empty deinit does nothing
deinit {
    // Protective deinit for @Observable @MainActor class
}
```

**Fix:** Delete it entirely.

### ❌ Pitfall 2: Relying on CancellationBag's deinit

```swift
// ❌ WRONG: Implicit cleanup is non-deterministic
@ObservationIgnored
private let cancels = CancellationBag()

// NO explicit deinit (bad for DAW-grade timing)
```

**Fix:** Always add explicit `deinit { cancels.cancelAll() }`.

### ❌ Pitfall 3: Forgetting [weak self]

```swift
// ❌ WRONG: Creates retain cycle
timer.setEventHandler {
    self.doWork()  // ← Strong capture
}
```

**Fix:**
```swift
// ✅ CORRECT: Breaks retain cycle
timer.setEventHandler { [weak self] in
    guard let self else { return }
    self.doWork()
}
```

### ❌ Pitfall 4: Storing Timers/Tasks Directly

```swift
// ❌ WRONG: Requires nonisolated(unsafe) workaround
@ObservationIgnored
private nonisolated(unsafe) var timer: DispatchSourceTimer?
```

**Fix:**
```swift
// ✅ CORRECT: CancellationBag encapsulates the unsafe
@ObservationIgnored
private let cancels = CancellationBag()
// Insert timer into bag, never store it directly
```

---

## Architecture Principles

### Principle 1: Ownership Is Explicit

Every type should make it **immediately obvious** whether it owns async resources:
- Present: `CancellationBag` + `deinit`
- Absent: Neither

### Principle 2: Cleanup Is Deterministic

Async resources are cancelled **as early as possible** (in `deinit`), not "sometime during property teardown".

### Principle 3: Unsafe Is Encapsulated

`nonisolated(unsafe)` appears **only in infrastructure**:
- `CancellationBag` internals
- `RTSafeAtomic` internals

**Never** in application code.

### Principle 4: Comments Describe Reality

Comments state **what the code owns**, not folklore about Swift internals.

---

## Why This Matters for a DAW

**Professional audio software demands deterministic behavior.**

- ✅ Timers stop **immediately** on teardown (not "eventually")
- ✅ No "zombie objects" firing callbacks after logical death
- ✅ Minimal race windows during teardown
- ✅ Auditable, consistent lifecycle management
- ✅ Future maintainers understand ownership at a glance

**This is the difference between a toy and a tool.**

---

## References

- Swift Forums: [Cleaning up in deinit with self](https://forums.swift.org/t/cleaning-up-in-deinit-with-self-and-complete-concurrency-checking/70012)
- Swift Issue: [Observation prevents use of Sendable properties in deinit](https://github.com/swiftlang/swift/issues/79551)
- CancellationBag implementation: `Stori/Core/Utilities/CancellationBag.swift`
- RTSafeAtomic implementation: `Stori/Core/Audio/RTSafeAtomic.swift`

---

## Quick Decision Tree

```
Does the type own timers, tasks, or other async work?
├─ YES → Use CancellationBag + explicit deinit { cancels.cancelAll() }
└─ NO  → No deinit at all
```

**It's that simple.**
