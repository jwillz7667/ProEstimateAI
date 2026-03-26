import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { PaginationParams, paginateResults, buildCursorWhere } from '../../lib/pagination';
import { CreatePricingProfileInput, UpdatePricingProfileInput } from './pricing-profiles.validators';

export async function list(companyId: string, pagination: PaginationParams) {
  const { cursor, pageSize = 25 } = pagination;

  const profiles = await prisma.pricingProfile.findMany({
    where: { companyId },
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    take: pageSize + 1,
    ...buildCursorWhere(cursor),
  });

  return paginateResults(profiles, pageSize);
}

export async function getById(id: string, companyId: string) {
  const profile = await prisma.pricingProfile.findFirst({
    where: { id, companyId },
  });

  if (!profile) {
    throw new NotFoundError('PricingProfile', id);
  }

  return profile;
}

export async function create(companyId: string, data: CreatePricingProfileInput) {
  // If this profile is being set as default, clear defaults on all others in a transaction
  if (data.is_default) {
    return prisma.$transaction(async (tx) => {
      await tx.pricingProfile.updateMany({
        where: { companyId, isDefault: true },
        data: { isDefault: false },
      });

      return tx.pricingProfile.create({
        data: {
          companyId,
          name: data.name,
          defaultMarkupPercent: data.default_markup_percent ?? undefined,
          contingencyPercent: data.contingency_percent ?? undefined,
          wasteFactor: data.waste_factor ?? undefined,
          isDefault: true,
        },
      });
    });
  }

  return prisma.pricingProfile.create({
    data: {
      companyId,
      name: data.name,
      defaultMarkupPercent: data.default_markup_percent ?? undefined,
      contingencyPercent: data.contingency_percent ?? undefined,
      wasteFactor: data.waste_factor ?? undefined,
      isDefault: data.is_default ?? false,
    },
  });
}

export async function update(id: string, companyId: string, data: UpdatePricingProfileInput) {
  const existing = await prisma.pricingProfile.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError('PricingProfile', id);
  }

  // If setting as default, clear all others in a transaction
  if (data.is_default === true) {
    return prisma.$transaction(async (tx) => {
      await tx.pricingProfile.updateMany({
        where: { companyId, isDefault: true, NOT: { id } },
        data: { isDefault: false },
      });

      return tx.pricingProfile.update({
        where: { id },
        data: {
          ...(data.name !== undefined && { name: data.name }),
          ...(data.default_markup_percent !== undefined && {
            defaultMarkupPercent: data.default_markup_percent,
          }),
          ...(data.contingency_percent !== undefined && {
            contingencyPercent: data.contingency_percent,
          }),
          ...(data.waste_factor !== undefined && { wasteFactor: data.waste_factor }),
          isDefault: true,
        },
      });
    });
  }

  return prisma.pricingProfile.update({
    where: { id },
    data: {
      ...(data.name !== undefined && { name: data.name }),
      ...(data.default_markup_percent !== undefined && {
        defaultMarkupPercent: data.default_markup_percent,
      }),
      ...(data.contingency_percent !== undefined && {
        contingencyPercent: data.contingency_percent,
      }),
      ...(data.waste_factor !== undefined && { wasteFactor: data.waste_factor }),
      ...(data.is_default !== undefined && { isDefault: data.is_default }),
    },
  });
}

export async function remove(id: string, companyId: string) {
  const existing = await prisma.pricingProfile.findFirst({
    where: { id, companyId },
  });

  if (!existing) {
    throw new NotFoundError('PricingProfile', id);
  }

  await prisma.pricingProfile.delete({ where: { id } });
}
