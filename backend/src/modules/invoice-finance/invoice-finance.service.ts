import { randomUUID } from "node:crypto";
import { Prisma } from "@prisma/client";
import { prisma } from "../../config/database";
import { env } from "../../config/env";
import { ConflictError, NotFoundError, ValidationError } from "../../lib/errors";
import { toInvoiceDto } from "../invoices/invoices.dto";
import type { InvoiceScheduleInput, RecordInvoicePaymentInput } from "./invoice-finance.validators";
import { assertNoActiveCheckout, invoiceCheckoutInfo } from "../invoice-checkout/invoice-checkout.policy";
import { sharedCheckoutAvailability } from "../invoice-checkout/invoice-checkout.service";
import { invoiceAmountDue, allocateInvoiceInstallments } from "./invoice-balance";
import { lockContractForInvoice } from "../change-orders/change-order-locks";
import { applyAvailableContractCredits } from "../change-orders/credit-notes.service";

async function lockedInvoice(tx: Prisma.TransactionClient, id: string, companyId: string) {
  const contract = await lockContractForInvoice(tx, id, companyId);
  const rows = await tx.$queryRaw<Array<{ id: string }>>`
    SELECT id FROM "Invoice" WHERE id = ${id} AND "companyId" = ${companyId} FOR UPDATE`;
  if (!rows.length) throw new NotFoundError("Invoice", id);
  return { ...await tx.invoice.findUniqueOrThrow({ where: { id } }), contractRootEstimateId: contract.rootEstimateId };
}

export async function getFinance(id: string, companyId: string) {
  const invoice = await prisma.invoice.findFirst({ where: { id, companyId }, include: {
    payments: { orderBy: [{ createdAt: "asc" }, { id: "asc" }] },
    installments: { orderBy: { sortOrder: "asc" } },
  } });
  if (!invoice) throw new NotFoundError("Invoice", id);
  const installments = allocateInvoiceInstallments(invoice.installments, invoice.amountPaid, invoice.creditAmount);
  return {
    invoice: toInvoiceDto(invoice),
    share_url: invoice.status === "DRAFT" ? null : `${env.PUBLIC_WEB_BASE_URL.replace(/\/$/, "")}/invoice/${encodeURIComponent(invoice.shareToken)}`,
    payments: invoice.payments.map((payment) => ({
      id: payment.id, request_id: payment.requestId, amount: Number(payment.amount), method: payment.method.toLowerCase(),
      reference: payment.reference, notes: payment.notes,
      recorded_at: payment.recordedAt?.toISOString() ?? null, created_at: payment.createdAt.toISOString(),
    })),
    installments: installments.map((installment) => {
      return {
        id: installment.id, title: installment.title, amount: Number(installment.amount),
        paid_amount: Number(installment.paidAmount), credit_amount: Number(installment.creditAmount), amount_due: Number(installment.amountDue),
        due_date: installment.dueDate?.toISOString() ?? null, sort_order: installment.sortOrder,
      };
    }),
    checkout: await invoiceCheckoutInfo(id, companyId),
  };
}

export async function recordPayment(id: string, companyId: string, userId: string, input: RecordInvoicePaymentInput) {
  const amount = new Prisma.Decimal(input.amount);
  if (amount.lte(0) || amount.decimalPlaces() > 2) throw new ValidationError("Enter a positive payment with at most two decimal places");
  let refusal: Error | undefined;
  await prisma.$transaction(async (tx) => {
    let invoice = await lockedInvoice(tx, id, companyId);
    const existing = await tx.invoicePayment.findUnique({ where: { companyId_requestId: { companyId, requestId: input.request_id } } });
    if (existing) {
      if (existing.invoiceId !== id || !existing.amount.equals(amount) || existing.method !== input.method.toUpperCase() ||
          existing.reference !== (input.reference ?? null) || existing.notes !== (input.notes ?? null) ||
          (input.recorded_at && existing.recordedAt?.toISOString() !== new Date(input.recorded_at).toISOString())) {
        throw new ConflictError("This payment request was already used with different details");
      }
      return;
    }
    await assertNoActiveCheckout(tx, id);
    if (invoice.status === "DRAFT" || invoice.status === "VOID") throw new ConflictError("Send the invoice before recording a payment");
    if (invoice.contractRootEstimateId) {
      await applyAvailableContractCredits(tx, companyId, invoice.contractRootEstimateId);
      invoice = { ...await tx.invoice.findUniqueOrThrow({ where: { id } }), contractRootEstimateId: invoice.contractRootEstimateId };
    }
    if (invoice.paymentReviewRequired) {
      refusal = new ConflictError("An owner or administrator must reconcile the refund, credits or dispute before recording another payment");
      return;
    }
    if (amount.gt(invoice.amountDue)) {
      refusal = new ValidationError("The payment exceeds the current outstanding balance after contract credits. Refresh this invoice.");
      return;
    }
    const recordedAt = input.recorded_at ? new Date(input.recorded_at) : new Date();
    if (recordedAt.getTime() > Date.now() + 60_000) throw new ValidationError("A payment date cannot be in the future");
    await tx.invoicePayment.create({ data: {
      invoiceId: id, companyId, requestId: input.request_id, amount, method: input.method.toUpperCase(),
      reference: input.reference ?? null, notes: input.notes ?? null, recordedAt,
    } });
    const paid = invoice.amountPaid.plus(amount);
    const due = invoiceAmountDue(invoice.totalAmount, paid, invoice.creditAmount);
    await tx.invoice.update({ where: { id }, data: {
      amountPaid: paid, amountDue: due, status: due.isZero() ? "PAID" : "PARTIALLY_PAID",
      paidAt: due.isZero() ? recordedAt : null,
    } });
    await tx.activityLogEntry.create({ data: {
      companyId, projectId: invoice.projectId, userId, action: due.isZero() ? "INVOICE_PAID" : "UPDATED",
      entityType: "InvoicePayment",
      description: `Payment recorded for invoice ${invoice.invoiceNumber}`,
      metadataJson: { request_id: input.request_id, amount: amount.toFixed(2), method: input.method },
    } });
  });
  if (refusal) throw refusal;
  return getFinance(id, companyId);
}

