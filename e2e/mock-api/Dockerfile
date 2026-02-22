# Stage 1: builder
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY tsconfig.json ./
COPY index.ts ./
RUN npm run build

# Stage 2: production
FROM node:22-alpine AS production
WORKDIR /app
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /app/package*.json ./
RUN npm ci --omit=dev
COPY --from=builder /app/build ./build
USER appuser
EXPOSE 4000
CMD ["node", "build/index.js"]
