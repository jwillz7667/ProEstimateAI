import { randomUUID } from 'node:crypto';
import { beforeEach, describe, expect, it } from 'vitest';
import { EstimateStatus, InvoiceStatus, ProposalStatus } from '@prisma/client';
import { prisma } from '../../src/config/database';
import { getAttention } from '../../src/modules/dashboard/dashboard-attention.service';
import { getSummary } from '../../src/modules/dashboard/dashboard.service';

const now = new Date('2026-11-03T16:00:00Z');
const daysAgo = (days: number) => new Date(now.getTime() - days * 86_400_000);

async function fixture() {
  const company = await prisma.company.create({ data: { name: `Attention ${randomUUID()}` } });
  const client = await prisma.client.create({ data: { companyId: company.id, name: 'Example client' } });
  const project = await prisma.project.create({ data: { companyId: company.id, clientId: client.id, title: 'Kitchen', projectType: 'KITCHEN' } });
  const user = await prisma.user.create({ data: { companyId: company.id, email: `${randomUUID()}@example.test`, fullName: 'Owner' } });
  return { company, client, project, user };
}
type Fixture = Awaited<ReturnType<typeof fixture>>;

async function estimate(t: Fixture, status: EstimateStatus = 'DRAFT', amount = '10.01', age = 1) {
  return prisma.estimate.create({ data: {
    companyId: t.company.id, projectId: t.project.id,
    estimateNumber: `EST-${randomUUID()}`, status, totalAmount: amount, updatedAt: daysAgo(age),
  } });
}

async function invoice(t: Fixture, args: { status?: InvoiceStatus; dueDate?: Date | null; amountDue?: string; currency?: string; estimateId?: string } = {}) {
  return prisma.invoice.create({ data: {
    companyId: t.company.id, clientId: t.client.id, projectId: t.project.id,
    invoiceNumber: `INV-${randomUUID()}`, status: args.status ?? 'SENT',
    totalAmount: '100', amountDue: args.amountDue ?? '100',
    dueDate: args.dueDate === undefined ? daysAgo(2) : args.dueDate,
    currencyCode: args.currency ?? 'USD', estimateId: args.estimateId,
  } });
}

async function proposal(t: Fixture, args: { status?: ProposalStatus; age?: number; expiresAt?: Date; respondedAt?: Date } = {}) {
  const e = await estimate(t, 'SENT');
  return prisma.proposal.create({ data: {
    companyId: t.company.id, projectId: t.project.id, estimateId: e.id,
    proposalNumber: `PROP-${randomUUID()}`, status: args.status ?? 'VIEWED',
    sentAt: daysAgo(args.age ?? 4), expiresAt: args.expiresAt, respondedAt: args.respondedAt,
  } });
}

