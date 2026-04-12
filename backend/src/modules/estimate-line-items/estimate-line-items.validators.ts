import { z } from 'zod';

export const createEstimateLineItemSchema = z.object({
  category: z.enum(['materials', 'labor', 'other']),
  name: z.string().min(1, 'name is required').max(500),
  description: z.string().max(5000).nullable().optional(),
  quantity: z.number().positive('quantity must be positive'),
  unit: z.string().min(1, 'unit is required').max(50),
  unit_cost: z.number().min(0, 'unit_cost must be non-negative'),
  markup_percent: z.number().min(0).max(1000).optional().default(0),
  tax_rate: z.number().min(0).max(1).optional().default(0),
  sort_order: z.number().int().min(0).optional().default(0),
  parent_line_item_id: z.string().nullable().optional(),
  source_material_suggestion_id: z.string().nullable().optional(),
  item_type: z.enum(['per_unit', 'flat_rate', 'hourly']).nullable().optional(),
});

export const updateEstimateLineItemSchema = z.object({
  category: z.enum(['materials', 'labor', 'other']).optional(),
  name: z.string().min(1).max(500).optional(),
  description: z.string().max(5000).nullable().optional(),
  quantity: z.number().positive().optional(),
  unit: z.string().min(1).max(50).optional(),
  unit_cost: z.number().min(0).optional(),
  markup_percent: z.number().min(0).max(1000).optional(),
  tax_rate: z.number().min(0).max(1).optional(),
  sort_order: z.number().int().min(0).optional(),
  parent_line_item_id: z.string().nullable().optional(),
  source_material_suggestion_id: z.string().nullable().optional(),
  item_type: z.enum(['per_unit', 'flat_rate', 'hourly']).nullable().optional(),
});

export const batchCreateEstimateLineItemsSchema = z.object({
  items: z.array(createEstimateLineItemSchema).min(1, 'At least one line item is required').max(200, 'Maximum 200 line items per batch'),
});

export type CreateEstimateLineItemInput = z.infer<typeof createEstimateLineItemSchema>;
export type UpdateEstimateLineItemInput = z.infer<typeof updateEstimateLineItemSchema>;
export type BatchCreateEstimateLineItemsInput = z.infer<typeof batchCreateEstimateLineItemsSchema>;
