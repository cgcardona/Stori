# 🎵 TellUrStori V2 - Blockchain Smart Contracts

This directory contains the smart contracts for TellUrStori V2's STEM tokenization and marketplace functionality.

## 🏗️ Architecture

### Smart Contracts

1. **TellUrStoriSTEM_Optimized.sol** - Production-ready ERC-1155 multi-token contract for music STEM NFTs
   - Mint individual or batch STEM tokens with gas optimization
   - Built-in royalty calculation system with ERC2981 standard compliance
   - Creator management and metadata storage with IPFS validation
   - Pausable mechanism for emergency stops and enhanced security
   - Comprehensive input validation and custom error handling
   - **SECURITY AUDITED**: RemixAI verified, no critical vulnerabilities

2. **STEMMarketplace_Optimized.sol** - Enterprise-grade marketplace for trading STEMs
   - Fixed-price listings with expiration and enhanced validation
   - Offer/counter-offer system with escrow protection
   - Auction functionality with anti-sniping bid extension mechanism
   - Royalty distribution to creators with precision safeguards
   - Marketplace fee collection with transparent events
   - Pagination optimization for gas efficiency and scalability
   - **BULLETPROOF SECURITY**: Production-ready with modern Solidity patterns

### Key Features

- **ERC-1155 Multi-Token Standard**: Efficient batch operations and fractional ownership
- **Royalty System**: Automatic creator royalties on secondary sales
- **Marketplace Integration**: Complete trading ecosystem with listings, offers, and auctions
- **Security**: OpenZeppelin security patterns, reentrancy protection, access controls
- **Gas Optimization**: Efficient batch operations and storage patterns

## 🚀 Quick Start

### Prerequisites

- Node.js 18+
- npm or yarn
- Git

### Installation

```bash
# Install dependencies
npm install

# Compile contracts
npx hardhat compile

# Run tests
npx hardhat test

# Deploy to local network
npx hardhat run scripts/deploy.js

# Deploy to Avalanche Fuji testnet
npx hardhat run scripts/deploy.js --network fuji
```

### Environment Setup

Create a `.env` file in this directory:

```bash
# Private key for deployment (DO NOT COMMIT)
PRIVATE_KEY=your_private_key_here

# Snowtrace API key for contract verification
SNOWTRACE_API_KEY=your_snowtrace_api_key

# RPC URLs (optional, defaults provided)
AVALANCHE_RPC_URL=https://api.avax.network/ext/bc/C/rpc
FUJI_RPC_URL=https://api.avax-test.network/ext/bc/C/rpc
```

## 📜 Contract Details

### TellUrStoriSTEM

**Key Functions:**
- `mintSTEM()` - Mint a single STEM token
- `batchMintSTEMs()` - Mint multiple STEM tokens in one transaction
- `updateSTEMMetadata()` - Update STEM name and description (creator only)
- `calculateRoyalty()` - Calculate royalty amount for a sale
- `getSTEMsByCreator()` - Get all STEMs created by an address

**Events:**
- `STEMMinted` - Emitted when new STEM tokens are minted
- `STEMMetadataUpdated` - Emitted when metadata is updated
- `RoyaltyPaid` - Emitted when royalties are distributed

### STEMMarketplace

**Key Functions:**
- `createListing()` - List STEM tokens for sale
- `buyListing()` - Purchase from a listing
- `makeOffer()` - Make an offer on a listing
- `acceptOffer()` - Accept an offer (seller only)
- `createAuction()` - Create an auction
- `placeBid()` - Place a bid on an auction
- `settleAuction()` - Settle a completed auction

**Events:**
- `Listed` - New listing created
- `Sold` - Successful purchase
- `OfferMade` - New offer placed
- `OfferAccepted` - Offer accepted
- `AuctionCreated` - New auction started
- `BidPlaced` - New bid placed
- `AuctionSettled` - Auction completed

## 🧪 Testing

Our test suite covers:
- Contract deployment and initialization
- STEM minting (individual and batch)
- Metadata management
- Royalty calculations
- Marketplace operations
- Error conditions and edge cases

