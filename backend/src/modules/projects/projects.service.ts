import { ProjectType, ProjectStatus, QualityTier } from "@prisma/client";
import { prisma } from "../../config/database";
import { env } from "../../config/env";
import { NotFoundError } from "../../lib/errors";
import {
  PaginationParams,
  paginateResults,
  buildCursorWhere,
} from "../../lib/pagination";
import { CreateProjectInput, UpdateProjectInput } from "./projects.validators";

export async function list(companyId: string, pagination: PaginationParams) {
  const { cursor, pageSize = 25 } = pagination;

  const projects = await prisma.project.findMany({
    where: { companyId },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: pageSize + 1,
    ...buildCursorWhere(cursor),
  });

  return paginateResults(projects, pageSize);
}

/**
 * For each project ID, find the best thumbnail URL:
 *   1. Most recent COMPLETED AIGeneration (preview endpoint), or
 *   2. First ORIGINAL asset with stored image data (asset image endpoint), or
 *   3. null.
 *
 * Issued as two queries instead of N+1: one for generations, one for assets
 * scoped to projects that lack a generation. Cheap even for large pages.
 */
export async function buildThumbnailMap(
  projectIds: string[],
): Promise<Map<string, string>> {
  const result = new Map<string, string>();
  if (projectIds.length === 0) return result;

  const apiBase = env.API_BASE_URL;

  const generations = await prisma.aIGeneration.findMany({
    where: { projectId: { in: projectIds }, status: "COMPLETED" },
    select: { projectId: true, id: true, createdAt: true },
    orderBy: [{ projectId: "asc" }, { createdAt: "desc" }],
  });
  for (const g of generations) {
    if (!result.has(g.projectId)) {
      result.set(g.projectId, `${apiBase}/v1/generations/${g.id}/preview`);
    }
  }

  const missing = projectIds.filter((id) => !result.has(id));
  if (missing.length > 0) {
    const assets = await prisma.asset.findMany({
      where: {
        projectId: { in: missing },
        assetType: "ORIGINAL",
        imageData: { not: null },
      },
      select: { projectId: true, id: true, sortOrder: true, createdAt: true },
      orderBy: [
        { projectId: "asc" },
        { sortOrder: "asc" },
        { createdAt: "asc" },
      ],
    });
    for (const a of assets) {
      if (!result.has(a.projectId)) {
        result.set(a.projectId, `${apiBase}/v1/assets/${a.id}/image`);
      }
    }
  }

  return result;
}

export async function getById(id: string, companyId: string) {
  const project = await prisma.project.findFirst({
    where: { id, companyId },
  });

  if (!project) {
    throw new NotFoundError("Project", id);
  }

  return project;
}

export async function create(companyId: string, data: CreateProjectInput) {
  const project = await prisma.project.create({
    data: {
      companyId,
      title: data.title,
      clientId: data.client_id ?? null,
      description: data.description ?? null,
      projectType: data.project_type
        ? (data.project_type.toUpperCase() as ProjectType)
        : undefined,
      status: data.status
        ? (data.status.toUpperCase() as ProjectStatus)
        : undefined,
      budgetMin: data.budget_min ?? null,
      budgetMax: data.budget_max ?? null,
      qualityTier: data.quality_tier
        ? (data.quality_tier.toUpperCase() as QualityTier)
        : undefined,
      squareFootage: data.square_footage ?? null,
      dimensions: data.dimensions ?? null,
      language: data.language ?? undefined,
      lawnAreaSqFt: data.lawn_area_sq_ft ?? null,
      roofAreaSqFt: data.roof_area_sq_ft ?? null,
      propertyLatitude: data.property_latitude ?? null,
      propertyLongitude: data.property_longitude ?? null,
      isRecurring: data.is_recurring ?? false,
      recurrenceFrequency: data.recurrence_frequency ?? null,
      visitsPerMonth: data.visits_per_month ?? null,
      contractMonths: data.contract_months ?? null,
      recurrenceStartDate: data.recurrence_start_date
        ? new Date(data.recurrence_start_date)
        : null,
    },
  });

  return project;
}

export async function update(
  id: string,
  companyId: string,
  data: UpdateProjectInput,
) {
  const existing = await prisma.project.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError("Project", id);
  }

  const project = await prisma.project.update({
    where: { id },
    data: {
      ...(data.title !== undefined && { title: data.title }),
      ...(data.client_id !== undefined && { clientId: data.client_id }),
      ...(data.description !== undefined && { description: data.description }),
      ...(data.project_type !== undefined && {
        projectType: data.project_type.toUpperCase() as ProjectType,
      }),
      ...(data.status !== undefined && {
        status: data.status.toUpperCase() as ProjectStatus,
      }),
      ...(data.budget_min !== undefined && { budgetMin: data.budget_min }),
      ...(data.budget_max !== undefined && { budgetMax: data.budget_max }),
      ...(data.quality_tier !== undefined && {
        qualityTier: data.quality_tier.toUpperCase() as QualityTier,
      }),
      ...(data.square_footage !== undefined && {
        squareFootage: data.square_footage,
      }),
      ...(data.dimensions !== undefined && { dimensions: data.dimensions }),
      ...(data.language !== undefined && { language: data.language }),
      ...(data.lawn_area_sq_ft !== undefined && {
        lawnAreaSqFt: data.lawn_area_sq_ft,
      }),
      ...(data.roof_area_sq_ft !== undefined && {
        roofAreaSqFt: data.roof_area_sq_ft,
      }),
      ...(data.property_latitude !== undefined && {
        propertyLatitude: data.property_latitude,
      }),
      ...(data.property_longitude !== undefined && {
        propertyLongitude: data.property_longitude,
      }),
      ...(data.is_recurring !== undefined && {
        isRecurring: data.is_recurring,
      }),
      ...(data.recurrence_frequency !== undefined && {
        recurrenceFrequency: data.recurrence_frequency,
      }),
      ...(data.visits_per_month !== undefined && {
        visitsPerMonth: data.visits_per_month,
      }),
      ...(data.contract_months !== undefined && {
        contractMonths: data.contract_months,
      }),
      ...(data.recurrence_start_date !== undefined && {
        recurrenceStartDate: data.recurrence_start_date
          ? new Date(data.recurrence_start_date)
          : null,
      }),
    },
  });

  return project;
}

export async function remove(id: string, companyId: string) {
  const existing = await prisma.project.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError("Project", id);
  }

  await prisma.project.delete({ where: { id } });
}
