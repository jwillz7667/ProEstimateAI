import { Request, Response, NextFunction } from 'express';
import { isAdminUser } from '../lib/admin';
import { AuthenticationError, AuthorizationError } from '../lib/errors';

/**
 * Authorize admin-only routes. Must run AFTER `requireAuth` (which populates
 * `req.userId`); deny-by-default — any non-admin or unauthenticated request is
 * rejected. Admin membership is the ADMIN_EMAILS allowlist (see lib/admin.ts).
 */
export async function requireAdmin(
  req: Request,
  _res: Response,
  next: NextFunction,
): Promise<void> {
  const userId = req.userId;
  if (!userId) {
    next(new AuthenticationError());
    return;
  }

  try {
    if (await isAdminUser(userId)) {
      next();
      return;
    }
    next(new AuthorizationError('Admin access required'));
  } catch (err) {
    next(err);
  }
}
