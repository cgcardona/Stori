# [Mission Critical] Verify and harden plugin delay compensation (PDC)

**Labels:** `audio`, `plugins`, `engine`, `mission critical`, `WYHIWYG`  
**Goal:** All tracks stay phase- and time-aligned when using latency-inducing plugins. Engine and export only — no UI.

## Context

`PluginLatencyManager` exists and applies compensation delays so tracks with less plugin latency are delayed to match the worst-case track. This is critical for WYHIWYG: without correct PDC, heavy plugins on one track make that track late and cause phase/alignment issues. For a UFO-grade DAW, PDC must be verified and bulletproof in both playback and export.

## WYHIWYG impact

- **Phase and timing:** If PDC is wrong or missing on a path, the summed mix (and export) will not match what the user expects — phase smear, flamming, or mud.
- **Export:** Offline export must use the same PDC values as playback so the bounce matches what you hear.

## Task (engine and export only — no UI)

1. **Verify PDC in playback**  
   - Trace where `PluginLatencyManager.getCompensationDelay(for:)` is used (e.g. in `TrackAudioNode` or scheduling).
   - Confirm every playback path that uses plugins applies this delay.
   - Check that plugin latency is read correctly (AU `latency` in seconds → samples at current sample rate) and that the manager’s sample rate is kept in sync with the engine.

2. **Verify PDC in export**  
   - Ensure offline export applies the same per-track compensation (or equivalent) so exported audio matches playback. No separate “export PDC” logic that could drift from playback.

3. **Harden and test**  
   - Add a unit or integration test: insert a known-latency plugin (or mock), assert that the mix remains aligned (e.g. null test with/without PDC, or phase alignment check). Document PDC behavior in code comments so future contributors know where it’s applied and why.

## Acceptance criteria

- [ ] All playback paths that use plugins apply PDC from `PluginLatencyManager`.
- [ ] Export uses the same PDC logic so bounce matches playback.
- [ ] At least one test validates PDC behavior; PDC is documented in code for maintainers.

## Files to start from

- `Stori/Core/Audio/PluginLatencyManager.swift`
- `Stori/Core/Audio/TrackAudioNode.swift` — scheduling and `compensationDelaySamples`
- `Stori/Core/Services/ProjectExportService.swift` — offline graph and delay compensation
