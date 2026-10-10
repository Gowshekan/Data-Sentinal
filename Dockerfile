# syntax=docker/dockerfile:1

FROM node:20-alpine AS client-builder
WORKDIR /app/client
COPY client/package*.json ./
RUN npm ci
COPY client/ ./
RUN npm run build

FROM node:20-alpine AS server-deps
WORKDIR /app/server
COPY server/package*.json ./
RUN npm ci --omit=dev

FROM node:20-alpine AS runtime
WORKDIR /app/server
ENV NODE_ENV=production
ENV PORT=5000

# Install production server dependencies
COPY --from=server-deps /app/server/node_modules ./node_modules

# Copy backend source
COPY server/ ./

# Copy built frontend to be served by Express
COPY --from=client-builder /app/client/dist ./public

# Ensure runtime directories exist
RUN mkdir -p uploads quarantine reports

EXPOSE 5000
CMD ["node", "index.js"]
