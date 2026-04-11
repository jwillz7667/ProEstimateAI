import { EstimateLineItem } from '@prisma/client';

export interface EstimateLineItemDto {
  id: string;
  estimate_id: string;
  parent_line_item_id: string | null;
  source_material_suggestion_id: string | null;
  category: string;
  item_type: string | null;
  name: string;
  description: string | null;
  quantity: number;
  unit: string;
  unit_cost: number;
  markup_percent: number;
  tax_rate: number;
  line_total: number;
  sort_order: number;
}

export function toEstimateLineItemDto(item: EstimateLineItem): EstimateLineItemDto {
  return {
    id: item.id,
    estimate_id: item.estimateId,
    parent_line_item_id: item.parentLineItemId ?? null,
    source_material_suggestion_id: item.sourceMaterialSuggestionId ?? null,
    category: item.category.toLowerCase(),
    item_type: item.itemType ?? null,
    name: item.name,
    description: item.description,
    quantity: Number(item.quantity),
    unit: item.unit,
    unit_cost: Number(item.unitCost),
    markup_percent: Number(item.markupPercent),
    tax_rate: Number(item.taxRate),
    line_total: Number(item.lineTotal),
    sort_order: item.sortOrder,
  };
}
