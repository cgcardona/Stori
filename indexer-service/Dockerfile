# 🎵 TellUrStori V2 - Indexer Service Dockerfile

FROM node:20-alpine

# Set working directory
WORKDIR /app

# Install system dependencies
RUN apk add --no-cache \
    curl \
    git \
    python3 \
    make \
    g++

# Copy package files
COPY package*.json ./

# Install Node.js dependencies
RUN npm ci --only=production && npm cache clean --force

# Create non-root user
RUN addgroup -g 1001 -S nodejs && \
    adduser -S indexer -u 1001

# Create necessary directories
RUN mkdir -p logs && \
    chown -R indexer:nodejs /app

# Copy application code
COPY --chown=indexer:nodejs . .

# Switch to non-root user
USER indexer

# Expose port
EXPOSE 4000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:4000/health || exit 1

# Start the application
CMD ["npm", "start"]
