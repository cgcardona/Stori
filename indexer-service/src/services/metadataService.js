/**
 * 🎵 TellUrStori V2 - Metadata Service
 * 
 * Handles fetching, caching, and processing of STEM token metadata from IPFS.
 * Provides intelligent caching and metadata enrichment capabilities.
 */

import winston from 'winston';

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  defaultMeta: { service: 'metadata-service' }
});

export class MetadataService {
  constructor(ipfsService, database) {
    this.ipfs = ipfsService;
    this.db = database;
    this.cacheTimeout = 24 * 60 * 60 * 1000; // 24 hours in milliseconds
  }

  /**
   * Fetch and cache metadata from IPFS URI
   * @param {string} metadataURI - IPFS URI (ipfs://... or https://...)
   * @returns {Promise<Object>} Metadata object
   */
  async fetchAndCacheMetadata(metadataURI) {
    try {
      logger.info('📋 Fetching metadata', { uri: metadataURI });

      // Extract CID from URI
      const cid = this.extractCIDFromURI(metadataURI);
      if (!cid) {
        throw new Error(`Invalid metadata URI: ${metadataURI}`);
      }

      // Check cache first
      const cachedMetadata = await this.getCachedMetadata(cid);
      if (cachedMetadata) {
        logger.info('✅ Metadata found in cache', { cid });
        await this.updateCacheAccess(cid);
        return cachedMetadata;
      }

      // Fetch from IPFS
      const metadata = await this.fetchMetadataFromIPFS(cid);
      
      // Enrich metadata with additional processing
      const enrichedMetadata = await this.enrichMetadata(metadata);

      // Cache the metadata
      await this.cacheMetadata(cid, enrichedMetadata);

      logger.info('✅ Metadata fetched and cached', { cid });
      return enrichedMetadata;
    } catch (error) {
      logger.error('❌ Failed to fetch metadata:', error);
      throw error;
    }
  }

  /**
   * Extract CID from various URI formats
   * @param {string} uri - IPFS URI
   * @returns {string|null} CID or null if invalid
   */
  extractCIDFromURI(uri) {
    if (!uri) return null;

    // Handle ipfs:// protocol
    if (uri.startsWith('ipfs://')) {
      return uri.replace('ipfs://', '');
    }

    // Handle IPFS gateway URLs
    const gatewayPatterns = [
      /https?:\/\/ipfs\.io\/ipfs\/([a-zA-Z0-9]+)/,
      /https?:\/\/gateway\.ipfs\.io\/ipfs\/([a-zA-Z0-9]+)/,
      /https?:\/\/[^\/]+\/ipfs\/([a-zA-Z0-9]+)/
    ];

    for (const pattern of gatewayPatterns) {
      const match = uri.match(pattern);
      if (match) {
        return match[1];
      }
    }

    // If it looks like a raw CID
    if (/^[a-zA-Z0-9]{46,}$/.test(uri)) {
      return uri;
    }

    return null;
  }

  /**
   * Fetch metadata from IPFS
   * @param {string} cid - IPFS CID
   * @returns {Promise<Object>} Metadata object
   */
  async fetchMetadataFromIPFS(cid) {
    try {
      logger.info('🌐 Fetching metadata from IPFS', { cid });

      // Try to fetch as JSON first
      try {
        const metadata = await this.ipfs.downloadJSON(cid);
        return metadata;
      } catch (jsonError) {
        logger.warn('⚠️ Failed to fetch as JSON, trying as raw data', { cid });
        
        // Try to fetch as raw data and parse
        const rawData = await this.ipfs.downloadFile(cid);
        const textData = new TextDecoder().decode(rawData);
        
        try {
          return JSON.parse(textData);
        } catch (parseError) {
          throw new Error(`Failed to parse metadata as JSON: ${parseError.message}`);
        }
      }
    } catch (error) {
      logger.error('❌ Failed to fetch metadata from IPFS:', error);
      throw error;
    }
  }

