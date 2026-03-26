import { Project } from '@prisma/client';

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
  created_at: string;
  updated_at: string;
}

export function toProjectDto(project: Project): ProjectDto {
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
    square_footage: project.squareFootage ? Number(project.squareFootage) : null,
    dimensions: project.dimensions,
    language: project.language,
    created_at: project.createdAt.toISOString(),
    updated_at: project.updatedAt.toISOString(),
  };
}
