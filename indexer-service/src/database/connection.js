/**
 * 🎵 TellUrStori V2 - Database Connection
 * 
 * PostgreSQL database connection and management for blockchain indexing data.
 */

import pg from 'pg';
import winston from 'winston';

const { Pool } = pg;

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  defaultMeta: { service: 'database' }
});

export class DatabaseConnection {
  constructor(config = {}) {
    this.config = {
      host: process.env.DB_HOST || 'localhost',
      port: parseInt(process.env.DB_PORT) || 5432,
      database: process.env.DB_NAME || 'tellurstoridaw',
      user: process.env.DB_USER || 'postgres',
      password: process.env.DB_PASSWORD || 'password',
      ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
      max: parseInt(process.env.DB_POOL_MAX) || 20,
      idleTimeoutMillis: parseInt(process.env.DB_IDLE_TIMEOUT) || 30000,
      connectionTimeoutMillis: parseInt(process.env.DB_CONNECTION_TIMEOUT) || 2000,
      ...config
    };
    
    this.pool = null;
    this.connected = false;
  }

  async connect() {
    try {
      logger.info('📊 Connecting to PostgreSQL database...', {
        host: this.config.host,
        port: this.config.port,
        database: this.config.database,
        user: this.config.user
      });

      this.pool = new Pool(this.config);

      // Test connection
      const client = await this.pool.connect();
      const result = await client.query('SELECT NOW() as current_time, version() as version');
      client.release();

      logger.info('✅ Database connected successfully', {
        currentTime: result.rows[0].current_time,
        version: result.rows[0].version.split(' ')[0]
      });

      this.connected = true;
      
      // Set up error handling
      this.pool.on('error', (err) => {
        logger.error('❌ Database pool error:', err);
        this.connected = false;
      });

      return true;
    } catch (error) {
      logger.error('❌ Failed to connect to database:', error);
      throw error;
    }
  }

  async disconnect() {
    if (this.pool) {
      try {
        logger.info('🔌 Disconnecting from database...');
        await this.pool.end();
        this.connected = false;
        logger.info('✅ Database disconnected');
      } catch (error) {
        logger.error('❌ Error disconnecting from database:', error);
        throw error;
      }
    }
  }

  async query(text, params = []) {
    if (!this.connected) {
      throw new Error('Database not connected');
    }

    try {
      const start = Date.now();
      const result = await this.pool.query(text, params);
      const duration = Date.now() - start;
      
      logger.debug('📊 Database query executed', {
        query: text.substring(0, 100) + (text.length > 100 ? '...' : ''),
        duration: `${duration}ms`,
        rows: result.rowCount
      });
      
      return result;
    } catch (error) {
      logger.error('❌ Database query error:', {
        query: text,
        params,
        error: error.message
      });
      throw error;
    }
  }