  /**
   * Enrich metadata with additional processing
   * @param {Object} metadata - Raw metadata
   * @returns {Promise<Object>} Enriched metadata
   */
  async enrichMetadata(metadata) {
    try {
      const enriched = { ...metadata };

      // Extract audio CID from audio_url if present
      if (metadata.audio_url) {
        enriched.audio_cid = this.extractCIDFromURI(metadata.audio_url);
      }

      // Extract image CID from image if present
      if (metadata.image) {
        enriched.image_cid = this.extractCIDFromURI(metadata.image);
      }

      // Normalize stem type
      if (metadata.stem_type) {
        enriched.stem_type = this.normalizeStemType(metadata.stem_type);
      }

      // Validate and normalize BPM
      if (metadata.bpm) {
        const bpm = parseInt(metadata.bpm);
        if (bpm > 0 && bpm <= 300) {
          enriched.bpm = bpm;
        }
      }

      // Validate and normalize duration
      if (metadata.duration) {
        const duration = parseFloat(metadata.duration);
        if (duration > 0) {
          enriched.duration = Math.round(duration);
        }
      }

      // Normalize genre
      if (metadata.genre) {
        enriched.genre = this.normalizeGenre(metadata.genre);
      }

      // Normalize key
      if (metadata.key) {
        enriched.key = this.normalizeKey(metadata.key);
      }

      // Add processing timestamp
      enriched.processed_at = new Date().toISOString();

      return enriched;
    } catch (error) {
      logger.error('❌ Failed to enrich metadata:', error);
      // Return original metadata if enrichment fails
      return metadata;
    }
  }

  /**
   * Normalize STEM type to standard categories
   * @param {string} stemType - Raw stem type
   * @returns {string} Normalized stem type
   */
  normalizeStemType(stemType) {
    const normalized = stemType.toLowerCase().trim();
    
    const typeMap = {
      'drum': 'drums',
      'drums': 'drums',
      'percussion': 'drums',
      'kick': 'drums',
      'snare': 'drums',
      'hihat': 'drums',
      'cymbal': 'drums',
      
      'bass': 'bass',
      'bassline': 'bass',
      'sub': 'bass',
      'subbass': 'bass',
      
      'melody': 'melody',
      'lead': 'melody',
      'synth': 'melody',
      'piano': 'melody',
      'keys': 'melody',
      'keyboard': 'melody',
      
      'vocal': 'vocals',
      'vocals': 'vocals',
      'voice': 'vocals',
      'singing': 'vocals',
      
      'harmony': 'harmony',
      'chord': 'harmony',
      'chords': 'harmony',
      'pad': 'harmony',
      
      'fx': 'effects',
      'effect': 'effects',
      'effects': 'effects',
      'reverb': 'effects',
      'delay': 'effects'
    };

    return typeMap[normalized] || 'other';
  }

  /**
   * Normalize genre to standard categories
   * @param {string} genre - Raw genre
   * @returns {string} Normalized genre
   */
  normalizeGenre(genre) {
    const normalized = genre.toLowerCase().trim();
    
    // Common genre mappings
    const genreMap = {
      'electronic': 'electronic',
      'edm': 'electronic',
      'techno': 'electronic',
      'house': 'electronic',
      'trance': 'electronic',
      'dubstep': 'electronic',
      'drum and bass': 'electronic',
      'dnb': 'electronic',
      
      'hip hop': 'hip-hop',
      'hiphop': 'hip-hop',
      'rap': 'hip-hop',
      'trap': 'hip-hop',
      
      'rock': 'rock',
      'metal': 'rock',
      'punk': 'rock',
      'alternative': 'rock',
      
      'pop': 'pop',
      'indie': 'indie',
      'folk': 'folk',
      'country': 'country',
      'jazz': 'jazz',
      'blues': 'blues',
      'classical': 'classical',
      'ambient': 'ambient',
      'experimental': 'experimental'
    };

    return genreMap[normalized] || normalized;
  }

