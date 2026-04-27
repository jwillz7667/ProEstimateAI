import { Company } from "@prisma/client";

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
  tax_inclusive_pricing: boolean;
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
  appearance_mode: string | null;
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
    default_tax_rate: company.defaultTaxRate
      ? Number(company.defaultTaxRate)
      : null,
    default_markup_percent: company.defaultMarkupPercent
      ? Number(company.defaultMarkupPercent)
      : null,
    tax_inclusive_pricing: company.taxInclusivePricing,
    estimate_prefix: company.estimatePrefix,
    invoice_prefix: company.invoicePrefix,
    proposal_prefix: company.proposalPrefix ?? null,
    next_estimate_number: company.nextEstimateNumber,
    next_invoice_number: company.nextInvoiceNumber,
    next_proposal_number: company.nextProposalNumber,
    default_language: company.defaultLanguage ?? null,
    timezone: company.timezone ?? null,
    website_url: company.websiteUrl ?? null,
    tax_label: company.taxLabel ?? null,
    appearance_mode: company.appearanceMode ?? null,
    created_at: company.createdAt.toISOString(),
    updated_at: company.updatedAt.toISOString(),
  };
}
