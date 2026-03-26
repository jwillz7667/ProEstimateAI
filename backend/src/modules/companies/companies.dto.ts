import { Company } from '@prisma/client';

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
  next_estimate_number: number;
  next_invoice_number: number;
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
    default_tax_rate: company.defaultTaxRate ? Number(company.defaultTaxRate) : null,
    default_markup_percent: company.defaultMarkupPercent ? Number(company.defaultMarkupPercent) : null,
    estimate_prefix: company.estimatePrefix,
    invoice_prefix: company.invoicePrefix,
    next_estimate_number: company.nextEstimateNumber,
    next_invoice_number: company.nextInvoiceNumber,
    created_at: company.createdAt.toISOString(),
    updated_at: company.updatedAt.toISOString(),
  };
}
