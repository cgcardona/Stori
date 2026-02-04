#!/bin/zsh
# Clear downloaded GM SoundFont and drum kits so you can test download and "no assets" state.
# Stori stores these under ~/Library/Application Support/Stori/
# Run with Stori quit for a clean test.

set -e

SUPPORT="$HOME/Library/Application Support/Stori"
SOUNDFONTS="$SUPPORT/SoundFonts"
DRUMKITS="$SUPPORT/DrumKits"

echo "Stori downloaded assets (for testing)"
echo "===================================="
echo ""

if [[ ! -d "$SUPPORT" ]]; then
    echo "No Stori Application Support folder found. Nothing to clear."
    exit 0
fi

# SoundFonts (GM .sf2 file)
if [[ -d "$SOUNDFONTS" ]]; then
    echo "Removing: $SOUNDFONTS"
    rm -rf "$SOUNDFONTS"
    echo "  -> GM SoundFont(s) removed."
else
    echo "No SoundFonts folder (already clear)."
fi

# Drum kits
if [[ -d "$DRUMKITS" ]]; then
    echo "Removing: $DRUMKITS"
    rm -rf "$DRUMKITS"
    echo "  -> Drum kits removed."
else
    echo "No DrumKits folder (already clear)."
fi

echo ""
echo "Done. Quit Stori (if running), then relaunch to see the 'no SoundFont' / download UI."
