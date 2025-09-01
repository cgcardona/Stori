# 🎵 TellUrStori V2 Implementation Roadmap
*Digital Audio Workstation with AI Music Generation & NFT Tokenization*

## 🎯 Project Overview

TellUrStori V2 is an innovative digital audio workstation that combines traditional DAW functionality with AI-powered music generation using Meta's AudioCraft MusicGen and blockchain-based STEM tokenization on a custom Avalanche L1. The application features a modern Swift/SwiftUI frontend with Python backend services for AI generation and comprehensive blockchain integration for NFT creation and trading.

### Core Technology Stack
- **Frontend**: Swift 6 + SwiftUI (macOS/iOS)
- **AI Backend**: Python + Meta AudioCraft MusicGen
- **Blockchain**: Custom Avalanche L1 + Hardhat + OpenZeppelin
- **Audio Processing**: AVFoundation + Core Audio + Metal Performance Shaders
- **Communication**: WebSocket/REST APIs + gRPC for real-time audio streaming

---

## 📋 Phase 1: DAW MVP Foundation

### 1.1 Project Architecture & Setup

#### Swift Package Structure
```
TellUrStoriDAW/
├── TellUrStoriDAW.xcodeproj
├── Sources/
│   ├── TellUrStoriDAW/
│   │   ├── App/
│   │   │   ├── TellUrStoriDAWApp.swift
│   │   │   └── ContentView.swift
│   │   ├── Core/
│   │   │   ├── Audio/
│   │   │   ├── Models/
│   │   │   ├── Services/
│   │   │   └── Utilities/
│   │   ├── Features/
│   │   │   ├── Timeline/
│   │   │   ├── Mixer/
│   │   │   ├── TrackEditor/
│   │   │   └── Transport/
│   │   └── UI/
│   │       ├── Components/
│   │       ├── Views/
│   │       └── Styles/
│   └── TellUrStoriDAWTests/
├── Package.swift
└── README.md
```

#### Required Dependencies (Package.swift)
```swift
dependencies: [
    .package(url: "https://github.com/AudioKit/AudioKit", from: "5.6.0"),
    .package(url: "https://github.com/AudioKit/SoundpipeAudioKit", from: "5.6.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.0.0"),
    .package(url: "https://github.com/realm/realm-swift", from: "10.45.0"),
    .package(url: "https://github.com/stephencelis/SQLite.swift", from: "0.14.1")
]
```

### 1.2 Core Audio Engine Architecture

#### Audio Engine Components
- **AudioEngine**: Core audio processing engine using AVAudioEngine
- **AudioTrack**: Individual track management with effects chain
- **AudioRegion**: Audio clip representation with timing and properties
- **MixerChannel**: Per-track mixing controls (volume, pan, mute, solo)
- **TransportController**: Playback, recording, and timeline control
- **AudioRenderer**: Real-time audio rendering and visualization

#### Key Models
```swift
// Core audio models needed
struct AudioProject {
    let id: UUID
    var name: String
    var tracks: [AudioTrack]
    var tempo: Double
    var timeSignature: TimeSignature
    var sampleRate: Double
    var bufferSize: Int
}

struct AudioTrack {
    let id: UUID
    var name: String
    var regions: [AudioRegion]
    var mixerSettings: MixerSettings
    var effects: [AudioEffect]
    var isMuted: Bool
    var isSolo: Bool
}

struct AudioRegion {
    let id: UUID
    var audioFile: AudioFile
    var startTime: TimeInterval
    var duration: TimeInterval
    var fadeIn: TimeInterval
    var fadeOut: TimeInterval
    var gain: Float
    var isLooped: Bool
}
```

### 1.3 SwiftUI Interface Components

#### Main Interface Views
- **MainDAWView**: Primary container with timeline, mixer, and transport
- **TimelineView**: Horizontal scrolling timeline with track lanes
- **TrackLaneView**: Individual track representation with regions
- **MixerView**: Vertical mixer panel with channel strips
- **TransportView**: Play/pause/record/stop controls with position indicator
- **InspectorView**: Properties panel for selected regions/tracks

#### Interactive Components
- **AudioRegionView**: Draggable, resizable audio clip representation
- **WaveformView**: Real-time waveform visualization using Metal
- **MixerChannelView**: Fader, knobs, and buttons for mixing
- **TimeRulerView**: Timeline ruler with beat/bar markers
- **TrackHeaderView**: Track name, record/mute/solo buttons

#### Drag & Drop Implementation
```swift
// Drag and drop functionality for audio regions
struct AudioRegionView: View {
    @State private var dragOffset = CGSize.zero
    @State private var isDragging = false
    
    var body: some View {
        // Region visualization with drag gesture
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.blue.opacity(0.7))
            .overlay(WaveformView(audioFile: region.audioFile))
            .offset(dragOffset)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                        isDragging = true
                    }
                    .onEnded { value in
                        // Handle drop logic
                        handleRegionDrop(offset: value.translation)
                        dragOffset = .zero
                        isDragging = false
                    }
            )
    }
}
```

### 1.4 Audio Processing Pipeline

#### Real-time Audio Processing
- **BufferManager**: Circular buffer management for low-latency audio
- **AudioMixer**: Multi-track mixing with real-time effects processing
- **EffectsProcessor**: Plugin-style effects chain (EQ, compression, reverb)
- **MetronomeEngine**: Click track generation with customizable sounds
- **RecordingEngine**: Multi-track recording with punch-in/out

#### Performance Optimization
- **Background Processing**: Core Audio callbacks on real-time thread
- **Memory Pool**: Pre-allocated audio buffers to avoid allocation during playback
- **SIMD Operations**: Vectorized audio processing using Accelerate framework
- **Metal Shaders**: GPU-accelerated waveform rendering and effects

### 1.5 Data Persistence

#### Core Data Schema
```swift
// Core Data entities for project persistence
@Model
class ProjectEntity {
    var id: UUID
    var name: String
    var createdDate: Date
    var modifiedDate: Date
    var tempo: Double
    var tracks: [TrackEntity]
}

@Model
class TrackEntity {
    var id: UUID
    var name: String
    var colorHex: String
    var regions: [RegionEntity]
    var mixerSettings: Data // Encoded MixerSettings
}

@Model
class RegionEntity {
    var id: UUID
    var audioFileURL: URL
    var startTime: TimeInterval
    var duration: TimeInterval
    var properties: Data // Encoded region properties
}
```

### 1.6 Testing Strategy

#### Unit Tests
- Audio engine component testing
- Model validation and persistence
- Mathematical calculations (time conversion, sample rate conversion)
- Effects processing accuracy

#### Integration Tests
- Audio pipeline end-to-end testing
- UI interaction testing with XCUITest
- Performance benchmarking with XCTMetric
- Memory leak detection with Instruments

#### Performance Requirements
- **Latency**: < 10ms round-trip audio latency
- **CPU Usage**: < 30% on Apple Silicon M1/M2
- **Memory**: < 500MB for typical 8-track project
- **Startup Time**: < 2 seconds to ready state

---

## 🤖 Phase 2: MusicGen Python Backend

### 2.1 Python Backend Architecture

