#!/bin/zsh
# 🎵 Stori Release .dmg Builder
# Creates a signed and notarized .dmg for distribution
# Requires: Apple Developer Account ($99) with Developer ID certificate
#
# Usage: ./scripts/build-release-dmg.sh [--skip-notarize]
#
# Prerequisites (one-time setup):
#   1. Create App-Specific Password at https://appleid.apple.com
#   2. Store credentials: xcrun notarytool store-credentials "StoriNotarize" \
#        --apple-id "YOUR_EMAIL" --team-id "KS7G78R93R" --password "YOUR_APP_PASSWORD"

set -e  # Exit on any error

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                              CONFIGURATION                                 ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# Parse arguments
SKIP_NOTARIZE=false
for arg in "$@"; do
    case $arg in
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
    esac
done

# Paths
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# App configuration
APP_NAME="Stori"
XCODE_PROJECT="Stori.xcodeproj"
SCHEME="Stori"
TEAM_ID="KS7G78R93R"
NOTARIZE_PROFILE="StoriNotarize"

# Read version from Info.plist (single source of truth)
INFO_PLIST="$PROJECT_ROOT/Stori/Info.plist"
if [[ -f "$INFO_PLIST" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "")
    if [[ -z "$VERSION" ]]; then
        echo "❌ Error: Could not read CFBundleShortVersionString from Info.plist"
        exit 1
    fi
else
    echo "❌ Error: Info.plist not found at $INFO_PLIST"
    exit 1
fi

# Build paths
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED_DATA="$BUILD_DIR/DerivedData"
APP_BUILD_PATH="$DERIVED_DATA/Build/Products/Release/${APP_NAME}.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
STAGING_DIR="$PROJECT_ROOT/dmg-staging"

# Logging
LOG_DIR="$PROJECT_ROOT/build-logs"
mkdir -p "$LOG_DIR"
BUILD_TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
LOG_FILE="$LOG_DIR/build-${BUILD_TIMESTAMP}.log"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                              LOGGING                                       ║
# ╚════════════════════════════════════════════════════════════════════════════╝

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    case "$level" in
        "INFO")    echo -e "${BLUE}[$timestamp]${NC} ${CYAN}ℹ${NC} $message" ;;
        "SUCCESS") echo -e "${BLUE}[$timestamp]${NC} ${GREEN}✅${NC} $message" ;;
        "WARN")    echo -e "${BLUE}[$timestamp]${NC} ${YELLOW}⚠️${NC} $message" ;;
        "ERROR")   echo -e "${BLUE}[$timestamp]${NC} ${RED}❌${NC} $message" ;;
        "STEP")    echo -e "\n${BOLD}${GREEN}▶${NC} ${BOLD}$message${NC}" ;;
        *)         echo -e "$message" ;;
    esac
}

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                              BANNER                                        ║
# ╚════════════════════════════════════════════════════════════════════════════╝

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}       ${BOLD}🎵 Stori Release DMG Builder${NC}                           ${BLUE}║${NC}"
echo -e "${BLUE}╠════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${BLUE}║${NC} Version:    ${YELLOW}${VERSION}${NC}"
echo -e "${BLUE}║${NC} Output:     ${YELLOW}${DMG_NAME}${NC}"
echo -e "${BLUE}║${NC} Signing:    ${GREEN}Developer ID (Team: ${TEAM_ID})${NC}"
if [[ "$SKIP_NOTARIZE" == "true" ]]; then
echo -e "${BLUE}║${NC} Notarize:   ${YELLOW}Skipped (use --skip-notarize to skip)${NC}"
else
echo -e "${BLUE}║${NC} Notarize:   ${GREEN}Yes (Apple Notarization)${NC}"
fi
echo -e "${BLUE}║${NC} Log:        ${CYAN}build-logs/build-${BUILD_TIMESTAMP}.log${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Initialize log
echo "" > "$LOG_FILE"
log "INFO" "Build started at $(date)"
log "INFO" "Version: $VERSION"
log "INFO" "Project: $PROJECT_ROOT"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           STEP 1: PREREQUISITES                            ║
# ╚════════════════════════════════════════════════════════════════════════════╝

