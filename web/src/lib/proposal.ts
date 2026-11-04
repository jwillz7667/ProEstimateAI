/**
 * Types and helpers for the public proposal share page.
 * Mirrors the backend `SharedProposalPageDto` shape 1:1 (snake_case).
 */
import { fetchAPI } from "./api";

export type ProposalStatus =
  | "draft"
  | "sent"
  | "viewed"
  | "approved"
  | "declined"
  | "expired";

export interface SharedLineItem {
  name: string;
  description: string | null;
  category: "materials" | "labor" | "other" | string;
  quantity: number;
  unit: string;
  unit_cost: number;
  unit_price?: number;
  line_total: number;
}

export interface SharedCompany {
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

export interface SharedProject {
  title: string;
  description: string | null;
  project_type: string;
}

export interface SharedEstimate {
  subtotal_materials: number;
  subtotal_labor: number;
  subtotal_other: number;
  tax_amount: number;
  discount_amount: number;
  total_amount: number;
  line_items: SharedLineItem[];
  assumptions?: string | null;
  exclusions?: string | null;
}

export interface SharedProposalMeta {
  title: string | null;
  proposal_number: string | null;
  status: ProposalStatus;
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

export interface ProposalAcceptance {
  signer_name: string;
  accepted_at: string;
  document_hash: string;
  estimate_version: number;
  consent_text: string;
  consent_version: string;
  identity_assurance: "self_attested";
}

export interface SharedBeforeAfterImage {
  asset_id: string;
  asset_type: string;
  url: string;
  sort_order: number;
}

export interface SharedProposalPage {
  company: SharedCompany;
  project: SharedProject;
  estimate: SharedEstimate;
  proposal: SharedProposalMeta;
  before_after_images: SharedBeforeAfterImage[];
  document_hash?: string | null;
  document_captured_at?: string;
  document_capture_reason?: "sent" | "legacy_backfill";
  approval_consent_text?: string;
  approval_consent_version?: string;
  acceptance?: ProposalAcceptance | null;
  change_order?: ChangeOrderComparison;
}

export interface ChangeOrderComparison {
  id: string;
  title: string;
  reason: string;
  currency_code: "USD";
  base_estimate_number: string;
  base_version: number;
  base_document_hash: string;
  base_total: number;
  new_total: number;
  change_amount: number;
  subtotal_delta: number;
  tax_delta: number;
  discount_delta: number;
  base_scope: {
    line_items: Array<{ name: string; description: string | null; quantity: number; unit: string; line_total: number }>;
    assumptions: string | null;
    exclusions: string | null;
  };
  billing_effect: "additional_invoice" | "credit_note" | "included_in_first_invoice" | "no_price_change";
}

export function changeOrderBillingExplanation(comparison: ChangeOrderComparison): string {
  switch (comparison.billing_effect) {
    case "additional_invoice": return "This increase will be billed separately after approval. The revised contract total below is not a second bill for the full project.";
    case "credit_note": return "This reduction will be recorded as a contract credit after approval. A credit is not a cash refund; your contractor can explain any remaining credit balance.";
    case "included_in_first_invoice": return "This change will be included in the first invoice for the revised contract total. It is not a separate payment request.";
    case "no_price_change": return "This changes the agreed scope without changing the contract price. Approval does not create an additional charge.";
  }
}

export async function getSharedProposal(
  token: string
): Promise<SharedProposalPage> {
  return fetchAPI<SharedProposalPage>(
    `/proposals/share/${encodeURIComponent(token)}`,
  );
}

export type ProposalDecision = "approved" | "declined" | "changes_requested";

export async function respondToSharedProposal(
  token: string,
  decision: ProposalDecision,
  message?: string,
  acknowledgement?: { signer_name: string; acceptance_consent: true; consent_version: string; document_hash: string },
  documentHash?: string,
): Promise<SharedProposalPage> {
  return fetchAPI<SharedProposalPage>(
    `/proposals/share/${encodeURIComponent(token)}/respond`,
    {
      method: "POST",
      body: JSON.stringify({
        decision,
        message: message && message.length > 0 ? message : null,
        ...(acknowledgement ?? {}),
        ...(documentHash ? { document_hash: documentHash } : {}),
      }),
    },
  );
}

// ─── Presentation helpers ───────────────────────────────────────────────────

export function formatCurrency(value: number): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(value);
}

export function formatQuantity(value: number): string {
  return Number.isInteger(value)
    ? value.toString()
    : value.toLocaleString("en-US", {
        minimumFractionDigits: 1,
        maximumFractionDigits: 2,
      });
}

/** Never display the private unit_cost field from older servers/snapshots. */
export function customerUnitPriceLabel(item: SharedLineItem): string | null {
  if (!Number.isFinite(item.quantity) || !Number.isFinite(item.line_total) || item.quantity <= 0) return null;
  const effective = item.line_total / item.quantity;
  const cents = Math.round(effective * 100);
  if (BigInt(cents) * BigInt(Math.round(item.quantity * 100)) !== BigInt(Math.round(item.line_total * 100)) * BigInt(100)) return null;
  return formatCurrency(cents / 100);
}

export function formatDate(iso: string | null): string | null {
  if (!iso) return null;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "long",
  }).format(date);
}

export function isProposalOpen(proposal: SharedProposalMeta): boolean {
  return !proposal.changes_requested_at && (proposal.status === "sent" || proposal.status === "viewed");
}

export function isProposalExpired(proposal: SharedProposalMeta): boolean {
  // Expiration closes an unanswered offer; it never replaces a final decision.
  if (proposal.status === "approved" || proposal.status === "declined") return false;
  if (proposal.status === "expired") return true;
  if (!proposal.expires_at) return false;
  const expires = new Date(proposal.expires_at);
  return !Number.isNaN(expires.getTime()) && expires.getTime() <= Date.now();
}

/** Accept only web links, including when old company records predate validation. */
export function safeWebsiteURL(value: string | null): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    return url.protocol === "https:" || url.protocol === "http:" ? url.href : null;
  } catch {
    return null;
  }
}

/**
 * Split line items into their category buckets, preserving order.
 */
export function groupLineItems(items: SharedLineItem[]) {
  const materials = items.filter((i) => i.category === "materials");
  const labor = items.filter((i) => i.category === "labor");
  const other = items.filter(
    (i) => i.category !== "materials" && i.category !== "labor",
  );
  return { materials, labor, other };
}
