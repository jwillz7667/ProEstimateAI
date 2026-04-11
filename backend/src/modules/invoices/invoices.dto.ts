import { Invoice } from '@prisma/client';

export interface InvoiceDto {
  id: string;
  estimate_id: string | null;
  proposal_id: string | null;
  project_id: string;
  company_id: string;
  client_id: string;
  invoice_number: string;
  status: string;
  subtotal: number;
  tax_amount: number;
  discount_amount: number;
  total_amount: number;
  amount_paid: number;
  amount_due: number;
  issued_date: string | null;
  due_date: string | null;
  paid_at: string | null;
  sent_at: string | null;
  notes: string | null;
  payment_instructions: string | null;
  currency_code: string | null;
  created_at: string;
  updated_at: string;
}

export function toInvoiceDto(invoice: Invoice): InvoiceDto {
  return {
    id: invoice.id,
    estimate_id: invoice.estimateId,
    proposal_id: invoice.proposalId ?? null,
    project_id: invoice.projectId,
    company_id: invoice.companyId,
    client_id: invoice.clientId,
    invoice_number: invoice.invoiceNumber,
    status: invoice.status.toLowerCase(),
    subtotal: Number(invoice.subtotal),
    tax_amount: Number(invoice.taxAmount),
    discount_amount: Number(invoice.discountAmount),
    total_amount: Number(invoice.totalAmount),
    amount_paid: Number(invoice.amountPaid),
    amount_due: Number(invoice.amountDue),
    issued_date: invoice.issuedDate?.toISOString() ?? null,
    due_date: invoice.dueDate ? invoice.dueDate.toISOString() : null,
    paid_at: invoice.paidAt ? invoice.paidAt.toISOString() : null,
    sent_at: invoice.sentAt ? invoice.sentAt.toISOString() : null,
    notes: invoice.notes,
    payment_instructions: invoice.paymentInstructions ?? null,
    currency_code: invoice.currencyCode ?? null,
    created_at: invoice.createdAt.toISOString(),
    updated_at: invoice.updatedAt.toISOString(),
  };
}
