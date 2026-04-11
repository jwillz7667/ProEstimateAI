import { Proposal } from '@prisma/client';

export interface ProposalDto {
  id: string;
  estimate_id: string;
  project_id: string;
  company_id: string;
  proposal_number: string | null;
  title: string | null;
  status: string;
  share_token: string | null;
  hero_image_url: string | null;
  intro_text: string | null;
  scope_of_work: string | null;
  timeline_text: string | null;
  terms_and_conditions: string | null;
  footer_text: string | null;
  client_message: string | null;
  pdf_asset_id: string | null;
  sent_at: string | null;
  viewed_at: string | null;
  responded_at: string | null;
  expires_at: string | null;
  created_at: string;
}

export function toProposalDto(proposal: Proposal): ProposalDto {
  return {
    id: proposal.id,
    estimate_id: proposal.estimateId,
    project_id: proposal.projectId,
    company_id: proposal.companyId,
    proposal_number: proposal.proposalNumber ?? null,
    title: proposal.title ?? null,
    status: proposal.status.toLowerCase(),
    share_token: proposal.shareToken,
    hero_image_url: proposal.heroImageUrl,
    intro_text: proposal.introText ?? null,
    scope_of_work: proposal.scopeOfWork ?? null,
    timeline_text: proposal.timelineText ?? null,
    terms_and_conditions: proposal.termsAndConditions,
    footer_text: proposal.footerText ?? null,
    client_message: proposal.clientMessage,
    pdf_asset_id: proposal.pdfAssetId ?? null,
    sent_at: proposal.sentAt ? proposal.sentAt.toISOString() : null,
    viewed_at: proposal.viewedAt ? proposal.viewedAt.toISOString() : null,
    responded_at: proposal.respondedAt ? proposal.respondedAt.toISOString() : null,
    expires_at: proposal.expiresAt ? proposal.expiresAt.toISOString() : null,
    created_at: proposal.createdAt.toISOString(),
  };
}
