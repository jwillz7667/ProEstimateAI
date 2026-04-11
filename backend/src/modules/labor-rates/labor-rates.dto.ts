import { LaborRateRule } from '@prisma/client';

export interface LaborRateDto {
  id: string;
  pricing_profile_id: string;
  category: string;
  rate_per_hour: number;
  minimum_hours: number;
  rate_type: string;
  flat_rate: number | null;
  unit_rate: number | null;
  unit: string | null;
}

export function toLaborRateDto(rule: LaborRateRule): LaborRateDto {
  return {
    id: rule.id,
    pricing_profile_id: rule.pricingProfileId,
    category: rule.category,
    rate_per_hour: Number(rule.ratePerHour),
    minimum_hours: Number(rule.minimumHours),
    rate_type: rule.rateType,
    flat_rate: rule.flatRate ? Number(rule.flatRate) : null,
    unit_rate: rule.unitRate ? Number(rule.unitRate) : null,
    unit: rule.unit ?? null,
  };
}
