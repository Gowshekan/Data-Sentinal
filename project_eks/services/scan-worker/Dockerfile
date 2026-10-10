# Multi-stage build for scan-worker
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Production stage
FROM node:20-alpine

# Install security updates
RUN apk --no-cache upgrade && \
    apk add --no-cache dumb-init

# Create app user
RUN addgroup -g 1000 appuser && \
    adduser -D -u 1000 -G appuser appuser

WORKDIR /app

# Copy dependencies from builder
COPY --from=builder --chown=appuser:appuser /app/node_modules ./node_modules

# Copy application code
COPY --chown=appuser:appuser src ./src
COPY --chown=appuser:appuser package.json ./

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD pgrep -f worker.js || exit 1

# Use dumb-init to handle signals properly
ENTRYPOINT ["dumb-init", "--"]

# Start the worker
CMD ["node", "src/worker.js"]
