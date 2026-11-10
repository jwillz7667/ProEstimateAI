import { Prisma, LineItemCategory } from "@prisma/client";
import { prisma } from "../../config/database";
import { ConflictError, NotFoundError, ValidationError } from "../../lib/errors";
import { assertEditableEstimate } from "../estimates/estimates.lifecycle";
import { calculateEstimateTotals, normalizeEstimateLineMoney } from "../../lib/estimate-money";
import {
  CreateEstimateLineItemInput,
  UpdateEstimateLineItemInput,
  ReviewEstimatePriceInput,
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
  const estimate = await tx.estimate.findUniqueOrThrow({ where: { id: estimateId } });
  // The status check shares the parent row lock with every item mutation.
  // A client with an older draft cannot alter a quote after it was sent or approved.
  await assertEditableEstimate(tx, estimate);
  return estimate;
}

export async function recalculateEstimateTotals(
  estimateId: string,
  tx: Prisma.TransactionClient = prisma,
) {
  const [lineItems, estimate] = await Promise.all([
    tx.estimateLineItem.findMany({ where: { estimateId } }),
    tx.estimate.findUniqueOrThrow({ where: { id: estimateId } }),
  ]);
  const totals = calculateEstimateTotals(lineItems, estimate.discountAmount);
  return tx.estimate.update({
    where: { id: estimateId },
    data: { ...totals, updatedAt: new Date(Math.max(Date.now(), estimate.updatedAt.getTime() + 1)) },
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
  return normalizeEstimateLineMoney(quantity, unitCost, markupPercent);
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
    priceOrigin: data.source_material_suggestion_id ? "AI_SUGGESTED" : "CONTRACTOR_ENTERED",
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
    if ((data.unit_cost !== undefined && !existing.unitCost.equals(data.unit_cost)) ||
        (data.unit !== undefined && data.unit !== existing.unit) ||
        (data.name !== undefined && data.name !== existing.name)) {
      updateData.priceOrigin = "CONTRACTOR_ENTERED";
      updateData.priceSourceLabel = null;
      updateData.priceSourceUrl = null;
      updateData.priceCheckedAt = null;
      updateData.priceCheckedByUserId = null;
    }
    if ((data.quantity !== undefined && !existing.quantity.equals(data.quantity)) ||
        (data.unit !== undefined && data.unit !== existing.unit) ||
        (data.name !== undefined && data.name !== existing.name)) {
      updateData.quantityBasis = null;
      updateData.quantityCheckedAt = null;
    }
    const totalsChange = linePriceChange
      || (data.category !== undefined && data.category.toUpperCase() !== existing.category)
      || (data.tax_rate !== undefined && !existing.taxRate.equals(new Prisma.Decimal(data.tax_rate).toDecimalPlaces(4)));
    const lineItem = await tx.estimateLineItem.update({
      where: { id: lineItemId },
      data: updateData,
    });
    if (totalsChange) await recalculateEstimateTotals(existing.estimateId, tx);
    else if (Object.keys(updateData).length) await tx.estimate.update({
      where: { id: estimate.id },
      data: { updatedAt: new Date(Math.max(Date.now(), estimate.updatedAt.getTime() + 1)) },
    });
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

/** Records a contractor's own check, never a claim of independent supplier verification. */
export async function reviewPrice(lineItemId: string, companyId: string, userId: string, input: ReviewEstimatePriceInput) {
  const parent = await verifyLineItemOwnership(lineItemId, companyId);
  return prisma.$transaction(async (tx) => {
    const estimate = await lockEstimate(tx, parent.estimateId, companyId);
    const item = await verifyLineItemOwnership(lineItemId, companyId, tx);
    if (item.name !== input.expected_name || item.unit !== input.expected_unit ||
        !item.unitCost.equals(input.expected_unit_cost) || !item.quantity.equals(input.expected_quantity)) {
      throw new ConflictError("The item changed while you were checking it. Refresh before confirming its price.");
    }
    const checkedAt = new Date();
    const updated = await tx.estimateLineItem.update({ where: { id: lineItemId }, data: {
      priceSourceLabel: input.source_label, priceSourceUrl: input.source_url ?? null,
      priceCheckedAt: checkedAt, priceCheckedByUserId: userId,
      ...(input.quantity_confirmed ? { quantityBasis: input.quantity_basis, quantityCheckedAt: checkedAt } : {}),
    } });
    await tx.estimate.update({ where: { id: item.estimateId }, data: { updatedAt: new Date(Math.max(checkedAt.getTime(), estimate.updatedAt.getTime() + 1)) } });
    await tx.activityLogEntry.create({ data: {
      companyId, projectId: estimate.projectId, userId, action: "ESTIMATE_UPDATED", entityType: "EstimateLineItem", entityId: lineItemId,
      description: "Contractor checked a base price and recorded its source",
    } });
    return updated;
  });
}
