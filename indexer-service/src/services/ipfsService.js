/**
 * 🎵 TellUrStori V2 - IPFS Service
 * 
 * Decentralized storage service for STEM metadata, audio files, and artwork
 * using Helia (modern IPFS implementation for JavaScript).
 */

import { createHelia } from 'helia';
import { unixfs } from '@helia/unixfs';
import { json } from '@helia/json';
import { CID } from 'multiformats/cid';
import winston from 'winston';
import fs from 'fs/promises';
import path from 'path';

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  defaultMeta: { service: 'ipfs-service' }
});

export class IPFSService {
  constructor(options = {}) {
    this.helia = null;
    this.fs = null;
    this.json = null;
    this.isReady = false;
    this.options = {
      // Default IPFS configuration
      config: {
        Addresses: {
          Swarm: [
            '/ip4/0.0.0.0/tcp/4001',
            '/ip4/0.0.0.0/tcp/4002/ws'
          ],
          API: '/ip4/127.0.0.1/tcp/5001',
          Gateway: '/ip4/127.0.0.1/tcp/8080'
        },
        Discovery: {
          MDNS: {
            Enabled: true
          },
          webRTCStar: {
            Enabled: true
          }
        }
      },
      ...options
    };
  }

  async initialize() {
    try {
      logger.info('🌐 Initializing IPFS (Helia) node...');
      
      // Create Helia node
      this.helia = await createHelia(this.options);
      
      // Initialize UnixFS for file operations
      this.fs = unixfs(this.helia);
      
      // Initialize JSON for metadata operations
      this.json = json(this.helia);
      
      // Get node info
      const peerId = this.helia.libp2p.peerId.toString();
      logger.info('✅ IPFS node initialized', { peerId });
      
      this.isReady = true;
      
      // Set up event listeners
      this.setupEventListeners();
      
      return true;
    } catch (error) {
      logger.error('❌ Failed to initialize IPFS node:', error);
      throw error;
    }
  }

  setupEventListeners() {
    // Listen for peer connections
    this.helia.libp2p.addEventListener('peer:connect', (event) => {
      logger.debug('🤝 Peer connected', { peerId: event.detail.toString() });
    });

    this.helia.libp2p.addEventListener('peer:disconnect', (event) => {
      logger.debug('👋 Peer disconnected', { peerId: event.detail.toString() });
    });
  }

  /**
   * Upload audio file to IPFS
   * @param {Buffer|Uint8Array} audioData - Audio file data
   * @param {Object} metadata - Audio metadata
   * @returns {Promise<Object>} Upload result with CID and metadata
   */
  async uploadAudioFile(audioData, metadata = {}) {
    if (!this.isReady) {
      throw new Error('IPFS service not initialized');
    }

    try {
      logger.info('🎵 Uploading audio file to IPFS...', { 
        size: audioData.length,
        format: metadata.format || 'unknown'
      });

      // Upload audio file
      const audioCID = await this.fs.addBytes(audioData);
      logger.info('✅ Audio file uploaded', { cid: audioCID.toString() });

      // Create comprehensive metadata
      const audioMetadata = {
        type: 'audio',
        format: metadata.format || 'wav',
        duration: metadata.duration || null,
        sampleRate: metadata.sampleRate || null,
        channels: metadata.channels || null,
        bitrate: metadata.bitrate || null,
        size: audioData.length,
        cid: audioCID.toString(),
        uploadedAt: new Date().toISOString(),
        ...metadata
      };

      // Upload metadata as JSON
      const metadataCID = await this.json.add(audioMetadata);
      logger.info('✅ Audio metadata uploaded', { cid: metadataCID.toString() });

      return {
        audioCID: audioCID.toString(),
        metadataCID: metadataCID.toString(),
        metadata: audioMetadata,
        urls: {
          audio: `ipfs://${audioCID.toString()}`,
          metadata: `ipfs://${metadataCID.toString()}`
        }
      };
    } catch (error) {
      logger.error('❌ Failed to upload audio file:', error);
      throw error;
    }
  }

  /**
   * Upload STEM token metadata to IPFS
   * @param {Object} stemMetadata - STEM token metadata
   * @returns {Promise<Object>} Upload result with CID
   */
  async uploadSTEMMetadata(stemMetadata) {
    if (!this.isReady) {
      throw new Error('IPFS service not initialized');
    }

    try {
      logger.info('📋 Uploading STEM metadata to IPFS...', { 
        tokenId: stemMetadata.tokenId,
        name: stemMetadata.name 
      });

      // Ensure required fields
      const metadata = {
        name: stemMetadata.name,
        description: stemMetadata.description || '',
        image: stemMetadata.image || '',
        external_url: stemMetadata.external_url || '',
        attributes: stemMetadata.attributes || [],
        
        // STEM-specific metadata
        stem_type: stemMetadata.stem_type || 'unknown', // drums, bass, melody, vocals, etc.
        audio_url: stemMetadata.audio_url || '',
        duration: stemMetadata.duration || null,
        bpm: stemMetadata.bpm || null,
        key: stemMetadata.key || null,
        genre: stemMetadata.genre || null,
        
        // Creator information
        creator: stemMetadata.creator || '',
        created_at: stemMetadata.created_at || new Date().toISOString(),
        
        // Technical metadata
        format: stemMetadata.format || 'wav',
        sample_rate: stemMetadata.sample_rate || null,
        bit_depth: stemMetadata.bit_depth || null,
        channels: stemMetadata.channels || null,
        
        // Blockchain metadata
        token_id: stemMetadata.tokenId,
        contract_address: stemMetadata.contract_address || '',
        chain_id: stemMetadata.chain_id || null,
        
        // IPFS metadata
        uploaded_at: new Date().toISOString(),
        version: '1.0.0'
      };

      // Upload metadata
      const cid = await this.json.add(metadata);
      logger.info('✅ STEM metadata uploaded', { 
        cid: cid.toString(),
        tokenId: stemMetadata.tokenId 
      });

      return {
        cid: cid.toString(),
        url: `ipfs://${cid.toString()}`,
        metadata
      };
    } catch (error) {
      logger.error('❌ Failed to upload STEM metadata:', error);
      throw error;
    }
  }

