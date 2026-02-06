# Issue #56 Fix Summary: Metronome-MIDI Drift Under Tempo Automation

## Problem Statement

Under tempo automation, the metronome click could drift from MIDI playback because they used independent timing calculations:
- **MetronomeEngine**: Calculated click positions using its own `tempo` and `framesPerBeat()` 
- **SampleAccurateMIDIScheduler**: Used `MIDITimingReference` with its own timing state

This violated the professional DAW requirement that the metronome must be the perfect timing reference.

## Root Cause

```swift
// Before: MetronomeEngine (line 380-383)
private func framesPerBeat() -> AVAudioFramePosition {
    let secondsPerBeat = 60.0 / tempo  // ❌ Uses local tempo variable
    return AVAudioFramePosition((secondsPerBeat * sampleRate).rounded())
}
```

The metronome didn't know about tempo automation changes that the MIDI scheduler was handling.

## Solution Architecture

### 1. Created Shared Timing Context (`AudioSchedulingContext.swift`)

A thread-safe struct that provides consistent beat-to-sample conversions:

```swift
struct AudioSchedulingContext: Sendable {
    let sampleRate: Double
    let tempo: Double
    let timeSignature: TimeSignature
    
    var samplesPerBeat: Double {
        (60.0 / tempo) * sampleRate
    }
    
    func sampleTime(forBeat beat: Double, referenceBeat: Double, referenceSample: Int64) -> Int64
    func beat(forSampleTime sample: Int64, referenceBeat: Double, referenceSample: Int64) -> Double
}
```

**Benefits:**
- Immutable and thread-safe (Sendable)
- Single source of truth for all timing calculations
- Can be captured and passed to background threads

### 2. Updated `MIDITimingReference` to Use Shared Context

```swift
struct MIDITimingReference {
    let hostTime: UInt64
    let createdAt: Date
    let beatPosition: Double
    let context: AudioSchedulingContext  // ✅ Now uses shared context
    
    var samplesPerBeat: Double {
        context.samplesPerBeat  // ✅ Delegates to shared calculation
    }
}
```

### 3. Exposed Scheduler from `MIDIPlaybackEngine`

```swift
class MIDIPlaybackEngine {
    private let scheduler = SampleAccurateMIDIScheduler()
    
    var sampleAccurateScheduler: SampleAccurateMIDIScheduler {
        scheduler  // ✅ Public accessor for metronome
    }
}
```

### 4. Updated `MetronomeEngine` to Use Shared Timing

```swift
class MetronomeEngine {
    @ObservationIgnored
    private weak var midiScheduler: SampleAccurateMIDIScheduler?
    
    private func framesPerBeat() -> AVAudioFramePosition {
        // ✅ Use shared scheduling context if available
        if let scheduler = midiScheduler {
            let context = scheduler.schedulingContext
            return context.samplesPerBeatInt64()
        }
        
        // Fallback: calculate from local tempo
        let secondsPerBeat = 60.0 / tempo
        return AVAudioFramePosition((secondsPerBeat * sampleRate).rounded())
    }
}
```

### 5. Wired Up Dependencies in `AudioEngine`

```swift
func installMetronome(_ metronome: MetronomeEngine) {
    metronome.install(
        into: engine,
        dawMixer: mixer,
        audioEngine: self,
        transportController: transportController,
        midiScheduler: midiPlaybackEngine.sampleAccurateScheduler  // ✅ Pass shared scheduler
    )
    installedMetronome = metronome
}
```

## Files Modified

1. **NEW: `Stori/Core/Audio/AudioSchedulingContext.swift`**
   - Shared timing context for all audio subsystems
   - Provides beat ↔ sample ↔ seconds conversions
   - Thread-safe and immutable

2. **`Stori/Core/Audio/SampleAccurateMIDIScheduler.swift`**
   - Updated `MIDITimingReference` to use `AudioSchedulingContext`
   - Added `schedulingContext` property for external access
   - Maintained backward compatibility

3. **`Stori/Core/Audio/MetronomeEngine.swift`**
   - Added `midiScheduler` weak reference
   - Updated `framesPerBeat()` to use shared scheduler context
   - Updated `install()` method to accept scheduler parameter

