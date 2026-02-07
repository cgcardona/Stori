# Remaining Deinit Refactor TODO

## Summary
**Status**: 10/93 files refactored (11%)  
**Remaining**: 83 files need refactoring

## ✅ Completed (10 files)
1. AudioEngine - CancellationBag pattern
2. TransportController - CancellationBag pattern  
3. AutomationServer - CancellationBag pattern
4. AudioAnalysisService - CancellationBag pattern
5. MIDIPlaybackEngine - NO deinit (no async resources)
6. PluginLatencyManager - NO deinit (no async resources)
7. StoriApp (AppState) - NO deinit (empty protective)
8. MainDAWView (SharedAudioEngine) - NO deinit (empty protective)
9. UndoService - NO deinit (empty protective)
10. CancellationBag - Infrastructure (keep as-is)

## 🔄 Remaining Refactors (83 files)

### Category A: Empty Protective Deinits (Delete Entirely) - ~70 files

These files have empty `deinit {}` blocks with folklore comments. **Delete the entire deinit block.**

**Pattern to delete:**
```swift
deinit {
    // CRITICAL: Protective deinit for @Observable @MainActor class (ASan Issue #84742+)
    // Prevents double-free from implicit Swift Concurrency property change notification tasks
}
```

**Replace with:**
```swift
// No async resources owned.
// No deinit required.
```

**Files:**
1. TrackInstrument.swift
2. DigitalMasterMintingService.swift
3. AudioEngineContext.swift
4. SandboxedPluginHost.swift
5. FeedbackProtectionMonitor.swift
6. AudioResourcePool.swift
7. BusManager.swift
8. PlaybackSchedulingCoordinator.swift (has comment "Empty deinit is sufficient")
9. AudioFormatCoordinator.swift
10. AudioPerformanceMonitor.swift
11. AudioEngineErrorTracker.swift
12. ProjectLifecycleManager.swift
13. LibraryService.swift
14. DigitalMasterService.swift
15. UpdateStore.swift
16. TrackFreezeService.swift
17. PluginGreylist.swift
18. AudioFileReferenceManager.swift
19. TrackPluginManager.swift
20. SamplerEngine.swift
21. MixerController.swift
22. MeteringService.swift
23. InstrumentPluginHost.swift
24. DrumKitEngine.swift
25. AutomationProcessor (second deinit - "Empty deinit is sufficient")
26. VirtualKeyboardView.swift
27. MIDISheetViews.swift
28. ScrollSyncModel.swift
29. TokenApprovalsView.swift
30. RoyaltyDashboardView.swift
31. RegionDragBehavior.swift
32. ScoreEntryController.swift
33. NotationQuantizer.swift
34. NotationEngraver.swift
35. LicenseEnforcer.swift
36. ContentDeliveryService.swift
37. WalletManager.swift
38. WalletService.swift
39. TransactionHistoryService.swift
40. NFTService.swift
41. AddressValidator.swift
42. AccountManager.swift
43. UserManager.swift
44. UpdateService.swift
45. TokenManager.swift
46. StoriAPIClient.swift
47. SetupManager.swift
48. SelectionManager.swift
49. ProjectManager.swift
50. PluginWatchdog.swift
51. PluginScanner.swift
52. PluginPresetManager.swift
53. MIDIDeviceManager.swift
54. InstrumentManager.swift
55. DrumKitLoader.swift
56. ConversationService.swift
57. AutomationRecorder.swift
58. AuthService.swift
59. AudioExportService.swift
60. AssetDownloadService.swift
61. AICommandDispatcher.swift
62. TrackNodeManager.swift
63. TrackAudioNode.swift
64. SynthEngine.swift
65. StepInputEngine.swift
66. SequencerEngine.swift
67. SampleAccurateMIDIScheduler.swift
68. RecordingBufferPool.swift
69. PluginInstance.swift
70. PluginDeferredDeallocationManager.swift
71. PluginChain.swift
72. MIDIBounceEngine.swift
73. DeviceConfigurationManager.swift
74. BusAudioNode.swift
75. AudioGraphManager.swift
76. AudioEngineHealthMonitor.swift
77. AudioAnalyzer.swift
78. AppLogger.swift
79. BlockchainClient.swift

### Category B: Has Actual Cleanup (Needs CancellationBag) - ~10 files

These files have real cleanup logic that needs to be refactored to use `CancellationBag`.

