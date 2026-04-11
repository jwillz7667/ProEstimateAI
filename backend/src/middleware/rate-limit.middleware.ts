import rateLimit from 'express-rate-limit';
import { RedisStore } from 'rate-limit-redis';
import { getRedis } from '../config/redis';

/**
 * Build a Redis-backed rate limit store if Redis is available,
 * otherwise fall back to in-memory (acceptable for single-instance).
 */
function buildStore(): RedisStore | undefined {
  const redis = getRedis();
  if (redis) {
    return new RedisStore({
      sendCommand: async (...args: string[]) => {
        // ioredis call() expects (command, ...args)
        const [command, ...rest] = args;
        return redis.call(command, ...rest) as never;
      },
    });
  }
  return undefined;
}

export const globalRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  store: buildStore(),
  message: { ok: false, error: { code: 'RATE_LIMIT', message: 'Too many requests', retryable: true } },
});

export const authRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  store: buildStore(),
  message: { ok: false, error: { code: 'RATE_LIMIT', message: 'Too many auth requests', retryable: true } },
});
