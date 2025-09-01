/**
 * 🎵 TellUrStori V2 - Indexing Service
 * 
 * Processes blockchain events and stores indexed data in PostgreSQL database.
 * Handles STEM minting, transfers, marketplace activities, and metadata updates.
 */

import winston from 'winston';

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  defaultMeta: { service: 'indexing-service' }
});

export class IndexingService {
  constructor(database, metadataService) {
    this.db = database;
    this.metadataService = metadataService;
  }

  /**
   * Process STEM minted event
   * @param {Object} event - STEMMinted event data
   */
  async processStemMintedEvent(event) {
    try {
      logger.info('🎵 Processing STEM minted event', { tokenId: event.tokenId });

      await this.db.transaction(async (client) => {
        // Check if STEM already exists
        const existingResult = await client.query(
          'SELECT id FROM stems WHERE token_id = $1',
          [event.tokenId]
        );

        if (existingResult.rows.length > 0) {
          logger.warn('⚠️ STEM already exists, skipping', { tokenId: event.tokenId });
          return;
        }

        // Fetch and cache metadata
        let metadata = {};
        if (event.metadataURI) {
          try {
            metadata = await this.metadataService.fetchAndCacheMetadata(event.metadataURI);
          } catch (error) {
            logger.warn('⚠️ Failed to fetch metadata, continuing without it', { 
              tokenId: event.tokenId, 
              error: error.message 
            });
          }
        }

        // Insert STEM record
        await client.query(`
          INSERT INTO stems (
            token_id, creator_address, name, description, metadata_uri, metadata_cid,
            audio_cid, image_cid, stem_type, duration, bpm, key, genre, format,
            sample_rate, bit_depth, channels, total_supply, contract_address,
            block_number, transaction_hash, log_index, created_at
          ) VALUES (
            $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22,
            TO_TIMESTAMP($23)
          )
        `, [
          event.tokenId,
          event.creator,
          metadata.name || null,
          metadata.description || null,
          event.metadataURI || null,
          metadata.metadata_cid || null,
          metadata.audio_cid || null,
          metadata.image_cid || null,
          metadata.stem_type || null,
          metadata.duration || null,
          metadata.bpm || null,
          metadata.key || null,
          metadata.genre || null,
          metadata.format || null,
          metadata.sample_rate || null,
          metadata.bit_depth || null,
          metadata.channels || null,
          event.amount,
          event.contractAddress || null,
          event.blockNumber,
          event.transactionHash,
          event.logIndex,
          parseInt(event.timestamp)
        ]);

        // Record initial transfer (mint)
        await client.query(`
          INSERT INTO transfers (
            token_id, from_address, to_address, operator_address, amount,
            transaction_hash, block_number, log_index, timestamp
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, TO_TIMESTAMP($9))
        `, [
          event.tokenId,
          '0x0000000000000000000000000000000000000000', // from zero address (mint)
          event.creator,
          event.creator, // operator is creator for minting
          event.amount,
          event.transactionHash,
          event.blockNumber,
          event.logIndex,
          parseInt(event.timestamp)
        ]);
      });

      logger.info('✅ STEM minted event processed successfully', { tokenId: event.tokenId });
    } catch (error) {
      logger.error('❌ Failed to process STEM minted event:', error);
      throw error;
    }
  }

  /**
   * Process transfer event
   * @param {Object} event - Transfer event data
   */
  async processTransferEvent(event) {
    try {
      logger.info('📤 Processing transfer event', { 
        tokenId: event.tokenId, 
        from: event.from, 
        to: event.to 
      });

      await this.db.transaction(async (client) => {
        // Check for duplicate
        const existingResult = await client.query(
          'SELECT id FROM transfers WHERE transaction_hash = $1 AND log_index = $2',
          [event.transactionHash, event.logIndex]
        );

        if (existingResult.rows.length > 0) {
          logger.warn('⚠️ Transfer already processed, skipping', { 
            transactionHash: event.transactionHash,
            logIndex: event.logIndex
          });
          return;
        }

        // Insert transfer record
        await client.query(`
          INSERT INTO transfers (
            token_id, from_address, to_address, operator_address, amount,
            transaction_hash, block_number, log_index
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        `, [
          event.tokenId,
          event.from,
          event.to,
          event.operator,
          event.amount,
          event.transactionHash,
          event.blockNumber,
          event.logIndex
        ]);

        // Update STEM total supply if this is not a mint/burn
        if (event.from !== '0x0000000000000000000000000000000000000000' && 
            event.to !== '0x0000000000000000000000000000000000000000') {
          // This is a regular transfer, no supply change needed
        } else if (event.from === '0x0000000000000000000000000000000000000000') {
          // This is a mint, increase supply
          await client.query(
            'UPDATE stems SET total_supply = total_supply + $1 WHERE token_id = $2',
            [event.amount, event.tokenId]
          );
        } else if (event.to === '0x0000000000000000000000000000000000000000') {
          // This is a burn, decrease supply
          await client.query(
            'UPDATE stems SET total_supply = total_supply - $1 WHERE token_id = $2',
            [event.amount, event.tokenId]
          );
        }
      });

      logger.info('✅ Transfer event processed successfully', { 
        tokenId: event.tokenId,
        transactionHash: event.transactionHash
      });
    } catch (error) {
      logger.error('❌ Failed to process transfer event:', error);
      throw error;
    }
  }

