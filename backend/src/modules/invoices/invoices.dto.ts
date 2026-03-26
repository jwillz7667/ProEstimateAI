import { Invoice } from '@prisma/client';

export interface InvoiceDto {
  id: string;
  estimate_id: string | null;
  project_id: string;
  company_id: string;
  client_id: string;
  invoice_number: string;
  status: string;
  subtotal: number;
  tax_amount: number;
  total_amount: number;
  amount_paid: number;
  amount_due: number;
  due_date: string | null;
  paid_at: string | null;
  sent_at: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export function toInvoiceDto(invoice: Invoice): InvoiceDto {
  return {
    id: invoice.id,
    estimate_id: invoice.estimateId,
    project_id: invoice.projectId,
    company_id: invoice.companyId,
    client_id: invoice.clientId,
    invoice_number: invoice.invoiceNumber,
    status: invoice.status.toLowerCase(),
    subtotal: Number(invoice.subtotal),
    tax_amount: Number(invoice.taxAmount),
    total_amount: Number(invoice.totalAmount),
    amount_paid: Number(invoice.amountPaid),
    amount_due: Number(invoice.amountDue),
    due_date: invoice.dueDate ? invoice.dueDate.toISOString() : null,
    paid_at: invoice.paidAt ? invoice.paidAt.toISOString() : null,
    sent_at: invoice.sentAt ? invoice.sentAt.toISOString() : null,
    notes: invoice.notes,
    created_at: invoice.createdAt.toISOString(),
    updated_at: invoice.updatedAt.toISOString(),
  };
}
