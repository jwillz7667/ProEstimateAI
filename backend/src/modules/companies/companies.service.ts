import { prisma } from "../../config/database";
import { env } from "../../config/env";
import { NotFoundError, ValidationError } from "../../lib/errors";
import { UpdateCompanyInput, UploadLogoInput } from "./companies.validators";
import { invalidateCache, CacheKeys } from "../../config/redis";

export async function getMe(companyId: string) {
  const company = await prisma.company.findUnique({
    where: { id: companyId },
  });

  if (!company) {
    throw new NotFoundError("Company", companyId);
  }

  return company;
}

export async function updateMe(companyId: string, data: UpdateCompanyInput) {
  // Verify company exists
  const existing = await prisma.company.findUnique({
    where: { id: companyId },
  });

  if (!existing) {
    throw new NotFoundError("Company", companyId);
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
      ...(data.primary_color !== undefined && {
        primaryColor: data.primary_color,
      }),
      ...(data.secondary_color !== undefined && {
        secondaryColor: data.secondary_color,
      }),
      ...(data.default_tax_rate !== undefined && {
        defaultTaxRate: data.default_tax_rate,
      }),
      ...(data.default_markup_percent !== undefined && {
        defaultMarkupPercent: data.default_markup_percent,
      }),
      ...(data.tax_inclusive_pricing !== undefined && {
        taxInclusivePricing: data.tax_inclusive_pricing,
      }),
      ...(data.estimate_prefix !== undefined && {
        estimatePrefix: data.estimate_prefix,
      }),
      ...(data.invoice_prefix !== undefined && {
        invoicePrefix: data.invoice_prefix,
      }),
      ...(data.proposal_prefix !== undefined && {
        proposalPrefix: data.proposal_prefix,
      }),
      ...(data.next_estimate_number !== undefined && {
        nextEstimateNumber: data.next_estimate_number,
      }),
      ...(data.next_invoice_number !== undefined && {
        nextInvoiceNumber: data.next_invoice_number,
      }),
      ...(data.next_proposal_number !== undefined && {
        nextProposalNumber: data.next_proposal_number,
      }),
      ...(data.default_language !== undefined && {
        defaultLanguage: data.default_language,
      }),
      ...(data.timezone !== undefined && { timezone: data.timezone }),
      ...(data.website_url !== undefined && { websiteUrl: data.website_url }),
      ...(data.tax_label !== undefined && { taxLabel: data.tax_label }),
      ...(data.appearance_mode !== undefined && {
        appearanceMode: data.appearance_mode,
      }),
    },
  });

  await invalidateCache(CacheKeys.companyProfile(companyId));

  return company;
}

/**
 * Persist a company logo as base64 on the Company row and rewrite `logoUrl`
 * to the public serve endpoint. Mirrors the asset upload pattern in
 * `assets.service.ts:54-93`.
 */
export async function uploadLogo(companyId: string, data: UploadLogoInput) {
  const existing = await prisma.company.findUnique({
    where: { id: companyId },
  });
  if (!existing) {
    throw new NotFoundError("Company", companyId);
  }

  // Defense in depth: re-check decoded size even though the validator caps
  // encoded length. Keeps a bad actor with `image_data` = junk from ballooning
  // storage above ~2MB per company.
  const decodedSizeBytes = Math.floor((data.image_data.length * 3) / 4);
  if (decodedSizeBytes > 2 * 1024 * 1024) {
    throw new ValidationError("Logo must be 2MB or smaller after decoding");
  }

  const serveUrl = `${env.API_BASE_URL}/v1/companies/${companyId}/logo`;
  const company = await prisma.company.update({
    where: { id: companyId },
    data: {
      logoImageData: data.image_data,
      logoImageMimeType: data.mime_type,
      logoUrl: serveUrl,
    },
  });

  await invalidateCache(CacheKeys.companyProfile(companyId));
  return company;
}

/**
 * Remove the stored company logo. Clears all three fields (binary + mime +
 * derived serve URL) so the UI snaps back to the fallback.
 */
export async function deleteLogo(companyId: string) {
  const existing = await prisma.company.findUnique({
    where: { id: companyId },
  });
  if (!existing) {
    throw new NotFoundError("Company", companyId);
  }

  const company = await prisma.company.update({
    where: { id: companyId },
    data: {
      logoImageData: null,
      logoImageMimeType: null,
      logoUrl: null,
    },
  });

  await invalidateCache(CacheKeys.companyProfile(companyId));
  return company;
}

/**
 * Public (no-auth) logo retrieval. CUIDs are unguessable; rendering the logo
 * on a PDF or share page must not require the contractor's session.
 */
export async function getPublicCompanyLogo(companyId: string) {
  const company = await prisma.company.findUnique({
    where: { id: companyId },
    select: { logoImageData: true, logoImageMimeType: true },
  });

  if (!company?.logoImageData || !company?.logoImageMimeType) {
    return null;
  }

  return {
    data: Buffer.from(company.logoImageData, "base64"),
    mimeType: company.logoImageMimeType,
  };
}
