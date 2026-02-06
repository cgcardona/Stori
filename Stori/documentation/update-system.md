# Stori Update System

Developer documentation for the auto-update subsystem.

## Architecture Overview

The update system checks GitHub Releases for new versions, notifies users with an escalating urgency indicator, and provides a guided download-and-install flow.

### Files

```
Stori/Core/Services/Update/
  SemanticVersion.swift   - Version parsing & comparison (SemVer 2.0)
  UpdateModels.swift      - GitHub API types, UpdateState, DownloadProgress, UpdateUrgency, UpdateError
  UpdateStore.swift       - Persistent storage (UserDefaults): ETags, snooze, ignored versions, first-seen dates
  UpdateService.swift     - Core service: GitHub API, state machine, download lifecycle

Stori/Features/Setup/
  UpdateIndicatorView.swift  - Compact toolbar badge (green/yellow/red dot)
  UpdateBannerView.swift     - Non-blocking top banner (first detection)
  UpdateSheetView.swift      - Full details sheet (release notes, progress, install guide)
```

### State Machine

```
.idle  -->  .checking  -->  .upToDate
                        -->  .aheadOfRelease
                        -->  .updateAvailable(ReleaseInfo)  -->  .downloading(DownloadProgress)  -->  .downloaded(fileURL, release)
                        -->  .error(UpdateError)
```

## How Update Checks Work

1. **On app launch**: After a 10-second delay, the service checks the GitHub API if enough time has passed since the last check (12 hours by default).
2. **Periodic**: While the app is running, checks repeat every 12 hours.
3. **Manual**: User clicks "Check for Updates..." in the Stori menu (Cmd+Shift+U).

### GitHub API Usage

- **Endpoint**: `GET https://api.github.com/repos/cgcardona/Stori/releases/latest`
- **ETag caching**: Sends `If-None-Match` header; on `304 Not Modified`, uses cached response data.
- **Rate limiting**: On `429` or `403`, backs off exponentially (1h, 2h, 4h, ..., max 24h).
- **User-Agent**: `Stori/<version>` header is sent per GitHub guidelines.

### Version Comparison

Uses proper semantic versioning (not lexicographic string comparison):
- `0.2.10 > 0.2.3` (numeric comparison)
- `1.0.0-beta.1 < 1.0.0` (prerelease < release)
- `1.0.0-alpha < 1.0.0-beta` (alphabetical prerelease comparison)

### Prerelease Handling

By default, prerelease versions (tagged with `prerelease: true` on GitHub) are **ignored**. Users can opt in via `UpdateStore.betaOptIn`. The setting is stored in UserDefaults.

## Escalation (Urgency Colors)

Based on **days since the update was first detected** (persisted across launches):

| Days | Urgency | Indicator Color | Badge Label |
|------|---------|-----------------|-------------|
| 0-3  | Low     | Green           | "New"       |
| 4-10 | Medium  | Orange/Yellow   | "Recommended" |
| 11+  | High    | Red             | "Important" |

## User Actions

| Action | Effect |
|--------|--------|
| **Download** | Downloads the DMG/ZIP from GitHub to ~/Downloads |
| **Not Now** | Snoozes notifications for 3 days; banner hidden, indicator remains |
| **Skip This Version** | Permanently ignores this specific version; future versions still shown |
| **Release Notes** | Opens the full update sheet with rendered release notes |
| **Dismiss (X)** | Hides the banner; indicator remains; won't show banner again for this version |

## Download & Install Flow

1. User clicks "Download" - asset is downloaded from GitHub with progress tracking.
2. Download completes -> file saved to `~/Downloads/Stori-v{version}.dmg`.
3. Security validations:
   - Download URL must be on `github.com`, `*.github.com`, or `*.githubusercontent.com`.
   - File must be at least 1 MB (reject suspiciously small downloads).
   - Version strings are sanitized for filename safety (no path traversal).
4. User sees install instructions:
   - Quit Stori
   - Open the DMG
   - Drag Stori into Applications (replace existing)
   - Relaunch Stori
5. User data is **never** affected -- projects live in `~/Library/Application Support/Stori/`, preferences in `~/Library/Preferences/`.

## Configuring Intervals

In `UpdateService.swift`:

```swift
private static let checkInterval: TimeInterval = 12 * 3600   // 12 hours
private static let launchDelay: TimeInterval = 10             // 10 seconds after launch
static let snoozeDays = 3                                     // Snooze duration
```

## Release Engineering

### How to Tag a Release

1. Create a GitHub Release with a tag like `v0.2.3`
2. Attach assets:
   - **Preferred**: `Stori-v0.2.3.dmg` (DMG is selected first)
   - **Fallback**: `Stori-v0.2.3.zip` (ZIP used if no DMG found)
3. Write release notes in the GitHub release body (displayed as-is in the app)
4. Mark as prerelease if it's a beta/RC (these are hidden from users by default)

### Asset Naming Convention

The updater selects assets in this priority order:
1. DMG files with name starting with "Stori" (e.g., `Stori-v0.2.3.dmg`)
2. Any other DMG file
3. ZIP files with name starting with "Stori"
4. Any other ZIP file

### Tag Format

- `v0.2.3` - standard release
- `v0.2.3-beta.1` - prerelease (mark as prerelease on GitHub)
- `v0.2.3-rc.1` - release candidate (mark as prerelease on GitHub)

## Testing

Run all update-system tests:
```bash
xcodebuild test -project Stori.xcodeproj -scheme Stori -destination 'platform=macOS' \
  -only-testing:StoriTests/SemanticVersionTests \
  -only-testing:StoriTests/UpdateStoreTests \
  -only-testing:StoriTests/UpdateServiceTests
```

Tests use `MockURLProtocol` for network isolation and separate `UserDefaults` suites for persistence isolation. No real network calls are made during testing.

## Future Enhancements

- **SHA256 verification**: The system is designed to support checksum validation. When ready, include a `sha256` field in the release or compute it server-side.
- **Sparkle migration**: If distribution needs grow beyond GitHub Releases, the service can be adapted to read Sparkle appcasts.
- **Auto-install**: macOS code signing and notarization constraints make automated app replacement complex. The current guided flow is the safest approach.
- **Delta updates**: For large app bundles, delta/patch updates could reduce download sizes.