#### Service Structure
```
musicgen-service/
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── api/
│   │   ├── __init__.py
│   │   ├── routes/
│   │   │   ├── generation.py
│   │   │   └── health.py
│   │   └── models/
│   │       ├── requests.py
│   │       └── responses.py
│   ├── core/
│   │   ├── __init__.py
│   │   ├── musicgen_engine.py
│   │   ├── audio_processor.py
│   │   └── prompt_builder.py
│   ├── services/
│   │   ├── __init__.py
│   │   ├── generation_service.py
│   │   └── file_service.py
│   └── utils/
│       ├── __init__.py
│       ├── audio_utils.py
│       └── validation.py
├── requirements.txt
├── Dockerfile
├── docker-compose.yml
└── README.md
```

#### Core Dependencies (requirements.txt)
```txt
audiocraft==1.3.0
torch>=2.0.0
torchaudio>=2.0.0
fastapi==0.104.1
uvicorn[standard]==0.24.0
pydantic==2.5.0
numpy==1.24.3
librosa==0.10.1
soundfile==0.12.1
redis==5.0.1
celery==5.3.4
python-multipart==0.0.6
aiofiles==23.2.1
```

### 2.2 MusicGen Integration

#### MusicGen Engine Wrapper
```python
from audiocraft.models import MusicGen
from audiocraft.data.audio import audio_write
import torch

class MusicGenEngine:
    def __init__(self, model_size: str = "medium"):
        self.model = MusicGen.get_pretrained(f"facebook/musicgen-{model_size}")
        self.sample_rate = self.model.sample_rate
        
    async def generate_music(
        self,
        prompt: str,
        duration: float = 30.0,
        temperature: float = 1.0,
        top_k: int = 250,
        top_p: float = 0.0
    ) -> tuple[torch.Tensor, int]:
        """Generate music from text prompt"""
        self.model.set_generation_params(
            duration=duration,
            temperature=temperature,
            top_k=top_k,
            top_p=top_p
        )
        
        with torch.no_grad():
            wav = self.model.generate([prompt])
            
        return wav[0], self.sample_rate
```

#### Prompt Template Builder
```python
class PromptBuilder:
    GENRES = [
        "rock", "pop", "jazz", "classical", "electronic", "hip-hop",
        "country", "blues", "reggae", "folk", "metal", "punk"
    ]
    
    TEMPOS = [
        "slow", "medium", "fast", "very slow", "very fast",
        "60 BPM", "120 BPM", "140 BPM", "180 BPM"
    ]
    
    MOODS = [
        "happy", "sad", "energetic", "calm", "mysterious",
        "uplifting", "dark", "romantic", "aggressive", "peaceful"
    ]
    
    ARTISTS = [
        "in the style of The Beatles", "like Mozart", "similar to Daft Punk",
        "in the style of Miles Davis", "like Beethoven", "similar to Radiohead"
    ]
    
    def build_prompt(
        self,
        genre: str = None,
        tempo: str = None,
        mood: str = None,
        artist_style: str = None,
        instruments: list[str] = None,
        custom_text: str = None
    ) -> str:
        """Build structured prompt from components"""
        parts = []
        
        if custom_text:
            parts.append(custom_text)
        
        if genre and genre in self.GENRES:
            parts.append(f"{genre} music")
            
        if tempo and tempo in self.TEMPOS:
            parts.append(f"at {tempo} tempo")
            
        if mood and mood in self.MOODS:
            parts.append(f"with {mood} mood")
            
        if instruments:
            instrument_list = ", ".join(instruments)
            parts.append(f"featuring {instrument_list}")
            
        if artist_style and artist_style in self.ARTISTS:
            parts.append(artist_style)
            
        return ", ".join(parts)
```

### 2.3 FastAPI Service Implementation

#### Generation API Endpoints
```python
from fastapi import FastAPI, HTTPException, BackgroundTasks
from pydantic import BaseModel
import uuid
import asyncio

app = FastAPI(title="TellUrStori MusicGen Service")

class GenerationRequest(BaseModel):
    prompt: str
    duration: float = 30.0
    temperature: float = 1.0
    top_k: int = 250
    top_p: float = 0.0

class GenerationResponse(BaseModel):
    job_id: str
    status: str
    message: str

@app.post("/generate", response_model=GenerationResponse)
async def generate_music(
    request: GenerationRequest,
    background_tasks: BackgroundTasks
):
    """Start music generation job"""
    job_id = str(uuid.uuid4())
    
    background_tasks.add_task(
        process_generation,
        job_id,
        request.prompt,
        request.duration,
        request.temperature,
        request.top_k,
        request.top_p
    )
    
    return GenerationResponse(
        job_id=job_id,
        status="processing",
        message="Generation started"
    )

@app.get("/status/{job_id}")
async def get_generation_status(job_id: str):
    """Check generation job status"""
    # Implementation for job status checking
    pass

@app.get("/download/{job_id}")
async def download_generated_audio(job_id: str):
    """Download generated audio file"""
    # Implementation for file download
    pass
```

### 2.4 Swift-Python Communication

#### WebSocket Integration
```swift
// Swift WebSocket client for real-time communication
import Foundation
import Network

class MusicGenClient: ObservableObject {
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var generationProgress: Double = 0.0
    
    private var webSocketTask: URLSessionWebSocketTask?
    
    func connect() {
        let url = URL(string: "ws://localhost:8000/ws")!
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
        
        receiveMessage()
    }
    
    func generateMusic(prompt: String, duration: Double) async throws -> URL {
        let request = GenerationRequest(
            prompt: prompt,
            duration: duration
        )
        
        // Send generation request and handle response
        return try await sendGenerationRequest(request)
    }
}
```

#### Audio File Handling
```swift
// Audio file processing for generated content
import AVFoundation

class GeneratedAudioProcessor {
    func processGeneratedAudio(from url: URL) async throws -> AudioFile {
        let asset = AVAsset(url: url)
        
        // Convert to project sample rate if needed
        let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        )
        
        // Process and return AudioFile object
        return try await convertToAudioFile(exportSession)
    }
}
```

### 2.5 Caching and Performance

#### Redis Caching Strategy
- Cache generated audio files by prompt hash
- Store generation parameters and metadata
- Implement LRU eviction for storage management
- Cache prompt templates and user preferences

#### Async Processing
- Celery task queue for long-running generations
- Progress tracking with WebSocket updates
- Batch processing for multiple generations
- GPU memory management for model inference

---

## ⛓️ Phase 3: Avalanche L1 Blockchain Backend

### 3.1 Avalanche L1 Infrastructure

#### Blockchain Architecture
```
avalanche-l1/
├── contracts/
│   ├── TellUrStoriSTEM.sol
│   ├── STEMMarketplace.sol
│   ├── RoyaltyManager.sol
│   └── AccessControl.sol
├── scripts/
│   ├── deploy.js
│   ├── mint.js
│   └── setup.js
├── test/
│   ├── STEM.test.js
│   ├── Marketplace.test.js
│   └── Integration.test.js
├── hardhat.config.js
├── package.json
└── README.md
```

#### Smart Contract Dependencies (package.json)
```json
{
  "dependencies": {
    "@openzeppelin/contracts": "^5.0.0",
    "@openzeppelin/contracts-upgradeable": "^5.0.0",
    "hardhat": "^2.19.0",
    "@nomicfoundation/hardhat-toolbox": "^4.0.0",
    "@avalabs/avalanche-cli": "^1.5.0"
  }
}
```

### 3.2 STEM NFT Smart Contracts