/** Older app builds PATCH a cumulative balance; retain an explicit adjustment receipt for every delta. */
export async function recordLegacyBalanceChange(
  tx: Prisma.TransactionClient,
  invoice: { id: string; companyId: string; amountPaid: Prisma.Decimal },
  nextPaid: Prisma.Decimal,
) {
  const delta = nextPaid.minus(invoice.amountPaid);
  if (delta.isZero()) return;
  await tx.invoicePayment.create({ data: {
    invoiceId: invoice.id, companyId: invoice.companyId, requestId: randomUUID(), amount: delta,
    method: delta.isNegative() ? "BALANCE_CORRECTION" : "LEGACY_MANUAL", recordedAt: new Date(),
  } });
}

export async function replaceSchedule(id: string, companyId: string, input: InvoiceScheduleInput) {
  await prisma.$transaction(async (tx) => {
    const invoice = await lockedInvoice(tx, id, companyId);
    if (invoice.status !== "DRAFT" || !invoice.amountPaid.isZero()) throw new ConflictError("Set the payment schedule before sending the invoice");
    if (!invoice.totalAmount.equals(input.expected_total)) throw new ConflictError("The invoice total changed. Refresh before setting a payment schedule.");
    const total = input.installments.reduce((sum, item) => sum.plus(item.amount), new Prisma.Decimal(0));
    if (!total.equals(invoice.totalAmount)) throw new ValidationError("Scheduled payments must add up to the invoice total");
    await tx.invoiceInstallment.deleteMany({ where: { invoiceId: id } });
    await tx.invoiceInstallment.createMany({ data: input.installments.map((item, index) => ({
      invoiceId: id, title: item.title, amount: item.amount,
      dueDate: item.due_date ? new Date(item.due_date) : null, sortOrder: index,
    })) });
  });
  return getFinance(id, companyId);
}

export async function getSharedInvoice(token: string) {
  const invoice = await prisma.invoice.findUnique({ where: { shareToken: token }, include: {
    company: true, client: true, project: true, lineItems: { orderBy: { sortOrder: "asc" } },
  } });
  if (!invoice || invoice.status === "DRAFT") throw new NotFoundError("Invoice");
  const finance = await getFinance(invoice.id, invoice.companyId);
  return {
    invoice: finance.invoice,
    company: { name: invoice.company.name, logo_url: invoice.company.logoUrl, primary_color: invoice.company.primaryColor,
      email: invoice.company.email, phone: invoice.company.phone },
    client: { name: invoice.client.name }, project: { title: invoice.project.title },
    line_items: invoice.lineItems.map((item) => ({ name: item.name, description: item.description,
      quantity: Number(item.quantity), unit: item.unit, unit_cost: Number(item.unitCost), line_total: Number(item.lineTotal) })),
    // Internal notes and processor identifiers never leave the contractor's account.
    payments: finance.payments.map(({ notes: _notes, reference: _reference, request_id: _requestId, ...payment }) => payment),
    installments: finance.installments,
    online_payment: await sharedCheckoutAvailability(invoice.id, invoice.companyId),
  };
}
