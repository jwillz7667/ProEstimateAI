import { Router, Request, Response } from 'express';
import { prisma } from '../../config/database';
import { getRedis } from '../../config/redis';
import { sendSuccess, sendError } from '../../lib/envelope';
import { logger } from '../../config/logger';

const router = Router();

// A health probe must answer fast. If a dependency doesn't respond within this
// window we treat it as down rather than letting the orchestrator's own
// timeout fire — a hung Postgres connection should surface as 503, not as a
// request that never returns.
const PROBE_TIMEOUT_MS = 2_000;

function withTimeout<T>(work: Promise<T>, ms: number, label: string): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(
      () => reject(new Error(`${label} probe timed out after ${ms}ms`)),
      ms,
    );
    work.then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (err) => {
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}

/**
 * Liveness + readiness probe.
 *
 * Postgres is a hard dependency: with the database unreachable the API can
 * serve no authenticated request, so we return 503 and let Railway / the load
 * balancer recycle the instance. Redis is a soft dependency (rate-limit store
 * and cache) — when it's down we degrade to in-memory behavior and report
 * `degraded` with a 200 so a transient Redis blip doesn't take the whole
 * service out of rotation.
 */
router.get('/', async (_req: Request, res: Response) => {
  let databaseConnected = true;
  try {
    await withTimeout(prisma.$queryRaw`SELECT 1`, PROBE_TIMEOUT_MS, 'database');
  } catch (err) {
    databaseConnected = false;
    logger.error({ err }, 'Health check: database probe failed');
  }

  const redis = getRedis();
  let redisStatus: 'connected' | 'disconnected' | 'disabled' = 'disabled';
  if (redis) {
    try {
      await withTimeout(redis.ping(), PROBE_TIMEOUT_MS, 'redis');
      redisStatus = 'connected';
    } catch (err) {
      redisStatus = 'disconnected';
      logger.warn({ err }, 'Health check: redis probe failed');
    }
  }

  if (!databaseConnected) {
    sendError(res, 503, {
      code: 'SERVICE_UNAVAILABLE',
      message: 'Database unavailable',
      retryable: true,
    });
    return;
  }

  const status = redisStatus === 'disconnected' ? 'degraded' : 'healthy';
  sendSuccess(res, {
    status,
    database: 'connected',
    redis: redisStatus,
  });
});

export default router;
