import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import { EstimateStatus } from "@prisma/client";
import { prisma } from "../../src/config/database";
import { create, createBatch, remove, update } from "../../src/modules/estimate-line-items/estimate-line-items.service";

const input = {
  category: "materials" as const, name: "Cabinet hardware", quantity: 2,
  unit: "each", unit_cost: 10, markup_percent: 10, tax_rate: 0.1, sort_order: 0,
};

async function fixture() {
  const company = await prisma.company.create({ data: { name: `Estimate editing ${randomUUID()}` } });
  const project = await prisma.project.create({ data: {
    companyId: company.id, title: "Manual kitchen project", projectType: "KITCHEN",
  } });
  const estimate = await prisma.estimate.create({ data: {
    companyId: company.id, projectId: project.id, estimateNumber: "EDIT-1",
  } });
  const line = await create(estimate.id, company.id, input);
  return { company, estimate, line };
}

describe("estimate editor mutations", () => {
  beforeEach(async () => {
    await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE');
  });

  it("recalculates canonical pre-tax, tax and total after draft CRUD without paid access", async () => {
    const { company, estimate, line } = await fixture();
    await update(line.id, company.id, { quantity: 3 });
    let saved = await prisma.estimate.findUniqueOrThrow({ where: { id: estimate.id } });
    expect(Number(saved.subtotalMaterials)).toBe(33);
    expect(Number(saved.taxAmount)).toBe(3.3);
    expect(Number(saved.totalAmount)).toBe(36.3);
    await remove(line.id, company.id);
    saved = await prisma.estimate.findUniqueOrThrow({ where: { id: estimate.id } });
    expect(Number(saved.totalAmount)).toBe(0);
  });

  for (const status of ["SENT", "APPROVED", "DECLINED", "EXPIRED"] as EstimateStatus[]) {
    it(`keeps ${status.toLowerCase()} line items and totals unchanged when a stale client edits`, async () => {
      const { company, estimate, line } = await fixture();
      await prisma.estimate.update({ where: { id: estimate.id }, data: { status } });
      const before = await prisma.estimate.findUniqueOrThrow({ where: { id: estimate.id } });
      for (const action of [
        () => create(estimate.id, company.id, input),
        () => createBatch(estimate.id, company.id, [input, input]),
        () => update(line.id, company.id, { unit_cost: 999 }),
        () => remove(line.id, company.id),
      ]) {
        await expect(action()).rejects.toMatchObject({ statusCode: 409, code: "CONFLICT" });
      }
      expect(await prisma.estimateLineItem.findMany({ where: { estimateId: estimate.id } })).toHaveLength(1);
      expect(Number((await prisma.estimateLineItem.findUniqueOrThrow({ where: { id: line.id } })).unitCost)).toBe(10);
      const after = await prisma.estimate.findUniqueOrThrow({ where: { id: estimate.id } });
      expect(after.totalAmount.toString()).toBe(before.totalAmount.toString());
      expect(after.updatedAt).toEqual(before.updatedAt);
    });
  }

  it("preserves tenant isolation for draft mutations", async () => {
    const { estimate, line } = await fixture();
    const other = await prisma.company.create({ data: { name: "Unrelated company" } });
    await expect(create(estimate.id, other.id, input)).rejects.toMatchObject({ statusCode: 404 });
    await expect(update(line.id, other.id, { unit_cost: 0 })).rejects.toMatchObject({ statusCode: 404 });
    await expect(remove(line.id, other.id)).rejects.toMatchObject({ statusCode: 404 });
  });
});
