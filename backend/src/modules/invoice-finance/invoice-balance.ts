import { Prisma } from "@prisma/client";

type Money = Prisma.Decimal | number | string;

export function computeInvoiceTotals(input: {
  subtotal: Money; taxAmount: Money; discountAmount: Money; amountPaid: Money; creditAmount?: Money;
}): { totalAmount: number; amountDue: number } {
  const total = Prisma.Decimal.max(0, new Prisma.Decimal(input.subtotal).plus(input.taxAmount).minus(input.discountAmount)).toDecimalPlaces(2);
  return { totalAmount: Number(total), amountDue: Number(invoiceAmountDue(total, input.amountPaid, input.creditAmount ?? 0)) };
}

/** Contract credits reduce what can be collected, never the cash receipt total. */
export function invoiceAmountDue(totalAmount: Money, amountPaid: Money, creditAmount: Money = 0): Prisma.Decimal {
  return Prisma.Decimal.max(0, new Prisma.Decimal(totalAmount).minus(amountPaid).minus(creditAmount)).toDecimalPlaces(2);
}

/** Cash and credits settle the oldest agreed installment first. Keeping the
 * allocations separate prevents a credit note being presented as money paid.
 */
export function allocateInvoiceInstallments<T extends { amount: Money }>(
  installments: ReadonlyArray<T>, amountPaid: Money, creditAmount: Money = 0,
): Array<T & { paidAmount: Prisma.Decimal; creditAmount: Prisma.Decimal; amountDue: Prisma.Decimal }> {
  let cash = Prisma.Decimal.max(0, amountPaid);
  let credit = Prisma.Decimal.max(0, creditAmount);
  return installments.map(installment => {
    const amount = new Prisma.Decimal(installment.amount);
    const paidAmount = Prisma.Decimal.min(amount, cash);
    cash = cash.minus(paidAmount);
    const appliedCredit = Prisma.Decimal.min(amount.minus(paidAmount), credit);
    credit = credit.minus(appliedCredit);
    return { ...installment, paidAmount, creditAmount: appliedCredit, amountDue: amount.minus(paidAmount).minus(appliedCredit) };
  });
}
