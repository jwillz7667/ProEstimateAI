import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { PaginationParams, paginateResults, buildCursorWhere } from '../../lib/pagination';
import { CreateEstimateInput, UpdateEstimateInput } from './estimates.validators';
import { EstimateStatus } from '@prisma/client';

export async function list(companyId: string, pagination: PaginationParams, projectId?: string) {
  const { cursor, pageSize = 25 } = pagination;

  const where: any = { companyId };
  if (projectId) {
    where.projectId = projectId;
  }

  const estimates = await prisma.estimate.findMany({
    where,
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    take: pageSize + 1,
    ...buildCursorWhere(cursor),
  });

  return paginateResults(estimates, pageSize);
}

export async function getById(id: string, companyId: string) {
  const estimate = await prisma.estimate.findFirst({
    where: { id, companyId },
  });

  if (!estimate) {
    throw new NotFoundError('Estimate', id);
  }

  return estimate;
}

export async function create(companyId: string, userId: string, data: CreateEstimateInput) {
  // Verify the project belongs to this company
  const project = await prisma.project.findFirst({
    where: { id: data.project_id, companyId },
  });

  if (!project) {
    throw new NotFoundError('Project', data.project_id);
  }

  // Auto-increment estimate number inside a transaction
  const estimate = await prisma.$transaction(async (tx) => {
    // Read the company's current numbering state
    const company = await tx.company.findUnique({
      where: { id: companyId },
      select: { estimatePrefix: true, nextEstimateNumber: true },
    });

    if (!company) {
      throw new NotFoundError('Company', companyId);
    }

    const estimateNumber = `${company.estimatePrefix || 'EST'}-${company.nextEstimateNumber}`;

    // Increment the company's next estimate number
    await tx.company.update({
      where: { id: companyId },
      data: { nextEstimateNumber: company.nextEstimateNumber + 1 },
    });

    // Create the estimate
    const created = await tx.estimate.create({
      data: {
        projectId: data.project_id,
        companyId,
        estimateNumber,
        notes: data.notes ?? null,
        validUntil: data.valid_until ? new Date(data.valid_until) : null,
      },
    });

    // Log activity
    await tx.activityLogEntry.create({
      data: {
        projectId: data.project_id,
        userId,
        action: 'ESTIMATE_CREATED',
        description: `Estimate ${estimateNumber} created`,
      },
    });

    return created;
  });

  return estimate;
}

export async function update(id: string, companyId: string, userId: string, data: UpdateEstimateInput) {
  const existing = await prisma.estimate.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError('Estimate', id);
  }

  const updateData: any = {};

  if (data.status !== undefined) {
    updateData.status = data.status.toUpperCase() as EstimateStatus;
  }
  if (data.notes !== undefined) {
    updateData.notes = data.notes;
  }
  if (data.valid_until !== undefined) {
    updateData.validUntil = data.valid_until ? new Date(data.valid_until) : null;
  }
  if (data.subtotal_materials !== undefined) {
    updateData.subtotalMaterials = data.subtotal_materials;
  }
  if (data.subtotal_labor !== undefined) {
    updateData.subtotalLabor = data.subtotal_labor;
  }
  if (data.subtotal_other !== undefined) {
    updateData.subtotalOther = data.subtotal_other;
  }
  if (data.tax_amount !== undefined) {
    updateData.taxAmount = data.tax_amount;
  }
  if (data.discount_amount !== undefined) {
    updateData.discountAmount = data.discount_amount;
  }
  if (data.total_amount !== undefined) {
    updateData.totalAmount = data.total_amount;
  }

  const estimate = await prisma.estimate.update({
    where: { id },
    data: updateData,
  });

  // Log activity
  await prisma.activityLogEntry.create({
    data: {
      projectId: existing.projectId,
      userId,
      action: 'ESTIMATE_UPDATED',
      description: `Estimate ${existing.estimateNumber} updated`,
    },
  });

  return estimate;
}

export async function remove(id: string, companyId: string) {
  const existing = await prisma.estimate.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError('Estimate', id);
  }

  await prisma.estimate.delete({ where: { id } });
}
