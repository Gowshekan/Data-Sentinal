# Multi-stage build for search-indexer
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

# Production stage
FROM node:20-alpine

# Install security updates
RUN apk --no-cache upgrade && \
    apk add --no-cache dumb-init curl

# Create app user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

WORKDIR /app

# Copy from builder
COPY --from=builder --chown=appuser:appuser /app/node_modules ./node_modules

# Copy application code
COPY --chown=appuser:appuser src ./src
COPY --chown=appuser:appuser package.json ./

# Switch to non-root user
USER appuser

# Expose port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Use dumb-init
ENTRYPOINT ["dumb-init", "--"]

# Start the service
CMD ["node", "src/indexer.js"]
