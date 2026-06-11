import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../../src/config/database";
import { createFromEstimate } from "../../src/modules/invoices/invoices.service";
import { PaywallError, ValidationError } from "../../src/lib/errors";

async function resetTables() {
  // CASCADE from Company + Plan clears users, entitlements, projects,
  // estimates, invoices and every dependent row.
  await prisma.$executeRawUnsafe(
    `TRUNCATE TABLE "Company", "Plan" RESTART IDENTITY CASCADE;`,
  );
}

async function seedPlans() {
  const proPlan = await prisma.plan.create({
    data: {
      code: "PRO_MONTHLY",
      displayName: "Pro Monthly",
      description: "Pro",
      featuresJson: { CAN_CREATE_INVOICE: true },
    },
  });
  const freePlan = await prisma.plan.create({
    data: {
      code: "FREE_STARTER",
      displayName: "Starter",
      description: "Free",
      featuresJson: {},
    },
  });
  return { proPlan, freePlan };
}

async function seedUser(args: {
  planId: string;
  status: "PRO_ACTIVE" | "FREE";
  prefix: string;
}) {
  const company = await prisma.company.create({
    data: { name: "Convert Co", invoicePrefix: "INV", nextInvoiceNumber: 5001 },
  });
  const user = await prisma.user.create({
    data: {
      companyId: company.id,
      email: `${args.prefix}-${randomUUID()}@example.com`,
      fullName: "Convert User",
      passwordHash: "not-used",
    },
  });
  await prisma.userEntitlement.create({
    data: {
      userId: user.id,
      companyId: company.id,
      planId: args.planId,
      status: args.status,
    },
  });
  return { company, user };
}

async function seedEstimate(companyId: string, opts: { withClient: boolean }) {
  let clientId: string | null = null;
  if (opts.withClient) {
    const client = await prisma.client.create({
      data: { companyId, name: "Jane Homeowner", email: "jane@example.com" },
    });
    clientId = client.id;
  }
  const project = await prisma.project.create({
    data: {
      companyId,
      clientId,
      title: "Bathroom Remodel",
      projectType: "BATHROOM",
      status: "DRAFT",
    },
  });
  const estimate = await prisma.estimate.create({
    data: {
      projectId: project.id,
      companyId,
      estimateNumber: "EST-1001",
      title: "Bathroom Estimate",
      subtotalMaterials: 800,
      subtotalLabor: 240,
      subtotalOther: 0,
      taxAmount: 80,
      discountAmount: 0,
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
        markupPercent: 0,
        taxRate: 0.1,
        lineTotal: 800,
        sortOrder: 0,
      },
      {
        // 2 × $100 + 20% markup → pre-tax lineTotal 240; effective unit price 120.
        estimateId: estimate.id,
        category: "LABOR",
        name: "Install labor",
        quantity: 2,
        unit: "hour",
        unitCost: 100,
        markupPercent: 20,
        taxRate: 0,
        lineTotal: 240,
        sortOrder: 1,
      },
    ],
  });
  return { project, estimate, clientId };
}

describe("invoices.createFromEstimate — convert-to-invoice", () => {
  let proPlanId: string;
  let freePlanId: string;

  beforeEach(async () => {
    await resetTables();
    const { proPlan, freePlan } = await seedPlans();
    proPlanId = proPlan.id;
    freePlanId = freePlan.id;
  });

  it("mirrors the estimate's money exactly and folds markup into unit cost", async () => {
    const { company, user } = await seedUser({
      planId: proPlanId,
      status: "PRO_ACTIVE",
      prefix: "pro",
    });
    const { estimate, clientId } = await seedEstimate(company.id, {
      withClient: true,
    });

    const invoice = await createFromEstimate(company.id, user.id, estimate.id, {
      due_date: "2026-07-01T00:00:00.000Z",
      notes: "Net 30",
      payment_instructions: "ACH to account 1234",
    });

    expect(invoice.estimateId).toBe(estimate.id);
    expect(invoice.clientId).toBe(clientId);
    expect(invoice.status).toBe("DRAFT");
    expect(invoice.invoiceNumber).toBe("INV-5001");
    expect(Number(invoice.subtotal)).toBe(1040);
    expect(Number(invoice.taxAmount)).toBeCloseTo(80, 2);
    expect(Number(invoice.totalAmount)).toBeCloseTo(1120, 2);
    expect(Number(invoice.amountPaid)).toBe(0);
    expect(Number(invoice.amountDue)).toBeCloseTo(1120, 2);
    expect(invoice.notes).toBe("Net 30");
    expect(invoice.paymentInstructions).toBe("ACH to account 1234");
    expect(invoice.dueDate?.toISOString()).toBe("2026-07-01T00:00:00.000Z");

    const lines = await prisma.invoiceLineItem.findMany({
      where: { invoiceId: invoice.id },
      orderBy: { sortOrder: "asc" },
    });
    expect(lines).toHaveLength(2);
    expect(lines[0].name).toBe("Tile");
    expect(Number(lines[0].unitCost)).toBe(800);
    expect(Number(lines[0].lineTotal)).toBe(800);
    expect(lines[1].name).toBe("Install labor");
    // Markup folded into the client-facing unit price: 240 / 2 = 120.
    expect(Number(lines[1].unitCost)).toBe(120);
    expect(Number(lines[1].lineTotal)).toBe(240);
  });

  it("throws ValidationError when the estimate's project has no client", async () => {
    const { company, user } = await seedUser({
      planId: proPlanId,
      status: "PRO_ACTIVE",
      prefix: "pro",
    });
    const { estimate } = await seedEstimate(company.id, { withClient: false });

    await expect(
      createFromEstimate(company.id, user.id, estimate.id, {}),
    ).rejects.toBeInstanceOf(ValidationError);

    // No invoice and no number burned on the failed attempt.
    expect(await prisma.invoice.count()).toBe(0);
  });

  it("throws PaywallError (402) for a free-tier user", async () => {
    const { company, user } = await seedUser({
      planId: freePlanId,
      status: "FREE",
      prefix: "free",
    });
    const { estimate } = await seedEstimate(company.id, { withClient: true });

    const err = await createFromEstimate(
      company.id,
      user.id,
      estimate.id,
      {},
    ).catch((e) => e);

    expect(err).toBeInstanceOf(PaywallError);
    expect((err as PaywallError).statusCode).toBe(402);
    expect(await prisma.invoice.count()).toBe(0);
  });
});
