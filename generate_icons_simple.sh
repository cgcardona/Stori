#!/bin/bash

# Simple icon generator using macOS built-in 'sips' command
# Compatible with default macOS shell

set -e

echo "🎵 TellUrStori V2 DAW - App Icon Generator"
echo "========================================"

SOURCE_ICON="app_icon_source.png"
ICONS_DIR="TellUrStoriDAW/Assets.xcassets/AppIcon.appiconset"

# Check if source icon exists
if [ ! -f "$SOURCE_ICON" ]; then
    echo "❌ Source icon not found: $SOURCE_ICON"
    exit 1
fi

# Create icons directory if it doesn't exist
mkdir -p "$ICONS_DIR"

echo "🎨 Generating app icon sizes using sips..."

# Generate all required sizes individually
echo "  Creating 16x16 icons..."
sips -z 16 16 "$SOURCE_ICON" --out "$ICONS_DIR/icon_16x16.png" > /dev/null 2>&1
echo "    ✓ icon_16x16.png"

echo "  Creating 32x32 icons..."
sips -z 32 32 "$SOURCE_ICON" --out "$ICONS_DIR/icon_16x16@2x.png" > /dev/null 2>&1
echo "    ✓ icon_16x16@2x.png"

sips -z 32 32 "$SOURCE_ICON" --out "$ICONS_DIR/icon_32x32.png" > /dev/null 2>&1
echo "    ✓ icon_32x32.png"

echo "  Creating 64x64 icons..."
sips -z 64 64 "$SOURCE_ICON" --out "$ICONS_DIR/icon_32x32@2x.png" > /dev/null 2>&1
echo "    ✓ icon_32x32@2x.png"

echo "  Creating 128x128 icons..."
sips -z 128 128 "$SOURCE_ICON" --out "$ICONS_DIR/icon_128x128.png" > /dev/null 2>&1
echo "    ✓ icon_128x128.png"

echo "  Creating 256x256 icons..."
sips -z 256 256 "$SOURCE_ICON" --out "$ICONS_DIR/icon_128x128@2x.png" > /dev/null 2>&1
echo "    ✓ icon_128x128@2x.png"

sips -z 256 256 "$SOURCE_ICON" --out "$ICONS_DIR/icon_256x256.png" > /dev/null 2>&1
echo "    ✓ icon_256x256.png"

echo "  Creating 512x512 icons..."
sips -z 512 512 "$SOURCE_ICON" --out "$ICONS_DIR/icon_256x256@2x.png" > /dev/null 2>&1
echo "    ✓ icon_256x256@2x.png"

sips -z 512 512 "$SOURCE_ICON" --out "$ICONS_DIR/icon_512x512.png" > /dev/null 2>&1
echo "    ✓ icon_512x512.png"

echo "  Creating 1024x1024 icons..."
sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONS_DIR/icon_512x512@2x.png" > /dev/null 2>&1
echo "    ✓ icon_512x512@2x.png"

echo ""
echo "✅ App icons generated successfully!"
echo ""
echo "📁 Icons saved to: $ICONS_DIR"
echo ""
echo "Generated files:"
echo "  - icon_16x16.png (16×16)"
echo "  - icon_16x16@2x.png (32×32)"
echo "  - icon_32x32.png (32×32)"
echo "  - icon_32x32@2x.png (64×64)"
echo "  - icon_128x128.png (128×128)"
echo "  - icon_128x128@2x.png (256×256)"
echo "  - icon_256x256.png (256×256)"
echo "  - icon_256x256@2x.png (512×512)"
echo "  - icon_512x512.png (512×512)"
echo "  - icon_512x512@2x.png (1024×1024)"
echo ""
echo "🔧 Next steps:"
echo "1. Open TellUrStoriDAW.xcodeproj in Xcode"
echo "2. Build and run to see the new app icon"
echo "3. The icon should appear in the Dock and Finder"
echo ""
echo "🎉 Your beautiful app icon is now ready!"
