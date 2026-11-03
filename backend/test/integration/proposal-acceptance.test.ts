import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../../src/config/database";
import * as proposals from "../../src/modules/proposals/proposals.service";
import * as estimates from "../../src/modules/estimates/estimates.service";
import * as items from "../../src/modules/estimate-line-items/estimate-line-items.service";
import { toSharedProposalDto } from "../../src/modules/proposals/proposals.share-dto";
import { ACCEPTANCE_CONSENT_TEXT, ACCEPTANCE_CONSENT_VERSION, proposalDocumentHash } from "../../src/modules/proposals/proposal-document-snapshot";
import { respondToProposalSchema } from "../../src/modules/proposals/proposals.validators";

async function fixture() {
  const company = await prisma.company.create({ data: { name: "Approval test" } });
  const user = await prisma.user.create({ data: { companyId: company.id, email: `${randomUUID()}@example.test`, fullName: "Estimator" } });
  const project = await prisma.project.create({ data: { companyId: company.id, title: "Bathroom", projectType: "BATHROOM" } });
  const estimate = await estimates.create(company.id, user.id, { project_id: project.id });
  await items.create(estimate.id, company.id, { category: "labor", name: "Installation", quantity: 2, unit: "hour", unit_cost: 100, markup_percent: 10, tax_rate: 0, sort_order: 0 });
  const proposal = await proposals.create(company.id, { estimate_id: estimate.id, terms_and_conditions: "Agreed terms" });
  await proposals.send(proposal.id, company.id, user.id);
  const shared = await proposals.getByShareToken(proposal.shareToken!);
  return { company, user, project, estimate, proposal, shared, hash: proposalDocumentHash(shared.sentSnapshot) };
}

