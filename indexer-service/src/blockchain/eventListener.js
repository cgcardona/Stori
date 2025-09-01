/**
 * 🎵 TellUrStori V2 - Blockchain Event Listener
 * 
 * Real-time monitoring and indexing of smart contract events
 * for STEM token minting, marketplace activities, and transfers.
 */

import { ethers } from 'ethers';
import winston from 'winston';

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.combine(
    winston.format.timestamp(),
    winston.format.json()
  ),
  defaultMeta: { service: 'blockchain-indexer' }
});

export class BlockchainIndexer {
  constructor(rpcUrl, contractAddresses, indexingService) {
    this.rpcUrl = rpcUrl;
    this.contractAddresses = contractAddresses;
    this.indexingService = indexingService;
    this.provider = null;
    this.contracts = {};
    this.listeners = new Map();
    this.isListening = false;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = 5;
    this.reconnectDelay = 5000; // 5 seconds
  }

  async initialize() {
    try {
      logger.info('🔗 Connecting to blockchain provider...', { rpcUrl: this.rpcUrl });
      
      // Create provider
      this.provider = new ethers.JsonRpcProvider(this.rpcUrl);
      
      // Test connection
      const network = await this.provider.getNetwork();
      logger.info('✅ Connected to blockchain network', { 
        chainId: network.chainId.toString(),
        name: network.name 
      });

      // Load contract ABIs and create contract instances
      await this.loadContracts();
      
      this.reconnectAttempts = 0;
      return true;
    } catch (error) {
      logger.error('❌ Failed to initialize blockchain connection:', error);
      throw error;
    }
  }

  async loadContracts() {
    try {
      // Load TellUrStoriSTEM contract
      if (this.contractAddresses.stemContract) {
        const stemABI = await this.loadContractABI('TellUrStoriSTEM');
        this.contracts.stem = new ethers.Contract(
          this.contractAddresses.stemContract,
          stemABI,
          this.provider
        );
        logger.info('📜 TellUrStoriSTEM contract loaded', { 
          address: this.contractAddresses.stemContract 
        });
      }

      // Load STEMMarketplace contract
      if (this.contractAddresses.marketplaceContract) {
        const marketplaceABI = await this.loadContractABI('STEMMarketplace');
        this.contracts.marketplace = new ethers.Contract(
          this.contractAddresses.marketplaceContract,
          marketplaceABI,
          this.provider
        );
        logger.info('🏪 STEMMarketplace contract loaded', { 
          address: this.contractAddresses.marketplaceContract 
        });
      }
    } catch (error) {
      logger.error('❌ Failed to load contracts:', error);
      throw error;
    }
  }

  async loadContractABI(contractName) {
    // In a real implementation, you would load the ABI from the compiled artifacts
    // For now, we'll define the essential events we need to listen to
    
    if (contractName === 'TellUrStoriSTEM') {
      return [
        // STEMMinted event
        "event STEMMinted(uint256 indexed tokenId, address indexed creator, uint256 amount, string metadataURI, uint256 timestamp)",
        
        // TransferSingle event (from ERC1155)
        "event TransferSingle(address indexed operator, address indexed from, address indexed to, uint256 id, uint256 value)",
        
        // TransferBatch event (from ERC1155)
        "event TransferBatch(address indexed operator, address indexed from, address indexed to, uint256[] ids, uint256[] values)",
        
        // STEMMetadataUpdated event
        "event STEMMetadataUpdated(uint256 indexed tokenId, string newName, string newDescription, uint256 timestamp)",
        
        // RoyaltyPaid event
        "event RoyaltyPaid(uint256 indexed tokenId, address indexed recipient, uint256 amount, uint256 timestamp)"
      ];
    }
    
    if (contractName === 'STEMMarketplace') {
      return [
        // Listed event
        "event Listed(uint256 indexed listingId, address indexed seller, uint256 indexed tokenId, uint256 amount, uint256 pricePerToken, uint256 expiration)",
        
        // Sold event
        "event Sold(uint256 indexed listingId, address indexed buyer, uint256 amount, uint256 totalPrice)",
        
        // OfferMade event
        "event OfferMade(uint256 indexed offerId, uint256 indexed listingId, address indexed buyer, uint256 amount, uint256 pricePerToken, uint256 expiration)",
        
        // OfferAccepted event
        "event OfferAccepted(uint256 indexed offerId, address indexed seller, address indexed buyer, uint256 amount, uint256 totalPrice)",
        
        // AuctionCreated event
        "event AuctionCreated(uint256 indexed auctionId, address indexed seller, uint256 indexed tokenId, uint256 amount, uint256 startingBid, uint256 endTime)",
        
        // BidPlaced event
        "event BidPlaced(uint256 indexed auctionId, address indexed bidder, uint256 bidAmount, uint256 timestamp)",
        
        // AuctionSettled event
        "event AuctionSettled(uint256 indexed auctionId, address indexed winner, uint256 winningBid, uint256 timestamp)"
      ];
    }
    
    throw new Error(`Unknown contract: ${contractName}`);
  }