#### ERC-1155 STEM Token Contract
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract TellUrStoriSTEM is ERC1155, Ownable, ERC1155Supply {
    using Strings for uint256;
    
    struct STEMMetadata {
        string name;
        string description;
        string audioIPFSHash;
        string imageIPFSHash;
        address creator;
        uint256 createdAt;
        uint256 duration; // in seconds
        string genre;
        string[] tags;
        uint256 royaltyPercentage; // basis points (100 = 1%)
    }
    
    mapping(uint256 => STEMMetadata) public stemMetadata;
    mapping(address => uint256[]) public creatorSTEMs;
    
    uint256 private _currentTokenId = 1;
    
    event STEMMinted(
        uint256 indexed tokenId,
        address indexed creator,
        string name,
        string audioIPFSHash
    );
    
    constructor() ERC1155("https://api.tellurstoridaw.com/metadata/{id}.json") {}
    
    function mintSTEM(
        address to,
        uint256 amount,
        STEMMetadata memory metadata,
        bytes memory data
    ) public returns (uint256) {
        uint256 tokenId = _currentTokenId++;
        
        stemMetadata[tokenId] = metadata;
        creatorSTEMs[metadata.creator].push(tokenId);
        
        _mint(to, tokenId, amount, data);
        
        emit STEMMinted(tokenId, metadata.creator, metadata.name, metadata.audioIPFSHash);
        
        return tokenId;
    }
    
    function getSTEMsByCreator(address creator) external view returns (uint256[] memory) {
        return creatorSTEMs[creator];
    }
    
    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(
            "https://api.tellurstoridaw.com/metadata/",
            tokenId.toString(),
            ".json"
        ));
    }
}
```

#### Marketplace Contract
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract STEMMarketplace is ReentrancyGuard, Ownable {
    struct Listing {
        uint256 tokenId;
        address seller;
        uint256 amount;
        uint256 pricePerToken;
        bool active;
        uint256 listedAt;
    }
    
    struct Offer {
        uint256 listingId;
        address buyer;
        uint256 amount;
        uint256 pricePerToken;
        uint256 expiresAt;
        bool active;
    }
    
    IERC1155 public stemContract;
    
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Offer[]) public offers;
    mapping(address => uint256[]) public userListings;
    
    uint256 private _currentListingId = 1;
    uint256 public marketplaceFee = 250; // 2.5%
    
    event Listed(uint256 indexed listingId, uint256 indexed tokenId, address seller, uint256 amount, uint256 price);
    event Sold(uint256 indexed listingId, address buyer, uint256 amount, uint256 totalPrice);
    event OfferMade(uint256 indexed listingId, address buyer, uint256 amount, uint256 price);
    
    constructor(address _stemContract) {
        stemContract = IERC1155(_stemContract);
    }
    
    function createListing(
        uint256 tokenId,
        uint256 amount,
        uint256 pricePerToken
    ) external {
        require(stemContract.balanceOf(msg.sender, tokenId) >= amount, "Insufficient balance");
        require(stemContract.isApprovedForAll(msg.sender, address(this)), "Not approved");
        
        uint256 listingId = _currentListingId++;
        
        listings[listingId] = Listing({
            tokenId: tokenId,
            seller: msg.sender,
            amount: amount,
            pricePerToken: pricePerToken,
            active: true,
            listedAt: block.timestamp
        });
        
        userListings[msg.sender].push(listingId);
        
        emit Listed(listingId, tokenId, msg.sender, amount, pricePerToken);
    }
    
    function buyListing(uint256 listingId, uint256 amount) external payable nonReentrant {
        Listing storage listing = listings[listingId];
        require(listing.active, "Listing not active");
        require(amount <= listing.amount, "Insufficient amount available");
        
        uint256 totalPrice = amount * listing.pricePerToken;
        require(msg.value >= totalPrice, "Insufficient payment");
        
        // Calculate fees and royalties
        uint256 fee = (totalPrice * marketplaceFee) / 10000;
        uint256 sellerAmount = totalPrice - fee;
        
        // Transfer tokens
        stemContract.safeTransferFrom(listing.seller, msg.sender, listing.tokenId, amount, "");
        
        // Transfer payments
        payable(listing.seller).transfer(sellerAmount);
        
        // Update listing
        listing.amount -= amount;
        if (listing.amount == 0) {
            listing.active = false;
        }
        
        emit Sold(listingId, msg.sender, amount, totalPrice);
    }
}
```

### 3.3 Backend Indexer Service

#### Node.js Indexer Architecture
```
indexer-service/
├── src/
│   ├── index.js
│   ├── blockchain/
│   │   ├── client.js
│   │   ├── eventListener.js
│   │   └── contractABI.js
│   ├── database/
│   │   ├── models/
│   │   ├── migrations/
│   │   └── connection.js
│   ├── api/
│   │   ├── routes/
│   │   ├── controllers/
│   │   └── middleware/
│   └── services/
│       ├── indexingService.js
│       ├── metadataService.js
│       └── ipfsService.js
├── package.json
├── docker-compose.yml
└── README.md
```

#### Event Indexing Service
```javascript
const { ethers } = require('ethers');
const { STEMContract, MarketplaceContract } = require('./contractABI');

class BlockchainIndexer {
    constructor(rpcUrl, contractAddresses) {
        this.provider = new ethers.JsonRpcProvider(rpcUrl);
        this.stemContract = new ethers.Contract(
            contractAddresses.stem,
            STEMContract.abi,
            this.provider
        );
        this.marketplaceContract = new ethers.Contract(
            contractAddresses.marketplace,
            MarketplaceContract.abi,
            this.provider
        );
    }
    
    async startIndexing() {
        // Listen for STEM minting events
        this.stemContract.on('STEMMinted', async (tokenId, creator, name, audioHash, event) => {
            await this.handleSTEMMinted({
                tokenId: tokenId.toString(),
                creator,
                name,
                audioHash,
                blockNumber: event.blockNumber,
                transactionHash: event.transactionHash
            });
        });
        
        // Listen for marketplace events
        this.marketplaceContract.on('Listed', async (listingId, tokenId, seller, amount, price, event) => {
            await this.handleListing({
                listingId: listingId.toString(),
                tokenId: tokenId.toString(),
                seller,
                amount: amount.toString(),
                price: price.toString(),
                blockNumber: event.blockNumber,
                transactionHash: event.transactionHash
            });
        });
    }
    
    async handleSTEMMinted(data) {
        // Store STEM data in database
        await STEMModel.create({
            tokenId: data.tokenId,
            creator: data.creator,
            name: data.name,
            audioIPFSHash: data.audioHash,
            mintedAt: new Date(),
            blockNumber: data.blockNumber,
            transactionHash: data.transactionHash
        });
    }
}
```

### 3.4 IPFS Integration

#### Metadata and Audio Storage
```javascript
const IPFS = require('ipfs-http-client');

class IPFSService {
    constructor() {
        this.client = IPFS.create({
            host: 'ipfs.infura.io',
            port: 5001,
            protocol: 'https'
        });
    }
    
    async uploadAudioFile(audioBuffer, metadata) {
        // Upload audio file
        const audioResult = await this.client.add(audioBuffer);
        
        // Create and upload metadata
        const metadataObject = {
            name: metadata.name,
            description: metadata.description,
            image: metadata.imageHash,
            audio: audioResult.path,
            attributes: [
                { trait_type: "Duration", value: metadata.duration },
                { trait_type: "Genre", value: metadata.genre },
                { trait_type: "Creator", value: metadata.creator }
            ]
        };
        
        const metadataResult = await this.client.add(JSON.stringify(metadataObject));
        
        return {
            audioHash: audioResult.path,
            metadataHash: metadataResult.path
        };
    }
}
```

