import { z } from 'zod';

export const updateCompanySchema = z.object({
  name: z.string().min(1).max(255).optional(),
  phone: z.string().max(50).nullable().optional(),
  email: z.string().email().max(255).nullable().optional(),
  address: z.string().max(500).nullable().optional(),
  city: z.string().max(100).nullable().optional(),
  state: z.string().max(100).nullable().optional(),
  zip: z.string().max(20).nullable().optional(),
  logo_url: z.string().url().max(2048).nullable().optional(),
  primary_color: z.string().max(20).nullable().optional(),
  secondary_color: z.string().max(20).nullable().optional(),
  default_tax_rate: z.number().min(0).max(1).nullable().optional(),
  default_markup_percent: z.number().min(0).max(999).nullable().optional(),
  estimate_prefix: z.string().max(10).nullable().optional(),
  invoice_prefix: z.string().max(10).nullable().optional(),
});

export type UpdateCompanyInput = z.infer<typeof updateCompanySchema>;
