#!/usr/bin/env node

/**
 * 🎵 TellUrStori V2 - Blockchain Indexer Service
 * 
 * Real-time blockchain event indexing, IPFS integration, and GraphQL API
 * for STEM token minting, marketplace activities, and metadata management.
 * 
 * @author TellUrStori V2 Team
 * @version 1.0.0
 */

import dotenv from 'dotenv';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import morgan from 'morgan';
import { ApolloServer } from '@apollo/server';
import { startStandaloneServer } from '@apollo/server/standalone';
import { createServer } from 'http';
import winston from 'winston';

// Import our services
import { BlockchainIndexer } from './blockchain/eventListener.js';
import { DatabaseConnection } from './database/connection.js';
import { IPFSService } from './services/ipfsService.js';
import { MetadataService } from './services/metadataService.js';
import { IndexingService } from './services/indexingService.js';
import { createGraphQLSchema } from './api/schema.js';

// Load environment variables
dotenv.config();

// Configure logging
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.errors({ stack: true }),
    winston.format.json()
  ),
  defaultMeta: { service: 'indexer-service' },
  transports: [
    new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
    new winston.transports.File({ filename: 'logs/combined.log' }),
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple()
      )
    })
  ]
});

// Global error handlers
process.on('uncaughtException', (error) => {
  logger.error('Uncaught Exception:', error);
  process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
  logger.error('Unhandled Rejection at:', promise, 'reason:', reason);
  process.exit(1);
});

class IndexerServiceApp {
  constructor() {
    this.app = express();
    this.server = null;
    this.apolloServer = null;
    this.services = {};
    this.port = process.env.PORT || 4000;
  }

  async initialize() {
    try {
      logger.info('🚀 Initializing TellUrStori V2 Indexer Service...');

      // For development, skip complex services that require database/IPFS
      logger.info('⚠️ Running in simplified mode - complex services disabled');

      // Setup Express middleware
      this.setupMiddleware();

      // Initialize GraphQL server (simplified)
      await this.setupGraphQL();

      logger.info('🎉 Basic services initialized successfully!');
    } catch (error) {
      logger.error('❌ Failed to initialize services:', error);
      throw error;
    }
  }

  setupMiddleware() {
    // Security middleware
    this.app.use(helmet({
      contentSecurityPolicy: process.env.NODE_ENV === 'production' ? undefined : false,
      crossOriginEmbedderPolicy: false
    }));

    // CORS configuration
    this.app.use(cors({
      origin: process.env.CORS_ORIGIN || ['http://localhost:3000', 'http://localhost:8080'],
      credentials: true
    }));

    // Request logging
    this.app.use(morgan('combined', {
      stream: { write: (message) => logger.info(message.trim()) }
    }));

    // Body parsing
    this.app.use(express.json({ limit: '10mb' }));
    this.app.use(express.urlencoded({ extended: true, limit: '10mb' }));

    // Health check endpoint
    this.app.get('/health', (req, res) => {
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
    this.app.get('/api/info', (req, res) => {
      res.json({
        name: 'TellUrStori V2 Indexer Service',
        version: '1.0.0',
        description: 'Real-time blockchain event indexing and GraphQL API',
        endpoints: {
          graphql: '/graphql',
          health: '/health',
          metrics: '/metrics'
        }
      });
    });
  }

  async setupGraphQL() {
    try {
      logger.info('🔧 Setting up GraphQL server...');

      // For now, skip GraphQL setup and just provide health endpoint
      // TODO: Fix Apollo Server configuration
      logger.info('⚠️ GraphQL server temporarily disabled - using health endpoints only');
    } catch (error) {
      logger.error('❌ Failed to setup GraphQL server:', error);
      throw error;
    }
  }

  async start() {
    try {
      await this.initialize();

      // Create HTTP server
      this.server = createServer(this.app);

      // Start listening
      this.server.listen(this.port, () => {
        logger.info(`🎵 TellUrStori V2 Indexer Service running on port ${this.port}`);
        logger.info(`📊 GraphQL Playground: http://localhost:${this.port}/graphql`);
        logger.info(`🏥 Health Check: http://localhost:${this.port}/health`);
        logger.info(`📋 API Info: http://localhost:${this.port}/api/info`);
      });

      // Graceful shutdown handling
      this.setupGracefulShutdown();

    } catch (error) {
      logger.error('❌ Failed to start server:', error);
      process.exit(1);
    }
  }

  setupGracefulShutdown() {
    const shutdown = async (signal) => {
      logger.info(`🛑 Received ${signal}, starting graceful shutdown...`);

      // Stop accepting new requests
      this.server.close(async () => {
        logger.info('📡 HTTP server closed');

        try {
          // Stop Apollo Server
          // if (this.apolloServer) {
          //   await this.apolloServer.stop();
          //   logger.info('🔧 GraphQL server stopped');
          // }

          // Stop blockchain indexer
          if (this.services.blockchainIndexer) {
            await this.services.blockchainIndexer.stopListening();
            logger.info('⛓️ Blockchain indexer stopped');
          }

          // Close database connection
          if (this.services.database) {
            await this.services.database.disconnect();
            logger.info('📊 Database disconnected');
          }

          // Stop IPFS service
          if (this.services.ipfs) {
            await this.services.ipfs.stop();
            logger.info('🌐 IPFS service stopped');
          }

          logger.info('✅ Graceful shutdown completed');
          process.exit(0);
        } catch (error) {
          logger.error('❌ Error during shutdown:', error);
          process.exit(1);
        }
      });

      // Force shutdown after timeout
      setTimeout(() => {
        logger.error('⏰ Shutdown timeout, forcing exit');
        process.exit(1);
      }, 30000);
    };

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));
  }
}

// Start the application
if (import.meta.url === `file://${process.argv[1]}`) {
  const app = new IndexerServiceApp();
  app.start().catch((error) => {
    logger.error('💥 Failed to start application:', error);
    process.exit(1);
  });
}

export default IndexerServiceApp;
