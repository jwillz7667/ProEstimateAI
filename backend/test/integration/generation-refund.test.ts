import { randomUUID } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { prisma } from '../../src/config/database';
import { env } from '../../src/config/env';
import { bootstrapCatalog } from '../../src/lib/catalog-bootstrap';
import { gateAIAction } from '../../src/modules/commerce/entitlement-gate';
import { failGenerationAndRefund, linkGenerationReservation } from '../../src/lib/generation-usage';
import { markStuckGenerationsFailed, markImagelessCompletedGenerationsFailed } from '../../src/lib/generation-cleanup';
import { resetCommerceTables } from './helpers';

const mocks = vi.hoisted(() => ({ provider: vi.fn(), push: vi.fn(), materials: vi.fn() }));
vi.mock('../../src/lib/image-gen', async (original) => ({ ...await original<object>(), generatePreviewImage: mocks.provider }));
vi.mock('../../src/lib/apns', () => ({ sendGenerationReady: mocks.push }));
vi.mock('../../src/lib/material-gen', () => ({ generateMaterialSuggestions: mocks.materials, generateLaborEstimates: mocks.materials }));
import { create } from '../../src/modules/generations/generations.service';

const old = new Date(Date.now() - 2 * 60 * 60 * 1000);
const image = { base64Data: 'cHJldmlldyBieXRlcw==', mimeType: 'image/png', durationMs: 50 };
beforeEach(async () => {
  await resetCommerceTables();
  await bootstrapCatalog(prisma);
  vi.clearAllMocks();
  mocks.provider.mockResolvedValue(null);
  mocks.push.mockResolvedValue(undefined);
  mocks.materials.mockResolvedValue([]);
  env.FAL_KEY = 'integration-provider-mock';
  env.GOOGLE_AI_API_KEY = undefined;
  env.PIAPI_API_KEY = undefined;
});
afterEach(() => vi.restoreAllMocks());

async function account(paid = false) {
  const company = await prisma.company.create({ data: { name: 'Generation refunds' } });
  const user = await prisma.user.create({ data: { companyId: company.id, email: `${randomUUID()}@example.test`, fullName: 'Refund tester' } });
  const plan = await prisma.plan.findUniqueOrThrow({ where: { code: paid ? 'PRO_MONTHLY' : 'FREE_STARTER' } });
  await prisma.userEntitlement.create({ data: { userId: user.id, companyId: company.id, planId: plan.id,
    status: paid ? 'PRO_ACTIVE' : 'FREE', renewalDate: paid ? new Date(Date.now() + 86_400_000) : null } });
  const bucket = await prisma.usageBucket.create({ data: { userId: user.id, companyId: company.id,
    metricCode: 'AI_GENERATION', includedQuantity: 5, source: 'STARTER_CREDITS' } });
  const project = await prisma.project.create({ data: { companyId: company.id, title: 'Refund project', projectType: 'KITCHEN' } });
  return { company, user, project, bucket, plan };
}

async function status(id: string, expected: string) {
  await vi.waitFor(async () => {
    expect((await prisma.aIGeneration.findUniqueOrThrow({ where: { id } })).status).toBe(expected);
  }, { timeout: 5000 });
}

async function linkedEvent(id: string) {
  return prisma.usageEvent.findFirstOrThrow({ where: { metadata: { path: ['generation_reservation', 'generation_id'], equals: id } } });
}

