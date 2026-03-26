import { z } from 'zod';

export const createPricingProfileSchema = z.object({
  name: z.string().min(1).max(255),
  default_markup_percent: z.number().min(0).max(999).optional(),
  contingency_percent: z.number().min(0).max(100).optional(),
  waste_factor: z.number().min(0).max(100).optional(),
  is_default: z.boolean().optional(),
});

export const updatePricingProfileSchema = z.object({
  name: z.string().min(1).max(255).optional(),
  default_markup_percent: z.number().min(0).max(999).optional(),
  contingency_percent: z.number().min(0).max(100).optional(),
  waste_factor: z.number().min(0).max(100).optional(),
  is_default: z.boolean().optional(),
});

export type CreatePricingProfileInput = z.infer<typeof createPricingProfileSchema>;
export type UpdatePricingProfileInput = z.infer<typeof updatePricingProfileSchema>;
