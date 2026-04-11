import { prisma } from '../../config/database';
import { NotFoundError, PaywallError } from '../../lib/errors';
import { isAdminUser } from '../../lib/admin';
import { PaginationParams, paginateResults, buildCursorWhere } from '../../lib/pagination';
import { CreateInvoiceInput, UpdateInvoiceInput } from './invoices.validators';
import { InvoiceStatus } from '@prisma/client';

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
    const company = await tx.company.findUnique({
      where: { id: companyId },
      select: { invoicePrefix: true, nextInvoiceNumber: true },
    });

    if (!company) {
      throw new NotFoundError('Company', companyId);
    }

    const invoiceNumber = `${company.invoicePrefix || 'INV'}-${company.nextInvoiceNumber}`;

    // Increment the company's next invoice number
    await tx.company.update({
      where: { id: companyId },
      data: { nextInvoiceNumber: company.nextInvoiceNumber + 1 },
    });

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
    // Recalculate amountDue = totalAmount - amountPaid
    updateData.amountDue = Number(existing.totalAmount) - data.amount_paid;
  }

  // Handle status transitions for payment
  if (data.status === 'paid') {
    updateData.paidAt = new Date();
  }

  const invoice = await prisma.invoice.update({
    where: { id },
    data: updateData,
  });

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
