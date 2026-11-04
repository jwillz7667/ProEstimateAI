import type { Request, Response, NextFunction } from "express";
import { prisma } from "../config/database";
import { AuthenticationError, AuthorizationError } from "../lib/errors";

/** Read-only company members cannot bypass native editing controls with direct API calls. */
export async function requireWriteAccess(req: Request, _res: Response, next: NextFunction) {
  if (["GET", "HEAD", "OPTIONS"].includes(req.method)) return next();
  if (!req.userId || !req.companyId) return next(new AuthenticationError());
  try {
    const user = await prisma.user.findFirst({
      where: { id: req.userId, companyId: req.companyId, isActive: true }, select: { role: true },
    });
    if (!user) return next(new AuthenticationError("Account is unavailable"));
    if (user.role === "VIEWER") return next(new AuthorizationError("Your account has read-only access"));
    next();
  } catch (error) { next(error); }
}
