import { Proposal, ProposalAcceptance, Estimate, ChangeOrder } from '@prisma/client';
import { proposalDocumentHash, readProposalSnapshot } from './proposal-document-snapshot';
import { toAcceptanceDto } from './proposals.share-dto';
import { currentProposalRecipient, proposalRecipientMatches } from './proposal-recipient';
import { toChangeOrderComparison, type ChangeOrderComparison } from '../change-orders/change-order-comparison';

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
  changes_requested_at: string | null;
  requested_changes_message: string | null;
  response_message: string | null;
  document_hash: string | null;
  acceptance: ReturnType<typeof toAcceptanceDto> | null;
  draft_review_token: string | null;
  recipient_client_id: string | null;
  recipient_name: string | null;
  recipient_email: string | null;
  recipient_matches_current: boolean | null;
  change_order: ChangeOrderComparison | null;
}

export function toProposalDto(proposal: Proposal & { acceptance?: ProposalAcceptance | null; draftReviewToken?: string | null; project?: { clientId: string | null; client: { id: string; name: string; email: string | null } | null }; estimate?: Estimate & { changeOrder?: ChangeOrder | null } }): ProposalDto {
  const draft = proposal.status === 'DRAFT' && !proposal.sentSnapshot && !proposal.sentAt;
  const recipient = draft && proposal.project ? currentProposalRecipient(proposal.project) : { clientId: proposal.sentRecipientClientId, name: proposal.sentRecipientName, email: proposal.sentRecipientEmail };
  const comparison = proposal.sentSnapshot ? readProposalSnapshot(proposal.sentSnapshot).content.change_order ?? null
    : draft && proposal.estimate?.changeOrder ? toChangeOrderComparison(proposal.estimate.changeOrder, proposal.estimate) : null;
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
    changes_requested_at: proposal.changesRequestedAt?.toISOString() ?? null,
    requested_changes_message: proposal.requestedChangesMessage,
    response_message: proposal.responseMessage,
    document_hash: proposal.sentSnapshot ? proposalDocumentHash(proposal.sentSnapshot) : null,
    acceptance: proposal.acceptance ? toAcceptanceDto(proposal.acceptance) : null,
    draft_review_token: proposal.draftReviewToken ?? null,
    recipient_client_id: recipient.clientId,
    recipient_name: recipient.name,
    recipient_email: recipient.email,
    recipient_matches_current: draft ? null : proposal.project ? proposalRecipientMatches({ ...proposal, project: proposal.project }) : null,
    change_order: comparison,
  };
}
