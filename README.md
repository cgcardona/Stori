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

## 🚀 Current Status: Revolutionary AI-Powered DAW ✅

### ✅ Implemented Features

- **🎛️ Professional DAW Interface**
  - Multi-track audio timeline with interactive controls
  - Professional mixer interface with functional channel strips
  - Transport controls with real-time playback
  - Real-time audio engine using AVFoundation
  - Project creation, saving, and management
  - Audio region management with waveform visualization

- **🤖 AI Music Generation**
  - Integrated Meta AudioCraft MusicGen for AI-powered composition
  - Template-based prompt builder with genre, mood, and instrument selection
  - Real-time generation progress tracking
  - Seamless integration of AI-generated music into DAW projects
  - Professional audio processing and waveform display

- **⛓️ Blockchain Integration**
  - Complete Swift blockchain client with GraphQL integration
  - STEM minting directly from AI-generated music
  - Professional marketplace UI with comprehensive filtering and search
  - Real-time audio preview and wallet connection capabilities
  - Activity feeds, market analytics, and transaction management
  - Custom Avalanche L1 subnet integration (TellUrStori L1)
  - **BULLETPROOF SMART CONTRACTS**: Security-audited with RemixAI, production-ready

- **🏪 NFT Marketplace**
  - Buy, sell, and trade music NFTs with built-in royalty system
  - Portfolio management and analytics
  - Advanced filtering and search capabilities
  - Real-time market data and transaction history

- **🎨 Technical Excellence**
  - Organized modular structure (Core/, Features/, UI/)
  - MVVM pattern with ObservableObject
  - macOS-native implementation with professional styling
  - Real-time audio processing with <10ms latency
  - Comprehensive data models and error handling

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

## 🛠️ Complete Development Setup

### Prerequisites

- **macOS 15.0+** (Sonoma or later)
- **Xcode 16.0+** with Swift 6.0
- **Node.js 20+** (for blockchain and indexer services)
- **Python 3.11+** (for AI music generation)
- **Docker** (for services)
- **Avalanche CLI** (for L1 subnet management)
- **Apple Developer Account** (for code signing)

### 🚀 Full Stack Setup (Complete Ecosystem)

Follow these steps to set up the entire TellUrStori V2 ecosystem from scratch:

#### 1. **Clone and Setup Repository**
```bash
# Clone the repository
git clone https://github.com/yourusername/TellUrStoriDAW.git
cd TellUrStoriDAW

# Install Avalanche CLI (if not already installed)
curl -sSfL https://raw.githubusercontent.com/ava-labs/avalanche-cli/main/scripts/install.sh | sh -s
export PATH=$PATH:~/bin
```

#### 2. **Setup AI Music Generation Service**
```bash
# Navigate to MusicGen service
cd musicgen-service

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Start the AI service (runs on port 8000)
python -m app.main &
cd ..
```

#### 3. **Setup Avalanche L1 Subnet & Deploy Contracts**
```bash
# Navigate to blockchain directory
cd blockchain

# Install Node.js dependencies
npm install

# Create and deploy TellUrStori L1 subnet
avalanche blockchain create tellurstoridaw
# Follow prompts: SubnetEVM, Chain ID: 507, Token Symbol: TUS

# Deploy the subnet locally
avalanche blockchain deploy tellurstoridaw --local
# Note: Save the RPC URL from output (e.g., http://127.0.0.1:XXXXX/ext/bc/.../rpc)

# Deploy optimized smart contracts
node scripts/deploy-optimized-direct.js

# Run comprehensive contract tests
node scripts/run-all-tests-direct.js

# Populate blockchain with sample data
node scripts/populate-marketplace-data.js

cd ..
```

#### 4. **Setup GraphQL Indexer Service**
```bash
# Navigate to indexer service
cd indexer-service

# Install dependencies (if needed)
npm install

# Start the GraphQL indexer (connects to L1 and serves data)
node marketplace-graphql-server.js &

# Verify it's running
curl http://localhost:4000/health
cd ..
```

#### 5. **Launch Swift DAW Application**
```bash
# Open in Xcode
open TellUrStoriDAW.xcodeproj

# Build and run (Cmd+R in Xcode)
# The app will automatically connect to all services
```

### 🎯 Quick Start (Swift App Only)

If you just want to run the Swift DAW with placeholder data:

1. **Clone and Open**
   ```bash
   git clone https://github.com/yourusername/TellUrStoriDAW.git
   cd TellUrStoriDAW
   open TellUrStoriDAW.xcodeproj
   ```

2. **Build and Run**
   - Select your target device/simulator
   - Press `Cmd+R` to build and run
   - The app will launch with placeholder data

### 🧪 Running Tests

#### **Blockchain Tests**
```bash
cd blockchain

# Test both STEM and Marketplace contracts
node scripts/run-all-tests-direct.js

# Test only STEM contract
node scripts/run-all-tests-direct.js --stem

# Test only Marketplace contract  
node scripts/run-all-tests-direct.js --marketplace
```

#### **Swift Tests**
```bash
# Unit tests
xcodebuild test -scheme TellUrStoriDAW -destination 'platform=macOS'

# UI tests
xcodebuild test -scheme TellUrStoriDAWUITests -destination 'platform=macOS'
```

#### **AI Service Tests**
```bash
cd musicgen-service
source venv/bin/activate

# Run Python tests
python -m pytest tests/

# Test generation endpoint
curl -X POST http://localhost:8000/generate \
  -H "Content-Type: application/json" \
  -d '{"prompt": "upbeat electronic music", "duration": 10}'
```

