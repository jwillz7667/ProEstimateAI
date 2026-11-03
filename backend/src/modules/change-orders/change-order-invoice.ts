import { Prisma } from '@prisma/client';
import { ConflictError } from '../../lib/errors';
import { estimateFamily } from './change-order-locks';

/** First billing includes every approved amendment in the latest full price.
 * Once a family is billed this route is never used to issue another full bill.
 */
export async function assertChangeOrderFirstInvoice(
  tx: Prisma.TransactionClient,
  companyId: string,
  estimateId: string,
) {
  const family = await estimateFamily(tx, estimateId, companyId);
  const pending = await tx.changeOrder.findFirst({
    where: {
      companyId,
      rootEstimateId: family.rootEstimateId,
      status: { in: ['DRAFT', 'SENT'] },
    },
  });
  if (pending)
    throw new ConflictError(
      'Finish the pending change order before creating the first invoice.',
    );
  const latest = await tx.changeOrder.findFirst({
    where: {
      companyId,
      rootEstimateId: family.rootEstimateId,
      status: { in: ['APPROVED', 'APPLIED', 'INCLUDED'] },
    },
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
  });
  if (latest && latest.estimateId !== estimateId)
    throw new ConflictError(
      'Create the first invoice from the latest approved change order so the full agreed price is billed once.',
    );
}
export async function includeChangeOrdersInFirstInvoice(
  tx: Prisma.TransactionClient,
  companyId: string,
  estimateId: string,
  invoiceId: string,
) {
  const family = await estimateFamily(tx, estimateId, companyId);
  await tx.changeOrder.updateMany({
    where: {
      companyId,
      rootEstimateId: family.rootEstimateId,
      status: 'APPROVED',
    },
    data: {
      status: 'INCLUDED',
      rootInvoiceId: invoiceId,
      appliedAt: new Date(),
    },
  });
  // Even the first full invoice is immutable when it incorporates approved COs.
  const count = await tx.changeOrder.count({
    where: {
      companyId,
      rootEstimateId: family.rootEstimateId,
      status: 'INCLUDED',
      rootInvoiceId: invoiceId,
    },
  });
  if (count)
    await tx.invoice.update({
      where: { id: invoiceId },
      data: { financialBasisLocked: true },
    });
}

/** Legacy invoices may have an explicit extra discount/concession. Preserve
 * that concession while refusing a manually repriced original cost/tax basis.
 */
export async function assertOriginalInvoiceBasis(
  tx: Prisma.TransactionClient,
  invoice: {
    id: string;
    financialBasisLocked?: boolean;
    estimateId: string | null;
    subtotal: Prisma.Decimal;
    taxAmount: Prisma.Decimal;
    discountAmount: Prisma.Decimal;
    totalAmount: Prisma.Decimal;
    currencyCode: string | null;
  },
  companyId: string,
) {
  if (!invoice.estimateId)
    throw new ConflictError(
      'The original contract invoice has no approved estimate basis.',
    );
  const source = await tx.estimate.findFirst({
    where: { id: invoice.estimateId, companyId, status: 'APPROVED' },
  });
  if (!source)
    throw new ConflictError(
      'The original contract price needs review before it can be amended.',
    );
  const subtotal = source.subtotalMaterials
    .plus(source.subtotalLabor)
    .plus(source.subtotalOther);
  if (
    (invoice.currencyCode ?? 'USD').toUpperCase() !== 'USD' ||
    !invoice.subtotal.equals(subtotal) ||
    !invoice.taxAmount.equals(source.taxAmount) ||
    invoice.discountAmount.lt(source.discountAmount) ||
    !invoice.totalAmount.equals(
      Prisma.Decimal.max(
        0,
        subtotal.plus(invoice.taxAmount).minus(invoice.discountAmount),
      ),
    )
  )
    throw new ConflictError(
      'The original invoice was repriced outside its approved contract. Review its financial basis before applying a change order.',
    );
  if (!invoice.financialBasisLocked)
    await tx.invoice.update({
      where: { id: invoice.id },
      data: { financialBasisLocked: true },
    });
}
