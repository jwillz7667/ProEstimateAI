import { prisma } from "../../config/database";
import {
  NotFoundError,
  PaywallError,
  ValidationError,
  ConflictError,
} from "../../lib/errors";
import { isAdminUser } from "../../lib/admin";
import {
  PaginationParams,
  paginateResults,
  buildCursorWhere,
} from "../../lib/pagination";
import {
  CreateInvoiceInput,
  UpdateInvoiceInput,
  ConvertEstimateToInvoiceInput,
} from "./invoices.validators";
import { computeInvoiceTotals } from "../invoice-line-items/invoice-line-items.service";
import { InvoiceStatus, Prisma } from "@prisma/client";

/**
 * Paywall decision for INVOICE_LOCKED placement.
 * Returned when a free-tier user attempts to create an invoice.
 */
const INVOICE_LOCKED_PAYWALL = {
  placement: "INVOICE_LOCKED",
  trigger_reason: "Invoice creation requires Pro subscription",
  blocking: true,
  headline: "Invoicing is a Pro Feature",
  subheadline: "Upgrade to create and send professional invoices",
  primary_cta_title: "Start Free Trial",
  secondary_cta_title: "View Plans",
  show_continue_free: false,
  show_restore_purchases: true,
  recommended_product_id: "proestimate.pro.monthly",
  available_products: null,
};

/**
 * Check whether the user holds a CAN_CREATE_INVOICE entitlement.
 * Reads the user's active entitlement, then inspects the associated Plan's
 * featuresJson array for the CAN_CREATE_INVOICE feature code.
 */
async function assertCanCreateInvoice(userId: string): Promise<void> {
  if (await isAdminUser(userId)) return;

  const entitlement = await prisma.userEntitlement.findUnique({
    where: { userId },
    include: { plan: { select: { featuresJson: true } } },
  });

  if (!entitlement) {
    throw new PaywallError(
      "Invoice creation requires Pro subscription",
      INVOICE_LOCKED_PAYWALL,
    );
  }

  // featuresJson is stored as an object: { CAN_CREATE_INVOICE: true, ... }
  const features = entitlement.plan.featuresJson as Record<string, unknown>;
  const canCreate = features.CAN_CREATE_INVOICE === true;

  // Also verify the entitlement status permits access
  const activeStatuses = [
    "TRIAL_ACTIVE",
    "PRO_ACTIVE",
    "GRACE_PERIOD",
    "BILLING_RETRY",
    "CANCELED_ACTIVE",
    "ADMIN_OVERRIDE",
  ];
  const isActiveStatus = activeStatuses.includes(entitlement.status);

  if (!canCreate || !isActiveStatus) {
    throw new PaywallError(
      "Invoice creation requires Pro subscription",
      INVOICE_LOCKED_PAYWALL,
    );
  }
}

export async function list(
  companyId: string,
  pagination: PaginationParams,
  projectId?: string,
) {
  const { cursor, pageSize = 25 } = pagination;

  const where: any = { companyId };
  if (projectId) {
    where.projectId = projectId;
  }

  const invoices = await prisma.invoice.findMany({
    where,
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: pageSize + 1,
    ...buildCursorWhere(cursor),
  });

  return paginateResults(invoices, pageSize);
}

export async function getById(id: string, companyId: string) {
  const invoice = await prisma.invoice.findFirst({
    where: { id, companyId },
  });

  if (!invoice) {
    throw new NotFoundError("Invoice", id);
  }

  return invoice;
}