```bash
# Run all tests
npx hardhat test

# Run specific test file
npx hardhat test test/TellUrStoriSTEM.test.js

# Run tests with gas reporting
REPORT_GAS=true npx hardhat test
```

## 🌐 Network Configuration

### Supported Networks

1. **Hardhat Local** - Development and testing
   - Chain ID: 31337
   - RPC: http://localhost:8545

2. **Avalanche Fuji Testnet** - Testing deployment
   - Chain ID: 43113
   - RPC: https://api.avax-test.network/ext/bc/C/rpc
   - Explorer: https://testnet.snowtrace.io

3. **Avalanche Mainnet** - Production deployment
   - Chain ID: 43114
   - RPC: https://api.avax.network/ext/bc/C/rpc
   - Explorer: https://snowtrace.io

### Custom L1 Subnet (Future)

We plan to deploy on a custom Avalanche L1 subnet for:
- Lower transaction costs
- Higher throughput
- Custom governance
- Specialized features for music NFTs

## 📊 Gas Optimization

Our contracts are optimized for gas efficiency:
- Batch operations for multiple tokens
- Packed structs for storage efficiency
- Minimal external calls
- Efficient event logging

## 🔐 Security Features

- **OpenZeppelin Contracts**: Battle-tested security patterns
- **Reentrancy Protection**: All state-changing functions protected
- **Access Controls**: Owner and creator-only functions
- **Input Validation**: Comprehensive parameter checking
- **Custom Errors**: Gas-efficient error handling

## 🚀 Deployment

### Local Development

```bash
# Start local Hardhat network
npx hardhat node

# Deploy to local network (in another terminal)
npx hardhat run scripts/deploy.js --network localhost
```

### Testnet Deployment

```bash
# Deploy to Avalanche Fuji testnet
npx hardhat run scripts/deploy.js --network fuji

# Verify contracts on Snowtrace
npx hardhat verify --network fuji DEPLOYED_CONTRACT_ADDRESS "constructor_arg1" "constructor_arg2"
```

### Production Deployment

```bash
# Deploy to Avalanche mainnet
npx hardhat run scripts/deploy.js --network avalanche

# Verify contracts
npx hardhat verify --network avalanche DEPLOYED_CONTRACT_ADDRESS "constructor_arg1" "constructor_arg2"
```

## 📁 Project Structure

```
blockchain/
├── contracts/              # Smart contract source files
│   ├── TellUrStoriSTEM.sol     # Main STEM token contract
│   └── STEMMarketplace.sol     # Marketplace contract
├── scripts/                # Deployment and utility scripts
│   └── deploy.js              # Main deployment script
├── test/                   # Test files
│   └── TellUrStoriSTEM.test.js # Contract tests
├── deployments/            # Deployment artifacts (auto-generated)
├── artifacts/              # Compiled contracts (auto-generated)
├── cache/                  # Hardhat cache (auto-generated)
├── hardhat.config.js       # Hardhat configuration
├── package.json            # Node.js dependencies
└── README.md              # This file
```

## 🔗 Integration

These contracts integrate with:
- **Swift DAW Application**: For minting STEMs from generated music
- **IPFS Service**: For decentralized metadata and audio storage
- **Indexer Service**: For real-time blockchain event processing
- **GraphQL API**: For querying blockchain data
- **Frontend Marketplace**: For trading and discovery

## 📚 Additional Resources

- [Hardhat Documentation](https://hardhat.org/docs)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts)
- [Avalanche Documentation](https://docs.avax.network)
- [ERC-1155 Standard](https://eips.ethereum.org/EIPS/eip-1155)
- [Solidity Documentation](https://docs.soliditylang.org)

## 🤝 Contributing

1. Follow Solidity style guidelines
2. Add comprehensive tests for new features
3. Update documentation for any changes
4. Use OpenZeppelin patterns for security
5. Optimize for gas efficiency

---

**Built with ❤️ for the future of music creation and ownership** 🎵⛓️✨
