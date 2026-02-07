# Isolated Deinit Compiler Flag Investigation

**Branch:** `fix/isolated-deinit-compiler-flag`
**Date:** 2026-02-06
**Issue:** Build error requiring experimental Swift 6 feature flag

---

## 🔍 Issue Summary

**Error Message:**
```
TransportController.swift:281: 'isolated' deinit requires frontend flag 
-enable-experimental-feature IsolatedDeinit to enable the usage of this language feature
```

**Location:** `Stori/Core/Audio/TransportController.swift`, line 281
```swift
nonisolated deinit {
    // Ensure position timer is stopped to prevent memory leaks
    // Cancel the timer directly since deinit is nonisolated
    positionTimer?.cancel()
}
```

---

## 🏗️ Architecture Context

### Current Project Configuration

**Xcode:** 16.3 (Build 16E140)
**Swift Compiler:** 6.1 (swiftlang-6.1.0.110.21)
**Project SWIFT_VERSION:** 5.0 ⚠️ **CRITICAL MISMATCH**

**Build Settings (project.pbxproj):**
```
SWIFT_VERSION = 5.0
SWIFT_APPROACHABLE_CONCURRENCY = YES
SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor
SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES
```

### The Problem

The codebase is written for **Swift 6** but the project build settings specify **Swift 5.0**. This causes:

1. Swift 6 language features (like `nonisolated deinit`) are not recognized
2. The compiler requires explicit experimental feature flags for advanced concurrency features
3. The project cannot build despite having Swift 6.1 compiler installed

---

## 📚 Swift Evolution Background

### SE-0371: Isolated Synchronous Deinit

**Status:** Experimental in Swift 6.1, available in Swift 6.2+

**Problem it Solves:**
- Before Swift 6.2, `deinit` was always `nonisolated`, even in `@MainActor` or actor-isolated classes
- This prevented cleanup code from calling actor-isolated methods
- Caused memory leaks and cleanup issues in concurrent code

**The Feature:**
- Allows deinitializers to inherit the isolation of their containing class
- `nonisolated deinit` explicitly opts OUT of actor isolation
- Enables safe cleanup of actor-isolated resources

**Timeline:**
- Originally planned for Swift 6.1
- Deemed too risky during qualification
- Made experimental in Swift 6.1 (requires `-enable-experimental-feature IsolatedDeinit`)
- Fully available in Swift 6.2 (still in development as of Feb 2026)

### Why TransportController Needs `nonisolated deinit`

`TransportController` is a `@MainActor` `@Observable` class that owns:
- `positionTimer: DispatchSourceTimer?` (marked `@ObservationIgnored`)
- Timer runs on separate high-priority queue (`positionQueue`)
- Timer must be cancelled in deinit to prevent memory leaks

**The Concurrency Problem:**
```swift
@Observable
@MainActor
class TransportController {
    @ObservationIgnored
    private var positionTimer: DispatchSourceTimer?
    
    // ❌ Without nonisolated: deinit would be MainActor-isolated
    // This means it could only run on MainActor, but:
    // - Object might be deallocated from ANY thread
    // - Cannot hop to MainActor during deinit
    // - Result: Crash or timer never cancelled = memory leak
    
    // ✅ With nonisolated: deinit can run on any thread
    // - Safely accesses @ObservationIgnored properties
    // - Can call timer?.cancel() directly
    // - No actor isolation needed for cleanup
    nonisolated deinit {
        positionTimer?.cancel()
    }
}
```

---

## 🔬 Codebase Analysis

### Affected Classes

Found **38 deinit implementations** across the audio subsystem. Most are "protective deinits" for ASan Issue #84742 (Swift Concurrency TaskLocal double-free bug).

**Critical Finding:** Only `TransportController` uses `nonisolated deinit`. All others use regular `deinit`.

### Classes with Similar Pattern (but without nonisolated)

1. **AutomationProcessor** (line 211-217):
```swift
deinit {
    // CRITICAL: Protective deinit for timer cleanup (Issue #72, ASan Issue #84742+)
    // Root cause: DispatchSourceTimer with Swift Concurrency TaskLocal can cause
    // bad-free on deinit if timer isn't explicitly cancelled.
    timer?.cancel()
}
```
**POTENTIAL BUG:** This should probably also be `nonisolated deinit` since it accesses a timer on a separate queue.

2. **MetronomeEngine** (line 617-626):
```swift
deinit {
    // CRITICAL: Cancel async resources before implicit deinit
    // ASan detected double-free during swift_task_deinitOnExecutorImpl
    beatFlashTask?.cancel()
    fillTimer?.cancel()
}
```
**POTENTIAL BUG:** Also cancels timers, might need `nonisolated`.

3. **PluginDeferredDeallocationManager** (line 171-176):
```swift
deinit {
    sweepTask?.cancel()
    // Final cleanup on deinit
    if !pendingDeallocations.isEmpty {
        AppLogger.shared.warning(...)
    }
}
```
**POTENTIAL BUG:** Cancels async tasks, might need `nonisolated`.

### Common Pattern: ASan Issue #84742

Most deinit implementations are "protective deinits" - empty or minimal deinits that prevent Swift Concurrency TaskLocal double-free bugs:

```swift
deinit {
    // CRITICAL: Protective deinit for @Observable @MainActor class (ASan Issue #84742+)
    // Prevents double-free from implicit Swift Concurrency property change notification tasks
}
```

**This is a workaround for Swift Concurrency bugs that should be fixed upstream.**

---

## 🎯 Solution Options

