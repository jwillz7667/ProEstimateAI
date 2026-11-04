import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { prisma } from "../../src/config/database";
import * as proposals from "../../src/modules/proposals/proposals.service";
import * as estimates from "../../src/modules/estimates/estimates.service";
import * as estimateItems from "../../src/modules/estimate-line-items/estimate-line-items.service";
import * as service from "../../src/modules/follow-ups/follow-ups.service";
import { enqueueDueReminders, processFollowUpQueue } from "../../src/modules/follow-ups/follow-ups.worker";
import { FollowUpDeliveryError } from "../../src/modules/follow-ups/follow-ups.email";

vi.mock("../../src/config/env", async (original) => {
  const actual = await original<typeof import("../../src/config/env")>();
  return { ...actual, env: { ...actual.env, RESEND_API_KEY: "test-placeholder-never-sent" } };
});
vi.mock("../../src/lib/email", () => ({ sendProposalEmail: vi.fn().mockResolvedValue(undefined) }));

const DAY = 86_400_000;
async function fixture() {
  const company = await prisma.company.create({ data: { name: "Follow-up Company", email: "contractor@example.test" } });
  const user = await prisma.user.create({ data: { companyId: company.id, fullName: "Owner", email: `${randomUUID()}@example.test` } });
  const plan = await prisma.plan.upsert({ where: { code: "PRO_MONTHLY" }, update: {}, create: { code: "PRO_MONTHLY", displayName: "Pro", description: "Disposable test plan", featuresJson: { CAN_SHARE_APPROVAL_LINK: true, CAN_CREATE_INVOICE: true } } });
  await prisma.userEntitlement.create({ data: { companyId: company.id, userId: user.id, planId: plan.id, status: "PRO_ACTIVE", renewalDate: new Date(Date.now() + 120 * DAY) } });
  const client = await prisma.client.create({ data: { companyId: company.id, name: "Customer", email: "customer@example.test" } });
  const project = await prisma.project.create({ data: { companyId: company.id, clientId: client.id, title: "Job", projectType: "CUSTOM" } });
  const estimate = await estimates.create(company.id, user.id, { project_id: project.id });
  await estimateItems.create(estimate.id, company.id, { category: "labor", name: "Site work", quantity: 1, unit: "job", unit_cost: 100, markup_percent: 0, tax_rate: 0, sort_order: 0 });
  const proposal = await proposals.create(company.id, { estimate_id: estimate.id });
  await proposals.send(proposal.id, company.id, user.id);
  const invoice = await prisma.invoice.create({ data: { companyId: company.id, projectId: project.id, clientId: client.id, invoiceNumber: "INV-1", totalAmount: 100, amountDue: 100, status: "SENT", sentAt: new Date(Date.now() - 12 * DAY), dueDate: new Date(Date.now() - 10 * DAY) } });
  return { company, user, client, project, estimate, proposal, invoice };
}
const noSend = async () => { throw new Error("A provider call was not expected"); };

