import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { CreateLaborRateInput, UpdateLaborRateInput } from './labor-rates.validators';

/**
 * Verify that a pricing profile belongs to the given company.
 * Returns the profile or throws NotFoundError.
 */
async function verifyProfileOwnership(profileId: string, companyId: string) {
  const profile = await prisma.pricingProfile.findFirst({
    where: { id: profileId, companyId },
  });

  if (!profile) {
    throw new NotFoundError('PricingProfile', profileId);
  }

  return profile;
}

/**
 * Verify that a labor rate rule belongs to a profile owned by the company.
 * Returns the rule or throws NotFoundError.
 */
async function verifyRuleOwnership(ruleId: string, companyId: string) {
  const rule = await prisma.laborRateRule.findUnique({
    where: { id: ruleId },
    include: { pricingProfile: { select: { companyId: true } } },
  });

  if (!rule || rule.pricingProfile.companyId !== companyId) {
    throw new NotFoundError('LaborRateRule', ruleId);
  }

  return rule;
}

export async function listByProfile(profileId: string, companyId: string) {
  await verifyProfileOwnership(profileId, companyId);

  const rules = await prisma.laborRateRule.findMany({
    where: { pricingProfileId: profileId },
    orderBy: { category: 'asc' },
  });

  return rules;
}

export async function create(profileId: string, companyId: string, data: CreateLaborRateInput) {
  await verifyProfileOwnership(profileId, companyId);

  const rule = await prisma.laborRateRule.create({
    data: {
      pricingProfileId: profileId,
      category: data.category,
      ratePerHour: data.rate_per_hour,
      minimumHours: data.minimum_hours ?? undefined,
      rateType: data.rate_type ?? 'hourly',
      flatRate: data.flat_rate ?? null,
      unitRate: data.unit_rate ?? null,
      unit: data.unit ?? null,
    },
  });

  return rule;
}

export async function update(id: string, companyId: string, data: UpdateLaborRateInput) {
  await verifyRuleOwnership(id, companyId);

  const rule = await prisma.laborRateRule.update({
    where: { id },
    data: {
      ...(data.category !== undefined && { category: data.category }),
      ...(data.rate_per_hour !== undefined && { ratePerHour: data.rate_per_hour }),
      ...(data.minimum_hours !== undefined && { minimumHours: data.minimum_hours }),
      ...(data.rate_type !== undefined && { rateType: data.rate_type }),
      ...(data.flat_rate !== undefined && { flatRate: data.flat_rate }),
      ...(data.unit_rate !== undefined && { unitRate: data.unit_rate }),
      ...(data.unit !== undefined && { unit: data.unit }),
    },
  });

  return rule;
}

export async function remove(id: string, companyId: string) {
  await verifyRuleOwnership(id, companyId);

  await prisma.laborRateRule.delete({ where: { id } });
}
