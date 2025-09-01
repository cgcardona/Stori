# 🎵 TellUrStori V2 - Blockchain Indexer Service

Real-time blockchain event indexing, IPFS integration, and GraphQL API for TellUrStori V2's STEM tokenization and marketplace ecosystem.

## 🚀 Features

### 🔗 Blockchain Integration
- **Real-time Event Listening**: Monitors smart contract events in real-time
- **Automatic Reconnection**: Robust connection handling with exponential backoff
- **Multi-Contract Support**: Indexes both STEM token and marketplace contracts
- **Event Processing**: Comprehensive event handling for mints, transfers, listings, sales, and offers

### 🌐 IPFS Integration
- **Modern Helia Implementation**: Uses the latest IPFS JavaScript client
- **Metadata Management**: Fetches, caches, and enriches STEM metadata
- **Audio File Storage**: Handles decentralized audio file storage and retrieval
- **Intelligent Caching**: Smart caching with expiration and access tracking

### 📊 Database & Analytics
- **PostgreSQL Storage**: Robust relational database for indexed data
- **Comprehensive Schema**: Tables for STEMs, transfers, listings, sales, offers, and metadata
- **Performance Optimized**: Proper indexing and query optimization
- **Analytics Ready**: Built-in analytics and statistics generation

### 🔍 GraphQL API
- **Comprehensive Schema**: Full-featured GraphQL API for all indexed data
- **Advanced Filtering**: Complex filtering and sorting capabilities
- **Pagination Support**: Cursor-based pagination for large datasets
- **Real-time Subscriptions**: Live updates for blockchain events (future)

### 🛠️ Developer Experience
- **Docker Compose**: Complete development environment setup
- **Health Checks**: Comprehensive health monitoring
- **Logging**: Structured logging with Winston
- **Error Handling**: Robust error handling and recovery
- **Monitoring Ready**: Prometheus metrics and Grafana dashboards

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Blockchain    │    │      IPFS       │    │   PostgreSQL    │
│   (Avalanche)   │◄──►│    (Helia)      │◄──►│   Database      │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Indexer Service Core                            │
│  ┌─────────────┐ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐│
│  │ Event       │ │ Metadata    │ │ Indexing    │ │ GraphQL     ││
│  │ Listener    │ │ Service     │ │ Service     │ │ API         ││
│  └─────────────┘ └─────────────┘ └─────────────┘ └─────────────┘│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   Client Apps   │
                    │ (Swift DAW,     │
                    │  Web Frontend)  │
                    └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites
- Node.js 20+
- Docker & Docker Compose
- PostgreSQL 15+
- Redis 7+

### Development Setup

1. **Clone and Navigate**
   ```bash
   cd indexer-service
   ```

2. **Install Dependencies**
   ```bash
   npm install
   ```

3. **Configure Environment**
   ```bash
   cp env.example .env
   # Edit .env with your configuration
   ```

4. **Start Infrastructure**
   ```bash
   docker-compose up -d postgres redis ipfs
   ```

5. **Initialize Database**
   ```bash
   npm run migrate
   ```

6. **Start Development Server**
   ```bash
   npm run dev
   ```

### Production Deployment

1. **Full Stack with Docker**
   ```bash
   docker-compose up -d
   ```

2. **Environment Configuration**
   ```bash
   # Set production environment variables
   export NODE_ENV=production
   export RPC_URL=https://api.avax.network/ext/bc/C/rpc
   export STEM_CONTRACT_ADDRESS=0x...
   export MARKETPLACE_CONTRACT_ADDRESS=0x...
   ```

## 📡 API Endpoints

### REST Endpoints
- `GET /health` - Health check
- `GET /api/info` - Service information
- `GET /metrics` - Prometheus metrics

### GraphQL Endpoint
- `POST /graphql` - GraphQL API
- `GET /graphql` - GraphQL Playground (development)

## 🔍 GraphQL Schema

### Core Queries

```graphql
# Get a specific STEM
query GetStem($tokenId: String!) {
  stem(tokenId: $tokenId) {
    id
    tokenId
    name
    description
    creator {
      address
      stemsCount
    }
    stemType
    duration
    bpm
    key
    genre
    totalSupply
    floorPrice
    lastSalePrice
    createdAt
  }
}

# Search STEMs with filters
query SearchStems($where: StemFilter, $first: Int) {
  stems(where: $where, first: $first) {
    edges {
      node {
        tokenId
        name
        creator {
          address
        }
        stemType
        floorPrice
      }
    }
    totalCount
  }
}

# Get marketplace listings
query GetListings($where: ListingFilter) {
  listings(where: $where) {
    edges {
      node {
        listingId
        seller
        stem {
          name
          stemType
        }
        pricePerToken
        amount
        expiration
        active
      }
    }
  }
}

# Get market statistics
query GetMarketStats {
  marketStats {
    totalVolume
    totalSales
    averageSalePrice
    activeListings
    floorPrice
    volume24h
    sales24h
  }
}
```

### Advanced Filtering

```graphql
query FilteredStems {
  stems(
    where: {
      stemType: DRUMS
      genre: "electronic"
      minBPM: 120
      maxBPM: 140
      hasAudio: true
      createdAfter: "2024-01-01T00:00:00Z"
    }
    orderBy: CREATED_AT
    orderDirection: DESC
    first: 20
  ) {
    edges {
      node {
        tokenId
        name
        bpm
        duration
        floorPrice
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
```