export async function create(
  companyId: string,
  userId: string,
  data: CreateInvoiceInput,
) {
  // Entitlement gate: user must be Pro to create invoices
  await assertCanCreateInvoice(userId);

  // Verify project belongs to company
  const project = await prisma.project.findFirst({
    where: { id: data.project_id, companyId },
    select: { id: true },
  });

  if (!project) {
    throw new NotFoundError("Project", data.project_id);
  }

  // Verify client belongs to company
  const client = await prisma.client.findFirst({
    where: { id: data.client_id, companyId },
  });

  if (!client) {
    throw new NotFoundError("Client", data.client_id);
  }

  // If an estimate_id is provided, verify it belongs to the company
  if (data.estimate_id) {
    const estimate = await prisma.estimate.findFirst({
      where: { id: data.estimate_id, companyId, projectId: data.project_id },
    });

    if (!estimate) {
      throw new NotFoundError("Estimate", data.estimate_id);
    }
  }

  await verifyProposalOwnership(
    data.proposal_id,
    companyId,
    data.project_id,
    data.estimate_id,
  );

  // Auto-increment invoice number inside a transaction
  const invoice = await prisma.$transaction(async (tx) => {
    // Atomically claim the next number. The increment row-locks the company
    // row, serializing concurrent creates for the same company; a
    // read-then-write under READ COMMITTED would let two transactions read
    // the same value and collide on @@unique([companyId, invoiceNumber])
    // (spurious 500). The returned counter is post-increment, so the number
    // we claimed is one less.
    const company = await tx.company
      .update({
        where: { id: companyId },
        data: { nextInvoiceNumber: { increment: 1 } },
        select: { invoicePrefix: true, nextInvoiceNumber: true },
      })
      .catch((err: unknown) => {
        if (
          err instanceof Prisma.PrismaClientKnownRequestError &&
          err.code === "P2025"
        ) {
          throw new NotFoundError("Company", companyId);
        }
        throw err;
      });

    const invoiceNumber = `${company.invoicePrefix || "INV"}-${company.nextInvoiceNumber - 1}`;

    // Create the invoice
    const created = await tx.invoice.create({
      data: {
        projectId: data.project_id,
        companyId,
        clientId: data.client_id,
        estimateId: data.estimate_id ?? null,
        proposalId: data.proposal_id ?? null,
        invoiceNumber,
        notes: data.notes ?? null,
        issuedDate: data.issued_date ? new Date(data.issued_date) : null,
        dueDate: data.due_date ? new Date(data.due_date) : null,
        discountAmount: data.discount_amount ?? 0,
        paymentInstructions: data.payment_instructions ?? null,
        currencyCode: data.currency_code ?? null,
      },
    });

    // Log activity
    await tx.activityLogEntry.create({
      data: {
        projectId: data.project_id,
        userId,
        action: "INVOICE_CREATED",
        description: `Invoice ${invoiceNumber} created`,
      },
    });

    return created;
  });

  return invoice;
}

/**
 * Convert an existing estimate into a DRAFT invoice. Pro-gated like manual
 * invoice creation. The invoice mirrors the estimate's money exactly — the
 * pre-tax subtotal, the estimate's tax, and the estimate total are copied
 * verbatim rather than re-derived, so the client is billed precisely what the
 * approved estimate showed (no double-tax, no per-line-vs-company-rate drift).
 * Each estimate line becomes an invoice line; its tax fraction is snapshotted
 * and its marked-up unit price is folded into unitCost, while
 * lineTotal stays the estimate line's pre-tax (markup-inclusive) total.
 */
