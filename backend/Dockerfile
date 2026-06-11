FROM node:20-alpine AS builder
RUN apk add --no-cache openssl
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npx prisma generate
RUN npm run build

FROM node:20-alpine AS runner
RUN apk add --no-cache openssl curl
RUN addgroup -g 1001 -S nodejs && adduser -S appuser -u 1001
WORKDIR /app
COPY --from=builder --chown=appuser:nodejs /app/dist ./dist
COPY --from=builder --chown=appuser:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=appuser:nodejs /app/package.json ./
COPY --from=builder --chown=appuser:nodejs /app/prisma ./prisma

USER appuser
EXPOSE 3000

# start-period covers the cold-boot window: `prisma migrate deploy` runs
# before the server binds, so a 10s grace marked the container unhealthy
# (and triggered a restart loop) whenever migrations took longer. 90s leaves
# ample headroom for migrations + JIT warmup before failed probes count.
HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

# Use exec form so SIGTERM is forwarded directly to node (not shell).
# Order matters and each step must succeed before the next (&&):
#   1. pre-deploy-indexes: builds performance indexes with CREATE INDEX
#      CONCURRENTLY (no table-write lock). Must run OUTSIDE the migration
#      transaction, so it cannot live in a migration file — hence a separate
#      step before migrate deploy. Idempotent; a no-op once indexes exist.
#   2. migrate deploy: applies schema migrations (these take their normal lock,
#      but the heavy index builds already happened lock-free in step 1).
#   3. server: exec so node is PID 1 and receives SIGTERM directly.
CMD ["sh", "-c", "node dist/scripts/pre-deploy-indexes.js && npx prisma migrate deploy && exec node dist/index.js"]
