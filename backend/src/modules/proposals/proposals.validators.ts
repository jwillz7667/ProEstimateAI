import { z } from 'zod';

export const createProposalSchema = z.object({
  estimate_id: z.string().min(1, 'estimate_id is required'),
  // project_id is optional — when omitted the service derives it from the estimate.
  project_id: z.string().min(1).optional(),
  title: z.string().max(500).nullable().optional(),
  intro_text: z.string().max(50000).nullable().optional(),
  scope_of_work: z.string().max(50000).nullable().optional(),
  timeline_text: z.string().max(50000).nullable().optional(),
  footer_text: z.string().max(50000).nullable().optional(),
  hero_image_url: z.string().url().max(2048).nullable().optional(),
  terms_and_conditions: z.string().max(50000).nullable().optional(),
  client_message: z.string().max(10000).nullable().optional(),
  expires_at: z.string().datetime().nullable().optional(),
});

export const sendProposalSchema = z.object({
  client_message: z.string().max(10000).nullable().optional(),
  expected_estimate_updated_at: z.string().datetime().optional(),
  draft_review_token: z.string().regex(/^[a-f0-9]{64}$/).optional(),
});

export const respondToProposalSchema = z.object({
  decision: z.enum(['approved', 'declined', 'changes_requested']),
  message: z.string().max(10000).nullable().optional(),
  signer_name: z.string().trim().min(1).max(200).optional(),
  acceptance_consent: z.boolean().optional(),
  consent_version: z.literal('quote-acceptance-v1').optional(),
  document_hash: z.string().regex(/^[a-f0-9]{64}$/).optional(),
}).superRefine((data, ctx) => {
  if (data.decision === 'changes_requested' && !data.message?.trim()) {
    ctx.addIssue({ code: 'custom', path: ['message'], message: 'Describe the changes you would like.' });
  }
  const signing = data.signer_name !== undefined || data.acceptance_consent !== undefined || data.consent_version !== undefined;
  if (signing && (data.decision !== 'approved' || !data.signer_name || data.acceptance_consent !== true || !data.document_hash || data.consent_version !== 'quote-acceptance-v1')) {
    ctx.addIssue({ code: 'custom', path: ['acceptance_consent'], message: 'Approval requires your name, explicit consent and the proposal version you reviewed.' });
  }
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
