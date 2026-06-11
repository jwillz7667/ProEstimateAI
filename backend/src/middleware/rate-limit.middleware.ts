import rateLimit from 'express-rate-limit';
import { RedisStore } from 'rate-limit-redis';
import { getRedis } from '../config/redis';
import { env } from '../config/env';

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

// Without Redis the limiter uses an in-memory store that is per-process. On a
// multi-instance Railway deployment that means the effective ceiling is
// `max × instanceCount` from an attacker's view, so a shared store is the only
// way to enforce a true global cap. We can't tighten generic traffic without
// hurting legitimate bursts, but the auth surface (credential stuffing /
// brute force) is worth a stricter per-process cap in that exact degraded
// state: production AND no shared store.
const hasSharedRateLimitStore = getRedis() !== null;
const authRateLimitMax =
  env.NODE_ENV === 'production' && !hasSharedRateLimitStore ? 15 : 30;

export const globalRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  store: buildStore(),
  // Railway Redis can transiently close or fail DNS resolution. Do not turn a
  // rate-limit store outage into a production-wide 500, especially before auth.
  passOnStoreError: true,
  message: { ok: false, error: { code: 'RATE_LIMIT', message: 'Too many requests', retryable: true } },
});

export const authRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: authRateLimitMax,
  standardHeaders: true,
  legacyHeaders: false,
  store: buildStore(),
  // Availability beats strict brute-force throttling during Redis incidents;
  // auth still validates credentials and keeps generic failure messages.
  passOnStoreError: true,
  message: { ok: false, error: { code: 'RATE_LIMIT', message: 'Too many auth requests', retryable: true } },
});

export const shareRateLimit = rateLimit({
  windowMs: 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  store: buildStore(),
  // Public, unauthenticated proposal-share endpoints (GET + respond) are
  // reachable by anyone holding a token, so they're the natural surface for
  // token-guessing and scraping. 20/min per IP is a soft cap — a genuine
  // client views the proposal and responds a handful of times, far under it.
  passOnStoreError: true,
  message: { ok: false, error: { code: 'RATE_LIMIT', message: 'Too many requests', retryable: true } },
});