beforeEach(async () => { await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company", "Plan" RESTART IDENTITY CASCADE'); });

describe("follow-up consent and manual requests", () => {
  it("starts off and does not enqueue existing work when first enabled", async () => {
    const t = await fixture();
    expect((await service.getSettings(t.company.id, t.user.id)).enabled).toBe(false);
    expect(await enqueueDueReminders()).toBe(0);
    await service.updateSettings(t.company.id, t.user.id, { enabled: true, quote_days: 3, invoice_days: 7 });
    expect(await enqueueDueReminders()).toBe(0);
    expect(await prisma.followUpMessage.count()).toBe(0);
  });

  it("queues an explicit request once, safely replays its UUID and records provider acceptance", async () => {
    const t = await fixture();
    const key = randomUUID();
    const results = await Promise.all([
      service.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, key),
      service.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, key),
    ]);
    expect(results[0].id).toBe(results[1].id);
    expect(await prisma.followUpMessage.count()).toBe(1);
    expect((await service.listHistory(t.company.id, "proposal", t.proposal.id)).eligible).toBe(false);
    const sender = vi.fn(async () => "provider-id-1");
    await processFollowUpQueue({ send: sender });
    expect(sender).toHaveBeenCalledTimes(1);
    const saved = await prisma.followUpMessage.findUniqueOrThrow({ where: { id: results[0].id } });
    expect(saved.status).toBe("SENT");
    expect(saved.acceptedAt).not.toBeNull();
    expect(saved.deliveredAt).toBeNull();
    expect((await service.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, key)).id).toBe(saved.id);
    await expect(service.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, randomUUID())).rejects.toMatchObject({ statusCode: 409 });
  });

  it("rejects a request UUID reused for another document even under a race", async () => {
    const t = await fixture();
    const key = randomUUID();
    const results = await Promise.allSettled([
      service.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, key),
      service.enqueueManual(t.company.id, t.user.id, "invoice", t.invoice.id, key),
    ]);
    expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    const rejected = results.find((result) => result.status === "rejected");
    expect(rejected?.status === "rejected" && rejected.reason.statusCode).toBe(409);
  });

  it("allows an expired owner's disabling action but rejects enabling or new sends", async () => {
    const t = await fixture();
    await service.updateSettings(t.company.id, t.user.id, { enabled: true, quote_days: 3, invoice_days: 7 });
    await prisma.userEntitlement.update({ where: { userId: t.user.id }, data: { status: "EXPIRED" } });
    expect((await service.updateSettings(t.company.id, t.user.id, { enabled: false, quote_days: 3, invoice_days: 7 })).enabled).toBe(false);
    await expect(service.updateSettings(t.company.id, t.user.id, { enabled: true, quote_days: 3, invoice_days: 7 })).rejects.toMatchObject({ statusCode: 403 });
    await expect(service.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, randomUUID())).rejects.toMatchObject({ statusCode: 403 });
  });

  it("preserves tenant boundaries and owner/admin control of automation", async () => {
    const t = await fixture();
    const foreign = await fixture();
    await expect(service.listHistory(foreign.company.id, "proposal", t.proposal.id)).rejects.toMatchObject({ statusCode: 404 });
    await expect(service.enqueueManual(foreign.company.id, foreign.user.id, "invoice", t.invoice.id, randomUUID())).rejects.toMatchObject({ statusCode: 404 });
    await prisma.user.update({ where: { id: t.user.id }, data: { role: "ESTIMATOR" } });
    await expect(service.updateSettings(t.company.id, t.user.id, { enabled: true, quote_days: 3, invoice_days: 7 })).rejects.toMatchObject({ statusCode: 403 });
    await prisma.user.update({ where: { id: t.user.id }, data: { role: "VIEWER" } });
    await expect(service.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, randomUUID())).rejects.toMatchObject({ statusCode: 403 });
  });
});

