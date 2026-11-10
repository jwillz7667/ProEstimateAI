import { randomUUID } from 'node:crypto';
import { beforeEach, describe, expect, it } from 'vitest';
import type { EntitlementStatus } from '@prisma/client';
import { prisma } from '../../src/config/database';
import { bootstrapCatalog } from '../../src/lib/catalog-bootstrap';
import { ensureAccountTrial, readAccessEntitlement } from '../../src/lib/account-trial';
import { getEffectiveEntitlement, handleAppStoreWebhook } from '../../src/modules/commerce/commerce.service';
import { gateAIAction } from '../../src/modules/commerce/entitlement-gate';
import { assertCanCreateInvoice } from '../../src/modules/invoices/invoices.service';
import { assertFollowUpAccess } from '../../src/modules/follow-ups/follow-ups.target';
import { buildAppleTransactionInfo, buildDecodedNotification, resetCommerceTables } from './helpers';

beforeEach(async () => { await resetCommerceTables(); await bootstrapCatalog(prisma); });

async function account(status: EntitlementStatus = 'FREE') {
  const company = await prisma.company.create({ data: { name: 'Seven-day trial regression' } });
  const user = await prisma.user.create({ data: {
    companyId: company.id, email: `${randomUUID()}@example.test`, fullName: 'Trial user', role: 'OWNER',
  } });
  const plan = await prisma.plan.findUniqueOrThrow({ where: { code: status === 'FREE' ? 'FREE_STARTER' : 'PRO_MONTHLY' } });
  const endsAt = new Date(Date.now() + (status === 'PRO_ACTIVE' ? 30 : -5) * 86_400_000);
  const entitlement = await prisma.userEntitlement.create({ data: {
    userId: user.id, companyId: company.id, planId: plan.id, status,
    source: status === 'FREE' ? null : 'APP_STORE',
    endsAt: status === 'FREE' ? null : endsAt,
    trialEndsAt: status === 'EXPIRED' ? endsAt : null,
    isAutoRenewEnabled: status === 'PRO_ACTIVE',
  } });
  return { user, company, entitlement };
}

