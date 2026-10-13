import { Request, Response, NextFunction } from 'express';
import { verifyAccessToken } from '../lib/jwt';
import { AuthenticationError } from '../lib/errors';
import { prisma } from '../config/database';

export async function requireAuth(req: Request, _res: Response, next: NextFunction) {
  const header = req.headers.authorization;
  if (!header || !header.startsWith('Bearer ')) return next(new AuthenticationError('Missing or invalid authorization header'));
  let payload;
  try { payload = verifyAccessToken(header.slice(7)); }
  catch { return next(new AuthenticationError('Invalid or expired access token')); }
  try {
    // Deactivation and tenant changes must take effect immediately, including
    // for an otherwise valid access token issued before the change.
    const user = await prisma.user.findUnique({ where: { id: payload.userId }, select: { isActive: true, companyId: true } });
    if (!user?.isActive || user.companyId !== payload.companyId) return next(new AuthenticationError('Account is unavailable'));
    req.userId = payload.userId;
    req.companyId = user.companyId;
    next();
  } catch (error) { next(error); }
}
