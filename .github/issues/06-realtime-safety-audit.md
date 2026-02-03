# [Mission Critical] Real-time safety audit for the audio thread

**Labels:** `audio`, `engine`, `mission critical`, `realtime`  
**Goal:** Guarantee no allocation, no unbounded locks, and no main-thread dependency on the audio/render path. UFO-grade DAWs are real-time safe.

## Context

Audio callbacks run on a high-priority thread. Any allocation (e.g. `Array.append`, `Dictionary` growth, `malloc`) or blocking lock can cause glitches, dropouts, or priority inversion. Stori already uses patterns like `RecordingBufferPool`, `os_unfair_lock`, and `nonisolated(unsafe)` in places. This issue is an audit and fix pass: identify every code path that runs on the audio thread (or that can be called from it) and ensure it is real-time safe.

## Mission critical impact

- **Glitches and dropouts:** One allocation or block on the audio thread can ruin a take or a live performance.
- **Professional standard:** Logic Pro and other pro DAWs are built on real-time safe audio cores.

## Task (engine and core audio only — no UI)

1. **Map the audio thread**  
   - List every callback or function that runs on the audio thread: render callbacks, tap callbacks, MIDI scheduling, playback scheduling, PDC reads, etc.
   - For each, trace all called code (including into `TrackAudioNode`, `PluginLatencyManager.getCompensationDelay`, `TransportController` atomic access, buffers, etc.).

2. **Eliminate allocations**  
   - Ensure no `Array`/`Dictionary` mutations that can reallocate, no `String` operations that allocate, no `malloc`/new buffers in hot paths. Pre-allocate pools (like `RecordingBufferPool`) and use fixed-size or lock-free structures where needed.

3. **Eliminate blocking**  
   - Replace or document any lock that can block (e.g. `DispatchQueue.sync`, long-held locks). Prefer `os_unfair_lock` with very short critical sections, or lock-free atomics. Ensure no main-thread dependency (e.g. no `DispatchQueue.main.sync` from audio thread).

4. **Document and test**  
   - Add a short “Real-time safety” section in code (e.g. in `AudioEngine` or a dedicated AUDIO_THREAD.md) listing which modules are RT-safe and which are not. Optional: add a test or script that runs with MallocStackLogging or similar to catch allocations on the audio thread during a playback/record run.

## Acceptance criteria

- [ ] All code paths that run on the audio thread are identified and documented.
- [ ] No allocation or blocking lock is performed on the audio thread in those paths; any exception is documented and justified.
- [ ] Documentation exists for future contributors (what is RT-safe, what to avoid).

## Files to start from

- `Stori/Core/Audio/AudioEngine.swift` — engine and render flow.
- `Stori/Core/Audio/RecordingController.swift` — tap and buffer pool.
- `Stori/Core/Audio/TrackAudioNode.swift` — scheduling.
- `Stori/Core/Audio/PluginLatencyManager.swift` — `getCompensationDelay` (nonisolated).
- `Stori/Core/Audio/TransportController.swift` — atomic position access.
- `Stori/Core/Audio/MIDIPlaybackEngine.swift` — MIDI scheduling.
