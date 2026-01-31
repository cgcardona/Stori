#!/bin/zsh
#
# Diagnose why Stori.app won't launch on a Mac
# Run this on the Mac where the app fails to open
#

set -e

APP_PATH="${1:-/Applications/Stori.app}"

echo "════════════════════════════════════════════════════════════"
echo "🔍 Stori App Launch Diagnostics"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "App path: $APP_PATH"
echo ""

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ ERROR: App not found at $APP_PATH"
    echo ""
    echo "Usage: $0 [path-to-Stori.app]"
    echo "Example: $0 /Applications/Stori.app"
    exit 1
fi

echo "1️⃣  Checking quarantine attributes..."
echo "────────────────────────────────────────────────────────────"
if xattr -l "$APP_PATH" | grep -q "com.apple.quarantine"; then
    echo "⚠️  App is quarantined (normal for downloads)"
    xattr -l "$APP_PATH" | grep quarantine
else
    echo "✅ No quarantine attribute"
fi
echo ""

echo "2️⃣  Checking Info.plist for required keys..."
echo "────────────────────────────────────────────────────────────"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
if [[ ! -f "$INFO_PLIST" ]]; then
    echo "❌ CRITICAL: Info.plist not found!"
else
    MISSING_KEYS=()
    
    # Check for required keys
    if ! /usr/libexec/PlistBuddy -c "Print :CFBundlePackageType" "$INFO_PLIST" &>/dev/null; then
        MISSING_KEYS+=("CFBundlePackageType")
    fi
    if ! /usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO_PLIST" &>/dev/null; then
        MISSING_KEYS+=("CFBundleExecutable")
    fi
    if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" &>/dev/null; then
        MISSING_KEYS+=("CFBundleIdentifier")
    fi
    if ! /usr/libexec/PlistBuddy -c "Print :CFBundleName" "$INFO_PLIST" &>/dev/null; then
        MISSING_KEYS+=("CFBundleName")
    fi
    
    if [[ ${#MISSING_KEYS[@]} -gt 0 ]]; then
        echo "❌ CRITICAL: Missing required Info.plist keys:"
        for key in "${MISSING_KEYS[@]}"; do
            echo "   - $key"
        done
        echo ""
        echo "   This is why Gatekeeper rejects it as 'not an app'"
    else
        echo "✅ All required Info.plist keys present"
        echo "   CFBundlePackageType: $(/usr/libexec/PlistBuddy -c "Print :CFBundlePackageType" "$INFO_PLIST")"
        echo "   CFBundleExecutable: $(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO_PLIST")"
        echo "   CFBundleIdentifier: $(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST")"
    fi
fi
echo ""

echo "3️⃣  Checking code signature..."
echo "────────────────────────────────────────────────────────────"
if codesign -dvvv --deep --strict "$APP_PATH" 2>&1; then
    echo "✅ Code signature valid"
else
    echo "❌ Code signature has issues"
fi
echo ""

echo "4️⃣  Checking Gatekeeper assessment..."
echo "────────────────────────────────────────────────────────────"
if spctl -a -vvv -t execute "$APP_PATH" 2>&1; then
    echo "✅ Gatekeeper accepted"
else
    echo "❌ Gatekeeper rejected"
fi
echo ""

echo "5️⃣  Checking notarization ticket..."
echo "────────────────────────────────────────────────────────────"
if stapler validate "$APP_PATH" 2>&1; then
    echo "✅ Notarization ticket present"
else
    echo "⚠️  No notarization ticket (needs stapling)"
fi
echo ""

echo "6️⃣  Checking architecture..."
echo "────────────────────────────────────────────────────────────"
file "$APP_PATH/Contents/MacOS/Stori"
echo ""

echo "7️⃣  Checking for unsigned nested code..."
echo "────────────────────────────────────────────────────────────"
UNSIGNED_COUNT=0
find "$APP_PATH/Contents" \( -name "*.framework" -o -name "*.dylib" -o -name "*.bundle" \) -print0 | while IFS= read -r -d '' nested; do
    if ! codesign -v "$nested" 2>/dev/null; then
        echo "❌ UNSIGNED: $nested"
        UNSIGNED_COUNT=$((UNSIGNED_COUNT + 1))
    fi
done

if [[ $UNSIGNED_COUNT -eq 0 ]]; then
    echo "✅ All nested code is signed"
else
    echo "⚠️  Found $UNSIGNED_COUNT unsigned components"
fi
echo ""

echo "8️⃣  Checking recent system logs (last 2 minutes)..."
echo "────────────────────────────────────────────────────────────"
echo "Searching for Gatekeeper, syspolicyd, or Stori errors..."
log show --predicate 'process == "Gatekeeper" OR process == "syspolicyd" OR processImagePath CONTAINS "Stori"' --last 2m --style compact 2>/dev/null | tail -20
echo ""

echo "════════════════════════════════════════════════════════════"
echo "🎯 Summary"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "If Gatekeeper says 'does not seem to be an app':"
echo "  → MISSING Info.plist keys (CFBundlePackageType, etc.)"
echo "  → Rebuild with fixed Info.plist"
echo ""
echo "If Gatekeeper rejected for other reasons:"
echo "  → Code signature issue; rebuild with proper signing"
echo ""
echo "If no notarization ticket:"
echo "  → Run: xcrun stapler staple \"$APP_PATH\""
echo ""
echo "If quarantined but signature valid:"
echo "  → Remove quarantine: xattr -cr \"$APP_PATH\""
echo "  → Then try opening again"
echo ""
echo "If errors in logs:"
echo "  → Check the log output above for specific reasons"
echo ""
