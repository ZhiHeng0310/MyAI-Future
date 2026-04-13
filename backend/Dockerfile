FROM node:20-slim

WORKDIR /app
# Copy package files
COPY package*.json ./

# Install dependencies first (better caching)
RUN npm ci --only=production

# Copy app code
COPY . .

# Cloud Run requires this
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD node -e "require('http').get('http://localhost:8080/api/health', (r) => {process.exit(r.statusCode === 200 ? 0 : 1)})"

CMD ["node", "server.js"]