log "STEP" "Step 1: Checking prerequisites"

cd "$PROJECT_ROOT"

# Check Xcode project exists
if [[ ! -d "$XCODE_PROJECT" ]]; then
    log "ERROR" "Xcode project not found: $XCODE_PROJECT"
    exit 1
fi
log "SUCCESS" "Xcode project found: $XCODE_PROJECT"

# Check for Developer ID certificate
SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk -F'"' '{print $2}')
if [[ -z "$SIGNING_IDENTITY" ]]; then
    log "ERROR" "Developer ID Application certificate not found"
    log "INFO" "Please install your Developer ID certificate from developer.apple.com"
    exit 1
fi
log "SUCCESS" "Signing identity: $SIGNING_IDENTITY"

# Check for notarization credentials (unless skipped)
if [[ "$SKIP_NOTARIZE" == "false" ]]; then
    if ! xcrun notarytool history --keychain-profile "$NOTARIZE_PROFILE" &>/dev/null; then
        log "ERROR" "Notarization credentials not found for profile: $NOTARIZE_PROFILE"
        log "INFO" "Run: xcrun notarytool store-credentials \"$NOTARIZE_PROFILE\" --apple-id \"YOUR_EMAIL\" --team-id \"$TEAM_ID\" --password \"APP_SPECIFIC_PASSWORD\""
        log "INFO" "Or use --skip-notarize to skip notarization"
        exit 1
    fi
    log "SUCCESS" "Notarization credentials found"
fi

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           STEP 2: CLEAN BUILD                              ║
# ╚════════════════════════════════════════════════════════════════════════════╝

log "STEP" "Step 2: Cleaning previous builds"

rm -rf "$BUILD_DIR"
rm -rf "$STAGING_DIR"
rm -f "$PROJECT_ROOT/$DMG_NAME"

log "SUCCESS" "Previous builds cleaned"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           STEP 3: BUILD                                    ║
# ╚════════════════════════════════════════════════════════════════════════════╝

log "STEP" "Step 3: Building app (this may take a few minutes)"

BUILD_START=$(date +%s)

# Build with automatic signing first (uses development cert)
# We'll re-sign with Developer ID after
set +e  # Don't exit on error yet, we need to check build status
# Do not override PRODUCT_NAME/EXECUTABLE_NAME — project already sets them; overriding
# can trigger Xcode "Multiple commands produce" / RegisterExecutionPolicyException.
xcodebuild build \
    -project "$XCODE_PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    PRODUCT_BUNDLE_IDENTIFIER="com.tellurstori.stori" \
    MACOSX_DEPLOYMENT_TARGET="14.0" \
    2>&1 | tee -a "$LOG_FILE" | grep -E '(Build Succeeded|BUILD SUCCEEDED|error:|BUILD FAILED)'

BUILD_EXIT_CODE=${PIPESTATUS[0]}

BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))

if [[ $BUILD_EXIT_CODE -ne 0 ]]; then
    log "ERROR" "Build failed with exit code: $BUILD_EXIT_CODE"
    log "ERROR" "Check the log file for details: $LOG_FILE"
    log "INFO" "Common fixes:"
    log "INFO" "  1. Clean DerivedData: rm -rf build/DerivedData"
    log "INFO" "  2. Clean Xcode: xcodebuild clean -project \"$XCODE_PROJECT\" -scheme \"$SCHEME\""
    set -e  # Re-enable exit on error before exiting
    exit 1
fi

set -e  # Re-enable exit on error after successful build

if [[ ! -d "$APP_BUILD_PATH" ]]; then
    log "ERROR" "Build succeeded but app not found at: $APP_BUILD_PATH"
    log "INFO" "Checking what was built..."
    find "$DERIVED_DATA" -name "*.app" -type d 2>/dev/null | head -5 | while read -r app; do
        log "DEBUG" "Found: $app"
    done
    exit 1
