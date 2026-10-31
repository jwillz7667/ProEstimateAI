import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import type { Server } from 'node:http';
import type { EntitlementStatus } from '@prisma/client';
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from '../../src/app';
import { prisma } from '../../src/config/database';
import { bootstrapCatalog } from '../../src/lib/catalog-bootstrap';
import { signAccessToken } from '../../src/lib/jwt';
import { gateAIAction } from '../../src/modules/commerce/entitlement-gate';
import { getEffectiveEntitlement } from '../../src/modules/commerce/commerce.service';
import { resetCommerceTables } from './helpers';

const providers = vi.hoisted(() => ({ image: vi.fn(), materials: vi.fn(), labor: vi.fn(), estimate: vi.fn() }));
vi.mock('../../src/lib/image-gen', async (original) => ({ ...await original<object>(), generatePreviewImage: providers.image }));
vi.mock('../../src/lib/material-gen', () => ({ generateMaterialSuggestions: providers.materials, generateLaborEstimates: providers.labor }));
vi.mock('../../src/lib/estimate-gen', () => ({ generateEstimate: providers.estimate }));

let server: Server;
let origin: string;
beforeAll(async () => {
  server = createApp().listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Expected loopback listener');
  origin = `http://127.0.0.1:${address.port}`;
});
afterAll(async () => {
  if (server) await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
});
beforeEach(async () => {
  await resetCommerceTables();
  await bootstrapCatalog(prisma);
  vi.clearAllMocks();
});

