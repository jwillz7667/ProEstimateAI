import { z } from 'zod';

export const createGenerationSchema = z.object({
  prompt: z
    .string()
    .trim()
    .min(1, 'Prompt is required')
    .max(2000, 'Prompt must not exceed 2000 characters'),
});

export type CreateGenerationInput = z.infer<typeof createGenerationSchema>;
