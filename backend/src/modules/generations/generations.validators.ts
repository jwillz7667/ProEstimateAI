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
});

export type CreateGenerationInput = z.infer<typeof createGenerationSchema>;
