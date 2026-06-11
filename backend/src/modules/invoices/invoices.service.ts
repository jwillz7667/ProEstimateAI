import { prisma } from '../../config/database';
import { NotFoundError, PaywallError, ValidationError } from '../../lib/errors';
import { isAdminUser } from '../../lib/admin';
import { PaginationParams, paginateResults, buildCursorWhere } from '../../lib/pagination';
import {
  CreateInvoiceInput,
  UpdateInvoiceInput,
  ConvertEstimateToInvoiceInput,
} from './invoices.validators';
import { recalculateInvoiceTotals } from '../invoice-line-items/invoice-line-items.service';
import { InvoiceStatus, Prisma } from '@prisma/client';

/**
 * Paywall decision for INVOICE_LOCKED placement.
 * Returned when a free-tier user attempts to create an invoice.
 */
const INVOICE_LOCKED_PAYWALL = {
  placement: 'INVOICE_LOCKED',
  trigger_reason: 'Invoice creation requires Pro subscription',
  blocking: true,
  headline: 'Invoicing is a Pro Feature',
  subheadline: 'Upgrade to create and send professional invoices',
  primary_cta_title: 'Start Free Trial',
  secondary_cta_title: 'View Plans',
  show_continue_free: false,
  show_restore_purchases: true,
  recommended_product_id: 'proestimate.pro.monthly',
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
    throw new PaywallError('Invoice creation requires Pro subscription', INVOICE_LOCKED_PAYWALL);
  }

  // featuresJson is stored as an object: { CAN_CREATE_INVOICE: true, ... }
  const features = entitlement.plan.featuresJson as Record<string, unknown>;
  const canCreate = features.CAN_CREATE_INVOICE === true;

  // Also verify the entitlement status permits access
  const activeStatuses = ['TRIAL_ACTIVE', 'PRO_ACTIVE', 'GRACE_PERIOD', 'BILLING_RETRY', 'CANCELED_ACTIVE'];
  const isActiveStatus = activeStatuses.includes(entitlement.status);

  if (!canCreate || !isActiveStatus) {
    throw new PaywallError('Invoice creation requires Pro subscription', INVOICE_LOCKED_PAYWALL);
  }
}

export async function list(companyId: string, pagination: PaginationParams, projectId?: string) {
  const { cursor, pageSize = 25 } = pagination;

  const where: any = { companyId };
  if (projectId) {
    where.projectId = projectId;
  }

  const invoices = await prisma.invoice.findMany({
    where,
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
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
    throw new NotFoundError('Invoice', id);
  }

  return invoice;
}

export async function create(companyId: string, userId: string, data: CreateInvoiceInput) {
  // Entitlement gate: user must be Pro to create invoices
  await assertCanCreateInvoice(userId);

  // Verify project belongs to company
  const project = await prisma.project.findFirst({
    where: { id: data.project_id, companyId },
    select: { id: true },
  });

  if (!project) {
    throw new NotFoundError('Project', data.project_id);
  }

  // Verify client belongs to company
  const client = await prisma.client.findFirst({
    where: { id: data.client_id, companyId },
  });

  if (!client) {
    throw new NotFoundError('Client', data.client_id);
  }

  // If an estimate_id is provided, verify it belongs to the company
  if (data.estimate_id) {
    const estimate = await prisma.estimate.findFirst({
      where: { id: data.estimate_id, companyId },
    });

    if (!estimate) {
      throw new NotFoundError('Estimate', data.estimate_id);
    }
  }

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
          err.code === 'P2025'
        ) {
          throw new NotFoundError('Company', companyId);
        }
        throw err;
      });

    const invoiceNumber = `${company.invoicePrefix || 'INV'}-${company.nextInvoiceNumber - 1}`;

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
        action: 'INVOICE_CREATED',
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
 * Each estimate line becomes an invoice line; since invoice lines carry no
 * markup or per-line tax, the marked-up unit price is folded into unitCost and
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

  const estimate = await prisma.estimate.findFirst({
    where: { id: estimateId, companyId },
    include: {
      lineItems: { orderBy: { sortOrder: 'asc' } },
      project: { select: { id: true, clientId: true } },
    },
  });

  if (!estimate) {
    throw new NotFoundError('Estimate', estimateId);
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

  const invoice = await prisma.$transaction(async (tx) => {
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
          err.code === 'P2025'
        ) {
          throw new NotFoundError('Company', companyId);
        }
        throw err;
      });

    const invoiceNumber = `${company.invoicePrefix || 'INV'}-${company.nextInvoiceNumber - 1}`;

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
          sortOrder: li.sortOrder,
        },
      });
    }

    await tx.activityLogEntry.create({
      data: {
        projectId: estimate.projectId,
        userId,
        action: 'INVOICE_CREATED',
        description: `Invoice ${invoiceNumber} created from estimate ${estimate.estimateNumber}`,
      },
    });

    return created;
  });

  return invoice;
}

