import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { UpdateUserInput } from './users.validators';
import { invalidateCache, CacheKeys } from '../../config/redis';

export async function getMe(userId: string) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
  });

  if (!user) {
    throw new NotFoundError('User', userId);
  }

  return user;
}

export async function updateMe(userId: string, data: UpdateUserInput) {
  const existing = await prisma.user.findUnique({ where: { id: userId } });
  if (!existing) throw new NotFoundError('User', userId);

  const updateData: Record<string, unknown> = {};
  if (data.full_name !== undefined) updateData.fullName = data.full_name;
  if (data.phone !== undefined) updateData.phone = data.phone;
  if (data.avatar_url !== undefined) updateData.avatarUrl = data.avatar_url;

  const updated = await prisma.user.update({ where: { id: userId }, data: updateData });

  await invalidateCache(CacheKeys.userProfile(userId));

  return updated;
}

/**
 * Permanently delete the current user's account and (when they are the sole
 * member of their company) the entire company tenancy.
 *
 * Required by Apple App Store Review Guideline 5.1.1(v) — apps that support
 * account creation must offer in-app account deletion.
 *
 * Deletion order respects foreign-key constraints; we wrap everything in a
 * single transaction so a partial failure rolls back rather than leaving the
 * user in an inconsistent state.
 */
export async function deleteMe(userId: string) {
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, companyId: true, email: true },
  });

  if (!user) {
    throw new NotFoundError('User', userId);
  }

  const { companyId } = user;

  await prisma.$transaction(async (tx) => {
    // Detect whether this user is the sole member of the company tenancy.
    const otherUsers = await tx.user.count({
      where: { companyId, id: { not: userId } },
    });

    // If sole owner, wipe all company-scoped data first so the company row
    // can be deleted at the end without FK constraint violations.
    if (otherUsers === 0) {
      await tx.invoiceLineItem.deleteMany({
        where: { invoice: { companyId } },
      });
      await tx.invoice.deleteMany({ where: { companyId } });

      await tx.proposal.deleteMany({ where: { companyId } });

      await tx.estimateLineItem.deleteMany({
        where: { estimate: { companyId } },
      });
      await tx.estimate.deleteMany({ where: { companyId } });

      // MaterialSuggestion / AIGeneration / Asset cascade from Project on delete.
      await tx.project.deleteMany({ where: { companyId } });

      await tx.client.deleteMany({ where: { companyId } });

      // LaborRateRule cascades via PricingProfile.onDelete: Cascade, so
      // deleting the profiles below is sufficient. The explicit deleteMany
      // here is belt-and-suspenders in case the schema changes.
      await tx.laborRateRule.deleteMany({
        where: { pricingProfile: { companyId } },
      });
      await tx.pricingProfile.deleteMany({ where: { companyId } });
    }

    // Per-user records that are not auto-cascaded by the schema.
    await tx.refreshToken.deleteMany({ where: { userId } });
    await tx.purchaseAttempt.deleteMany({ where: { userId } });
    await tx.subscriptionEvent.deleteMany({ where: { userId } });
    await tx.usageEvent.deleteMany({ where: { userId } });
    await tx.usageBucket.deleteMany({ where: { userId } });
    await tx.activityLogEntry.deleteMany({ where: { userId } });
    await tx.userEntitlement.deleteMany({ where: { userId } });
    // UserIdentity has onDelete: Cascade and is removed automatically.

    await tx.user.delete({ where: { id: userId } });

    if (otherUsers === 0) {
      await tx.company.delete({ where: { id: companyId } });
    }
  });

  await invalidateCache(CacheKeys.userProfile(userId));
}
