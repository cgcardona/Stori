# Phase 3: Remaining CancellationBag Refactoring

## Status: 77/93 Files Complete (83%)

**Completed:**
- Phase 1: 10 exemplar files with correct patterns ✅
- Phase 2: 67 empty protective deinits deleted ✅

**Remaining:** 14 files need CancellationBag refactoring

---

## Remaining Files (Categorized by Complexity)

### Category A: Simple Timer/Task Cleanup (8 files)

**Pattern:** Add CancellationBag, refactor timer/task creation, update deinit.

1. **AutomationProcessor** (`Stori/Core/Audio/AutomationProcessor.swift`)
   - Has: `timer?.cancel()` in deinit
   - Action: Convert timer to CancellationBag pattern

2. **AudioGraphManager** (`Stori/Core/Audio/AudioGraphManager.swift`)
   - Has: `flushTimer?.invalidate()` in deinit
   - Action: Convert to DispatchSourceTimer + CancellationBag

3. **UpdateService** (`Stori/Core/Services/Update/UpdateService.swift`)
   - Has: `periodicCheckTask?.cancel()`, `downloadTask?.cancel()`
   - Action: Add CancellationBag, track both tasks

4. **PluginDeferredDeallocationManager** (`Stori/Core/Audio/PluginDeferredDeallocationManager.swift`)
   - Has: `sweepTask?.cancel()` in deinit
   - Action: Add CancellationBag, track sweep task

5. **MIDIDeviceManager** (`Stori/Core/Services/MIDIDeviceManager.swift`)
   - Has: `Task { @MainActor in teardownMIDI() }` in deinit
   - Action: Extract teardownMIDI to be callable from deinit, remove Task wrapper

6. **LicenseEnforcer** (`Stori/Features/Library/LicenseEnforcer.swift`)
   - Has: `removeStreamTimeObserver()`, `stop()` in nested class
   - Action: Review if synchronous cleanup is sufficient or needs CancellationBag

7. **MeterDataProvider** (`Stori/Features/Mixer/Components/MeterDataProvider.swift`)
   - Has: `stopMonitoring()` in deinit
   - Action: Review stopMonitoring implementation, may not need CancellationBag

8. **SynchronizedScrollView** (`Stori/Core/Utilities/SynchronizedScrollView.swift`)
   - Has: `NotificationCenter.default.removeObserver(observer)` in nested class
   - Action: Keep as-is (synchronous cleanup), add factual comment

---

### Category B: Complex Multi-Task Services (4 files)

**Pattern:** Multiple tasks/timers require careful tracking.

9. **ProjectExportService** (`Stori/Core/Services/ProjectExportService.swift`)
   - Has: 3 tasks (`cleanupTask`, `progressUpdateTask`, `timeoutTask`)
   - Has: 2 nested class empty protective deinits (RenderVoice, OfflineMIDIRenderer)
   - Action: 
     - Add CancellationBag to main class
     - Track all 3 tasks
     - Delete nested class protective deinits
     - Update main deinit to canonical form

10. **LLMComposerClient** (`Stori/Core/Services/LLMComposerClient.swift`)
    - Has: Streaming task with async iterations
    - Action: Add CancellationBag, track streaming task

11. **AudioExportService** (`Stori/Core/Services/AudioExportService.swift`)
    - Has: Export tasks
    - Action: Add CancellationBag, track export tasks

---

### Category C: Nested Class Cleanup (2 files)

**Pattern:** Multiple deinits in nested classes.

12. **InstrumentPluginHost** (`Stori/Core/Audio/InstrumentPluginHost.swift`)
    - Has: 2 deinits (main class + nested InstrumentChannel class)
    - Action: Delete empty nested class deinit, review main class

13. **PluginInstance** (`Stori/Core/Audio/PluginInstance.swift`)
    - Has: 2 deinits (main class already refactored, nested ParameterTree class)
    - Action: Review/delete nested class deinit

---

### Category D: Memory Management + Cleanup (1 file)

**Pattern:** Combines async cleanup with manual memory management.

14. **TrackAudioNode** (`Stori/Core/Audio/TrackAudioNode.swift`)
    - Has: `removeLevelMonitoring()`, `_currentLevelLeft.deinitialize(count: 1)`, `_currentLevelRight.deinitialize(count: 1)`
    - Action: Keep manual memory deinitialization, review if monitoring needs CancellationBag

---

## Implementation Strategy

### Step 1: Simple Files (Category A, 30 min)
Process files 1-8 systematically:
- Add `@ObservationIgnored private let cancels = CancellationBag()`
- Refactor timer/task creation to use `cancels.insert()`
- Update deinit to canonical form: `deinit { cancels.cancelAll() }`

### Step 2: Complex Services (Category B, 45 min)
Process files 9-11 with careful task tracking:
- Map all async resources
- Add CancellationBag
- Track each task/timer
- Ensure [weak self] in all closures
- Update deinit

### Step 3: Nested Classes (Category C, 15 min)
Process files 12-13:
- Delete empty protective deinits in nested classes
- Verify main class patterns

### Step 4: Special Cases (Category D, 15 min)
Process file 14:
- Keep manual memory management
- Add factual comments
- Review monitoring cleanup

### Step 5: Final Verification (15 min)
- Build entire project
- Run test suite
- Update DEINIT_STANDARDS.md with any edge cases discovered
- Update .cursorrules if needed
- Commit Phase 3

---

## Expected Completion
**Total time:** ~2 hours
**Final result:** 93/93 files refactored (100%)

---

## Success Metrics
- ✅ Zero empty protective deinits
- ✅ Zero `nonisolated(unsafe)` in application code
- ✅ All async resources tracked in CancellationBag
- ✅ All deinit blocks follow canonical patterns
- ✅ All folklore comments deleted
- ✅ Project builds successfully
- ✅ Test suite passes
