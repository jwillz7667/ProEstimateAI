import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../../src/config/database";
import * as estimates from "../../src/modules/estimates/estimates.service";
import * as items from "../../src/modules/estimate-line-items/estimate-line-items.service";
import * as proposals from "../../src/modules/proposals/proposals.service";
import { toSharedProposalDto } from "../../src/modules/proposals/proposals.share-dto";
import { proposalDocumentHash, canShowCustomerUnitPrice } from "../../src/modules/proposals/proposal-document-snapshot";
import { normalizeEstimateLineMoney, calculateEstimateTotals } from "../../src/lib/estimate-money";
import { updateEstimateSchema } from "../../src/modules/estimates/estimates.validators";

async function fixture(withItem = true) {
  const company = await prisma.company.create({ data: { name: "Canonical quote" } });
  const user = await prisma.user.create({ data: { companyId: company.id, fullName: "Estimator", email: `${randomUUID()}@example.test` } });
  const project = await prisma.project.create({ data: { companyId: company.id, projectType: "CUSTOM", title: "Work" } });
  const estimate = await estimates.create(company.id, user.id, { project_id: project.id, assumptions: "Accessible framing", exclusions: "Permit fees" });
  const line = withItem ? await items.create(estimate.id, company.id, { name: "Material", category: "materials", quantity: 2, unit: "each", unit_cost: 10, markup_percent: 10, tax_rate: 0.1, sort_order: 0 }) : null;
  const proposal = await proposals.create(company.id, { estimate_id: estimate.id });
  return { company, user, project, estimate, line, proposal };
}

