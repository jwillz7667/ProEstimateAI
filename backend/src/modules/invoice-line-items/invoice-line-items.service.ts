import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { CreateInvoiceLineItemInput, UpdateInvoiceLineItemInput } from './invoice-line-items.validators';

/**
 * Recalculates the aggregate totals on an Invoice by summing its line items.
 * Called after every line item create / update / delete.
 */
async function recalculateInvoiceTotals(invoiceId: string) {
  const lineItems = await prisma.invoiceLineItem.findMany({ where: { invoiceId } });

  const subtotal = lineItems.reduce((sum, item) => sum + Number(item.lineTotal), 0);

  const invoice = await prisma.invoice.findUnique({
    where: { id: invoiceId },
    include: { company: { select: { defaultTaxRate: true } } },
  });

  const defaultTaxRate = Number(invoice?.company?.defaultTaxRate ?? 0);
  const taxAmount = subtotal * (defaultTaxRate / 100);
  const totalAmount = subtotal + taxAmount;
  const amountDue = totalAmount - Number(invoice?.amountPaid ?? 0);

  await prisma.invoice.update({
    where: { id: invoiceId },
    data: { subtotal, taxAmount, totalAmount, amountDue },
  });
}

/**
 * Verify that an invoice exists and belongs to the given company.
 */
async function verifyInvoiceOwnership(invoiceId: string, companyId: string) {
  const invoice = await prisma.invoice.findFirst({
    where: { id: invoiceId, companyId },
  });

  if (!invoice) {
    throw new NotFoundError('Invoice', invoiceId);
  }

  return invoice;
}

/**
 * Verify a line item exists and that its parent invoice belongs to the given company.
 */
async function verifyLineItemOwnership(lineItemId: string, companyId: string) {
  const lineItem = await prisma.invoiceLineItem.findUnique({
    where: { id: lineItemId },
    include: { invoice: { select: { id: true, companyId: true } } },
  });

  if (!lineItem || lineItem.invoice.companyId !== companyId) {
    throw new NotFoundError('InvoiceLineItem', lineItemId);
  }

  return lineItem;
}

export async function listByInvoice(invoiceId: string, companyId: string) {
  // Verify the invoice belongs to this company
  await verifyInvoiceOwnership(invoiceId, companyId);

  const lineItems = await prisma.invoiceLineItem.findMany({
    where: { invoiceId },
    orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
  });

  return lineItems;
}

export async function create(invoiceId: string, companyId: string, data: CreateInvoiceLineItemInput) {
  // Verify the invoice belongs to this company
  await verifyInvoiceOwnership(invoiceId, companyId);

  // Calculate line total: quantity * unitCost
  const lineTotal = data.quantity * data.unit_cost;

  const lineItem = await prisma.invoiceLineItem.create({
    data: {
      invoiceId,
      name: data.name,
      description: data.description ?? null,
      quantity: data.quantity,
      unit: data.unit,
      unitCost: data.unit_cost,
      lineTotal,
      sortOrder: data.sort_order ?? 0,
    },
  });

  // Recalculate invoice totals after adding a line item
  await recalculateInvoiceTotals(invoiceId);

  return lineItem;
}

export async function update(lineItemId: string, companyId: string, data: UpdateInvoiceLineItemInput) {
  const existing = await verifyLineItemOwnership(lineItemId, companyId);

  const updateData: any = {};

  if (data.name !== undefined) {
    updateData.name = data.name;
  }
  if (data.description !== undefined) {
    updateData.description = data.description;
  }
  if (data.quantity !== undefined) {
    updateData.quantity = data.quantity;
  }
  if (data.unit !== undefined) {
    updateData.unit = data.unit;
  }
  if (data.unit_cost !== undefined) {
    updateData.unitCost = data.unit_cost;
  }
  if (data.sort_order !== undefined) {
    updateData.sortOrder = data.sort_order;
  }

  // Recalculate line total using merged values
  const quantity = data.quantity ?? Number(existing.quantity);
  const unitCost = data.unit_cost ?? Number(existing.unitCost);
  updateData.lineTotal = quantity * unitCost;

  const lineItem = await prisma.invoiceLineItem.update({
    where: { id: lineItemId },
    data: updateData,
  });

  // Recalculate invoice totals
  await recalculateInvoiceTotals(existing.invoiceId);

  return lineItem;
}

export async function remove(lineItemId: string, companyId: string) {
  const existing = await verifyLineItemOwnership(lineItemId, companyId);

  await prisma.invoiceLineItem.delete({ where: { id: lineItemId } });

  // Recalculate invoice totals after removal
  await recalculateInvoiceTotals(existing.invoiceId);
}
