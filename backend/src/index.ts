import 'dotenv/config';
import http from 'http';
import { createApp } from './app';
import { prisma } from './config/database';
import { env } from './config/env';
import { logger } from './config/logger';
import { disconnectRedis, getRedis } from './config/redis';

async function main() {
  try {
    // Connect to database
    await prisma.$connect();
    logger.info('Database connected');

    // Warm up Redis connection (non-blocking — null if not configured)
    const redis = getRedis();
    if (!redis) {
      logger.warn('REDIS_URL not configured — running without cache (not recommended for production)');
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

    // ─── Graceful Shutdown ─────────────────────────────────
    let isShuttingDown = false;

    async function shutdown(signal: string) {
      if (isShuttingDown) return;
      isShuttingDown = true;

      logger.info({ signal }, 'Shutdown signal received — draining connections');

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
