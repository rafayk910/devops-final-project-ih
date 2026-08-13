# ---------- builder ----------
FROM node:24-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build            # tsc -> dist/

# ---------- runner ----------
FROM node:24-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=builder /app/dist ./dist
RUN addgroup -S nodejs && adduser -S nodejs -G nodejs
USER nodejs
EXPOSE 8706
CMD ["node", "dist/server.js"]