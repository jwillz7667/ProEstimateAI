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
  proposal_prefix: z.string().max(10).nullable().optional(),
  default_language: z.string().max(10).nullable().optional(),
  timezone: z.string().max(100).nullable().optional(),
  website_url: z.string().url().max(2048).nullable().optional(),
  tax_label: z.string().max(50).nullable().optional(),
});

export type UpdateCompanyInput = z.infer<typeof updateCompanySchema>;

// Max encoded base64 length ≈ 2.85 MB (roughly 2 MB decoded). Keeps the
// Company row + Postgres toast overhead well inside the 10mb JSON body limit.
export const uploadLogoSchema = z.object({
  image_data: z.string().min(1).max(3_000_000),
  mime_type: z.enum(['image/png', 'image/jpeg', 'image/webp']),
});

export type UploadLogoInput = z.infer<typeof uploadLogoSchema>;
