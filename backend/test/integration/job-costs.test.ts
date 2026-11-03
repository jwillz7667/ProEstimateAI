import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import sharp from "sharp";
import { prisma } from "../../src/config/database";
import * as costs from "../../src/modules/job-costs/job-costs.service";
import { createJobCostSchema } from "../../src/modules/job-costs/job-costs.validators";

beforeEach(async () => { await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE'); });
async function fixture() {
  const company = await prisma.company.create({ data: { name: "Job cost tests" } });
  const user = await prisma.user.create({ data: { companyId: company.id, email: `${randomUUID()}@example.test`, fullName: "Contractor" } });
  const project = await prisma.project.create({ data: { companyId: company.id, title: "Kitchen", projectType: "KITCHEN" } });
  return { company, user, project };
}
const input = (overrides = {}) => createJobCostSchema.parse({ request_id: randomUUID(), category: "materials", description: "Paint receipt", amount: 33.33, currency_code: "USD", recorded_at: "2026-10-01T12:00:00.000Z", ...overrides });

describe("actual job costs", () => {
  it("records once under concurrent retries and rejects a reused key with altered prices", async () => {
    const { company, user, project } = await fixture(); const request = input();
    const results = await Promise.all([1, 2, 3].map(() => costs.create(project.id, company.id, user.id, request)));
    expect(new Set(results.map((entry) => entry.id)).size).toBe(1);
    expect(await prisma.jobCostEntry.count()).toBe(1);
    await expect(costs.create(project.id, company.id, user.id, { ...request, amount: 34 })).rejects.toMatchObject({ statusCode: 409 });
  });
  it("calculates hourly labor and keeps different currencies separate", async () => {
    const { company, user, project } = await fixture();
    await costs.create(project.id, company.id, user.id, input({ category: "labor", amount: undefined, labor_hours: 2.5, hourly_rate: 20 }));
    await costs.create(project.id, company.id, user.id, input({ amount: 10, currency_code: "EUR" }));
    const result = await costs.list(project.id, company.id, {});
    expect(result.summary.recorded_cost).toBe(50);
    expect(result.summary.costs_by_currency).toEqual([
      { currency_code: "EUR", materials: 10, labor: 0, other: 0, total: 10 },
      { currency_code: "USD", materials: 0, labor: 50, other: 0, total: 50 },
    ]);
    await expect(costs.create(project.id, company.id, user.id, input({ category: "labor", amount: 99, labor_hours: 2, hourly_rate: 20 }))).rejects.toMatchObject({ statusCode: 400 });
  });
  it("uses the latest accepted quote and excludes sales tax from the comparison", async () => {
    const { company, user, project } = await fixture();
    const approved = await prisma.estimate.create({ data: { companyId: company.id, projectId: project.id, estimateNumber: "EST-1", status: "APPROVED", totalAmount: 220, taxAmount: 20 } });
    await prisma.estimateLineItem.create({ data: { estimateId: approved.id, category: "MATERIALS", name: "Paint", quantity: 2, unit: "can", unitCost: 50, lineTotal: 200 } });
    await prisma.estimate.create({ data: { companyId: company.id, projectId: project.id, estimateNumber: "EST-2", status: "DRAFT", totalAmount: 9999 } });
    await costs.create(project.id, company.id, user.id, input());
    const result = await costs.list(project.id, company.id, {});
    expect(result.summary.estimate_number).toBe("EST-1");
    expect(result.summary.quote_before_tax).toBe(200); expect(result.summary.estimated_item_cost).toBe(100);
    expect(result.summary.quote_less_recorded_cost).toBe(166.67);
  });
  it("voids a mistaken expense once without erasing its audit record", async () => {
    const { company, user, project } = await fixture(); const request = input();
    const entry = await costs.create(project.id, company.id, user.id, request);
    await costs.voidEntry(entry.id, company.id, user.id); await costs.voidEntry(entry.id, company.id, user.id);
    expect((await costs.list(project.id, company.id, {})).items).toHaveLength(0);
    const history = await costs.list(project.id, company.id, {}, true);
    expect(history.items).toHaveLength(1);
    expect(history.items[0].voided_at).not.toBeNull();
    expect(history.summary.recorded_cost).toBe(0);
    expect(history.summary.costs_by_currency).toEqual([]);
    expect(await prisma.jobCostEntry.count()).toBe(1);
    expect((await costs.create(project.id, company.id, user.id, request)).voided_at).not.toBeNull();
  });
  it("paginates without losing the full-project cost summary", async () => {
    const { company, user, project } = await fixture();
    for (let i = 0; i < 3; i++) await costs.create(project.id, company.id, user.id, input({ amount: 10 }));
    const first = await costs.list(project.id, company.id, { pageSize: 2 });
    const last = await costs.list(project.id, company.id, { pageSize: 2, cursor: first.next_cursor! });
    expect(first.items).toHaveLength(2); expect(last.items).toHaveLength(1);
    expect(first.summary.recorded_cost).toBe(30); expect(last.summary.recorded_cost).toBe(30);
    expect(new Set([...first.items, ...last.items].map((entry) => entry.id)).size).toBe(3);
  });
  it("keeps receipts private, normalizes images and omits file bytes from history", async () => {
    const { company, user, project } = await fixture();
    const entry = await costs.create(project.id, company.id, user.id, input());
    const png = await sharp({ create: { width: 20, height: 30, channels: 3, background: "white" } }).png().toBuffer();
    await costs.attachReceipt(entry.id, company.id, { data_base64: png.toString("base64"), mime_type: "image/png", filename: "Paint receipt.png" });
    const receipt = await costs.getReceipt(entry.id, company.id);
    expect(receipt.mimeType).toBe("image/jpeg"); expect(receipt.filename).toBe("Paint receipt.jpg");
    expect((await sharp(receipt.data).metadata()).exif).toBeUndefined();
    const row = (await costs.list(project.id, company.id, {})).items[0];
    expect(row.receipt_filename).toBe("Paint receipt.jpg"); expect(row).not.toHaveProperty("receiptData");
    const stranger = await prisma.company.create({ data: { name: "Stranger" } });
    await expect(costs.getReceipt(entry.id, stranger.id)).rejects.toMatchObject({ statusCode: 404 });
    await expect(costs.list(project.id, stranger.id, {})).rejects.toMatchObject({ statusCode: 404 });
    await expect(costs.create(project.id, stranger.id, user.id, input())).rejects.toMatchObject({ statusCode: 404 });
    await expect(costs.voidEntry(entry.id, stranger.id, user.id)).rejects.toMatchObject({ statusCode: 404 });
  });
  it("rejects malformed or mismatched attachments and invalid monetary input", async () => {
    const { company, user, project } = await fixture();
    const entry = await costs.create(project.id, company.id, user.id, input());
    await expect(costs.attachReceipt(entry.id, company.id, { data_base64: "not a receipt", mime_type: "image/jpeg", filename: "x.jpg" })).rejects.toMatchObject({ statusCode: 400 });
    await expect(costs.attachReceipt(entry.id, company.id, { data_base64: Buffer.from("not pdf").toString("base64"), mime_type: "application/pdf", filename: "x.pdf" })).rejects.toMatchObject({ statusCode: 400 });
    for (const amount of [0, -1, 0.001, Infinity]) expect(createJobCostSchema.safeParse({ ...input(), amount }).success).toBe(false);
    expect(createJobCostSchema.safeParse({ ...input(), labor_hours: 1 }).success).toBe(false);
  });
});
