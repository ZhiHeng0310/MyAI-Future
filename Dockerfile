FROM ghcr.io/cirruslabs/flutter:3.41.0 AS build

WORKDIR /app

COPY . .

RUN flutter --version
RUN flutter pub get
RUN flutter build web

FROM nginx:alpine

COPY --from=build /app/build/web /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]