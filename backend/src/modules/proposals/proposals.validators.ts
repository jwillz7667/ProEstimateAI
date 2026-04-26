import { z } from 'zod';

export const createProposalSchema = z.object({
  estimate_id: z.string().min(1, 'estimate_id is required'),
  // project_id is optional — when omitted the service derives it from the estimate.
  project_id: z.string().min(1).optional(),
  hero_image_url: z.string().url().max(2048).nullable().optional(),
  terms_and_conditions: z.string().max(50000).nullable().optional(),
  client_message: z.string().max(10000).nullable().optional(),
  expires_at: z.string().datetime().nullable().optional(),
});

export const sendProposalSchema = z.object({
  client_message: z.string().max(10000).nullable().optional(),
});

export const respondToProposalSchema = z.object({
  decision: z.enum(['approved', 'declined']),
  message: z.string().max(10000).nullable().optional(),
});

export const updateProposalSchema = z.object({
  title: z.string().max(500).nullable().optional(),
  intro_text: z.string().max(50000).nullable().optional(),
  scope_of_work: z.string().max(50000).nullable().optional(),
  timeline_text: z.string().max(50000).nullable().optional(),
  terms_and_conditions: z.string().max(50000).nullable().optional(),
  footer_text: z.string().max(50000).nullable().optional(),
  client_message: z.string().max(10000).nullable().optional(),
  hero_image_url: z.string().url().max(2048).nullable().optional(),
  expires_at: z.string().datetime().nullable().optional(),
});

export type CreateProposalInput = z.infer<typeof createProposalSchema>;
export type SendProposalInput = z.infer<typeof sendProposalSchema>;
export type RespondToProposalInput = z.infer<typeof respondToProposalSchema>;
export type UpdateProposalInput = z.infer<typeof updateProposalSchema>;