  async startListening() {
    if (this.isListening) {
      logger.warn('⚠️ Already listening to blockchain events');
      return;
    }

    try {
      await this.initialize();
      
      logger.info('👂 Starting blockchain event listeners...');
      
      // Set up STEM contract event listeners
      if (this.contracts.stem) {
        await this.setupSTEMEventListeners();
      }
      
      // Set up Marketplace contract event listeners
      if (this.contracts.marketplace) {
        await this.setupMarketplaceEventListeners();
      }
      
      this.isListening = true;
      logger.info('✅ All blockchain event listeners started successfully');
      
    } catch (error) {
      logger.error('❌ Failed to start event listeners:', error);
      await this.handleReconnection();
    }
  }

  async setupSTEMEventListeners() {
    const contract = this.contracts.stem;
    
    // Listen for STEM minting events
    const stemMintedListener = async (tokenId, creator, amount, metadataURI, timestamp, event) => {
      try {
        logger.info('🎵 STEM Minted Event', { tokenId: tokenId.toString(), creator, amount: amount.toString() });
        
        await this.indexingService.processStemMintedEvent({
          tokenId: tokenId.toString(),
          creator,
          amount: amount.toString(),
          metadataURI,
          timestamp: timestamp.toString(),
          transactionHash: event.transactionHash,
          blockNumber: event.blockNumber,
          logIndex: event.logIndex
        });
      } catch (error) {
        logger.error('❌ Error processing STEMMinted event:', error);
      }
    };
    
    contract.on('STEMMinted', stemMintedListener);
    this.listeners.set('STEMMinted', { contract, listener: stemMintedListener });
    
    // Listen for transfer events
    const transferSingleListener = async (operator, from, to, id, value, event) => {
      try {
        logger.info('📤 STEM Transfer Event', { 
          from, 
          to, 
          tokenId: id.toString(), 
          amount: value.toString() 
        });
        
        await this.indexingService.processTransferEvent({
          operator,
          from,
          to,
          tokenId: id.toString(),
          amount: value.toString(),
          transactionHash: event.transactionHash,
          blockNumber: event.blockNumber,
          logIndex: event.logIndex
        });
      } catch (error) {
        logger.error('❌ Error processing TransferSingle event:', error);
      }
    };
    
    contract.on('TransferSingle', transferSingleListener);
    this.listeners.set('TransferSingle', { contract, listener: transferSingleListener });
    
    // Listen for metadata updates
    const metadataUpdatedListener = async (tokenId, newName, newDescription, timestamp, event) => {
      try {
        logger.info('📝 STEM Metadata Updated', { tokenId: tokenId.toString() });
        
        await this.indexingService.processMetadataUpdatedEvent({
          tokenId: tokenId.toString(),
          newName,
          newDescription,
          timestamp: timestamp.toString(),
          transactionHash: event.transactionHash,
          blockNumber: event.blockNumber,
          logIndex: event.logIndex
        });
      } catch (error) {
        logger.error('❌ Error processing STEMMetadataUpdated event:', error);
      }
    };
    
    contract.on('STEMMetadataUpdated', metadataUpdatedListener);
    this.listeners.set('STEMMetadataUpdated', { contract, listener: metadataUpdatedListener });
  }