### 3.5 API Gateway

#### GraphQL API for Blockchain Data
```javascript
const { ApolloServer, gql } = require('apollo-server-express');

const typeDefs = gql`
    type STEM {
        tokenId: ID!
        name: String!
        description: String
        creator: String!
        audioIPFSHash: String!
        imageIPFSHash: String
        createdAt: String!
        duration: Int!
        genre: String
        tags: [String!]!
        royaltyPercentage: Int!
        currentListings: [Listing!]!
    }
    
    type Listing {
        id: ID!
        tokenId: ID!
        seller: String!
        amount: Int!
        pricePerToken: String!
        active: Boolean!
        listedAt: String!
        stem: STEM!
    }
    
    type Query {
        getSTEM(tokenId: ID!): STEM
        getSTEMsByCreator(creator: String!): [STEM!]!
        getActiveListings(limit: Int, offset: Int): [Listing!]!
        searchSTEMs(query: String!, genre: String, tags: [String!]): [STEM!]!
    }
    
    type Mutation {
        createListing(tokenId: ID!, amount: Int!, pricePerToken: String!): Listing!
        cancelListing(listingId: ID!): Boolean!
    }
`;

const resolvers = {
    Query: {
        getSTEM: async (_, { tokenId }) => {
            return await STEMModel.findOne({ tokenId });
        },
        getSTEMsByCreator: async (_, { creator }) => {
            return await STEMModel.find({ creator });
        },
        getActiveListings: async (_, { limit = 20, offset = 0 }) => {
            return await ListingModel.find({ active: true })
                .limit(limit)
                .skip(offset)
                .populate('stem');
        }
    }
};
```

---

## 🎨 Phase 4: Tokenization GUI Integration

### 4.1 SwiftUI Tokenization Interface

#### Tokenization Workflow Views
```swift
// Main tokenization interface
struct TokenizationView: View {
    @StateObject private var tokenizationManager = TokenizationManager()
    @State private var selectedRegions: Set<AudioRegion> = []
    @State private var showingTokenizationSheet = false
    
    var body: some View {
        VStack {
            // Region selection interface
            RegionSelectionView(selectedRegions: $selectedRegions)
            
            // Tokenization controls
            HStack {
                Button("Tokenize Selected STEMs") {
                    showingTokenizationSheet = true
                }
                .disabled(selectedRegions.isEmpty)
                
                Button("View My NFTs") {
                    // Navigate to NFT collection view
                }
            }
        }
        .sheet(isPresented: $showingTokenizationSheet) {
            TokenizationConfigurationView(
                regions: Array(selectedRegions),
                onTokenize: { metadata in
                    Task {
                        await tokenizationManager.tokenizeSTEMs(
                            regions: Array(selectedRegions),
                            metadata: metadata
                        )
                    }
                }
            )
        }
    }
}

// Tokenization configuration sheet
struct TokenizationConfigurationView: View {
    let regions: [AudioRegion]
    let onTokenize: (STEMMetadata) -> Void
    
    @State private var stemName = ""
    @State private var description = ""
    @State private var genre = "Electronic"
    @State private var tags: [String] = []
    @State private var royaltyPercentage = 5.0
    @State private var mintAmount = 1
    
    var body: some View {
        NavigationView {
            Form {
                Section("STEM Information") {
                    TextField("Name", text: $stemName)
                    TextField("Description", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Classification") {
                    Picker("Genre", selection: $genre) {
                        ForEach(MusicGenre.allCases, id: \.self) { genre in
                            Text(genre.rawValue).tag(genre.rawValue)
                        }
                    }
                    
                    TagInputView(tags: $tags)
                }
                
                Section("Tokenization Settings") {
                    HStack {
                        Text("Royalty Percentage")
                        Spacer()
                        Text("\(royaltyPercentage, specifier: "%.1f")%")
                    }
                    Slider(value: $royaltyPercentage, in: 0...20, step: 0.5)
                    
                    Stepper("Mint Amount: \(mintAmount)", value: $mintAmount, in: 1...1000)
                }
                
                Section("Preview") {
                    ForEach(regions, id: \.id) { region in
                        STEMPreviewRow(region: region)
                    }
                }
            }
            .navigationTitle("Tokenize STEMs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        // Dismiss sheet
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Tokenize") {
                        let metadata = STEMMetadata(
                            name: stemName,
                            description: description,
                            genre: genre,
                            tags: tags,
                            royaltyPercentage: royaltyPercentage
                        )
                        onTokenize(metadata)
                    }
                    .disabled(stemName.isEmpty)
                }
            }
        }
    }
}
```

### 4.2 Blockchain Integration Layer

#### TokenizationManager
```swift
import Foundation
import Web3

@MainActor
class TokenizationManager: ObservableObject {
    @Published var tokenizationStatus: TokenizationStatus = .idle
    @Published var progress: Double = 0.0
    @Published var errorMessage: String?
    
    private let web3Service = Web3Service()
    private let ipfsService = IPFSService()
    private let audioProcessor = AudioProcessor()
    
    func tokenizeSTEMs(regions: [AudioRegion], metadata: STEMMetadata) async {
        tokenizationStatus = .processing
        progress = 0.0
        
        do {
            // Step 1: Process audio regions (20%)
            let processedAudio = try await audioProcessor.exportRegionsToSTEMs(regions)
            progress = 0.2
            
            // Step 2: Upload to IPFS (40%)
            let ipfsHashes = try await ipfsService.uploadSTEMFiles(processedAudio)
            progress = 0.6
            
            // Step 3: Generate artwork (60%)
            let artworkHash = try await generateSTEMArtwork(metadata: metadata)
            progress = 0.7
            
            // Step 4: Mint NFT on blockchain (80%)
            let tokenId = try await web3Service.mintSTEMNFT(
                metadata: metadata,
                audioHash: ipfsHashes.audioHash,
                imageHash: artworkHash
            )
            progress = 0.9
            
            // Step 5: Update local database (100%)
            try await saveTokenizedSTEM(tokenId: tokenId, metadata: metadata)
            progress = 1.0
            
            tokenizationStatus = .completed(tokenId: tokenId)
            
        } catch {
            tokenizationStatus = .failed
            errorMessage = error.localizedDescription
        }
    }
}

enum TokenizationStatus {
    case idle
    case processing
    case completed(tokenId: String)
    case failed
}
```

#### Web3 Service Integration
```swift
import Web3
import BigInt

class Web3Service {
    private let web3: Web3
    private let stemContract: EthereumContract
    private let userWallet: EthereumKeystoreV3
    
    init() {
        // Initialize Web3 connection to Avalanche L1
        self.web3 = Web3(rpcURL: "https://api.avax-test.network/ext/bc/C/rpc")
        
        // Load contract ABI and address
        self.stemContract = try! EthereumContract(
            abi: STEMContractABI.abi,
            at: EthereumAddress("0x...") // Contract address
        )
    }
    
    func mintSTEMNFT(
        metadata: STEMMetadata,
        audioHash: String,
        imageHash: String
    ) async throws -> String {
        
        let mintFunction = stemContract["mintSTEM"]!
        
        let transaction = try mintFunction(
            userWallet.address,
            BigUInt(1), // amount
            [
                metadata.name,
                metadata.description,
                audioHash,
                imageHash,
                userWallet.address,
                BigUInt(Date().timeIntervalSince1970),
                BigUInt(metadata.duration),
                metadata.genre,
                metadata.tags,
                BigUInt(metadata.royaltyPercentage * 100) // convert to basis points
            ],
            Data() // additional data
        ).createTransaction(
            nonce: try await web3.eth.getTransactionCount(address: userWallet.address, block: .latest),
            gasPrice: try await web3.eth.gasPrice(),
            gasLimit: 500000
        )!
        
        let signedTransaction = try transaction.sign(with: userWallet, chainId: 43113) // Avalanche Fuji testnet
        let result = try await web3.eth.sendRawTransaction(transaction: signedTransaction)
        
        // Wait for transaction confirmation and extract token ID
        let receipt = try await waitForTransactionReceipt(hash: result.hash)
        return extractTokenIdFromReceipt(receipt)
    }
}
```

