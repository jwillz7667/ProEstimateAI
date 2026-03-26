import { z } from 'zod';

export const createProposalSchema = z.object({
  estimate_id: z.string().min(1, 'estimate_id is required'),
  project_id: z.string().min(1, 'project_id is required'),
  hero_image_url: z.string().url().max(2048).nullable().optional(),
  terms_and_conditions: z.string().max(50000).nullable().optional(),
  client_message: z.string().max(10000).nullable().optional(),
  expires_at: z.string().datetime().nullable().optional(),
});

export const sendProposalSchema = z.object({
  client_message: z.string().max(10000).nullable().optional(),
});

export type CreateProposalInput = z.infer<typeof createProposalSchema>;
export type SendProposalInput = z.infer<typeof sendProposalSchema>;