export async function createFromEstimate(
  companyId: string,
  userId: string,
  estimateId: string,
  data: ConvertEstimateToInvoiceInput,
) {
  // Entitlement gate first: free users get a 402 before any work happens.
  await assertCanCreateInvoice(userId);

  return prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw<
      Array<{ id: string }>
    >`SELECT id FROM "Estimate" WHERE id = ${estimateId} AND "companyId" = ${companyId} FOR UPDATE`;
    if (rows.length === 0) throw new NotFoundError("Estimate", estimateId);
    const estimate = await tx.estimate.findFirst({
      where: { id: estimateId, companyId },
      include: {
        lineItems: { orderBy: { sortOrder: "asc" } },
        project: { select: { id: true, clientId: true } },
      },
    });

    if (!estimate) {
      throw new NotFoundError("Estimate", estimateId);
    }

    // An invoice requires a client (Invoice.clientId is non-null). Projects can
    // exist without one, so fail loudly rather than inventing a client.
    const clientId = estimate.project.clientId;
    if (!clientId) {
      throw new ValidationError(
        "The estimate's project has no client assigned. Assign a client to the project before converting it to an invoice.",
      );
    }

    const subtotal =
      Number(estimate.subtotalMaterials) +
      Number(estimate.subtotalLabor) +
      Number(estimate.subtotalOther);
    const taxAmount = Number(estimate.taxAmount);
    const discountAmount = Number(estimate.discountAmount);
    const totalAmount = Number(estimate.totalAmount);

    // Same atomic-numbering pattern as create() — increment row-locks the
    // company row so concurrent creates can't collide on the unique number.
    const company = await tx.company
      .update({
        where: { id: companyId },
        data: { nextInvoiceNumber: { increment: 1 } },
        select: { invoicePrefix: true, nextInvoiceNumber: true },
      })
      .catch((err: unknown) => {
        if (
          err instanceof Prisma.PrismaClientKnownRequestError &&
          err.code === "P2025"
        ) {
          throw new NotFoundError("Company", companyId);
        }
        throw err;
      });

    const invoiceNumber = `${company.invoicePrefix || "INV"}-${company.nextInvoiceNumber - 1}`;

    const created = await tx.invoice.create({
      data: {
        projectId: estimate.projectId,
        companyId,
        clientId,
        estimateId: estimate.id,
        invoiceNumber,
        subtotal,
        taxAmount,
        discountAmount,
        totalAmount,
        amountPaid: 0,
        amountDue: totalAmount,
        notes: data.notes ?? null,
        dueDate: data.due_date ? new Date(data.due_date) : null,
        paymentInstructions: data.payment_instructions ?? null,
      },
    });

    for (let i = 0; i < estimate.lineItems.length; i++) {
      const li = estimate.lineItems[i];
      const lineTotal = Number(li.lineTotal);
      const quantity = Number(li.quantity);
      // Fold markup into the client-facing unit price. lineTotal is stored
      // authoritatively (the header subtotal sums lineTotals), so unit-cost
      // rounding can't drift the invoice total.
      const effectiveUnitCost = quantity > 0 ? lineTotal / quantity : lineTotal;

      await tx.invoiceLineItem.create({
        data: {
          invoiceId: created.id,
          name: li.name,
          description: li.description,
          quantity: quantity > 0 ? quantity : 1,
          unit: li.unit,
          unitCost: effectiveUnitCost,
          lineTotal,
          taxRate: li.taxRate,
          sortOrder: li.sortOrder,
        },
      });
    }

    await tx.activityLogEntry.create({
      data: {
        projectId: estimate.projectId,
        userId,
        action: "INVOICE_CREATED",
        description: `Invoice ${invoiceNumber} created from estimate ${estimate.estimateNumber}`,
      },
    });

    return created;
  });
}

async function verifyProposalOwnership(
  proposalId: string | null | undefined,
  companyId: string,
  projectId: string,
  estimateId?: string | null,
  database: Prisma.TransactionClient = prisma,
) {
  if (!proposalId) return;
  const proposal = await database.proposal.findFirst({
    where: {
      id: proposalId,
      companyId,
      projectId,
      ...(estimateId ? { estimateId } : {}),
    },
    select: { id: true },
  });
  if (!proposal) throw new NotFoundError("Proposal", proposalId);
}

