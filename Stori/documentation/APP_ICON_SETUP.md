# 🎵 Stori - App Icon Setup Guide

This guide will help you set up the beautiful app icon for Stori.

## 📋 Prerequisites

1. **Source Icon Image**: Save your app icon image as `app_icon_source.png` in this directory
2. **macOS Development Environment**: Xcode installed
3. **Optional**: Python 3 with Pillow (PIL) for advanced icon generation

## 🚀 Quick Setup

### Method 1: Automated Setup (Recommended)

1. **Save your icon image** as `app_icon_source.png` in this directory
2. **Run the setup script**:
   ```bash
   ./setup_app_icon.sh
   ```

This will automatically:
- Check dependencies
- Install Pillow if needed
- Generate all required icon sizes with proper rounded corners
- Place them in the correct Assets.xcassets location

### Method 2: Using macOS Built-in Tools

If you prefer not to install Python dependencies:

1. **Save your icon image** as `app_icon_source.png`
2. **Run the sips-based generator**:
   ```bash
   ./generate_icons_sips.sh
   ```

This uses macOS's built-in `sips` command to resize images.

### Method 3: Manual Setup via Xcode

1. **Open Xcode**: Open `Stori.xcodeproj`
2. **Navigate to Assets**: Go to `Stori` → `Assets.xcassets` → `AppIcon`
3. **Drag and Drop**: Drag your icon images into the appropriate size slots

## 📐 Required Icon Sizes

The app requires these macOS icon sizes:

| Size | Filename | Purpose |
|------|----------|---------|
| 16×16 | `icon_16x16.png` | Menu bar, small UI elements |
| 32×32 | `icon_16x16@2x.png` | Retina menu bar |
| 32×32 | `icon_32x32.png` | Finder sidebar |
| 64×64 | `icon_32x32@2x.png` | Retina Finder sidebar |
| 128×128 | `icon_128x128.png` | Finder list view |
| 256×256 | `icon_128x128@2x.png` | Retina Finder list view |
| 256×256 | `icon_256x256.png` | Finder icon view |
| 512×512 | `icon_256x256@2x.png` | Retina Finder icon view |
| 512×512 | `icon_512x512.png` | Dock, large icons |
| 1024×1024 | `icon_512x512@2x.png` | Retina Dock, App Store |

## 🎨 Icon Design Guidelines

Your icon beautifully follows Apple's design principles:

- ✅ **Rounded Corners**: Proper corner radius for macOS
- ✅ **Rich Colors**: Beautiful gradient from blue to purple to pink
- ✅ **Clear Symbolism**: Music notes, waveforms, AI/blockchain elements
- ✅ **Scalability**: Design works at all sizes
- ✅ **Modern Aesthetic**: Fits perfectly with macOS Big Sur+ design language

## 🔧 Verification

After setup, verify your icon is working:

1. **Build the app** in Xcode (`Cmd+B`)
2. **Run the app** (`Cmd+R`)
3. **Check the Dock**: Your icon should appear in the Dock
4. **Check Finder**: Navigate to the built app in Finder to see the icon

## 📁 File Structure

After setup, your Assets.xcassets should look like:

```
Stori/Assets.xcassets/AppIcon.appiconset/
├── Contents.json
├── icon_16x16.png
├── icon_16x16@2x.png
├── icon_32x32.png
├── icon_32x32@2x.png
├── icon_128x128.png
├── icon_128x128@2x.png
├── icon_256x256.png
├── icon_256x256@2x.png
├── icon_512x512.png
└── icon_512x512@2x.png
```

## 🐛 Troubleshooting

### Icon Not Appearing
- **Clean Build**: Product → Clean Build Folder in Xcode
- **Reset Dock**: `killall Dock` in Terminal
- **Check File Names**: Ensure exact filename matches in Contents.json

### Wrong Icon Size
- **Verify Dimensions**: Use `sips -g pixelWidth -g pixelHeight filename.png`
- **Regenerate**: Run the setup script again

### Python/PIL Issues
- **Install Pillow**: `pip3 install Pillow`
- **Use Alternative**: Try the sips-based generator instead

## 🎉 Success!

Once setup is complete, your Stori will have a beautiful, professional app icon that represents the innovative combination of:

- 🎵 **Music Creation** (notes and waveforms)
- 🤖 **AI Generation** (geometric patterns)
- ⛓️ **Blockchain Integration** (network elements)
- 🎨 **Modern Design** (gradient and clean aesthetics)

Your app icon perfectly captures the revolutionary nature of this AI-powered DAW with blockchain tokenization capabilities!

---

*Need help? Check the main project documentation or create an issue in the repository.*
