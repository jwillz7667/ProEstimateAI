import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../../src/config/database";
import * as invoices from "../../src/modules/invoices/invoices.service";
import * as invoiceLines from "../../src/modules/invoice-line-items/invoice-line-items.service";
import * as estimateLines from "../../src/modules/estimate-line-items/estimate-line-items.service";
import * as estimates from "../../src/modules/estimates/estimates.service";
import * as proposals from "../../src/modules/proposals/proposals.service";
import * as projects from "../../src/modules/projects/projects.service";
import { toSharedProposalDto } from "../../src/modules/proposals/proposals.share-dto";
import { toProjectListDto } from "../../src/modules/projects/projects.dto";
import {
  gateAIAction,
  runReservedAction,
} from "../../src/modules/commerce/entitlement-gate";
import { readProjectQualityTier } from "../../src/lib/project-quality-tier";
import { resetPassword } from "../../src/modules/auth/auth.service";
import { verifyPassword } from "../../src/lib/hash";

beforeEach(async () => {
  await prisma.$executeRawUnsafe(
    'TRUNCATE TABLE "Company", "Plan" RESTART IDENTITY CASCADE',
  );
});

async function tenant(
  code: "PRO_MONTHLY" | "FREE_STARTER" = "PRO_MONTHLY",
  featuresJson = {},
) {
  const company = await prisma.company.create({
    data: { name: "Audit Company", defaultTaxRate: 8.25 },
  });
  const user = await prisma.user.create({
    data: {
      companyId: company.id,
      fullName: "Audit User",
      email: `${randomUUID()}@example.test`,
    },
  });
  const plan = await prisma.plan.upsert({
    where: { code },
    create: {
      code,
      displayName: code,
      description: "Audit plan",
      featuresJson: { CAN_CREATE_INVOICE: true, ...featuresJson },
    },
    update: {},
  });
  await prisma.userEntitlement.create({
    data: {
      companyId: company.id,
      userId: user.id,
      planId: plan.id,
      status: code === "FREE_STARTER" ? "FREE" : "PRO_ACTIVE",
      renewalDate: code === "FREE_STARTER" ? null : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000),
    },
  });
  const client = await prisma.client.create({
    data: { companyId: company.id, name: "Audit Client" },
  });
  const project = await prisma.project.create({
    data: {
      companyId: company.id,
      clientId: client.id,
      title: "Kitchen",
      projectType: "KITCHEN",
      qualityTier: "PREMIUM",
    },
  });
  const estimate = await prisma.estimate.create({
    data: {
      companyId: company.id,
      projectId: project.id,
      estimateNumber: "EST-0",
      subtotalMaterials: 800,
      subtotalLabor: 240,
      taxAmount: 80,
      totalAmount: 1120,
    },
  });
  await prisma.estimateLineItem.createMany({
    data: [
      {
        estimateId: estimate.id,
        category: "MATERIALS",
        name: "Tile",
        quantity: 1,
        unit: "lot",
        unitCost: 800,
        lineTotal: 800,
        taxRate: 0.1,
        sortOrder: 0,
      },
      {
        estimateId: estimate.id,
        category: "LABOR",
        name: "Labor",
        quantity: 2,
        unit: "hour",
        unitCost: 100,
        markupPercent: 20,
        lineTotal: 240,
        taxRate: 0,
        sortOrder: 1,
      },
    ],
  });
  return { company, user, client, project, estimate };
}

const otherLine = (name: string) => ({
  category: "other" as const,
  name,
  quantity: 1,
  unit: "lot",
  unit_cost: 10,
  markup_percent: 0,
  tax_rate: 0,
  sort_order: 3,
});

