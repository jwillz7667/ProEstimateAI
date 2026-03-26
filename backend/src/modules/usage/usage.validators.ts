import { z } from 'zod';

export const consumeUsageSchema = z.object({
  metric_code: z.enum(['AI_GENERATION', 'QUOTE_EXPORT'], {
    required_error: 'Metric code is required',
    invalid_type_error: 'Metric code must be AI_GENERATION or QUOTE_EXPORT',
  }),
});

export type ConsumeUsageInput = z.infer<typeof consumeUsageSchema>;
