# [Mission Critical] Harden sample-accurate recording start and alignment

**Labels:** `audio`, `recording`, `engine`, `mission critical`, `WYHIWYG`  
**Goal:** Recorded material starts at the exact timeline position the user chose — what you hear (playback of the take) lines up with the grid. Engine and tests only.

## Context

`RecordingController` captures `recordingStartBeat` on the first buffer arrival and uses that for alignment. Multiple sample rates are involved (engine vs file), and there are comments in `TrackAudioNode` about the “DUAL SAMPLE RATE SYSTEM” and timing. Small drifts or off-by-one-frame issues break WYHIWYG for recording. Mission-critical DAWs must be sample-accurate on record start.

## WYHIWYG impact

- **Punch-in / overdub:** If the start of the recording is even a few ms off, the take will be out of sync when played back.
- **Trust:** Users must be able to rely on “record from here” meaning “this bar/beat is where the take starts.”

## Task (engine and tests only — no UI)

1. **Clarify and document timing in code**  
   - Document the exact moment we consider “recording start” (first sample of the first buffer after transport goes into record, etc.) in `RecordingController` or a shared timing doc.
   - Ensure `recordingStartBeat` (or equivalent) is derived in a way that matches how we later schedule playback (same tempo, same beat↔sample mapping).

2. **Engine vs file sample rate**  
   - Re-read the dual–sample-rate comments in `TrackAudioNode` and `RecordingController`.
   - Ensure recording start is expressed so it’s correct for both the engine timeline (beats) and the written file (sample offset if needed). Fix any inconsistency.

3. **Edge cases and tests**  
   - Record start exactly on bar/beat; record start while already playing; small buffer sizes.
   - Add or extend tests in `StoriTests/Integration/RecordingAlignmentTests.swift` (or equivalent) to lock in sample-accurate behavior. No manual-only steps — automated tests that assert alignment.

## Acceptance criteria

- [ ] Recording start beat is defined and documented in code; it matches playback scheduling semantics.
- [ ] Recorded regions play back aligned to the same bar/beat they were recorded from (verified by automated test).
- [ ] No regressions in existing recording or playback tests.

## Files to start from

- `Stori/Core/Audio/RecordingController.swift` — `recordingStartBeat`, first buffer handling.
- `Stori/Core/Audio/TrackAudioNode.swift` — scheduling and dual sample rate comments.
- `StoriTests/Integration/RecordingAlignmentTests.swift`