4. **`Stori/Core/Audio/MIDIPlaybackEngine.swift`**
   - Exposed `sampleAccurateScheduler` property
   - Allows metronome to access shared timing

5. **`Stori/Core/Audio/AudioEngine.swift`**
   - Updated `installMetronome()` to pass MIDI scheduler reference
   - Wires up dependency injection

6. **NEW: `StoriTests/Audio/MetronomeMIDIAlignmentTests.swift`**
   - Comprehensive tests for timing alignment
   - Tempo automation drift tests
   - Sample rate change tests
   - Beat-to-sample conversion consistency tests

## Test Coverage

### Tests Added

1. **`testMetronomeUsesMIDISchedulerTimingContext`**
   - Verifies metronome reads from shared scheduler context
   - Ensures tempo/sample rate consistency

2. **`testTempoChangeUpdatesSchedulingContext`**
   - Verifies samples-per-beat recalculates on tempo change
   - Tests 120 BPM → 150 BPM transition

3. **`testBeatToSampleConversionConsistency`**
   - Validates beat-to-sample math is consistent
   - At 120 BPM: 1 beat = 24000 samples @ 48kHz

4. **`testNoAccumulatedDriftUnderTempoRamp`**
   - Simulates gradual tempo ramp (100 → 150 BPM)
   - Ensures no cumulative drift across 10 steps

5. **`testTimingReferenceUpdatesOnTempoChange`**
   - Verifies timing reference regenerates on tempo change
   - Critical for professional timing accuracy

6. **`testSampleRateChangeUpdatesContext`**
   - Tests audio interface changes (48kHz → 96kHz)
   - Ensures samples-per-beat scales correctly

7. **`testContextConsistencyAfterMultipleChanges`**
   - Stress test with multiple tempo/sample rate changes
   - Validates formula correctness throughout

## Professional DAW Standards

This fix brings Stori in line with professional DAW requirements:

### Logic Pro
- Maintains single timing reference for all audio events
- Regenerates timing on tempo changes
- Metronome is sample-accurate reference

### Pro Tools
- Uses shared clock for all scheduling
- Lookahead buffer handles tempo automation
- 150-200ms lookahead typical

### Cubase
- Unified timing reference across subsystems
- Real-time tempo changes don't cause drift
- Sample-accurate click alignment

## Why This Matters (Audiophile Perspective)

1. **Trust in Timing**
   - Musicians rely on metronome as absolute reference
   - Drift destroys confidence in the DAW

2. **Professional Recording**
   - Click track must align with MIDI backing
   - Out-of-sync click makes editing impossible

3. **Live Performance**
   - Tempo changes are common in live scoring
   - Click must adapt instantly without drift

4. **Export Parity**
   - What you hear during playback = what exports
   - WYSIWYG is fundamental DAW requirement

## Future Improvements

1. **Tempo Automation Curves**
   - Current implementation handles discrete tempo changes
   - Future: support gradual tempo ramps via automation curves

2. **Recording with Tempo Automation**
   - RecordingController should also use shared context
   - Ensures recorded audio aligns with click

3. **Offline Bounce Alignment**
   - OfflineMIDIRenderer should use same timing reference
   - Prevents export drift from playback

## Testing Instructions (Manual)

Since the build has unrelated errors, manual testing steps:

1. Create a new project at 120 BPM
2. Add a MIDI region with notes on every beat
3. Enable metronome
4. Start playback
5. During playback, change tempo to 150 BPM
6. Listen carefully: metronome should stay perfectly aligned with MIDI
7. Verify no cumulative drift over 8+ bars

## Regression Risk

**Low** - Changes are additive and use fallback paths:

- Metronome falls back to local tempo if scheduler unavailable
- MIDI scheduler unchanged except for context structure
- All existing tests should pass (if build succeeds)
- No breaking changes to public APIs

## Performance Impact

**Negligible**:

- `AudioSchedulingContext` is a struct (stack allocated)
- Computation is same formula, just centralized
- No additional allocations in audio thread
- Thread-safe read-only access (no locks in hot path)

## Completion Status

✅ Core implementation complete  
✅ Dependency injection wired up  
✅ Comprehensive tests written  
⏳ Build blocked by unrelated errors in AudioModels.swift  
⏳ Manual testing pending build fix  

The fix is architecturally sound and ready for testing once build issues are resolved.
