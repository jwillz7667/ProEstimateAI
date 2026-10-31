import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import type { Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../../src/app';
import { prisma } from '../../src/config/database';
import { bootstrapCatalog } from '../../src/lib/catalog-bootstrap';
import { signAccessToken } from '../../src/lib/jwt';
import { resetCommerceTables } from './helpers';

let server: Server;
let origin: string;
beforeAll(async () => {
  server = createApp().listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Expected loopback TCP listener');
  origin = `http://127.0.0.1:${address.port}`;
});
afterAll(async () => {
  if (server) await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
});
beforeEach(async () => {
  await resetCommerceTables();
  await bootstrapCatalog(prisma);
});

async function account(paid: boolean) {
  const company = await prisma.company.create({ data: { name: 'Feature access' } });
  const user = await prisma.user.create({ data: {
    companyId: company.id, fullName: 'Feature access', email: `${randomUUID()}@example.test`,
  } });
  const plan = await prisma.plan.findUniqueOrThrow({ where: { code: paid ? 'PRO_MONTHLY' : 'FREE_STARTER' } });
  await prisma.userEntitlement.create({ data: {
    userId: user.id, companyId: company.id, planId: plan.id,
    status: paid ? 'PRO_ACTIVE' : 'FREE', renewalDate: paid ? new Date(Date.now() + 86_400_000) : null,
  } });
  const token = signAccessToken({ userId: user.id, companyId: company.id });
  const request = (path: string, method: string, body?: object) => fetch(`${origin}/v1${path}`, {
    method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  return { company, user, request };
}

describe('server policy matches existing iOS feature gates', () => {
  it('allows ordinary company edits and unchanged colors for Free but blocks new custom branding', async () => {
    const { company, request } = await account(false);
    expect((await request('/companies/me', 'PATCH', { name: 'Updated name', primary_color: company.primaryColor })).status).toBe(200);
    expect((await request('/companies/me', 'PATCH', { name: 'Must not be written', primary_color: '#123456' })).status).toBe(402);
    expect((await request('/companies/me/logo', 'POST', { image_data: 'aGVsbG8=', mime_type: 'image/png' })).status).toBe(402);
    expect((await prisma.company.findUniqueOrThrow({ where: { id: company.id } })).name).toBe('Updated name');
    expect((await request('/companies/me/logo', 'DELETE')).status).toBe(200);
  });

  it('requires an active entitlement for new approval tokens and sending', async () => {
    const free = await account(false);
    expect((await free.request('/proposals', 'POST', { estimate_id: 'unused' })).status).toBe(402);
    expect(await prisma.proposal.count()).toBe(0);
    const paid = await account(true);
    const project = await prisma.project.create({ data: { companyId: paid.company.id, title: 'Proposal audit' } });
    const estimate = await prisma.estimate.create({ data: { companyId: paid.company.id, projectId: project.id, estimateNumber: 'EST-1' } });
    expect((await paid.request('/proposals', 'POST', { estimate_id: estimate.id })).status).toBe(201);
    const proposal = await prisma.proposal.findFirstOrThrow({ where: { companyId: paid.company.id } });
    expect(proposal.shareToken).toBeTruthy();
    await prisma.userEntitlement.update({ where: { userId: paid.user.id }, data: { renewalDate: new Date(Date.now() - 1000) } });
    expect((await paid.request(`/proposals/${proposal.id}/send`, 'POST', {})).status).toBe(402);
    expect((await prisma.proposal.findUniqueOrThrow({ where: { id: proposal.id } })).status).toBe('DRAFT');
  });

  it('blocks Free map access before a billable provider call and allows paid local polygon measurement', async () => {
    const free = await account(false);
    expect((await free.request('/maps/geocode', 'POST', { address: '123 Main Street' })).status).toBe(402);
    expect((await free.request('/maps/roof-scouting', 'POST', { latitude: 44, longitude: -93 })).status).toBe(402);
    const polygon = [{ latitude: 44, longitude: -93 }, { latitude: 44.001, longitude: -93 }, { latitude: 44, longitude: -93.001 }];
    const paid = await account(true);
    expect((await paid.request('/maps/lawn-area', 'POST', { polygon })).status).toBe(200);
  });
});