  async transaction(callback) {
    if (!this.connected) {
      throw new Error('Database not connected');
    }

    const client = await this.pool.connect();
    
    try {
      await client.query('BEGIN');
      const result = await callback(client);
      await client.query('COMMIT');
      return result;
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  async createTables() {
    try {
      logger.info('🏗️ Creating database tables...');

      // Create stems table
      await this.query(`
        CREATE TABLE IF NOT EXISTS stems (
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
          format VARCHAR(10),
          sample_rate INTEGER,
          bit_depth INTEGER,
          channels INTEGER,
          total_supply NUMERIC(78, 0) DEFAULT 0,
          contract_address VARCHAR(42),
          chain_id INTEGER,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          block_number BIGINT,
          transaction_hash VARCHAR(66),
          log_index INTEGER
        );
      `);

      // Create transfers table
      await this.query(`
        CREATE TABLE IF NOT EXISTS transfers (
          id SERIAL PRIMARY KEY,
          token_id VARCHAR(255) NOT NULL,
          from_address VARCHAR(42),
          to_address VARCHAR(42) NOT NULL,
          operator_address VARCHAR(42),
          amount NUMERIC(78, 0) NOT NULL,
          transaction_hash VARCHAR(66) NOT NULL,
          block_number BIGINT NOT NULL,
          log_index INTEGER NOT NULL,
          timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          UNIQUE(transaction_hash, log_index)
        );
      `);

      // Create listings table
      await this.query(`
        CREATE TABLE IF NOT EXISTS listings (
          id SERIAL PRIMARY KEY,
          listing_id VARCHAR(255) NOT NULL UNIQUE,
          seller_address VARCHAR(42) NOT NULL,
          token_id VARCHAR(255) NOT NULL,
          amount NUMERIC(78, 0) NOT NULL,
          price_per_token NUMERIC(78, 0) NOT NULL,
          total_price NUMERIC(78, 0) NOT NULL,
          expiration TIMESTAMP WITH TIME ZONE,
          active BOOLEAN DEFAULT true,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          block_number BIGINT NOT NULL,
          transaction_hash VARCHAR(66) NOT NULL,
          log_index INTEGER NOT NULL
        );
      `);

      // Create sales table
      await this.query(`
        CREATE TABLE IF NOT EXISTS sales (
          id SERIAL PRIMARY KEY,
          listing_id VARCHAR(255) NOT NULL,
          buyer_address VARCHAR(42) NOT NULL,
          seller_address VARCHAR(42) NOT NULL,
          token_id VARCHAR(255) NOT NULL,
          amount NUMERIC(78, 0) NOT NULL,
          price_per_token NUMERIC(78, 0) NOT NULL,
          total_price NUMERIC(78, 0) NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          block_number BIGINT NOT NULL,
          transaction_hash VARCHAR(66) NOT NULL,
          log_index INTEGER NOT NULL,
          UNIQUE(transaction_hash, log_index)
        );
      `);

      // Create offers table
      await this.query(`
        CREATE TABLE IF NOT EXISTS offers (
          id SERIAL PRIMARY KEY,
          offer_id VARCHAR(255) NOT NULL UNIQUE,
          listing_id VARCHAR(255) NOT NULL,
          buyer_address VARCHAR(42) NOT NULL,
          amount NUMERIC(78, 0) NOT NULL,
          price_per_token NUMERIC(78, 0) NOT NULL,
          total_price NUMERIC(78, 0) NOT NULL,
          expiration TIMESTAMP WITH TIME ZONE,
          status VARCHAR(20) DEFAULT 'active',
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          block_number BIGINT NOT NULL,
          transaction_hash VARCHAR(66) NOT NULL,
          log_index INTEGER NOT NULL
        );
      `);

      // Create auctions table
      await this.query(`
        CREATE TABLE IF NOT EXISTS auctions (
          id SERIAL PRIMARY KEY,
          auction_id VARCHAR(255) NOT NULL UNIQUE,
          seller_address VARCHAR(42) NOT NULL,
          token_id VARCHAR(255) NOT NULL,
          amount NUMERIC(78, 0) NOT NULL,
          starting_bid NUMERIC(78, 0) NOT NULL,
          current_bid NUMERIC(78, 0) DEFAULT 0,
          current_bidder VARCHAR(42),
          end_time TIMESTAMP WITH TIME ZONE NOT NULL,
          status VARCHAR(20) DEFAULT 'active',
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          block_number BIGINT NOT NULL,
          transaction_hash VARCHAR(66) NOT NULL,
          log_index INTEGER NOT NULL
        );
      `);

      // Create bids table
      await this.query(`
        CREATE TABLE IF NOT EXISTS bids (
          id SERIAL PRIMARY KEY,
          auction_id VARCHAR(255) NOT NULL,
          bidder_address VARCHAR(42) NOT NULL,
          bid_amount NUMERIC(78, 0) NOT NULL,
          created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          block_number BIGINT NOT NULL,
          transaction_hash VARCHAR(66) NOT NULL,
          log_index INTEGER NOT NULL,
          UNIQUE(transaction_hash, log_index)
        );
      `);

      // Create metadata_cache table
      await this.query(`
        CREATE TABLE IF NOT EXISTS metadata_cache (
          id SERIAL PRIMARY KEY,
          cid VARCHAR(255) NOT NULL UNIQUE,
          content_type VARCHAR(50) NOT NULL,
          data JSONB NOT NULL,
          cached_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
          expires_at TIMESTAMP WITH TIME ZONE,
          access_count INTEGER DEFAULT 0,
          last_accessed TIMESTAMP WITH TIME ZONE DEFAULT NOW()
        );
      `);

      // Create indexes for better performance
      await this.createIndexes();

      logger.info('✅ Database tables created successfully');
    } catch (error) {
      logger.error('❌ Failed to create database tables:', error);
      throw error;
    }
  }

  async createIndexes() {
    const indexes = [
      // Stems indexes
      'CREATE INDEX IF NOT EXISTS idx_stems_token_id ON stems(token_id)',
      'CREATE INDEX IF NOT EXISTS idx_stems_creator ON stems(creator_address)',
      'CREATE INDEX IF NOT EXISTS idx_stems_created_at ON stems(created_at)',
      'CREATE INDEX IF NOT EXISTS idx_stems_stem_type ON stems(stem_type)',
      'CREATE INDEX IF NOT EXISTS idx_stems_genre ON stems(genre)',
      
      // Transfers indexes
      'CREATE INDEX IF NOT EXISTS idx_transfers_token_id ON transfers(token_id)',
      'CREATE INDEX IF NOT EXISTS idx_transfers_from ON transfers(from_address)',
      'CREATE INDEX IF NOT EXISTS idx_transfers_to ON transfers(to_address)',
      'CREATE INDEX IF NOT EXISTS idx_transfers_block ON transfers(block_number)',
      'CREATE INDEX IF NOT EXISTS idx_transfers_timestamp ON transfers(timestamp)',
      
      // Listings indexes
      'CREATE INDEX IF NOT EXISTS idx_listings_token_id ON listings(token_id)',
      'CREATE INDEX IF NOT EXISTS idx_listings_seller ON listings(seller_address)',
      'CREATE INDEX IF NOT EXISTS idx_listings_active ON listings(active)',
      'CREATE INDEX IF NOT EXISTS idx_listings_expiration ON listings(expiration)',
      'CREATE INDEX IF NOT EXISTS idx_listings_price ON listings(price_per_token)',
      
      // Sales indexes
      'CREATE INDEX IF NOT EXISTS idx_sales_token_id ON sales(token_id)',
      'CREATE INDEX IF NOT EXISTS idx_sales_buyer ON sales(buyer_address)',
      'CREATE INDEX IF NOT EXISTS idx_sales_seller ON sales(seller_address)',
      'CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at)',
      'CREATE INDEX IF NOT EXISTS idx_sales_total_price ON sales(total_price)',
      
      // Offers indexes
      'CREATE INDEX IF NOT EXISTS idx_offers_listing_id ON offers(listing_id)',
      'CREATE INDEX IF NOT EXISTS idx_offers_buyer ON offers(buyer_address)',
      'CREATE INDEX IF NOT EXISTS idx_offers_status ON offers(status)',
      'CREATE INDEX IF NOT EXISTS idx_offers_expiration ON offers(expiration)',
      
      // Auctions indexes
      'CREATE INDEX IF NOT EXISTS idx_auctions_token_id ON auctions(token_id)',
      'CREATE INDEX IF NOT EXISTS idx_auctions_seller ON auctions(seller_address)',
      'CREATE INDEX IF NOT EXISTS idx_auctions_status ON auctions(status)',
      'CREATE INDEX IF NOT EXISTS idx_auctions_end_time ON auctions(end_time)',
      
      // Bids indexes
      'CREATE INDEX IF NOT EXISTS idx_bids_auction_id ON bids(auction_id)',
      'CREATE INDEX IF NOT EXISTS idx_bids_bidder ON bids(bidder_address)',
      'CREATE INDEX IF NOT EXISTS idx_bids_created_at ON bids(created_at)',
      
      // Metadata cache indexes
      'CREATE INDEX IF NOT EXISTS idx_metadata_cache_cid ON metadata_cache(cid)',
      'CREATE INDEX IF NOT EXISTS idx_metadata_cache_type ON metadata_cache(content_type)',
      'CREATE INDEX IF NOT EXISTS idx_metadata_cache_expires ON metadata_cache(expires_at)'
    ];

    for (const indexQuery of indexes) {
      try {
        await this.query(indexQuery);
      } catch (error) {
        logger.warn('⚠️ Failed to create index:', { query: indexQuery, error: error.message });
      }
    }

    logger.info('✅ Database indexes created');
  }

  isConnected() {
    return this.connected;
  }

  getPool() {
    return this.pool;
  }
}