### 4.3 IPFS Integration

#### Audio and Metadata Upload
```swift
import Foundation

class IPFSService {
    private let baseURL = "https://ipfs.infura.io:5001/api/v0"
    private let session = URLSession.shared
    
    func uploadSTEMFiles(_ stemFiles: [STEMFile]) async throws -> IPFSUploadResult {
        var audioHashes: [String] = []
        
        // Upload each audio file
        for stemFile in stemFiles {
            let audioHash = try await uploadFile(stemFile.audioData, filename: stemFile.filename)
            audioHashes.append(audioHash)
        }
        
        // Create and upload metadata
        let metadata = createMetadataJSON(stemFiles: stemFiles, audioHashes: audioHashes)
        let metadataHash = try await uploadJSON(metadata)
        
        return IPFSUploadResult(
            audioHashes: audioHashes,
            metadataHash: metadataHash
        )
    }
    
    private func uploadFile(_ data: Data, filename: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/add")!)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (responseData, _) = try await session.data(for: request)
        let response = try JSONDecoder().decode(IPFSResponse.self, from: responseData)
        
        return response.Hash
    }
}

struct IPFSUploadResult {
    let audioHashes: [String]
    let metadataHash: String
}

struct IPFSResponse: Codable {
    let Hash: String
    let Name: String
    let Size: String
}
```

### 4.4 Progress Tracking and User Feedback

#### Tokenization Progress View
```swift
struct TokenizationProgressView: View {
    @ObservedObject var tokenizationManager: TokenizationManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Progress indicator
            ProgressView(value: tokenizationManager.progress)
                .progressViewStyle(LinearProgressViewStyle())
                .scaleEffect(x: 1, y: 2, anchor: .center)
            
            // Status text
            Text(statusText)
                .font(.headline)
                .foregroundColor(.primary)
            
            // Detailed progress steps
            VStack(alignment: .leading, spacing: 8) {
                ProgressStepView(
                    title: "Processing Audio",
                    isCompleted: tokenizationManager.progress > 0.2,
                    isActive: tokenizationManager.progress <= 0.2
                )
                
                ProgressStepView(
                    title: "Uploading to IPFS",
                    isCompleted: tokenizationManager.progress > 0.6,
                    isActive: tokenizationManager.progress > 0.2 && tokenizationManager.progress <= 0.6
                )
                
                ProgressStepView(
                    title: "Generating Artwork",
                    isCompleted: tokenizationManager.progress > 0.7,
                    isActive: tokenizationManager.progress > 0.6 && tokenizationManager.progress <= 0.7
                )
                
                ProgressStepView(
                    title: "Minting NFT",
                    isCompleted: tokenizationManager.progress > 0.9,
                    isActive: tokenizationManager.progress > 0.7 && tokenizationManager.progress <= 0.9
                )
                
                ProgressStepView(
                    title: "Finalizing",
                    isCompleted: tokenizationManager.progress >= 1.0,
                    isActive: tokenizationManager.progress > 0.9 && tokenizationManager.progress < 1.0
                )
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .padding()
    }
    
    private var statusText: String {
        switch tokenizationManager.tokenizationStatus {
        case .idle:
            return "Ready to tokenize"
        case .processing:
            return "Tokenizing STEMs..."
        case .completed(let tokenId):
            return "Successfully minted NFT #\(tokenId)"
        case .failed:
            return "Tokenization failed"
        }
    }
}

struct ProgressStepView: View {
    let title: String
    let isCompleted: Bool
    let isActive: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : (isActive ? "circle.dotted" : "circle"))
                .foregroundColor(isCompleted ? .green : (isActive ? .blue : .gray))
                .font(.title3)
            
            Text(title)
                .foregroundColor(isCompleted ? .green : (isActive ? .primary : .secondary))
                .font(.body)
            
            Spacer()
        }
    }
}
```

---

## 🏪 Phase 5: NFT Marketplace GUI

### 5.1 NFT Collection Interface

#### My STEMs Collection View
```swift
struct MySTEMsView: View {
    @StateObject private var collectionManager = STEMCollectionManager()
    @State private var selectedFilter: STEMFilter = .all
    @State private var searchText = ""
    @State private var showingCreateListing = false
    @State private var selectedSTEM: STEM?
    
    var body: some View {
        NavigationView {
            VStack {
                // Search and filter bar
                HStack {
                    SearchBar(text: $searchText)
                    
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(STEMFilter.allCases, id: \.self) { filter in
                            Text(filter.displayName).tag(filter)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                .padding(.horizontal)
                
                // Collection grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 200, maximum: 300))
                    ], spacing: 16) {
                        ForEach(filteredSTEMs) { stem in
                            STEMCardView(stem: stem) {
                                selectedSTEM = stem
                                showingCreateListing = true
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("My STEMs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        Task {
                            await collectionManager.refreshCollection()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingCreateListing) {
            if let stem = selectedSTEM {
                CreateListingView(stem: stem) { listing in
                    Task {
                        await collectionManager.createListing(listing)
                    }
                }
            }
        }
        .task {
            await collectionManager.loadUserSTEMs()
        }
    }
    
    private var filteredSTEMs: [STEM] {
        collectionManager.userSTEMs
            .filter { stem in
                if !searchText.isEmpty {
                    return stem.name.localizedCaseInsensitiveContains(searchText) ||
                           stem.genre.localizedCaseInsensitiveContains(searchText)
                }
                return true
            }
            .filter { stem in
                switch selectedFilter {
                case .all:
                    return true
                case .listed:
                    return stem.hasActiveListings
                case .unlisted:
                    return !stem.hasActiveListings
                case .recent:
                    return stem.createdAt > Date().addingTimeInterval(-7 * 24 * 60 * 60) // Last 7 days
                }
            }
    }
}

enum STEMFilter: CaseIterable {
    case all, listed, unlisted, recent
    
    var displayName: String {
        switch self {
        case .all: return "All"
        case .listed: return "Listed"
        case .unlisted: return "Unlisted"
        case .recent: return "Recent"
        }
    }
}
```