fi

log "SUCCESS" "Build completed in ${BUILD_DURATION}s"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                     STEP 3.5: VERIFY APP BUNDLE                            ║
# ╚════════════════════════════════════════════════════════════════════════════╝

log "STEP" "Step 3.5: Verifying app bundle structure"

set +e  # Don't exit on error yet
"$PROJECT_ROOT/scripts/verify-app-bundle.sh" "$APP_BUILD_PATH" 2>&1 | tee -a "$LOG_FILE"
VERIFY_EXIT_CODE=${PIPESTATUS[0]}
set -e  # Re-enable exit on error

if [[ $VERIFY_EXIT_CODE -ne 0 ]]; then
    log "ERROR" "App bundle verification failed"
    log "INFO" "The app has structural issues that will cause Gatekeeper to reject it"
    log "INFO" "Check the verification output above for details"
    exit 1
fi

log "SUCCESS" "App bundle verification passed"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           STEP 4: SIGN APP                                 ║
# ╚════════════════════════════════════════════════════════════════════════════╝

log "STEP" "Step 4: Signing app with Developer ID"

APP_PATH="$APP_BUILD_PATH"

# Re-sign with Developer ID to ensure proper distribution signing
log "INFO" "Signing with: $SIGNING_IDENTITY"

# Sign all nested code first (inside-out: frameworks, helpers, plugins, then main bundle)
# IMPORTANT: Do NOT use --deep on the main bundle; sign each component explicitly

# 1. Sign all frameworks
if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
    find "$APP_PATH/Contents/Frameworks" -depth -name "*.framework" -print0 | while IFS= read -r -d '' framework; do
        log "INFO" "Signing framework: $(basename "$framework")"
        codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$framework" 2>&1 | tee -a "$LOG_FILE"
    done
fi

# 2. Sign all dylibs
if [[ -d "$APP_PATH/Contents/Frameworks" ]]; then
    find "$APP_PATH/Contents/Frameworks" -name "*.dylib" -print0 | while IFS= read -r -d '' dylib; do
        log "INFO" "Signing dylib: $(basename "$dylib")"
        codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$dylib" 2>&1 | tee -a "$LOG_FILE"
    done
fi

# 3. Sign any helper tools or plugins
if [[ -d "$APP_PATH/Contents/PlugIns" ]]; then
    find "$APP_PATH/Contents/PlugIns" -depth -type d -print0 | while IFS= read -r -d '' plugin; do
        log "INFO" "Signing plugin: $(basename "$plugin")"
        codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp "$plugin" 2>&1 | tee -a "$LOG_FILE"
    done
fi

# 4. Sign the main app bundle LAST (without --deep)
log "INFO" "Signing main bundle: Stori.app"
codesign --force --sign "$SIGNING_IDENTITY" --options runtime --timestamp --entitlements "$PROJECT_ROOT/Stori/Stori.entitlements" "$APP_PATH" 2>&1 | tee -a "$LOG_FILE"

log "SUCCESS" "App signed with Developer ID"

# Verify code signature
log "INFO" "Verifying code signature..."
if codesign -vvv --deep --strict "$APP_PATH" 2>&1 | tee -a "$LOG_FILE"; then
    log "SUCCESS" "Code signature verified"
else
    log "WARN" "Code signature verification had warnings - see log"
fi

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           STEP 5: CREATE DMG                               ║
# ╚════════════════════════════════════════════════════════════════════════════╝

log "STEP" "Step 5: Creating DMG"

mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/"

# Note: Applications symlink is created by create-dmg automatically via --app-drop-link
# If using hdiutil fallback, we'll create it there

