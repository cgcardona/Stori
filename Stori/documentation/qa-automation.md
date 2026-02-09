# Stori DAW — QA Automation Infrastructure

## Architecture Overview

The QA system has four pillars:

| Layer | Location | Runs On | What It Catches |
|-------|----------|---------|-----------------|
| **Unit Tests** | `StoriTests/` | Every PR | Logic bugs, model regressions |
| **UI Smoke Tests** | `StoriUITests/` | Every PR | Broken workflows, UI regressions |
| **Audio Regression** | `StoriTests/AudioRegression/` | Every PR (small), Nightly (full) | Silent exports, routing bugs, timing drift |
| **Stress Tests** | `StoriTests/StressTests/` | Nightly | Race conditions, deadlocks, crashes |

### CI Pipelines

- **PR Tests** (`.github/workflows/pr-tests.yml`): Unit → UI Smoke → Small Audio Regression
- **Nightly** (`.github/workflows/nightly.yml`): Full suite + Stress + Performance

---

## Folder Structure

```
Stori/
├── StoriUITests/                          # XCUITest UI automation target
│   ├── StoriUITestCase.swift              # Base class (launch, helpers, screenshots)
│   ├── StoriUITestsLaunchTests.swift      # Launch validation
│   └── SmokeTests/
│       ├── TransportSmokeTests.swift      # Play/Stop/Navigate
│       ├── TrackWorkflowSmokeTests.swift  # Create Audio/MIDI, Play workflow
│       ├── PanelToggleSmokeTests.swift    # Mixer/PianoRoll/StepSeq toggles
│       ├── ExportSmokeTests.swift         # Export dialog workflow
│       └── ProjectLifecycleSmokeTests.swift # New/Save/Undo/Redo
│
├── StoriTests/
│   ├── AudioRegression/
│   │   ├── AudioRegressionTestCase.swift  # Base class (golden compare, analysis)
│   │   ├── SilenceDetectionTests.swift    # Non-silent export validation
│   │   └── GoldenFileRegressionTests.swift # Golden file comparison
│   │
│   └── StressTests/
│       ├── TrackStressTests.swift         # Rapid add/remove, concurrent mutations
│       ├── TransportStressTests.swift     # Rapid play/stop, scrub-while-playing
│       └── ExportStressTests.swift        # Rapid exports, determinism
│
├── GoldenProjects/                        # Golden audio reference files
│   ├── basic-midi.golden.wav
│   ├── volume-automation.golden.wav
│   └── pan-position.golden.wav
│
├── Stori/Core/Utilities/
│   └── AccessibilityIdentifiers.swift     # Centralized accessibility IDs
│
└── .github/workflows/
    ├── pr-tests.yml                       # PR pipeline
    └── nightly.yml                        # Nightly pipeline
```

---

## How to Add a New UI Test

### 1. Create the Test File

```swift
// StoriUITests/SmokeTests/MyFeatureTests.swift
import XCTest

final class MyFeatureTests: StoriUITestCase {
    func testMyFeatureWorks() throws {
        // 1. Find element by accessibility ID
        tap("my_feature.button")
        
        // 2. Assert state change
        assertExists("my_feature.result_view", timeout: 5)
        
        // 3. Capture screenshot
        captureScreenshot(name: "MyFeature-Complete")
    }
}
```

### 2. Add Accessibility Identifiers

In `AccessibilityIdentifiers.swift`:
```swift
enum MyFeature {
    static let button = "my_feature.button"
    static let resultView = "my_feature.result_view"
}
```

In your SwiftUI view:
```swift
Button("Do Thing") { ... }
    .accessibilityIdentifier(AccessibilityID.MyFeature.button)
```

### 3. Rules for Stable UI Tests

- **Use accessibility IDs, never coordinates**
- **Use `waitForExistence()` or `XCTNSPredicateExpectation`, never `sleep()`** (except brief Thread.sleep for animations)
- **Assert state transitions, not pixel layout**
- **Capture screenshots at key points** — they're invaluable for debugging CI failures
- **Test one workflow per test method** — if a test does too much, split it

### 4. Run Locally

```bash
# Run all UI tests
xcodebuild test \
  -project Stori.xcodeproj \
  -scheme Stori \
  -destination 'platform=macOS' \
  -only-testing:StoriUITests

# Run a specific test
xcodebuild test \
  -project Stori.xcodeproj \
  -scheme Stori \
  -destination 'platform=macOS' \
  -only-testing:StoriUITests/TransportSmokeTests/testPlayAndStop
```

---

## How to Add a New Audio Golden Test

### 1. Create the Test

```swift
// StoriTests/AudioRegression/MyGoldenTest.swift
final class MyGoldenTest: AudioRegressionTestCase {
    @MainActor
    func testMyAudioFeatureGolden() async throws {
        // 1. Build a project programmatically
        var project = AudioProject(name: "Golden-MyFeature")
        // ... add tracks, regions, automation ...
        
        // 2. Render offline
        let exportService = ProjectExportService()
        let audioEngine = AudioEngine()
        audioEngine.loadProject(project)
        try await Task.sleep(for: .milliseconds(500))
        
        let url = try await exportService.exportProjectMix(
            project: project,
            audioEngine: audioEngine
        )
        
        // 3. Basic checks
        try assertNotSilent(url)
        
        // 4. Compare against golden
        try assertAudioMatchesGolden(
            rendered: url,
            goldenName: "my-feature"  // Creates/compares GoldenProjects/my-feature.golden.wav
        )
        
        try? FileManager.default.removeItem(at: url)
    }
}
```

### 2. Generate the Golden File (First Run)