#### STEM Card Component
```swift
struct STEMCardView: View {
    let stem: STEM
    let onListAction: () -> Void
    
    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Artwork and play button
            ZStack {
                AsyncImage(url: URL(string: "https://ipfs.io/ipfs/\(stem.imageIPFSHash)")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.purple.opacity(0.6), Color.blue.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 40))
                                .foregroundColor(.white.opacity(0.8))
                        )
                }
                .frame(height: 150)
                .clipped()
                .cornerRadius(12)
                
                // Play/pause button overlay
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                        .background(Color.black.opacity(0.3))
                        .clipShape(Circle())
                }
            }
            
            // STEM information
            VStack(alignment: .leading, spacing: 4) {
                Text(stem.name)
                    .font(.headline)
                    .lineLimit(2)
                
                Text(stem.genre)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
                
                HStack {
                    Text("\(stem.duration)s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if stem.hasActiveListings {
                        Text("Listed")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            }
            
            // Action buttons
            HStack {
                Button("Details") {
                    // Show detailed view
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(stem.hasActiveListings ? "Edit Listing" : "List for Sale") {
                    onListAction()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private func togglePlayback() {
        if isPlaying {
            // Pause audio
            AudioPlayerManager.shared.pause()
        } else {
            // Play audio from IPFS
            Task {
                await AudioPlayerManager.shared.playFromIPFS(hash: stem.audioIPFSHash)
            }
        }
        isPlaying.toggle()
    }
}
```

### 5.2 Marketplace Browse Interface

#### Marketplace Discovery View
```swift
struct MarketplaceView: View {
    @StateObject private var marketplaceManager = MarketplaceManager()
    @State private var selectedCategory: MarketplaceCategory = .trending
    @State private var searchText = ""
    @State private var priceRange: ClosedRange<Double> = 0...1000
    @State private var selectedGenres: Set<String> = []
    
    var body: some View {
        NavigationView {
            VStack {
                // Category selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(MarketplaceCategory.allCases, id: \.self) { category in
                            CategoryButton(
                                category: category,
                                isSelected: selectedCategory == category
                            ) {
                                selectedCategory = category
                                Task {
                                    await marketplaceManager.loadCategory(category)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Filters
                DisclosureGroup("Filters") {
                    VStack(alignment: .leading, spacing: 16) {
                        // Price range filter
                        VStack(alignment: .leading) {
                            Text("Price Range")
                                .font(.headline)
                            RangeSlider(range: $priceRange, bounds: 0...1000)
                            HStack {
                                Text("$\(priceRange.lowerBound, specifier: "%.0f")")
                                Spacer()
                                Text("$\(priceRange.upperBound, specifier: "%.0f")")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        
                        // Genre filter
                        VStack(alignment: .leading) {
                            Text("Genres")
                                .font(.headline)
                            LazyVGrid(columns: [
                                GridItem(.adaptive(minimum: 80))
                            ], spacing: 8) {
                                ForEach(MusicGenre.allCases, id: \.self) { genre in
                                    GenreFilterButton(
                                        genre: genre,
                                        isSelected: selectedGenres.contains(genre.rawValue)
                                    ) {
                                        if selectedGenres.contains(genre.rawValue) {
                                            selectedGenres.remove(genre.rawValue)
                                        } else {
                                            selectedGenres.insert(genre.rawValue)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // Listings grid
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 250, maximum: 350))
                    ], spacing: 16) {
                        ForEach(filteredListings) { listing in
                            MarketplaceListingCard(listing: listing) {
                                // Handle purchase
                                Task {
                                    await marketplaceManager.purchaseListing(listing)
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Marketplace")
            .searchable(text: $searchText)
        }
        .task {
            await marketplaceManager.loadCategory(.trending)
        }
    }
    
    private var filteredListings: [MarketplaceListing] {
        marketplaceManager.currentListings
            .filter { listing in
                // Price filter
                let price = Double(listing.pricePerToken) ?? 0
                guard priceRange.contains(price) else { return false }
                
                // Genre filter
                if !selectedGenres.isEmpty {
                    guard selectedGenres.contains(listing.stem.genre) else { return false }
                }
                
                // Search filter
                if !searchText.isEmpty {
                    let searchLower = searchText.lowercased()
                    return listing.stem.name.lowercased().contains(searchLower) ||
                           listing.stem.genre.lowercased().contains(searchLower) ||
                           listing.stem.tags.contains { $0.lowercased().contains(searchLower) }
                }
                
                return true
            }
    }
}

enum MarketplaceCategory: CaseIterable {
    case trending, recent, topSellers, lowPrice, highPrice
    
    var displayName: String {
        switch self {
        case .trending: return "Trending"
        case .recent: return "Recent"
        case .topSellers: return "Top Sellers"
        case .lowPrice: return "Low Price"
        case .highPrice: return "High Price"
        }
    }
}
```

#### Marketplace Listing Card
```swift
struct MarketplaceListingCard: View {
    let listing: MarketplaceListing
    let onPurchase: () -> Void
    
    @State private var showingDetails = false
    @State private var isPlaying = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // STEM artwork and info
            ZStack {
                AsyncImage(url: URL(string: "https://ipfs.io/ipfs/\(listing.stem.imageIPFSHash)")) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.orange.opacity(0.6), Color.red.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
                .frame(height: 180)
                .clipped()
                .cornerRadius(12)
                
                // Play button overlay
                VStack {
                    Spacer()
                    HStack {
                        Button(action: { isPlaying.toggle() }) {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.white)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // Creator info
                        VStack(alignment: .trailing) {
                            Text("by \(listing.stem.creator.prefix(6))...")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            
            // STEM details
            VStack(alignment: .leading, spacing: 8) {
                Text(listing.stem.name)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack {
                    Text(listing.stem.genre)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                    
                    Text("\(listing.stem.duration)s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                
                // Tags
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(listing.stem.tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }
                    }
                }
            }
            
            Divider()
            
            // Pricing and purchase
            HStack {
                VStack(alignment: .leading) {
                    Text("Price")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("$\(listing.pricePerToken)")
                        .font(.title2)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text("\(listing.amount) available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Buy Now") {
                        onPurchase()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            // Action buttons
            HStack {
                Button("Details") {
                    showingDetails = true
                }
                .buttonStyle(.bordered)
                
                Button("Make Offer") {
                    // Show offer sheet
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Button(action: {}) {
                    Image(systemName: "heart")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .sheet(isPresented: $showingDetails) {
            STEMDetailView(stem: listing.stem, listing: listing)
        }
    }
}
```

### 5.3 Purchase and Trading Interface

#### Purchase Flow
```swift
struct PurchaseFlowView: View {
    let listing: MarketplaceListing
    @StateObject private var purchaseManager = PurchaseManager()
    @State private var purchaseAmount = 1
    @State private var showingConfirmation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // STEM preview
                STEMPreviewCard(stem: listing.stem)
                
                // Purchase details
                VStack(alignment: .leading, spacing: 16) {
                    Text("Purchase Details")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Price per token:")
                        Spacer()
                        Text("$\(listing.pricePerToken)")
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Amount:")
                        Spacer()
                        Stepper("\(purchaseAmount)", value: $purchaseAmount, in: 1...listing.amount)
                    }
                    
                    Divider()
                    
                    HStack {
                        Text("Total:")
                            .font(.headline)
                        Spacer()
                        Text("$\(totalPrice, specifier: "%.2f")")
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    
                    // Fees breakdown
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Marketplace fee (2.5%):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("$\(marketplaceFee, specifier: "%.2f")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Creator royalty (\(listing.stem.royaltyPercentage, specifier: "%.1f")%):")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("$\(royaltyFee, specifier: "%.2f")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                Spacer()
                
                // Purchase button
                Button("Purchase STEM") {
                    showingConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(purchaseManager.isPurchasing)
                
                if purchaseManager.isPurchasing {
                    ProgressView("Processing purchase...")
                        .progressViewStyle(CircularProgressViewStyle())
                }
            }
            .padding()
            .navigationTitle("Purchase STEM")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Confirm Purchase", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Confirm") {
                    Task {
                        await purchaseManager.purchaseListing(
                            listing: listing,
                            amount: purchaseAmount
                        )
                    }
                }
            } message: {
                Text("Are you sure you want to purchase \(purchaseAmount) token(s) of \"\(listing.stem.name)\" for $\(totalPrice, specifier: "%.2f")?")
            }
        }
    }
    
    private var totalPrice: Double {
        Double(listing.pricePerToken)! * Double(purchaseAmount)
    }
    
    private var marketplaceFee: Double {
        totalPrice * 0.025
    }
    
    private var royaltyFee: Double {
        totalPrice * (listing.stem.royaltyPercentage / 100.0)
    }
}
```

