# [Mission Critical] Plugin tails and final buffer flush in offline export

**Labels:** `audio`, `export`, `engine`, `mission critical`, `WYHIWYG`  
**Goal:** Offline bounce includes full plugin tails (reverb, delay) and a clean flush of the last buffers so the exported file is not cut short or missing tail. Engine and export only.

## Context

When exporting, the render runs for a computed duration. If that duration is exactly “project length,” reverb and delay tails get cut off — so what you hear in the session (full tail) is not what you get in the file. Similarly, if the final buffers are not flushed correctly, the last few ms can be zero or truncated. Pro DAWs add a tail region to the render and ensure all processing is drained before writing the file.

## WYHIWYG impact

- **What you hear is what you get:** If the bounce is missing the tail or the end of the file, the export does not match the session.
- **Professional use:** Deliverables must include full reverb/delay decay and a clean end.

## Task (engine and export only — no UI)

1. **Render duration includes tail**  
   - Ensure offline render duration = project length + tail. Use existing `maxPluginTailTime` (or a dedicated export tail constant) so that the engine renders extra time after the last content. Document the chosen tail length and that it applies to all exports.

2. **Drain and flush**  
   - After the last render cycle, ensure the engine (or offline graph) is given enough buffers to drain any internal delay lines and reverb tails. Then flush the final output buffer to the file so no samples are lost. Verify that the written file length in samples matches (project length + tail) × sample rate (within one buffer if needed).

3. **Consistency with playback**  
   - The tail behavior should match what the user would hear if they let playback run past the end of the project (same plugin state, same tail). No special “export tail” processing that could sound different — just more time and correct flush.

4. **Tests**  
   - Add a test: export a project that has a region with a long reverb or delay; assert the exported file length is at least project length + tail, and optionally that the last N seconds are not silence (tail is present). No UI.

## Acceptance criteria

- [ ] Offline export renders for (project length + tail) so plugin tails are included.
- [ ] Final buffers are drained and flushed so the written file is complete.
- [ ] Exported file length matches (project + tail) at the export sample rate (within one buffer).
- [ ] At least one automated test checks export length or tail presence; no regressions in export.

## Files to start from

- `Stori/Core/Services/ProjectExportService.swift` — `renderProjectAudio`, `calculateProjectDuration`, and where the render loop stops and writes the file.
- `Stori/Core/Audio/SampleAccurateMIDIScheduler.swift` — `AudioConstants.maxPluginTailTime`.
- `Stori/Core/Audio/` — any offline engine or graph that needs explicit drain/flush.
