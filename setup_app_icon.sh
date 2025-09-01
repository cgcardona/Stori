#!/bin/bash

# TellUrStori V2 DAW - App Icon Setup Script
# This script generates all required macOS app icon sizes and installs them

set -e

echo "🎵 TellUrStori V2 DAW - App Icon Setup"
echo "======================================"

# Check if source icon exists
SOURCE_ICON="app_icon_source.png"
if [ ! -f "$SOURCE_ICON" ]; then
    echo "❌ Source icon not found: $SOURCE_ICON"
    echo "Please save your app icon image as 'app_icon_source.png' in this directory"
    exit 1
fi

# Check if Python and PIL are available
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is required but not installed"
    exit 1
fi

# Install Pillow if not available
echo "📦 Checking dependencies..."
python3 -c "import PIL" 2>/dev/null || {
    echo "Installing Pillow (PIL)..."
    pip3 install Pillow
}

# Generate app icons
echo "🎨 Generating app icon sizes..."
ICONS_DIR="TellUrStoriDAW/Assets.xcassets/AppIcon.appiconset"
python3 generate_app_icons.py "$SOURCE_ICON" -o "$ICONS_DIR"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ App icons generated successfully!"
    echo ""
    echo "📁 Icons saved to: $ICONS_DIR"
    echo ""
    echo "🔧 Next steps:"
    echo "1. Open TellUrStoriDAW.xcodeproj in Xcode"
    echo "2. Build and run to see the new app icon"
    echo "3. The icon should appear in the Dock and Finder"
    echo ""
    echo "🎉 Your beautiful app icon is now ready!"
else
    echo "❌ Failed to generate app icons"
    exit 1
fi
