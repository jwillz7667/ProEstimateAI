import { z } from 'zod';

export const updateMaterialSchema = z.object({
  is_selected: z.boolean({
    error: (issue) => issue.input === undefined ? 'is_selected is required' : undefined,
  }),
});

export type UpdateMaterialInput = z.infer<typeof updateMaterialSchema>;
