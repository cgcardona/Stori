#!/bin/bash

# Alternative icon generator using macOS built-in 'sips' command
# This is a fallback if Python/PIL is not available

set -e

echo "🎵 TellUrStori V2 DAW - App Icon Generator (sips)"
echo "==============================================="

SOURCE_ICON="app_icon_source.png"
ICONS_DIR="TellUrStoriDAW/Assets.xcassets/AppIcon.appiconset"

# Check if source icon exists
if [ ! -f "$SOURCE_ICON" ]; then
    echo "❌ Source icon not found: $SOURCE_ICON"
    echo "Please save your app icon image as 'app_icon_source.png' in this directory"
    exit 1
fi

# Create icons directory if it doesn't exist
mkdir -p "$ICONS_DIR"

echo "🎨 Generating app icon sizes using sips..."

# Generate all required sizes
declare -A sizes=(
    ["16"]="icon_16x16.png"
    ["32"]="icon_16x16@2x.png icon_32x32.png"
    ["64"]="icon_32x32@2x.png"
    ["128"]="icon_128x128.png"
    ["256"]="icon_128x128@2x.png icon_256x256.png"
    ["512"]="icon_256x256@2x.png icon_512x512.png"
    ["1024"]="icon_512x512@2x.png"
)

for size in "${!sizes[@]}"; do
    echo "  Creating ${size}x${size} icons..."
    
    # Create temporary resized image
    temp_file="temp_${size}.png"
    sips -z "$size" "$size" "$SOURCE_ICON" --out "$temp_file" > /dev/null 2>&1
    
    # Copy to all required filenames for this size
    for filename in ${sizes[$size]}; do
        cp "$temp_file" "$ICONS_DIR/$filename"
        echo "    ✓ $filename"
    done
    
    # Clean up temp file
    rm "$temp_file"
done

echo ""
echo "✅ App icons generated successfully using sips!"
echo ""
echo "📁 Icons saved to: $ICONS_DIR"
echo ""
echo "🔧 Next steps:"
echo "1. Open TellUrStoriDAW.xcodeproj in Xcode"
echo "2. Build and run to see the new app icon"
echo "3. The icon should appear in the Dock and Finder"
echo ""
echo "🎉 Your beautiful app icon is now ready!"