  /**
   * Process metadata updated event
   * @param {Object} event - Metadata updated event data
   */
  async processMetadataUpdatedEvent(event) {
    try {
      logger.info('📝 Processing metadata updated event', { tokenId: event.tokenId });

      await this.db.query(`
        UPDATE stems 
        SET name = $1, description = $2, updated_at = NOW()
        WHERE token_id = $3
      `, [
        event.newName,
        event.newDescription,
        event.tokenId
      ]);

      logger.info('✅ Metadata updated event processed successfully', { tokenId: event.tokenId });
    } catch (error) {
      logger.error('❌ Failed to process metadata updated event:', error);
      throw error;
    }
  }

  /**
   * Process listing created event
   * @param {Object} event - Listed event data
   */
  async processListedEvent(event) {
    try {
      logger.info('🏷️ Processing listed event', { listingId: event.listingId });

      await this.db.transaction(async (client) => {
        // Check if listing already exists
        const existingResult = await client.query(
          'SELECT id FROM listings WHERE listing_id = $1',
          [event.listingId]
        );

        if (existingResult.rows.length > 0) {
          logger.warn('⚠️ Listing already exists, skipping', { listingId: event.listingId });
          return;
        }

        // Insert listing record
        await client.query(`
          INSERT INTO listings (
            listing_id, seller_address, token_id, amount, price_per_token,
            total_price, expiration, block_number, transaction_hash, log_index
          ) VALUES ($1, $2, $3, $4, $5, $6, TO_TIMESTAMP($7), $8, $9, $10)
        `, [
          event.listingId,
          event.seller,
          event.tokenId,
          event.amount,
          event.pricePerToken,
          BigInt(event.amount) * BigInt(event.pricePerToken),
          parseInt(event.expiration),
          event.blockNumber,
          event.transactionHash,
          event.logIndex
        ]);
      });

      logger.info('✅ Listed event processed successfully', { listingId: event.listingId });
    } catch (error) {
      logger.error('❌ Failed to process listed event:', error);
      throw error;
    }
  }

  /**
   * Process sale event
   * @param {Object} event - Sold event data
   */
  async processSoldEvent(event) {
    try {
      logger.info('💰 Processing sold event', { listingId: event.listingId });

      await this.db.transaction(async (client) => {
        // Check for duplicate
        const existingResult = await client.query(
          'SELECT id FROM sales WHERE transaction_hash = $1 AND log_index = $2',
          [event.transactionHash, event.logIndex]
        );

        if (existingResult.rows.length > 0) {
          logger.warn('⚠️ Sale already processed, skipping', { 
            transactionHash: event.transactionHash,
            logIndex: event.logIndex
          });
          return;
        }

        // Get listing details
        const listingResult = await client.query(
          'SELECT seller_address, token_id, price_per_token FROM listings WHERE listing_id = $1',
          [event.listingId]
        );

        if (listingResult.rows.length === 0) {
          throw new Error(`Listing not found: ${event.listingId}`);
        }

        const listing = listingResult.rows[0];

        // Insert sale record
        await client.query(`
          INSERT INTO sales (
            listing_id, buyer_address, seller_address, token_id, amount,
            price_per_token, total_price, block_number, transaction_hash, log_index
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
        `, [
          event.listingId,
          event.buyer,
          listing.seller_address,
          listing.token_id,
          event.amount,
          listing.price_per_token,
          event.totalPrice,
          event.blockNumber,
          event.transactionHash,
          event.logIndex
        ]);

        // Update listing (reduce amount or deactivate)
        await client.query(`
          UPDATE listings 
          SET amount = amount - $1, 
              active = CASE WHEN amount - $1 <= 0 THEN false ELSE active END,
              updated_at = NOW()
          WHERE listing_id = $2
        `, [event.amount, event.listingId]);
      });

      logger.info('✅ Sold event processed successfully', { listingId: event.listingId });
    } catch (error) {
      logger.error('❌ Failed to process sold event:', error);
      throw error;
    }
  }

