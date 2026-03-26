import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { UpdateCompanyInput } from './companies.validators';

export async function getMe(companyId: string) {
  const company = await prisma.company.findUnique({
    where: { id: companyId },
  });

  if (!company) {
    throw new NotFoundError('Company', companyId);
  }

  return company;
}

export async function updateMe(companyId: string, data: UpdateCompanyInput) {
  // Verify company exists
  const existing = await prisma.company.findUnique({
    where: { id: companyId },
  });

  if (!existing) {
    throw new NotFoundError('Company', companyId);
  }

  // Map snake_case input to camelCase Prisma fields
  const company = await prisma.company.update({
    where: { id: companyId },
    data: {
      ...(data.name !== undefined && { name: data.name }),
      ...(data.phone !== undefined && { phone: data.phone }),
      ...(data.email !== undefined && { email: data.email }),
      ...(data.address !== undefined && { address: data.address }),
      ...(data.city !== undefined && { city: data.city }),
      ...(data.state !== undefined && { state: data.state }),
      ...(data.zip !== undefined && { zip: data.zip }),
      ...(data.logo_url !== undefined && { logoUrl: data.logo_url }),
      ...(data.primary_color !== undefined && { primaryColor: data.primary_color }),
      ...(data.secondary_color !== undefined && { secondaryColor: data.secondary_color }),
      ...(data.default_tax_rate !== undefined && { defaultTaxRate: data.default_tax_rate }),
      ...(data.default_markup_percent !== undefined && { defaultMarkupPercent: data.default_markup_percent }),
      ...(data.estimate_prefix !== undefined && { estimatePrefix: data.estimate_prefix }),
      ...(data.invoice_prefix !== undefined && { invoicePrefix: data.invoice_prefix }),
    },
  });

  return company;
}
