# [Mission Critical] Implement tap tempo service (engine only)

**Labels:** `audio`, `transport`, `engine`, `mission critical`, `WYHIWYG`  
**Goal:** Tempo can be set from performance so click and playback match the performer’s timing. Core logic only — no UI work in this issue.

## Context

`DAWControlBar` has a “Tap Tempo” button with `/* TODO: Implement tap tempo */`. Logic Pro and other pro DAWs derive project tempo from tap intervals. For WYHIWYG, the grid and click must be able to match the performer’s feel. This issue is limited to the under-the-hood service: tap detection, BPM computation, and updating project tempo. UI wiring (button, feedback) is explicitly out of scope.

## WYHIWYG impact

- **Tempo = what you hear:** If the grid and click can’t follow the performer’s tempo, the DAW is not “what you hear is what you get” for time.
- **Mission critical:** Tap tempo is standard in pro DAWs; the engine must support it before the button is wired.

## Task (engine / service only — no UI)

1. **Tap detection and BPM computation**  
   - Implement a `TapTempoService` (or equivalent) that accepts “tap” events (timestamps). From the last N taps (e.g. 4–8), compute the average interval (or median) and derive BPM: `60 / interval_seconds`.
   - Handle edge cases: single tap (no tempo change or keep previous?), two taps (use that one interval), reset after a long pause (e.g. 2+ seconds). Optionally clamp BPM to a sensible range (e.g. 40–300).

2. **Apply to project**  
   - The service must update the current project’s tempo (via `ProjectManager` or whoever owns tempo). Document whether tempo is applied immediately or at next bar when transport is playing — and implement that behavior consistently.

3. **No UI in this issue**  
   - Do not wire the Tap Tempo button or add any UI feedback. The deliverable is a callable service/API that: (a) accepts tap timestamps, (b) returns or applies computed BPM to the project. The existing button can be wired in a separate issue.

4. **Testability**  
   - Add unit tests: given a sequence of timestamps at a known interval, assert the computed BPM is correct; test reset-after-pause and clamp behavior.

## Acceptance criteria

- [ ] A service or clear API exists that accepts tap timestamps and computes BPM.
- [ ] Computed BPM is applied to the current project’s tempo (with documented behavior when transport is playing).
- [ ] Edge cases (single tap, two taps, long pause, BPM clamp) are handled and tested.
- [ ] No UI changes; no new buttons or displays. Button wiring is out of scope.

## Files to start from

- `Stori/Core/Services/ProjectManager.swift` — where tempo is stored and updated.
- New: `Stori/Core/Services/TapTempoService.swift` (or similar under Core/Services or Core/Audio).
- `Stori/Features/Transport/DAWControlBar.swift` — for context only (Tap Tempo button); do not modify for this issue.
