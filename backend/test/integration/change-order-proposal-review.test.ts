import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { prisma } from "../../src/config/database";
import * as estimates from "../../src/modules/estimates/estimates.service";
import * as items from "../../src/modules/estimate-line-items/estimate-line-items.service";
import * as proposals from "../../src/modules/proposals/proposals.service";
import { toSharedProposalDto } from "../../src/modules/proposals/proposals.share-dto";
import { toProposalDto } from "../../src/modules/proposals/proposals.dto";
import { ACCEPTANCE_CONSENT_VERSION, hashCanonicalValue, proposalDocumentHash, readProposalSnapshot } from "../../src/modules/proposals/proposal-document-snapshot";

vi.mock("../../src/lib/email", () => ({ sendProposalEmail: vi.fn().mockResolvedValue(undefined) }));

async function fixture() {
  const company = await prisma.company.create({ data: { name: "Change order review" } });
  const user = await prisma.user.create({ data: { companyId: company.id, fullName: "Owner", email: `${randomUUID()}@example.test` } });
  const client = await prisma.client.create({ data: { companyId: company.id, name: "Customer", email: "customer@example.test" } });
  const project = await prisma.project.create({ data: { companyId: company.id, clientId: client.id, title: "Project", projectType: "CUSTOM" } });
  const base = await estimates.create(company.id, user.id, { project_id: project.id, assumptions: "Existing frame", exclusions: "Permits" });
  await items.create(base.id, company.id, { category: "labor", name: "Original scope", quantity: 1, unit: "job", unit_cost: 100, markup_percent: 0, tax_rate: 0, sort_order: 0 });
  const baseProposal = await proposals.create(company.id, { estimate_id: base.id });
  await proposals.send(baseProposal.id, company.id, user.id);
  const approved = await proposals.respondToProposal(baseProposal.shareToken!, { decision: "approved" });
  const document = readProposalSnapshot(approved.sentSnapshot);
  const revised = await estimates.revise(base.id, company.id, user.id, randomUUID());
  const line = (await items.listByEstimate(revised.id, company.id))[0];
  await items.update(line.id, company.id, { name: "Expanded scope", unit_cost: 150 });
  const proposal = await proposals.create(company.id, { estimate_id: revised.id });
  const order = await prisma.changeOrder.create({ data: {
    companyId: company.id, projectId: project.id, rootEstimateId: base.id, baseEstimateId: base.id,
    estimateId: revised.id, proposalId: proposal.id, requestId: randomUUID(), title: "Additional work", reason: "Customer requested expanded scope", createdByUserId: user.id,
    baseSnapshot: {
      estimate_id: base.id, estimate_number: base.estimateNumber!, version: base.version, document_hash: proposalDocumentHash(approved.sentSnapshot),
      subtotal: "100.00", tax: "0.00", discount: "0.00", total: "100.00",
      scope: { line_items: document.content.estimate.line_items.map(({ name, description, quantity, unit, line_total }) => ({ name, description, quantity, unit, line_total })), assumptions: "Existing frame", exclusions: "Permits" },
    },
  } });
  return { company, user, project, base, baseProposal, revised, proposal, order };
}

