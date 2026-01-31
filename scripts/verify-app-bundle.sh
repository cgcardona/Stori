#!/bin/zsh
#
# Verify that an app bundle is properly structured before signing/distribution
# Catches missing Info.plist keys and bundle structure issues early
#

set -e

APP_PATH="${1}"

if [[ -z "$APP_PATH" ]]; then
    echo "Usage: $0 <path-to-app-bundle>"
    echo "Example: $0 build/Release/Stori.app"
    exit 1
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ ERROR: App bundle not found at: $APP_PATH"
    exit 1
fi

echo "════════════════════════════════════════════════════════════"
echo "🔍 App Bundle Verification"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "App: $APP_PATH"
echo ""

ERRORS=0
WARNINGS=0

# Check bundle structure
echo "1️⃣  Bundle Structure"
echo "────────────────────────────────────────────────────────────"

if [[ ! -d "$APP_PATH/Contents" ]]; then
    echo "❌ Missing Contents/ directory"
    ERRORS=$((ERRORS + 1))
else
    echo "✅ Contents/ directory present"
fi

if [[ ! -d "$APP_PATH/Contents/MacOS" ]]; then
    echo "❌ Missing Contents/MacOS/ directory"
    ERRORS=$((ERRORS + 1))
else
    echo "✅ Contents/MacOS/ directory present"
fi

if [[ ! -d "$APP_PATH/Contents/Resources" ]]; then
    echo "⚠️  Missing Contents/Resources/ directory (may be optional)"
    WARNINGS=$((WARNINGS + 1))
else
    echo "✅ Contents/Resources/ directory present"
fi

echo ""

# Check Info.plist
echo "2️⃣  Info.plist Required Keys"
echo "────────────────────────────────────────────────────────────"

INFO_PLIST="$APP_PATH/Contents/Info.plist"

if [[ ! -f "$INFO_PLIST" ]]; then
    echo "❌ CRITICAL: Info.plist not found at: $INFO_PLIST"
    ERRORS=$((ERRORS + 1))
else
    echo "✅ Info.plist exists"
    echo ""
    
    # Check required keys
    REQUIRED_KEYS=(
        "CFBundlePackageType"
        "CFBundleExecutable"
        "CFBundleIdentifier"
        "CFBundleName"
        "CFBundleShortVersionString"
    )
    
    for key in "${REQUIRED_KEYS[@]}"; do
        VALUE=$(/usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" 2>/dev/null)
        if [[ -z "$VALUE" ]]; then
            echo "❌ MISSING: $key"
            ERRORS=$((ERRORS + 1))
        else
            # Check for unexpanded build variables (using double brackets with proper escaping)
            if [[ "$VALUE" == *'$('* ]]; then
                echo "⚠️  UNEXPANDED: $key = $VALUE"
                WARNINGS=$((WARNINGS + 1))
            else
                echo "✅ $key = $VALUE"
            fi
        fi
    done
    
    # Check CFBundlePackageType is "APPL"
    PACKAGE_TYPE=$(/usr/libexec/PlistBuddy -c "Print :CFBundlePackageType" "$INFO_PLIST" 2>/dev/null)
    if [[ "$PACKAGE_TYPE" != "APPL" ]]; then
        echo "❌ CRITICAL: CFBundlePackageType must be 'APPL', got: '$PACKAGE_TYPE'"
        ERRORS=$((ERRORS + 1))
    fi
fi

echo ""

# Check executable
echo "3️⃣  Executable"
echo "────────────────────────────────────────────────────────────"

if [[ -f "$INFO_PLIST" ]]; then
    EXECUTABLE=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$INFO_PLIST" 2>/dev/null)
    
    if [[ -z "$EXECUTABLE" ]]; then
        echo "❌ CFBundleExecutable not set in Info.plist"
        ERRORS=$((ERRORS + 1))
    elif [[ "$EXECUTABLE" == *'$('* ]]; then
        echo "⚠️  CFBundleExecutable has unexpanded variable: $EXECUTABLE"
        WARNINGS=$((WARNINGS + 1))
    else
        EXEC_PATH="$APP_PATH/Contents/MacOS/$EXECUTABLE"
        if [[ ! -f "$EXEC_PATH" ]]; then
            echo "❌ Executable not found: $EXEC_PATH"
            ERRORS=$((ERRORS + 1))
        elif [[ ! -x "$EXEC_PATH" ]]; then
            echo "❌ Executable not executable: $EXEC_PATH"
            ERRORS=$((ERRORS + 1))
        else
            echo "✅ Executable exists and is executable: $EXECUTABLE"
            
            # Check architecture
            ARCH=$(file "$EXEC_PATH" | cut -d: -f2-)
            echo "   Architecture: $ARCH"
        fi
    fi
else
    echo "⚠️  Skipping (no Info.plist)"
fi

echo ""

# Summary
echo "════════════════════════════════════════════════════════════"
echo "🎯 Result"
echo "════════════════════════════════════════════════════════════"
echo ""

if [[ $ERRORS -eq 0 ]] && [[ $WARNINGS -eq 0 ]]; then
    echo "✅ PASS: App bundle is valid"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo "⚠️  PASS WITH WARNINGS: $WARNINGS warning(s)"
    echo ""
    echo "The app may work, but should be investigated"
    exit 0
else
    echo "❌ FAIL: $ERRORS error(s), $WARNINGS warning(s)"
    echo ""
    echo "DO NOT SIGN OR DISTRIBUTE THIS BUNDLE"
    echo "Fix the errors above first"
    exit 1
fi
