# ---------- builder ----------
FROM node:24-slim AS builder
WORKDIR /app

ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}

COPY package.json package-lock.json ./
RUN npm config set fetch-retries 5 \
 && npm config set fetch-retry-mintimeout 20000 \
 && npm config set fetch-retry-maxtimeout 120000 \
 && for i in 1 2 3; do npm ci && break || (echo "npm ci attempt $i failed, retrying..." && sleep 10); done
COPY . .
RUN npm run build

# ---------- runner ----------
FROM node:24-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000

COPY package.json package-lock.json ./
RUN for i in 1 2 3; do npm ci --omit=dev && break || (echo "npm ci attempt $i failed, retrying..." && sleep 10); done \
 && npm cache clean --force

COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/next.config.mjs ./next.config.mjs

RUN groupadd -r nodejs && useradd -r -g nodejs nextjs
USER nextjs
EXPOSE 3000
CMD ["npx", "next", "start"]