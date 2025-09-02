/**
 * 🎵 TellUrStori V2 - GraphQL Resolvers
 * 
 * Resolvers for the comprehensive GraphQL API providing access to
 * blockchain-indexed STEM data, marketplace activities, and analytics.
 */

import { GraphQLScalarType } from 'graphql';
import { Kind } from 'graphql/language/index.js';

// Custom scalar types
const DateTimeType = new GraphQLScalarType({
  name: 'DateTime',
  description: 'Date custom scalar type',
  serialize(value) {
    return value instanceof Date ? value.toISOString() : value;
  },
  parseValue(value) {
    return new Date(value);
  },
  parseLiteral(ast) {
    if (ast.kind === Kind.STRING) {
      return new Date(ast.value);
    }
    return null;
  }
});

const BigIntType = new GraphQLScalarType({
  name: 'BigInt',
  description: 'BigInt custom scalar type',
  serialize(value) {
    return value.toString();
  },
  parseValue(value) {
    return BigInt(value);
  },
  parseLiteral(ast) {
    if (ast.kind === Kind.STRING || ast.kind === Kind.INT) {
      return BigInt(ast.value);
    }
    return null;
  }
});

export const resolvers = {
  DateTime: DateTimeType,
  BigInt: BigIntType,

  Query: {
    // STEM Queries
    async stem(_, { tokenId }, { services }) {
      const result = await services.database.query(
        'SELECT * FROM stems WHERE token_id = $1',
        [tokenId]
      );
      return result.rows[0] || null;
    },

    async stems(_, { first, skip, orderBy, orderDirection, where }, { services }) {
      let query = 'SELECT * FROM stems';
      let countQuery = 'SELECT COUNT(*) FROM stems';
      const params = [];
      const conditions = [];

      // Apply filters
      if (where) {
        if (where.creator) {
          conditions.push(`creator_address = $${params.length + 1}`);
          params.push(where.creator);
        }
        if (where.stemType) {
          conditions.push(`stem_type = $${params.length + 1}`);
          params.push(where.stemType.toLowerCase());
        }
        if (where.genre) {
          conditions.push(`genre = $${params.length + 1}`);
          params.push(where.genre);
        }
        if (where.key) {
          conditions.push(`key = $${params.length + 1}`);
          params.push(where.key);
        }
        if (where.minDuration) {
          conditions.push(`duration >= $${params.length + 1}`);
          params.push(where.minDuration);
        }
        if (where.maxDuration) {
          conditions.push(`duration <= $${params.length + 1}`);
          params.push(where.maxDuration);
        }
        if (where.minBPM) {
          conditions.push(`bpm >= $${params.length + 1}`);
          params.push(where.minBPM);
        }
        if (where.maxBPM) {
          conditions.push(`bpm <= $${params.length + 1}`);
          params.push(where.maxBPM);
        }
        if (where.hasAudio !== undefined) {
          conditions.push(where.hasAudio ? 'audio_cid IS NOT NULL' : 'audio_cid IS NULL');
        }
        if (where.hasImage !== undefined) {
          conditions.push(where.hasImage ? 'image_cid IS NOT NULL' : 'image_cid IS NULL');
        }
        if (where.createdAfter) {
          conditions.push(`created_at >= $${params.length + 1}`);
          params.push(where.createdAfter);
        }
        if (where.createdBefore) {
          conditions.push(`created_at <= $${params.length + 1}`);
          params.push(where.createdBefore);
        }
      }

      if (conditions.length > 0) {
        const whereClause = ` WHERE ${conditions.join(' AND ')}`;
        query += whereClause;
        countQuery += whereClause;
      }

      // Apply ordering
      const orderByMap = {
        CREATED_AT: 'created_at',
        UPDATED_AT: 'updated_at',
        NAME: 'name',
        DURATION: 'duration',
        BPM: 'bpm',
        TOTAL_SUPPLY: 'total_supply'
      };
      
      const orderColumn = orderByMap[orderBy] || 'created_at';
      const direction = orderDirection === 'ASC' ? 'ASC' : 'DESC';
      query += ` ORDER BY ${orderColumn} ${direction}`;

      // Apply pagination
      query += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(first, skip);

      const [result, countResult] = await Promise.all([
        services.database.query(query, params),
        services.database.query(countQuery, params.slice(0, -2))
      ]);

      const totalCount = parseInt(countResult.rows[0].count);
      const hasNextPage = skip + first < totalCount;
      const hasPreviousPage = skip > 0;

      return {
        edges: result.rows.map((stem, index) => ({
          node: stem,
          cursor: Buffer.from(`${skip + index}`).toString('base64')
        })),
        pageInfo: {
          hasNextPage,
          hasPreviousPage,
          startCursor: result.rows.length > 0 ? Buffer.from(`${skip}`).toString('base64') : null,
          endCursor: result.rows.length > 0 ? Buffer.from(`${skip + result.rows.length - 1}`).toString('base64') : null
        },
        totalCount
      };
    },

    // Creator Queries
    async creator(_, { address }, { services }) {
      const result = await services.database.query(`
        SELECT 
          creator_address as address,
          COUNT(*) as stems_count,
          MIN(created_at) as first_stem_at,
          MAX(created_at) as last_active_at
        FROM stems 
        WHERE creator_address = $1
        GROUP BY creator_address
      `, [address]);

      if (result.rows.length === 0) {
        return null;
      }

      const creator = result.rows[0];
      
      // Get volume and sales data
      const volumeResult = await services.database.query(`
        SELECT 
          COALESCE(SUM(s.total_price), 0) as total_volume,
          COUNT(s.id) as total_sales
        FROM sales s
        JOIN stems st ON s.token_id = st.token_id
        WHERE st.creator_address = $1
      `, [address]);

      const volumeData = volumeResult.rows[0];
      
      return {
        ...creator,
        totalVolume: volumeData.total_volume,
        totalSales: parseInt(volumeData.total_sales)
      };
    },

    // Marketplace Queries
    async listing(_, { listingId }, { services }) {
      const result = await services.database.query(
        'SELECT * FROM listings WHERE listing_id = $1',
        [listingId]
      );
      return result.rows[0] || null;
    },

    async listings(_, { first, skip, orderBy, orderDirection, where }, { services }) {
      let query = 'SELECT * FROM listings';
      let countQuery = 'SELECT COUNT(*) FROM listings';
      const params = [];
      const conditions = [];

      // Apply filters
      if (where) {
        if (where.seller) {
          conditions.push(`seller_address = $${params.length + 1}`);
          params.push(where.seller);
        }
        if (where.tokenId) {
          conditions.push(`token_id = $${params.length + 1}`);
          params.push(where.tokenId);
        }
        if (where.active !== undefined) {
          conditions.push(`active = $${params.length + 1}`);
          params.push(where.active);
        }
        if (where.minPrice) {
          conditions.push(`price_per_token >= $${params.length + 1}`);
          params.push(where.minPrice);
        }
        if (where.maxPrice) {
          conditions.push(`price_per_token <= $${params.length + 1}`);
          params.push(where.maxPrice);
        }
        if (where.expiresAfter) {
          conditions.push(`expiration >= $${params.length + 1}`);
          params.push(where.expiresAfter);
        }
        if (where.expiresBefore) {
          conditions.push(`expiration <= $${params.length + 1}`);
          params.push(where.expiresBefore);
        }
      }

      if (conditions.length > 0) {
        const whereClause = ` WHERE ${conditions.join(' AND ')}`;
        query += whereClause;
        countQuery += whereClause;
      }

      // Apply ordering
      const orderByMap = {
        CREATED_AT: 'created_at',
        UPDATED_AT: 'updated_at',
        PRICE_PER_TOKEN: 'price_per_token',
        TOTAL_PRICE: 'total_price',
        EXPIRATION: 'expiration'
      };
      
      const orderColumn = orderByMap[orderBy] || 'created_at';
      const direction = orderDirection === 'ASC' ? 'ASC' : 'DESC';
      query += ` ORDER BY ${orderColumn} ${direction}`;

      // Apply pagination
      query += ` LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
      params.push(first, skip);

      const [result, countResult] = await Promise.all([
        services.database.query(query, params),
        services.database.query(countQuery, params.slice(0, -2))
      ]);

      const totalCount = parseInt(countResult.rows[0].count);

      return {
        edges: result.rows.map((listing, index) => ({
          node: listing,
          cursor: Buffer.from(`${skip + index}`).toString('base64')
        })),
        pageInfo: {
          hasNextPage: skip + first < totalCount,
          hasPreviousPage: skip > 0,
          startCursor: result.rows.length > 0 ? Buffer.from(`${skip}`).toString('base64') : null,
          endCursor: result.rows.length > 0 ? Buffer.from(`${skip + result.rows.length - 1}`).toString('base64') : null
        },
        totalCount
      };
    },

    // Analytics Queries
    async marketStats(_, __, { services }) {
      const [volumeResult, listingsResult, offersResult, tradersResult] = await Promise.all([
        services.database.query(`
          SELECT 
            COALESCE(SUM(total_price), 0) as total_volume,
            COUNT(*) as total_sales,
            COALESCE(AVG(total_price), 0) as average_sale_price,
            COALESCE(SUM(CASE WHEN created_at >= NOW() - INTERVAL '24 hours' THEN total_price ELSE 0 END), 0) as volume_24h,
            COUNT(CASE WHEN created_at >= NOW() - INTERVAL '24 hours' THEN 1 END) as sales_24h,
            COALESCE(SUM(CASE WHEN created_at >= NOW() - INTERVAL '7 days' THEN total_price ELSE 0 END), 0) as volume_7d,
            COUNT(CASE WHEN created_at >= NOW() - INTERVAL '7 days' THEN 1 END) as sales_7d,
            COALESCE(SUM(CASE WHEN created_at >= NOW() - INTERVAL '30 days' THEN total_price ELSE 0 END), 0) as volume_30d,
            COUNT(CASE WHEN created_at >= NOW() - INTERVAL '30 days' THEN 1 END) as sales_30d
          FROM sales
        `),
        services.database.query('SELECT COUNT(*) as count FROM listings WHERE active = true'),
        services.database.query('SELECT COUNT(*) as count FROM offers WHERE status = \'active\''),
        services.database.query(`
          SELECT COUNT(DISTINCT address) as count FROM (
            SELECT buyer_address as address FROM sales
            UNION
            SELECT seller_address as address FROM sales
          ) traders
        `)
      ]);

      const volume = volumeResult.rows[0];
      const activeListings = parseInt(listingsResult.rows[0].count);
      const activeOffers = parseInt(offersResult.rows[0].count);
      const uniqueTraders = parseInt(tradersResult.rows[0].count);

      // Get floor price
      const floorResult = await services.database.query(`
        SELECT MIN(price_per_token) as floor_price
        FROM listings 
        WHERE active = true AND (expiration IS NULL OR expiration > NOW())
      `);

      return {
        totalVolume: volume.total_volume,
        totalSales: parseInt(volume.total_sales),
        averageSalePrice: Math.round(parseFloat(volume.average_sale_price)),
        activeListings,
        activeOffers,
        uniqueTraders,
        floorPrice: floorResult.rows[0].floor_price || '0',
        volume24h: volume.volume_24h,
        sales24h: parseInt(volume.sales_24h),
        volume7d: volume.volume_7d,
        sales7d: parseInt(volume.sales_7d),
        volume30d: volume.volume_30d,
        sales30d: parseInt(volume.sales_30d),
        lastUpdated: new Date()
      };
    },

    async stemStats(_, __, { services }) {
      const [basicResult, typeResult, genreResult, keyResult] = await Promise.all([
        services.database.query(`
          SELECT 
            COUNT(*) as total_stems,
            COUNT(DISTINCT creator_address) as total_creators,
            COALESCE(SUM(total_supply), 0) as total_supply,
            AVG(duration) as average_duration,
            AVG(bpm) as average_bpm
          FROM stems
        `),
        services.database.query(`
          SELECT stem_type, COUNT(*) as count
          FROM stems 
          WHERE stem_type IS NOT NULL
          GROUP BY stem_type
          ORDER BY count DESC
        `),
        services.database.query(`
          SELECT genre, COUNT(*) as count
          FROM stems 
          WHERE genre IS NOT NULL
          GROUP BY genre
          ORDER BY count DESC
        `),
        services.database.query(`
          SELECT key, COUNT(*) as count
          FROM stems 
          WHERE key IS NOT NULL
          GROUP BY key
          ORDER BY count DESC
        `)
      ];

      const basic = basicResult.rows[0];

      return {
        totalStems: parseInt(basic.total_stems),
        totalCreators: parseInt(basic.total_creators),
        totalSupply: basic.total_supply,
        averageDuration: parseFloat(basic.average_duration) || 0,
        averageBPM: parseFloat(basic.average_bpm) || 0,
        stemTypeDistribution: typeResult.rows.map(row => ({
          stemType: row.stem_type.toUpperCase(),
          count: parseInt(row.count)
        })),
        genreDistribution: genreResult.rows.map(row => ({
          genre: row.genre,
          count: parseInt(row.count)
        })),
        keyDistribution: keyResult.rows.map(row => ({
          key: row.key,
          count: parseInt(row.count)
        })),
        lastUpdated: new Date()
      };
    },

    async recentActivity(_, { limit }, { services }) {
      return await services.indexing.getRecentActivity(limit);
    },

    async searchStems(_, { query, first }, { services }) {
      const result = await services.database.query(`
        SELECT * FROM stems
        WHERE 
          name ILIKE $1 OR 
          description ILIKE $1 OR 
          stem_type ILIKE $1 OR 
          genre ILIKE $1 OR 
          key ILIKE $1
        ORDER BY 
          CASE 
            WHEN name ILIKE $1 THEN 1
            WHEN description ILIKE $1 THEN 2
            WHEN stem_type ILIKE $1 THEN 3
            ELSE 4
          END,
          created_at DESC
        LIMIT $2
      `, [`%${query}%`, first]);

      return result.rows;
    }
  },

  // Type resolvers
  Stem: {
    creator: async (stem, _, { services }) => {
      return await resolvers.Query.creator(_, { address: stem.creator_address }, { services });
    },

    transfers: async (stem, { first }, { services }) => {
      const result = await services.database.query(`
        SELECT * FROM transfers 
        WHERE token_id = $1 
        ORDER BY timestamp DESC 
        LIMIT $2
      `, [stem.token_id, first]);

      return {
        edges: result.rows.map((transfer, index) => ({
          node: transfer,
          cursor: Buffer.from(`${index}`).toString('base64')
        })),
        pageInfo: {
          hasNextPage: result.rows.length === first,
          hasPreviousPage: false,
          startCursor: result.rows.length > 0 ? Buffer.from('0').toString('base64') : null,
          endCursor: result.rows.length > 0 ? Buffer.from(`${result.rows.length - 1}`).toString('base64') : null
        },
        totalCount: result.rows.length
      };
    },

    listings: async (stem, { first, active }, { services }) => {
      let query = 'SELECT * FROM listings WHERE token_id = $1';
      const params = [stem.token_id];

      if (active !== undefined) {
        query += ' AND active = $2';
        params.push(active);
      }

      query += ' ORDER BY created_at DESC LIMIT $' + (params.length + 1);
      params.push(first);

      const result = await services.database.query(query, params);

      return {
        edges: result.rows.map((listing, index) => ({
          node: listing,
          cursor: Buffer.from(`${index}`).toString('base64')
        })),
        pageInfo: {
          hasNextPage: result.rows.length === first,
          hasPreviousPage: false,
          startCursor: result.rows.length > 0 ? Buffer.from('0').toString('base64') : null,
          endCursor: result.rows.length > 0 ? Buffer.from(`${result.rows.length - 1}`).toString('base64') : null
        },
        totalCount: result.rows.length
      };
    },

    sales: async (stem, { first }, { services }) => {
      const result = await services.database.query(`
        SELECT * FROM sales 
        WHERE token_id = $1 
        ORDER BY created_at DESC 
        LIMIT $2
      `, [stem.token_id, first]);

      return {
        edges: result.rows.map((sale, index) => ({
          node: sale,
          cursor: Buffer.from(`${index}`).toString('base64')
        })),
        pageInfo: {
          hasNextPage: result.rows.length === first,
          hasPreviousPage: false,
          startCursor: result.rows.length > 0 ? Buffer.from('0').toString('base64') : null,
          endCursor: result.rows.length > 0 ? Buffer.from(`${result.rows.length - 1}`).toString('base64') : null
        },
        totalCount: result.rows.length
      };
    },

    owners: async (stem, _, { services }) => {
      // This would require tracking current balances, which is complex
      // For now, return empty array - would need to implement balance tracking
      return [];
    },

    floorPrice: async (stem, _, { services }) => {
      const result = await services.database.query(`
        SELECT MIN(price_per_token) as floor_price
        FROM listings 
        WHERE token_id = $1 AND active = true AND (expiration IS NULL OR expiration > NOW())
      `, [stem.token_id]);

      return result.rows[0]?.floor_price || null;
    },

    lastSalePrice: async (stem, _, { services }) => {
      const result = await services.database.query(`
        SELECT total_price
        FROM sales 
        WHERE token_id = $1 
        ORDER BY created_at DESC 
        LIMIT 1
      `, [stem.token_id]);

      return result.rows[0]?.total_price || null;
    },

    totalVolume: async (stem, _, { services }) => {
      const result = await services.database.query(`
        SELECT COALESCE(SUM(total_price), 0) as total_volume
        FROM sales 
        WHERE token_id = $1
      `, [stem.token_id]);

      return result.rows[0].total_volume;
    },

    holdersCount: async (stem, _, { services }) => {
      // This would require balance tracking - return 0 for now
      return 0;
    }
  },

  Creator: {
    stemsCreated: async (creator, _, { services }) => {
      const result = await services.database.query(
        'SELECT * FROM stems WHERE creator_address = $1 ORDER BY created_at DESC',
        [creator.address]
      );
      return result.rows;
    },

    averageSalePrice: async (creator, _, { services }) => {
      const result = await services.database.query(`
        SELECT AVG(s.total_price) as avg_price
        FROM sales s
        JOIN stems st ON s.token_id = st.token_id
        WHERE st.creator_address = $1
      `, [creator.address]);

      return Math.round(parseFloat(result.rows[0].avg_price) || 0);
    },

    topStem: async (creator, _, { services }) => {
      const result = await services.database.query(`
        SELECT st.*, COALESCE(SUM(s.total_price), 0) as volume
        FROM stems st
        LEFT JOIN sales s ON st.token_id = s.token_id
        WHERE st.creator_address = $1
        GROUP BY st.id
        ORDER BY volume DESC, st.created_at DESC
        LIMIT 1
      `, [creator.address]);

      return result.rows[0] || null;
    }
  },

  Transfer: {
    stem: async (transfer, _, { services }) => {
      const result = await services.database.query(
        'SELECT * FROM stems WHERE token_id = $1',
        [transfer.token_id]
      );
      return result.rows[0];
    },

    isMint: (transfer) => {
      return transfer.from_address === '0x0000000000000000000000000000000000000000';
    },

    isBurn: (transfer) => {
      return transfer.to_address === '0x0000000000000000000000000000000000000000';
    }
  },

  Listing: {
    stem: async (listing, _, { services }) => {
      const result = await services.database.query(
        'SELECT * FROM stems WHERE token_id = $1',
        [listing.token_id]
      );
      return result.rows[0];
    },

    isExpired: (listing) => {
      return listing.expiration && new Date(listing.expiration) < new Date();
    },

    timeRemaining: (listing) => {
      if (!listing.expiration) return null;
      const remaining = new Date(listing.expiration).getTime() - Date.now();
      return Math.max(0, Math.floor(remaining / 1000));
    }
  },

  Sale: {
    listing: async (sale, _, { services }) => {
      const result = await services.database.query(
        'SELECT * FROM listings WHERE listing_id = $1',
        [sale.listing_id]
      );
      return result.rows[0];
    },

    stem: async (sale, _, { services }) => {
      const result = await services.database.query(
        'SELECT * FROM stems WHERE token_id = $1',
        [sale.token_id]
      );
      return result.rows[0];
    }
  },

  Offer: {
    listing: async (offer, _, { services }) => {
      const result = await services.database.query(
        'SELECT * FROM listings WHERE listing_id = $1',
        [offer.listing_id]
      );
      return result.rows[0];
    },

    isExpired: (offer) => {
      return offer.expiration && new Date(offer.expiration) < new Date();
    },

    timeRemaining: (offer) => {
      if (!offer.expiration) return null;
      const remaining = new Date(offer.expiration).getTime() - Date.now();
      return Math.max(0, Math.floor(remaining / 1000));
    }
  },

  Activity: {
    stem: async (activity, _, { services }) => {
      const result = await services.database.query(
        'SELECT * FROM stems WHERE token_id = $1',
        [activity.token_id]
      );
      return result.rows[0];
    }
  }
};