describe("invoice money and reference invariants", () => {
  it("retains agreed tax during payment and discount changes, records payment status", async () => {
    const t = await tenant();
    const invoice = await invoices.createFromEstimate(
      t.company.id,
      t.user.id,
      t.estimate.id,
      {},
    );
    await prisma.company.update({
      where: { id: t.company.id },
      data: { defaultTaxRate: 25 },
    });
    const partial = await invoices.update(invoice.id, t.company.id, {
      amount_paid: 500,
    });
    expect(Number(partial.taxAmount)).toBe(80);
    expect(Number(partial.amountDue)).toBe(620);
    expect(partial.status).toBe("PARTIALLY_PAID");
    const discounted = await invoices.update(invoice.id, t.company.id, {
      discount_amount: 100,
    });
    expect(Number(discounted.totalAmount)).toBe(1020);
    expect(Number(discounted.amountDue)).toBe(520);
    const paid = await invoices.update(invoice.id, t.company.id, {
      status: "paid",
    });
    expect(Number(paid.amountPaid)).toBe(1020);
    expect(Number(paid.amountDue)).toBe(0);
    expect(paid.paidAt).not.toBeNull();
  });
  it("snapshots exact converted line taxes and keeps labor untaxed after company rate changes", async () => {
    const t = await tenant();
    const invoice = await invoices.createFromEstimate(
      t.company.id,
      t.user.id,
      t.estimate.id,
      {},
    );
    const lines = await prisma.invoiceLineItem.findMany({
      where: { invoiceId: invoice.id },
      orderBy: { sortOrder: "asc" },
    });
    expect(Number(lines[0].taxRate)).toBe(0.1);
    expect(Number(lines[1].taxRate)).toBe(0);
    await prisma.company.update({
      where: { id: t.company.id },
      data: { defaultTaxRate: 25 },
    });
    await invoiceLines.update(lines[1].id, t.company.id, { unit_cost: 150 });
    const fresh = await prisma.invoice.findUniqueOrThrow({
      where: { id: invoice.id },
    });
    expect(Number(fresh.subtotal)).toBe(1100);
    expect(Number(fresh.taxAmount)).toBe(80);
    expect(Number(fresh.totalAmount)).toBe(1180);
  });
  it("rejects stale concurrent cumulative payments, including an ambiguous equal-sized retry", async () => {
    const t = await tenant();
    const invoice = await invoices.createFromEstimate(
      t.company.id,
      t.user.id,
      t.estimate.id,
      {},
    );
    const results = await Promise.allSettled([
      invoices.update(invoice.id, t.company.id, {
        amount_paid: 100,
        expected_amount_paid: 0,
      }),
      invoices.update(invoice.id, t.company.id, {
        amount_paid: 200,
        expected_amount_paid: 0,
      }),
    ]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    const loser = results.find((r) => r.status === "rejected");
    expect(loser?.status === "rejected" && loser.reason.code).toBe("CONFLICT");
    const fresh = await prisma.invoice.findUniqueOrThrow({
      where: { id: invoice.id },
    });
    await expect(
      invoices.update(invoice.id, t.company.id, {
        amount_paid: Number(fresh.amountPaid),
        expected_amount_paid: 0,
      }),
    ).rejects.toMatchObject({ code: "CONFLICT" });
  });
  it("does not reopen paid/void invoices by sending and keeps partial payments intact", async () => {
    const t = await tenant();
    const invoice = await invoices.createFromEstimate(
      t.company.id,
      t.user.id,
      t.estimate.id,
      {},
    );
    await invoices.update(invoice.id, t.company.id, { amount_paid: 100 });
    expect(
      (await invoices.send(invoice.id, t.company.id, t.user.id)).status,
    ).toBe("PARTIALLY_PAID");
    await invoices.update(invoice.id, t.company.id, { status: "paid" });
    await expect(
      invoices.send(invoice.id, t.company.id, t.user.id),
    ).rejects.toThrow(/cannot be sent/);
    await invoices.update(invoice.id, t.company.id, { status: "void" });
    await expect(
      invoices.send(invoice.id, t.company.id, t.user.id),
    ).rejects.toThrow(/cannot be sent/);
  });
  it("preserves authoritative converted line totals on metadata-only edits", async () => {
    const t = await tenant();
    await prisma.estimateLineItem.deleteMany({
      where: { estimateId: t.estimate.id },
    });
    await prisma.estimateLineItem.create({
      data: {
        estimateId: t.estimate.id,
        name: "Rounded unit price",
        quantity: 3,
        unit: "each",
        unitCost: 0.33,
        lineTotal: 1,
      },
    });
    await prisma.estimate.update({
      where: { id: t.estimate.id },
      data: {
        subtotalMaterials: 1,
        subtotalLabor: 0,
        taxAmount: 0,
        totalAmount: 1,
      },
    });
    const invoice = await invoices.createFromEstimate(
      t.company.id,
      t.user.id,
      t.estimate.id,
      {},
    );
    const line = await prisma.invoiceLineItem.findFirstOrThrow({
      where: { invoiceId: invoice.id },
    });
    const updated = await invoiceLines.update(line.id, t.company.id, {
      description: "Clarified scope", quantity: 3, unit_cost: 0.33,
    });
    expect(Number(updated.lineTotal)).toBe(1);
    expect(
      Number(
        (await prisma.invoice.findUniqueOrThrow({ where: { id: invoice.id } }))
          .totalAmount,
      ),
    ).toBe(1);
  });
  it("rejects overpayments and reductions below payments without partial writes", async () => {
    const t = await tenant();
    const invoice = await invoices.createFromEstimate(
      t.company.id,
      t.user.id,
      t.estimate.id,
      {},
    );
    await expect(
      invoices.update(invoice.id, t.company.id, { amount_paid: 1121 }),
    ).rejects.toThrow(/exceed/);
    await invoices.update(invoice.id, t.company.id, { amount_paid: 1000 });
    await expect(
      invoices.update(invoice.id, t.company.id, { discount_amount: 200 }),
    ).rejects.toThrow(/exceed/);
    const line = await prisma.invoiceLineItem.findFirstOrThrow({
      where: { invoiceId: invoice.id, name: "Tile" },
    });
    await expect(invoiceLines.remove(line.id, t.company.id)).rejects.toThrow(
      /below/,
    );
    expect(
      await prisma.invoiceLineItem.count({ where: { invoiceId: invoice.id } }),
    ).toBe(2);
    expect(
      Number(
        (await prisma.invoice.findUniqueOrThrow({ where: { id: invoice.id } }))
          .discountAmount,
      ),
    ).toBe(0);
  });
  it("rejects foreign or unrelated proposals and estimates on invoice creation/update", async () => {
    const t = await tenant();
    const foreign = await tenant();
    const proposal = await proposals.create(foreign.company.id, {
      estimate_id: foreign.estimate.id,
    });
    const input = { project_id: t.project.id, client_id: t.client.id };
    await expect(
      invoices.create(t.company.id, t.user.id, {
        ...input,
        proposal_id: proposal.id,
      }),
    ).rejects.toThrow(/Proposal/);
    await expect(
      invoices.create(t.company.id, t.user.id, {
        ...input,
        estimate_id: foreign.estimate.id,
      }),
    ).rejects.toThrow(/Estimate/);
    const invoice = await invoices.create(t.company.id, t.user.id, input);
    await expect(
      invoices.update(invoice.id, t.company.id, { proposal_id: proposal.id }),
    ).rejects.toThrow(/Proposal/);
    const secondProject = await prisma.project.create({
      data: {
        companyId: t.company.id,
        title: "Other job",
        projectType: "CUSTOM",
      },
    });
    const secondEstimate = await prisma.estimate.create({
      data: {
        companyId: t.company.id,
        projectId: secondProject.id,
        estimateNumber: "EST-OTHER",
      },
    });
    await expect(
      invoices.create(t.company.id, t.user.id, {
        ...input,
        estimate_id: secondEstimate.id,
      }),
    ).rejects.toThrow(/Estimate/);
  });
  it("serializes concurrent line mutations and rounds stored cents consistently", async () => {
    const t = await tenant();
    const invoice = await invoices.create(t.company.id, t.user.id, {
      project_id: t.project.id,
      client_id: t.client.id,
    });
    await Promise.all(
      Array.from({ length: 8 }, (_, i) =>
        invoiceLines.create(invoice.id, t.company.id, {
          name: `Line ${i}`,
          quantity: 1,
          unit: "lot",
          unit_cost: 10,
          sort_order: i,
        }),
      ),
    );
    const line = await invoiceLines.create(invoice.id, t.company.id, {
      name: "Rounding",
      quantity: 1.005,
      unit: "lot",
      unit_cost: 0.005,
      sort_order: 8,
    });
    expect(Number(line.quantity)).toBe(1.01);
    expect(Number(line.unitCost)).toBe(0.01);
    expect(Number(line.lineTotal)).toBe(0.01);
    const fresh = await prisma.invoice.findUniqueOrThrow({
      where: { id: invoice.id },
    });
    expect(Number(fresh.subtotal)).toBe(80.01);
    expect(Number(fresh.taxAmount)).toBe(6.6);
    expect(Number(fresh.amountDue)).toBe(86.61);
  });
});

describe("estimate line totals and hierarchy", () => {
  it("keeps estimate totals current for discount-only updates", async () => {
    const t = await tenant();
    const discounted = await estimates.update(
      t.estimate.id,
      t.company.id,
      t.user.id,
      { discount_amount: 120 },
    );
    expect(Number(discounted.totalAmount)).toBe(1000);
  });
  it("serializes concurrent additions and floors excessive discounts at zero", async () => {
    const t = await tenant();
    await Promise.all(
      Array.from({ length: 8 }, (_, i) =>
        estimateLines.create(
          t.estimate.id,
          t.company.id,
          otherLine(`Added ${i}`),
        ),
      ),
    );
    let fresh = await prisma.estimate.findUniqueOrThrow({
      where: { id: t.estimate.id },
    });
    expect(Number(fresh.subtotalOther)).toBe(80);
    expect(Number(fresh.totalAmount)).toBe(1200);
    await prisma.estimate.update({
      where: { id: t.estimate.id },
      data: { discountAmount: 5000 },
    });
    await estimateLines.create(
      t.estimate.id,
      t.company.id,
      otherLine("Discount trigger"),
    );
    fresh = await prisma.estimate.findUniqueOrThrow({
      where: { id: t.estimate.id },
    });
    expect(Number(fresh.totalAmount)).toBe(0);
  });
  it("rejects cross-estimate parents and cycles, detaches children when parent is removed", async () => {
    const t = await tenant();
    const foreign = await tenant();
    const foreignLine = await prisma.estimateLineItem.findFirstOrThrow({
      where: { estimateId: foreign.estimate.id },
    });
    await expect(
      estimateLines.create(t.estimate.id, t.company.id, {
        ...otherLine("Bad parent"),
        parent_line_item_id: foreignLine.id,
      }),
    ).rejects.toThrow(/EstimateLineItem/);
    const parent = await estimateLines.create(
      t.estimate.id,
      t.company.id,
      otherLine("Parent"),
    );
    const child = await estimateLines.create(t.estimate.id, t.company.id, {
      ...otherLine("Child"),
      parent_line_item_id: parent.id,
    });
    await expect(
      estimateLines.update(parent.id, t.company.id, {
        parent_line_item_id: child.id,
      }),
    ).rejects.toThrow(/cycle/);
    await estimateLines.remove(parent.id, t.company.id);
    expect(
      (
        await prisma.estimateLineItem.findUniqueOrThrow({
          where: { id: child.id },
        })
      ).parentLineItemId,
    ).toBeNull();
  });
  it("rejects material suggestion links from a different project and rolls batch creation back", async () => {
    const t = await tenant();
    const foreign = await tenant();
    const generation = await prisma.aIGeneration.create({
      data: {
        projectId: foreign.project.id,
        prompt: "Fixture",
        systemPrompt: "Fixture",
      },
    });
    const material = await prisma.materialSuggestion.create({
      data: {
        generationId: generation.id,
        projectId: foreign.project.id,
        name: "Foreign tile",
        category: "Tile",
        qualityTier: "STANDARD",
        estimatedCost: 10,
        unit: "sqft",
        quantity: 1,
      },
    });
    await expect(
      estimateLines.createBatch(t.estimate.id, t.company.id, [
        otherLine("Good"),
        { ...otherLine("Bad"), source_material_suggestion_id: material.id },
      ]),
    ).rejects.toThrow(/MaterialSuggestion/);
    expect(
      await prisma.estimateLineItem.count({
        where: { estimateId: t.estimate.id },
      }),
    ).toBe(2);
  });
});

describe("proposal decisions and shared page freshness", () => {
  it("records one authoritative decision under conflicting concurrent responses", async () => {
    const t = await tenant();
    const proposal = await proposals.create(t.company.id, {
      estimate_id: t.estimate.id,
    });
    await prisma.proposal.update({
      where: { id: proposal.id },
      data: { status: "SENT", sentAt: new Date() },
    });
    const results = await Promise.all([
      proposals.respondToProposal(proposal.shareToken!, {
        decision: "approved",
      }),
      proposals.respondToProposal(proposal.shareToken!, {
        decision: "declined",
      }),
    ]);
    expect(results[0].status).toBe(results[1].status);
    expect(
      await prisma.activityLogEntry.count({
        where: {
          projectId: t.project.id,
          action: { in: ["PROPOSAL_APPROVED", "PROPOSAL_DECLINED"] },
        },
      }),
    ).toBe(1);
    expect(
      (
        await prisma.estimate.findUniqueOrThrow({
          where: { id: t.estimate.id },
        })
      ).status,
    ).toBe(results[0].status);
  });
  it("keeps Date values serializable and reflects updates and deletion immediately", async () => {
    const t = await tenant();
    const proposal = await proposals.create(t.company.id, {
      estimate_id: t.estimate.id,
    });
    await prisma.proposal.update({
      where: { id: proposal.id },
      data: { status: "SENT", sentAt: new Date() },
    });
    for (let i = 0; i < 2; i++)
      expect(
        toSharedProposalDto(
          await proposals.getByShareToken(proposal.shareToken!),
        ).proposal.viewed_at,
      ).toMatch(/^\d{4}-/);
    expect(
      await prisma.activityLogEntry.count({
        where: { projectId: t.project.id, action: "PROPOSAL_VIEWED" },
      }),
    ).toBe(1);
    await proposals.update(proposal.id, t.company.id, {
      title: "Revised proposal",
    });
    expect((await proposals.getByShareToken(proposal.shareToken!)).title).toBe(
      "Revised proposal",
    );
    await proposals.remove(proposal.id, t.company.id);
    await expect(
      proposals.getByShareToken(proposal.shareToken!),
    ).rejects.toThrow(/Proposal/);
  });
  it("does not reopen finished projects and rejects resend after a client decision", async () => {
    const t = await tenant();
    const proposal = await proposals.create(t.company.id, {
      estimate_id: t.estimate.id,
    });
    await prisma.proposal.update({
      where: { id: proposal.id },
      data: { status: "SENT" },
    });
    await prisma.project.update({
      where: { id: t.project.id },
      data: { status: "INVOICED" },
    });
    await proposals.respondToProposal(proposal.shareToken!, {
      decision: "approved",
    });
    expect(
      (await prisma.project.findUniqueOrThrow({ where: { id: t.project.id } }))
        .status,
    ).toBe("INVOICED");
    await expect(
      proposals.send(proposal.id, t.company.id, t.user.id),
    ).rejects.toThrow(/new proposal/);
    await expect(
      proposals.update(proposal.id, t.company.id, {
        terms_and_conditions: "Changed terms",
      }),
    ).rejects.toThrow(/cannot be edited/);
  });
});

describe("usage reservations and selected quality tier", () => {
  it("allows only one request to consume the final starter credit and records one event", async () => {
    const t = await tenant("FREE_STARTER");
    await prisma.usageBucket.create({
      data: {
        userId: t.user.id,
        companyId: t.company.id,
        metricCode: "AI_GENERATION",
        source: "STARTER_CREDITS",
        includedQuantity: 5,
        consumedQuantity: 4,
      },
    });
    const results = await Promise.allSettled(
      Array.from({ length: 6 }, () =>
        gateAIAction({
          userId: t.user.id,
          companyId: t.company.id,
          metric: "AI_GENERATION",
        }),
      ),
    );
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(
      await prisma.usageEvent.count({ where: { userId: t.user.id } }),
    ).toBe(1);
    expect(
      (
        await prisma.usageBucket.findFirstOrThrow({
          where: { userId: t.user.id },
        })
      ).consumedQuantity,
    ).toBe(5);
  });
  it("refunds failed actions so credits and rolling limits can be retried", async () => {
    const t = await tenant("FREE_STARTER");
    const opts = {
      userId: t.user.id,
      companyId: t.company.id,
      metric: "AI_GENERATION" as const,
    };
    const reservation = await gateAIAction(opts);
    await expect(
      runReservedAction(reservation, async () => {
        throw new Error("Database failure");
      }),
    ).rejects.toThrow(/Database failure/);
    expect(
      await prisma.usageEvent.count({ where: { userId: t.user.id } }),
    ).toBe(0);
    expect(
      (
        await prisma.usageBucket.findFirstOrThrow({
          where: { userId: t.user.id },
        })
      ).consumedQuantity,
    ).toBe(0);
    await expect(gateAIAction(opts)).resolves.toBeDefined();
  });
  it("enforces the independent estimate cap atomically and keeps estimates Pro-only", async () => {
    const t = await tenant("PRO_MONTHLY", {
      LIMITS: { ESTIMATE_GENERATED: { monthly: 1 } },
    });
    const opts = {
      userId: t.user.id,
      companyId: t.company.id,
      metric: "ESTIMATE_GENERATED" as const,
    };
    const results = await Promise.allSettled([
      gateAIAction(opts),
      gateAIAction(opts),
    ]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    await expect(
      gateAIAction({ ...opts, metric: "AI_GENERATION" }),
    ).resolves.toBeDefined();
    const free = await tenant("FREE_STARTER");
    await expect(
      gateAIAction({
        userId: free.user.id,
        companyId: free.company.id,
        metric: "ESTIMATE_GENERATED",
      }),
    ).rejects.toThrow(/subscription/);
    expect(
      await prisma.usageBucket.count({ where: { userId: free.user.id } }),
    ).toBe(0);
  });
  it("returns saved Premium through detail/list and snapshots it on manual estimates; Auto stays null", async () => {
    const t = await tenant();
    const detail = await projects.getById(t.project.id, t.company.id);
    expect(toProjectListDto(detail).quality_tier).toBe("premium");
    const list = await projects.list(t.company.id, {});
    expect(toProjectListDto(list.items[0]).quality_tier).toBe("premium");
    expect(
      (
        await estimates.create(t.company.id, t.user.id, {
          project_id: t.project.id,
        })
      ).qualityTier,
    ).toBe("PREMIUM");
    await prisma.project.update({
      where: { id: t.project.id },
      data: { qualityTier: null },
    });
    expect(await readProjectQualityTier(t.project.id, t.company.id)).toBeNull();
    expect(
      await readProjectQualityTier(t.project.id, "another-company"),
    ).toBeNull();
  });
});

describe("single-use password reset", () => {
  it("permits only one concurrent password reset and invalidates sessions atomically", async () => {
    const t = await tenant();
    await prisma.user.update({
      where: { id: t.user.id },
      data: {
        passwordResetToken: "single-use",
        passwordResetExpiresAt: new Date(Date.now() + 60_000),
      },
    });
    await prisma.refreshToken.create({
      data: {
        userId: t.user.id,
        token: randomUUID(),
        expiresAt: new Date(Date.now() + 60_000),
      },
    });
    const passwords = ["FirstPassword123", "SecondPassword123"];
    const results = await Promise.allSettled(
      passwords.map((new_password) =>
        resetPassword({ token: "single-use", new_password }),
      ),
    );
    const winner = results.findIndex((r) => r.status === "fulfilled");
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    const fresh = await prisma.user.findUniqueOrThrow({
      where: { id: t.user.id },
    });
    expect(await verifyPassword(passwords[winner], fresh.passwordHash!)).toBe(
      true,
    );
    expect(fresh.passwordResetToken).toBeNull();
    expect(
      await prisma.refreshToken.count({ where: { userId: t.user.id } }),
    ).toBe(0);
  });
});
