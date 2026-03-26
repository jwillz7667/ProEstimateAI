import { Estimate } from '@prisma/client';

export interface EstimateDto {
  id: string;
  project_id: string;
  company_id: string;
  estimate_number: string;
  version: number;
  status: string;
  subtotal_materials: number;
  subtotal_labor: number;
  subtotal_other: number;
  tax_amount: number;
  discount_amount: number;
  total_amount: number;
  notes: string | null;
  valid_until: string | null;
  created_at: string;
  updated_at: string;
}

export function toEstimateDto(estimate: Estimate): EstimateDto {
  return {
    id: estimate.id,
    project_id: estimate.projectId,
    company_id: estimate.companyId,
    estimate_number: estimate.estimateNumber,
    version: estimate.version,
    status: estimate.status.toLowerCase(),
    subtotal_materials: Number(estimate.subtotalMaterials),
    subtotal_labor: Number(estimate.subtotalLabor),
    subtotal_other: Number(estimate.subtotalOther),
    tax_amount: Number(estimate.taxAmount),
    discount_amount: Number(estimate.discountAmount),
    total_amount: Number(estimate.totalAmount),
    notes: estimate.notes,
    valid_until: estimate.validUntil ? estimate.validUntil.toISOString() : null,
    created_at: estimate.createdAt.toISOString(),
    updated_at: estimate.updatedAt.toISOString(),
  };
}
