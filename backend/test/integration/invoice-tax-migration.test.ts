import { readFileSync } from 'node:fs';
import { beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../../src/config/database';

// Exercise the committed migration's real backfill SQL, without repeating the
// additive ALTER that setup.ts already applied to the disposable database.
const backfillStatements = readFileSync('prisma/migrations/20261013000000_snapshot_invoice_line_tax/migration.sql', 'utf8')
  .split(';').slice(1).map((statement) => statement.trim()).filter(Boolean);

beforeEach(async () => {
  await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE');
});

async function historicalInvoice(options: {
  materialsTax?: number; laborTax?: number; editedAfterInvoice?: boolean; ambiguous?: boolean;
} = {}) {
  const company = await prisma.company.create({ data: { name: 'Historical Invoice Co' } });
  const client = await prisma.client.create({ data: { companyId: company.id, name: 'Client' } });
  const project = await prisma.project.create({ data: { companyId: company.id, clientId: client.id, title: 'Job', projectType: 'CUSTOM' } });
  const estimate = await prisma.estimate.create({ data: {
    companyId: company.id, projectId: project.id, estimateNumber: 'EST-HISTORICAL',
    subtotalMaterials: 800, subtotalLabor: 200, taxAmount: 80, totalAmount: 1080,
    createdAt: new Date('2026-01-01T00:00:00Z'), updatedAt: new Date(options.editedAfterInvoice ? '2026-03-01T00:00:00Z' : '2026-01-01T00:00:00Z'),
  } });
  const sourceLines = [
    { name: 'Materials', quantity: 1, unit: 'lot', unitCost: 800, lineTotal: 800, sortOrder: 0, taxRate: options.materialsTax ?? 0.1 },
    { name: 'Labor', quantity: 1, unit: 'lot', unitCost: 200, lineTotal: 200, sortOrder: 1, taxRate: options.laborTax ?? 0 },
  ];
  await prisma.estimateLineItem.createMany({ data: [...sourceLines, ...(options.ambiguous ? [sourceLines[0]] : [])].map((line) => ({ ...line, estimateId: estimate.id })) });
  const invoice = await prisma.invoice.create({ data: {
    companyId: company.id, projectId: project.id, clientId: client.id, estimateId: estimate.id, invoiceNumber: 'INV-HISTORICAL',
    subtotal: 1000, taxAmount: 80, totalAmount: 1080, amountDue: 1080, createdAt: new Date('2026-02-01T00:00:00Z'),
  } });
  await prisma.invoiceLineItem.createMany({ data: sourceLines.map(({ taxRate: _historicalUnknownRate, ...line }) => ({ ...line, invoiceId: invoice.id })) });
  for (const statement of backfillStatements) await prisma.$executeRawUnsafe(statement);
  const lines = await prisma.invoiceLineItem.findMany({ where: { invoiceId: invoice.id }, orderBy: { sortOrder: 'asc' } });
  const preserved = await prisma.invoice.findUniqueOrThrow({ where: { id: invoice.id } });
  expect(Number(preserved.taxAmount)).toBe(80);
  expect(Number(preserved.totalAmount)).toBe(1080);
  expect(Number(preserved.amountDue)).toBe(1080);
  return lines.map((line) => Number(line.taxRate));
}

describe('historical invoice tax migration', () => {
  it('recovers exact rates for an unchanged, unambiguous source distribution reproducing the bill', async () => {
    expect(await historicalInvoice()).toEqual([0.1, 0]);
  });
  it('retains blended rates when source tax no longer reproduces the recorded invoice tax', async () => {
    expect(await historicalInvoice({ materialsTax: 0.2 })).toEqual([0.08, 0.08]);
  });
  it('retains blended rates for a later source edit even if its aggregate tax is unchanged', async () => {
    expect(await historicalInvoice({ materialsTax: 0.05, laborTax: 0.2, editedAfterInvoice: true })).toEqual([0.08, 0.08]);
  });
  it('retains blended rates if a source line match is ambiguous', async () => {
    expect(await historicalInvoice({ ambiguous: true })).toEqual([0.08, 0.08]);
  });
});
