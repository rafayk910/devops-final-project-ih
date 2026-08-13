# ---------- builder ----------
FROM node:24-slim AS builder
WORKDIR /app

ARG NEXT_PUBLIC_API_URL
ENV NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}

COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# ---------- runner ----------
FROM node:24-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV PORT=3000

COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY --from=builder /app/.next ./.next
COPY --from=builder /app/public ./public
COPY --from=builder /app/next.config.mjs ./next.config.mjs

RUN groupadd -r nodejs && useradd -r -g nodejs nextjs
USER nextjs
EXPOSE 3000
CMD ["npx", "next", "start"]