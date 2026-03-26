import { z } from 'zod';

export const updateMaterialSchema = z.object({
  is_selected: z.boolean({ required_error: 'is_selected is required' }),
});

export type UpdateMaterialInput = z.infer<typeof updateMaterialSchema>;
