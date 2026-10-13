import { Prisma } from "@prisma/client";
import { prisma } from "../../config/database";
import { NotFoundError, ValidationError } from "../../lib/errors";
import {
  CreateInvoiceLineItemInput,
  UpdateInvoiceLineItemInput,
} from "./invoice-line-items.validators";

export function computeInvoiceTotals(input: {
  subtotal: number;
  taxAmount: number;
  discountAmount: number;
  amountPaid: number;
}): { totalAmount: number; amountDue: number } {
  const totalAmount = Number(
    Prisma.Decimal.max(
      0,
      new Prisma.Decimal(input.subtotal)
        .plus(input.taxAmount)
        .minus(input.discountAmount),
    ).toDecimalPlaces(2),
  );
  const amountDue = Number(
    Prisma.Decimal.max(
      0,
      new Prisma.Decimal(totalAmount).minus(input.amountPaid),
    ).toDecimalPlaces(2),
  );
  return { totalAmount, amountDue };
}

/** The parent row lock serializes edits so the header always matches its lines. */
async function lockInvoice(
  tx: Prisma.TransactionClient,
  invoiceId: string,
  companyId: string,
) {
  const rows = await tx.$queryRaw<Array<{ id: string }>>`
    SELECT id FROM "Invoice" WHERE id = ${invoiceId} AND "companyId" = ${companyId} FOR UPDATE
  `;
  if (rows.length === 0) throw new NotFoundError("Invoice", invoiceId);
  return tx.invoice.findUniqueOrThrow({
    where: { id: invoiceId },
    include: { company: { select: { defaultTaxRate: true } } },
  });
}

export async function recalculateInvoiceTotals(
  invoiceId: string,
  tx: Prisma.TransactionClient = prisma,
) {
  const [lineItems, invoice] = await Promise.all([
    tx.invoiceLineItem.findMany({ where: { invoiceId } }),
    tx.invoice.findUniqueOrThrow({ where: { id: invoiceId } }),
  ]);
  const subtotal = lineItems.reduce(
    (sum, item) => sum + Number(item.lineTotal),
    0,
  );
  const taxAmount = Number(
    lineItems
      .reduce(
        (sum, item) => sum.plus(item.lineTotal.times(item.taxRate)),
        new Prisma.Decimal(0),
      )
      .toDecimalPlaces(2),
  );
  const { totalAmount, amountDue } = computeInvoiceTotals({
    subtotal,
    taxAmount,
    discountAmount: Number(invoice.discountAmount),
    amountPaid: Number(invoice.amountPaid),
  });
  if (Number(invoice.amountPaid) > totalAmount) {
    throw new ValidationError(
      "The invoice total cannot be reduced below its recorded payments",
    );
  }
  // A changed bill can reopen a previously paid balance; retain the payment itself.
  const status =
    invoice.status === "VOID"
      ? "VOID"
      : Number(invoice.amountPaid) > 0
        ? amountDue === 0
          ? "PAID"
          : "PARTIALLY_PAID"
        : invoice.status === "PAID" || invoice.status === "PARTIALLY_PAID"
          ? "SENT"
          : invoice.status;
  return tx.invoice.update({
    where: { id: invoiceId },
    data: {
      subtotal,
      taxAmount,
      totalAmount,
      amountDue,
      status,
      paidAt: status === "PAID" ? (invoice.paidAt ?? new Date()) : null,
    },
  });
}

async function verifyLineItemOwnership(
  lineItemId: string,
  companyId: string,
  tx: Prisma.TransactionClient = prisma,
) {
  const lineItem = await tx.invoiceLineItem.findFirst({
    where: { id: lineItemId, invoice: { companyId } },
  });
  if (!lineItem) throw new NotFoundError("InvoiceLineItem", lineItemId);
  return lineItem;
}

export async function listByInvoice(invoiceId: string, companyId: string) {
  const invoice = await prisma.invoice.findFirst({
    where: { id: invoiceId, companyId },
    select: { id: true },
  });
  if (!invoice) throw new NotFoundError("Invoice", invoiceId);
  return prisma.invoiceLineItem.findMany({
    where: { invoiceId },
    orderBy: [{ sortOrder: "asc" }, { id: "asc" }],
  });
}

function lineMoney(quantity: number, unitCost: number) {
  const storedQuantity = new Prisma.Decimal(quantity).toDecimalPlaces(2);
  const storedUnitCost = new Prisma.Decimal(unitCost).toDecimalPlaces(2);
  const lineTotal = storedQuantity.times(storedUnitCost).toDecimalPlaces(2);
  if (storedQuantity.lte(0) || lineTotal.gt("9999999999.99"))
    throw new ValidationError(
      "Line item quantity or total is outside the supported range",
    );
  return { quantity: storedQuantity, unitCost: storedUnitCost, lineTotal };
}

export async function create(
  invoiceId: string,
  companyId: string,
  data: CreateInvoiceLineItemInput,
) {
  return prisma.$transaction(async (tx) => {
    const invoice = await lockInvoice(tx, invoiceId, companyId);
    const lineItem = await tx.invoiceLineItem.create({
      data: {
        invoiceId,
        name: data.name,
        description: data.description ?? null,
        unit: data.unit,
        ...lineMoney(data.quantity, data.unit_cost),
        taxRate: Number(invoice.company.defaultTaxRate ?? 0) / 100,
        sortOrder: data.sort_order ?? 0,
      },
    });
    await recalculateInvoiceTotals(invoiceId, tx);
    return lineItem;
  });
}

export async function update(
  lineItemId: string,
  companyId: string,
  data: UpdateInvoiceLineItemInput,
) {
  const parent = await verifyLineItemOwnership(lineItemId, companyId);
  return prisma.$transaction(async (tx) => {
    await lockInvoice(tx, parent.invoiceId, companyId);
    const existing = await verifyLineItemOwnership(lineItemId, companyId, tx);
    const updateData: Prisma.InvoiceLineItemUpdateInput = {};
    if (data.name !== undefined) updateData.name = data.name;
    if (data.description !== undefined)
      updateData.description = data.description;
    if (data.quantity !== undefined) updateData.quantity = data.quantity;
    if (data.unit !== undefined) updateData.unit = data.unit;
    if (data.unit_cost !== undefined) updateData.unitCost = data.unit_cost;
    if (data.sort_order !== undefined) updateData.sortOrder = data.sort_order;
    if (data.quantity !== undefined || data.unit_cost !== undefined) {
      Object.assign(
        updateData,
        lineMoney(
          data.quantity ?? Number(existing.quantity),
          data.unit_cost ?? Number(existing.unitCost),
        ),
      );
    }
    const lineItem = await tx.invoiceLineItem.update({
      where: { id: lineItemId },
      data: updateData,
    });
    await recalculateInvoiceTotals(existing.invoiceId, tx);
    return lineItem;
  });
}

export async function remove(lineItemId: string, companyId: string) {
  const parent = await verifyLineItemOwnership(lineItemId, companyId);
  await prisma.$transaction(async (tx) => {
    await lockInvoice(tx, parent.invoiceId, companyId);
    const existing = await verifyLineItemOwnership(lineItemId, companyId, tx);
    await tx.invoiceLineItem.delete({ where: { id: lineItemId } });
    await recalculateInvoiceTotals(existing.invoiceId, tx);
  });
}
