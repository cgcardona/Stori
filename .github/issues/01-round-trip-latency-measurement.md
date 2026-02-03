# [Mission Critical] Implement round-trip latency measurement in the engine

**Labels:** `audio`, `engine`, `mission critical`, `WYHIWYG`  
**Goal:** The engine must *know* its round-trip latency so monitoring and future features can rely on accurate timing. No UI — under the hood only.

## Context

Stori uses fixed buffer sizes in `AudioConstants` (e.g. `defaultBufferSize: 512`, `recordingTapBufferSize: 1024`). There is no internal API that computes or exposes round-trip latency (input + output + buffer). Professional DAWs need this value for low-latency monitoring paths, delay compensation, and consistent behavior across devices. What you hear is what you get only if the engine has an accurate picture of when sound leaves and when it comes back.

## WYHIWYG impact

- **Monitoring:** Recording and monitoring paths need to know total delay so any future compensation or reporting is correct.
- **Mission critical:** Latency is a number the engine must compute and expose to services; it should not be guessed or hardcoded.

## Task (engine / services only — no UI)

1. **Compute round-trip latency from real device and graph**  
   Use `AVAudioEngine`, input/output node formats, and buffer frame count to derive:
   - Input latency (seconds or samples at current sample rate).
   - Output latency.
   - Round-trip = input + output + (buffer size in time).
   Expose this via a dedicated service (e.g. `LatencyReportingService`) or extend `DeviceConfigurationManager` with a method that returns current round-trip latency (and optionally input/output separately). All values must be derived from the actual engine/device, not constants.

2. **Integrate with engine lifecycle**  
   When the engine is configured or the device/sample rate/buffer size changes, recompute and store the latency. Ensure any code that needs “current latency” can read it from this single source (e.g. `RecordingController` or future monitoring logic).

3. **No GUI**  
   Do not add any UI. The deliverable is an internal API and correct computation. Optional: add a unit test that, with a known buffer size and (mocked or real) device, asserts the computed latency is in the expected range.

## Acceptance criteria

- [ ] Round-trip latency (and ideally input/output separately) is computed from real engine/device values.
- [ ] A clear internal API exists for other components to read current latency (e.g. `DeviceConfigurationManager` or `LatencyReportingService`).
- [ ] Latency is updated when device or buffer configuration changes.
- [ ] No UI added; no regression in playback or recording.

## Files to start from

- `Stori/Core/Audio/SampleAccurateMIDIScheduler.swift` — `AudioConstants` (buffer sizes).
- `Stori/Core/Audio/DeviceConfigurationManager.swift` — device/format configuration.
- `Stori/Core/Audio/AudioEngine.swift` — engine and buffer configuration.

## References

- `.cursorrules`: Performance — “< 10ms round-trip audio latency” goal.
- Apple: on macOS, use `AVAudioEngine` and node latencies / buffer size to derive round-trip.
