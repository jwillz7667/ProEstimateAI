import { z } from 'zod';

export const createInvoiceLineItemSchema = z.object({
  name: z.string().min(1, 'name is required').max(500),
  description: z.string().max(5000).nullable().optional(),
  quantity: z.number().positive('quantity must be positive'),
  unit: z.string().min(1, 'unit is required').max(50),
  unit_cost: z.number().min(0, 'unit_cost must be non-negative'),
  sort_order: z.number().int().min(0).optional().default(0),
});

export const updateInvoiceLineItemSchema = z.object({
  name: z.string().min(1).max(500).optional(),
  description: z.string().max(5000).nullable().optional(),
  quantity: z.number().positive().optional(),
  unit: z.string().min(1).max(50).optional(),
  unit_cost: z.number().min(0).optional(),
  sort_order: z.number().int().min(0).optional(),
});

export type CreateInvoiceLineItemInput = z.infer<typeof createInvoiceLineItemSchema>;
export type UpdateInvoiceLineItemInput = z.infer<typeof updateInvoiceLineItemSchema>;