describe('Home next actions', () => {
  beforeEach(async () => {
    await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE');
  });

  it('returns genuine empty work without inventing actions', async () => {
    const t = await fixture();
    const result = await getAttention(t.company.id, now);
    expect(result.groups).toEqual([]);
    expect(result.follow_up_after_days).toBe(3);
    expect(result.generated_at).toBe(now.toISOString());
  });

  it('counts all workspace drafts beyond the recent page, excludes archived and foreign work, and picks the oldest', async () => {
    const t = await fixture();
    const oldest = await estimate(t, 'DRAFT', '10.01', 40);
    for (let i = 0; i < 29; i++) await estimate(t, 'DRAFT', '10.01', 1);
    const other = await fixture();
    await estimate(other, 'DRAFT', '99999.99', 100);
    const archived = await fixture();
    await prisma.project.update({ where: { id: archived.project.id }, data: { companyId: t.company.id, status: 'ARCHIVED' } });
    await prisma.estimate.create({ data: { companyId: t.company.id, projectId: archived.project.id, estimateNumber: 'ARCHIVED', totalAmount: 9999 } });
    const result = await getAttention(t.company.id, now);
    expect(result.groups).toHaveLength(1);
    expect(result.groups[0]).toMatchObject({ kind: 'draft_estimate', count: 30, amounts: [{ currency_code: 'USD', amount: '300.30' }] });
    expect(result.groups[0].target.document_id).toBe(oldest.id);
    expect(result.groups[0].target.client_name).toBe('Example client');
  });

  it('orders urgent categories before drafts and only follows up unanswered proposals after three days', async () => {
    const t = await fixture();
    await estimate(t);
    await estimate(t, 'APPROVED', '800.50');
    await invoice(t);
    const oldest = await proposal(t, { age: 8 });
    await proposal(t, { status: 'SENT', age: 3 });
    await proposal(t, { age: 2 });
    await proposal(t, { age: 6, expiresAt: daysAgo(1) });
    await proposal(t, { age: 9, respondedAt: daysAgo(1) });
    await proposal(t, { age: 10, status: 'DECLINED' });
    const result = await getAttention(t.company.id, now);
    expect(result.groups.map(g => g.kind)).toEqual(['overdue_invoice', 'approved_estimate', 'unanswered_proposal', 'draft_estimate']);
    expect(result.groups[2].count).toBe(2);
    expect(result.groups[2].target.document_id).toBe(oldest.id);
    expect(result.groups[2].amounts).toEqual([{ currency_code: 'USD', amount: '20.02' }]);
  });

  it('does not present invoiced approved work as ready for another invoice, while voided invoices permit rebilling', async () => {
    const t = await fixture();
    const ready = await estimate(t, 'APPROVED', '50.01');
    const voided = await estimate(t, 'APPROVED', '20.02');
    const billed = await estimate(t, 'APPROVED', '1000');
    await invoice(t, { estimateId: voided.id, status: 'VOID' });
    await invoice(t, { estimateId: billed.id, status: 'DRAFT' });
    const group = (await getAttention(t.company.id, now)).groups.find(g => g.kind === 'approved_estimate')!;
    expect(group.count).toBe(2);
    expect(group.amounts).toEqual([{ currency_code: 'USD', amount: '70.03' }]);
    expect([ready.id, voided.id]).toContain(group.target.document_id);
  });

  it('derives overdue from actual due date and positive unpaid balance, preserving currency-separated amounts', async () => {
    const t = await fixture();
    const oldest = await invoice(t, { dueDate: daysAgo(12), amountDue: '10.01' });
    await invoice(t, { status: 'PARTIALLY_PAID', amountDue: '20.02' });
    await invoice(t, { status: 'VIEWED', amountDue: '30.03', currency: 'CAD' });
    await invoice(t, { dueDate: new Date(now.getTime() + 86_400_000), status: 'OVERDUE' });
    await invoice(t, { dueDate: null });
    await invoice(t, { amountDue: '0' });
    for (const status of ['DRAFT', 'PAID', 'VOID'] as const) await invoice(t, { status });
    const other = await fixture();
    await invoice(other, { amountDue: '99999.99' });
    const group = (await getAttention(t.company.id, now)).groups[0];
    expect(group.kind).toBe('overdue_invoice');
    expect(group.count).toBe(3);
    expect(group.amounts).toEqual([{ currency_code: 'CAD', amount: '30.03' }, { currency_code: 'USD', amount: '30.03' }]);
    expect(group.target.document_id).toBe(oldest.id);
  });

  it('does not call a sent draft estimate unfinished and drops follow-ups after its estimate is approved', async () => {
    const t = await fixture();
    const e = await estimate(t);
    await prisma.proposal.create({ data: { companyId: t.company.id, projectId: t.project.id, estimateId: e.id, status: 'SENT', sentAt: daysAgo(4) } });
    expect((await getAttention(t.company.id, now)).groups.map(g => g.kind)).toEqual(['unanswered_proposal']);
    await prisma.estimate.update({ where: { id: e.id }, data: { status: 'APPROVED' } });
    expect((await getAttention(t.company.id, now)).groups.map(g => g.kind)).toEqual(['approved_estimate']);
  });

  it('keeps overdue balances actionable after a project is archived', async () => {
    const t = await fixture();
    await invoice(t, { amountDue: '25.50' });
    await estimate(t);
    await proposal(t);
    await prisma.project.update({ where: { id: t.project.id }, data: { status: 'ARCHIVED' } });
    const result = await getAttention(t.company.id, now);
    expect(result.groups.map(g => g.kind)).toEqual(['overdue_invoice']);
    expect(result.groups[0].amounts).toEqual([{ currency_code: 'USD', amount: '25.50' }]);
  });

  it('uses exact UTC date boundaries independently of the database session time zone', async () => {
    const t = await fixture();
    const overdue = await invoice(t, { dueDate: new Date(now.getTime() - 1) });
    await invoice(t, { dueDate: now });
    await invoice(t, { dueDate: new Date(now.getTime() + 1) });
    const atBoundary = await proposal(t, { age: 3 });
    const tooRecent = await proposal(t, { age: 3 });
    await prisma.proposal.update({ where: { id: tooRecent.id }, data: { sentAt: new Date(daysAgo(3).getTime() + 1) } });
    await proposal(t, { age: 5, expiresAt: now });
    const result = await getAttention(t.company.id, now);
    expect(result.groups[0]).toMatchObject({ kind: 'overdue_invoice', count: 1, target: { document_id: overdue.id } });
    expect(result.groups[1]).toMatchObject({ kind: 'unanswered_proposal', count: 1, target: { document_id: atBoundary.id } });
  });

  it('reports settled invoice face values separately by currency instead of labelling them cash collected', async () => {
    const t = await fixture();
    for (const [currency, amount] of [['USD', '10.01'], ['USD', '20.02'], ['CAD', '30.03']]) {
      const i = await invoice(t, { status: 'PAID', amountDue: '0', currency });
      await prisma.invoice.update({ where: { id: i.id }, data: { totalAmount: amount, paidAt: new Date() } });
    }
    const unpaid = await invoice(t, { status: 'PARTIALLY_PAID', amountDue: '1' });
    await prisma.invoice.update({ where: { id: unpaid.id }, data: { paidAt: new Date() } });
    const summary = await getSummary(t.company.id, t.user.id);
    expect(summary.settled_invoice_amounts).toEqual([{ currency_code: 'CAD', amount: '30.03' }, { currency_code: 'USD', amount: '30.03' }]);
  });
});