beforeEach(async () => { await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE'); });

describe("proposal acknowledgement evidence", () => {
  it("records the typed name, explicit consent, exact frozen version and server timestamp", async () => {
    const t = await fixture();
    const before = Date.now();
    const approved = await proposals.respondToProposal(t.proposal.shareToken!, {
      decision: "approved", signer_name: "  Jordan Customer  ", acceptance_consent: true,
      consent_version: ACCEPTANCE_CONSENT_VERSION, document_hash: t.hash, message: "Proceed",
    });
    const evidence = await prisma.proposalAcceptance.findUniqueOrThrow({ where: { proposalId: t.proposal.id } });
    expect(evidence.signerName).toBe("Jordan Customer");
    expect(evidence.documentHash).toBe(t.hash);
    expect(evidence.estimateVersion).toBe(t.estimate.version);
    expect(evidence.consentText).toBe(ACCEPTANCE_CONSENT_TEXT);
    expect(evidence.identityAssurance).toBe("SELF_ATTESTED");
    expect(evidence.acceptedAt.getTime()).toBeGreaterThanOrEqual(before);
    const publicRecord = toSharedProposalDto(approved);
    expect(publicRecord.acceptance?.document_hash).toBe(t.hash);
    expect(publicRecord.acceptance?.identity_assurance).toBe("self_attested");
    expect(publicRecord.proposal.response_message).toBe("Proceed");
    expect((await proposals.getById(t.proposal.id, t.company.id)).acceptance?.id).toBe(evidence.id);
    await expect(prisma.proposalAcceptance.update({ where: { id: evidence.id }, data: { signerName: "Replacement signer" } })).rejects.toThrow();
  });

  it("rejects a stale document reference before recording a decision or evidence", async () => {
    const t = await fixture();
    await expect(proposals.respondToProposal(t.proposal.shareToken!, { decision: "approved", signer_name: "Customer", acceptance_consent: true, document_hash: "a".repeat(64) })).rejects.toMatchObject({ statusCode: 409 });
    expect(await prisma.proposalAcceptance.count()).toBe(0);
    expect((await proposals.getById(t.proposal.id, t.company.id)).respondedAt).toBeNull();
  });

  it("requires every acknowledgement field when any signing input is supplied", async () => {
    const t = await fixture();
    for (const body of [
      { decision: "approved", signer_name: "Customer" },
      { decision: "approved", acceptance_consent: false, signer_name: "Customer", document_hash: t.hash },
      { decision: "approved", signer_name: "", acceptance_consent: true, document_hash: t.hash },
      { decision: "declined", signer_name: "Customer", acceptance_consent: true, document_hash: t.hash },
    ]) expect(respondToProposalSchema.safeParse(body).success).toBe(false);
    await expect(proposals.respondToProposal(t.proposal.shareToken!, { decision: "approved", signer_name: "Customer", acceptance_consent: false, document_hash: t.hash })).rejects.toMatchObject({ statusCode: 400 });
    expect(await prisma.proposalAcceptance.count()).toBe(0);
  });

  it("keeps older approval clients compatible without inventing signed evidence", async () => {
    const t = await fixture();
    const approved = await proposals.respondToProposal(t.proposal.shareToken!, { decision: "approved" });
    expect(approved.status).toBe("APPROVED");
    expect(toSharedProposalDto(approved).acceptance).toBeNull();
    expect(await prisma.proposalAcceptance.count()).toBe(0);
  });

  it("keeps the first acknowledgement authoritative across concurrent retries", async () => {
    const t = await fixture();
    const body = { decision: "approved", signer_name: "First Customer", acceptance_consent: true, consent_version: ACCEPTANCE_CONSENT_VERSION, document_hash: t.hash } as const;
    const results = await Promise.all([
      proposals.respondToProposal(t.proposal.shareToken!, body),
      proposals.respondToProposal(t.proposal.shareToken!, { ...body, signer_name: "Second Name" }),
    ]);
    expect(results[0].status).toBe("APPROVED");
    expect(results[1].acceptance?.signerName).toBe(results[0].acceptance?.signerName);
    expect(await prisma.proposalAcceptance.count()).toBe(1);
  });

  it("hashes frozen content and capture time consistently across JSON key order", async () => {
    const t = await fixture();
    const snapshot = t.shared.sentSnapshot as Record<string, unknown>;
    const reordered = Object.fromEntries(Object.entries(snapshot).reverse());
    expect(proposalDocumentHash(reordered)).toBe(t.hash);
    expect(proposalDocumentHash({ ...snapshot, captured_at: "2020-01-01T00:00:00.000Z" })).not.toBe(t.hash);
  });
});

describe("customer change requests", () => {
  it("records a change request without approving or declining and closes the original offer", async () => {
    const t = await fixture();
    const changed = await proposals.respondToProposal(t.proposal.shareToken!, { decision: "changes_requested", message: "Use oak instead of pine", document_hash: t.hash });
    expect(changed.status).toBe("VIEWED");
    expect(changed.respondedAt).toBeNull();
    expect(changed.changesRequestedAt).not.toBeNull();
    expect(toSharedProposalDto(changed).proposal.requested_changes_message).toBe("Use oak instead of pine");
    expect(proposalDocumentHash(changed.sentSnapshot)).toBe(t.hash);
    await expect(proposals.respondToProposal(t.proposal.shareToken!, { decision: "approved" })).rejects.toMatchObject({ statusCode: 409 });
    await expect(proposals.send(changed.id, t.company.id, t.user.id)).rejects.toMatchObject({ statusCode: 409 });
    const retry = await proposals.respondToProposal(t.proposal.shareToken!, { decision: "changes_requested", message: "Different second message" });
    expect(retry.changesRequestedAt).toEqual(changed.changesRequestedAt);
    expect(retry.requestedChangesMessage).toBe("Use oak instead of pine");
    const revision = await estimates.revise(t.estimate.id, t.company.id, t.user.id, randomUUID());
    expect(revision.status).toBe("DRAFT");
    expect(revision.revisesEstimateId).toBe(t.estimate.id);
  });

  it("requires a useful message before closing an offer for requested changes", async () => {
    const t = await fixture();
    expect(respondToProposalSchema.safeParse({ decision: "changes_requested", message: " " }).success).toBe(false);
    await expect(proposals.respondToProposal(t.proposal.shareToken!, { decision: "changes_requested" })).rejects.toMatchObject({ statusCode: 400 });
    expect((await proposals.getById(t.proposal.id, t.company.id)).changesRequestedAt).toBeNull();
  });
});
