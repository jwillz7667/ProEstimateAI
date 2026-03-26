import { LaborRateRule } from '@prisma/client';

export interface LaborRateDto {
  id: string;
  pricing_profile_id: string;
  category: string;
  rate_per_hour: number;
  minimum_hours: number;
}

export function toLaborRateDto(rule: LaborRateRule): LaborRateDto {
  return {
    id: rule.id,
    pricing_profile_id: rule.pricingProfileId,
    category: rule.category,
    rate_per_hour: Number(rule.ratePerHour),
    minimum_hours: Number(rule.minimumHours),
  };
}
