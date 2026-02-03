# [Mission Critical] Harden MIDI scheduling (jitter, lookahead, start/stop)

**Labels:** `audio`, `MIDI`, `engine`, `mission critical`, `WYHIWYG`  
**Goal:** MIDI notes and events are scheduled sample-accurately, with no late notes, no jitter on start/stop or tempo change, and correct handling of lookahead and edge cases. Engine only.

## Context

`SampleAccurateMIDIScheduler` and `MIDIPlaybackEngine` schedule MIDI using host time and beat position. For a mission-critical DAW, notes must never be late (which causes missing or delayed attacks), and scheduling must survive transport start/stop, tempo changes, and loop jumps without glitches or double/lost notes. Lookahead and buffer boundaries must be correct so that all events in the next few ms are scheduled in time.

## WYHIWYG impact

- **What you hear:** Late or dropped MIDI means wrong or missing notes; that’s a direct WYHIWYG failure.
- **Professional use:** Tight timing is non-negotiable for drums, synths, and scoring.

## Task (engine only — no UI)

1. **Review lookahead and buffer timing**  
   - Confirm MIDI lookahead (e.g. `midiLookaheadSeconds`) and timer interval are sufficient so that every note is scheduled before its playback time. Document the worst-case latency from “decision to schedule” to “note actually played” and ensure it’s less than lookahead.

2. **Transport edge cases**  
   - On transport stop: ensure no stray or double notes (all scheduled events cleared or completed cleanly). On transport start: ensure first events are scheduled from the correct beat and sample. On tempo change or cycle jump: ensure the scheduler’s reference (e.g. `MIDITimingReference`) is updated and no old scheduled events conflict with new position.

3. **Real-time safety**  
   - Ensure scheduling path doesn’t allocate on the audio thread and doesn’t block (see issue 06). Use lock-free or very short critical sections when reading/writing scheduled blocks or position.

4. **Tests**  
   - Add tests: (a) schedule a note at a known beat, run playback, assert it plays at the expected time (e.g. via callback or rendered output); (b) start/stop/start and assert no duplicate or missing notes; (c) optional: tempo change mid-playback and assert notes still align to the new tempo. No UI — automated tests only.

## Acceptance criteria

- [ ] MIDI events are scheduled with sufficient lookahead so no note is late.
- [ ] Transport start, stop, and tempo/cycle jump do not cause duplicate, missing, or mis-timed notes.
- [ ] Scheduling path is real-time safe (no allocation, no blocking).
- [ ] At least one test validates MIDI timing and at least one validates start/stop or tempo change behavior.

## Files to start from

- `Stori/Core/Audio/SampleAccurateMIDIScheduler.swift` — lookahead, `MIDITimingReference`, `sampleTime(forBeat:)`.
- `Stori/Core/Audio/MIDIPlaybackEngine.swift` — scheduling, transport notifications.
- `Stori/Core/Audio/TransportController.swift` — start/stop, cycle jump, atomic position.
- `Stori/Core/Audio/AudioEngine.swift` — how MIDI scheduler is driven.
