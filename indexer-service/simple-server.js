#!/usr/bin/env node

/**
 * 🎵 TellUrStori V2 - Simple Indexer Service
 * 
 * Minimal health check server for development
 */

import express from 'express';
import cors from 'cors';

const app = express();
const port = process.env.PORT || 4000;

// CORS configuration
app.use(cors({
  origin: ['http://localhost:3000', 'http://localhost:8080', 'http://localhost:8000'],
  credentials: true
}));

// Body parsing
app.use(express.json());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    services: {
      database: false, // Disabled in development
      ipfs: false,     // Disabled in development  
      blockchain: true // Assume blockchain is available
    }
  });
});

// API info endpoint
app.get('/api/info', (req, res) => {
  res.json({
    name: 'TellUrStori V2 Indexer Service (Simple)',
    version: '1.0.0',
    description: 'Minimal health check service for development',
    endpoints: {
      health: '/health',
      info: '/api/info'
    }
  });
});

// Basic GraphQL endpoint (returns empty data for now)
app.post('/graphql', (req, res) => {
  res.json({
    data: {
      marketStats: {
        totalVolume: "0",
        totalSales: 0,
        activeListings: 0,
        floorPrice: null,
        lastUpdated: new Date().toISOString()
      },
      stemStats: {
        totalStems: 0,
        totalCreators: 0,
        totalSupply: 0,
        averageDuration: 0,
        averageBpm: 0
      }
    }
  });
});

// Start server
app.listen(port, () => {
  console.log(`🚀 TellUrStori V2 Simple Indexer Service running on port ${port}`);
  console.log(`📡 Health endpoint: http://localhost:${port}/health`);
  console.log(`🔧 GraphQL endpoint: http://localhost:${port}/graphql`);
});