export async function update(
  id: string,
  companyId: string,
  data: UpdateInvoiceInput,
) {
  return prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT id FROM "Invoice" WHERE id = ${id} AND "companyId" = ${companyId} FOR UPDATE
    `;
    if (rows.length === 0) throw new NotFoundError("Invoice", id);
    const existing = await tx.invoice.findUniqueOrThrow({ where: { id } });
    if (
      data.expected_amount_paid !== undefined &&
      !existing.amountPaid.equals(
        new Prisma.Decimal(data.expected_amount_paid).toDecimalPlaces(2),
      )
    ) {
      throw new ConflictError(
        "Invoice payments changed since you opened it. Refresh the invoice before recording this payment.",
      );
    }
    await verifyProposalOwnership(
      data.proposal_id,
      companyId,
      existing.projectId,
      existing.estimateId,
      tx,
    );

    const updateData: Prisma.InvoiceUpdateInput = {};
    if (data.status !== undefined)
      updateData.status = data.status.toUpperCase() as InvoiceStatus;
    if (data.notes !== undefined) updateData.notes = data.notes;
    if (data.proposal_id !== undefined)
      updateData.proposalId = data.proposal_id;
    if (data.issued_date !== undefined)
      updateData.issuedDate = data.issued_date
        ? new Date(data.issued_date)
        : null;
    if (data.due_date !== undefined)
      updateData.dueDate = data.due_date ? new Date(data.due_date) : null;
    if (data.payment_instructions !== undefined)
      updateData.paymentInstructions = data.payment_instructions;
    if (data.currency_code !== undefined)
      updateData.currencyCode = data.currency_code;

    // Payments and discounts affect the balance, never the previously agreed tax.
    const discountAmount = Number(
      new Prisma.Decimal(
        data.discount_amount !== undefined
          ? (data.discount_amount ?? 0)
          : existing.discountAmount,
      ).toDecimalPlaces(2),
    );
    const totalAmount = computeInvoiceTotals({
      subtotal: Number(existing.subtotal),
      taxAmount: Number(existing.taxAmount),
      discountAmount,
      amountPaid: 0,
    }).totalAmount;
    const amountPaid = Number(
      new Prisma.Decimal(
        data.amount_paid ??
          (data.status === "paid" ? totalAmount : existing.amountPaid),
      ).toDecimalPlaces(2),
    );
    if (amountPaid > totalAmount)
      throw new ValidationError(
        "Recorded payments cannot exceed the invoice total",
      );
    const amountDue = computeInvoiceTotals({
      subtotal: Number(existing.subtotal),
      taxAmount: Number(existing.taxAmount),
      discountAmount,
      amountPaid,
    }).amountDue;
    const financialChange =
      data.discount_amount !== undefined ||
      data.amount_paid !== undefined ||
      data.status === "paid";
    if (financialChange) {
      updateData.discountAmount = discountAmount;
      updateData.totalAmount = totalAmount;
      updateData.amountPaid = amountPaid;
      updateData.amountDue = amountDue;
      if (data.status !== "void" && existing.status !== "VOID") {
        if (amountPaid > 0 || data.status === "paid") {
          updateData.status = amountDue === 0 ? "PAID" : "PARTIALLY_PAID";
        } else if (
          existing.status === "PAID" ||
          existing.status === "PARTIALLY_PAID"
        ) {
          updateData.status = "SENT";
        }
      }
    }
    const nextStatus = updateData.status ?? existing.status;
    if (nextStatus === "PAID")
      updateData.paidAt = existing.paidAt ?? new Date();
    else if (data.status !== undefined || financialChange)
      updateData.paidAt = null;
    return tx.invoice.update({ where: { id }, data: updateData });
  });
}

export async function send(
  invoiceId: string,
  companyId: string,
  userId: string,
) {
  const updated = await prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw<
      Array<{ id: string }>
    >`SELECT id FROM "Invoice" WHERE id = ${invoiceId} AND "companyId" = ${companyId} FOR UPDATE`;
    if (rows.length === 0) throw new NotFoundError("Invoice", invoiceId);
    const invoice = await tx.invoice.findUniqueOrThrow({
      where: { id: invoiceId },
    });
    if (invoice.status === "PAID" || invoice.status === "VOID")
      throw new ValidationError("Paid or void invoices cannot be sent");
    const result = await tx.invoice.update({
      where: { id: invoiceId },
      data: {
        status: invoice.status === "PARTIALLY_PAID" ? "PARTIALLY_PAID" : "SENT",
        sentAt: new Date(),
      },
    });
    await tx.activityLogEntry.create({
      data: {
        projectId: invoice.projectId,
        userId,
        action: "INVOICE_SENT",
        description: `Invoice ${invoice.invoiceNumber} sent`,
      },
    });
    return result;
  });

  // Send email to client
  const client = await prisma.client.findUnique({
    where: { id: updated.clientId },
  });
  const company = await prisma.company.findUnique({ where: { id: companyId } });
  if (client?.email && company) {
    const { sendInvoiceEmail } = await import("../../lib/email");
    const currency = updated.currencyCode?.toUpperCase() ?? "USD";
    const amount = /^[A-Z]{3}$/.test(currency)
      ? new Intl.NumberFormat("en-US", { style: "currency", currency }).format(Number(updated.totalAmount))
      : `${currency} ${Number(updated.totalAmount).toFixed(2)}`;
    const { env } = await import("../../config/env");
    const invoicePdf = env.RESEND_API_KEY
      ? {
          filename: `${updated.invoiceNumber.replace(/[^a-zA-Z0-9_-]/g, "_")}.pdf`,
          content: await (
            await import("../pdf/pdf.service")
          ).generateInvoicePDF(updated.id, companyId, userId),
        }
      : undefined;
    await sendInvoiceEmail(client.email, "", company.name, amount, invoicePdf);
  }

  return updated;
}

export async function remove(id: string, companyId: string) {
  const existing = await prisma.invoice.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError("Invoice", id);
  }

  await prisma.invoice.delete({ where: { id } });
}
