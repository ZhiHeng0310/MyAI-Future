FROM node:20-slim

WORKDIR /app

COPY package*.json ./

# ✅ Use install instead of ci
RUN npm install

COPY . .

EXPOSE 8080

# ❌ REMOVE HEALTHCHECK (Cloud Run doesn't need it)
# HEALTHCHECK ...

CMD ["node", "server.js"]