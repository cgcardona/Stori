#!/usr/bin/env node

/**
 * 🎵 TellUrStori V2 - Marketplace GraphQL Server
 * 
 * Real-time GraphQL API serving blockchain data for the Swift frontend
 */

import express from 'express';
import cors from 'cors';
import { ethers } from 'ethers';
import fs from 'fs';
import path from 'path';

const app = express();
const port = process.env.PORT || 4000;

// CORS configuration for Swift app
app.use(cors({
  origin: ['http://localhost:3000', 'http://localhost:8080', 'http://localhost:8000', '*'],
  credentials: true
}));

// Body parsing
app.use(express.json());

// Blockchain configuration
const RPC_URL = "http://127.0.0.1:49315/ext/bc/2Y2VATbw3jVSeZmZzb4ydyjwbYjzd5xfU4d7UWqPHQ2QEK1mki/rpc";
const STEM_CONTRACT_ADDRESS = "0x0938Ae5E07A7af37Bfb629AC94fA55B2eDA5E930";
const MARKETPLACE_CONTRACT_ADDRESS = "0x3f772F690AbBBb1F7122eAd83962D7919BFdD729";

// Initialize blockchain connection
let provider;
let stemContract;
let marketplaceContract;

async function initializeBlockchain() {
  try {
    provider = new ethers.JsonRpcProvider(RPC_URL);
    
    // Load contract ABIs
    const stemABI = JSON.parse(fs.readFileSync("../blockchain/artifacts/contracts/TellUrStoriSTEM_Optimized.sol/TellUrStoriSTEM.json", "utf8")).abi;
    const marketplaceABI = JSON.parse(fs.readFileSync("../blockchain/artifacts/contracts/STEMMarketplace_Optimized.sol/STEMMarketplace.json", "utf8")).abi;
    
    stemContract = new ethers.Contract(STEM_CONTRACT_ADDRESS, stemABI, provider);
    marketplaceContract = new ethers.Contract(MARKETPLACE_CONTRACT_ADDRESS, marketplaceABI, provider);
    
    console.log("✅ Blockchain connection initialized");
    console.log(`├── STEM Contract: ${STEM_CONTRACT_ADDRESS}`);
    console.log(`└── Marketplace Contract: ${MARKETPLACE_CONTRACT_ADDRESS}`);
  } catch (error) {
    console.error("❌ Failed to initialize blockchain:", error.message);
  }
}

// Helper function to get STEM metadata
async function getSTEMMetadata(tokenId) {
  try {
    const metadata = await stemContract.getSTEMMetadata(tokenId);
    const totalSupply = await stemContract["totalSupply(uint256)"](tokenId);
    
    return {
      tokenId: tokenId.toString(),
      name: metadata[0], // name
      description: metadata[1], // description  
      creator: metadata[4], // creator
      genre: metadata[7], // genre
      tags: metadata[8], // tags array
      duration: metadata[6].toString(), // duration
      royaltyPercentage: metadata[9].toString(), // royaltyPercentage
      totalSupply: totalSupply.toString(),
      createdAt: new Date(Number(metadata[5]) * 1000).toISOString(), // createdAt
      audioIPFSHash: metadata[2], // audioIPFSHash
      imageIPFSHash: metadata[3] // imageIPFSHash
    };
  } catch (error) {
    console.error(`Error fetching metadata for token ${tokenId}:`, error.message);
    return null;
  }
}

// Helper function to get marketplace listings
async function getMarketplaceListings() {
  try {
    // For now, return mock data based on our populated tokens
    // In a full implementation, this would query actual marketplace events
    return [
      {
        id: "1",
        tokenId: "1",
        seller: "0x2345678901234567890123456789012345678901",
        pricePerToken: ethers.parseEther("2.5").toString(),
        amount: "5",
        active: true,
        createdAt: new Date().toISOString()
      },
      {
        id: "2", 
        tokenId: "12",
        seller: "0x5678901234567890123456789012345678901234",
        pricePerToken: ethers.parseEther("5.0").toString(),
        amount: "3",
        active: true,
        createdAt: new Date().toISOString()
      }
    ];
  } catch (error) {
    console.error("Error fetching marketplace listings:", error.message);
    return [];
  }
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    services: {
      database: false,
      ipfs: false,
      blockchain: provider ? true : false
    },
    contracts: {
      stem: STEM_CONTRACT_ADDRESS,
      marketplace: MARKETPLACE_CONTRACT_ADDRESS
    }
  });
});

// API info endpoint
app.get('/api/info', (req, res) => {
  res.json({
    name: 'TellUrStori V2 Marketplace GraphQL Server',
    version: '1.0.0',
    description: 'Real-time GraphQL API for STEM marketplace data',
    endpoints: {
      health: '/health',
      info: '/api/info',
      graphql: '/graphql'
    },
    network: {
      chainId: 507,
      rpcUrl: RPC_URL,
      contracts: {
        stem: STEM_CONTRACT_ADDRESS,
        marketplace: MARKETPLACE_CONTRACT_ADDRESS
      }
    }
  });
});

