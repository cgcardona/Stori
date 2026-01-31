# Stori

**Professional DAW for macOS, powered by AI.**

Create, record, mix, and produce music with 128 instruments, professional effects, and intuitive editing tools. AI-powered music generation coming soon.

![Stori DAW](https://tellurstori.com/assets/screenshots/hero-main-daw.png)

## Features

### Core DAW
- **Multi-track Timeline** — Arrange audio and MIDI with snap-to-grid, cycle regions, and waveform display
- **Professional Mixer** — Channel strips with volume, pan, 3-band EQ, and aux sends
- **8 Studio Effects** — Reverb, delay, chorus, compressor, EQ, distortion, filter, modulation (43 presets)
- **Audio Recording** — Record from any microphone or audio interface with <10ms latency

### MIDI & Instruments
- **128 GM Instruments** — Full General MIDI with SoundFont support
- **Piano Roll Editor** — Traditional grid view with velocity editing and 14 scale options
- **Score Editor** — Musical staff notation view
- **Step Sequencer** — 16-step drum machine with 300+ patterns across 27 categories
- **16-Voice Synthesizer** — Polyphonic synth with ADSR envelopes
- **Audio Unit Plugins** — Host third-party AU instruments and effects

### Accessibility
- VoiceOver support with proper labels
- Full keyboard navigation
- High contrast mode support
- Voice Control compatible

### Coming Soon
- AI music generation from text descriptions
- AI sound effects and ambient audio
- AI chat assistant for music theory
- Web3/NFT tokenization and marketplace

## Installation

### Option 1: Download DMG (Recommended)

1. Visit [tellurstori.com](https://tellurstori.com)
2. Download `Stori-0.1.2.dmg`
3. Open the DMG and drag Stori to Applications
4. Launch Stori from Applications or Spotlight
5. Click "Open" when prompted to confirm opening an app downloaded from the internet

### Option 2: Build from Source

**Requirements:**
- macOS 14+ (Sonoma)
- Xcode 15+
- 8GB RAM minimum

**Steps:**

```bash
# Clone the repository
git clone https://github.com/cgcardona/Stori.git
cd Stori

# Open in Xcode
open Stori.xcodeproj

# Build and run (⌘R)
```

The app will build and launch. First build takes 2-5 minutes.

### Creating a Release DMG

To create a signed and notarized DMG for distribution:

```bash
./scripts/build-release-dmg.sh
```

See [scripts/README.md](scripts/README.md) for detailed build instructions and prerequisites.

## System Requirements

| Requirement | Minimum |
|-------------|---------|
| macOS | 14.0 (Sonoma) |
| RAM | 8GB |
| Disk Space | 500MB |
| Audio | Built-in or external audio interface |

## Project Structure

```
Stori/
├── Core/
│   ├── Audio/          # Audio engine, transport, mixer, recording
│   ├── Models/         # Data models (tracks, regions, MIDI)
│   └── Services/       # Project management, undo, export
├── Features/
│   ├── Timeline/       # Main timeline view
│   ├── Mixer/          # Mixer and channel strips
│   ├── PianoRoll/      # MIDI editor
│   ├── StepSequencer/  # Drum machine
│   └── ...
├── UI/
│   ├── Components/     # Reusable UI elements
│   └── Views/          # Main views
└── Resources/          # SoundFonts, localizations
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License — see [LICENSE.md](LICENSE.md)

## Links

- **Website:** [tellurstori.com](https://tellurstori.com)
- **Documentation:** [tellurstori.com/docs.html](https://tellurstori.com/docs.html)
- **Twitter:** [@tellurstori](https://twitter.com/tellurstori)

---

**Built with ❤️ for musicians and creators**