### 5.4 Portfolio and Analytics

#### Portfolio Overview
```swift
struct PortfolioView: View {
    @StateObject private var portfolioManager = PortfolioManager()
    @State private var selectedTimeframe: TimeFrame = .week
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Portfolio summary
                VStack(spacing: 16) {
                    Text("Portfolio Value")
                        .font(.headline)
                    
                    Text("$\(portfolioManager.totalValue, specifier: "%.2f")")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    HStack {
                        Text("\(portfolioManager.valueChange >= 0 ? "+" : "")$\(portfolioManager.valueChange, specifier: "%.2f")")
                            .foregroundColor(portfolioManager.valueChange >= 0 ? .green : .red)
                        
                        Text("(\(portfolioManager.percentageChange >= 0 ? "+" : "")\(portfolioManager.percentageChange, specifier: "%.1f")%)")
                            .foregroundColor(portfolioManager.valueChange >= 0 ? .green : .red)
                        
                        Text("today")
                            .foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(16)
                
                // Portfolio chart
                VStack(alignment: .leading) {
                    HStack {
                        Text("Performance")
                            .font(.headline)
                        
                        Spacer()
                        
                        Picker("Timeframe", selection: $selectedTimeframe) {
                            ForEach(TimeFrame.allCases, id: \.self) { timeframe in
                                Text(timeframe.displayName).tag(timeframe)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                    
                    PortfolioChartView(
                        data: portfolioManager.chartData,
                        timeframe: selectedTimeframe
                    )
                    .frame(height: 200)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(16)
                
                // Holdings breakdown
                VStack(alignment: .leading) {
                    Text("Holdings")
                        .font(.headline)
                    
                    ForEach(portfolioManager.holdings) { holding in
                        HoldingRowView(holding: holding)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(16)
                
                // Recent activity
                VStack(alignment: .leading) {
                    Text("Recent Activity")
                        .font(.headline)
                    
                    ForEach(portfolioManager.recentActivity) { activity in
                        ActivityRowView(activity: activity)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(16)
            }
            .padding()
        }
        .navigationTitle("Portfolio")
        .task {
            await portfolioManager.loadPortfolioData()
        }
    }
}

enum TimeFrame: CaseIterable {
    case day, week, month, year
    
    var displayName: String {
        switch self {
        case .day: return "1D"
        case .week: return "1W"
        case .month: return "1M"
        case .year: return "1Y"
        }
    }
}
```

---

## 🔧 Technical Implementation Details

### Development Environment Setup

#### Required Tools and Versions
```bash
# macOS Development
- Xcode 16.0+
- Swift 6.0+
- macOS 14.0+ (Sonoma)

# Python Backend
- Python 3.11+
- PyTorch 2.0+
- CUDA 11.8+ (for GPU acceleration)

# Blockchain Development
- Node.js 18+
- Hardhat 2.19+
- Avalanche CLI 1.5+

# Additional Tools
- Docker & Docker Compose
- Redis 7.0+
- PostgreSQL 15+
- IPFS Node
```

#### Project Structure Overview
```
TellUrStoriV2/
├── ios-app/                    # Swift/SwiftUI DAW application
├── musicgen-service/           # Python MusicGen backend
├── blockchain/                 # Avalanche L1 smart contracts
├── indexer-service/           # Blockchain event indexer
├── api-gateway/               # GraphQL API gateway
├── ipfs-service/              # IPFS integration service
├── docker-compose.yml         # Development environment
└── README.md                  # Project documentation
```

### Performance Requirements

#### Audio Performance Targets
- **Latency**: < 10ms round-trip audio latency
- **CPU Usage**: < 30% on Apple Silicon M1/M2
- **Memory Usage**: < 500MB for 8-track project
- **Startup Time**: < 2 seconds to ready state
- **Export Speed**: Real-time or faster for standard formats

#### AI Generation Performance
- **Generation Time**: < 60 seconds for 30s audio clip
- **Queue Processing**: Support for 10+ concurrent generations
- **Model Loading**: < 30 seconds cold start
- **Memory Usage**: < 8GB VRAM for medium model

#### Blockchain Performance
- **Transaction Confirmation**: < 5 seconds on Avalanche L1
- **Indexing Latency**: < 1 second for new events
- **API Response Time**: < 200ms for standard queries
- **IPFS Upload**: < 30 seconds for 30MB audio file

### Security Considerations

#### Smart Contract Security
- OpenZeppelin security patterns
- Multi-signature wallet integration
- Reentrancy protection
- Access control mechanisms
- Upgrade patterns for contract evolution

#### API Security
- JWT authentication
- Rate limiting
- Input validation
- CORS configuration
- API key management

#### Data Privacy
- Local audio processing when possible
- Encrypted IPFS uploads
- User consent for AI training data
- GDPR compliance measures
- Secure key storage

### Deployment Strategy

#### Development Environment
```yaml
# docker-compose.yml
version: '3.8'
services:
  musicgen-service:
    build: ./musicgen-service
    ports:
      - "8000:8000"
    environment:
      - CUDA_VISIBLE_DEVICES=0
    volumes:
      - ./models:/app/models
      - ./generated:/app/generated
  
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
  
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: tellurstoridaw
      POSTGRES_USER: dev
      POSTGRES_PASSWORD: devpass
    ports:
      - "5432:5432"
  
  ipfs:
    image: ipfs/go-ipfs:latest
    ports:
      - "4001:4001"
      - "5001:5001"
      - "8080:8080"
```

#### Production Deployment
- **iOS App**: App Store distribution with TestFlight beta
- **Backend Services**: Kubernetes cluster with auto-scaling
- **Blockchain**: Avalanche L1 mainnet deployment
- **IPFS**: Pinata or Infura IPFS service
- **Monitoring**: Prometheus + Grafana + Sentry

### Testing Strategy

#### Unit Testing Coverage
- Swift: XCTest with 90%+ code coverage
- Python: pytest with 85%+ coverage
- Smart Contracts: Hardhat tests with 95%+ coverage
- Integration: End-to-end testing with Cypress

#### Performance Testing
- Audio latency benchmarking
- Memory leak detection
- Stress testing with multiple concurrent users
- Blockchain load testing

#### Security Testing
- Smart contract auditing
- Penetration testing
- Dependency vulnerability scanning
- Code quality analysis with SonarQube

---

## 📋 Implementation Checklist