# Create README (Version/Built lines padded to 58 chars so right border aligns)
VERSION_LINE=$(printf "%-58s" "         Version: ${VERSION}")
BUILT_LINE=$(printf "%-58s" "         Built: ${BUILD_TIMESTAMP}")
cat > "$STAGING_DIR/README.txt" << README_EOF
╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║     ███████╗████████╗ ██████╗ ██████╗ ██╗                      ║
║     ██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗██║                      ║
║     ███████╗   ██║   ██║   ██║██████╔╝██║                      ║
║     ╚════██║   ██║   ██║   ██║██╔══██╗██║                      ║
║     ███████║   ██║   ╚██████╔╝██║  ██║██║                      ║
║     ╚══════╝   ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚═╝                      ║
║                                                                ║
║            Digital Audio Workstation                           ║
║                                                                ║
║${VERSION_LINE}║
║${BUILT_LINE}║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

INSTALLATION
════════════════════════════════════════════════════════════════

Simply drag Stori.app to the Applications folder →

That's it! The app is signed and notarized, so macOS will
allow it to run without any security warnings.

════════════════════════════════════════════════════════════════

FEATURES
────────
✅ Multi-track timeline with audio and MIDI
✅ Professional mixer with channel strips
✅ 128 MIDI instruments (General MIDI)
✅ Piano roll and step sequencer
✅ Score editor with notation
✅ Audio Unit plugin support
✅ Virtual keyboard
✅ Automation lanes

════════════════════════════════════════════════════════════════

REQUIREMENTS
────────────
• macOS 14.0 (Sonoma) or later
• Apple Silicon or Intel Mac

════════════════════════════════════════════════════════════════

SUPPORT
───────
For help and feedback, visit: https://stori.audio

Built with ❤️ for musicians and creators
README_EOF

# Create DMG
DMG_PATH="$PROJECT_ROOT/$DMG_NAME"

if command -v create-dmg &>/dev/null; then
    log "INFO" "Using create-dmg for professional layout"
    
    create-dmg \
        --volname "${APP_NAME}" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 100 \
        --icon "${APP_NAME}.app" 180 190 \
        --icon "Applications" 480 190 \
        --hide-extension "${APP_NAME}.app" \
        --app-drop-link 480 190 \
        --no-internet-enable \
        "$DMG_PATH" \
        "$STAGING_DIR" 2>&1 | tee -a "$LOG_FILE" || {
            log "WARN" "create-dmg failed, falling back to hdiutil"
            # For hdiutil, we need to create Applications symlink manually
            ln -sf /Applications "$STAGING_DIR/Applications"
            hdiutil create -volname "${APP_NAME}" \
                -srcfolder "$STAGING_DIR" \
                -ov -format UDZO \
                "$DMG_PATH" 2>&1 | tee -a "$LOG_FILE"
        }
else
    log "INFO" "Using hdiutil (install create-dmg for prettier layout: brew install create-dmg)"
    
    # For hdiutil, we need to create Applications symlink manually
    ln -sf /Applications "$STAGING_DIR/Applications"
    
    hdiutil create -volname "${APP_NAME}" \
        -srcfolder "$STAGING_DIR" \
        -ov -format UDZO \
        "$DMG_PATH" 2>&1 | tee -a "$LOG_FILE"
fi

if [[ ! -f "$DMG_PATH" ]]; then
    log "ERROR" "DMG creation failed"
    exit 1
fi

log "SUCCESS" "DMG created: $DMG_NAME"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           STEP 6: SIGN DMG                                 ║
# ╚════════════════════════════════════════════════════════════════════════════╝

log "STEP" "Step 6: Signing DMG"

codesign --force --sign "$SIGNING_IDENTITY" "$DMG_PATH" 2>&1 | tee -a "$LOG_FILE"

log "SUCCESS" "DMG signed"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           STEP 7: NOTARIZE                                 ║
# ╚════════════════════════════════════════════════════════════════════════════╝

if [[ "$SKIP_NOTARIZE" == "true" ]]; then
    log "WARN" "Skipping notarization (--skip-notarize flag used)"
