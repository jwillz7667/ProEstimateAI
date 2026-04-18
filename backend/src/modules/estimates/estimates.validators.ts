import { z } from 'zod';

export const createEstimateSchema = z.object({
  project_id: z.string().min(1, 'project_id is required'),
  title: z.string().max(500).nullable().optional(),
  pricing_profile_id: z.string().nullable().optional(),
  notes: z.string().max(10000).nullable().optional(),
  assumptions: z.string().max(50000).nullable().optional(),
  exclusions: z.string().max(50000).nullable().optional(),
  contingency_amount: z.number().min(0).nullable().optional(),
  valid_until: z.string().datetime().nullable().optional(),
});

export const updateEstimateSchema = z.object({
  status: z.enum(['draft', 'sent', 'approved', 'declined', 'expired']).optional(),
  title: z.string().max(500).nullable().optional(),
  pricing_profile_id: z.string().nullable().optional(),
  notes: z.string().max(10000).nullable().optional(),
  assumptions: z.string().max(50000).nullable().optional(),
  exclusions: z.string().max(50000).nullable().optional(),
  contingency_amount: z.number().min(0).nullable().optional(),
  valid_until: z.string().datetime().nullable().optional(),
  subtotal_materials: z.number().min(0).optional(),
  subtotal_labor: z.number().min(0).optional(),
  subtotal_other: z.number().min(0).optional(),
  tax_amount: z.number().min(0).optional(),
  discount_amount: z.number().min(0).optional(),
  total_amount: z.number().min(0).optional(),
});

export const generateEstimateSchema = z.object({
  project_id: z.string().min(1, 'project_id is required'),
});

export type CreateEstimateInput = z.infer<typeof createEstimateSchema>;
export type UpdateEstimateInput = z.infer<typeof updateEstimateSchema>;
export type GenerateEstimateInput = z.infer<typeof generateEstimateSchema>;
