# [WYHIWYG] Implement tap tempo

**Labels:** `good first issue`, `transport`, `WYHIWYG`  
**Goal:** Tempo can be set from performance so what you hear (click and playback) matches the performer’s timing.

## Context

`DAWControlBar` has a “Tap Tempo” button with `/* TODO: Implement tap tempo */`. Logic Pro and other DAWs let users tap a key or button in time with the performance and set the project tempo from the tap interval. Without this, tempo may not match the performance, so the grid and playback feel wrong — a WYHIWYG issue for timing.

## WYHIWYG impact

- **Tempo = what you hear:** If the grid and click don’t match the performer’s feel, the DAW is not “what you hear is what you get” for time.  
- **Workflow:** Tap tempo is a standard way to lock the session to the performer’s tempo.

## Task

1. **Implement tap detection**  
   - On each “tap” (e.g. button click or keyboard shortcut), record a timestamp.  
   - From the last N taps (e.g. 4–8), compute the average interval (or median) and derive BPM: `60 / interval_seconds`.  
   - Handle edge cases: single tap (no tempo change or keep previous?), two taps (use that one interval), reset after a long pause.

2. **Apply to project**  
   - Update the current project’s tempo with the computed BPM (via `ProjectManager` or whoever owns tempo).  
   - Optionally clamp to a sensible range (e.g. 40–300 BPM).  
   - If transport is playing, consider whether to apply immediately or at next bar (document behavior).

3. **UI**  
   - Wire the existing “Tap Tempo” button in `DAWControlBar` to this logic.  
   - Optional: show momentary feedback (e.g. “Tap…” or current computed BPM) so the user knows taps are registered.

4. **Accessibility**  
   - Add an accessibility label and, if possible, a keyboard shortcut for tap (so users don’t have to click the button in time).

## Acceptance criteria

- [ ] Tapping 4+ times in steady rhythm sets project tempo to the corresponding BPM.
- [ ] Tempo is applied to the current project and reflected in transport/click.
- [ ] Tap Tempo is accessible (label + optional shortcut).

## Files to start from

- `Stori/Features/Transport/DAWControlBar.swift` — Tap Tempo button (search for “Tap Tempo”).
- `Stori/Core/Services/ProjectManager.swift` or project model — where tempo is stored and updated.