describe("durable reminder delivery", () => {
  it("retries a transient provider failure with identical content and idempotency key", async () => {
    const t = await fixture();
    await service.enqueueManual(t.company.id, t.user.id, "invoice", t.invoice.id, randomUUID());
    const sender = vi.fn().mockRejectedValueOnce(new FollowUpDeliveryError("Temporary provider error", true)).mockResolvedValueOnce("retried-id");
    const now = new Date();
    await processFollowUpQueue({ now, send: sender });
    const retry = await prisma.followUpMessage.findFirstOrThrow();
    expect(retry.status).toBe("QUEUED");
    expect(retry.attempts).toBe(1);
    await prisma.invoice.update({ where: { id: t.invoice.id }, data: { amountPaid: 50, amountDue: 50 } });
    await processFollowUpQueue({ now: new Date(now.getTime() + 120_000), send: sender });
    expect(sender).toHaveBeenCalledTimes(2);
    expect(sender.mock.calls[0]).toEqual(sender.mock.calls[1]);
    expect(JSON.stringify(sender.mock.calls[1][0])).not.toContain("$100.00");
    expect((await prisma.followUpMessage.findFirstOrThrow()).status).toBe("SENT");
    await expect(prisma.followUpMessage.update({ where: { id: retry.id }, data: { recipientEmail: "other@example.test" } })).rejects.toThrow();
  });

  it("marks permanent failures without retrying or claiming delivery", async () => {
    const t = await fixture();
    await service.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, randomUUID());
    const sender = vi.fn(async () => { throw new FollowUpDeliveryError("Provider rejected request", false); });
    await processFollowUpQueue({ send: sender });
    expect((await prisma.followUpMessage.findFirstOrThrow()).status).toBe("FAILED");
    await processFollowUpQueue({ now: new Date(Date.now() + DAY), send: sender });
    expect(sender).toHaveBeenCalledTimes(1);
  });

  it("bounds retries inside the provider idempotency window", async () => {
    const t = await fixture();
    const queued = await service.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, randomUUID());
    await processFollowUpQueue({ send: async () => { throw new FollowUpDeliveryError("Ambiguous response", true); } });
    const sender = vi.fn(noSend);
    await processFollowUpQueue({ now: new Date(Date.now() + 23 * 3_600_000), send: sender });
    expect(sender).not.toHaveBeenCalled();
    expect((await prisma.followUpMessage.findUniqueOrThrow({ where: { id: queued.id } })).status).toBe("FAILED");
  });

  it("lets only one worker claim a queued delivery", async () => {
    const t = await fixture();
    await service.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, randomUUID());
    const sender = vi.fn(async () => "single-provider-id");
    await Promise.all([processFollowUpQueue({ send: sender }), processFollowUpQueue({ send: sender })]);
    expect(sender).toHaveBeenCalledTimes(1);
  });

  it("enqueues at most one automatic quote and invoice reminder after an explicit earlier opt-in", async () => {
    const t = await fixture();
    await service.updateSettings(t.company.id, t.user.id, { enabled: true, quote_days: 3, invoice_days: 7 });
    await prisma.followUpSettings.update({ where: { companyId: t.company.id }, data: { enabledAt: new Date(Date.now() - 20 * DAY) } });
    await prisma.proposal.update({ where: { id: t.proposal.id }, data: { sentAt: new Date(Date.now() - 4 * DAY) } });
    expect(await enqueueDueReminders()).toBe(2);
    expect(await enqueueDueReminders()).toBe(0);
    await service.updateSettings(t.company.id, t.user.id, { enabled: false, quote_days: 3, invoice_days: 7 });
    const sender = vi.fn(noSend);
    await processFollowUpQueue({ send: sender });
    expect(sender).not.toHaveBeenCalled();
    expect(await prisma.followUpMessage.count({ where: { status: "CANCELLED" } })).toBe(2);
  });

  for (const state of ["approved", "declined", "changes_requested"] as const) {
    it(`stops a pending quote follow-up after ${state}`, async () => {
      const t = await fixture();
      await service.enqueueManual(t.company.id, t.user.id, "proposal", t.proposal.id, randomUUID());
      await proposals.respondToProposal(t.proposal.shareToken!, { decision: state, ...(state === "changes_requested" ? { message: "Revise scope" } : {}) });
      const sender = vi.fn(noSend);
      await processFollowUpQueue({ send: sender });
      expect(sender).not.toHaveBeenCalled();
      expect((await prisma.followUpMessage.findFirstOrThrow()).status).toBe("CANCELLED");
    });
  }

  for (const status of ["PAID", "VOID"] as const) {
    it(`stops a pending invoice follow-up after ${status.toLowerCase()}`, async () => {
      const t = await fixture();
      await service.enqueueManual(t.company.id, t.user.id, "invoice", t.invoice.id, randomUUID());
      await prisma.invoice.update({ where: { id: t.invoice.id }, data: { status, ...(status === "PAID" ? { amountPaid: 100, amountDue: 0 } : {}) } });
      const sender = vi.fn(noSend);
      await processFollowUpQueue({ send: sender });
      expect(sender).not.toHaveBeenCalled();
      expect((await prisma.followUpMessage.findFirstOrThrow()).status).toBe("CANCELLED");
    });
  }

  it("honors recipient opt-out on queued messages and preserves the business document", async () => {
    const t = await fixture();
    await service.enqueueManual(t.company.id, t.user.id, "invoice", t.invoice.id, randomUUID());
    const queued = await prisma.followUpMessage.findFirstOrThrow();
    expect((await service.getPreference(queued.unsubscribeToken)).suppressed).toBe(false);
    await service.unsubscribe(queued.unsubscribeToken);
    await service.unsubscribe(queued.unsubscribeToken);
    const sender = vi.fn(noSend);
    await processFollowUpQueue({ send: sender });
    expect(sender).not.toHaveBeenCalled();
    expect((await service.listHistory(t.company.id, "invoice", t.invoice.id)).suppressed).toBe(true);
    expect((await prisma.invoice.findUniqueOrThrow({ where: { id: t.invoice.id } })).amountDue.toString()).toBe("100");
    await expect(service.enqueueManual(t.company.id, t.user.id, "invoice", t.invoice.id, randomUUID())).rejects.toMatchObject({ statusCode: 409 });
  });
});
