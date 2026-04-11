import Redis from 'ioredis';
import { env } from './env';
import { logger } from './logger';

// ---------------------------------------------------------------------------
// Redis Client — Singleton
// ---------------------------------------------------------------------------

let redis: Redis | null = null;

/**
 * Get the Redis client singleton.
 * Returns null if REDIS_URL is not configured (graceful degradation).
 */
export function getRedis(): Redis | null {
  if (!env.REDIS_URL) return null;

  if (!redis) {
    redis = new Redis(env.REDIS_URL, {
      maxRetriesPerRequest: 3,
      retryStrategy(times) {
        if (times > 10) return null; // Stop reconnecting after 10 attempts
        return Math.min(times * 200, 5000); // Exponential backoff, max 5s
      },
      enableReadyCheck: true,
      connectTimeout: 5000,
      lazyConnect: false,
    });

    redis.on('connect', () => logger.info('Redis connected'));
    redis.on('error', (err) => logger.error({ err }, 'Redis connection error'));
    redis.on('close', () => logger.warn('Redis connection closed'));
  }

  return redis;
}

/**
 * Gracefully disconnect Redis.
 */
export async function disconnectRedis(): Promise<void> {
  if (redis) {
    await redis.quit();
    redis = null;
    logger.info('Redis disconnected');
  }
}

// ---------------------------------------------------------------------------
// Cache Helpers — Typed, TTL-based
// ---------------------------------------------------------------------------

/**
 * Get a cached value, or compute and cache it.
 * Falls back to computing without cache if Redis is unavailable.
 */
export async function cached<T>(
  key: string,
  ttlSeconds: number,
  compute: () => Promise<T>,
): Promise<T> {
  const client = getRedis();

  if (client) {
    try {
      const hit = await client.get(key);
      if (hit) {
        return JSON.parse(hit) as T;
      }
    } catch (err) {
      logger.warn({ err, key }, 'Redis GET failed — computing fresh');
    }
  }

  const value = await compute();

  if (client) {
    try {
      await client.setex(key, ttlSeconds, JSON.stringify(value));
    } catch (err) {
      logger.warn({ err, key }, 'Redis SETEX failed — result not cached');
    }
  }

  return value;
}

/**
 * Invalidate one or more cache keys.
 */
export async function invalidateCache(...keys: string[]): Promise<void> {
  const client = getRedis();
  if (client && keys.length > 0) {
    try {
      await client.del(...keys);
    } catch (err) {
      logger.warn({ err, keys }, 'Redis DEL failed');
    }
  }
}

/**
 * Invalidate all keys matching a pattern.
 * Uses SCAN (non-blocking) instead of KEYS.
 */
export async function invalidateCachePattern(pattern: string): Promise<void> {
  const client = getRedis();
  if (!client) return;

  try {
    let cursor = '0';
    do {
      const [nextCursor, keys] = await client.scan(cursor, 'MATCH', pattern, 'COUNT', 100);
      cursor = nextCursor;
      if (keys.length > 0) {
        await client.del(...keys);
      }
    } while (cursor !== '0');
  } catch (err) {
    logger.warn({ err, pattern }, 'Redis SCAN+DEL failed');
  }
}

// ---------------------------------------------------------------------------
// Cache Key Builders — Centralized naming
// ---------------------------------------------------------------------------

export const CacheKeys = {
  entitlement: (userId: string) => `entitlement:${userId}`,
  dashboard: (companyId: string, userId: string) => `dashboard:${companyId}:${userId}`,
  commerceProducts: () => 'commerce:products',
  proposalShare: (shareToken: string) => `proposal:share:${shareToken}`,
  materialSearch: (query: string, zip?: string) => `materials:search:${query}:${zip ?? 'all'}`,
  projectMaterials: (type: string, zip?: string) => `materials:project:${type}:${zip ?? 'all'}`,
  userProfile: (userId: string) => `user:${userId}`,
  companyProfile: (companyId: string) => `company:${companyId}`,
} as const;

// Cache TTLs in seconds
export const CacheTTL = {
  ENTITLEMENT: 120,        // 2 minutes — balance freshness with load
  DASHBOARD: 300,          // 5 minutes — aggregate stats don't need real-time
  COMMERCE_PRODUCTS: 3600, // 1 hour — product catalog rarely changes
  PROPOSAL_SHARE: 3600,    // 1 hour — share pages are static
  MATERIAL_SEARCH: 86400,  // 24 hours — retail prices update daily at most
  PROJECT_MATERIALS: 86400, // 24 hours
  USER_PROFILE: 300,       // 5 minutes
  COMPANY_PROFILE: 300,    // 5 minutes
} as const;
