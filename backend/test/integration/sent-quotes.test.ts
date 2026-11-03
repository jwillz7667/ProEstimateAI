import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../../src/config/database";
import * as proposals from "../../src/modules/proposals/proposals.service";
import * as estimates from "../../src/modules/estimates/estimates.service";
import * as items from "../../src/modules/estimate-line-items/estimate-line-items.service";
import { toSharedProposalDto } from "../../src/modules/proposals/proposals.share-dto";

const itemInput = {
  category: "materials" as const, name: "Cabinet hardware", quantity: 2,
  unit: "each", unit_cost: 10, markup_percent: 10, tax_rate: 0.1, sort_order: 0,
};

async function fixture() {
  const company = await prisma.company.create({ data: { name: `Quote ${randomUUID()}` } });
  const user = await prisma.user.create({ data: { companyId: company.id, fullName: "Estimator", email: `${randomUUID()}@example.test` } });
  const project = await prisma.project.create({ data: { companyId: company.id, title: "Kitchen", projectType: "KITCHEN" } });
  const estimate = await estimates.create(company.id, user.id, {
    project_id: project.id, title: "Kitchen quote", assumptions: "Existing framing is sound", exclusions: "Permits", notes: "Agreed scope",
  });
  const line = await items.create(estimate.id, company.id, itemInput);
  const proposal = await proposals.create(company.id, {
    estimate_id: estimate.id, terms_and_conditions: "Payment on completion", client_message: "Please review your kitchen quote",
  });
  const fresh = await estimates.getById(estimate.id, company.id);
  return { company, user, project, estimate: fresh, line, proposal };
}

async function send(t: Awaited<ReturnType<typeof fixture>>) {
  return proposals.send(t.proposal.id, t.company.id, t.user.id, { expected_estimate_updated_at: t.estimate.updatedAt.toISOString() });
}

beforeEach(async () => {
  await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE');
});