beforeEach(async () => { await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE'); });

describe("canonical estimate amounts", () => {
  it("rejects caller totals that disagree with priced line items without partial writes", async () => {
    const t = await fixture();
    const before = await estimates.getById(t.estimate.id, t.company.id);
    for (const input of [{ total_amount: 1 }, { subtotal_materials: 1 }, { subtotal_labor: 1 }, { subtotal_other: 1 }, { tax_amount: 999 }]) {
      await expect(estimates.update(t.estimate.id, t.company.id, t.user.id, { ...input, notes: "Should not save" })).rejects.toMatchObject({ statusCode: 400 });
    }
    const after = await estimates.getById(t.estimate.id, t.company.id);
    expect(after.totalAmount.toString()).toBe(before.totalAmount.toString());
    expect(after.notes).toBe(before.notes);
    expect(after.updatedAt).toEqual(before.updatedAt);
    const valid = await estimates.update(t.estimate.id, t.company.id, t.user.id, { subtotal_materials: 22, tax_amount: 2.2, total_amount: 24.2 });
    expect(Number(valid.totalAmount)).toBe(24.2);
    expect(Number((await estimates.update(t.estimate.id, t.company.id, t.user.id, { discount_amount: 4.2 })).totalAmount)).toBe(20);
  });

  it("cannot turn an empty draft into a header-only offer by overriding money", async () => {
    const t = await fixture(false);
    await expect(estimates.update(t.estimate.id, t.company.id, t.user.id, { total_amount: 100 })).rejects.toMatchObject({ statusCode: 400 });
    await expect(proposals.send(t.proposal.id, t.company.id, t.user.id)).rejects.toMatchObject({ statusCode: 400 });
    expect((await proposals.getById(t.proposal.id, t.company.id)).status).toBe("DRAFT");
  });

  it("uses stored precision for both manual and generated line math instead of unrounded floating sums", async () => {
    const t = await fixture(false);
    const row = { name: "Rounded", category: "materials" as const, quantity: 1.005, unit: "each", unit_cost: 0.005, markup_percent: 0, tax_rate: 0.0825, sort_order: 0 };
    await items.createBatch(t.estimate.id, t.company.id, [row, row, row]);
    const saved = await estimates.getById(t.estimate.id, t.company.id);
    expect(Number(saved.subtotalMaterials)).toBe(0.03);
    expect(Number(saved.totalAmount)).toBe(0.03);
    const normalized = normalizeEstimateLineMoney(row.quantity, row.unit_cost, row.markup_percent);
    const generated = calculateEstimateTotals([1, 2, 3].map(() => ({ ...normalized, category: "materials", taxRate: row.tax_rate })));
    expect(generated.totalAmount.toString()).toBe(saved.totalAmount.toString());
  });

  it("returns validation errors for scalar and aggregate decimal overflow", async () => {
    const t = await fixture(false);
    for (const input of [{ quantity: 100_000_000, unit_cost: 0 }, { quantity: 1, unit_cost: 10_000_000_000 }, { quantity: 1, unit_cost: 1, markup_percent: 1001 }]) {
      await expect(items.create(t.estimate.id, t.company.id, { category: "materials", name: "Too large", unit: "each", markup_percent: 0, tax_rate: 0, sort_order: 0, ...input })).rejects.toMatchObject({ statusCode: 400 });
    }
    await expect(items.createBatch(t.estimate.id, t.company.id, [1, 2].map(() => ({ category: "materials", name: "Aggregate overflow", unit: "each", quantity: 1, unit_cost: 6_000_000_000, markup_percent: 0, tax_rate: 0, sort_order: 0 })))).rejects.toMatchObject({ statusCode: 400 });
    expect(await prisma.estimateLineItem.count({ where: { estimateId: t.estimate.id } })).toBe(0);
    for (const key of ["subtotal_materials", "subtotal_labor", "subtotal_other", "tax_amount", "discount_amount", "total_amount", "contingency_amount"]) {
      expect(updateEstimateSchema.safeParse({ [key]: 10_000_000_000 }).success).toBe(false);
    }
    const valid = await items.create(t.estimate.id, t.company.id, { category: "labor", name: "Allowed markup", quantity: 1, unit: "job", unit_cost: 1, markup_percent: 1000, tax_rate: 0, sort_order: 0 });
    expect(Number(valid.lineTotal)).toBe(11);
  });

  it("repairs an inconsistent legacy draft but requires another explicit review before publishing", async () => {
    const t = await fixture();
    await prisma.estimate.update({ where: { id: t.estimate.id }, data: { totalAmount: 1 } });
    await expect(proposals.send(t.proposal.id, t.company.id, t.user.id)).rejects.toMatchObject({ statusCode: 409 });
    expect(Number((await estimates.getById(t.estimate.id, t.company.id)).totalAmount)).toBe(24.2);
    expect((await proposals.getById(t.proposal.id, t.company.id)).status).toBe("DRAFT");
    await expect(proposals.getByShareToken(t.proposal.shareToken!)).rejects.toMatchObject({ statusCode: 404 });
    await proposals.send(t.proposal.id, t.company.id, t.user.id);
    expect(toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!)).estimate.total_amount).toBe(24.2);
  });

  it("detects changed proposal terms and changed prices even if a timestamp is reused", async () => {
    const t = await fixture();
    const reviewed = await proposals.getById(t.proposal.id, t.company.id);
    await proposals.update(t.proposal.id, t.company.id, { terms_and_conditions: "Changed terms" });
    await expect(proposals.send(t.proposal.id, t.company.id, t.user.id, { draft_review_token: reviewed.draftReviewToken! })).rejects.toMatchObject({ statusCode: 409 });
    const current = await proposals.getById(t.proposal.id, t.company.id);
    const stamp = current.estimate.updatedAt;
    await items.update(t.line!.id, t.company.id, { unit_cost: 50 });
    await prisma.estimate.update({ where: { id: t.estimate.id }, data: { updatedAt: stamp } });
    await expect(proposals.send(t.proposal.id, t.company.id, t.user.id, { draft_review_token: current.draftReviewToken!, expected_estimate_updated_at: stamp.toISOString() })).rejects.toMatchObject({ statusCode: 409 });
  });

  it("invalidates timestamp-only reviews after narrative, ordering and contractor source checks", async () => {
    const t = await fixture();
    let previous = await estimates.getById(t.estimate.id, t.company.id);
    for (const patch of [{ description: "Updated customer-facing description" }, { name: "Revised material" }, { unit: "box" }, { sort_order: 3 }]) {
      await items.update(t.line!.id, t.company.id, patch);
      const current = await estimates.getById(t.estimate.id, t.company.id);
      expect(current.updatedAt.getTime()).toBeGreaterThan(previous.updatedAt.getTime());
      await expect(proposals.send(t.proposal.id, t.company.id, t.user.id, { expected_estimate_updated_at: previous.updatedAt.toISOString() })).rejects.toMatchObject({ statusCode: 409 });
      previous = current;
    }
    const line = await prisma.estimateLineItem.findUniqueOrThrow({ where: { id: t.line!.id } });
    await items.reviewPrice(line.id, t.company.id, t.user.id, { expected_name: line.name, expected_unit: line.unit, expected_unit_cost: Number(line.unitCost), expected_quantity: Number(line.quantity), price_confirmed: true, source_label: "Supplier invoice", source_url: null, quantity_confirmed: false });
    expect((await estimates.getById(t.estimate.id, t.company.id)).updatedAt.getTime()).toBeGreaterThan(previous.updatedAt.getTime());
  });

  it("redacts internal base costs and includes assumptions/exclusions without altering legacy hashes", async () => {
    const t = await fixture();
    await proposals.send(t.proposal.id, t.company.id, t.user.id);
    let shared = await proposals.getByShareToken(t.proposal.shareToken!);
    const dto = toSharedProposalDto(shared);
    expect(dto.estimate.line_items[0].unit_cost).toBe(11);
    expect(dto.estimate.line_items[0].unit_price).toBe(11);
    expect(dto.estimate.assumptions).toBe("Accessible framing");
    expect(dto.estimate.exclusions).toBe("Permit fees");
    expect(canShowCustomerUnitPrice(3, 1)).toBe(false);
    expect(canShowCustomerUnitPrice(2, 22)).toBe(true);
    // The exact SQL backfill format represents the old document with base cost.
    const legacyEstimate = await estimates.create(t.company.id, t.user.id, { project_id: t.project.id });
    await items.create(legacyEstimate.id, t.company.id, { name: "Legacy material", category: "materials", quantity: 2, unit: "each", unit_cost: 10, markup_percent: 10, tax_rate: 0, sort_order: 0 });
    const legacy = await proposals.create(t.company.id, { estimate_id: legacyEstimate.id });
    await prisma.proposal.update({ where: { id: legacy.id }, data: { status: "SENT" } });
    const migration = (await import("node:fs")).readFileSync("prisma/migrations/20261103130000_protect_sent_quote_versions/migration.sql", "utf8");
    await prisma.$executeRawUnsafe(migration.slice(migration.indexOf('UPDATE "Proposal"'), migration.indexOf('-- Older send paths')));
    shared = await proposals.getByShareToken(legacy.shareToken!);
    const hash = proposalDocumentHash(shared.sentSnapshot);
    const stored = JSON.stringify(shared.sentSnapshot);
    expect((shared.sentSnapshot as any).content.estimate.line_items[0].unit_cost).toBe(10);
    expect(toSharedProposalDto(shared).estimate.line_items[0].unit_cost).toBe(11);
    expect(proposalDocumentHash(shared.sentSnapshot)).toBe(hash);
    expect(JSON.stringify(shared.sentSnapshot)).toBe(stored);
  });
});