async function account(status: EntitlementStatus = 'FREE', source?: string) {
  const company = await prisma.company.create({ data: { name: 'Subscription policy audit' } });
  const user = await prisma.user.create({ data: { companyId: company.id, email: `${randomUUID()}@example.test`, fullName: 'Policy audit' } });
  const plan = await prisma.plan.findUniqueOrThrow({ where: { code: status === 'FREE' ? 'FREE_STARTER' : 'PRO_MONTHLY' } });
  const end = new Date(Date.now() + 7 * 86_400_000);
  await prisma.userEntitlement.create({ data: {
    userId: user.id, companyId: company.id, planId: plan.id, status, source,
    endsAt: status === 'FREE' ? null : end, trialEndsAt: status === 'TRIAL_ACTIVE' ? end : null,
  } });
  const project = await prisma.project.create({ data: { companyId: company.id, title: 'Existing project' } });
  const token = signAccessToken({ userId: user.id, companyId: company.id });
  const request = (path: string, method = 'GET', body?: object) => fetch(`${origin}/v1${path}`, {
    method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { company, user, plan, project, request };
}

describe('subscription-only AI and free basic access', () => {
  it('rejects image and text-only AI despite historical starter/custom credits before any provider work', async () => {
    const t = await account();
    await prisma.usageBucket.createMany({ data: ['STARTER_CREDITS', 'CUSTOM_GRANT'].map((source) => ({
      userId: t.user.id, companyId: t.company.id, metricCode: 'AI_GENERATION' as const,
      includedQuantity: 1000, consumedQuantity: 2, source,
    })) });
    for (const generate_preview of [true, false]) {
      const response = await t.request(`/projects/${t.project.id}/generations`, 'POST', { prompt: 'Remodel this kitchen', generate_preview });
      expect(response.status).toBe(402);
      expect(await response.json()).toMatchObject({ error: { paywall: { placement: 'TRIAL_OFFER', blocking: true } } });
    }
    expect((await t.request('/estimates/generate', 'POST', { project_id: t.project.id })).status).toBe(402);
    expect(Object.values(providers).every((provider) => provider.mock.calls.length === 0)).toBe(true);
    expect(await prisma.aIGeneration.count()).toBe(0);
    expect(await prisma.usageEvent.count()).toBe(0);
    expect((await prisma.usageBucket.findMany({ where: { userId: t.user.id } })).every((bucket) => bucket.consumedQuantity === 2)).toBe(true);
    const snapshot = await getEffectiveEntitlement(t.user.id, t.company.id);
    expect(Object.values(snapshot.feature_flags).every((flag) => !flag)).toBe(true);
    expect(snapshot.usage).toEqual([]);
  });

  it.each(['FREE', 'EXPIRED', 'REVOKED', 'BILLING_RETRY', 'PRO_ACTIVE', 'TRIAL_ACTIVE'] as const)(
    'keeps sign-in data, manual projects and manual estimates available for %s without AI quota', async (state) => {
      const t = await account(state);
      for (let index = 0; index < 3; index++) {
        expect((await t.request('/projects', 'POST', { title: `Manual ${index}`, ai_preview_enabled: false })).status).toBe(201);
      }
      expect((await t.request('/projects')).status).toBe(200);
      expect((await t.request(`/projects/${t.project.id}`)).status).toBe(200);
      expect((await t.request('/estimates', 'POST', { project_id: t.project.id })).status).toBe(201);
      expect(await prisma.usageEvent.count({ where: { userId: t.user.id } })).toBe(0);
    },
  );

  it('backfills only missing legacy Free entitlement and does not require upgrade to open basic tools', async () => {
    const t = await account();
    await prisma.userEntitlement.delete({ where: { userId: t.user.id } });
    const results = await Promise.all(Array.from({ length: 5 }, () => getEffectiveEntitlement(t.user.id, t.company.id)));
    expect(results.every((snapshot) => snapshot.subscription_state === 'FREE' && snapshot.usage.length === 0)).toBe(true);
    expect(await prisma.userEntitlement.count({ where: { userId: t.user.id } })).toBe(1);
    expect((await t.request('/projects', 'POST', { title: 'Legacy manual', ai_preview_enabled: false })).status).toBe(201);
    expect((await t.request(`/projects/${t.project.id}/generations`, 'POST', { prompt: 'Kitchen update' })).status).toBe(402);
  });

  it('does not grant unlimited billing rights to an allowlisted admin email', async () => {
    const t = await account();
    const child = execFileSync('node', ['-e', `
      const { prisma } = require('./dist/config/database');
      const { gateAIAction } = require('./dist/modules/commerce/entitlement-gate');
      const { getEffectiveEntitlement } = require('./dist/modules/commerce/commerce.service');
      (async () => {
        const snapshot = await getEffectiveEntitlement(${JSON.stringify(t.user.id)}, ${JSON.stringify(t.company.id)});
        if (snapshot.subscription_state !== 'FREE') throw new Error('Admin email received implicit Pro');
        let blocked = false;
        try { await gateAIAction({ userId: ${JSON.stringify(t.user.id)}, companyId: ${JSON.stringify(t.company.id)}, metric: 'AI_GENERATION' }); }
        catch (error) { if (error.statusCode !== 402) throw error; blocked = true; }
        if (!blocked) throw new Error('Admin email bypassed subscription gate');
      })().then(() => prisma.$disconnect()).catch(async error => { console.error(error.message); await prisma.$disconnect(); process.exitCode = 1; });
    `], { env: { ...process.env, DATABASE_URL: process.env.TEST_DATABASE_URL, ADMIN_EMAILS: t.user.email }, stdio: 'pipe', timeout: 15_000 });
    expect(child).toBeDefined();
    expect(await prisma.usageEvent.count()).toBe(0);
  });

  it('allows only the explicit review grant and applies its finite Pro limit', async () => {
    const unrelated = await account('ADMIN_OVERRIDE', 'MANUAL');
    await expect(gateAIAction({ userId: unrelated.user.id, companyId: unrelated.company.id, metric: 'AI_GENERATION' })).rejects.toMatchObject({ statusCode: 402 });
    const review = await account('ADMIN_OVERRIDE', 'APP_REVIEW_DEMO');
    await prisma.plan.update({ where: { id: review.plan.id }, data: { featuresJson: { LIMITS: { AI_GENERATION: { monthly: 1 } } } } });
    const attempts = await Promise.allSettled(Array.from({ length: 5 }, () => gateAIAction({ userId: review.user.id, companyId: review.company.id, metric: 'AI_GENERATION' })));
    expect(attempts.filter((result) => result.status === 'fulfilled')).toHaveLength(1);
    expect(await prisma.usageEvent.count({ where: { userId: review.user.id } })).toBe(1);
  });

  it('changes only future offer catalog and manual-project caps, preserving old signed trials and balances', async () => {
    const t = await account('TRIAL_ACTIVE', 'APP_STORE');
    const before = await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: t.user.id } });
    const bucket = await prisma.usageBucket.create({ data: { userId: t.user.id, companyId: t.company.id, metricCode: 'AI_GENERATION', source: 'STARTER_CREDITS', includedQuantity: 5, consumedQuantity: 3 } });
    await prisma.subscriptionProduct.updateMany({ where: { storeProductId: { startsWith: 'proestimate.pro.' } }, data: { introOfferDisplayText: '7-day free trial', hasIntroOffer: false } });
    await prisma.plan.update({ where: { id: t.plan.id }, data: { featuresJson: { LIMITS: { PROJECT_CREATED: { monthly: 2 }, AI_GENERATION: { monthly: 20 } } } } });
    // libpq does not accept Prisma's schema parameter. Keep SSL and other
    // connection options intact rather than dropping the full query string.
    const psqlUrl = new URL(process.env.TEST_DATABASE_URL!);
    psqlUrl.searchParams.delete('schema');
    execFileSync('psql', [psqlUrl.toString(), '-v', 'ON_ERROR_STOP=1', '-f', resolve('prisma/migrations/20261030120000_subscription_trial_gates/migration.sql')], { stdio: 'pipe', timeout: 15_000 });
    expect(await prisma.userEntitlement.findUniqueOrThrow({ where: { userId: t.user.id } })).toEqual(before);
    expect(await prisma.usageBucket.findUniqueOrThrow({ where: { id: bucket.id } })).toEqual(bucket);
    const products = await prisma.subscriptionProduct.findMany({ where: { storeProductId: { startsWith: 'proestimate.pro.' } } });
    expect(products).toHaveLength(2);
    expect(products.every((product) => product.hasIntroOffer && product.introOfferDisplayText === '3-day free trial')).toBe(true);
    const plan = await prisma.plan.findUniqueOrThrow({ where: { id: t.plan.id } });
    expect(plan.featuresJson).toEqual({ LIMITS: { AI_GENERATION: { monthly: 20 } } });
    await expect(gateAIAction({ userId: t.user.id, companyId: t.company.id, metric: 'AI_GENERATION' })).resolves.toBeDefined();
  });
});
