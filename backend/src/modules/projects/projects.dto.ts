import { Project } from "@prisma/client";

export interface ProjectDto {
  id: string;
  company_id: string;
  client_id: string | null;
  title: string;
  description: string | null;
  project_type: string;
  status: string;
  budget_min: number | null;
  budget_max: number | null;
  quality_tier: string;
  square_footage: number | null;
  dimensions: string | null;
  language: string | null;
  // Property measurements populated by maps integration. Optional and
  // nullable so older client builds that don't expect them keep working.
  lawn_area_sq_ft: number | null;
  roof_area_sq_ft: number | null;
  property_latitude: number | null;
  property_longitude: number | null;
  // Recurring service contract terms. `is_recurring` flips the iOS
  // estimate UI into per-visit / monthly / annual rollup mode.
  is_recurring: boolean;
  recurrence_frequency: string | null;
  visits_per_month: number | null;
  contract_months: number | null;
  recurrence_start_date: string | null;
  created_at: string;
  updated_at: string;
  // Public preview thumbnail used by the iOS Projects list. Resolves to the most
  // recent COMPLETED AIGeneration's preview image, falling back to the first
  // ORIGINAL asset, or null when neither exists. Always nullable so legacy
  // clients that ignore the field don't break.
  thumbnail_url?: string | null;
}

export function toProjectDto(
  project: Project,
  thumbnailUrl?: string | null,
): ProjectDto {
  return {
    id: project.id,
    company_id: project.companyId,
    client_id: project.clientId,
    title: project.title,
    description: project.description,
    project_type: project.projectType.toLowerCase(),
    status: project.status.toLowerCase(),
    budget_min: project.budgetMin ? Number(project.budgetMin) : null,
    budget_max: project.budgetMax ? Number(project.budgetMax) : null,
    quality_tier: project.qualityTier.toLowerCase(),
    square_footage: project.squareFootage
      ? Number(project.squareFootage)
      : null,
    dimensions: project.dimensions,
    language: project.language,
    lawn_area_sq_ft: project.lawnAreaSqFt ? Number(project.lawnAreaSqFt) : null,
    roof_area_sq_ft: project.roofAreaSqFt ? Number(project.roofAreaSqFt) : null,
    property_latitude: project.propertyLatitude
      ? Number(project.propertyLatitude)
      : null,
    property_longitude: project.propertyLongitude
      ? Number(project.propertyLongitude)
      : null,
    is_recurring: project.isRecurring,
    recurrence_frequency: project.recurrenceFrequency ?? null,
    visits_per_month: project.visitsPerMonth
      ? Number(project.visitsPerMonth)
      : null,
    contract_months: project.contractMonths ?? null,
    recurrence_start_date: project.recurrenceStartDate
      ? project.recurrenceStartDate.toISOString()
      : null,
    created_at: project.createdAt.toISOString(),
    updated_at: project.updatedAt.toISOString(),
    thumbnail_url: thumbnailUrl ?? null,
  };
}
