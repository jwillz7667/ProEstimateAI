import { describe, expect, it } from "vitest";
import { allocateInvoiceInstallments, invoiceAmountDue } from "./invoice-balance";

describe("credit-aware invoice balances", () => {
  it("reduces collection by a credit while preserving the gross contract and cash", () => {
    expect(invoiceAmountDue("100.00", "35.25", "14.75").toFixed(2)).toBe("50.00");
    expect(invoiceAmountDue("100.00", "100.00", "20.00").toFixed(2)).toBe("0.00");
    expect(invoiceAmountDue("100.00", "80.00", "20.00").toFixed(2)).toBe("0.00");
    expect(invoiceAmountDue("100.00", "80.00", "10.00").toFixed(2)).toBe("10.00");
  });

  it("retains exact cent precision for large contracts and combined cash/credit settlements", () => {
    expect(invoiceAmountDue("9999999999.99", "9999999999.95", "0.03").toFixed(2)).toBe("0.01");
    expect(invoiceAmountDue("0.30", "0.10", "0.20").toFixed(2)).toBe("0.00");
  });

  it("allocates the cash and credit portions separately across deposit and completion", () => {
    const result = allocateInvoiceInstallments([{ id: "deposit", amount: "30.00" }, { id: "completion", amount: "70.00" }], "20.00", "35.00");
    expect(result.map(row => [row.id, row.paidAmount.toFixed(2), row.creditAmount.toFixed(2), row.amountDue.toFixed(2)]))
      .toEqual([["deposit", "20.00", "10.00", "0.00"], ["completion", "0.00", "25.00", "45.00"]]);
    expect(result.reduce((sum, row) => sum.plus(row.amountDue), invoiceAmountDue(0, 0)).toFixed(2)).toBe("45.00");
  });

  it("does not overallocate a schedule when cash or credits exceed its remaining balance", () => {
    const result = allocateInvoiceInstallments([{ amount: "10.00" }, { amount: "20.00" }], "40.00", "15.00");
    expect(result.map(row => row.paidAmount.toFixed(2))).toEqual(["10.00", "20.00"]);
    expect(result.map(row => row.creditAmount.toFixed(2))).toEqual(["0.00", "0.00"]);
    expect(result.map(row => row.amountDue.toFixed(2))).toEqual(["0.00", "0.00"]);
  });
});
