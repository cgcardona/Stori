#!/usr/bin/env python3
"""
App Icon Generator for TellUrStori V2 DAW
Generates all required macOS app icon sizes from a source image.
"""

import os
import sys
from PIL import Image, ImageDraw, ImageFilter
import argparse

def create_icon_with_rounded_corners(image, size, corner_radius_ratio=0.2):
    """Create an icon with rounded corners matching macOS style."""
    # Resize image to target size
    icon = image.resize((size, size), Image.Resampling.LANCZOS)
    
    # Create mask for rounded corners
    mask = Image.new('L', (size, size), 0)
    draw = ImageDraw.Draw(mask)
    
    # Calculate corner radius (typically 20% of size for macOS icons)
    corner_radius = int(size * corner_radius_ratio)
    
    # Draw rounded rectangle
    draw.rounded_rectangle(
        [(0, 0), (size, size)], 
        radius=corner_radius, 
        fill=255
    )
    
    # Apply mask to create rounded corners
    output = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    output.paste(icon, (0, 0))
    output.putalpha(mask)
    
    return output

def generate_app_icons(source_path, output_dir):
    """Generate all required macOS app icon sizes."""
    
    # Required sizes for macOS (from Contents.json)
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), 
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png")
    ]
    
    try:
        # Load source image
        print(f"Loading source image: {source_path}")
        source_image = Image.open(source_path)
        
        # Convert to RGBA if needed
        if source_image.mode != 'RGBA':
            source_image = source_image.convert('RGBA')
        
        # Create output directory if it doesn't exist
        os.makedirs(output_dir, exist_ok=True)
        
        print(f"Generating {len(sizes)} icon sizes...")
        
        for size, filename in sizes:
            print(f"  Creating {filename} ({size}x{size})")
            
            # Create icon with rounded corners
            icon = create_icon_with_rounded_corners(source_image, size)
            
            # Save icon
            output_path = os.path.join(output_dir, filename)
            icon.save(output_path, 'PNG', optimize=True)
            
        print(f"\n✅ Successfully generated all app icons in: {output_dir}")
        print("\nGenerated files:")
        for _, filename in sizes:
            print(f"  - {filename}")
            
        return True
        
    except Exception as e:
        print(f"❌ Error generating icons: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Generate macOS app icons from source image')
    parser.add_argument('source', help='Path to source icon image (PNG recommended)')
    parser.add_argument('-o', '--output', default='./app_icons', 
                       help='Output directory for generated icons (default: ./app_icons)')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.source):
        print(f"❌ Source image not found: {args.source}")
        sys.exit(1)
    
    success = generate_app_icons(args.source, args.output)
    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()
