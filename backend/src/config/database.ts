import { PrismaClient } from '@prisma/client';

/**
 * Prisma Client singleton with production-tuned settings.
 *
 * Connection pool is configured via DATABASE_URL query params:
 *   ?connection_limit=20&pool_timeout=30&connect_timeout=10
 *
 * In production (Railway), the default pool size is adequate for a single
 * container. Scale horizontally by adding containers, not increasing pool.
 */
export const prisma = new PrismaClient({
  log: process.env.NODE_ENV === 'development'
    ? ['query', 'warn', 'error']
    : ['warn', 'error'],
});
