import { z } from 'zod';

export const createGenerationSchema = z.object({
  prompt: z
    .string()
    .trim()
    .min(1, 'Prompt is required')
    .max(2000, 'Prompt must not exceed 2000 characters'),
  materials: z
    .array(
      z.object({
        name: z.string(),
        category: z.string().optional(),
        quantity: z.number().optional(),
        unit: z.string().optional(),
      })
    )
    .optional(),
  // Per-request override of the project's image switch. When false the
  // pipeline skips image generation and produces a text-only estimate.
  // Absent → fall back to the project's aiPreviewEnabled flag.
  generate_preview: z.boolean().optional(),
});

export type CreateGenerationInput = z.infer<typeof createGenerationSchema>;
