import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { PaginationParams, paginateResults, buildCursorWhere } from '../../lib/pagination';
import { CreateEstimateInput, UpdateEstimateInput } from './estimates.validators';
import { EstimateStatus, LineItemCategory } from '@prisma/client';
import { generateEstimate, type EstimateGenContext } from '../../lib/estimate-gen';

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
        title: data.title ?? null,
        pricingProfileId: data.pricing_profile_id ?? null,
        notes: data.notes ?? null,
        assumptions: data.assumptions ?? null,
        exclusions: data.exclusions ?? null,
        contingencyAmount: data.contingency_amount ?? null,
        validUntil: data.valid_until ? new Date(data.valid_until) : null,
        createdByUserId: userId,
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
  if (data.title !== undefined) {
    updateData.title = data.title;
  }
  if (data.pricing_profile_id !== undefined) {
    updateData.pricingProfileId = data.pricing_profile_id;
  }
  if (data.notes !== undefined) {
    updateData.notes = data.notes;
  }
  if (data.assumptions !== undefined) {
    updateData.assumptions = data.assumptions;
  }
  if (data.exclusions !== undefined) {
    updateData.exclusions = data.exclusions;
  }
  if (data.contingency_amount !== undefined) {
    updateData.contingencyAmount = data.contingency_amount;
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

/**
 * AI-generate a complete, professional estimate for a project. Pulls the
 * project, the company's branding and numbering defaults, the project's
 * selected materials, and any configured pricing profile + labor rates, then
 * hands everything to the estimate-gen lib. The returned structured output is
 * persisted as an Estimate plus its line items in a single transaction.
 */
export async function generateAI(companyId: string, userId: string, projectId: string) {
  const project = await prisma.project.findFirst({
    where: { id: projectId, companyId },
  });
  if (!project) {
    throw new NotFoundError('Project', projectId);
  }

  const company = await prisma.company.findUnique({ where: { id: companyId } });
  if (!company) {
    throw new NotFoundError('Company', companyId);
  }

  const [selectedMaterials, defaultPricingProfile] = await Promise.all([
    prisma.materialSuggestion.findMany({
      where: { projectId, isSelected: true },
      orderBy: { sortOrder: 'asc' },
    }),
    prisma.pricingProfile.findFirst({
      where: { companyId, isDefault: true },
      include: { laborRates: true },
    }),
  ]);

  const context: EstimateGenContext = {
    projectType: project.projectType,
    qualityTier: project.qualityTier,
    projectTitle: project.title,
    projectDescription: project.description ?? undefined,
    squareFootage: project.squareFootage?.toString(),
    dimensions: project.dimensions ?? undefined,
    companyName: company.name,
    companyPhone: company.phone ?? undefined,
    companyEmail: company.email ?? undefined,
    companyAddress: [company.address, company.city, company.state, company.zip]
      .filter(Boolean)
      .join(', ') || undefined,
    companyWebsite: company.websiteUrl ?? undefined,
    defaultMarkupPercent: company.defaultMarkupPercent
      ? Number(company.defaultMarkupPercent)
      : undefined,
    defaultTaxRate: company.defaultTaxRate ? Number(company.defaultTaxRate) : undefined,
    selectedMaterials: selectedMaterials.map((m) => ({
      name: m.name,
      category: m.category,
      estimatedCost: Number(m.estimatedCost),
      unit: m.unit,
      quantity: Number(m.quantity),
    })),
    pricingProfile: defaultPricingProfile
      ? {
          defaultMarkupPercent: Number(defaultPricingProfile.defaultMarkupPercent),
          contingencyPercent: Number(defaultPricingProfile.contingencyPercent),
          wasteFactor: Number(defaultPricingProfile.wasteFactor),
          laborRates: defaultPricingProfile.laborRates.map((r) => ({
            category: r.category,
            ratePerHour: Number(r.ratePerHour),
          })),
        }
      : undefined,
  };

  const generated = await generateEstimate(context);

  // Compute totals from the generated line items so the Estimate row has
  // realistic pre-tax and total numbers on first load — the user can still
  // tweak everything in the editor.
  let subtotalMaterials = 0;
  let subtotalLabor = 0;
  let subtotalOther = 0;
  let taxAmount = 0;

  for (const item of generated.lineItems) {
    const lineBase = item.quantity * item.unitCost;
    const markup = lineBase * (item.markupPercent / 100);
    const preTax = lineBase + markup;
    const lineTax = preTax * item.taxRate;

    switch (item.category) {
      case 'materials':
        subtotalMaterials += preTax;
        break;
      case 'labor':
        subtotalLabor += preTax;
        break;
      case 'other':
        subtotalOther += preTax;
        break;
    }
    taxAmount += lineTax;
  }

  const totalAmount = subtotalMaterials + subtotalLabor + subtotalOther + taxAmount;

  const validUntil = new Date();
  validUntil.setDate(validUntil.getDate() + generated.validDays);

  const notesWithTerms = [generated.overview, generated.terms]
    .filter((s) => s && s.trim().length > 0)
    .join('\n\n');

  // Compose Assumptions and Exclusions into the dedicated Estimate columns.
  const estimate = await prisma.$transaction(async (tx) => {
    const co = await tx.company.findUnique({
      where: { id: companyId },
      select: { estimatePrefix: true, nextEstimateNumber: true },
    });
    if (!co) {
      throw new NotFoundError('Company', companyId);
    }

    const estimateNumber = `${co.estimatePrefix || 'EST'}-${co.nextEstimateNumber}`;

    await tx.company.update({
      where: { id: companyId },
      data: { nextEstimateNumber: co.nextEstimateNumber + 1 },
    });

    const created = await tx.estimate.create({
      data: {
        projectId,
        companyId,
        estimateNumber,
        title: generated.title,
        pricingProfileId: defaultPricingProfile?.id ?? null,
        createdByUserId: userId,
        subtotalMaterials,
        subtotalLabor,
        subtotalOther,
        taxAmount,
        discountAmount: 0,
        totalAmount,
        assumptions: generated.assumptions || null,
        exclusions: generated.exclusions || null,
        notes: notesWithTerms || null,
        validUntil,
      },
    });

    // Persist each AI-generated line item.
    for (let i = 0; i < generated.lineItems.length; i++) {
      const item = generated.lineItems[i];
      const lineBase = item.quantity * item.unitCost;
      const markup = lineBase * (item.markupPercent / 100);
      const preTax = lineBase + markup;
      const lineTotal = preTax + preTax * item.taxRate;

      const categoryEnum =
        item.category === 'materials'
          ? LineItemCategory.MATERIALS
          : item.category === 'labor'
            ? LineItemCategory.LABOR
            : LineItemCategory.OTHER;

      await tx.estimateLineItem.create({
        data: {
          estimateId: created.id,
          category: categoryEnum,
          itemType: 'per_unit',
          name: item.name,
          description: item.description || null,
          quantity: item.quantity,
          unit: item.unit,
          unitCost: item.unitCost,
          markupPercent: item.markupPercent,
          // Canonical: tax_rate stored as a fraction (e.g. 0.0825 for 8.25%),
          // matching the validator (max 1.0) and the recalc logic that
          // treats the DB value as a multiplier.
          taxRate: item.taxRate,
          lineTotal,
          sortOrder: i,
        },
      });
    }

    await tx.activityLogEntry.create({
      data: {
        projectId,
        userId,
        action: 'ESTIMATE_CREATED',
        description: `AI-generated estimate ${estimateNumber} created`,
      },
    });

    return created;
  });

  return estimate;
}