describe("sent quote documents", () => {
  it("freezes first send and rejects header, lifecycle, item and individual deletion mutations", async () => {
    const t = await fixture();
    const sent = await send(t);
    expect(sent.status).toBe("SENT");
    expect((await estimates.getById(t.estimate.id, t.company.id)).status).toBe("SENT");
    const original = toSharedProposalDto(await proposals.getByShareToken(sent.shareToken!));
    expect(original.estimate.total_amount).toBe(24.2);
    expect(original.document_capture_reason).toBe("sent");
    for (const action of [
      () => estimates.update(t.estimate.id, t.company.id, t.user.id, { status: "draft" }),
      () => estimates.update(t.estimate.id, t.company.id, t.user.id, { total_amount: 1, notes: "Changed" }),
      () => items.update(t.line.id, t.company.id, { unit_cost: 999 }),
      () => items.create(t.estimate.id, t.company.id, itemInput),
      () => items.remove(t.line.id, t.company.id),
      () => proposals.update(sent.id, t.company.id, { terms_and_conditions: "Changed" }),
      () => proposals.remove(sent.id, t.company.id),
      () => estimates.remove(t.estimate.id, t.company.id),
    ]) await expect(action()).rejects.toMatchObject({ statusCode: 409 });
    expect(toSharedProposalDto(await proposals.getByShareToken(sent.shareToken!))).toEqual(original);
  });

  it("does not publish an editable draft token, while authenticated preview still works", async () => {
    const t = await fixture();
    await expect(proposals.getByShareToken(t.proposal.shareToken!)).rejects.toMatchObject({ statusCode: 404 });
    await expect(proposals.respondToProposal(t.proposal.shareToken!, { decision: "approved" })).rejects.toMatchObject({ statusCode: 400 });
    expect(toSharedProposalDto(await proposals.getForRendering(t.proposal.id, t.company.id)).estimate.total_amount).toBe(24.2);
    expect((await proposals.getById(t.proposal.id, t.company.id)).sentSnapshot).toBeNull();
  });

  it("rejects stale reviewed prices without publishing or partially changing the draft", async () => {
    const t = await fixture();
    await items.update(t.line.id, t.company.id, { quantity: 4 });
    await expect(send(t)).rejects.toMatchObject({ statusCode: 409 });
    const unchanged = await proposals.getById(t.proposal.id, t.company.id);
    expect(unchanged.status).toBe("DRAFT");
    expect(unchanged.sentSnapshot).toBeNull();
    expect((await estimates.getById(t.estimate.id, t.company.id)).status).toBe("DRAFT");
  });

  it("preserves public and PDF document data after company/project/live data changes", async () => {
    const t = await fixture();
    await proposals.update(t.proposal.id, t.company.id, { title: "Original proposal", scope_of_work: "Install hardware", footer_text: "Original footer" });
    await send(t);
    const before = toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!));
    await prisma.company.update({ where: { id: t.company.id }, data: { name: "Renamed business", address: "New address" } });
    await prisma.project.update({ where: { id: t.project.id }, data: { title: "Renamed project", description: "New description" } });
    // Simulate an out-of-band import, bypassing all protected application APIs.
    await prisma.estimate.update({ where: { id: t.estimate.id }, data: { totalAmount: 99999 } });
    await prisma.estimateLineItem.update({ where: { id: t.line.id }, data: { name: "Imported item", unitCost: 999 } });
    expect(toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!))).toEqual(before);
    expect(toSharedProposalDto(await proposals.getForRendering(t.proposal.id, t.company.id))).toEqual(before);
  });

  it("resends a viewed quote without replacing its content, first send or first-view dates", async () => {
    const t = await fixture();
    await send(t);
    const before = await proposals.getByShareToken(t.proposal.shareToken!);
    const resent = await send(t); // Original reviewed timestamp must be retry-safe.
    expect(resent.sentSnapshot).toEqual(before.sentSnapshot);
    expect(resent.sentAt).toEqual(before.sentAt);
    expect(resent.viewedAt).toEqual(before.viewedAt);
    expect(resent.status).toBe("VIEWED");
    await expect(proposals.send(t.proposal.id, t.company.id, t.user.id, { client_message: "Different offer" })).rejects.toMatchObject({ statusCode: 409 });
  });

  it("serializes first send against line item edits into one coherent accepted version", async () => {
    const t = await fixture();
    const results = await Promise.allSettled([
      proposals.send(t.proposal.id, t.company.id, t.user.id),
      items.update(t.line.id, t.company.id, { quantity: 4 }),
    ]);
    expect(results[0].status).toBe("fulfilled");
    if (results[1].status === "rejected") expect(results[1].reason.statusCode).toBe(409);
    const shared = toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!));
    const total = Number((await estimates.getById(t.estimate.id, t.company.id)).totalAmount);
    expect(shared.estimate.total_amount).toBe(total);
    expect(shared.estimate.line_items[0].quantity).toBe(results[1].status === "fulfilled" ? 4 : 2);
    expect(shared.estimate.total_amount).toBe(results[1].status === "fulfilled" ? 48.4 : 24.2);
  });

  it("allows only one of two prepared proposals to freeze the same draft", async () => {
    const t = await fixture();
    const second = await proposals.create(t.company.id, { estimate_id: t.estimate.id });
    const results = await Promise.allSettled([
      send(t), proposals.send(second.id, t.company.id, t.user.id),
    ]);
    expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    const rejected = results.find((result) => result.status === "rejected");
    expect(rejected?.status === "rejected" && rejected.reason.statusCode).toBe(409);
    expect(await prisma.proposal.count({ where: { estimateId: t.estimate.id, status: "SENT" } })).toBe(1);
  });

  it("keeps one authoritative response under parallel viewing and conflicting decisions", async () => {
    const t = await fixture();
    await send(t);
    const results = await Promise.all([
      proposals.respondToProposal(t.proposal.shareToken!, { decision: "approved", message: "Approved by customer" }),
      proposals.respondToProposal(t.proposal.shareToken!, { decision: "declined" }),
      proposals.getByShareToken(t.proposal.shareToken!),
    ]);
    expect(results[0].status).toBe(results[1].status);
    expect(["VIEWED", results[0].status]).toContain(results[2].status);
    expect((await proposals.getByShareToken(t.proposal.shareToken!)).status).toBe(results[0].status);
    const shared = toSharedProposalDto(results[0]);
    expect(shared.proposal.client_message).toBe("Please review your kitchen quote");
    expect(shared.proposal.responded_at).toMatch(/^\d{4}-/);
    expect(await prisma.activityLogEntry.count({ where: { projectId: t.project.id, action: { in: ["PROPOSAL_APPROVED", "PROPOSAL_DECLINED"] } } })).toBe(1);
    await expect(proposals.send(t.proposal.id, t.company.id, t.user.id)).rejects.toThrow(/new proposal/);
  });

  it("captures legacy sent records honestly once and blocks their draft edit loophole", async () => {
    const t = await fixture();
    await prisma.proposal.update({ where: { id: t.proposal.id }, data: { status: "SENT", sentAt: new Date("2026-10-01T00:00:00Z") } });
    await expect(items.update(t.line.id, t.company.id, { unit_cost: 900 })).rejects.toMatchObject({ statusCode: 409 });
    await expect(estimates.update(t.estimate.id, t.company.id, t.user.id, { status: "draft" })).rejects.toMatchObject({ statusCode: 409 });
    const shared = toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!));
    expect(shared.document_capture_reason).toBe("legacy_backfill");
    expect(shared.document_captured_at).not.toBe("2026-10-01T00:00:00.000Z");
    expect((await estimates.getById(t.estimate.id, t.company.id)).status).toBe("SENT");
  });

  it("backfills an existing sent document with the same public DTO shape as first send", async () => {
    const t = await fixture();
    await prisma.proposal.update({ where: { id: t.proposal.id }, data: { status: "SENT", sentAt: new Date("2026-10-01T00:00:00Z") } });
    const migration = readFileSync("prisma/migrations/20261103130000_protect_sent_quote_versions/migration.sql", "utf8");
    const backfill = migration.slice(migration.indexOf('UPDATE "Proposal"'), migration.indexOf('-- Older send paths'));
    await prisma.$executeRawUnsafe(backfill);
    const shared = toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!));
    expect(shared.document_capture_reason).toBe("legacy_backfill");
    expect(shared.estimate.total_amount).toBe(24.2);
    expect(shared.estimate.line_items[0].name).toBe("Cabinet hardware");
    expect(shared.proposal.sent_at).toBe("2026-10-01T00:00:00.000Z");
  });

  it("enforces append-only stored snapshots even on an accidental direct database update", async () => {
    const t = await fixture();
    await send(t);
    await expect(prisma.proposal.update({ where: { id: t.proposal.id }, data: { sentSnapshot: { replaced: true } } })).rejects.toThrow();
    expect(toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!)).estimate.total_amount).toBe(24.2);
  });

  it("fails closed on an invalid imported snapshot instead of displaying mutable live prices", async () => {
    const t = await fixture();
    await prisma.proposal.update({ where: { id: t.proposal.id }, data: { status: "SENT", sentSnapshot: { invalid: true } } });
    await expect(proposals.getByShareToken(t.proposal.shareToken!)).rejects.toMatchObject({ statusCode: 409 });
  });

  it("retains tenant boundaries for sending, rendering, metadata and revision creation", async () => {
    const t = await fixture();
    const other = await fixture();
    for (const action of [
      () => proposals.send(t.proposal.id, other.company.id, other.user.id),
      () => proposals.getForRendering(t.proposal.id, other.company.id),
      () => proposals.update(t.proposal.id, other.company.id, { title: "Intrusion" }),
      () => estimates.revise(t.estimate.id, other.company.id, other.user.id, randomUUID()),
    ]) await expect(action()).rejects.toMatchObject({ statusCode: 404 });
  });
});

