import 'dotenv/config';
import http from 'http';
import { createApp } from './app';
import { prisma } from './config/database';
import { env } from './config/env';
import { logger } from './config/logger';
import { disconnectRedis, getRedis } from './config/redis';
import {
  markImagelessCompletedGenerationsFailed,
  markStuckGenerationsFailed,
} from './lib/generation-cleanup';

// How often the background reaper re-sweeps generations orphaned by a crash
// between deploys. Unref'd so it never holds the event loop open at shutdown.
const REAPER_INTERVAL_MS = 5 * 60 * 1000;

async function main() {
  try {
    // Connect to database
    await prisma.$connect();
    logger.info('Database connected');

    // Recover any AI generations orphaned by a previous container's
    // crash / SIGKILL / Railway redeploy. processGeneration is
    // fire-and-forget and has no durable queue, so a row that was
    // PROCESSING on a dead container stays PROCESSING forever
    // unless we sweep it here. Runs before we start accepting
    // traffic so clients see a clean state on first reconnect.
    await markStuckGenerationsFailed();

    // Reap generations that report COMPLETED but never stored image bytes
    // (a pre-fix data defect). DRY-RUN ONLY on boot: this surfaces the count
    // in logs without mutating production data. The actual flip-to-FAILED is
    // an explicit, authenticated action via POST /v1/admin/generations/reap,
    // never an automatic prod write on startup.
    await markImagelessCompletedGenerationsFailed(undefined, true);

    // Warm up Redis connection (non-blocking — null if not configured).
    // In production a missing shared store is an operational defect, not a
    // soft warning: rate limiting falls back to a per-process in-memory store
    // (no true global cap across instances) and every cache read recomputes.
    // Surface it at error level so it trips log-based alerting; we still boot
    // (graceful degradation) rather than hard-failing a deploy on it.
    const redis = getRedis();
    if (!redis) {
      const message =
        'REDIS_URL not configured — running without shared cache or rate-limit store';
      if (env.NODE_ENV === 'production') {
        logger.error(message);
      } else {
        logger.warn(message);
      }
    }

    const app = createApp();

    // Use http.Server for graceful shutdown control
    const server = http.createServer(app);

    // Keep-alive timeout should be higher than load balancer's idle timeout
    // Railway/ALB default is 60s, so we set 65s
    server.keepAliveTimeout = 65_000;
    server.headersTimeout = 66_000;

    server.listen(env.PORT, () => {
      logger.info(`Server running on port ${env.PORT} [${env.NODE_ENV}]`);
    });

    // ─── Background Reaper ─────────────────────────────────
    // The boot-time sweep only catches generations orphaned by the *previous*
    // container. A long-lived container can also orphan rows mid-life (a
    // background processGeneration that dies without flipping status). Re-sweep
    // periodically so those reconcile within ~5 min instead of next deploy.
    // unref() lets the process exit even with the timer pending.
    const reaperInterval = setInterval(() => {
      void markStuckGenerationsFailed();
    }, REAPER_INTERVAL_MS);
    reaperInterval.unref();

    // ─── Graceful Shutdown ─────────────────────────────────
    let isShuttingDown = false;

    async function shutdown(signal: string) {
      if (isShuttingDown) return;
      isShuttingDown = true;

      logger.info({ signal }, 'Shutdown signal received — draining connections');

      // 0. Stop the background reaper so it can't fire mid-drain.
      clearInterval(reaperInterval);

      // 1. Stop accepting new connections
      server.close(() => {
        logger.info('HTTP server closed — no more incoming connections');
      });

      // 2. Give in-flight requests time to finish (max 30s)
      const forceTimeout = setTimeout(() => {
        logger.error('Forced shutdown — in-flight requests did not complete in 30s');
        process.exit(1);
      }, 30_000);

      try {
        // 3. Disconnect Redis
        await disconnectRedis();

        // 4. Disconnect database
        await prisma.$disconnect();
        logger.info('All connections closed — exiting cleanly');

        clearTimeout(forceTimeout);
        process.exit(0);
      } catch (err) {
        logger.error({ err }, 'Error during shutdown');
        clearTimeout(forceTimeout);
        process.exit(1);
      }
    }

    process.on('SIGTERM', () => shutdown('SIGTERM'));
    process.on('SIGINT', () => shutdown('SIGINT'));

    // Catch unhandled rejections — log but don't crash (let health checks detect issues)
    process.on('unhandledRejection', (reason) => {
      logger.error({ reason }, 'Unhandled promise rejection');
    });

    process.on('uncaughtException', (err) => {
      logger.fatal({ err }, 'Uncaught exception — shutting down');
      shutdown('uncaughtException');
    });
  } catch (err) {
    logger.fatal(err, 'Failed to start server');
    process.exit(1);
  }
}

main();
