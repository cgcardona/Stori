# [WYHIWYG] Expose round-trip latency and buffer size in UI

**Labels:** `good first issue`, `audio`, `WYHIWYG`  
**Goal:** What you hear is what you get — users must know *when* they’re hearing it.

## Context

Stori uses fixed buffer sizes in `AudioConstants` (e.g. `defaultBufferSize: 512`, `recordingTapBufferSize: 1024`). There is no UI showing round-trip latency or buffer size. Professional DAWs (e.g. Logic Pro) show input/output latency and often let users choose buffer size so they can trade latency vs CPU and understand monitoring delay.

## WYHIWYG impact

- **Monitoring:** When recording, the performer hears themselves with delay. If that delay isn’t visible, they can’t judge monitoring quality or know why things feel “off.”
- **Trust:** Showing latency and buffer builds trust that the app is transparent about what you hear.

## Task

1. **Compute and expose round-trip latency**  
   Use `AVAudioEngine` / `AVAudioSession` (or equivalent) to get input + output latency and buffer frame count. Expose this via a small service or existing audio config (e.g. `DeviceConfigurationManager` or a dedicated `LatencyReportingService`).

2. **Show it in the UI**  
   Add a small, non-intrusive display (e.g. in transport bar, status bar, or Setup/Audio preferences) that shows:
   - Round-trip latency in ms (or ms + buffer size in samples/frames).
   - Optional: current buffer size (frames) and sample rate.

3. **Optional follow-up**  
   Allow selecting buffer size (e.g. 128, 256, 512, 1024) from preferences and apply it to the engine so users can tune for low-latency monitoring vs stability. Document that lower buffer = lower latency but higher CPU.

## Acceptance criteria

- [ ] Round-trip latency (ms) is computed from real device/engine values.
- [ ] Latency (and optionally buffer size) is visible in the UI.
- [ ] No regression in playback or recording.

## Files to start from

- `Stori/Core/Audio/SampleAccurateMIDIScheduler.swift` — `AudioConstants` (buffer sizes).
- `Stori/Core/Audio/DeviceConfigurationManager.swift` — device/format configuration.
- Transport or Setup UI for the latency display.

## References

- `.cursorrules`: Performance — “< 10ms round-trip audio latency” goal.
- Apple: `AVAudioSession.inputLatency`, `outputLatency` (iOS); on macOS, use `AVAudioEngine` and node latencies / buffer size to derive round-trip.