### Option 1: Enable Experimental Feature Flag (RECOMMENDED for now)

**Pros:**
- Minimal code changes
- Addresses the immediate build error
- Preserves intended thread-safety semantics

**Cons:**
- Uses experimental feature (could change)
- Not available in production Swift 6.1 compiler

**Implementation:**
Add to `OTHER_SWIFT_FLAGS` in project.pbxproj:
```
OTHER_SWIFT_FLAGS = (
    "-enable-experimental-feature",
    "IsolatedDeinit"
);
```

**Risk Level:** LOW (feature is stable, just not officially released)

---

### Option 2: Remove `nonisolated` Keyword (TEMPORARY WORKAROUND)

**Pros:**
- Builds immediately with Swift 5.0/6.0 without flags
- No project settings changes needed

**Cons:**
- ⚠️ **POTENTIAL MEMORY LEAK:** Timer might not be cancelled if deinit can't run
- ⚠️ **POTENTIAL CRASH:** If object deallocated off MainActor, deinit would need to hop to MainActor (impossible during deinit)
- Removes intentional thread-safety design

**Implementation:**
```swift
// Change this:
nonisolated deinit {
    positionTimer?.cancel()
}

// To this:
deinit {
    positionTimer?.cancel()
}
```

**Risk Level:** MEDIUM-HIGH (undefined behavior, potential memory leaks)

---

### Option 3: Upgrade SWIFT_VERSION to 6.0 (CORRECT LONG-TERM FIX)

**Pros:**
- Aligns project settings with actual codebase
- Enables proper Swift 6 concurrency checking
- .cursorrules says "Swift 6" - project should match

**Cons:**
- Requires full Swift 6 migration audit
- May expose other concurrency issues
- Larger scope than isolated deinit fix

**Implementation:**
```diff
- SWIFT_VERSION = 5.0;
+ SWIFT_VERSION = 6.0;
```

Then add experimental feature flag:
```
OTHER_SWIFT_FLAGS = (
    "-enable-experimental-feature",
    "IsolatedDeinit"
);
```

**Risk Level:** MEDIUM (requires testing but is the correct fix)

---

### Option 4: Wait for Swift 6.2 (NOT VIABLE)

**Pros:**
- IsolatedDeinit will be available without experimental flag
- Fully supported, no workarounds

**Cons:**
- Swift 6.2 not released yet (Feb 2026)
- Cannot build project in the meantime
- Unknown release date

**Risk Level:** N/A (not actionable)

---

## 🧪 Investigation Findings

### Critical Discovery: Project/Compiler Mismatch

The root cause is a **configuration mismatch:**

```
.cursorrules:          "Swift 6"
Compiler:              Swift 6.1
Project Settings:      Swift 5.0  ⚠️ WRONG
Code:                  Written for Swift 6 (uses @Observable, nonisolated deinit)
```

**This explains why the build fails:**
- Swift 6.1 compiler is available
- Project is configured for Swift 5.0 language mode
- Code uses Swift 6 features (nonisolated deinit)
- Swift 5.0 mode doesn't recognize these features
- Compiler requires experimental flag to enable them

### Recommended Action Plan

**PHASE 1: Immediate Fix (Today)**
1. Change `SWIFT_VERSION = 5.0` → `SWIFT_VERSION = 6.0` in project.pbxproj
2. Add experimental feature flag for IsolatedDeinit
3. Build and test

**PHASE 2: Validation (This Week)**
1. Run full test suite
2. Test audio playback, transport, cycle loops
3. Verify timer cleanup with Instruments
4. Check for other Swift 6 concurrency warnings

**PHASE 3: Audit (Future)**
1. Review other @MainActor classes with timers
2. Consider if `AutomationProcessor`, `MetronomeEngine`, `PluginDeferredDeallocationManager` need `nonisolated deinit`
3. Monitor Swift 6.2 release for when experimental flag can be removed

---

## 📊 Impact Assessment

### Files to Change: 1
- `Stori.xcodeproj/project.pbxproj` (build settings)

### Risk: LOW-MEDIUM
- Changes build configuration, not runtime code
- Swift 6.0 mode is stable and well-tested
- Experimental feature (IsolatedDeinit) is mature, just not officially released

### Testing Required:
- ✅ Project builds successfully
- ✅ TransportController timer cleanup works (run with Instruments)
- ✅ No new concurrency warnings/errors
- ✅ Transport controls work (play, pause, stop, seek, cycle)
- ✅ Position timer updates correctly
- ✅ Memory leaks check with Instruments

---

## 🚀 Next Steps

1. **Decision:** Choose solution option (recommend Option 3)
2. **Implementation:** Update project.pbxproj
3. **Testing:** Run automated tests + manual transport testing
4. **Verification:** Use Instruments to verify timer cleanup
5. **Commit:** Once user confirms build + tests pass
6. **Documentation:** Update if this reveals other Swift 6 migration needs

---

## 📝 References

- [SE-0371: Isolated Synchronous Deinit](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0371-isolated-synchronous-deinit.md)
- [Swift Forums: Isolated deinit not in Swift 6.1?](https://forums.swift.org/t/isolated-deinit-not-in-swift-6-1/78055)
- [Medium: Isolated deinit in Swift 6.2](https://medium.com/ios-journeys/isolated-deinit-in-swift-6-2-whats-the-change-f9a266c11cbc)
- [Swift Issue #76538](https://github.com/swiftlang/swift/issues/76538)
- [Swift Issue #84742 - ASan double-free bug](https://github.com/apple/swift/issues/84742)

---

**END OF INVESTIGATION**
