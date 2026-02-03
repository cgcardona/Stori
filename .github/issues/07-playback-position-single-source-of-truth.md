# [Mission Critical] Single source of truth for playback position (no drift)

**Labels:** `audio`, `transport`, `engine`, `mission critical`, `WYHIWYG`  
**Goal:** One authoritative playback position in beats (and derived time). All consumers (transport UI, MIDI scheduler, metronome, automation, export) read from the same source so there is no drift or desync.

## Context

Playback position is used by the transport, the MIDI scheduler, the metronome, automation, and the export pipeline. If any of these uses a different clock or recomputes position from different inputs (e.g. wall time + tempo in one place, engine time in another), the result can be drift, late/early notes, or automation that doesn’t line up with audio. Mission-critical DAWs have a single, sample-accurate playhead.

## WYHIWYG impact

- **What you hear:** If the metronome, MIDI, and automation are not aligned to the same beat position, what you hear (clicks, notes, sweeps) won’t match the grid or each other.
- **Export:** Offline render must use the same notion of “current beat” and tempo so automation and events line up with playback.

## Task (engine and transport only — no UI)

1. **Identify all position consumers**  
   - List every component that needs “current playback position” or “current time in beats”: `TransportController`, `SampleAccurateMIDIScheduler`, `MetronomeEngine`, automation, `PlaybackSchedulingCoordinator`, export. For each, document where it gets position (atomic from transport, callback, recomputed from wall time, etc.).

2. **Define the single source**  
   - Choose one canonical source (e.g. `TransportController`’s atomic beat position, updated from a single place driven by the engine or a high-resolution timer). Ensure it is sample-rate and tempo aware so that “current beat” and “current time in seconds” are consistent.

3. **Route all consumers to that source**  
   - Refactor so that MIDI scheduler, metronome, automation, and any other consumer read current position only from this source (or from a thin wrapper that itself reads from it). Remove or fix any path that recomputes position independently in a way that can drift.

4. **Tests**  
   - Add a test that runs playback for a fixed duration and asserts that the reported position (from the single source) matches expected beats at the project tempo (e.g. 4 bars at 120 BPM = 8 seconds, position matches). Optional: assert that MIDI events and metronome ticks align to the same grid.

## Acceptance criteria

- [ ] One clearly defined source of truth for “current playback position in beats” (and derived time).
- [ ] All identified consumers use that source; no independent position derivation that can drift.
- [ ] At least one test validates position consistency over time; no regressions in playback or export.

## Files to start from

- `Stori/Core/Audio/TransportController.swift` — atomic position, `atomicBeatPosition`, `playbackStartWallTime`.
- `Stori/Core/Audio/SampleAccurateMIDIScheduler.swift` — MIDI timing reference.
- `Stori/Core/Audio/MetronomeEngine.swift` — click timing.
- `Stori/Core/Audio/AudioEngine.swift` — who drives position updates.
- Automation and `PlaybackSchedulingCoordinator` — where they get “current time”.
