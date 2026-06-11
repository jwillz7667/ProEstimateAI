import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { prisma } from "../../src/config/database";

// The AI text model (DeepSeek) is a third-party network call — mock it and
// return a fixed estimate so the test exercises persistence + tax math, not
// the model. gateAIAction / recordUsage are the entitlement layer; stub them
// so this test stays focused on the line-item tax accounting rather than
// re-seeding a full free-tier entitlement.
vi.mock("../../src/lib/estimate-gen", () => ({
  generateEstimate: vi.fn(),
}));
vi.mock("../../src/modules/commerce/entitlement-gate", () => ({
  gateAIAction: vi.fn().mockResolvedValue(undefined),
}));
vi.mock("../../src/lib/usage-limits", () => ({
  recordUsage: vi.fn().mockResolvedValue(undefined),
}));

import { generateEstimate } from "../../src/lib/estimate-gen";
import { generateAI } from "../../src/modules/estimates/estimates.service";
import { create as createLineItem } from "../../src/modules/estimate-line-items/estimate-line-items.service";

const generateEstimateMock = generateEstimate as unknown as ReturnType<
  typeof vi.fn
>;

async function resetEstimateTables() {
  // CASCADE from Company wipes User, Project, Estimate, EstimateLineItem,
  // ActivityLogEntry and every other table transitively referencing it.
  await prisma.$executeRawUnsafe(
    `TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE;`,
  );
}

async function seedCompanyUserProject() {
  const company = await prisma.company.create({
    data: { name: "Tax Math Co", estimatePrefix: "EST", nextEstimateNumber: 1001 },
  });
  const user = await prisma.user.create({
    data: {
      companyId: company.id,
      email: `tax-${randomUUID()}@example.com`,
      fullName: "Tax Tester",
      passwordHash: "not-used",
    },
  });
  const project = await prisma.project.create({
    data: {
      companyId: company.id,
      title: "Kitchen Remodel",
      projectType: "KITCHEN",
      status: "DRAFT",
    },
  });
  return { company, user, project };
}

describe("estimates.generateAI — line-item tax accounting", () => {
  beforeEach(async () => {
    await resetEstimateTables();
    generateEstimateMock.mockReset();
    // One materials line: 1 × $960, no markup, taxed at 10%.
    //   pre-tax subtotal = 960, tax = 96, total = 1056.
    generateEstimateMock.mockResolvedValue({
      title: "Generated Kitchen Estimate",
      overview: "Scope of work.",
      lineItems: [
        {
          category: "materials",
          name: "Cabinet package",
          description: "Shaker uppers and lowers",
          quantity: 1,
          unit: "lot",
          unitCost: 960,
          markupPercent: 0,
          taxRate: 0.1,
        },
      ],
      assumptions: "A",
      exclusions: "E",
      terms: "T",
      contingencyPercent: 10,
      validDays: 30,
    });
  });

  it("stores lineTotal pre-tax and tax separately so the total isn't double-taxed", async () => {
    const { company, user, project } = await seedCompanyUserProject();

    const estimate = await generateAI(company.id, user.id, project.id);

    expect(Number(estimate.subtotalMaterials)).toBe(960);
    expect(Number(estimate.taxAmount)).toBeCloseTo(96, 2);
    expect(Number(estimate.totalAmount)).toBeCloseTo(1056, 2);

    const items = await prisma.estimateLineItem.findMany({
      where: { estimateId: estimate.id },
    });
    expect(items).toHaveLength(1);
    // The critical invariant: lineTotal is the PRE-TAX subtotal (960), not the
    // tax-inclusive 1056. Storing it tax-inclusive double-counted tax on recalc.
    expect(Number(items[0].lineTotal)).toBe(960);
    expect(Number(items[0].taxRate)).toBeCloseTo(0.1, 4);
  });

  it("keeps tax single-counted when totals are recalculated after an edit", async () => {
    const { company, user, project } = await seedCompanyUserProject();

    const estimate = await generateAI(company.id, user.id, project.id);

    // Adding any line item triggers recalculateEstimateTotals, which re-reads
    // every line's lineTotal and re-applies `lineTotal * taxRate`. If the AI
    // line had been stored tax-inclusive (1056), recalc would compute
    // tax = 1056 × 0.10 = 105.6 and inflate the total. A $0 line is a no-op
    // contributor, so the totals must be unchanged.
    await createLineItem(estimate.id, company.id, {
      category: "other",
      name: "Miscellaneous",
      quantity: 1,
      unit: "lot",
      unit_cost: 0,
      markup_percent: 0,
      tax_rate: 0,
      sort_order: 1,
    });

    const reloaded = await prisma.estimate.findUniqueOrThrow({
      where: { id: estimate.id },
    });
    expect(Number(reloaded.subtotalMaterials)).toBe(960);
    expect(Number(reloaded.taxAmount)).toBeCloseTo(96, 2);
    expect(Number(reloaded.totalAmount)).toBeCloseTo(1056, 2);
  });
});
