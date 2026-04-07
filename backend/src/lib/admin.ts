import { prisma } from '../config/database';
import { env } from '../config/env';
import { logger } from '../config/logger';

/**
 * Parsed set of admin emails from the ADMIN_EMAILS env var.
 * Comma-separated, lowercased, cached at module load time.
 */
const adminEmails: Set<string> = new Set(
  env.ADMIN_EMAILS
    .split(',')
    .map((e) => e.trim().toLowerCase())
    .filter(Boolean),
);

if (adminEmails.size > 0) {
  logger.info({ count: adminEmails.size }, 'Admin emails configured');
}

/**
 * Check if a userId belongs to an admin user.
 * Queries the user's email and checks against the ADMIN_EMAILS env var.
 * Results are cached in-memory for the process lifetime.
 */
const adminUserCache = new Map<string, boolean>();

export async function isAdminUser(userId: string): Promise<boolean> {
  if (adminEmails.size === 0) return false;

  const cached = adminUserCache.get(userId);
  if (cached !== undefined) return cached;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { email: true },
  });

  const isAdmin = !!user && adminEmails.has(user.email.toLowerCase());
  adminUserCache.set(userId, isAdmin);
  return isAdmin;
}
