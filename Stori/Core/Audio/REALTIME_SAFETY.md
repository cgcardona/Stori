# Real-Time Safety Guidelines for Audio Thread

## Overview

The audio thread runs at high priority and cannot tolerate allocations, blocking locks, or long-running operations. Any violation causes glitches, dropouts, or priority inversion that ruins the user experience.

## Critical Rules

### ❌ NEVER on Audio Thread:
1. **Memory Allocation**
   - No `Array.append()`, `Array.removeAll()`, `Dictionary[key] = value` (if it causes resize)
   - No `String` operations that allocate
   - No `malloc`, `new`, or object creation
   
2. **Blocking Operations**
   - No `DispatchQueue.main.sync` or `.main.async`
   - No file I/O, network, or syscalls
   - No long-held locks (> microseconds)
   - No Objective-C message sends that can block
   
3. **MainActor Access**
   - No reading `@MainActor` properties
   - No calling `@MainActor` functions
   - Use `nonisolated` atomic accessors instead

### ✅ SAFE on Audio Thread:
1. **Lock-Free Atomics**
   - `os_unfair_lock` with SHORT critical sections (< 10 lines)
   - Atomic integers/booleans
   - Memory-mapped ring buffers
   
2. **Pre-Allocated Buffers**
   - Buffer pools (e.g., `RecordingBufferPool`, `AudioResourcePool`)
   - Fixed-size arrays with known capacity
   
3. **Pure Computation**
   - Math operations (SIMD preferred)
   - Reading from pre-allocated structures
   - Pointer arithmetic

## Audio Thread Code Paths

### 1. `installTap` Callbacks
**Where**: Recording, metering, level monitoring  
**Files**: 
- `RecordingController.swift` (lines 377-423, 474-518)
- `TrackAudioNode.swift` (line 416)
- `BusAudioNode.swift` (lines 123, 136)
- `MeteringService.swift` (line 216)

**Safety Pattern**:
```swift
inputNode.installTap(...) { [weak self] buffer, _ in
    guard let self = self else { return }
    
    // ✅ SAFE: Lock-protected write
    os_unfair_lock_lock(&self.lock)
    self._value = computedValue
    os_unfair_lock_unlock(&self.lock)
    
    // ❌ NEVER: Dispatch to main
    // DispatchQueue.main.async { self.value = computedValue }
}
```

### 2. Render Callbacks (AVAudioSourceNode)
**Where**: Synthesis, audio generation  
**Files**:
- `SynthEngine.swift` (lines 504-518, 595-626)

**Safety Pattern**:
```swift
AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
    // ✅ SAFE: Read from lock-protected storage
    voicesLock.lock()
    let voicesCopy = voices  // Shallow copy of array reference
    voicesLock.unlock()
    
    // ✅ SAFE: Render loop (no allocation)
    for voice in voicesCopy where voice.isActive {
        voice.render(into: buffer, frameCount: frameCount)
    }
    
    // ✅ SAFE: Mark for cleanup (no allocation)
    for i in 0..<voices.count {
        if voices[i].shouldDeallocate() {
            voices[i].isActive = false  // Just mark, don't remove
        }
    }
    
    // ❌ NEVER: Remove from array (allocates!)
    // voices.removeAll { $0.shouldDeallocate() }
    
    return noErr
}
```

### 3. MIDI Scheduling
**Where**: Sample-accurate MIDI event dispatch  
**Files**:
- `SampleAccurateMIDIScheduler.swift` (lines 280-350)
- `MIDIPlaybackEngine.swift` (lines 125-130, 306-330)

**Safety Pattern**:
```swift
// ✅ SAFE: Read atomic position (no MainActor)
let currentBeat = transport.atomicBeatPosition

// ✅ SAFE: Pre-cached MIDI blocks
if let midiBlock = midiBlocks[trackId] {
    midiBlock(status, data1, data2, sampleTime)
}

// ❌ NEVER: Read MainActor property
// let currentBeat = audioEngine.currentPosition.beats
```

### 4. Position Reads
**Where**: Transport, automation, metronome  
**Files**:
- `TransportController.swift` (lines 68-80)
- `MetronomeEngine.swift` (lines 311, 383)
- `RecordingController.swift` (lines 389, 486)

**Safety Pattern**:
```swift
// ✅ SAFE: Atomic read
nonisolated var atomicBeatPosition: Double {
    os_unfair_lock_lock(&beatPositionLock)
    defer { os_unfair_lock_unlock(&beatPositionLock) }
    
    // Wall-clock calculation (no allocation)
    let elapsed = CACurrentMediaTime() - _startWallTime
    return _startBeat + (elapsed * (_tempo / 60.0))
}

// ❌ NEVER: MainActor property
// @MainActor var currentPosition: PlaybackPosition
```

## Violations Fixed in This Codebase

### 1. RecordingController: MainActor Access (CRITICAL)
**Before**:
```swift
installTap(...) { buffer, _ in
    // ❌ MainActor property read from audio thread!
    self.recordingStartBeat = self.getCurrentPosition().beats
}
```

**After**:
```swift
installTap(...) { buffer, _ in
    // ✅ Thread-safe atomic read
    if let transport = self.transportController {
        self.recordingStartBeat = transport.atomicBeatPosition
    }
}
```

### 2. SynthEngine: Memory Allocation (CRITICAL)
**Before**:
```swift
func renderVoices(...) {
    voicesLock.lock()
    // ... render ...
    voices.removeAll { $0.shouldDeallocate() }  // ❌ ALLOCATES!
    voicesLock.unlock()
}
```

**After**:
```swift
func renderVoices(...) {
    voicesLock.lock()
    // ... render ...
    // ✅ Mark inactive (no allocation)
    for i in 0..<voices.count {
        if voices[i].shouldDeallocate() {
            voices[i].isActive = false
        }
    }
    voicesLock.unlock()
}

func noteOn(...) {
    // ✅ Cleanup outside render path
    voices.removeAll { !$0.isActive }
}
```

### 3. BusAudioNode: Priority Inversion (MEDIUM)
**Before**:
```swift
installTap(...) { buffer, _ in
    let level = calculateLevel(buffer)
    DispatchQueue.main.async {  // ❌ Priority inversion!
        self.inputLevel = level
    }
}
```

**After**:
```swift
installTap(...) { buffer, _ in
    let level = calculateLevel(buffer)
    // ✅ Direct write with lock
    os_unfair_lock_lock(&self.inputLevelLock)
    self._inputLevel = level
    os_unfair_lock_unlock(&self.inputLevelLock)
}
```

## Testing Real-Time Safety

### Tools
1. **Instruments** - Time Profiler, Allocations
2. **MallocStackLogging** - Catch allocations on audio thread
3. **Thread Sanitizer** - Detect data races

### Manual Verification
```swift
// Add to audio callback during development:
#if DEBUG
let start = mach_absolute_time()
// ... audio code ...
let duration = mach_absolute_time() - start
assert(duration < maxAllowedTicks, "Audio callback too slow!")
#endif
```

## References
- Apple: [Core Audio Programming Guide](https://developer.apple.com/library/archive/documentation/MusicAudio/Conceptual/CoreAudioOverview/)
- Ross Bencina: [Real-time Audio Programming 101](http://www.rossbencina.com/code/real-time-audio-programming-101-time-waits-for-nothing)
- `.cursorrules`: "< 10ms round-trip audio latency"

## Future Work
- [ ] Add automated RT safety tests
- [ ] Profile worst-case lock hold times
- [ ] Document plugin AU format negotiation safety
- [ ] Add RT-safe logging (ring buffer)