describe('seven-day account trial', () => {
  it('grants all seven days once under concurrent first-login refreshes without overwriting Apple state', async () => {
    const t = await account();
    const snapshots = await Promise.all(Array.from({ length: 6 }, () => getEffectiveEntitlement(t.user.id, t.company.id)));
    expect(snapshots.every((s) => s.subscription_state === 'TRIAL_ACTIVE' && s.source === 'ACCOUNT_TRIAL' && s.is_auto_renew_enabled === false)).toBe(true);
    expect(new Set(snapshots.map((s) => s.trial_ends_at)).size).toBe(1);
    const saved = await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: t.user.id } });
    expect(saved.accountTrialEndsAt!.getTime() - saved.accountTrialStartedAt!.getTime()).toBe(7 * 86_400_000);
    expect(saved.accountTrialStartedAt!.getTime()).toBeGreaterThanOrEqual(t.entitlement.createdAt.getTime());
    expect(saved.status).toBe('FREE');
    expect(saved.trialEndsAt).toBeNull();
    expect(Object.values(snapshots[0].feature_flags).every(Boolean)).toBe(true);
    await getEffectiveEntitlement(t.user.id, t.company.id);
    expect((await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: t.user.id } })).accountTrialEndsAt).toEqual(saved.accountTrialEndsAt);
  });

  it.each(['EXPIRED', 'REVOKED', 'BILLING_RETRY'] as const)('also gives an existing %s user a fresh account trial', async (status) => {
    const t = await account(status);
    const snapshot = await getEffectiveEntitlement(t.user.id, t.company.id);
    expect(snapshot).toMatchObject({ subscription_state: 'TRIAL_ACTIVE', source: 'ACCOUNT_TRIAL', renewal_date: null, is_auto_renew_enabled: false });
    expect(Date.parse(snapshot.trial_ends_at!)).toBeGreaterThan(Date.now() + 6.99 * 86_400_000);
    const saved = await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: t.user.id } });
    expect(saved.status).toBe(status);
    expect(saved.trialEndsAt).toEqual(t.entitlement.trialEndsAt);
    expect(saved.endsAt).toEqual(t.entitlement.endsAt);
  });

  it('backfills a missing legacy entitlement and starts the trial at its first refresh', async () => {
    const t = await account();
    await prisma.userEntitlement.delete({ where: { userId: t.user.id } });
    const result = await getEffectiveEntitlement(t.user.id, t.company.id);
    expect(result.source).toBe('ACCOUNT_TRIAL');
    expect(await prisma.userEntitlement.count({ where: { userId: t.user.id } })).toBe(1);
  });

  it('preserves paid access, renewal dates, prices and subscription identity', async () => {
    const t = await account('PRO_ACTIVE');
    const before = await prisma.subscriptionProduct.findMany();
    const snapshot = await getEffectiveEntitlement(t.user.id, t.company.id);
    expect(snapshot).toMatchObject({ subscription_state: 'PRO_ACTIVE', source: 'APP_STORE', is_auto_renew_enabled: true, trial_ends_at: null });
    expect(snapshot.ends_at).toBe(t.entitlement.endsAt!.toISOString());
    expect(await prisma.subscriptionProduct.findMany()).toEqual(before);
  });

  it('authorizes AI, invoices and follow-ups with finite Pro limits during the account trial', async () => {
    const t = await account();
    await getEffectiveEntitlement(t.user.id, t.company.id);
    const plan = await prisma.plan.findUniqueOrThrow({ where: { code: 'PRO_MONTHLY' } });
    await prisma.plan.update({ where: { id: plan.id }, data: {
      featuresJson: { CAN_CREATE_INVOICE: true, CAN_SHARE_APPROVAL_LINK: true, LIMITS: { AI_GENERATION: { monthly: 2 } } },
    } });
    const attempts = await Promise.allSettled(Array.from({ length: 6 }, () => gateAIAction({ userId: t.user.id, companyId: t.company.id, metric: 'AI_GENERATION' })));
    expect(attempts.filter((a) => a.status === 'fulfilled')).toHaveLength(2);
    expect(await prisma.usageEvent.count()).toBe(2);
    await expect(assertCanCreateInvoice(t.user.id)).resolves.toBeUndefined();
    await prisma.$transaction((tx) => assertFollowUpAccess(tx, t.company.id, t.user.id, true));
    const snapshot = await getEffectiveEntitlement(t.user.id, t.company.id);
    expect(snapshot.usage.find((b) => b.metric_code === 'AI_GENERATION')?.remaining_quantity).toBe(0);
  });

  it('expires permanently without a subscription and never restarts on refresh or restore', async () => {
    const t = await account();
    await ensureAccountTrial(t.user.id, t.company.id);
    const end = new Date(Date.now() - 1000);
    const started = new Date(end.getTime() - 7 * 86_400_000);
    await prisma.userEntitlement.update({ where: { userId: t.user.id }, data: { accountTrialStartedAt: started, accountTrialEndsAt: end } });
    for (let i = 0; i < 3; i++) {
      const snapshot = await getEffectiveEntitlement(t.user.id, t.company.id);
      expect(snapshot.subscription_state).toBe('FREE');
      expect(Object.values(snapshot.feature_flags).some(Boolean)).toBe(false);
    }
    expect((await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: t.user.id } })).accountTrialEndsAt).toEqual(end);
    await expect(gateAIAction({ userId: t.user.id, companyId: t.company.id, metric: 'AI_GENERATION' })).rejects.toMatchObject({ statusCode: 402 });
    await expect(assertCanCreateInvoice(t.user.id)).rejects.toMatchObject({ statusCode: 402 });
    await expect(gateAIAction({ userId: t.user.id, companyId: t.company.id, metric: 'PROJECT_CREATED' })).resolves.toBeUndefined();
  });

  it('leaves the account-trial clock intact when Apple renews or revokes a subscription', async () => {
    const t = await account();
    await ensureAccountTrial(t.user.id, t.company.id);
    const before = await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: t.user.id } });
    const apple = buildAppleTransactionInfo({ productId: 'proestimate.pro.monthly', signedDate: Date.now() });
    await prisma.userEntitlement.update({ where: { userId: t.user.id }, data: { originalTransactionId: apple.originalTransactionId } });
    await handleAppStoreWebhook(buildDecodedNotification({ notificationType: 'DID_RENEW', transactionInfo: apple }));
    expect((await getEffectiveEntitlement(t.user.id, t.company.id)).source).toBe('APP_STORE');
    await handleAppStoreWebhook(buildDecodedNotification({ notificationType: 'REFUND', transactionInfo: { ...apple, revocationDate: Date.now(), signedDate: Date.now() + 1 } }));
    const after = await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: t.user.id } });
    expect(after.status).toBe('REVOKED');
    expect(after.accountTrialEndsAt).toEqual(before.accountTrialEndsAt);
    expect((await getEffectiveEntitlement(t.user.id, t.company.id)).source).toBe('ACCOUNT_TRIAL');
  });

  it('does not grant or expose a trial across companies or to a deactivated user', async () => {
    const t = await account();
    await expect(ensureAccountTrial(t.user.id, randomUUID())).rejects.toMatchObject({ statusCode: 401 });
    expect(await readAccessEntitlement(t.user.id, randomUUID())).toBeNull();
    await prisma.user.update({ where: { id: t.user.id }, data: { isActive: false } });
    await expect(ensureAccountTrial(t.user.id, t.company.id)).rejects.toMatchObject({ statusCode: 401 });
    expect((await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: t.user.id } })).accountTrialStartedAt).toBeNull();
  });
});
