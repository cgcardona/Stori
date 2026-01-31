# 🎵 Stori Build Scripts

Build automation scripts for creating distributable installers.

---

## 📦 Build Script

### `build-release-dmg.sh`

Creates a **signed and notarized** .dmg installer for distribution. Requires Apple Developer Account ($99/year).

**Benefits:**
- ✅ No Gatekeeper warnings on any Mac
- ✅ Professional drag-to-install experience
- ✅ Apple-verified and trusted
- ✅ Proper bundle structure validation before signing
- ✅ Nested code signing for frameworks and plugins
- ✅ Hardened Runtime support for Audio Units

**Prerequisites (one-time setup):**

1. **Developer ID Certificate**: Download from developer.apple.com → Certificates
2. **App-Specific Password**: Create at https://appleid.apple.com → Security → App-Specific Passwords
3. **Store credentials** (run once):
   ```bash
   xcrun notarytool store-credentials "StoriNotarize" \
     --apple-id "your@email.com" \
     --team-id "yourTeamID" \
     --password "xxxx-xxxx-xxxx-xxxx"
   ```

**Usage:**

**For production (signed + notarized):**
```bash
./scripts/build-release-dmg.sh
```

**For quick testing (signed only, no notarization):**
```bash
./scripts/build-release-dmg.sh --skip-notarize
```

**Output:** `Stori-{VERSION}.dmg` (signed & notarized)

---

## 🔍 Diagnostic Scripts

### `diagnose-app-launch.sh`

Diagnose why Stori.app won't launch on a Mac. Run this on the target Mac where the app fails to open.

**Usage:**
```bash
./diagnose-app-launch.sh /Applications/Stori.app
```

**Checks:**
- Quarantine attributes
- Code signature validity
- Gatekeeper assessment
- Notarization ticket
- Info.plist required keys
- Architecture compatibility
- System logs for errors

### `verify-app-bundle.sh`

Verify that an app bundle is properly structured **before** signing and distribution. Catches missing Info.plist keys and bundle structure issues early.

**Usage:**
```bash
./verify-app-bundle.sh build/Release/Stori.app
```

**Validates:**
- Bundle directory structure
- Info.plist required keys (CFBundlePackageType, CFBundleExecutable, etc.)
- Executable presence and permissions
- Unexpanded build variables

This script is automatically run by `build-release-dmg.sh` before signing.

---

## 📋 What's in the .dmg?

```
Stori-0.1.2-beta.1.dmg/
├── Stori.app          # Main application (signed & notarized)
├── Applications →     # Symlink for drag-to-install
└── README.txt         # User instructions
```

---

## 🔧 Troubleshooting

### "Developer ID Application certificate not found"
Install your Developer ID certificate from developer.apple.com → Certificates, Identifiers & Profiles

### "Notarization credentials not found"
Run the `xcrun notarytool store-credentials` command from prerequisites

### "Notarization failed"
- Check the log file for details
- Ensure your bundle ID matches your provisioning profile
- Verify your app-specific password is correct

### Build takes too long
First build after a clean takes ~2-5 minutes. Subsequent builds are faster.

---

**Built with ❤️ for musicians and creators**
