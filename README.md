# 🎵 TellUrStori V2 - Digital Audio Workstation

*Professional DAW with AI Music Generation & NFT Tokenization*

[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-5.0-blue.svg)](https://developer.apple.com/swiftui/)
[![macOS](https://img.shields.io/badge/macOS-15.0+-black.svg)](https://developer.apple.com/macos/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

## 🎯 Project Overview

TellUrStori V2 is an innovative digital audio workstation that combines traditional DAW functionality with AI-powered music generation using Meta's AudioCraft MusicGen and blockchain-based STEM tokenization on a custom Avalanche L1.

### ✨ Key Features

- **🎛️ Professional DAW Interface**: Multi-track timeline, mixer, and transport controls
- **🤖 AI Music Generation**: Integrated Meta AudioCraft MusicGen for AI-powered composition
- **⛓️ NFT Tokenization**: Convert STEMs to tradeable NFTs on Avalanche L1
- **🏪 Marketplace**: Buy, sell, and trade music NFTs with built-in royalty system
- **🎨 Modern UI**: Native SwiftUI interface optimized for macOS

## 🚀 Current Status: Phase 1 Complete ✅

### ✅ Implemented Features

- **Core DAW Functionality**
  - Multi-track audio timeline with drag-and-drop regions
  - Professional mixer interface with channel strips
  - Transport controls (play/pause/stop/record)
  - Real-time audio engine using AVFoundation
  - Project creation and management
  - Audio region management with waveform visualization

- **Technical Architecture**
  - Organized modular structure (Core/, Features/, UI/)
  - MVVM pattern with ObservableObject
  - macOS-native implementation
  - Real-time audio processing foundation
  - Comprehensive data models

### 🔄 Current Limitations (Phase 1 MVP)

The current implementation focuses on **UI structure and architecture**. Interactive functionality will be implemented in subsequent phases:

- **Non-functional UI Elements**: Volume/pan sliders, mute/solo buttons, track creation
- **Audio Processing**: Playback, recording, and effects processing
- **File Operations**: Audio import/export, project save/load
- **Real-time Features**: Waveform display, level meters, transport sync

> **Note**: This is intentional for Phase 1 - we've built the foundation and UI structure. Phase 2 will wire up the interactive functionality.

## 🏗️ Architecture

### Project Structure
```
TellUrStoriDAW/
├── TellUrStoriDAW/
│   ├── Core/
│   │   ├── Audio/           # Audio engine and processing
│   │   ├── Models/          # Data models and business logic
│   │   └── Services/        # External service integrations
│   ├── Features/
│   │   ├── Timeline/        # Timeline and track management
│   │   ├── Mixer/          # Mixing console interface
│   │   └── Transport/       # Playback controls
│   └── UI/
│       ├── Views/          # Main interface views
│       └── Components/     # Reusable UI components
├── Tests/                   # Unit and integration tests
└── Resources/              # Assets and localizations
```

### Core Components

- **AudioEngine**: Real-time audio processing using AVAudioEngine
- **ProjectManager**: Project persistence and file management
- **MainDAWView**: Primary container combining timeline, mixer, transport
- **TimelineView**: Multi-track timeline with region management
- **MixerView**: Professional mixing console interface
- **TransportView**: Standard DAW transport controls

## 🛠️ Development Setup

### Prerequisites

- **Xcode 16.0+** with Swift 6.0
- **macOS 15.0+** (Sonoma or later)
- **Apple Developer Account** (for code signing)

### Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/TellUrStoriDAW.git
   cd TellUrStoriDAW
   ```

2. **Open in Xcode**
   ```bash
   open TellUrStoriDAW.xcodeproj
   ```

3. **Build and Run**
   - Select your target device/simulator
   - Press `Cmd+R` to build and run
   - The app should launch with the DAW interface

### Development Workflow

1. **Branch Strategy**: Use feature branches for development
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Code Style**: Follow Swift API Design Guidelines
   - Use meaningful, descriptive names
   - Leverage Swift's type system
   - Follow MVVM architecture patterns

3. **Testing**: Write tests for all business logic
   ```bash
   # Run tests in Xcode
   Cmd+U
   ```

## 📋 Roadmap

### 🎯 Phase 1: DAW MVP Foundation ✅ **COMPLETE**
- [x] Project architecture and setup
- [x] Core audio engine foundation
- [x] SwiftUI interface components
- [x] Timeline and track management UI
- [x] Mixer interface
- [x] Transport controls UI
- [x] Data models and persistence layer

### 🤖 Phase 2: Interactive Functionality (Next)
- [ ] Wire up audio playback and recording
- [ ] Implement mixer controls (volume, pan, mute, solo)
- [ ] Add track creation and management
- [ ] Audio file import/export
- [ ] Real-time waveform visualization
- [ ] Effects processing pipeline

### 🎵 Phase 3: MusicGen AI Integration
- [ ] Python MusicGen backend service
- [ ] Swift-Python communication layer
- [ ] AI generation interface
- [ ] Prompt template system
- [ ] Generated audio integration

### ⛓️ Phase 4: Blockchain Integration
- [ ] Avalanche L1 smart contracts
- [ ] STEM tokenization interface
- [ ] IPFS integration for metadata
- [ ] Web3 wallet integration

### 🏪 Phase 5: NFT Marketplace
- [ ] Marketplace interface
- [ ] Trading and auction system
- [ ] Portfolio management
- [ ] Analytics dashboard

## 🧪 Testing

### Running Tests
```bash
# Unit tests
xcodebuild test -scheme TellUrStoriDAW -destination 'platform=macOS'

# UI tests
xcodebuild test -scheme TellUrStoriDAWUITests -destination 'platform=macOS'
```

### Test Coverage Goals
- **Unit Tests**: 90%+ coverage for business logic
- **Integration Tests**: Critical user flows
- **Performance Tests**: Audio latency < 10ms
- **UI Tests**: Key user interactions

## 🔧 Configuration

### Audio Settings
- **Sample Rate**: 44.1kHz, 48kHz, 96kHz
- **Buffer Size**: 64, 128, 256, 512 samples
- **Latency Target**: < 10ms round-trip
- **CPU Usage**: < 30% on Apple Silicon

### Performance Requirements
- **Startup Time**: < 2 seconds
- **Memory Usage**: < 500MB for 8-track project
- **Export Speed**: Real-time or faster

## 🤝 Contributing

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md) for details.

### Development Process
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

### Code Review Checklist
- [ ] Code follows Swift style guidelines
- [ ] All tests pass
- [ ] Performance requirements met
- [ ] Documentation updated
- [ ] No hardcoded secrets

## 📚 Documentation

- **[Implementation Roadmap](TellUrStori-V2-Implementation-Roadmap.md)**: Detailed development plan
- **[Agent Onboarding](agent-onboarding.md)**: Developer setup guide
- **[Cursor Rules](.cursorrules)**: Development guidelines and standards
- **[API Documentation](docs/api/)**: Service APIs and interfaces
- **[Architecture Guide](docs/architecture.md)**: System design and patterns

## 🐛 Known Issues

### Phase 1 Limitations
- UI elements are not yet interactive (volume sliders, buttons)
- Audio playback not implemented
- File operations not functional
- Real-time features pending

### Planned Fixes
These will be addressed in Phase 2:
- Wire up all interactive controls
- Implement audio processing pipeline
- Add file import/export functionality
- Enable real-time audio features

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Meta AudioCraft**: AI music generation technology
- **Avalanche**: Blockchain infrastructure
- **Apple**: SwiftUI and Core Audio frameworks
- **Open Source Community**: Various dependencies and tools

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/TellUrStoriDAW/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/TellUrStoriDAW/discussions)
- **Email**: support@tellurstoridaw.com

---

**Built with ❤️ for musicians and creators**

*Transform your musical ideas into tradeable digital assets with the power of AI and blockchain technology.*
