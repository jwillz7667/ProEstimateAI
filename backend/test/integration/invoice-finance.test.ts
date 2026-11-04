import { randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it } from "vitest";
import { prisma } from "../../src/config/database";
import * as finance from "../../src/modules/invoice-finance/invoice-finance.service";
import * as invoices from "../../src/modules/invoices/invoices.service";
import { recordInvoicePaymentSchema } from "../../src/modules/invoice-finance/invoice-finance.validators";

beforeEach(async () => { await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE'); });

async function fixture() {
  const company = await prisma.company.create({ data: { name: "Invoice finance" } });
  const user = await prisma.user.create({ data: { companyId: company.id, email: `${randomUUID()}@example.test`, fullName: "Contractor" } });
  const client = await prisma.client.create({ data: { companyId: company.id, name: "Client" } });
  const project = await prisma.project.create({ data: { companyId: company.id, clientId: client.id, title: "Kitchen", projectType: "KITCHEN" } });
  const invoice = await prisma.invoice.create({ data: {
    companyId: company.id, projectId: project.id, clientId: client.id, invoiceNumber: "FIN-1",
    status: "SENT", subtotal: 100, totalAmount: 100, amountDue: 100,
  } });
  return { company, user, invoice };
}

describe("invoice receipts and schedules", () => {
  it("records exact partial and final receipts once when a request is retried", async () => {
    const { company, user, invoice } = await fixture();
    const request = { request_id: randomUUID(), amount: 33.33, method: "cash" as const };
    await finance.recordPayment(invoice.id, company.id, user.id, request);
    await finance.recordPayment(invoice.id, company.id, user.id, request);
    let result = await finance.getFinance(invoice.id, company.id);
    expect(result.invoice.amount_paid).toBe(33.33); expect(result.invoice.amount_due).toBe(66.67);
    expect(result.payments).toHaveLength(1); expect(result.invoice.status).toBe("partially_paid");
    result = await finance.recordPayment(invoice.id, company.id, user.id, { request_id: randomUUID(), amount: 66.67, method: "bank_transfer" });
    expect(result.invoice.amount_due).toBe(0); expect(result.invoice.status).toBe("paid"); expect(result.payments).toHaveLength(2);
    await expect(finance.recordPayment(invoice.id, company.id, user.id, { ...request, amount: 34 })).rejects.toMatchObject({ statusCode: 409 });
  });

  it("serializes concurrent recording without overpayment or a lost earlier receipt", async () => {
    const { company, user, invoice } = await fixture();
    const results = await Promise.allSettled([1, 2].map(() => finance.recordPayment(invoice.id, company.id, user.id, { request_id: randomUUID(), amount: 70, method: "check" })));
    expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect((await finance.getFinance(invoice.id, company.id)).invoice.amount_due).toBe(30);
    expect(await prisma.invoicePayment.count()).toBe(1);
  });

  it("requires tenant ownership, a sent invoice and positive two-decimal payments", async () => {
    const { company, user, invoice } = await fixture();
    const request = { request_id: randomUUID(), amount: 20, method: "other" as const };
    const stranger = await prisma.company.create({ data: { name: "Unrelated" } });
    await expect(finance.getFinance(invoice.id, stranger.id)).rejects.toMatchObject({ statusCode: 404 });
    await expect(finance.recordPayment(invoice.id, stranger.id, user.id, request)).rejects.toMatchObject({ statusCode: 404 });
    for (const status of ["DRAFT", "VOID"] as const) {
      await prisma.invoice.update({ where: { id: invoice.id }, data: { status } });
      await expect(finance.recordPayment(invoice.id, company.id, user.id, request)).rejects.toMatchObject({ statusCode: 409 });
    }
    for (const amount of [0, -1, 0.001, Infinity, NaN]) expect(recordInvoicePaymentSchema.safeParse({ ...request, amount }).success).toBe(false);
  });

  it("allocates a deposit and final balance without counting receipts twice", async () => {
    const { company, user, invoice } = await fixture();
    await prisma.invoice.update({ where: { id: invoice.id }, data: { status: "DRAFT" } });
    await finance.replaceSchedule(invoice.id, company.id, { expected_total: 100, installments: [{ title: "Deposit", amount: 30 }, { title: "Completion", amount: 70 }] });
    await expect(finance.replaceSchedule(invoice.id, company.id, { expected_total: 99, installments: [{ title: "Full", amount: 99 }] })).rejects.toMatchObject({ statusCode: 409 });
    await expect(finance.replaceSchedule(invoice.id, company.id, { expected_total: 100, installments: [{ title: "Short", amount: 50 }] })).rejects.toMatchObject({ statusCode: 400 });
    await prisma.invoice.update({ where: { id: invoice.id }, data: { status: "SENT" } });
    const result = await finance.recordPayment(invoice.id, company.id, user.id, { request_id: randomUUID(), amount: 40, method: "cash" });
    expect(result.installments.map((item) => item.paid_amount)).toEqual([30, 10]);
    expect(result.installments.map((item) => item.amount_due)).toEqual([0, 60]);
    await expect(finance.replaceSchedule(invoice.id, company.id, { expected_total: 100, installments: [{ title: "Full", amount: 100 }] })).rejects.toMatchObject({ statusCode: 409 });
  });

  it("retains payment history for cumulative balance updates made by older app builds", async () => {
    const { company, invoice } = await fixture();
    await invoices.update(invoice.id, company.id, { amount_paid: 25, expected_amount_paid: 0 });
    await invoices.update(invoice.id, company.id, { amount_paid: 25, expected_amount_paid: 25 });
    const result = await finance.getFinance(invoice.id, company.id);
    expect(result.payments).toHaveLength(1); expect(result.payments[0].amount).toBe(25); expect(result.payments[0].method).toBe("legacy_manual");
  });

  it("shares sent receipts while keeping internal notes and draft links private", async () => {
    const { company, user, invoice } = await fixture();
    await finance.recordPayment(invoice.id, company.id, user.id, { request_id: randomUUID(), amount: 20, method: "check", notes: "Internal", reference: "Private" });
    const shared = await finance.getSharedInvoice(invoice.shareToken);
    expect(shared.invoice.amount_due).toBe(80); expect(shared.company.name).toBe(company.name);
    expect(shared.payments[0]).not.toHaveProperty("notes"); expect(shared.payments[0]).not.toHaveProperty("reference");
    await prisma.invoice.update({ where: { id: invoice.id }, data: { status: "DRAFT" } });
    await expect(finance.getSharedInvoice(invoice.shareToken)).rejects.toMatchObject({ statusCode: 404 });
  });
});
