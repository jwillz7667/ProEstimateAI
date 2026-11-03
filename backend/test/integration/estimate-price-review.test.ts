import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../../src/config/database";
import * as items from "../../src/modules/estimate-line-items/estimate-line-items.service";
import { reviewEstimatePriceSchema } from "../../src/modules/estimate-line-items/estimate-line-items.validators";
import { requireWriteAccess } from "../../src/middleware/write-access.middleware";
import type { Request, Response } from "express";
import * as library from "../../src/modules/estimate-library/estimate-library.service";
import { saveItemSchema } from "../../src/modules/estimate-library/estimate-library.validators";

beforeEach(async () => { await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE'); });
async function fixture() {
  const company = await prisma.company.create({ data: { name: "Price review" } });
  const user = await prisma.user.create({ data: { companyId: company.id, email: `${randomUUID()}@example.test`, fullName: "Contractor" } });
  const project = await prisma.project.create({ data: { companyId: company.id, title: "Kitchen", projectType: "KITCHEN" } });
  const estimate = await prisma.estimate.create({ data: { companyId: company.id, projectId: project.id, estimateNumber: "CHECK-1" } });
  const item = await items.create(estimate.id, company.id, { category: "materials", name: "Cabinet handles", quantity: 10, unit: "each", unit_cost: 5, markup_percent: 20, tax_rate: 0, sort_order: 0 });
  return { company, user, estimate, item };
}
const review = () => reviewEstimatePriceSchema.parse({ expected_name: "Cabinet handles", expected_unit: "each", expected_unit_cost: 5, expected_quantity: 10, price_confirmed: true, source_label: "Supplier quote", source_url: "https://example.com/hardware", quantity_confirmed: true, quantity_basis: "Counted on site" });

describe("contractor price and quantity checks", () => {
  it("records a self-attested source and date without changing the estimate price", async () => {
    const { company, user, estimate, item } = await fixture();
    const before = await prisma.estimate.findUniqueOrThrow({ where: { id: estimate.id } });
    const checked = await items.reviewPrice(item.id, company.id, user.id, review());
    expect(checked.priceCheckedByUserId).toBe(user.id); expect(checked.priceCheckedAt).not.toBeNull();
    expect(checked.quantityBasis).toBe("Counted on site"); expect(checked.quantityCheckedAt).not.toBeNull();
    expect(checked.priceOrigin).toBe("CONTRACTOR_ENTERED");
    expect((await prisma.estimate.findUniqueOrThrow({ where: { id: estimate.id } })).totalAmount.toString()).toBe(before.totalAmount.toString());
  });
  it("invalidates only the affected checks when a draft is edited", async () => {
    const { company, user, item } = await fixture();
    await items.reviewPrice(item.id, company.id, user.id, review());
    let edited = await items.update(item.id, company.id, { markup_percent: 25 });
    expect(edited.priceCheckedAt).not.toBeNull(); expect(edited.quantityCheckedAt).not.toBeNull();
    edited = await items.update(item.id, company.id, { quantity: 11 });
    expect(edited.priceCheckedAt).not.toBeNull(); expect(edited.quantityCheckedAt).toBeNull();
    edited = await items.update(item.id, company.id, { unit_cost: 6 });
    expect(edited.priceCheckedAt).toBeNull(); expect(edited.priceSourceUrl).toBeNull();
  });
  it("preserves an existing quantity check when only the price is rechecked", async () => {
    const { company, user, item } = await fixture();
    const first = await items.reviewPrice(item.id, company.id, user.id, review());
    const second = await items.reviewPrice(item.id, company.id, user.id, { ...review(), quantity_confirmed: false, quantity_basis: null });
    expect(second.quantityCheckedAt).toEqual(first.quantityCheckedAt); expect(second.quantityBasis).toBe(first.quantityBasis);
  });
  it("rejects stale, cross-tenant and already-sent checks", async () => {
    const { company, user, estimate, item } = await fixture();
    await expect(items.reviewPrice(item.id, company.id, user.id, { ...review(), expected_unit_cost: 9 })).rejects.toMatchObject({ statusCode: 409 });
    const stranger = await prisma.company.create({ data: { name: "Other tenant" } });
    await expect(items.reviewPrice(item.id, stranger.id, user.id, review())).rejects.toMatchObject({ statusCode: 404 });
    await prisma.estimate.update({ where: { id: estimate.id }, data: { status: "SENT" } });
    await expect(items.reviewPrice(item.id, company.id, user.id, review())).rejects.toMatchObject({ statusCode: 409 });
  });
  it("does not treat an unchecked box or unsafe URL as a supplier check", async () => {
    expect(reviewEstimatePriceSchema.safeParse({ ...review(), price_confirmed: false }).success).toBe(false);
    for (const source_url of ["javascript:alert(1)", "file:///private/receipt", "https://user:pass@example.com"]) {
      expect(reviewEstimatePriceSchema.safeParse({ ...review(), source_url }).success).toBe(false);
    }
    expect(reviewEstimatePriceSchema.safeParse({ ...review(), quantity_basis: "" }).success).toBe(false);
  });
  it("supports the full 1000% markup range accepted by the manual editor", async () => {
    const { company, user, estimate, item } = await fixture();
    const edited = await items.update(item.id, company.id, { markup_percent: 1000 });
    expect(Number(edited.lineTotal)).toBe(550);
    const saved = await library.saveItem(company.id, saveItemSchema.parse({ request_id: randomUUID(), category: "materials", name: "High markup item", quantity: 1, unit: "each", unit_cost: 5, markup_percent: 1000 }));
    expect(Number(saved.markupPercent)).toBe(1000);
    const applied = await library.applyItem(company.id, saved.id, { request_id: randomUUID(), estimate_id: estimate.id });
    expect(Number(applied.lineTotal)).toBe(55);
    const template = await library.saveTemplate(company.id, user.id, { request_id: randomUUID(), estimate_id: estimate.id, name: "Reusable high markup" });
    const project = await prisma.project.create({ data: { companyId: company.id, title: "Another project" } });
    const copy = await library.instantiateTemplate(company.id, user.id, template.id, { request_id: randomUUID(), project_id: project.id });
    expect(Number(copy.totalAmount)).toBe(605);
  });
  it("blocks VIEWER API mutations while preserving reads and editor access", async () => {
    const { company, user } = await fixture();
    for (const role of ["OWNER", "ADMIN", "ESTIMATOR", "VIEWER"] as const) {
      await prisma.user.update({ where: { id: user.id }, data: { role } });
      for (const method of ["POST", "PATCH", "PUT", "DELETE"]) {
        let failure: unknown;
        await requireWriteAccess({ userId: user.id, companyId: company.id, method } as Request, {} as Response, (error) => { failure = error; });
        if (role === "VIEWER") expect(failure).toMatchObject({ statusCode: 403 }); else expect(failure).toBeUndefined();
      }
    }
  });
});