### Phase 1: DAW MVP ✅ **COMPLETED - December 2024**
- [x] Project setup and architecture
- [x] Core audio engine foundation (AVAudioEngine integration)
- [x] SwiftUI interface components (MainDAWView, TimelineView, MixerView, TransportView)
- [x] Timeline and track management UI structure
- [x] Audio region management data models
- [x] Mixer interface layout (channel strips, faders, EQ knobs)
- [x] Transport controls UI (play, pause, stop, record buttons)
- [x] Project persistence architecture (ProjectManager, Core Data models)
- [x] Comprehensive data models (AudioProject, AudioTrack, AudioRegion, etc.)
- [x] Organized modular folder structure (Core/, Features/, UI/)
- [x] MVVM architecture with ObservableObject pattern
- [x] macOS-native implementation with proper entitlements
- [x] Professional DAW styling and layout
- [x] Git repository setup with comprehensive .gitignore
- [x] Documentation (README.md, roadmap updates)

#### Phase 1 Notes:
- **UI Structure Complete**: All major interface components implemented
- **Architecture Foundation**: Solid MVVM foundation ready for functionality
- **Non-Interactive Elements**: Volume sliders, mute/solo buttons, track creation UI present but not wired up
- **Audio Processing**: Foundation in place, actual processing to be implemented in Phase 2
- **Ready for Phase 2**: Interactive functionality and audio processing implementation

### Phase 1.5: Interactive Functionality ✅ **COMPLETED - December 2024**
- [x] Wire up mixer controls (volume, pan, mute, solo functionality)
- [x] Implement track creation and deletion
- [x] Enable transport controls (actual playback/recording)
- [x] Project save/load operations
- [x] Real-time audio engine with proper timing coordination
- [x] Enhanced error handling and crash prevention
- [x] Performance optimization for real-time audio
- [x] Audio node cleanup and memory management
- [ ] Add audio file import/export
- [ ] Real-time waveform visualization
- [ ] Audio region drag & drop functionality
- [ ] Basic effects processing pipeline
- [ ] Unit and integration testing
- [ ] Beta testing with musicians

#### Phase 1.5 Notes:
- **Core Functionality Complete**: All essential DAW controls now fully interactive
- **Audio Engine Stable**: Robust audio processing with crash prevention
- **Professional UX**: Volume sliders, mute/solo buttons, transport controls all functional
- **Project Management**: Create, save, and load projects with persistent state
- **Ready for Phase 2**: Solid foundation for AI music generation integration

### Phase 2: MusicGen Backend ✅ **COMPLETED - December 2024**
- [x] Python service architecture (FastAPI with async processing)
- [x] MusicGen model integration (Hugging Face transformers)
- [x] Prompt template builder (structured prompt generation)
- [x] FastAPI endpoints (generation, status, download, health)
- [x] Swift-Python communication layer (MusicGenClient.swift)
- [x] Error handling and retry logic (comprehensive error management)
- [x] Audio file processing pipeline (real AI music generation)
- [x] Performance monitoring (extensive logging and progress tracking)
- [ ] WebSocket real-time communication (HTTP polling implemented)
- [ ] Celery task queue setup (background processing implemented)
- [ ] Redis caching implementation (direct processing for now)
- [ ] Load testing (basic functionality tested)
- [ ] Docker containerization (local development working)
- [ ] Production deployment (ready for deployment)

#### Phase 2 Notes:
- **AI Generation Working**: Real MusicGen model generating actual music from text prompts
- **Swift Integration**: Complete MusicGenClient.swift for seamless DAW-AI communication
- **Performance Optimized**: CPU-friendly generation with progress tracking and error handling
- **Production Ready**: Robust backend service ready for DAW integration
- **Next Priority**: Integrate AI generation UI directly into DAW timeline

### Phase 3: Avalanche L1 Backend
- [ ] Avalanche L1 subnet creation
- [ ] Smart contract development
- [ ] ERC-1155 STEM token contract
- [ ] Marketplace contract
- [ ] Royalty management system
- [ ] Contract testing and auditing
- [ ] Hardhat deployment scripts
- [ ] Blockchain indexer service
- [ ] GraphQL API development
- [ ] IPFS integration
- [ ] Metadata standards
- [ ] Event monitoring
- [ ] Performance optimization
- [ ] Security audit
- [ ] Mainnet deployment

### Phase 4: Tokenization GUI
- [ ] Tokenization workflow UI
- [ ] STEM metadata input forms
- [ ] Progress tracking interface
- [ ] Web3 integration layer
- [ ] IPFS upload handling
- [ ] Transaction status monitoring
- [ ] Error handling and recovery
- [ ] Batch tokenization support
- [ ] Preview and validation
- [ ] Success confirmation flows
- [ ] Integration testing
- [ ] User experience testing
- [ ] Performance optimization
- [ ] Documentation

### Phase 5: NFT Marketplace GUI
- [ ] Collection view interface
- [ ] Marketplace browse interface
- [ ] Search and filtering
- [ ] STEM detail views
- [ ] Purchase flow implementation
- [ ] Offer and bidding system
- [ ] Portfolio tracking
- [ ] Analytics dashboard
- [ ] Transaction history
- [ ] Notification system
- [ ] Social features (following, likes)
- [ ] Advanced trading features
- [ ] Mobile responsiveness
- [ ] Final integration testing
- [ ] Launch preparation

---

## 🚀 Success Metrics

### Technical Metrics
- **Audio Latency**: < 10ms consistently
- **Generation Speed**: 30s audio in < 60s
- **App Performance**: 60fps UI, < 2s startup
- **Blockchain TPS**: > 1000 transactions/second
- **Uptime**: 99.9% service availability

### User Experience Metrics
- **Onboarding**: < 5 minutes to first STEM creation
- **Learning Curve**: Basic proficiency in < 30 minutes
- **Error Rate**: < 1% failed operations
- **User Satisfaction**: > 4.5/5 rating
- **Retention**: > 70% monthly active users

### Business Metrics
- **STEM Creation**: > 1000 STEMs minted in first month
- **Marketplace Volume**: > $10K trading volume monthly
- **Creator Revenue**: > $1K average monthly earnings
- **Platform Growth**: 50% month-over-month user growth
- **Community Engagement**: > 80% of users participate in marketplace

---

## 📚 Documentation Requirements

### Technical Documentation
- [ ] API documentation with OpenAPI/Swagger
- [ ] Smart contract documentation
- [ ] Architecture decision records (ADRs)
- [ ] Database schema documentation
- [ ] Deployment guides
- [ ] Troubleshooting guides

### User Documentation
- [ ] Getting started guide
- [ ] DAW tutorial series
- [ ] MusicGen prompt guide
- [ ] NFT tokenization walkthrough
- [ ] Marketplace user guide
- [ ] FAQ and support documentation

### Developer Documentation
- [ ] Contributing guidelines
- [ ] Code style guides
- [ ] Testing procedures
- [ ] Release processes
- [ ] Security best practices
- [ ] Performance optimization guide

---

This comprehensive roadmap provides a detailed blueprint for implementing TellUrStori V2 across all five phases. Each phase builds upon the previous one, ensuring a solid foundation while maintaining development velocity. The modular architecture allows for parallel development of different components and provides flexibility for future enhancements and scaling.

The implementation plan balances technical excellence with practical startup constraints, emphasizing MVP functionality while establishing the architecture for advanced features. Regular testing, performance monitoring, and user feedback integration ensure the final product meets both technical requirements and user expectations.

*Ready to transform the music creation landscape with AI-powered DAW technology and blockchain innovation! 🎵⛓️✨*
