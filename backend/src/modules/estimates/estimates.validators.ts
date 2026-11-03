import { z } from 'zod';
const money = z.number().finite().min(0).max(9_999_999_999.99);

export const createEstimateSchema = z.object({
  project_id: z.string().min(1, 'project_id is required'),
  title: z.string().max(500).nullable().optional(),
  pricing_profile_id: z.string().nullable().optional(),
  notes: z.string().max(10000).nullable().optional(),
  assumptions: z.string().max(50000).nullable().optional(),
  exclusions: z.string().max(50000).nullable().optional(),
  contingency_amount: money.nullable().optional(),
  valid_until: z.string().datetime().nullable().optional(),
});

export const updateEstimateSchema = z.object({
  status: z.enum(['draft', 'sent', 'approved', 'declined', 'expired']).optional(),
  title: z.string().max(500).nullable().optional(),
  pricing_profile_id: z.string().nullable().optional(),
  notes: z.string().max(10000).nullable().optional(),
  assumptions: z.string().max(50000).nullable().optional(),
  exclusions: z.string().max(50000).nullable().optional(),
  contingency_amount: money.nullable().optional(),
  valid_until: z.string().datetime().nullable().optional(),
  subtotal_materials: money.optional(),
  subtotal_labor: money.optional(),
  subtotal_other: money.optional(),
  tax_amount: money.optional(),
  discount_amount: money.optional(),
  total_amount: money.optional(),
});

export const generateEstimateSchema = z.object({
  project_id: z.string().min(1, 'project_id is required'),
});

export const reviseEstimateSchema = z.object({ request_id: z.string().uuid() }).strict();

export type CreateEstimateInput = z.infer<typeof createEstimateSchema>;
export type UpdateEstimateInput = z.infer<typeof updateEstimateSchema>;
export type GenerateEstimateInput = z.infer<typeof generateEstimateSchema>;