describe('durable asynchronous generation refunds', () => {
  it('reserves through a single-connection pool when admin lookup is configured', async () => {
    const t = await account();
    const databaseUrl = new URL(process.env.TEST_DATABASE_URL!);
    databaseUrl.searchParams.set('connection_limit', '1');
    const childEnvironment: NodeJS.ProcessEnv = { ...process.env,
      DATABASE_URL: databaseUrl.toString(), ADMIN_EMAILS: 'unrelated-admin@example.test' };
    for (const name of ['FAL_KEY', 'GOOGLE_AI_API_KEY', 'PIAPI_API_KEY', 'DEEPSEEK_API_KEY']) delete childEnvironment[name];
    execFileSync('node', ['-e', `
      const { prisma } = require('./dist/config/database');
      const { create } = require('./dist/modules/generations/generations.service');
      create(${JSON.stringify(t.project.id)}, ${JSON.stringify(t.company.id)}, ${JSON.stringify(t.user.id)},
        { prompt: 'single connection', generate_preview: true })
        .then(async (generation) => {
          for (let attempt = 0; attempt < 100; attempt++) {
            const job = await prisma.aIGeneration.findUniqueOrThrow({ where: { id: generation.id } });
            if (job.status === 'FAILED') { await prisma.$disconnect(); return; }
            await new Promise((resolve) => setTimeout(resolve, 20));
          }
          throw new Error('Generation did not finish');
        })
        .catch(async (error) => { console.error(error.message); await prisma.$disconnect(); process.exitCode = 1; });
    `], {
      env: childEnvironment,
      stdio: 'pipe', timeout: 15_000,
    });
    expect(await prisma.aIGeneration.count()).toBe(1);
  });
  it.each(['provider returned no image', 'missing reference', 'safety rejection', 'processing exception', 'provider not configured'])(
    'returns the exact starter credit when %s terminates the job', async (failure) => {
      const t = await account();
      if (failure === 'processing exception' || failure === 'safety rejection') mocks.provider.mockRejectedValue(new Error(failure));
      if (failure === 'provider not configured') env.FAL_KEY = undefined;
      const generation = await create(t.project.id, t.company.id, t.user.id, { prompt: 'Update this kitchen', generate_preview: true });
      await status(generation.id, 'FAILED');
      const event = await linkedEvent(generation.id);
      expect(event.quantity).toBe(0);
      expect(event.metadata).toMatchObject({ source: 'STARTER_CREDITS', bucket_id: t.bucket.id,
        generation_reservation: { event_id: event.id, generation_id: generation.id, user_id: t.user.id },
        generation_refund: { reason: expect.any(String) } });
      expect((await prisma.usageBucket.findUniqueOrThrow({ where: { id: t.bucket.id } })).consumedQuantity).toBe(0);
      if (failure === 'missing reference') expect(mocks.provider.mock.calls[0][2]).toBeUndefined();
      await Promise.all(Array.from({ length: 5 }, () => failGenerationAndRefund(generation.id, 'duplicate retry')));
      expect((await prisma.usageBucket.findUniqueOrThrow({ where: { id: t.bucket.id } })).consumedQuantity).toBe(0);
      expect((await linkedEvent(generation.id)).metadata).toEqual(event.metadata);
    },
  );

  it('returns paid rolling capacity while preserving the linked event audit metadata', async () => {
    const t = await account(true);
    await prisma.plan.update({ where: { id: t.plan.id }, data: { featuresJson: { LIMITS: { AI_GENERATION: { monthly: 1 } } } } });
    const generation = await create(t.project.id, t.company.id, t.user.id, { prompt: 'Update kitchen' });
    await status(generation.id, 'FAILED');
    expect((await linkedEvent(generation.id)).quantity).toBe(0);
    await prisma.usageEvent.update({ where: { id: (await linkedEvent(generation.id)).id },
      data: { createdAt: new Date(Date.now() - 10 * 86_400_000) } });
    await expect(gateAIAction({ userId: t.user.id, companyId: t.company.id, metric: 'AI_GENERATION' })).resolves.toBeDefined();
    const charged = await prisma.usageEvent.findFirstOrThrow({ where: { userId: t.user.id, quantity: 1 } });
    try {
      await gateAIAction({ userId: t.user.id, companyId: t.company.id, metric: 'AI_GENERATION' });
      throw new Error('Expected the monthly quota to block');
    } catch (error) {
      expect(error).toMatchObject({ paywall: { reset_at: new Date(charged.createdAt.getTime() + 30 * 86_400_000).toISOString() } });
    }
  });

  it('keeps reservation, generation, linkage, and activity atomic if the creation transaction fails', async () => {
    const t = await account();
    // Fail an actual PostgreSQL statement after the generation/link inserts.
    const fault = `generation_fault_${randomUUID().replaceAll('-', '')}`;
    await prisma.$executeRawUnsafe(`CREATE FUNCTION "${fault}"() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'injected activity write failure'; END $$`);
    await prisma.$executeRawUnsafe(`CREATE TRIGGER "${fault}" BEFORE INSERT ON "ActivityLogEntry" FOR EACH ROW EXECUTE FUNCTION "${fault}"()`);
    try {
      await expect(create(t.project.id, t.company.id, t.user.id, { prompt: 'Update kitchen' })).rejects.toThrow('injected activity write failure');
    } finally {
      await prisma.$executeRawUnsafe(`DROP TRIGGER "${fault}" ON "ActivityLogEntry"`);
      await prisma.$executeRawUnsafe(`DROP FUNCTION "${fault}"()`);
    }
    expect(await prisma.aIGeneration.count()).toBe(0);
    expect(await prisma.usageEvent.count()).toBe(0);
    expect((await prisma.usageBucket.findUniqueOrThrow({ where: { id: t.bucket.id } })).consumedQuantity).toBe(0);
    expect(mocks.provider).not.toHaveBeenCalled();
  });

  it('refunds an orphan once after restart and rejects late provider success after the reaper wins', async () => {
    const t = await account();
    let finish!: (result: typeof image) => void;
    mocks.provider.mockReturnValue(new Promise<typeof image>((resolve) => { finish = resolve; }));
    const generation = await create(t.project.id, t.company.id, t.user.id, { prompt: 'Update kitchen' });
    await vi.waitFor(() => expect(mocks.provider).toHaveBeenCalledOnce());
    await prisma.aIGeneration.update({ where: { id: generation.id }, data: { createdAt: old } });
    const event = await linkedEvent(generation.id);
    await prisma.usageEvent.update({ where: { id: event.id }, data: { metadata: { ...(event.metadata as object), audit_note: 'must survive' } } });
    const reaps = await Promise.all([markStuckGenerationsFailed(), markStuckGenerationsFailed()]);
    expect(reaps.reduce((sum, count) => sum + count, 0)).toBe(1);
    const writes = vi.spyOn(prisma.aIGeneration, 'updateMany');
    finish(image);
    await vi.waitFor(() => expect(writes).toHaveBeenCalledWith(expect.objectContaining({ data: expect.objectContaining({ status: 'COMPLETED' }) })));
    await Promise.all(writes.mock.results.filter((result) => result.type === 'return').map((result) => result.value));
    const failed = await prisma.aIGeneration.findUniqueOrThrow({ where: { id: generation.id } });
    expect(failed.status).toBe('FAILED');
    expect(failed.imageData).toBeNull();
    expect(mocks.push).not.toHaveBeenCalled();
    expect(mocks.materials).not.toHaveBeenCalled();
    expect((await linkedEvent(generation.id)).metadata).toMatchObject({ audit_note: 'must survive' });
    expect((await prisma.usageBucket.findUniqueOrThrow({ where: { id: t.bucket.id } })).consumedQuantity).toBe(0);
  });

  it('keeps completed image and text-only jobs charged and excludes explicit text-only output from imageless reaping', async () => {
    const t = await account();
    mocks.provider.mockResolvedValue(image);
    const rendered = await create(t.project.id, t.company.id, t.user.id, { prompt: 'Update kitchen' });
    await status(rendered.id, 'COMPLETED');
    await expect(failGenerationAndRefund(rendered.id, 'late error')).resolves.toBe(false);
    const text = await create(t.project.id, t.company.id, t.user.id, { prompt: 'Estimate kitchen', generate_preview: false });
    await status(text.id, 'COMPLETED');
    await prisma.aIGeneration.updateMany({ data: { createdAt: old } });
    // Intent must remain correct even when the mutable project setting changes.
    await prisma.project.update({ where: { id: t.project.id }, data: { aiPreviewEnabled: true } });
    expect(await markImagelessCompletedGenerationsFailed(undefined, true)).toBe(0);
    expect(await markImagelessCompletedGenerationsFailed()).toBe(0);
    expect((await linkedEvent(rendered.id)).quantity).toBe(1);
    expect((await linkedEvent(text.id)).quantity).toBe(1);
    expect((await prisma.usageBucket.findUniqueOrThrow({ where: { id: t.bucket.id } })).consumedQuantity).toBe(2);
  });

  it('rolls failure and refund back together, then lets the reaper retry from persisted linkage', async () => {
    const t = await account();
    const generation = await prisma.$transaction(async (transaction) => {
      const reservation = await gateAIAction({ userId: t.user.id, companyId: t.company.id, metric: 'AI_GENERATION' }, transaction);
      const job = await transaction.aIGeneration.create({ data: { projectId: t.project.id, prompt: 'orphan', createdAt: old } });
      await linkGenerationReservation(transaction, reservation, job.id, t.project.id, t.company.id, true);
      return job;
    });
    // The refund's final bucket statement fails its invariant, after status and
    // event writes have run. Their rollback must be real, not a mocked return.
    await prisma.usageBucket.update({ where: { id: t.bucket.id }, data: { consumedQuantity: 0 } });
    await expect(failGenerationAndRefund(generation.id, 'provider failed')).rejects.toThrow('could not be refunded');
    expect((await prisma.aIGeneration.findUniqueOrThrow({ where: { id: generation.id } })).status).toBe('QUEUED');
    expect((await linkedEvent(generation.id)).quantity).toBe(1);
    await prisma.usageBucket.update({ where: { id: t.bucket.id }, data: { consumedQuantity: 1 } });
    expect(await markStuckGenerationsFailed()).toBe(1);
    expect((await linkedEvent(generation.id)).quantity).toBe(0);
    expect((await prisma.usageBucket.findUniqueOrThrow({ where: { id: t.bucket.id } })).consumedQuantity).toBe(0);
  });

  it('never guesses a refund for legacy unlinked usage rows', async () => {
    const t = await account();
    const reservation = await gateAIAction({ userId: t.user.id, companyId: t.company.id, metric: 'AI_GENERATION' });
    const generation = await prisma.aIGeneration.create({ data: { projectId: t.project.id, prompt: 'legacy', createdAt: old } });
    expect(await markStuckGenerationsFailed()).toBe(1);
    expect((await prisma.usageEvent.findUniqueOrThrow({ where: { id: reservation!.eventId } })).quantity).toBe(1);
    expect((await prisma.usageBucket.findUniqueOrThrow({ where: { id: t.bucket.id } })).consumedQuantity).toBe(1);
    expect((await prisma.aIGeneration.findUniqueOrThrow({ where: { id: generation.id } })).status).toBe('FAILED');
  });
});
