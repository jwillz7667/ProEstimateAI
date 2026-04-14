import type { User, Company } from '@prisma/client';

// ─── User DTO ────────────────────────────────────────────────────────────────
// Maps Prisma User model (camelCase) to the snake_case API contract.
// The `role` enum is stored as UPPER_CASE in DB but returned as lowercase.

export interface UserDto {
  id: string;
  company_id: string;
  email: string;
  full_name: string;
  role: string;
  avatar_url: string | null;
  phone: string | null;
  is_active: boolean;
  created_at: string;
}

export function toUserDto(user: User): UserDto {
  return {
    id: user.id,
    company_id: user.companyId,
    email: user.email,
    full_name: user.fullName,
    role: user.role.toLowerCase(),
    avatar_url: user.avatarUrl,
    phone: user.phone,
    is_active: user.isActive,
    created_at: user.createdAt.toISOString(),
  };
}

// ─── Company DTO ─────────────────────────────────────────────────────────────
// Prisma Decimal fields are returned as Prisma.Decimal objects.
// They must be converted to plain numbers for JSON serialization.

export interface CompanyDto {
  id: string;
  name: string;
  phone: string | null;
  email: string | null;
  address: string | null;
  city: string | null;
  state: string | null;
  zip: string | null;
  logo_url: string | null;
  primary_color: string | null;
  secondary_color: string | null;
  default_tax_rate: number | null;
  default_markup_percent: number | null;
  estimate_prefix: string | null;
  invoice_prefix: string | null;
  proposal_prefix: string | null;
  next_estimate_number: number;
  next_invoice_number: number;
  next_proposal_number: number;
  default_language: string | null;
  timezone: string | null;
  website_url: string | null;
  tax_label: string | null;
  created_at: string;
  updated_at: string;
}

export function toCompanyDto(company: Company): CompanyDto {
  return {
    id: company.id,
    name: company.name,
    phone: company.phone,
    email: company.email,
    address: company.address,
    city: company.city,
    state: company.state,
    zip: company.zip,
    logo_url: company.logoUrl,
    primary_color: company.primaryColor,
    secondary_color: company.secondaryColor,
    default_tax_rate: company.defaultTaxRate !== null
      ? Number(company.defaultTaxRate)
      : null,
    default_markup_percent: company.defaultMarkupPercent !== null
      ? Number(company.defaultMarkupPercent)
      : null,
    estimate_prefix: company.estimatePrefix,
    invoice_prefix: company.invoicePrefix,
    proposal_prefix: company.proposalPrefix,
    next_estimate_number: company.nextEstimateNumber,
    next_invoice_number: company.nextInvoiceNumber,
    next_proposal_number: company.nextProposalNumber,
    default_language: company.defaultLanguage,
    timezone: company.timezone,
    website_url: company.websiteUrl,
    tax_label: company.taxLabel,
    created_at: company.createdAt.toISOString(),
    updated_at: company.updatedAt.toISOString(),
  };
}

// ─── Auth Response DTO ───────────────────────────────────────────────────────

export interface AuthResponseDto {
  user: UserDto;
  company: CompanyDto;
  access_token: string;
  refresh_token: string;
}

export interface TokenPairDto {
  access_token: string;
  refresh_token: string;
}