// GraphQL endpoint with real blockchain data
app.post('/graphql', async (req, res) => {
  try {
    const { query, variables } = req.body;
    
    // Parse the GraphQL query to determine what data to fetch
    if (query.includes('stems') || query.includes('marketStats')) {
      
      // Get current token count
      const currentTokenId = await stemContract.getCurrentTokenId();
      const tokenCount = Number(currentTokenId) - 1; // Subtract 1 because IDs start at 1
      
      // Fetch metadata for all tokens (limited to first 20 for performance)
      const stems = [];
      const maxTokens = Math.min(tokenCount, 20);
      
      for (let i = 1; i <= maxTokens; i++) {
        const metadata = await getSTEMMetadata(BigInt(i));
        if (metadata) {
          stems.push(metadata);
        }
      }
      
      // Get marketplace listings
      const listings = await getMarketplaceListings();
      
      // Calculate market statistics
      const totalVolume = stems.reduce((sum, stem) => {
        // Mock calculation based on supply * 2 AVAX average
        return sum + (Number(stem.totalSupply) * 2);
      }, 0);
      
      const marketStats = {
        totalVolume: ethers.parseEther(totalVolume.toString()).toString(),
        totalSales: listings.length * 3, // Mock sales data
        averageSalePrice: ethers.parseEther("2.8").toString(),
        activeListings: listings.length,
        activeOffers: 5, // Mock offers
        uniqueTraders: 12, // Mock traders
        floorPrice: ethers.parseEther("0.75").toString(),
        lastUpdated: new Date().toISOString(),
        volume24h: ethers.parseEther("45.2").toString(),
        sales24h: 8,
        volume7d: ethers.parseEther("312.5").toString(),
        sales7d: 47
      };
      
      const stemStats = {
        totalStems: tokenCount,
        totalCreators: 8,
        totalSupply: stems.reduce((sum, stem) => sum + Number(stem.totalSupply), 0).toString(),
        averageDuration: stems.reduce((sum, stem) => sum + Number(stem.duration), 0) / stems.length,
        averageBPM: 120, // Mock BPM data
        genreDistribution: [
          { genre: "Electronic", count: 3 },
          { genre: "Hip Hop", count: 3 },
          { genre: "Pop", count: 3 },
          { genre: "Rock", count: 2 },
          { genre: "Other", count: tokenCount - 11 }
        ],
        lastUpdated: new Date().toISOString()
      };
      
      // Recent activity (mock data based on our populated tokens)
      const recentActivity = stems.slice(0, 10).map((stem, index) => ({
        id: `activity_${index}`,
        type: "MINT",
        tokenId: stem.tokenId,
        stem: stem,
        address: stem.creator,
        timestamp: stem.createdAt,
        transactionHash: `0x${Math.random().toString(16).slice(2, 66)}`
      }));
      
      res.json({
        data: {
          stems: {
            edges: stems.map(stem => ({
              node: stem,
              cursor: `cursor_${stem.tokenId}`
            })),
            pageInfo: {
              hasNextPage: tokenCount > 20,
              hasPreviousPage: false,
              startCursor: stems.length > 0 ? `cursor_${stems[0].tokenId}` : null,
              endCursor: stems.length > 0 ? `cursor_${stems[stems.length - 1].tokenId}` : null
            },
            totalCount: tokenCount
          },
          marketStats,
          stemStats,
          recentActivity,
          listings: {
            edges: listings.map(listing => ({
              node: {
                ...listing,
                stem: stems.find(s => s.tokenId === listing.tokenId)
              },
              cursor: `listing_cursor_${listing.id}`
            })),
            pageInfo: {
              hasNextPage: false,
              hasPreviousPage: false
            },
            totalCount: listings.length
          }
        }
      });
      
    } else {
      // Default response for unknown queries
      res.json({
        data: {
          marketStats: {
            totalVolume: "0",
            totalSales: 0,
            activeListings: 0,
            floorPrice: null,
            lastUpdated: new Date().toISOString()
          }
        }
      });
    }
    
  } catch (error) {
    console.error("GraphQL Error:", error);
    res.status(500).json({
      errors: [{
        message: error.message,
        extensions: {
          code: 'INTERNAL_ERROR'
        }
      }]
    });
  }
});

// GraphQL schema endpoint (for development)
app.get('/graphql', (req, res) => {
  res.send(`
    <html>
      <head><title>TellUrStori V2 GraphQL API</title></head>
      <body>
        <h1>🎵 TellUrStori V2 GraphQL API</h1>
        <p>POST to /graphql with GraphQL queries</p>
        <h2>Example Query:</h2>
        <pre>
{
  marketStats {
    totalVolume
    totalSales
    activeListings
    floorPrice
    lastUpdated
  }
  stems {
    edges {
      node {
        tokenId
        name
        genre
        creator
        totalSupply
      }
    }
  }
}
        </pre>
      </body>
    </html>
  `);
});

// Initialize and start server
async function start() {
  await initializeBlockchain();
  
  app.listen(port, () => {
    console.log(`🚀 TellUrStori V2 Marketplace GraphQL Server running on port ${port}`);
    console.log(`📡 Health endpoint: http://localhost:${port}/health`);
    console.log(`🔧 GraphQL endpoint: http://localhost:${port}/graphql`);
    console.log(`📊 Network: TellUrStori L1 (Chain ID: 507)`);
    console.log(`🎵 Ready to serve real blockchain data to Swift frontend!`);
  });
}

start().catch(console.error);
