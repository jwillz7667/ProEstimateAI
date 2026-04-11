import { z } from 'zod';

export const createInvoiceSchema = z.object({
  project_id: z.string().min(1, 'project_id is required'),
  client_id: z.string().min(1, 'client_id is required'),
  estimate_id: z.string().min(1).nullable().optional(),
  proposal_id: z.string().nullable().optional(),
  notes: z.string().max(10000).nullable().optional(),
  issued_date: z.string().datetime().nullable().optional(),
  due_date: z.string().datetime().nullable().optional(),
  discount_amount: z.number().min(0).nullable().optional(),
  payment_instructions: z.string().max(50000).nullable().optional(),
  currency_code: z.string().max(10).nullable().optional(),
});

export const updateInvoiceSchema = z.object({
  status: z.enum(['draft', 'sent', 'viewed', 'partially_paid', 'paid', 'overdue', 'void']).optional(),
  notes: z.string().max(10000).nullable().optional(),
  proposal_id: z.string().nullable().optional(),
  issued_date: z.string().datetime().nullable().optional(),
  due_date: z.string().datetime().nullable().optional(),
  discount_amount: z.number().min(0).nullable().optional(),
  payment_instructions: z.string().max(50000).nullable().optional(),
  currency_code: z.string().max(10).nullable().optional(),
  amount_paid: z.number().min(0).optional(),
});

export const sendInvoiceSchema = z.object({}).strict();

export type CreateInvoiceInput = z.infer<typeof createInvoiceSchema>;
export type UpdateInvoiceInput = z.infer<typeof updateInvoiceSchema>;
