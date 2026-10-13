import { Prisma, LineItemCategory } from "@prisma/client";
import { prisma } from "../../config/database";
import { NotFoundError, ValidationError } from "../../lib/errors";
import {
  CreateEstimateLineItemInput,
  UpdateEstimateLineItemInput,
} from "./estimate-line-items.validators";

type LineItemInput = CreateEstimateLineItemInput | UpdateEstimateLineItemInput;

/** Serialize edits on the parent to keep its totals and hierarchy consistent. */
async function lockEstimate(
  tx: Prisma.TransactionClient,
  estimateId: string,
  companyId: string,
) {
  const rows = await tx.$queryRaw<Array<{ id: string }>>`
    SELECT id FROM "Estimate" WHERE id = ${estimateId} AND "companyId" = ${companyId} FOR UPDATE
  `;
  if (rows.length === 0) throw new NotFoundError("Estimate", estimateId);
  return tx.estimate.findUniqueOrThrow({ where: { id: estimateId } });
}

export async function recalculateEstimateTotals(
  estimateId: string,
  tx: Prisma.TransactionClient = prisma,
) {
  const [lineItems, estimate] = await Promise.all([
    tx.estimateLineItem.findMany({ where: { estimateId } }),
    tx.estimate.findUniqueOrThrow({ where: { id: estimateId } }),
  ]);
  let subtotalMaterials = new Prisma.Decimal(0);
  let subtotalLabor = new Prisma.Decimal(0);
  let subtotalOther = new Prisma.Decimal(0);
  let taxAmount = new Prisma.Decimal(0);
  for (const item of lineItems) {
    taxAmount = taxAmount.plus(item.lineTotal.times(item.taxRate));
    if (item.category === "MATERIALS")
      subtotalMaterials = subtotalMaterials.plus(item.lineTotal);
    else if (item.category === "LABOR")
      subtotalLabor = subtotalLabor.plus(item.lineTotal);
    else subtotalOther = subtotalOther.plus(item.lineTotal);
  }
  taxAmount = taxAmount.toDecimalPlaces(2);
  const totalAmount = Prisma.Decimal.max(
    0,
    subtotalMaterials
      .plus(subtotalLabor)
      .plus(subtotalOther)
      .plus(taxAmount)
      .minus(estimate.discountAmount),
  );
  return tx.estimate.update({
    where: { id: estimateId },
    data: {
      subtotalMaterials,
      subtotalLabor,
      subtotalOther,
      taxAmount,
      totalAmount,
    },
  });
}

async function verifyLineItemOwnership(
  lineItemId: string,
  companyId: string,
  tx: Prisma.TransactionClient = prisma,
) {
  const lineItem = await tx.estimateLineItem.findFirst({
    where: { id: lineItemId, estimate: { companyId } },
  });
  if (!lineItem) throw new NotFoundError("EstimateLineItem", lineItemId);
  return lineItem;
}

async function verifyReferences(
  tx: Prisma.TransactionClient,
  estimateId: string,
  projectId: string,
  data: LineItemInput,
  lineItemId?: string,
) {
  if (data.source_material_suggestion_id) {
    const source = await tx.materialSuggestion.findFirst({
      where: { id: data.source_material_suggestion_id, projectId },
      select: { id: true },
    });
    if (!source)
      throw new NotFoundError(
        "MaterialSuggestion",
        data.source_material_suggestion_id,
      );
  }
  let parentId = data.parent_line_item_id;
  const visited = new Set<string>();
  // Traverse the existing ancestry to reject self-links and cycles, including
  // linking a parent to one of its own descendants.
  while (parentId) {
    if (parentId === lineItemId || visited.has(parentId))
      throw new ValidationError("Line item hierarchy cannot contain a cycle");
    visited.add(parentId);
    const parent = await tx.estimateLineItem.findFirst({
      where: { id: parentId, estimateId },
      select: { parentLineItemId: true },
    });
    if (!parent) throw new NotFoundError("EstimateLineItem", parentId);
    parentId = parent.parentLineItemId;
  }
}

function lineMoney(quantity: number, unitCost: number, markupPercent: number) {
  const storedQuantity = new Prisma.Decimal(quantity).toDecimalPlaces(2);
  const storedUnitCost = new Prisma.Decimal(unitCost).toDecimalPlaces(2);
  const storedMarkup = new Prisma.Decimal(markupPercent).toDecimalPlaces(2);
  const lineTotal = storedQuantity
    .times(storedUnitCost)
    .times(storedMarkup.div(100).plus(1))
    .toDecimalPlaces(2);
  if (storedQuantity.lte(0) || lineTotal.gt("9999999999.99"))
    throw new ValidationError(
      "Line item quantity or total is outside the supported range",
    );
  return {
    quantity: storedQuantity,
    unitCost: storedUnitCost,
    markupPercent: storedMarkup,
    lineTotal,
  };
}