```bash
STORI_UPDATE_GOLDENS=1 xcodebuild test \
  -project Stori.xcodeproj \
  -scheme Stori \
  -destination 'platform=macOS' \
  -only-testing:StoriTests/MyGoldenTest
```

This creates `GoldenProjects/my-feature.golden.wav`. **Commit this file.**

### 3. Subsequent Runs

```bash
xcodebuild test \
  -project Stori.xcodeproj \
  -scheme Stori \
  -destination 'platform=macOS' \
  -only-testing:StoriTests/MyGoldenTest
```

The test compares the new render against the golden. If they differ beyond tolerances, the test fails and attaches both WAV files as artifacts.

### 4. Intentional Changes

When you intentionally change audio behavior (e.g., new pan law):

1. Run with `STORI_UPDATE_GOLDENS=1` to regenerate
2. Listen to the new golden files — verify they sound correct
3. Commit the updated goldens
4. Document why the golden changed in your commit message

### 5. Tolerance Configuration

```swift
// Default: tight — catches subtle regressions
AudioTolerances.default
  .durationTolerance = 0.05s
  .peakTolerance     = 0.005
  .rmsTolerance      = 0.005

// Relaxed: for tests with non-deterministic plugins
AudioTolerances.relaxed
  .durationTolerance = 0.2s
  .peakTolerance     = 0.02
  .rmsTolerance      = 0.02
```

---

## How to Debug Failures Locally

### UI Test Failures

1. **Read the screenshot**: Failed tests capture a screenshot. Find it in the `.xcresult` bundle.

2. **Open the result bundle**:
   ```bash
   open TestResults/UITests.xcresult
   ```

3. **Run the failing test in Xcode**: Set a breakpoint in the test, click the diamond next to the test method.

4. **Check accessibility IDs**: Open Accessibility Inspector (Xcode → Open Developer Tool → Accessibility Inspector) and hover over the element.

5. **Record a screen capture**: Add `captureScreenshot(name: "debug")` at suspicious points.

### Audio Regression Failures

1. **Check the comparison summary** in the test output:
   ```
   Duration: PASS (delta: 0.001s)
   Peak: FAIL (delta: 0.150)
   RMS: PASS (delta: 0.002)
   ```

2. **Listen to both files**: The test attaches `rendered-*.wav` and `golden-*.wav` as artifacts.

3. **Diff in a DAW**: Import both files into any DAW, invert one, and listen for residual.

4. **Check recent changes**: `git log --oneline -20` — look for changes to AudioEngine, export, automation, or routing.

### Stress Test Failures

1. **Check for crash logs**:
   ```bash
   ls ~/Library/Logs/DiagnosticReports/Stori*
   ```

2. **Enable Thread Sanitizer**: In Xcode, edit the scheme → Test → Diagnostics → Thread Sanitizer.

3. **Enable Address Sanitizer**: Same location, enable ASAN for memory bugs.

4. **Run with Instruments**: Profile with "Time Profiler" or "Allocations" to find deadlocks.

---

## Accessibility Identifier Reference

### Transport Controls
| ID | Element |
|----|---------|
| `transport_play` | Play/Pause button |
| `transport_stop` | Stop button |
| `transport_record` | Record button |
| `transport_beginning` | Go to beginning |
| `transport_rewind` | Rewind |
| `transport_forward` | Fast forward |
| `transport_end` | Go to end |
| `transport_cycle` | Cycle toggle |
| `transport_catch_playhead` | Catch playhead toggle |

### Panel Toggles
| ID | Element |
|----|---------|
| `toggle_mixer` | Mixer panel toggle |
| `toggle_synthesizer` | Synthesizer panel toggle |
| `toggle_piano_roll` | Piano Roll toggle |
| `toggle_step_sequencer` | Step Sequencer toggle |
| `toggle_selection` | Selection Info toggle |

### Mixer (Dynamic per Track)
| Pattern | Element |
|---------|---------|
| `mixer.track.<uuid>.volume` | Track volume fader |
| `mixer.track.<uuid>.pan` | Track pan knob |
| `mixer.track.<uuid>.mute` | Track mute button |
| `mixer.track.<uuid>.solo` | Track solo button |
| `mixer.track.<uuid>.record_arm` | Track record arm |
| `mixer.track.<uuid>.strip` | Channel strip container |
| `mixer.container` | Mixer view container |

### Track Management
| ID | Element |
|----|---------|
| `track.create_dialog` | Create Track dialog |
| `track.create_dialog.type.audio` | Audio track type card |
| `track.create_dialog.type.midi` | MIDI track type card |
| `track.create_dialog.confirm` | Create button |
| `track.create_dialog.cancel` | Cancel button |

### Export
| ID | Element |
|----|---------|
| `export.dialog` | Export settings dialog |
| `export.dialog.confirm` | Export button |
| `export.dialog.cancel` | Cancel button |

All identifiers are centralized in `Stori/Core/Utilities/AccessibilityIdentifiers.swift`.

---

## macOS Runner Notes for CI

### GitHub-Hosted Runners
- macOS 15 runners are available (`macos-15`)
- No physical audio device — headless rendering works via `AVAudioEngine` in offline mode
- Screen capture works for XCUITest but resolution may differ from local
- Xcode version may lag; specify `DEVELOPER_DIR` explicitly

### Self-Hosted Mac Mini (Recommended)
- Full audio device access for real-time tests
- Consistent hardware for performance benchmarks
- Faster builds (no cold cache)
- Set up: install the GitHub Actions runner, pin Xcode version

### Artifact Collection
- `.xcresult` bundles contain screenshots, logs, and coverage data
- WAV files from audio regression are attached as test artifacts
- Crash logs are collected from `~/Library/Logs/DiagnosticReports/`
- All artifacts have retention policies (7-30 days depending on type)
