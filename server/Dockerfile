# DineCircle API — production image.
# Multi-stage: stage 1 compiles TypeScript to dist/, stage 2 runs only the
# compiled JS with production dependencies. The runtime image therefore does
# NOT ship tsx, typescript, or any test harness.

# ── Stage 1: build ──────────────────────────────────────────────────────────
FROM node:24-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json tsconfig.build.json ./
COPY src ./src

# tsc emits JS to dist/; the build script also copies schema.sql next to the
# compiled modules so the runtime can resolve it via import.meta.url.
RUN npm run build

# ── Stage 2: runtime ────────────────────────────────────────────────────────
FROM node:24-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

# Production-only dependencies (tsx, typescript, @types/* are omitted).
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

# Compiled JS + schema.sql from the build stage.
COPY --from=build /app/dist ./dist

# Managed Postgres (Supabase) hands out a CA bundle that the system trust
# store does not include. database_config.ts reads DATABASE_SSL_CA_FILE at
# boot, so the bundle has to exist in the image — otherwise a production
# container dies on readFileSync before it ever serves a request.
COPY database ./database

# Health endpoint is /api/health (unauthenticated, returns JSON). The port is
# read from $PORT because orchestrators assign it at runtime: Render's Docker
# runtime injects PORT=10000, while docker-compose pins 4000. Hardcoding 4000
# here would make the container report itself unhealthy on Render.
EXPOSE 4000
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- "http://127.0.0.1:${PORT:-4000}/api/health" || exit 1

USER node
CMD ["node", "dist/server.js"]