describe("linked estimate revisions", () => {
  it("retires the previous pending link only when its replacement is actually sent", async () => {
    const t = await fixture();
    await send(t);
    const original = toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!));
    const revision = await estimates.revise(t.estimate.id, t.company.id, t.user.id, randomUUID());
    expect((await proposals.getByShareToken(t.proposal.shareToken!)).status).toBe("VIEWED");
    const replacement = await proposals.create(t.company.id, { estimate_id: revision.id });
    await proposals.send(replacement.id, t.company.id, t.user.id);
    const previous = toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!));
    expect(previous.proposal.status).toBe("expired");
    expect(previous.estimate).toEqual(original.estimate);
    await expect(proposals.respondToProposal(t.proposal.shareToken!, { decision: "approved" })).rejects.toMatchObject({ statusCode: 400 });
    expect((await proposals.respondToProposal(replacement.shareToken!, { decision: "approved" })).status).toBe("APPROVED");
  });

  it("keeps previously accepted history intact when sending a revision", async () => {
    const t = await fixture();
    await send(t);
    await proposals.respondToProposal(t.proposal.shareToken!, { decision: "approved" });
    const original = toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!));
    const revision = await estimates.revise(t.estimate.id, t.company.id, t.user.id, randomUUID());
    const replacement = await proposals.create(t.company.id, { estimate_id: revision.id });
    await proposals.send(replacement.id, t.company.id, t.user.id);
    expect(toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!))).toEqual(original);
    expect((await estimates.getById(t.estimate.id, t.company.id)).status).toBe("APPROVED");
  });

  it("serializes sibling revision sends so only the first replaces the pending version", async () => {
    const t = await fixture();
    await send(t);
    const first = await estimates.revise(t.estimate.id, t.company.id, t.user.id, randomUUID());
    const second = await estimates.revise(t.estimate.id, t.company.id, t.user.id, randomUUID());
    const a = await proposals.create(t.company.id, { estimate_id: first.id });
    const b = await proposals.create(t.company.id, { estimate_id: second.id });
    const results = await Promise.allSettled([
      proposals.send(a.id, t.company.id, t.user.id), proposals.send(b.id, t.company.id, t.user.id),
    ]);
    expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    const rejected = results.find((result) => result.status === "rejected");
    expect(rejected?.status === "rejected" && rejected.reason.statusCode).toBe(409);
    expect((await proposals.getByShareToken(t.proposal.shareToken!)).status).toBe("EXPIRED");
  });

  it("copies exact scope, prices and item hierarchy to a separate draft, with safe request retries", async () => {
    const t = await fixture();
    const child = await items.create(t.estimate.id, t.company.id, { ...itemInput, name: "Fitting labor", category: "labor", parent_line_item_id: t.line.id });
    await proposals.send(t.proposal.id, t.company.id, t.user.id);
    const source = await estimates.getById(t.estimate.id, t.company.id);
    const originalShared = toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!));
    const key = randomUUID();
    const results = await Promise.all([
      estimates.revise(source.id, t.company.id, t.user.id, key),
      estimates.revise(source.id, t.company.id, t.user.id, key),
    ]);
    expect(results[0].id).toBe(results[1].id);
    const revision = results[0];
    expect(revision.id).not.toBe(source.id);
    expect(revision.status).toBe("DRAFT");
    expect(revision.revisesEstimateId).toBe(source.id);
    expect(revision.version).toBe(source.version + 1);
    expect(revision.estimateNumber).not.toBe(source.estimateNumber);
    expect(revision.assumptions).toBe(source.assumptions);
    expect(revision.exclusions).toBe(source.exclusions);
    expect(revision.notes).toBe(source.notes);
    expect(revision.totalAmount.toString()).toBe(source.totalAmount.toString());
    const copied = await prisma.estimateLineItem.findMany({ where: { estimateId: revision.id } });
    const parentCopy = copied.find((item) => item.name === t.line.name)!;
    const childCopy = copied.find((item) => item.name === child.name)!;
    expect(parentCopy.id).not.toBe(t.line.id);
    expect(childCopy.parentLineItemId).toBe(parentCopy.id);
    expect(childCopy.parentLineItemId).not.toBe(t.line.id);
    await items.update(parentCopy.id, t.company.id, { unit_cost: 500 });
    expect(toSharedProposalDto(await proposals.getByShareToken(t.proposal.shareToken!))).toEqual(originalShared);
    expect(await estimates.revise(source.id, t.company.id, t.user.id, key)).toMatchObject({ id: revision.id });
  });

  it("does not create a revision for an editable draft", async () => {
    const t = await fixture();
    await expect(estimates.revise(t.estimate.id, t.company.id, t.user.id, randomUUID())).rejects.toMatchObject({ statusCode: 409 });
    expect(await prisma.estimate.count({ where: { companyId: t.company.id } })).toBe(1);
  });

  it("rejects reused revision keys for different sources without unique-key errors", async () => {
    const t = await fixture();
    await send(t);
    const second = await estimates.create(t.company.id, t.user.id, { project_id: t.project.id });
    await estimates.update(second.id, t.company.id, t.user.id, { status: "sent" });
    const key = randomUUID();
    const results = await Promise.allSettled([
      estimates.revise(t.estimate.id, t.company.id, t.user.id, key),
      estimates.revise(second.id, t.company.id, t.user.id, key),
    ]);
    expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    const rejected = results.find((result) => result.status === "rejected");
    expect(rejected?.status === "rejected" && rejected.reason.statusCode).toBe(409);
  });
});
