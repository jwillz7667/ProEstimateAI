import { z } from 'zod';

// Body for POST /v1/admin/generations/reap.
//   dry_run — count only, no writes (always run this first in prod).
//   scope   — which orphan class to sweep:
//             'stuck'     QUEUED/PROCESSING past the threshold
//             'imageless' COMPLETED but no image bytes
//             'all'       both (default)
export const reapGenerationsSchema = z
  .object({
    dry_run: z.boolean().optional().default(false),
    scope: z.enum(['stuck', 'imageless', 'all']).optional().default('all'),
  })
  .strict();

export type ReapGenerationsInput = z.infer<typeof reapGenerationsSchema>;