function createData(
  estimateId: string,
  data: CreateEstimateLineItemInput,
): Prisma.EstimateLineItemUncheckedCreateInput {
  return {
    estimateId,
    category: data.category.toUpperCase() as LineItemCategory,
    name: data.name,
    description: data.description ?? null,
    unit: data.unit,
    taxRate: data.tax_rate ?? 0,
    sortOrder: data.sort_order ?? 0,
    parentLineItemId: data.parent_line_item_id ?? null,
    sourceMaterialSuggestionId: data.source_material_suggestion_id ?? null,
    itemType: data.item_type ?? null,
    ...lineMoney(data.quantity, data.unit_cost, data.markup_percent ?? 0),
  };
}

export async function listByEstimate(estimateId: string, companyId: string) {
  const estimate = await prisma.estimate.findFirst({
    where: { id: estimateId, companyId },
    select: { id: true },
  });
  if (!estimate) throw new NotFoundError("Estimate", estimateId);
  return prisma.estimateLineItem.findMany({
    where: { estimateId },
    orderBy: [{ sortOrder: "asc" }, { id: "asc" }],
  });
}

export async function create(
  estimateId: string,
  companyId: string,
  data: CreateEstimateLineItemInput,
) {
  const items = await createBatch(estimateId, companyId, [data]);
  return items[0];
}

export async function createBatch(
  estimateId: string,
  companyId: string,
  items: ReadonlyArray<CreateEstimateLineItemInput>,
) {
  return prisma.$transaction(async (tx) => {
    const estimate = await lockEstimate(tx, estimateId, companyId);
    const results = [];
    for (const data of items) {
      await verifyReferences(tx, estimateId, estimate.projectId, data);
      results.push(
        await tx.estimateLineItem.create({
          data: createData(estimateId, data),
        }),
      );
    }
    await recalculateEstimateTotals(estimateId, tx);
    return results;
  });
}

export async function update(
  lineItemId: string,
  companyId: string,
  data: UpdateEstimateLineItemInput,
) {
  const parent = await verifyLineItemOwnership(lineItemId, companyId);
  return prisma.$transaction(async (tx) => {
    const estimate = await lockEstimate(tx, parent.estimateId, companyId);
    const existing = await verifyLineItemOwnership(lineItemId, companyId, tx);
    await verifyReferences(
      tx,
      estimate.id,
      estimate.projectId,
      data,
      lineItemId,
    );
    const updateData: Prisma.EstimateLineItemUncheckedUpdateInput = {};
    if (data.category !== undefined)
      updateData.category = data.category.toUpperCase() as LineItemCategory;
    if (data.name !== undefined) updateData.name = data.name;
    if (data.description !== undefined)
      updateData.description = data.description;
    if (data.unit !== undefined) updateData.unit = data.unit;
    if (data.tax_rate !== undefined) updateData.taxRate = data.tax_rate;
    if (data.sort_order !== undefined) updateData.sortOrder = data.sort_order;
    if (data.parent_line_item_id !== undefined)
      updateData.parentLineItemId = data.parent_line_item_id;
    if (data.source_material_suggestion_id !== undefined)
      updateData.sourceMaterialSuggestionId =
        data.source_material_suggestion_id;
    if (data.item_type !== undefined) updateData.itemType = data.item_type;
    const linePriceChange = (data.quantity !== undefined && !existing.quantity.equals(new Prisma.Decimal(data.quantity).toDecimalPlaces(2)))
      || (data.unit_cost !== undefined && !existing.unitCost.equals(new Prisma.Decimal(data.unit_cost).toDecimalPlaces(2)))
      || (data.markup_percent !== undefined && !existing.markupPercent.equals(new Prisma.Decimal(data.markup_percent).toDecimalPlaces(2)));
    if (linePriceChange) {
      Object.assign(updateData, lineMoney(data.quantity ?? Number(existing.quantity), data.unit_cost ?? Number(existing.unitCost), data.markup_percent ?? Number(existing.markupPercent)));
    }
    const totalsChange = linePriceChange
      || (data.category !== undefined && data.category.toUpperCase() !== existing.category)
      || (data.tax_rate !== undefined && !existing.taxRate.equals(new Prisma.Decimal(data.tax_rate).toDecimalPlaces(4)));
    const lineItem = await tx.estimateLineItem.update({
      where: { id: lineItemId },
      data: updateData,
    });
    if (totalsChange) await recalculateEstimateTotals(existing.estimateId, tx);
    return lineItem;
  });
}

export async function remove(lineItemId: string, companyId: string) {
  const parent = await verifyLineItemOwnership(lineItemId, companyId);
  await prisma.$transaction(async (tx) => {
    await lockEstimate(tx, parent.estimateId, companyId);
    const existing = await verifyLineItemOwnership(lineItemId, companyId, tx);
    await tx.estimateLineItem.updateMany({
      where: { parentLineItemId: lineItemId },
      data: { parentLineItemId: null },
    });
    await tx.estimateLineItem.delete({ where: { id: lineItemId } });
    await recalculateEstimateTotals(existing.estimateId, tx);
  });
}
