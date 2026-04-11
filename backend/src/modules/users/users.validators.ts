import { z } from 'zod';

export const updateUserSchema = z.object({
  full_name: z.string().min(2).max(100).optional(),
  phone: z.string().max(50).nullable().optional(),
  avatar_url: z.string().url().max(2048).nullable().optional(),
});

export type UpdateUserInput = z.infer<typeof updateUserSchema>;
