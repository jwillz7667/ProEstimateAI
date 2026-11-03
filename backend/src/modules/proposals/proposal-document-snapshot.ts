import { z } from "zod";
import { createHash } from "node:crypto";
import { ConflictError } from "../../lib/errors";
import { changeOrderComparisonSchema } from "../change-orders/change-order-comparison";

const nullableText = z.string().nullable();
const money = z.number().finite();

// A whitelist of the document a recipient can see. Never snapshot a raw
// Company/User row: those also contain private account and billing details.
export const sharedProposalContentSchema = z.object({
  company: z.object({
    name: z.string(), phone: nullableText, email: nullableText,
    address: nullableText, city: nullableText, state: nullableText, zip: nullableText,
    logo_url: nullableText, primary_color: nullableText, website_url: nullableText,
  }),
  project: z.object({ title: z.string(), description: nullableText, project_type: z.string() }),
  estimate: z.object({
    subtotal_materials: money, subtotal_labor: money, subtotal_other: money,
    tax_amount: money, discount_amount: money, total_amount: money,
    line_items: z.array(z.object({
      name: z.string(), description: nullableText, category: z.string(),
      quantity: money, unit: z.string(), unit_cost: money, line_total: money,
      unit_price: money.optional(),
    })),
    assumptions: nullableText.optional(), exclusions: nullableText.optional(),
  }),
  proposal: z.object({
    title: nullableText, proposal_number: nullableText, status: z.string(),
    intro_text: nullableText, scope_of_work: nullableText, timeline_text: nullableText,
    terms_and_conditions: nullableText, footer_text: nullableText,
    client_message: nullableText, hero_image_url: nullableText,
    expires_at: nullableText, sent_at: nullableText, viewed_at: nullableText, responded_at: nullableText,
  }),
  before_after_images: z.array(z.object({
    asset_id: z.string(), asset_type: z.string(), url: z.string(), sort_order: z.number().int(),
  })),
  change_order: changeOrderComparisonSchema.optional(),
});

const snapshotSchema = z.object({
  schema_version: z.literal(1),
  estimate_id: z.string(),
  estimate_version: z.number().int().positive(),
  captured_at: z.string().datetime(),
  capture_reason: z.enum(["sent", "legacy_backfill"]),
  content: sharedProposalContentSchema,
});

export type ProposalDocumentSnapshot = z.infer<typeof snapshotSchema>;

/** A corrupt historical document must fail closed, never silently show live prices. */
export function readProposalSnapshot(value: unknown): ProposalDocumentSnapshot {
  const parsed = snapshotSchema.safeParse(value);
  if (!parsed.success) {
    throw new ConflictError("This proposal's saved version could not be loaded. Contact support before responding.");
  }
  return parsed.data;
}

export function canonicalJSON(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJSON).join(",")}]`;
  if (value !== null && typeof value === "object") {
    const record = value as Record<string, unknown>;
    return `{${Object.keys(record).sort().map((key) => `${JSON.stringify(key)}:${canonicalJSON(record[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

export function hashCanonicalValue(value: unknown): string {
  return createHash("sha256").update(canonicalJSON(value)).digest("hex");
}

/** Includes the exact frozen version and capture timestamp, independent of JSON key order. */
export function proposalDocumentHash(value: unknown): string {
  return hashCanonicalValue(readProposalSnapshot(value));
}

/** Public unit prices are markup-inclusive; private cost is never a fallback. */
export function customerUnitPrice(quantity: number, lineTotal: number) { return quantity > 0 ? lineTotal / quantity : 0; }

export function canShowCustomerUnitPrice(quantity: number, lineTotal: number): boolean {
  if (!Number.isFinite(quantity) || !Number.isFinite(lineTotal) || quantity <= 0) return false;
  const rateCents = BigInt(Math.round(customerUnitPrice(quantity, lineTotal) * 100));
  return rateCents * BigInt(Math.round(quantity * 100)) === BigInt(Math.round(lineTotal * 100)) * 100n;
}

export const ACCEPTANCE_CONSENT_VERSION = "quote-acceptance-v1";
export const ACCEPTANCE_CONSENT_TEXT = "I have reviewed this proposal, including its scope, price and terms. By typing my name and approving, I agree to this version and intend my typed name to be my electronic acknowledgement.";
