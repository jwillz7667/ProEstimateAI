import {
  Proposal,
  Company,
  Project,
  Estimate,
  EstimateLineItem,
  Asset,
} from '@prisma/client';

interface ProposalWithRelations extends Proposal {
  company: Company;
  project: Project & {
    assets: Asset[];
  };
  estimate: Estimate & {
    lineItems: EstimateLineItem[];
  };
}

interface SharedLineItemDto {
  name: string;
  description: string | null;
  category: string;
  quantity: number;
  unit: string;
  unit_cost: number;
  line_total: number;
}

interface SharedCompanyDto {
  name: string;
  phone: string | null;
  email: string | null;
  address: string | null;
  city: string | null;
  state: string | null;
  zip: string | null;
  logo_url: string | null;
  primary_color: string | null;
  website_url: string | null;
}

interface SharedProjectDto {
  title: string;
  description: string | null;
  project_type: string;
}

interface SharedEstimateDto {
  subtotal_materials: number;
  subtotal_labor: number;
  subtotal_other: number;
  tax_amount: number;
  discount_amount: number;
  total_amount: number;
  line_items: SharedLineItemDto[];
}

interface SharedProposalDto {
  title: string | null;
  proposal_number: string | null;
  status: string;
  intro_text: string | null;
  scope_of_work: string | null;
  timeline_text: string | null;
  terms_and_conditions: string | null;
  footer_text: string | null;
  client_message: string | null;
  hero_image_url: string | null;
  expires_at: string | null;
  sent_at: string | null;
  viewed_at: string | null;
  responded_at: string | null;
}

interface SharedBeforeAfterImageDto {
  asset_id: string;
  asset_type: string;
  url: string;
  sort_order: number;
}

export interface SharedProposalPageDto {
  company: SharedCompanyDto;
  project: SharedProjectDto;
  estimate: SharedEstimateDto;
  proposal: SharedProposalDto;
  before_after_images: SharedBeforeAfterImageDto[];
}

export function toSharedProposalDto(proposal: ProposalWithRelations): SharedProposalPageDto {
  const { company, project, estimate } = proposal;

  const lineItems: SharedLineItemDto[] = estimate.lineItems.map((item) => ({
    name: item.name,
    description: item.description,
    category: item.category.toLowerCase(),
    quantity: Number(item.quantity),
    unit: item.unit,
    unit_cost: Number(item.unitCost),
    line_total: Number(item.lineTotal),
  }));

  const beforeAfterImages: SharedBeforeAfterImageDto[] = project.assets.map((asset) => ({
    asset_id: asset.id,
    asset_type: asset.assetType.toLowerCase(),
    url: asset.url,
    sort_order: asset.sortOrder,
  }));

  return {
    company: {
      name: company.name,
      phone: company.phone,
      email: company.email,
      address: company.address,
      city: company.city,
      state: company.state,
      zip: company.zip,
      logo_url: company.logoUrl,
      primary_color: company.primaryColor,
      website_url: company.websiteUrl,
    },
    project: {
      title: project.title,
      description: project.description,
      project_type: project.projectType.toLowerCase(),
    },
    estimate: {
      subtotal_materials: Number(estimate.subtotalMaterials),
      subtotal_labor: Number(estimate.subtotalLabor),
      subtotal_other: Number(estimate.subtotalOther),
      tax_amount: Number(estimate.taxAmount),
      discount_amount: Number(estimate.discountAmount),
      total_amount: Number(estimate.totalAmount),
      line_items: lineItems,
    },
    proposal: {
      title: proposal.title,
      proposal_number: proposal.proposalNumber,
      status: proposal.status.toLowerCase(),
      intro_text: proposal.introText,
      scope_of_work: proposal.scopeOfWork,
      timeline_text: proposal.timelineText,
      terms_and_conditions: proposal.termsAndConditions,
      footer_text: proposal.footerText,
      client_message: proposal.clientMessage,
      hero_image_url: proposal.heroImageUrl,
      expires_at: proposal.expiresAt ? proposal.expiresAt.toISOString() : null,
      sent_at: proposal.sentAt ? proposal.sentAt.toISOString() : null,
      viewed_at: proposal.viewedAt ? proposal.viewedAt.toISOString() : null,
      responded_at: proposal.respondedAt ? proposal.respondedAt.toISOString() : null,
    },
    before_after_images: beforeAfterImages,
  };
}