  /**
   * Normalize musical key
   * @param {string} key - Raw key
   * @returns {string} Normalized key
   */
  normalizeKey(key) {
    const normalized = key.trim().toUpperCase();
    
    // Validate key format (e.g., C, C#, Dm, F#m)
    const keyPattern = /^[A-G][#b]?[m]?$/;
    if (keyPattern.test(normalized)) {
      return normalized;
    }
    
    return key; // Return original if doesn't match pattern
  }

  /**
   * Get cached metadata
   * @param {string} cid - IPFS CID
   * @returns {Promise<Object|null>} Cached metadata or null
   */
  async getCachedMetadata(cid) {
    try {
      const result = await this.db.query(`
        SELECT data, cached_at, expires_at 
        FROM metadata_cache 
        WHERE cid = $1 AND (expires_at IS NULL OR expires_at > NOW())
      `, [cid]);

      if (result.rows.length === 0) {
        return null;
      }

      const cached = result.rows[0];
      return cached.data;
    } catch (error) {
      logger.error('❌ Failed to get cached metadata:', error);
      return null;
    }
  }

  /**
   * Cache metadata
   * @param {string} cid - IPFS CID
   * @param {Object} metadata - Metadata to cache
   * @returns {Promise<void>}
   */
  async cacheMetadata(cid, metadata) {
    try {
      const expiresAt = new Date(Date.now() + this.cacheTimeout);
      
      await this.db.query(`
        INSERT INTO metadata_cache (cid, content_type, data, expires_at)
        VALUES ($1, $2, $3, $4)
        ON CONFLICT (cid) 
        DO UPDATE SET 
          data = EXCLUDED.data,
          cached_at = NOW(),
          expires_at = EXCLUDED.expires_at,
          access_count = metadata_cache.access_count + 1
      `, [cid, 'stem-metadata', JSON.stringify(metadata), expiresAt]);

      logger.debug('✅ Metadata cached', { cid });
    } catch (error) {
      logger.error('❌ Failed to cache metadata:', error);
      // Don't throw - caching failure shouldn't break the flow
    }
  }

  /**
   * Update cache access statistics
   * @param {string} cid - IPFS CID
   * @returns {Promise<void>}
   */
  async updateCacheAccess(cid) {
    try {
      await this.db.query(`
        UPDATE metadata_cache 
        SET access_count = access_count + 1, last_accessed = NOW()
        WHERE cid = $1
      `, [cid]);
    } catch (error) {
      logger.error('❌ Failed to update cache access:', error);
      // Don't throw - access tracking failure shouldn't break the flow
    }
  }

  /**
   * Clean expired cache entries
   * @returns {Promise<number>} Number of entries cleaned
   */
  async cleanExpiredCache() {
    try {
      logger.info('🧹 Cleaning expired cache entries...');
      
      const result = await this.db.query(`
        DELETE FROM metadata_cache 
        WHERE expires_at IS NOT NULL AND expires_at < NOW()
      `);

      const deletedCount = result.rowCount;
      logger.info('✅ Expired cache entries cleaned', { count: deletedCount });
      
      return deletedCount;
    } catch (error) {
      logger.error('❌ Failed to clean expired cache:', error);
      throw error;
    }
  }

  /**
   * Get cache statistics
   * @returns {Promise<Object>} Cache statistics
   */
  async getCacheStats() {
    try {
      const result = await this.db.query(`
        SELECT 
          COUNT(*) as total_entries,
          COUNT(*) FILTER (WHERE expires_at IS NULL OR expires_at > NOW()) as active_entries,
          COUNT(*) FILTER (WHERE expires_at IS NOT NULL AND expires_at <= NOW()) as expired_entries,
          AVG(access_count) as avg_access_count,
          SUM(access_count) as total_accesses
        FROM metadata_cache
      `);

      const stats = result.rows[0];
      return {
        totalEntries: parseInt(stats.total_entries),
        activeEntries: parseInt(stats.active_entries),
        expiredEntries: parseInt(stats.expired_entries),
        averageAccessCount: parseFloat(stats.avg_access_count) || 0,
        totalAccesses: parseInt(stats.total_accesses) || 0,
        timestamp: new Date().toISOString()
      };
    } catch (error) {
      logger.error('❌ Failed to get cache stats:', error);
      throw error;
    }
  }

  /**
   * Preload metadata for a list of CIDs
   * @param {Array<string>} cids - List of CIDs to preload
   * @returns {Promise<Object>} Preload results
   */
  async preloadMetadata(cids) {
    const results = {
      successful: 0,
      failed: 0,
      errors: []
    };

    logger.info('🔄 Preloading metadata', { count: cids.length });

    for (const cid of cids) {
      try {
        await this.fetchAndCacheMetadata(`ipfs://${cid}`);
        results.successful++;
      } catch (error) {
        results.failed++;
        results.errors.push({ cid, error: error.message });
        logger.warn('⚠️ Failed to preload metadata', { cid, error: error.message });
      }
    }

    logger.info('✅ Metadata preloading completed', results);
    return results;
  }
}
