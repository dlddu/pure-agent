FROM node:22-alpine AS builder

WORKDIR /app
COPY export-handler/package*.json ./
RUN npm ci
COPY export-handler/tsconfig.json ./
COPY export-handler/src ./src
RUN npm run build

FROM node:22-alpine

RUN apk add --no-cache zip git github-cli

WORKDIR /app
COPY --from=builder /app/build ./build
COPY --from=builder /app/node_modules ./node_modules
COPY export-handler/package*.json ./

USER node
CMD ["node", "build/index.js"]
