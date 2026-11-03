import { z } from 'zod';

const requestId = z.string().uuid();
export const librarySearchSchema = z.object({
  q: z.string().trim().max(200).optional(),
  cursor: z.string().max(100).optional(),
  page_size: z.coerce.number().int().min(1).max(100).default(25),
});
export const saveTemplateSchema = z.object({
  request_id: requestId, estimate_id: z.string().min(1),
  name: z.string().trim().min(1).max(200), description: z.string().trim().max(2000).nullable().optional(),
}).strict();
export const instantiateTemplateSchema = z.object({
  request_id: requestId, project_id: z.string().min(1), title: z.string().trim().min(1).max(500).optional(),
}).strict();
export const duplicateEstimateSchema = z.object({
  request_id: requestId, project_id: z.string().min(1).optional(), title: z.string().trim().min(1).max(500).optional(),
}).strict();
export const savedItemFieldsSchema = z.object({
  category: z.enum(['materials', 'labor', 'other']),
  name: z.string().trim().min(1).max(500), description: z.string().max(5000).nullable().optional(),
  quantity: z.number().finite().min(0.01).max(99999999.99), unit: z.string().trim().min(1).max(50),
  unit_cost: z.number().finite().min(0).max(9999999999.99),
  markup_percent: z.number().finite().min(0).max(1000).default(0),
  tax_rate: z.number().finite().min(0).max(1).default(0),
  item_type: z.enum(['per_unit', 'flat_rate', 'hourly']).nullable().optional(),
});
export const saveItemSchema = savedItemFieldsSchema.extend({ request_id: requestId }).strict();
export const applyItemSchema = z.object({
  request_id: requestId, estimate_id: z.string().min(1),
}).strict();
export type SavedItemInput = z.infer<typeof saveItemSchema>;
export type SaveTemplateInput = z.infer<typeof saveTemplateSchema>;
