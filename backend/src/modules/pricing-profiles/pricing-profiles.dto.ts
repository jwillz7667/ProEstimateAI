import { PricingProfile } from '@prisma/client';

export interface PricingProfileDto {
  id: string;
  company_id: string;
  name: string;
  default_markup_percent: number;
  contingency_percent: number;
  waste_factor: number;
  is_default: boolean;
  created_at: string;
}

export function toPricingProfileDto(profile: PricingProfile): PricingProfileDto {
  return {
    id: profile.id,
    company_id: profile.companyId,
    name: profile.name,
    default_markup_percent: Number(profile.defaultMarkupPercent),
    contingency_percent: Number(profile.contingencyPercent),
    waste_factor: Number(profile.wasteFactor),
    is_default: profile.isDefault,
    created_at: profile.createdAt.toISOString(),
  };
}
