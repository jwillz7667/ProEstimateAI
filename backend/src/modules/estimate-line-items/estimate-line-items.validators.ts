import { z } from 'zod';

export const createEstimateLineItemSchema = z.object({
  category: z.enum(['materials', 'labor', 'other']),
  name: z.string().min(1, 'name is required').max(500),
  description: z.string().max(5000).nullable().optional(),
  quantity: z.number().finite().positive('quantity must be positive').max(99_999_999.99),
  unit: z.string().min(1, 'unit is required').max(50),
  unit_cost: z.number().finite().min(0, 'unit_cost must be non-negative').max(9_999_999_999.99),
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
  quantity: z.number().finite().positive().max(99_999_999.99).optional(),
  unit: z.string().min(1).max(50).optional(),
  unit_cost: z.number().finite().min(0).max(9_999_999_999.99).optional(),
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

export const reviewEstimatePriceSchema = z.object({
  expected_name: z.string().min(1).max(500),
  expected_unit: z.string().min(1).max(50),
  expected_unit_cost: z.number().finite().min(0).max(9_999_999_999.99),
  expected_quantity: z.number().finite().positive().max(99_999_999.99),
  price_confirmed: z.literal(true),
  source_label: z.string().trim().min(1).max(255),
  source_url: z.string().url().max(2000).refine((value) => {
    const url = new URL(value);
    return ["http:", "https:"].includes(url.protocol) && !url.username && !url.password;
  }, "Use a public HTTP or HTTPS supplier link without embedded credentials").nullable().optional(),
  quantity_confirmed: z.boolean().default(false),
  quantity_basis: z.string().trim().max(500).nullable().optional(),
}).strict().superRefine((value, ctx) => {
  if (value.quantity_confirmed && !value.quantity_basis) ctx.addIssue({ code: "custom", message: "Describe how the quantity was checked", path: ["quantity_basis"] });
});

export type ReviewEstimatePriceInput = z.infer<typeof reviewEstimatePriceSchema>;

export type CreateEstimateLineItemInput = z.infer<typeof createEstimateLineItemSchema>;
export type UpdateEstimateLineItemInput = z.infer<typeof updateEstimateLineItemSchema>;
export type BatchCreateEstimateLineItemsInput = z.infer<typeof batchCreateEstimateLineItemsSchema>;
