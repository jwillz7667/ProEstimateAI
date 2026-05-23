import { z } from 'zod';

/// Cap PDF payload at ~7 MB raw, which leaves headroom under the
/// 10 MB express.json limit once base64 inflates the wire size by ~33%.
const MAX_BASE64_LENGTH = 7 * 1024 * 1024;

export const createEstimateExportSchema = z.object({
  file_name: z
    .string()
    .trim()
    .min(1, 'file_name is required')
    .max(255, 'file_name must not exceed 255 characters'),
  content_type: z
    .string()
    .trim()
    .min(1, 'content_type is required')
    .max(127, 'content_type must not exceed 127 characters')
    .optional(),
  pdf_data: z
    .string()
    .min(1, 'pdf_data is required')
    .max(MAX_BASE64_LENGTH, 'pdf_data exceeds the 7 MB upload limit'),
});

export type CreateEstimateExportInput = z.infer<typeof createEstimateExportSchema>;