beforeEach(async () => { await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE'); });

describe("customer change-order review", () => {
  it("freezes the old/new comparison inside the exact document hash without replacing the approved source", async () => {
    const t = await fixture();
    const reviewed = await proposals.getById(t.proposal.id, t.company.id);
    expect(toProposalDto(reviewed).change_order?.change_amount).toBe(50);
    const sent = await proposals.send(t.proposal.id, t.company.id, t.user.id, { draft_review_token: reviewed.draftReviewToken! });
    const snapshot = readProposalSnapshot(sent.sentSnapshot);
    expect(snapshot.content.change_order).toMatchObject({ base_total: 100, new_total: 150, change_amount: 50, base_version: 1, billing_effect: "included_in_first_invoice" });
    expect(snapshot.content.change_order?.base_scope.line_items[0].name).toBe("Original scope");
    const withoutComparison = structuredClone(snapshot);
    delete withoutComparison.content.change_order;
    expect(proposalDocumentHash(sent.sentSnapshot)).not.toBe(hashCanonicalValue(withoutComparison));
    const storedOrder = await prisma.changeOrder.findUniqueOrThrow({ where: { id: t.order.id } });
    expect(storedOrder.status).toBe("SENT");
    expect(storedOrder.comparisonSnapshot).toEqual(snapshot.content.change_order);
    await prisma.project.update({ where: { id: t.project.id }, data: { title: "Changed mutable title" } });
    const shared = toSharedProposalDto(await proposals.getByShareToken(sent.shareToken!));
    expect(shared.change_order).toEqual(snapshot.content.change_order);
    expect((await estimates.getById(t.base.id, t.company.id)).status).toBe("APPROVED");
    expect((await proposals.getById(t.baseProposal.id, t.company.id)).status).toBe("APPROVED");
  });

  it("requires typed approval of the exact comparison and records the same hash on the change order", async () => {
    const t = await fixture();
    const sent = await proposals.send(t.proposal.id, t.company.id, t.user.id);
    await expect(proposals.respondToProposal(sent.shareToken!, { decision: "approved" })).rejects.toMatchObject({ statusCode: 400 });
    await expect(proposals.respondToProposal(sent.shareToken!, { decision: "approved", signer_name: "Customer", acceptance_consent: true, consent_version: ACCEPTANCE_CONSENT_VERSION, document_hash: "f".repeat(64) })).rejects.toMatchObject({ statusCode: 409 });
    const hash = proposalDocumentHash(sent.sentSnapshot);
    const result = await proposals.respondToProposal(sent.shareToken!, { decision: "approved", signer_name: "Customer", acceptance_consent: true, consent_version: ACCEPTANCE_CONSENT_VERSION, document_hash: hash });
    expect(result.acceptance?.documentHash).toBe(hash);
    const order = await prisma.changeOrder.findUniqueOrThrow({ where: { id: t.order.id } });
    expect(order.status).toBe("APPROVED");
    expect(order.approvedDocumentHash).toBe(hash);
    expect(await prisma.invoice.count()).toBe(0);
  });

  it("includes change-order explanation changes in the contractor's reviewed token", async () => {
    const t = await fixture();
    const reviewed = await proposals.getById(t.proposal.id, t.company.id);
    await prisma.changeOrder.update({ where: { id: t.order.id }, data: { reason: "Different explanation" } });
    await expect(proposals.send(t.proposal.id, t.company.id, t.user.id, { draft_review_token: reviewed.draftReviewToken! })).rejects.toMatchObject({ statusCode: 409 });
    expect((await prisma.changeOrder.findUniqueOrThrow({ where: { id: t.order.id } })).status).toBe("DRAFT");
  });

  it("reuses its linked proposal while ordinary revision recovery excludes change-order drafts", async () => {
    const t = await fixture();
    expect((await proposals.create(t.company.id, { estimate_id: t.revised.id })).id).toBe(t.proposal.id);
    expect(await prisma.proposal.count({ where: { estimateId: t.revised.id } })).toBe(1);
    const ordinary = await estimates.revise(t.base.id, t.company.id, t.user.id, randomUUID());
    expect(ordinary.id).not.toBe(t.revised.id);
    expect(await prisma.changeOrder.count({ where: { estimateId: ordinary.id } })).toBe(0);
    await proposals.send(t.proposal.id, t.company.id, t.user.id);
    await expect(estimates.revise(t.revised.id, t.company.id, t.user.id, randomUUID())).rejects.toMatchObject({ statusCode: 409 });
  });

  it("declines only the amendment while keeping the approved project and source intact", async () => {
    const t = await fixture();
    const sent = await proposals.send(t.proposal.id, t.company.id, t.user.id);
    await proposals.respondToProposal(sent.shareToken!, { decision: "declined" });
    expect((await prisma.changeOrder.findUniqueOrThrow({ where: { id: t.order.id } })).status).toBe("DECLINED");
    expect((await prisma.project.findUniqueOrThrow({ where: { id: t.project.id } })).status).toBe("APPROVED");
    expect((await estimates.getById(t.base.id, t.company.id)).status).toBe("APPROVED");
  });
});
