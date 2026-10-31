import { z } from 'zod';

export const consumeUsageSchema = z.object({
  metric_code: z.enum(['AI_GENERATION', 'QUOTE_EXPORT'], {
    error: (issue) => {
      if (issue.input === undefined) return 'Metric code is required';
      if (typeof issue.input !== 'string') return 'Metric code must be AI_GENERATION or QUOTE_EXPORT';
      return undefined;
    },
  }),
});

export type ConsumeUsageInput = z.infer<typeof consumeUsageSchema>;