  async setupMarketplaceEventListeners() {
    const contract = this.contracts.marketplace;
    
    // Listen for listing events
    const listedListener = async (listingId, seller, tokenId, amount, pricePerToken, expiration, event) => {
      try {
        logger.info('🏷️ STEM Listed Event', { 
          listingId: listingId.toString(), 
          seller, 
          tokenId: tokenId.toString() 
        });
        
        await this.indexingService.processListedEvent({
          listingId: listingId.toString(),
          seller,
          tokenId: tokenId.toString(),
          amount: amount.toString(),
          pricePerToken: pricePerToken.toString(),
          expiration: expiration.toString(),
          transactionHash: event.transactionHash,
          blockNumber: event.blockNumber,
          logIndex: event.logIndex
        });
      } catch (error) {
        logger.error('❌ Error processing Listed event:', error);
      }
    };
    
    contract.on('Listed', listedListener);
    this.listeners.set('Listed', { contract, listener: listedListener });
    
    // Listen for sale events
    const soldListener = async (listingId, buyer, amount, totalPrice, event) => {
      try {
        logger.info('💰 STEM Sold Event', { 
          listingId: listingId.toString(), 
          buyer, 
          totalPrice: totalPrice.toString() 
        });
        
        await this.indexingService.processSoldEvent({
          listingId: listingId.toString(),
          buyer,
          amount: amount.toString(),
          totalPrice: totalPrice.toString(),
          transactionHash: event.transactionHash,
          blockNumber: event.blockNumber,
          logIndex: event.logIndex
        });
      } catch (error) {
        logger.error('❌ Error processing Sold event:', error);
      }
    };
    
    contract.on('Sold', soldListener);
    this.listeners.set('Sold', { contract, listener: soldListener });
    
    // Listen for offer events
    const offerMadeListener = async (offerId, listingId, buyer, amount, pricePerToken, expiration, event) => {
      try {
        logger.info('💡 Offer Made Event', { 
          offerId: offerId.toString(), 
          listingId: listingId.toString(), 
          buyer 
        });
        
        await this.indexingService.processOfferMadeEvent({
          offerId: offerId.toString(),
          listingId: listingId.toString(),
          buyer,
          amount: amount.toString(),
          pricePerToken: pricePerToken.toString(),
          expiration: expiration.toString(),
          transactionHash: event.transactionHash,
          blockNumber: event.blockNumber,
          logIndex: event.logIndex
        });
      } catch (error) {
        logger.error('❌ Error processing OfferMade event:', error);
      }
    };
    
    contract.on('OfferMade', offerMadeListener);
    this.listeners.set('OfferMade', { contract, listener: offerMadeListener });
  }

  async stopListening() {
    if (!this.isListening) {
      return;
    }

    logger.info('🛑 Stopping blockchain event listeners...');
    
    // Remove all event listeners
    for (const [eventName, { contract, listener }] of this.listeners) {
      try {
        contract.off(eventName, listener);
        logger.debug(`✅ Removed listener for ${eventName}`);
      } catch (error) {
        logger.error(`❌ Error removing listener for ${eventName}:`, error);
      }
    }
    
    this.listeners.clear();
    this.isListening = false;
    
    logger.info('✅ All blockchain event listeners stopped');
  }

  async handleReconnection() {
    if (this.reconnectAttempts >= this.maxReconnectAttempts) {
      logger.error('💥 Max reconnection attempts reached, giving up');
      return;
    }

    this.reconnectAttempts++;
    logger.info(`🔄 Attempting to reconnect (${this.reconnectAttempts}/${this.maxReconnectAttempts})...`);
    
    // Stop current listeners
    await this.stopListening();
    
    // Wait before reconnecting
    await new Promise(resolve => setTimeout(resolve, this.reconnectDelay));
    
    // Try to restart
    try {
      await this.startListening();
      logger.info('✅ Successfully reconnected to blockchain');
    } catch (error) {
      logger.error('❌ Reconnection failed:', error);
      // Exponential backoff
      this.reconnectDelay *= 2;
      await this.handleReconnection();
    }
  }

  isListening() {
    return this.isListening;
  }

  getStatus() {
    return {
      isListening: this.isListening,
      reconnectAttempts: this.reconnectAttempts,
      activeListeners: Array.from(this.listeners.keys()),
      contractAddresses: this.contractAddresses
    };
  }
}
