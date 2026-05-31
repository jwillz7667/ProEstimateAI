import { describe, expect, it } from "vitest";
import { computeInvoiceTotals } from "./invoice-line-items.service";

describe("computeInvoiceTotals", () => {
  it("adds tax to the subtotal when there is no discount", () => {
    const { totalAmount, amountDue } = computeInvoiceTotals({
      subtotal: 1000,
      taxAmount: 80,
      discountAmount: 0,
      amountPaid: 0,
    });

    expect(totalAmount).toBe(1080);
    expect(amountDue).toBe(1080);
  });

  it("subtracts the discount from the taxed total", () => {
    const { totalAmount, amountDue } = computeInvoiceTotals({
      subtotal: 1000,
      taxAmount: 80,
      discountAmount: 150,
      amountPaid: 0,
    });

    expect(totalAmount).toBe(930);
    expect(amountDue).toBe(930);
  });

  it("reduces amount due by the recorded payment", () => {
    const { totalAmount, amountDue } = computeInvoiceTotals({
      subtotal: 1000,
      taxAmount: 80,
      discountAmount: 150,
      amountPaid: 500,
    });

    expect(totalAmount).toBe(930);
    expect(amountDue).toBe(430);
  });

  it("reports zero due once the invoice is paid in full", () => {
    const { amountDue } = computeInvoiceTotals({
      subtotal: 1000,
      taxAmount: 80,
      discountAmount: 0,
      amountPaid: 1080,
    });

    expect(amountDue).toBe(0);
  });

  it("floors the total at zero when the discount exceeds the bill", () => {
    const { totalAmount, amountDue } = computeInvoiceTotals({
      subtotal: 100,
      taxAmount: 8,
      discountAmount: 500,
      amountPaid: 0,
    });

    expect(totalAmount).toBe(0);
    expect(amountDue).toBe(0);
  });

  it("floors amount due at zero on overpayment rather than going negative", () => {
    const { totalAmount, amountDue } = computeInvoiceTotals({
      subtotal: 200,
      taxAmount: 0,
      discountAmount: 0,
      amountPaid: 250,
    });

    expect(totalAmount).toBe(200);
    expect(amountDue).toBe(0);
  });
});
