# Use nginx to serve Flutter web
FROM nginx:alpine

# Remove default config
RUN rm -rf /usr/share/nginx/html/*

# Copy Flutter build
COPY build/web /usr/share/nginx/html

# Copy custom config (important for Flutter routing)
COPY nginx.conf /etc/nginx/conf.d/default.conf