/**
 * 🎵 TellUrStori V2 - GraphQL Schema
 * 
 * Comprehensive GraphQL API for querying blockchain-indexed STEM data,
 * marketplace activities, and metadata information.
 */

import { makeExecutableSchema } from '@graphql-tools/schema';
import { resolvers } from './resolvers.js';

const typeDefs = `
  scalar DateTime
  scalar BigInt

  type Query {
    # STEM Queries
    stem(tokenId: String!): Stem
    stems(
      first: Int = 20
      skip: Int = 0
      orderBy: StemOrderBy = CREATED_AT
      orderDirection: OrderDirection = DESC
      where: StemFilter
    ): StemConnection!
    
    # Creator Queries
    creator(address: String!): Creator
    creators(
      first: Int = 20
      skip: Int = 0
      orderBy: CreatorOrderBy = STEMS_COUNT
      orderDirection: OrderDirection = DESC
    ): CreatorConnection!
    
    # Marketplace Queries
    listing(listingId: String!): Listing
    listings(
      first: Int = 20
      skip: Int = 0
      orderBy: ListingOrderBy = CREATED_AT
      orderDirection: OrderDirection = DESC
      where: ListingFilter
    ): ListingConnection!
    
    sale(id: ID!): Sale
    sales(
      first: Int = 20
      skip: Int = 0
      orderBy: SaleOrderBy = CREATED_AT
      orderDirection: OrderDirection = DESC
      where: SaleFilter
    ): SaleConnection!
    
    offer(offerId: String!): Offer
    offers(
      first: Int = 20
      skip: Int = 0
      orderBy: OfferOrderBy = CREATED_AT
      orderDirection: OrderDirection = DESC
      where: OfferFilter
    ): OfferConnection!
    
    # Analytics Queries
    marketStats: MarketStats!
    stemStats: StemStats!
    recentActivity(limit: Int = 50): [Activity!]!
    
    # Search
    searchStems(query: String!, first: Int = 20): [Stem!]!
  }

  # STEM Types
  type Stem {
    id: ID!
    tokenId: String!
    creator: Creator!
    name: String
    description: String
    metadataURI: String
    metadataCID: String
    audioCID: String
    imageCID: String
    stemType: StemType
    duration: Int
    bpm: Int
    key: String
    genre: String
    format: String
    sampleRate: Int
    bitDepth: Int
    channels: Int
    totalSupply: BigInt!
    contractAddress: String
    chainId: Int
    createdAt: DateTime!
    updatedAt: DateTime!
    blockNumber: BigInt!
    transactionHash: String!
    
    # Related data
    transfers(first: Int = 10): TransferConnection!
    listings(first: Int = 10, active: Boolean): ListingConnection!
    sales(first: Int = 10): SaleConnection!
    owners: [Owner!]!
    
    # Computed fields
    floorPrice: BigInt
    lastSalePrice: BigInt
    totalVolume: BigInt
    holdersCount: Int!
  }

  type StemConnection {
    edges: [StemEdge!]!
    pageInfo: PageInfo!
    totalCount: Int!
  }

  type StemEdge {
    node: Stem!
    cursor: String!
  }

  # Creator Types
  type Creator {
    id: ID!
    address: String!
    stemsCreated: [Stem!]!
    stemsCount: Int!
    totalVolume: BigInt!
    totalSales: Int!
    firstStemAt: DateTime
    lastActiveAt: DateTime
    
    # Computed fields
    averageSalePrice: BigInt
    topStem: Stem
  }

  type CreatorConnection {
    edges: [CreatorEdge!]!
    pageInfo: PageInfo!
    totalCount: Int!
  }

  type CreatorEdge {
    node: Creator!
    cursor: String!
  }

  # Transfer Types
  type Transfer {
    id: ID!
    tokenId: String!
    stem: Stem!
    from: String
    to: String!
    operator: String
    amount: BigInt!
    transactionHash: String!
    blockNumber: BigInt!
    logIndex: Int!
    timestamp: DateTime!
    
    # Computed fields
    isMintt: Boolean!
    isBurn: Boolean!
  }

  type TransferConnection {
    edges: [TransferEdge!]!
    pageInfo: PageInfo!
    totalCount: Int!
  }

  type TransferEdge {
    node: Transfer!
    cursor: String!
  }

  # Marketplace Types
  type Listing {
    id: ID!
    listingId: String!
    seller: String!
    stem: Stem!
    amount: BigInt!
    pricePerToken: BigInt!
    totalPrice: BigInt!
    expiration: DateTime
    active: Boolean!
    createdAt: DateTime!
    updatedAt: DateTime!
    blockNumber: BigInt!
    transactionHash: String!
    
    # Related data
    offers(first: Int = 10): OfferConnection!
    sales(first: Int = 10): SaleConnection!
    
    # Computed fields
    isExpired: Boolean!
    timeRemaining: Int
  }

  type ListingConnection {
    edges: [ListingEdge!]!
    pageInfo: PageInfo!
    totalCount: Int!
  }

  type ListingEdge {
    node: Listing!
    cursor: String!
  }

  type Sale {
    id: ID!
    listing: Listing!
    buyer: String!
    seller: String!
    stem: Stem!
    amount: BigInt!
    pricePerToken: BigInt!
    totalPrice: BigInt!
    createdAt: DateTime!
    blockNumber: BigInt!
    transactionHash: String!
  }

  type SaleConnection {
    edges: [SaleEdge!]!
    pageInfo: PageInfo!
    totalCount: Int!
  }

  type SaleEdge {
    node: Sale!
    cursor: String!
  }

  type Offer {
    id: ID!
    offerId: String!
    listing: Listing!
    buyer: String!
    amount: BigInt!
    pricePerToken: BigInt!
    totalPrice: BigInt!
    expiration: DateTime
    status: OfferStatus!
    createdAt: DateTime!
    updatedAt: DateTime!
    blockNumber: BigInt!
    transactionHash: String!
    
    # Computed fields
    isExpired: Boolean!
    timeRemaining: Int
  }

  type OfferConnection {
    edges: [OfferEdge!]!
    pageInfo: PageInfo!
    totalCount: Int!
  }

  type OfferEdge {
    node: Offer!
    cursor: String!
  }

  # Owner Types
  type Owner {
    address: String!
    balance: BigInt!
    stem: Stem!
    firstAcquiredAt: DateTime!
    lastTransferAt: DateTime!
  }

  # Activity Types
  type Activity {
    id: ID!
    type: ActivityType!
    tokenId: String!
    stem: Stem!
    address: String!
    timestamp: DateTime!
    transactionHash: String!
    blockNumber: BigInt!
    
    # Type-specific data
    transferData: Transfer
    saleData: Sale
    listingData: Listing
    offerData: Offer
  }

  # Analytics Types
  type MarketStats {
    totalVolume: BigInt!
    totalSales: Int!
    averageSalePrice: BigInt!
    activeListings: Int!
    activeOffers: Int!
    uniqueTraders: Int!
    floorPrice: BigInt
    lastUpdated: DateTime!
    
    # Time-based stats
    volume24h: BigInt!
    sales24h: Int!
    volume7d: BigInt!
    sales7d: Int!
    volume30d: BigInt!
    sales30d: Int!
  }

  type StemStats {
    totalStems: Int!
    totalCreators: Int!
    totalSupply: BigInt!
    averageDuration: Float
    averageBPM: Float
    
    # Distribution stats
    stemTypeDistribution: [StemTypeCount!]!
    genreDistribution: [GenreCount!]!
    keyDistribution: [KeyCount!]!
    
    lastUpdated: DateTime!
  }

  type StemTypeCount {
    stemType: StemType!
    count: Int!
  }

  type GenreCount {
    genre: String!
    count: Int!
  }

  type KeyCount {
    key: String!
    count: Int!
  }

  # Pagination Types
  type PageInfo {
    hasNextPage: Boolean!
    hasPreviousPage: Boolean!
    startCursor: String
    endCursor: String
  }

  # Filter Types
  input StemFilter {
    creator: String
    stemType: StemType
    genre: String
    key: String
    minDuration: Int
    maxDuration: Int
    minBPM: Int
    maxBPM: Int
    hasAudio: Boolean
    hasImage: Boolean
    createdAfter: DateTime
    createdBefore: DateTime
  }

  input ListingFilter {
    seller: String
    tokenId: String
    stemType: StemType
    genre: String
    active: Boolean
    minPrice: BigInt
    maxPrice: BigInt
    expiresAfter: DateTime
    expiresBefore: DateTime
  }

  input SaleFilter {
    buyer: String
    seller: String
    tokenId: String
    stemType: StemType
    genre: String
    minPrice: BigInt
    maxPrice: BigInt
    soldAfter: DateTime
    soldBefore: DateTime
  }

  input OfferFilter {
    buyer: String
    listingId: String
    tokenId: String
    status: OfferStatus
    minPrice: BigInt
    maxPrice: BigInt
    expiresAfter: DateTime
    expiresBefore: DateTime
  }

  # Enums
  enum StemType {
    DRUMS
    BASS
    MELODY
    VOCALS
    HARMONY
    EFFECTS
    OTHER
  }

  enum ActivityType {
    MINT
    TRANSFER
    LISTING
    SALE
    OFFER
    OFFER_ACCEPTED
  }

  enum OfferStatus {
    ACTIVE
    ACCEPTED
    EXPIRED
    CANCELLED
  }

  enum OrderDirection {
    ASC
    DESC
  }

  enum StemOrderBy {
    CREATED_AT
    UPDATED_AT
    NAME
    DURATION
    BPM
    TOTAL_SUPPLY
    TOTAL_VOLUME
    LAST_SALE_PRICE
  }

  enum CreatorOrderBy {
    STEMS_COUNT
    TOTAL_VOLUME
    TOTAL_SALES
    FIRST_STEM_AT
    LAST_ACTIVE_AT
  }

  enum ListingOrderBy {
    CREATED_AT
    UPDATED_AT
    PRICE_PER_TOKEN
    TOTAL_PRICE
    EXPIRATION
  }

  enum SaleOrderBy {
    CREATED_AT
    TOTAL_PRICE
    PRICE_PER_TOKEN
  }

  enum OfferOrderBy {
    CREATED_AT
    UPDATED_AT
    TOTAL_PRICE
    PRICE_PER_TOKEN
    EXPIRATION
  }
`;

export function createGraphQLSchema() {
  return makeExecutableSchema({
    typeDefs,
    resolvers
  });
}