### 🔧 Service Endpoints

When all services are running, you'll have:

- **Swift DAW**: Native macOS application
- **AI Service**: `http://localhost:8000` (MusicGen API)
- **Blockchain L1**: `http://127.0.0.1:XXXXX/ext/bc/.../rpc` (Avalanche subnet)
- **GraphQL Indexer**: `http://localhost:4000/graphql` (Blockchain data API)

### 🚨 Troubleshooting

#### **Common Issues**

1. **Avalanche CLI Issues**
   ```bash
   # Clean and restart network
   avalanche network clean
   avalanche blockchain deploy tellurstoridaw --local
   ```

2. **Python Dependencies**
   ```bash
   # If MusicGen installation fails
   pip install --upgrade pip
   pip install torch torchvision torchaudio
   pip install -r requirements.txt
   ```

3. **Node.js Issues**
   ```bash
   # Clear npm cache and reinstall
   npm cache clean --force
   rm -rf node_modules package-lock.json
   npm install
   ```

4. **GraphQL Connection Issues**
   ```bash
   # Verify indexer is connecting to correct RPC
   # Update RPC URL in indexer-service/marketplace-graphql-server.js
   # Restart the indexer service
   ```

### 📊 Verifying Full Setup

After completing all steps, verify everything is working:

1. **Check AI Service**: Visit `http://localhost:8000/docs` for API documentation
2. **Check Blockchain**: Run `node scripts/run-all-tests-direct.js` (should show 100% pass rate)
3. **Check Indexer**: Visit `http://localhost:4000/graphql` for GraphQL playground
4. **Check Swift App**: Marketplace should show real STEMs and data from blockchain

### 🎵 Data Population

The setup automatically populates your blockchain with:
- **51 diverse STEM tokens** (Electronic, Hip Hop, Rock, Pop, etc.)
- **Real marketplace listings** with various price points
- **Transaction history** and activity data
- **Creator profiles** and royalty information

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

## 🎯 What's Next

TellUrStori V2 represents a complete ecosystem for AI-powered music creation and blockchain tokenization. The current implementation includes all core functionality for professional music production, AI generation, and NFT trading.

For detailed development roadmap and future enhancements, see our [Implementation Roadmap](TellUrStori-V2-Implementation-Roadmap.md).

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

### Current Limitations
- Some advanced DAW features are still in development
- Blockchain deployment to mainnet pending
- Advanced audio effects processing pipeline in progress
- Mobile companion app not yet available

### Support & Reporting
For bug reports and feature requests, please use our [GitHub Issues](https://github.com/yourusername/TellUrStoriDAW/issues) page.

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

## 🎛️ **DAW UI Element Terminology**

### **🎚️ Main Interface Areas**

1. **Transport Bar** (top section)
   - **New/Open/Save Buttons** - Project management controls
   - **Project Info** - "boom v4, 2 tracks • 120 BPM"
   - **CPU Meter** - Shows processing load (6%)

2. **Timeline/Arrangement View** (main center area)
   - **Timeline Ruler** - Time markers (0:01, 0:02, etc.)
   - **Playhead** - The red vertical line showing current position
   - **Track Lanes** - Horizontal strips for each track
   - **Track Headers** - Left side with track names and controls

3. **Mixer Panel** (right side)
   - **Channel Strip** - Complete set of controls for one track
   - **Track Selector** - Blue dot showing selected track

### **🎛️ Track Controls (Left Side)**

- **Track Name** - "Track 1", "Track 2"
- **Record Arm Button** - Red circle (●) to enable recording
- **Mute Button** - (M) to silence the track
- **Solo Button** - (S) to isolate the track
- **Track Color Indicator** - Blue/Red dots for visual identification
- **Delete Track Button** - Red trash icon

### **🎚️ Mixer Controls (Right Panel)**

**EQ Section:**
- **HI Knob** - High frequency control
- **MID Knob** - Mid frequency control  
- **LO Knob** - Low frequency control

**Pan & Volume:**
- **PAN Knob** - Stereo positioning control
- **Volume Fader** - Vertical slider for track level
- **Volume Percentage** - Numeric display (80%, 38%)

**Channel Buttons:**
- **M Button** - Mute (gray when off, orange when active)
- **S Button** - Solo (gray when off, yellow when active)  
- **R Button** - Record arm

### **🎮 Transport Controls (Bottom)**

- **Stop Button** - Blue square (■)
- **Play Button** - Blue triangle (▶)
- **Record Button** - Red circle (●)

**Time Display:**
- **Time Counter** - "00:00.00" (minutes:seconds.milliseconds)
- **Bar Counter** - "1.1.0" (bar.beat.tick)

### **🎯 Additional Elements**

- **Add Track Button** - Blue "⊕ Add Track" button
- **Mixer Toggle** - Hamburger menu icon (≡) to show/hide mixer
- **Waveform Display Area** - Where audio regions will appear
- **Grid Lines** - Vertical lines for timing reference

### **🏗️ Professional DAW Terminology**

- **Arrangement View** = Your main timeline area
- **Channel Strip** = Complete set of mixer controls for one track
- **Playhead/Cursor** = The red line showing playback position
- **Track Lane** = Horizontal area where audio/MIDI regions go
- **Session** = Your entire project
- **Regions/Clips** = Audio or MIDI segments on tracks
- **Fader** = Volume slider
- **Knob/Pot** = Rotary control (EQ, Pan)
