import { Prisma } from '@prisma/client';
import { ConflictError, NotFoundError } from '../../lib/errors';
import { lockCompanyPaymentAccess } from '../invoice-checkout/payment-erasure-lock';

/** Immutable parent links let every amendment and payment share one mutex.
 * Always take company gate -> contract -> ALL invoices -> credit notes.
 */
export async function estimateFamily(
  tx: Prisma.TransactionClient,
  estimateId: string,
  companyId: string,
) {
  const rows = await tx.$queryRaw<
    Array<{ id: string; revisesEstimateId: string | null }>
  >`
    WITH RECURSIVE ancestors AS (
      SELECT id, "revisesEstimateId", ARRAY[id] AS path FROM "Estimate" WHERE id=${estimateId} AND "companyId"=${companyId}
      UNION ALL SELECT e.id,e."revisesEstimateId",a.path||e.id FROM "Estimate" e JOIN ancestors a ON e.id=a."revisesEstimateId"
      WHERE e."companyId"=${companyId} AND NOT e.id=ANY(a.path) AND cardinality(a.path)<1000
    ) SELECT id,"revisesEstimateId" FROM ancestors`;
  if (!rows.length) throw new NotFoundError('Estimate', estimateId);
  const root = rows.find((row) => !row.revisesEstimateId);
  if (!root)
    throw new ConflictError('The contract revision history needs review.');
  const family = await tx.$queryRaw<Array<{ id: string }>>`
    WITH RECURSIVE family AS (
      SELECT id, ARRAY[id] AS path FROM "Estimate" WHERE id=${root.id} AND "companyId"=${companyId}
      UNION ALL SELECT e.id,f.path||e.id FROM "Estimate" e JOIN family f ON e."revisesEstimateId"=f.id
      WHERE e."companyId"=${companyId} AND NOT e.id=ANY(f.path) AND cardinality(f.path)<1000
    ) SELECT id FROM family`;
  if (family.length >= 1000)
    throw new ConflictError('The contract revision history needs review.');
  return { rootEstimateId: root.id, estimateIds: family.map((row) => row.id) };
}
export async function lockFamilyInvoices(
  tx: Prisma.TransactionClient,
  companyId: string,
  estimateIds: string[],
) {
  if (!estimateIds.length) return [];
  const rows = await tx.$queryRaw<Array<{ id: string }>>`
    SELECT id FROM "Invoice" WHERE "companyId"=${companyId} AND "estimateId" IN (${Prisma.join(estimateIds)}) ORDER BY id FOR UPDATE`;
  return rows.map((row) => row.id);
}
export async function lockContractForEstimate(
  tx: Prisma.TransactionClient,
  estimateId: string,
  companyId: string,
) {
  await lockCompanyPaymentAccess(tx, companyId);
  const family = await estimateFamily(tx, estimateId, companyId);
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`contract:${companyId}:estimate:${family.rootEstimateId}`},0))`;
  const current = await estimateFamily(tx, estimateId, companyId);
  return {
    rootEstimateId: family.rootEstimateId,
    invoiceIds: await lockFamilyInvoices(tx, companyId, current.estimateIds),
  };
}
export async function lockContractForInvoice(
  tx: Prisma.TransactionClient,
  invoiceId: string,
  companyId: string,
) {
  await lockCompanyPaymentAccess(tx, companyId);
  const invoice = await tx.invoice.findFirst({
    where: { id: invoiceId, companyId },
    select: { estimateId: true },
  });
  if (!invoice) throw new NotFoundError('Invoice', invoiceId);
  if (invoice.estimateId)
    return lockContractForEstimate(tx, invoice.estimateId, companyId);
  await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${`contract:${companyId}:invoice:${invoiceId}`},0))`;
  const rows = await tx.$queryRaw<
    Array<{ id: string }>
  >`SELECT id FROM "Invoice" WHERE id=${invoiceId} AND "companyId"=${companyId} FOR UPDATE`;
  if (!rows.length) throw new NotFoundError('Invoice', invoiceId);
  return { rootEstimateId: null, invoiceIds: [invoiceId] };
}
