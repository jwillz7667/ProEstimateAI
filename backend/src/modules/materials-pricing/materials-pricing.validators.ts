import { z } from 'zod';

export const searchMaterialsSchema = z.object({
  query: z.string().min(1).max(500),
  zip_code: z.string().max(10).optional(),
  store_id: z.string().max(20).optional(),
  sort: z.enum(['top_sellers', 'price_low_to_high', 'price_high_to_low', 'top_rated', 'best_match']).optional(),
  page: z.coerce.number().int().min(1).max(100).optional(),
  max_results: z.coerce.number().int().min(1).max(48).optional(),
});

export type SearchMaterialsInput = z.infer<typeof searchMaterialsSchema>;

export const projectMaterialsSchema = z.object({
  project_type: z.enum([
    'kitchen', 'bathroom', 'flooring', 'roofing', 'painting',
    'siding', 'room_remodel', 'exterior', 'custom',
  ]),
  zip_code: z.string().max(10).optional(),
});

export type ProjectMaterialsInput = z.infer<typeof projectMaterialsSchema>;