  /**
   * Upload artwork/image to IPFS
   * @param {Buffer|Uint8Array} imageData - Image file data
   * @param {Object} metadata - Image metadata
   * @returns {Promise<Object>} Upload result with CID
   */
  async uploadArtwork(imageData, metadata = {}) {
    if (!this.isReady) {
      throw new Error('IPFS service not initialized');
    }

    try {
      logger.info('🎨 Uploading artwork to IPFS...', { 
        size: imageData.length,
        format: metadata.format || 'unknown'
      });

      // Upload image
      const cid = await this.fs.addBytes(imageData);
      logger.info('✅ Artwork uploaded', { cid: cid.toString() });

      return {
        cid: cid.toString(),
        url: `ipfs://${cid.toString()}`,
        size: imageData.length,
        format: metadata.format || 'unknown',
        uploadedAt: new Date().toISOString()
      };
    } catch (error) {
      logger.error('❌ Failed to upload artwork:', error);
      throw error;
    }
  }

  /**
   * Download file from IPFS
   * @param {string} cid - IPFS CID
   * @returns {Promise<Uint8Array>} File data
   */
  async downloadFile(cid) {
    if (!this.isReady) {
      throw new Error('IPFS service not initialized');
    }

    try {
      logger.info('📥 Downloading file from IPFS...', { cid });
      
      const cidObj = CID.parse(cid);
      const chunks = [];
      
      for await (const chunk of this.fs.cat(cidObj)) {
        chunks.push(chunk);
      }
      
      const data = new Uint8Array(chunks.reduce((acc, chunk) => acc + chunk.length, 0));
      let offset = 0;
      
      for (const chunk of chunks) {
        data.set(chunk, offset);
        offset += chunk.length;
      }
      
      logger.info('✅ File downloaded', { cid, size: data.length });
      return data;
    } catch (error) {
      logger.error('❌ Failed to download file:', error);
      throw error;
    }
  }

  /**
   * Download JSON metadata from IPFS
   * @param {string} cid - IPFS CID
   * @returns {Promise<Object>} JSON data
   */
  async downloadJSON(cid) {
    if (!this.isReady) {
      throw new Error('IPFS service not initialized');
    }

    try {
      logger.info('📥 Downloading JSON from IPFS...', { cid });
      
      const cidObj = CID.parse(cid);
      const data = await this.json.get(cidObj);
      
      logger.info('✅ JSON downloaded', { cid });
      return data;
    } catch (error) {
      logger.error('❌ Failed to download JSON:', error);
      throw error;
    }
  }

  /**
   * Pin content to ensure it stays available
   * @param {string} cid - IPFS CID to pin
   * @returns {Promise<boolean>} Success status
   */
  async pinContent(cid) {
    if (!this.isReady) {
      throw new Error('IPFS service not initialized');
    }

    try {
      logger.info('📌 Pinning content...', { cid });
      
      const cidObj = CID.parse(cid);
      await this.helia.pins.add(cidObj);
      
      logger.info('✅ Content pinned', { cid });
      return true;
    } catch (error) {
      logger.error('❌ Failed to pin content:', error);
      throw error;
    }
  }

  /**
   * Unpin content
   * @param {string} cid - IPFS CID to unpin
   * @returns {Promise<boolean>} Success status
   */
  async unpinContent(cid) {
    if (!this.isReady) {
      throw new Error('IPFS service not initialized');
    }

    try {
      logger.info('📌 Unpinning content...', { cid });
      
      const cidObj = CID.parse(cid);
      await this.helia.pins.rm(cidObj);
      
      logger.info('✅ Content unpinned', { cid });
      return true;
    } catch (error) {
      logger.error('❌ Failed to unpin content:', error);
      throw error;
    }
  }

  /**
   * Get node statistics
   * @returns {Promise<Object>} Node stats
   */
  async getStats() {
    if (!this.isReady) {
      throw new Error('IPFS service not initialized');
    }

    try {
      const peerId = this.helia.libp2p.peerId.toString();
      const connections = this.helia.libp2p.getConnections();
      const peers = this.helia.libp2p.getPeers();
      
      return {
        peerId,
        isReady: this.isReady,
        connections: connections.length,
        peers: peers.length,
        multiaddrs: this.helia.libp2p.getMultiaddrs().map(ma => ma.toString())
      };
    } catch (error) {
      logger.error('❌ Failed to get IPFS stats:', error);
      throw error;
    }
  }

  /**
   * Stop IPFS service
   */
  async stop() {
    if (!this.isReady) {
      return;
    }

    try {
      logger.info('🛑 Stopping IPFS service...');
      
      await this.helia.stop();
      this.isReady = false;
      
      logger.info('✅ IPFS service stopped');
    } catch (error) {
      logger.error('❌ Error stopping IPFS service:', error);
      throw error;
    }
  }

  /**
   * Check if service is ready
   * @returns {boolean} Ready status
   */
  isReady() {
    return this.isReady;
  }
}
