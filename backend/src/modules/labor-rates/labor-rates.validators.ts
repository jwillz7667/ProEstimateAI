import { z } from 'zod';

export const createLaborRateSchema = z.object({
  category: z.string().min(1).max(255),
  rate_per_hour: z.number().min(0),
  minimum_hours: z.number().min(0).optional(),
  rate_type: z.enum(['hourly', 'flat', 'unit']).optional(),
  flat_rate: z.number().min(0).nullable().optional(),
  unit_rate: z.number().min(0).nullable().optional(),
  unit: z.string().max(50).nullable().optional(),
});

export const updateLaborRateSchema = z.object({
  category: z.string().min(1).max(255).optional(),
  rate_per_hour: z.number().min(0).optional(),
  minimum_hours: z.number().min(0).optional(),
  rate_type: z.enum(['hourly', 'flat', 'unit']).optional(),
  flat_rate: z.number().min(0).nullable().optional(),
  unit_rate: z.number().min(0).nullable().optional(),
  unit: z.string().max(50).nullable().optional(),
});

export type CreateLaborRateInput = z.infer<typeof createLaborRateSchema>;
export type UpdateLaborRateInput = z.infer<typeof updateLaborRateSchema>;
