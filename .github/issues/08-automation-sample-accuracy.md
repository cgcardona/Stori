# [Mission Critical] Sample-accurate automation in playback and export

**Labels:** `audio`, `automation`, `engine`, `mission critical`, `WYHIWYG`  
**Goal:** Automation (volume, pan, plugin params) is applied at the correct sample in both live playback and offline export, with no stepping or timing drift. Under the hood only.

## Context

Automation curves define how parameters change over time. If the engine or export applies them at buffer boundaries only, or with a different sample rate or timing than playback, the result is zipper noise, stepped moves, or a bounce that doesn’t match what you heard. Pro DAWs apply automation per-sample or at least per-frame with correct interpolation. This issue focuses on the audio engine and export pipeline: correct evaluation and application of automation, no UI.

## WYHIWYG impact

- **What you hear:** Automation must move parameters at the right moment so fades, pans, and plugin automation sound correct and match the timeline.
- **Export:** The same automation must be applied in offline render so the bounce is identical to playback.

## Task (engine and export only — no UI)

1. **Playback path**  
   - Trace where automation is applied in live playback (e.g. `AutomationProcessor`, track volume/pan, plugin parameters). Ensure curves are evaluated at the correct time (sample or frame) using the single source of playback position (see issue 07). Verify interpolation (linear, etc.) is smooth and consistent.

2. **Export path**  
   - Ensure offline export uses the same automation curves, same evaluation (time → value), and same application order as playback. No separate “export automation” logic that could diverge. If automation is not yet applied in export, implement it so that export matches playback.

3. **Timing and sample rate**  
   - Handle project tempo and sample rate correctly in both paths (beats → time → sample index). Document how automation time is derived (e.g. from beat position and tempo) so playback and export stay in sync.

4. **Tests**  
   - Add a test: simple project with one automation curve (e.g. volume ramp), run playback and export, compare (e.g. null test or sample-level comparison) so that automation application is verified. No GUI — automated test only.

## Acceptance criteria

- [ ] Automation is applied in playback at the correct time (sample/frame) with consistent interpolation.
- [ ] Export applies the same automation so that exported audio matches what is heard during playback.
- [ ] At least one automated test validates automation parity between playback and export (or automation timing).

## Files to start from

- `Stori/Core/Audio/` — automation application in the graph (e.g. `AutomationProcessor`, track nodes).
- `Stori/Core/Services/ProjectExportService.swift` — offline graph and automation in render.
- `Stori/Core/Models/` — automation curve models and interpolation.
