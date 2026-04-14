FROM node:20-slim
WORKDIR /app
COPY package*.json ./


RUN npm install

COPY . .

# Cloud Run ignores EXPOSE, but it's good for documentation
EXPOSE 8080

# Ensure the app binds to 0.0.0.0, not localhost
CMD ["node", "server.js"]