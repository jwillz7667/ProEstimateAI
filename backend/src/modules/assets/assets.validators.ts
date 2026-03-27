import { z } from 'zod';

export const createAssetSchema = z.object({
  url: z
    .string()
    .trim()
    .min(1, 'URL is required'),
  thumbnail_url: z
    .string()
    .trim()
    .max(2048, 'Thumbnail URL must not exceed 2048 characters')
    .optional(),
  asset_type: z
    .enum(['original', 'ai_generated', 'document'], {
      errorMap: () => ({ message: 'asset_type must be one of: original, ai_generated, document' }),
    })
    .optional(),
  sort_order: z
    .number()
    .int('sort_order must be an integer')
    .min(0, 'sort_order must be non-negative')
    .optional(),
});

export type CreateAssetInput = z.infer<typeof createAssetSchema>;
