import { Router, Request, Response } from 'express';
import { prisma } from '../../config/database';
import { sendSuccess } from '../../lib/envelope';

const router = Router();

router.get('/', async (_req: Request, res: Response) => {
  try {
    await prisma.$queryRaw`SELECT 1`;
    sendSuccess(res, { status: 'healthy', database: 'connected' });
  } catch {
    sendSuccess(res, { status: 'degraded', database: 'disconnected' });
  }
});

export default router;
