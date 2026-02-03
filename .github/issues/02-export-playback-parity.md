# [Mission Critical] Guarantee export matches playback (playback = bounce)

**Labels:** `audio`, `export`, `engine`, `mission critical`, `WYHIWYG`  
**Goal:** What you hear in the session is exactly what you get in the exported file. Under-the-hood alignment of signal path and processing only.

## Context

Export uses an offline `AVAudioEngine` and `setupOfflineAudioGraph` / `renderProjectAudio` in `ProjectExportService`. Playback uses the live `AudioEngine`. Any difference in graph setup, plugin order, bus routing, or automation application makes the bounce sound different from what the user heard — breaking WYHIWYG. This is core mission-critical behavior for a pro DAW.

## WYHIWYG impact

- **Core promise:** “What you hear is what you get.” If export differs from playback, the DAW fails its main guarantee.
- **Professional use:** Producers must be able to trust that the printed mix is identical to the session.

## Task (engine and export pipeline only — no UI)

1. **Align signal path between live and offline**  
   - List every processing step in live playback (track order, plugins, buses, master, PDC).
   - Ensure offline export builds the same graph (same order, same gains, same plugin state).
   - Add assertions or internal checks that compare key parameters (track mute/solo, bus sends, master fader) between live and offline code paths so regressions are caught.

2. **Automation in export**  
   - Confirm automation (volume, pan, plugin params) is applied in offline render exactly as in playback (same curves, same timing, same scaling).
   - If automation is not yet applied in export, implement it so that export is bit-accurate to what you hear. This is engine/export logic only.

3. **Verification**  
   - Add an integration test: for a known project, run offline export and compare (e.g. null test or sample-accurate diff) against a reference or against live-rendered output. No user-facing UI — automated test only.

## Acceptance criteria

- [ ] Offline export uses the same signal path and processing order as live playback.
- [ ] Automation is applied in export so that exported audio matches what is heard during playback.
- [ ] A test or automated process verifies export vs playback parity (e.g. null test).

## Files to start from

- `Stori/Core/Services/ProjectExportService.swift` — `setupOfflineAudioGraph`, `renderProjectAudio`.
- `Stori/Core/Audio/AudioEngine.swift` — live graph setup.
- Automation application in playback vs export (Core/Audio and Core/Services).
