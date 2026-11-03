import {
  Proposal,
  Company,
  Estimate,
  EstimateLineItem,
  Asset,
  ProjectType,
  ProposalAcceptance,
  ChangeOrder,
} from '@prisma/client';
import { ACCEPTANCE_CONSENT_TEXT, ACCEPTANCE_CONSENT_VERSION, customerUnitPrice, proposalDocumentHash, readProposalSnapshot } from './proposal-document-snapshot';
import { toChangeOrderComparison, type ChangeOrderComparison } from '../change-orders/change-order-comparison';

export interface ProposalWithRelations extends Proposal {
  acceptance: ProposalAcceptance | null;
  company: Company;
  project: {
    id: string;
    title: string;
    description: string | null;
    projectType: ProjectType;
    clientId: string | null;
    client: { id: string; name: string; email: string | null } | null;
    assets: Asset[];
  };
  estimate: Estimate & {
    lineItems: EstimateLineItem[];
    changeOrder: ChangeOrder | null;
  };
}

interface SharedLineItemDto {
  name: string;
  description: string | null;
  category: string;
  quantity: number;
  unit: string;
  unit_cost: number;
  unit_price?: number;
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
  assumptions?: string | null;
  exclusions?: string | null;
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
  changes_requested_at?: string | null;
  requested_changes_message?: string | null;
  response_message?: string | null;
}

export function toAcceptanceDto(acceptance: ProposalAcceptance) {
  return {
    signer_name: acceptance.signerName,
    accepted_at: acceptance.acceptedAt.toISOString(),
    document_hash: acceptance.documentHash,
    estimate_version: acceptance.estimateVersion,
    consent_text: acceptance.consentText,
    consent_version: acceptance.consentVersion,
    identity_assurance: 'self_attested' as const,
  };
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
  document_captured_at?: string;
  document_capture_reason?: 'sent' | 'legacy_backfill';
  document_hash?: string | null;
  acceptance?: ReturnType<typeof toAcceptanceDto> | null;
  change_order?: ChangeOrderComparison;
  approval_consent_text?: string;
  approval_consent_version?: string;
}

export function toSharedProposalDto(proposal: ProposalWithRelations): SharedProposalPageDto {
  if (proposal.sentSnapshot !== null && proposal.sentSnapshot !== undefined) {
    const snapshot = readProposalSnapshot(proposal.sentSnapshot);
    return {
      ...snapshot.content,
      estimate: {
        ...snapshot.content.estimate,
        // Derive the customer rate without rewriting legacy stored snapshots
        // (or their signed hashes), which historically included internal cost.
        line_items: snapshot.content.estimate.line_items.map((item) => ({
          ...item, unit_cost: customerUnitPrice(item.quantity, item.line_total),
          unit_price: customerUnitPrice(item.quantity, item.line_total),
        })),
      },
      proposal: {
        ...snapshot.content.proposal,
        status: proposal.status.toLowerCase(),
        sent_at: proposal.sentAt?.toISOString() ?? null,
        viewed_at: proposal.viewedAt?.toISOString() ?? null,
        responded_at: proposal.respondedAt?.toISOString() ?? null,
        changes_requested_at: proposal.changesRequestedAt?.toISOString() ?? null,
        requested_changes_message: proposal.requestedChangesMessage,
        response_message: proposal.responseMessage,
      },
      document_captured_at: snapshot.captured_at,
      document_capture_reason: snapshot.capture_reason,
      document_hash: proposalDocumentHash(proposal.sentSnapshot),
      acceptance: proposal.acceptance ? toAcceptanceDto(proposal.acceptance) : null,
      approval_consent_text: ACCEPTANCE_CONSENT_TEXT,
      approval_consent_version: ACCEPTANCE_CONSENT_VERSION,
    };
  }
  return toLiveSharedProposalDto(proposal);
}

/** Used only before first send, while the parent estimate is locked. */
export function toLiveSharedProposalDto(proposal: ProposalWithRelations): SharedProposalPageDto {
  const { company, project, estimate } = proposal;

  const lineItems: SharedLineItemDto[] = estimate.lineItems.map((item) => ({
    name: item.name,
    description: item.description,
    category: item.category.toLowerCase(),
    quantity: Number(item.quantity),
    unit: item.unit,
    unit_cost: customerUnitPrice(Number(item.quantity), Number(item.lineTotal)),
    unit_price: customerUnitPrice(Number(item.quantity), Number(item.lineTotal)),
    line_total: Number(item.lineTotal),
  }));

  const beforeAfterImages: SharedBeforeAfterImageDto[] = project.assets.map((asset) => ({
    asset_id: asset.id,
    asset_type: asset.assetType.toLowerCase(),
    url: asset.url,
    sort_order: asset.sortOrder,
  }));

  return {
    ...(estimate.changeOrder ? { change_order: toChangeOrderComparison(estimate.changeOrder, estimate) } : {}),
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
      assumptions: estimate.assumptions,
      exclusions: estimate.exclusions,
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