**Files:**
1. **MetronomeEngine.swift** - Has `beatFlashTask?.cancel()` and `fillTimer?.cancel()`
2. **ProjectExportService.swift** - Has multiple Task cancellations (3 deinit blocks!)
3. **LLMComposerClient.swift** - Has streaming task cleanup
4. **RecordingController.swift** - May have recording buffer cleanup
5. **AutomationProcessor.swift** (first deinit) - Has timer cleanup
6. **MeterDataProvider.swift** - Has `stopMonitoring()` call
7. **SynchronizedScrollView.swift** - Has NotificationCenter observer removal

### Category C: Needs Manual Review - ~3 files

**Files:**
1. **ProjectExportService.swift** - 3 separate deinit blocks (nested classes?)
2. **InstrumentPluginHost.swift** - Multiple deinit blocks
3. **SequencerEngine.swift** - Multiple deinit blocks

---

## Batch Refactor Strategy

### Phase 1: Empty Protective Deinits (Quick Wins)
**Effort**: Low (find/replace)  
**Impact**: Removes ~70 files worth of folklore  
**Time**: 30 minutes

**Script:**
```bash
# For each file in Category A:
# 1. Find the deinit block with folklore comment
# 2. Replace entire block with:
#    // No async resources owned.
#    // No deinit required.
```

### Phase 2: Refactor Files With Cleanup
**Effort**: Medium (code understanding required)  
**Impact**: Fixes ~10 files with actual async resources  
**Time**: 2-3 hours

**For each file:**
1. Identify all async resources (timers, tasks, observers)
2. Add `@ObservationIgnored private let cancels = CancellationBag()`
3. Change timer/task creation to use `cancels.insert()`
4. Ensure all closures use `[weak self]`
5. Replace deinit with canonical form:
   ```swift
   deinit {
       // Deterministic early cancellation of async resources.
       // CancellationBag is nonisolated and safe to call from deinit.
       cancels.cancelAll()
   }
   ```

### Phase 3: Manual Review
**Effort**: High (architecture understanding required)  
**Impact**: Fixes edge cases  
**Time**: 1-2 hours

Review files with multiple deinit blocks (nested classes) and ensure each follows the pattern correctly.

---

## Automated Refactor Script (Phase 1)

**Location**: `scripts/batch_refactor_empty_deinits.sh`

**Usage:**
```bash
# Dry run (preview changes)
./scripts/batch_refactor_empty_deinits.sh

# Apply changes
APPLY=1 ./scripts/batch_refactor_empty_deinits.sh
```

**What it does:**
1. Finds all files with empty protective deinit pattern
2. Replaces with standard "No async resources" comment
3. Runs build to verify no breakage
4. Reports summary

---

## Success Criteria

### Phase 1 Complete When:
- [ ] 70+ empty protective deinits deleted
- [ ] All files build successfully
- [ ] No new compiler warnings
- [ ] Git diff shows only deinit changes

### Phase 2 Complete When:
- [ ] All files with async resources use `CancellationBag`
- [ ] All timer/task closures use `[weak self]`
- [ ] Zero instances of `nonisolated(unsafe)` in application code
- [ ] All tests pass

### Phase 3 Complete When:
- [ ] All 93 files follow DAW-grade standards
- [ ] Documentation updated (`DEINIT_STANDARDS.md`)
- [ ] `.cursorrules` enforced
- [ ] Stress tests pass under ASan

---

## Commands for Tracking Progress

```bash
# Count remaining deinit blocks
find Stori -name "*.swift" -exec grep -l "deinit {" {} \; | wc -l

# Find empty protective deinits
grep -r "CRITICAL.*Protective deinit" Stori/ --include="*.swift" | wc -l

# Find files needing CancellationBag
grep -r "beatFlashTask\|fillTimer\|Task.*cancel\|timer.*cancel" Stori/ --include="*.swift" -l

# Verify no nonisolated(unsafe) in app code (infrastructure only)
grep -r "nonisolated(unsafe)" Stori/ --include="*.swift" -l | grep -v "CancellationBag\|RTSafeAtomic"
```

---

## Next Steps

1. **Commit current progress** (10 files refactored)
2. **Run Phase 1 batch refactor** (70 empty deinits)
3. **Manually refactor Phase 2** (10 files with cleanup)
4. **Review Phase 3 edge cases** (3 files)
5. **Run full test suite under ASan**
6. **Update documentation**
7. **Merge to dev**

---

## Estimated Time to Completion

- **Phase 1**: 30 minutes (scripted)
- **Phase 2**: 2-3 hours (manual)
- **Phase 3**: 1-2 hours (review)
- **Testing**: 1 hour (ASan stress tests)
- **Total**: 5-7 hours

**Current Progress**: 11% complete  
**Remaining Work**: 5-7 hours  
**Target Completion**: Next coding session
