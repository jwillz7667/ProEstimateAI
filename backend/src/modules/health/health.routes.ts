import { Router, Request, Response } from 'express';
import { prisma } from '../../config/database';
import { logger } from '../../config/logger';
import { sendError, sendSuccess } from '../../lib/envelope';

const router = Router();

router.get('/', async (_req: Request, res: Response) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    sendSuccess(res, { status: 'healthy', database: 'connected' });
  } catch (err) {
    // Return 503 (not 200) so Railway's deploy healthcheck and the Docker
    // HEALTHCHECK probe treat a DB-less process as unhealthy and restart it,
    // instead of silently serving a backend whose every query fails.
    logger.error({ err }, 'Health check failed: database unreachable');
    sendError(res, 503, {
      code: 'DATABASE_UNAVAILABLE',
      message: 'Database connection failed',
      retryable: true,
    });
  }
});

export default router;
