import { ProjectType, ProjectStatus, QualityTier } from '@prisma/client';
import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { PaginationParams, paginateResults, buildCursorWhere } from '../../lib/pagination';
import { CreateProjectInput, UpdateProjectInput } from './projects.validators';

export async function list(companyId: string, pagination: PaginationParams) {
  const { cursor, pageSize = 25 } = pagination;

  const projects = await prisma.project.findMany({
    where: { companyId },
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    take: pageSize + 1,
    ...buildCursorWhere(cursor),
  });

  return paginateResults(projects, pageSize);
}

export async function getById(id: string, companyId: string) {
  const project = await prisma.project.findFirst({
    where: { id, companyId },
  });

  if (!project) {
    throw new NotFoundError('Project', id);
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
    },
  });

  return project;
}

export async function update(id: string, companyId: string, data: UpdateProjectInput) {
  const existing = await prisma.project.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError('Project', id);
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
      ...(data.square_footage !== undefined && { squareFootage: data.square_footage }),
      ...(data.dimensions !== undefined && { dimensions: data.dimensions }),
      ...(data.language !== undefined && { language: data.language }),
    },
  });

  return project;
}

export async function remove(id: string, companyId: string) {
  const existing = await prisma.project.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError('Project', id);
  }

  await prisma.project.delete({ where: { id } });
}