## 🗄️ Database Schema

### Core Tables

```sql
-- STEMs table
CREATE TABLE stems (
  id SERIAL PRIMARY KEY,
  token_id VARCHAR(255) NOT NULL UNIQUE,
  creator_address VARCHAR(42) NOT NULL,
  name VARCHAR(255),
  description TEXT,
  metadata_uri TEXT,
  metadata_cid VARCHAR(255),
  audio_cid VARCHAR(255),
  image_cid VARCHAR(255),
  stem_type VARCHAR(50),
  duration INTEGER,
  bpm INTEGER,
  key VARCHAR(10),
  genre VARCHAR(50),
  total_supply NUMERIC(78, 0) DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  -- ... additional fields
);

-- Transfers table
CREATE TABLE transfers (
  id SERIAL PRIMARY KEY,
  token_id VARCHAR(255) NOT NULL,
  from_address VARCHAR(42),
  to_address VARCHAR(42) NOT NULL,
  amount NUMERIC(78, 0) NOT NULL,
  transaction_hash VARCHAR(66) NOT NULL,
  block_number BIGINT NOT NULL,
  timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Listings table
CREATE TABLE listings (
  id SERIAL PRIMARY KEY,
  listing_id VARCHAR(255) NOT NULL UNIQUE,
  seller_address VARCHAR(42) NOT NULL,
  token_id VARCHAR(255) NOT NULL,
  amount NUMERIC(78, 0) NOT NULL,
  price_per_token NUMERIC(78, 0) NOT NULL,
  expiration TIMESTAMP WITH TIME ZONE,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Sales table
CREATE TABLE sales (
  id SERIAL PRIMARY KEY,
  listing_id VARCHAR(255) NOT NULL,
  buyer_address VARCHAR(42) NOT NULL,
  seller_address VARCHAR(42) NOT NULL,
  token_id VARCHAR(255) NOT NULL,
  amount NUMERIC(78, 0) NOT NULL,
  total_price NUMERIC(78, 0) NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## 🔧 Configuration

### Environment Variables

```bash
# Server
PORT=4000
NODE_ENV=development
LOG_LEVEL=info

# Database
DB_HOST=localhost
DB_PORT=5432
DB_NAME=tellurstoridaw
DB_USER=postgres
DB_PASSWORD=password

# Blockchain
RPC_URL=http://localhost:8545
STEM_CONTRACT_ADDRESS=0x...
MARKETPLACE_CONTRACT_ADDRESS=0x...

# IPFS
IPFS_API_URL=http://localhost:5001
IPFS_GATEWAY_URL=http://localhost:8080
```

### Docker Configuration

The service includes a complete Docker Compose setup with:
- PostgreSQL database with initialization scripts
- Redis for caching
- IPFS node for decentralized storage
- Prometheus for metrics
- Grafana for dashboards

## 📊 Monitoring & Analytics

### Health Checks
- Database connectivity
- IPFS node status
- Blockchain connection
- Service health endpoint

### Metrics
- Event processing rates
- Database query performance
- IPFS operation metrics
- GraphQL query statistics

### Logging
- Structured JSON logging
- Configurable log levels
- Request/response logging
- Error tracking and alerting

## 🧪 Testing

```bash
# Run tests
npm test

# Run with coverage
npm run test:coverage

# Integration tests
npm run test:integration
```

## 🚀 Deployment

### Development
```bash
npm run dev
```

### Production
```bash
npm start
```

### Docker
```bash
docker-compose up -d
```

### Kubernetes
```bash
kubectl apply -f k8s/
```

## 🔒 Security

- Input validation and sanitization
- Rate limiting on API endpoints
- Secure database connections
- Environment variable protection
- Docker security best practices

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📚 API Documentation

The GraphQL API is self-documenting. Access the GraphQL Playground at:
- Development: `http://localhost:4000/graphql`
- Production: `https://api.tellurstoridaw.com/graphql`

## 🆘 Troubleshooting

### Common Issues

1. **Database Connection Failed**
   ```bash
   # Check PostgreSQL is running
   docker-compose ps postgres
   
   # Check logs
   docker-compose logs postgres
   ```

2. **IPFS Node Not Ready**
   ```bash
   # Restart IPFS service
   docker-compose restart ipfs
   
   # Check IPFS logs
   docker-compose logs ipfs
   ```

3. **Blockchain Connection Issues**
   ```bash
   # Verify RPC URL is accessible
   curl -X POST -H "Content-Type: application/json" \
     --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
     $RPC_URL
   ```

### Performance Optimization

1. **Database Indexing**
   - Ensure proper indexes on frequently queried columns
   - Monitor slow queries with `EXPLAIN ANALYZE`

2. **IPFS Caching**
   - Configure appropriate cache expiration times
   - Monitor cache hit rates

3. **GraphQL Query Optimization**
   - Use DataLoader for N+1 query prevention
   - Implement query complexity analysis

## 📄 License

MIT License - see LICENSE file for details.

---

**Built with ❤️ for the future of decentralized music creation and ownership** 🎵⛓️✨