else
    log "STEP" "Step 7: Notarizing with Apple (this may take several minutes)"
    
    NOTARIZE_START=$(date +%s)
    
    # Submit for notarization
    log "INFO" "Submitting to Apple notarization service..."
    
    NOTARIZE_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARIZE_PROFILE" \
        --wait 2>&1 | tee -a "$LOG_FILE")
    
    NOTARIZE_END=$(date +%s)
    NOTARIZE_DURATION=$((NOTARIZE_END - NOTARIZE_START))
    
    if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
        log "SUCCESS" "Notarization accepted (${NOTARIZE_DURATION}s)"
        
        # Staple the ticket
        log "INFO" "Stapling notarization ticket..."
        xcrun stapler staple "$DMG_PATH" 2>&1 | tee -a "$LOG_FILE"
        log "SUCCESS" "Notarization ticket stapled"
    else
        log "ERROR" "Notarization failed - check log for details"
        echo "$NOTARIZE_OUTPUT"
        exit 1
    fi
fi

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           STEP 8: CLEANUP                                  ║
# ╚════════════════════════════════════════════════════════════════════════════╝

log "STEP" "Step 8: Cleanup"

rm -rf "$STAGING_DIR"
rm -rf "$BUILD_DIR"

log "SUCCESS" "Temporary files cleaned up"

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                           STEP 9: VERIFICATION                             ║
# ╚════════════════════════════════════════════════════════════════════════════╝

log "STEP" "Step 9: Final verification"

# Get DMG info
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
DMG_SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)

# Verify notarization
if [[ "$SKIP_NOTARIZE" == "false" ]]; then
    log "INFO" "Verifying notarization status..."
    if spctl -a -t open --context context:primary-signature -v "$DMG_PATH" 2>&1 | grep -q "accepted"; then
        log "SUCCESS" "Gatekeeper verification passed"
    else
        log "WARN" "Gatekeeper verification may have issues - see log"
    fi
fi

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║                              SUMMARY                                       ║
# ╚════════════════════════════════════════════════════════════════════════════╝

TOTAL_END=$(date +%s)
TOTAL_DURATION=$((TOTAL_END - BUILD_START))

echo ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC}                    ${BOLD}✅ BUILD SUCCESSFUL!${NC}                        ${GREEN}║${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC} 📦 DMG:       ${YELLOW}${DMG_NAME}${NC}"
echo -e "${GREEN}║${NC} 💾 Size:      ${YELLOW}${DMG_SIZE}${NC}"
echo -e "${GREEN}║${NC} ⏱️  Duration:  ${YELLOW}${TOTAL_DURATION} seconds${NC}"
echo -e "${GREEN}║${NC} 📝 Log:       ${CYAN}${LOG_FILE}${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║${NC} ${BOLD}SHA256:${NC}"
echo -e "${GREEN}║${NC}   ${CYAN}${DMG_SHA256}${NC}"
echo -e "${GREEN}╠════════════════════════════════════════════════════════════════╣${NC}"
if [[ "$SKIP_NOTARIZE" == "true" ]]; then
echo -e "${GREEN}║${NC} ${YELLOW}⚠️  Not notarized - users may see Gatekeeper warnings${NC}"
else
echo -e "${GREEN}║${NC} ${GREEN}✅ Signed & Notarized - ready for distribution!${NC}"
fi
echo -e "${GREEN}║${NC}"
echo -e "${GREEN}║${NC} ${BOLD}Next Steps:${NC}"
echo -e "${GREEN}║${NC}   1. Upload ${DMG_NAME} to cloud storage"
echo -e "${GREEN}║${NC}   2. Share link with beta testers"
echo -e "${GREEN}║${NC}   3. Testers just drag to Applications - done!"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

log "INFO" "Build completed at $(date)"
log "INFO" "DMG: $DMG_PATH"
log "INFO" "SHA256: $DMG_SHA256"

echo -e "${GREEN}🎵 Happy distributing!${NC}"
