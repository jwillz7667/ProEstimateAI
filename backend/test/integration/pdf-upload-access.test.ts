import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import type { Server } from 'node:http';
import PDFDocument from 'pdfkit';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../../src/app';
import { prisma } from '../../src/config/database';
import { bootstrapCatalog } from '../../src/lib/catalog-bootstrap';
import { signAccessToken } from '../../src/lib/jwt';
import { gateAIAction } from '../../src/modules/commerce/entitlement-gate';
import { resetCommerceTables } from './helpers';

let server: Server;
let origin: string;
let pdf: Buffer;
beforeAll(async () => {
  pdf = await new Promise<Buffer>((resolve, reject) => {
    const chunks: Buffer[] = [];
    const document = new PDFDocument({ size: 'LETTER' });
    document.on('data', (chunk: Buffer) => chunks.push(chunk));
    document.on('end', () => resolve(Buffer.concat(chunks)));
    document.on('error', reject);
    document.text('Owned saved estimate test');
    document.end();
  });
  server = createApp().listen(0, '127.0.0.1');
  await once(server, 'listening');
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Expected local listener');
  origin = `http://127.0.0.1:${address.port}`;
});
afterAll(async () => {
  if (server) await new Promise<void>((resolve, reject) => server.close((error) => error ? reject(error) : resolve()));
});
beforeEach(async () => {
  await resetCommerceTables();
  await bootstrapCatalog(prisma);
});
async function account(status: 'FREE' | 'PRO_ACTIVE' | 'EXPIRED') {
  const company = await prisma.company.create({ data: { name: 'PDF access audit' } });
  const user = await prisma.user.create({ data: { companyId: company.id, email: `${randomUUID()}@example.test`, fullName: 'PDF access' } });
  const plan = await prisma.plan.findUniqueOrThrow({ where: { code: status === 'FREE' ? 'FREE_STARTER' : 'PRO_MONTHLY' } });
  await prisma.userEntitlement.create({ data: { userId: user.id, companyId: company.id, planId: plan.id, status, endsAt: new Date(Date.now() + (status === 'EXPIRED' ? -1 : 86_400_000)) } });
  const project = await prisma.project.create({ data: { companyId: company.id, title: 'Owned PDF project' } });
  const estimate = await prisma.estimate.create({ data: { companyId: company.id, projectId: project.id, estimateNumber: 'EST-PDF' } });
  const token = signAccessToken({ userId: user.id, companyId: company.id });
  const request = (path: string, method = 'GET', body?: object) => fetch(`${origin}/v1${path}`, { method,
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined });
  const upload = (estimateId = estimate.id) => request(`/estimates/${estimateId}/exports`, 'POST', { file_name: 'estimate.pdf', content_type: 'application/pdf', pdf_data: pdf.toString('base64') });
  return { company, user, project, estimate, request, upload };
}

describe('new PDF persistence requires paid access; historical work remains readable', () => {
  it.each(['FREE', 'EXPIRED'] as const)('blocks a new PDF upload for %s without creating data or quota', async (state) => {
    const t = await account(state);
    const response = await t.upload();
    expect(response.status).toBe(402);
    expect(await response.json()).toMatchObject({ error: { code: 'PAYWALL_REQUIRED' } });
    expect(await prisma.estimateExport.count()).toBe(0);
    expect(await prisma.usageEvent.count()).toBe(0);
  });

  it('permits Pro upload without double-charging the existing iOS pre-approval', async () => {
    const t = await account('PRO_ACTIVE');
    // Mirrors iOS: reserve after local rendering, then upload the same file.
    await gateAIAction({ userId: t.user.id, companyId: t.company.id, metric: 'QUOTE_EXPORT' });
    const response = await t.upload();
    expect(response.status).toBe(201);
    expect(await prisma.estimateExport.count()).toBe(1);
    expect(await prisma.usageEvent.count({ where: { metricCode: 'QUOTE_EXPORT' } })).toBe(1);
    const record = await prisma.estimateExport.findFirstOrThrow();
    expect(Buffer.from(record.pdfData, 'base64')).toEqual(pdf);
  });

  it.each(['FREE', 'EXPIRED'] as const)('keeps owned project, estimate, saved PDF metadata and exact binary readable for %s', async (state) => {
    const t = await account('PRO_ACTIVE');
    const upload = await t.upload();
    expect(upload.status).toBe(201);
    const { data: saved } = await upload.json() as { data: { id: string } };
    await prisma.userEntitlement.update({ where: { userId: t.user.id }, data: { status: state, endsAt: new Date(Date.now() - 1) } });
    for (const path of [`/projects/${t.project.id}`, `/estimates/${t.estimate.id}`, `/estimates/${t.estimate.id}/exports`, `/estimate-exports/${saved.id}`]) {
      expect((await t.request(path)).status).toBe(200);
    }
    const download = await t.request(`/estimate-exports/${saved.id}/file`);
    expect(download.status).toBe(200);
    expect(Buffer.from(await download.arrayBuffer())).toEqual(pdf);
    expect(await prisma.usageEvent.count()).toBe(0);
    expect((await t.upload()).status).toBe(402);
  });

  it('checks ownership before paid access and does not disclose another company estimate', async () => {
    const owner = await account('PRO_ACTIVE');
    const other = await account('FREE');
    expect((await other.upload(owner.estimate.id)).status).toBe(404);
    expect(await prisma.estimateExport.count()).toBe(0);
  });
});
