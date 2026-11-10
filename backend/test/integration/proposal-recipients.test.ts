import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { prisma } from "../../src/config/database";
import * as proposals from "../../src/modules/proposals/proposals.service";
import * as estimates from "../../src/modules/estimates/estimates.service";
import * as items from "../../src/modules/estimate-line-items/estimate-line-items.service";
import * as followUps from "../../src/modules/follow-ups/follow-ups.service";
import { processFollowUpQueue } from "../../src/modules/follow-ups/follow-ups.worker";
import { toProposalDto } from "../../src/modules/proposals/proposals.dto";
import { toSharedProposalDto } from "../../src/modules/proposals/proposals.share-dto";
import { sendProposalEmail } from "../../src/lib/email";

vi.mock("../../src/config/env", async (original) => {
  const actual = await original<typeof import("../../src/config/env")>();
  return { ...actual, env: { ...actual.env, RESEND_API_KEY: "test-placeholder-never-sent" } };
});
vi.mock("../../src/lib/email", () => ({ sendProposalEmail: vi.fn().mockResolvedValue(undefined) }));

async function fixture() {
  const company = await prisma.company.create({ data: { name: "Recipient isolation" } });
  const user = await prisma.user.create({ data: { companyId: company.id, fullName: "Owner", email: `${randomUUID()}@example.test` } });
  const plan = await prisma.plan.upsert({ where: { code: "PRO_MONTHLY" }, update: {}, create: { code: "PRO_MONTHLY", displayName: "Pro", description: "Test", featuresJson: { CAN_SHARE_APPROVAL_LINK: true } } });
  await prisma.userEntitlement.create({ data: { companyId: company.id, userId: user.id, planId: plan.id, status: "PRO_ACTIVE", renewalDate: new Date(Date.now() + 864_000_000) } });
  const client = await prisma.client.create({ data: { companyId: company.id, name: "Customer A", email: "customer-a@example.test" } });
  const other = await prisma.client.create({ data: { companyId: company.id, name: "Customer B", email: "customer-b@example.test" } });
  const project = await prisma.project.create({ data: { companyId: company.id, clientId: client.id, title: "Quoted job", projectType: "CUSTOM" } });
  const estimate = await estimates.create(company.id, user.id, { project_id: project.id });
  await items.create(estimate.id, company.id, { category: "labor", name: "Work", quantity: 1, unit: "job", unit_cost: 100, markup_percent: 0, tax_rate: 0, sort_order: 0 });
  const proposal = await proposals.create(company.id, { estimate_id: estimate.id });
  return { company, user, client, other, project, proposal };
}

beforeEach(async () => {
  await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company", "Plan" RESTART IDENTITY CASCADE');
  vi.mocked(sendProposalEmail).mockClear();
});