export async function update(id: string, companyId: string, data: UpdateInvoiceInput) {
  const existing = await prisma.invoice.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError('Invoice', id);
  }

  const updateData: any = {};

  if (data.status !== undefined) {
    updateData.status = data.status.toUpperCase().replace(' ', '_') as InvoiceStatus;
  }
  if (data.notes !== undefined) {
    updateData.notes = data.notes;
  }
  if (data.proposal_id !== undefined) {
    updateData.proposalId = data.proposal_id;
  }
  if (data.issued_date !== undefined) {
    updateData.issuedDate = data.issued_date ? new Date(data.issued_date) : null;
  }
  if (data.due_date !== undefined) {
    updateData.dueDate = data.due_date ? new Date(data.due_date) : null;
  }
  if (data.discount_amount !== undefined) {
    updateData.discountAmount = data.discount_amount;
  }
  if (data.payment_instructions !== undefined) {
    updateData.paymentInstructions = data.payment_instructions;
  }
  if (data.currency_code !== undefined) {
    updateData.currencyCode = data.currency_code;
  }
  if (data.amount_paid !== undefined) {
    updateData.amountPaid = data.amount_paid;
  }

  // Handle status transitions for payment
  if (data.status === 'paid') {
    updateData.paidAt = new Date();
  }

  const invoice = await prisma.invoice.update({
    where: { id },
    data: updateData,
  });

  // Changing the discount or recorded payment alters the derived totals
  // (totalAmount / amountDue). Recompute them from the canonical formula so
  // they stay consistent with the line-item recalc path — otherwise the
  // total would still reflect the pre-discount amount.
  if (data.discount_amount !== undefined || data.amount_paid !== undefined) {
    return recalculateInvoiceTotals(id);
  }

  return invoice;
}

export async function send(invoiceId: string, companyId: string, userId: string) {
  const invoice = await prisma.invoice.findFirst({
    where: { id: invoiceId, companyId },
  });

  if (!invoice) {
    throw new NotFoundError('Invoice', invoiceId);
  }

  const updated = await prisma.invoice.update({
    where: { id: invoiceId },
    data: {
      status: 'SENT',
      sentAt: new Date(),
    },
  });

  // Log activity
  await prisma.activityLogEntry.create({
    data: {
      projectId: invoice.projectId,
      userId,
      action: 'INVOICE_SENT',
      description: `Invoice ${invoice.invoiceNumber} sent`,
    },
  });

  // Send email to client
  const client = await prisma.client.findUnique({ where: { id: invoice.clientId } });
  const company = await prisma.company.findUnique({ where: { id: companyId } });
  if (client?.email && company) {
    const { sendInvoiceEmail } = await import('../../lib/email');
    const amount = `$${Number(updated.totalAmount).toLocaleString('en-US', { minimumFractionDigits: 2 })}`;
    await sendInvoiceEmail(client.email, '', company.name, amount);
  }

  return updated;
}

export async function remove(id: string, companyId: string) {
  const existing = await prisma.invoice.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError('Invoice', id);
  }

  await prisma.invoice.delete({ where: { id } });
}
