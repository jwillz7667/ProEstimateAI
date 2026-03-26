import { z } from 'zod';

const projectTypeEnum = z.enum([
  'kitchen', 'bathroom', 'flooring', 'roofing', 'painting',
  'siding', 'room_remodel', 'exterior', 'custom',
]);

const projectStatusEnum = z.enum([
  'draft', 'photos_uploaded', 'generating', 'generation_complete',
  'estimate_created', 'proposal_sent', 'approved', 'declined',
  'invoiced', 'completed', 'archived',
]);

const qualityTierEnum = z.enum(['standard', 'premium', 'luxury']);

export const createProjectSchema = z.object({
  title: z.string().min(1).max(255),
  client_id: z.string().cuid().nullable().optional(),
  description: z.string().max(5000).nullable().optional(),
  project_type: projectTypeEnum.optional(),
  status: projectStatusEnum.optional(),
  budget_min: z.number().min(0).nullable().optional(),
  budget_max: z.number().min(0).nullable().optional(),
  quality_tier: qualityTierEnum.optional(),
  square_footage: z.number().min(0).nullable().optional(),
  dimensions: z.string().max(500).nullable().optional(),
  language: z.string().max(10).nullable().optional(),
});

export const updateProjectSchema = z.object({
  title: z.string().min(1).max(255).optional(),
  client_id: z.string().cuid().nullable().optional(),
  description: z.string().max(5000).nullable().optional(),
  project_type: projectTypeEnum.optional(),
  status: projectStatusEnum.optional(),
  budget_min: z.number().min(0).nullable().optional(),
  budget_max: z.number().min(0).nullable().optional(),
  quality_tier: qualityTierEnum.optional(),
  square_footage: z.number().min(0).nullable().optional(),
  dimensions: z.string().max(500).nullable().optional(),
  language: z.string().max(10).nullable().optional(),
});

export type CreateProjectInput = z.infer<typeof createProjectSchema>;
export type UpdateProjectInput = z.infer<typeof updateProjectSchema>;
