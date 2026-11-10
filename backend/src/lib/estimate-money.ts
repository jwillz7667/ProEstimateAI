import { Prisma } from "@prisma/client";
import { ValidationError } from "./errors";

export const MAX_ESTIMATE_MONEY = new Prisma.Decimal("9999999999.99");
export const MAX_ESTIMATE_QUANTITY = new Prisma.Decimal("99999999.99");

type DecimalInput = Prisma.Decimal | number | string;
export function estimateMoney(value: DecimalInput, label = "Amount") {
  let decimal: Prisma.Decimal;
  try { decimal = new Prisma.Decimal(value); }
  catch { throw new ValidationError(`${label} must be a finite monetary value.`); }
  if (!decimal.isFinite() || decimal.lt(0) || decimal.gt(MAX_ESTIMATE_MONEY)) {
    throw new ValidationError(`${label} must be between 0 and 9,999,999,999.99.`);
  }
  return decimal.toDecimalPlaces(2);
}

/** Match stored precision before calculating a line; never sum unrounded floats. */
export function normalizeEstimateLineMoney(quantity: DecimalInput, unitCost: DecimalInput, markupPercent: DecimalInput) {
  const units = new Prisma.Decimal(quantity);
  const markup = new Prisma.Decimal(markupPercent);
  if (!units.isFinite() || units.lte(0) || units.gt(MAX_ESTIMATE_QUANTITY) || !markup.isFinite() || markup.lt(0) || markup.gt(1000)) {
    throw new ValidationError("Quantity or markup is outside the supported range.");
  }
  const storedQuantity = units.toDecimalPlaces(2);
  if (storedQuantity.lte(0)) throw new ValidationError("Quantity must round to at least 0.01.");
  const storedUnitCost = estimateMoney(unitCost, "Unit cost");
  const storedMarkup = markup.toDecimalPlaces(2);
  const lineTotal = storedQuantity.times(storedUnitCost).times(storedMarkup.div(100).plus(1)).toDecimalPlaces(2);
  estimateMoney(lineTotal, "Line total");
  return { quantity: storedQuantity, unitCost: storedUnitCost, markupPercent: storedMarkup, lineTotal };
}

export function calculateEstimateTotals(lines: ReadonlyArray<{ category: string; lineTotal: DecimalInput; taxRate: DecimalInput }>, discount: DecimalInput = 0) {
  let subtotalMaterials = new Prisma.Decimal(0), subtotalLabor = new Prisma.Decimal(0), subtotalOther = new Prisma.Decimal(0), taxAmount = new Prisma.Decimal(0);
  for (const line of lines) {
    const amount = estimateMoney(line.lineTotal, "Line total");
    const taxRate = new Prisma.Decimal(line.taxRate);
    if (!taxRate.isFinite() || taxRate.lt(0) || taxRate.gt(1)) throw new ValidationError("Tax rate must be between 0 and 1.");
    taxAmount = taxAmount.plus(amount.times(taxRate.toDecimalPlaces(4)));
    if (line.category.toUpperCase() === "MATERIALS") subtotalMaterials = subtotalMaterials.plus(amount);
    else if (line.category.toUpperCase() === "LABOR") subtotalLabor = subtotalLabor.plus(amount);
    else subtotalOther = subtotalOther.plus(amount);
  }
  subtotalMaterials = estimateMoney(subtotalMaterials, "Materials subtotal");
  subtotalLabor = estimateMoney(subtotalLabor, "Labor subtotal");
  subtotalOther = estimateMoney(subtotalOther, "Other subtotal");
  taxAmount = estimateMoney(taxAmount.toDecimalPlaces(2), "Tax total");
  const discountAmount = estimateMoney(discount, "Discount");
  const totalAmount = estimateMoney(Prisma.Decimal.max(0, subtotalMaterials.plus(subtotalLabor).plus(subtotalOther).plus(taxAmount).minus(discountAmount)), "Estimate total");
  return { subtotalMaterials, subtotalLabor, subtotalOther, taxAmount, discountAmount, totalAmount };
}

export function estimateTotalsMatch(estimate: { subtotalMaterials: Prisma.Decimal; subtotalLabor: Prisma.Decimal; subtotalOther: Prisma.Decimal; taxAmount: Prisma.Decimal; discountAmount: Prisma.Decimal; totalAmount: Prisma.Decimal }, totals: ReturnType<typeof calculateEstimateTotals>) {
  return (Object.keys(totals) as Array<keyof typeof totals>).every((key) => estimate[key].equals(totals[key]));
}
