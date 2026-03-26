import { MaterialSuggestion } from '@prisma/client';

export interface MaterialDto {
  id: string;
  generation_id: string;
  project_id: string;
  name: string;
  category: string;
  estimated_cost: number;
  unit: string;
  quantity: number;
  supplier_name: string | null;
  supplier_url: string | null;
  is_selected: boolean;
  sort_order: number;
}

export function toMaterialDto(material: MaterialSuggestion): MaterialDto {
  return {
    id: material.id,
    generation_id: material.generationId,
    project_id: material.projectId,
    name: material.name,
    category: material.category,
    estimated_cost: Number(material.estimatedCost),
    unit: material.unit,
    quantity: Number(material.quantity),
    supplier_name: material.supplierName,
    supplier_url: material.supplierUrl,
    is_selected: material.isSelected,
    sort_order: material.sortOrder,
  };
}