describe("sent proposal recipient isolation", () => {
  it("records the reviewed private recipient and never includes recipient PII in public content", async () => {
    const t = await fixture();
    const sent = await proposals.send(t.proposal.id, t.company.id, t.user.id);
    expect(sent.sentRecipientClientId).toBe(t.client.id);
    expect(sent.sentRecipientEmail).toBe(t.client.email);
    expect(sendProposalEmail).toHaveBeenCalledWith(t.client.email, expect.any(String), t.company.name, undefined);
    const publicJson = JSON.stringify(toSharedProposalDto(await proposals.getByShareToken(sent.shareToken!)));
    expect(publicJson).not.toContain(t.client.email);
    expect(JSON.stringify(sent.sentSnapshot)).not.toContain(t.client.id);
    await expect(prisma.proposal.update({ where: { id: sent.id }, data: { sentRecipientEmail: t.other.email } })).rejects.toThrow();
  });

  it.each(["client", "email"] as const)("rejects changed %s between review and send without publishing or emailing", async (change) => {
    const t = await fixture();
    const reviewed = await proposals.getById(t.proposal.id, t.company.id);
    if (change === "client") await prisma.project.update({ where: { id: t.project.id }, data: { clientId: t.other.id } });
    else await prisma.client.update({ where: { id: t.client.id }, data: { email: t.other.email } });
    await expect(proposals.send(t.proposal.id, t.company.id, t.user.id, { draft_review_token: reviewed.draftReviewToken! })).rejects.toMatchObject({ statusCode: 409 });
    expect((await prisma.proposal.findUniqueOrThrow({ where: { id: t.proposal.id } })).sentSnapshot).toBeNull();
    expect(sendProposalEmail).not.toHaveBeenCalled();
  });

  it.each(["client", "email"] as const)("suppresses pending/new reminders and resend after a sent %s changes", async (change) => {
    const t = await fixture();
    await proposals.send(t.proposal.id, t.company.id, t.user.id);
    await followUps.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, randomUUID());
    if (change === "client") await prisma.project.update({ where: { id: t.project.id }, data: { clientId: t.other.id } });
    else await prisma.client.update({ where: { id: t.client.id }, data: { email: t.other.email } });
    const history = await followUps.listHistory(t.company.id, "proposal", t.proposal.id);
    expect(history.eligible).toBe(false);
    expect(history.recipient_email).toBe(t.client.email);
    await expect(followUps.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, randomUUID())).rejects.toMatchObject({ statusCode: 409 });
    await expect(proposals.send(t.proposal.id, t.company.id, t.user.id)).rejects.toMatchObject({ statusCode: 409 });
    const sender = vi.fn(async () => "unexpected");
    await processFollowUpQueue({ send: sender });
    expect(sender).not.toHaveBeenCalled();
    expect((await prisma.followUpMessage.findFirstOrThrow()).status).toBe("CANCELLED");
    const dto = toProposalDto(await proposals.getById(t.proposal.id, t.company.id));
    expect(dto.recipient_name).toBe("Customer A");
    expect(dto.recipient_matches_current).toBe(false);
    expect(sendProposalEmail).toHaveBeenCalledTimes(1);
  });

  it("does not infer a historical recipient from a mutable current project", async () => {
    const t = await fixture();
    await prisma.proposal.update({ where: { id: t.proposal.id }, data: { status: "SENT", sentAt: new Date() } });
    const saved = await proposals.getByShareToken(t.proposal.shareToken!);
    expect(saved.sentRecipientEmail).toBeNull();
    expect(toSharedProposalDto(saved).estimate.total_amount).toBe(100);
    expect((await followUps.listHistory(t.company.id, "proposal", t.proposal.id)).eligible).toBe(false);
    await expect(proposals.send(t.proposal.id, t.company.id, t.user.id)).rejects.toMatchObject({ statusCode: 409 });
    expect(sendProposalEmail).not.toHaveBeenCalled();
  });

  it("serializes simultaneous reassignment and send without FK lock deadlock or misdirected delivery", async () => {
    const t = await fixture();
    const reviewed = await proposals.getById(t.proposal.id, t.company.id);
    let beginSend!: () => void;
    const sendStarted = new Promise<void>((resolve) => { beginSend = resolve; });
    let releaseProject!: () => void;
    const canRelease = new Promise<void>((resolve) => { releaseProject = resolve; });
    const reassignment = prisma.$transaction(async (tx) => {
      await tx.$queryRaw`SELECT id FROM "Project" WHERE id = ${t.project.id} FOR NO KEY UPDATE`;
      beginSend();
      await canRelease;
      await tx.project.update({ where: { id: t.project.id }, data: { clientId: t.other.id } });
    });
    await sendStarted;
    const result = proposals.send(t.proposal.id, t.company.id, t.user.id, { draft_review_token: reviewed.draftReviewToken! }).then(() => null, (error: unknown) => error);
    // Wait for the actual PostgreSQL lock wait, rather than assuming timing.
    for (let attempt = 0; attempt < 100; attempt++) {
      const waiting = await prisma.$queryRaw<Array<{ waiting: boolean }>>`SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE datname = current_database() AND wait_event_type = 'Lock' AND query LIKE '%FROM "Project"%') AS waiting`;
      if (waiting[0].waiting) break;
      await new Promise((resolve) => setTimeout(resolve, 10));
    }
    releaseProject();
    await reassignment;
    expect(await result).toMatchObject({ statusCode: 409 });
    expect(sendProposalEmail).not.toHaveBeenCalled();
  });
});
