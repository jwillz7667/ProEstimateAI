import type { Plan, Prisma, UserEntitlement } from '@prisma/client';
import { prisma } from '../config/database';
import { AuthenticationError } from './errors';
import { hasEffectiveProAccess } from './entitlement-access';

export const ACCOUNT_TRIAL_DAYS = 7;
export const ACCOUNT_TRIAL_SOURCE = 'ACCOUNT_TRIAL';
type AccessEntitlement = UserEntitlement & { plan: Plan };

/** A derived access record only: never write trial access over Apple's ledger. */
export async function readAccessEntitlement(
  userId: string,
  companyId?: string,
  database: Prisma.TransactionClient = prisma,
): Promise<AccessEntitlement | null> {
  const entitlement = await database.userEntitlement.findUnique({ where: { userId }, include: { plan: true } });
  if (!entitlement || (companyId && entitlement.companyId !== companyId)) return null;
  const now = new Date();
  if (hasEffectiveProAccess(entitlement, now) || !entitlement.accountTrialStartedAt ||
      entitlement.accountTrialStartedAt > now || !entitlement.accountTrialEndsAt || entitlement.accountTrialEndsAt <= now) {
    return entitlement;
  }
  const plan = await database.plan.findUnique({ where: { code: 'PRO_MONTHLY' } });
  if (!plan?.isActive) return entitlement;
  return {
    ...entitlement, plan, planId: plan.id, status: 'TRIAL_ACTIVE', source: ACCOUNT_TRIAL_SOURCE,
    startsAt: entitlement.accountTrialStartedAt, endsAt: entitlement.accountTrialEndsAt,
    trialEndsAt: entitlement.accountTrialEndsAt, renewalDate: null, gracePeriodEndsAt: null,
    isAutoRenewEnabled: false, storeProductId: null, latestTransactionId: null,
    originalTransactionId: null, environment: null,
  };
}

/** Start once at first authenticated entitlement refresh, including legacy users.
 * The same User lock used by purchases serializes initial grant/backfill. */
export async function ensureAccountTrial(userId: string, companyId: string): Promise<void> {
  await prisma.$transaction(async (tx) => {
    await tx.$queryRaw`
      SELECT pg_advisory_xact_lock(hashtext('proestimate:commerce-user'), hashtext(${userId}))::text
    `;
    const user = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT id FROM "User" WHERE id = ${userId} AND "companyId" = ${companyId} AND "isActive" = true FOR UPDATE
    `;
    if (user.length !== 1) throw new AuthenticationError('Account is unavailable');
    const freePlan = await tx.plan.findUniqueOrThrow({ where: { code: 'FREE_STARTER' } });
    await tx.userEntitlement.createMany({
      data: [{ userId, companyId, planId: freePlan.id, status: 'FREE' }], skipDuplicates: true,
    });
    const entitlement = await tx.userEntitlement.findUniqueOrThrow({ where: { userId } });
    if (entitlement.companyId !== companyId) throw new AuthenticationError('Account is unavailable');
    if (entitlement.accountTrialStartedAt !== null) return;
    const startedAt = new Date();
    await tx.userEntitlement.update({ where: { userId }, data: {
      accountTrialStartedAt: startedAt,
      accountTrialEndsAt: new Date(startedAt.getTime() + ACCOUNT_TRIAL_DAYS * 86_400_000),
    } });
  });
}
