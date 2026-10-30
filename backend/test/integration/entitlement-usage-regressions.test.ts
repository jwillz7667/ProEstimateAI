import { randomUUID } from 'node:crypto';
import type { EntitlementStatus } from '@prisma/client';
import { beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../../src/config/database';
import { bootstrapCatalog } from '../../src/lib/catalog-bootstrap';
import { gateAIAction } from '../../src/modules/commerce/entitlement-gate';
import { getEffectiveEntitlement, getProducts, createPurchaseAttempt } from '../../src/modules/commerce/commerce.service';
import { checkAndConsume } from '../../src/modules/usage/usage.service';
import { create as createInvoice } from '../../src/modules/invoices/invoices.service';
import { generateProposalPDF } from '../../src/modules/pdf/pdf.service';
import { resetCommerceTables } from './helpers';

beforeEach(async () => {
  await resetCommerceTables();
  await bootstrapCatalog(prisma);
});

async function account(status: EntitlementStatus = 'PRO_ACTIVE') {
  const company = await prisma.company.create({ data: { name: 'Entitlement audit' } });
  const user = await prisma.user.create({ data: {
    companyId: company.id, email: `${randomUUID()}@example.test`, fullName: 'Entitlement audit',
  } });
  const plan = await prisma.plan.findUniqueOrThrow({ where: { code: 'PRO_MONTHLY' } });
  const entitlement = await prisma.userEntitlement.create({ data: {
    userId: user.id, companyId: company.id, planId: plan.id, status,
    endsAt: new Date(Date.now() + 86_400_000), renewalDate: new Date(Date.now() + 86_400_000),
  } });
  return { company, user, plan, entitlement };
}

describe('authoritative subscription access and quotas', () => {
  it.each(['PRO_ACTIVE', 'TRIAL_ACTIVE', 'CANCELED_ACTIVE', 'GRACE_PERIOD'] as const)('denies expired %s before compute and invoice creation even without a webhook', async (status) => {
    const { company, user } = await account(status);
    const past = new Date(Date.now() - 1000);
    await prisma.userEntitlement.update({ where: { userId: user.id }, data: {
      endsAt: past, renewalDate: past, trialEndsAt: past, gracePeriodEndsAt: past,
    } });
    await expect(gateAIAction({ userId: user.id, companyId: company.id, metric: 'AI_GENERATION' })).rejects.toMatchObject({ statusCode: 402 });
    await expect(createInvoice(company.id, user.id, { project_id: 'unused', client_id: 'unused' })).rejects.toMatchObject({ statusCode: 402 });
    expect(await prisma.usageEvent.count({ where: { userId: user.id } })).toBe(0);
    const snapshot = await getEffectiveEntitlement(user.id, company.id);
    expect(snapshot.subscription_state).toBe('EXPIRED');
    expect(Object.values(snapshot.feature_flags).every((flag) => !flag)).toBe(true);
    expect(snapshot.usage).toEqual([]);
  });

  it.each(['EXPIRED', 'REVOKED', 'BILLING_RETRY'] as const)('never grants %s paid features through a lingering Pro plan/bucket', async (status) => {
    const { company, user } = await account(status);
    await prisma.usageBucket.create({ data: {
      userId: user.id, companyId: company.id, metricCode: 'AI_GENERATION',
      includedQuantity: 999999, source: 'PRO_SUBSCRIPTION',
    } });
    const snapshot = await getEffectiveEntitlement(user.id, company.id);
    expect(Object.values(snapshot.feature_flags).every((flag) => !flag)).toBe(true);
    expect(snapshot.usage).toEqual([]);
    await expect(checkAndConsume(user.id, company.id, 'QUOTE_EXPORT')).rejects.toMatchObject({ statusCode: 402 });
  });

  it('enforces the final quote quota atomically and returns real ledger counters instead of unlimited buckets', async () => {
    const { company, user, plan } = await account();
    await prisma.plan.update({ where: { id: plan.id }, data: { featuresJson: { LIMITS: { QUOTE_EXPORT: { monthly: 2 } } } } });
    await prisma.usageBucket.createMany({ data: [
      { userId: user.id, companyId: company.id, metricCode: 'QUOTE_EXPORT', includedQuantity: 999999, source: 'PRO_SUBSCRIPTION' },
      { userId: user.id, companyId: company.id, metricCode: 'QUOTE_EXPORT', includedQuantity: 3, source: 'STARTER_CREDITS' },
    ] });
    const attempts = await Promise.allSettled(Array.from({ length: 6 }, () => checkAndConsume(user.id, company.id, 'QUOTE_EXPORT')));
    expect(attempts.filter((result) => result.status === 'fulfilled')).toHaveLength(2);
    expect(await prisma.usageEvent.count({ where: { userId: user.id, metricCode: 'QUOTE_EXPORT' } })).toBe(2);
    const snapshot = await getEffectiveEntitlement(user.id, company.id);
    expect(snapshot.usage.filter((bucket) => bucket.metric_code === 'QUOTE_EXPORT')).toEqual([{
      metric_code: 'QUOTE_EXPORT', included_quantity: 2, consumed_quantity: 2, remaining_quantity: 0, source: 'PRO_SUBSCRIPTION',
    }]);
  });

  it('shows monthly paid usage from events and excludes expired events and starter bucket ordering', async () => {
    const { company, user } = await account();
    await prisma.usageBucket.createMany({ data: [
      { userId: user.id, companyId: company.id, metricCode: 'AI_GENERATION', includedQuantity: 5, consumedQuantity: 5, source: 'STARTER_CREDITS' },
      { userId: user.id, companyId: company.id, metricCode: 'AI_GENERATION', includedQuantity: 999999, source: 'PRO_SUBSCRIPTION' },
    ] });
    await prisma.usageEvent.createMany({ data: [
      { userId: user.id, companyId: company.id, metricCode: 'AI_GENERATION', quantity: 2 },
      { userId: user.id, companyId: company.id, metricCode: 'AI_GENERATION', quantity: 9, createdAt: new Date(Date.now() - 31 * 86_400_000) },
    ] });
    const snapshot = await getEffectiveEntitlement(user.id, company.id);
    expect(snapshot.usage.find((bucket) => bucket.metric_code === 'AI_GENERATION')).toEqual({
      metric_code: 'AI_GENERATION', included_quantity: 20, consumed_quantity: 2, remaining_quantity: 18, source: 'PRO_SUBSCRIPTION',
    });
    expect(snapshot.usage.map((bucket) => bucket.metric_code)).toEqual(['AI_GENERATION', 'QUOTE_EXPORT', 'PROJECT_CREATED', 'ESTIMATE_GENERATED']);
  });

  it('refunds server PDF export capacity on render/ownership failure', async () => {
    const { company, user } = await account();
    await expect(generateProposalPDF('missing', company.id, user.id)).rejects.toMatchObject({ statusCode: 404 });
    expect(await prisma.usageEvent.count({ where: { userId: user.id, metricCode: 'QUOTE_EXPORT' } })).toBe(0);
  });

  it('keeps historical Premium SKUs resolvable without advertising or selling them', async () => {
    const { company, user } = await account();
    expect(await prisma.subscriptionProduct.count()).toBe(4);
    expect((await getProducts()).map((product) => product.product_id)).toEqual(['proestimate.pro.monthly', 'proestimate.pro.annual']);
    await expect(createPurchaseAttempt(user.id, company.id, 'proestimate.premium.monthly')).rejects.toMatchObject({ statusCode: 404 });
  });
});
