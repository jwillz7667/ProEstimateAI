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
}

export async function getSharedProposal(
  token: string
): Promise<SharedProposalPage> {
  return fetchAPI<SharedProposalPage>(
    `/proposals/share/${encodeURIComponent(token)}`,
  );
}

export type ProposalDecision = "approved" | "declined";

export async function respondToSharedProposal(
  token: string,
  decision: ProposalDecision,
  message?: string,
): Promise<SharedProposalPage> {
  return fetchAPI<SharedProposalPage>(
    `/proposals/share/${encodeURIComponent(token)}/respond`,
    {
      method: "POST",
      body: JSON.stringify({
        decision,
        message: message && message.length > 0 ? message : null,
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

export function formatDate(iso: string | null): string | null {
  if (!iso) return null;
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) return null;
  return new Intl.DateTimeFormat("en-US", {
    dateStyle: "long",
  }).format(date);
}

export function isProposalOpen(proposal: SharedProposalMeta): boolean {
  return proposal.status === "sent" || proposal.status === "viewed";
}

export function isProposalExpired(proposal: SharedProposalMeta): boolean {
  if (!proposal.expires_at) return false;
  const expires = new Date(proposal.expires_at);
  return !Number.isNaN(expires.getTime()) && expires < new Date();
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