  /**
   * Process offer made event
   * @param {Object} event - OfferMade event data
   */
  async processOfferMadeEvent(event) {
    try {
      logger.info('💡 Processing offer made event', { offerId: event.offerId });

      await this.db.transaction(async (client) => {
        // Check if offer already exists
        const existingResult = await client.query(
          'SELECT id FROM offers WHERE offer_id = $1',
          [event.offerId]
        );

        if (existingResult.rows.length > 0) {
          logger.warn('⚠️ Offer already exists, skipping', { offerId: event.offerId });
          return;
        }

        // Insert offer record
        await client.query(`
          INSERT INTO offers (
            offer_id, listing_id, buyer_address, amount, price_per_token,
            total_price, expiration, block_number, transaction_hash, log_index
          ) VALUES ($1, $2, $3, $4, $5, $6, TO_TIMESTAMP($7), $8, $9, $10)
        `, [
          event.offerId,
          event.listingId,
          event.buyer,
          event.amount,
          event.pricePerToken,
          BigInt(event.amount) * BigInt(event.pricePerToken),
          parseInt(event.expiration),
          event.blockNumber,
          event.transactionHash,
          event.logIndex
        ]);
      });

      logger.info('✅ Offer made event processed successfully', { offerId: event.offerId });
    } catch (error) {
      logger.error('❌ Failed to process offer made event:', error);
      throw error;
    }
  }

  /**
   * Get processing statistics
   * @returns {Promise<Object>} Processing stats
   */
  async getProcessingStats() {
    try {
      const [stemsResult, transfersResult, listingsResult, salesResult, offersResult] = await Promise.all([
        this.db.query('SELECT COUNT(*) as count FROM stems'),
        this.db.query('SELECT COUNT(*) as count FROM transfers'),
        this.db.query('SELECT COUNT(*) as count FROM listings'),
        this.db.query('SELECT COUNT(*) as count FROM sales'),
        this.db.query('SELECT COUNT(*) as count FROM offers')
      ]);

      return {
        stems: parseInt(stemsResult.rows[0].count),
        transfers: parseInt(transfersResult.rows[0].count),
        listings: parseInt(listingsResult.rows[0].count),
        sales: parseInt(salesResult.rows[0].count),
        offers: parseInt(offersResult.rows[0].count),
        timestamp: new Date().toISOString()
      };
    } catch (error) {
      logger.error('❌ Failed to get processing stats:', error);
      throw error;
    }
  }

  /**
   * Get recent activity
   * @param {number} limit - Number of recent activities to return
   * @returns {Promise<Array>} Recent activities
   */
  async getRecentActivity(limit = 50) {
    try {
      const result = await this.db.query(`
        (
          SELECT 'mint' as type, token_id, creator_address as address, 
                 created_at as timestamp, transaction_hash, block_number
          FROM stems
          ORDER BY created_at DESC
          LIMIT $1
        )
        UNION ALL
        (
          SELECT 'transfer' as type, token_id, to_address as address,
                 timestamp, transaction_hash, block_number
          FROM transfers
          WHERE from_address != '0x0000000000000000000000000000000000000000'
          ORDER BY timestamp DESC
          LIMIT $1
        )
        UNION ALL
        (
          SELECT 'listing' as type, token_id, seller_address as address,
                 created_at as timestamp, transaction_hash, block_number
          FROM listings
          ORDER BY created_at DESC
          LIMIT $1
        )
        UNION ALL
        (
          SELECT 'sale' as type, token_id, buyer_address as address,
                 created_at as timestamp, transaction_hash, block_number
          FROM sales
          ORDER BY created_at DESC
          LIMIT $1
        )
        ORDER BY timestamp DESC
        LIMIT $1
      `, [limit]);

      return result.rows;
    } catch (error) {
      logger.error('❌ Failed to get recent activity:', error);
      throw error;
    }
  }
}
