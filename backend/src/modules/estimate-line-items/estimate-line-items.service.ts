import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { LineItemCategory } from '@prisma/client';
import { CreateEstimateLineItemInput, UpdateEstimateLineItemInput } from './estimate-line-items.validators';

/**
 * Recalculates the aggregate totals on an Estimate by summing its line items.
 * Called after every line item create / update / delete.
 */
async function recalculateEstimateTotals(estimateId: string) {
  const lineItems = await prisma.estimateLineItem.findMany({ where: { estimateId } });
  const estimate = await prisma.estimate.findUnique({ where: { id: estimateId } });

  let subtotalMaterials = 0;
  let subtotalLabor = 0;
  let subtotalOther = 0;
  let taxAmount = 0;

  for (const item of lineItems) {
    const lt = Number(item.lineTotal);
    const tax = lt * Number(item.taxRate);
    taxAmount += tax;

    if (item.category === 'MATERIALS') {
      subtotalMaterials += lt;
    } else if (item.category === 'LABOR') {
      subtotalLabor += lt;
    } else {
      subtotalOther += lt;
    }
  }

  const discountAmount = Number(estimate?.discountAmount ?? 0);
  const totalAmount = subtotalMaterials + subtotalLabor + subtotalOther + taxAmount - discountAmount;

  await prisma.estimate.update({
    where: { id: estimateId },
    data: { subtotalMaterials, subtotalLabor, subtotalOther, taxAmount, totalAmount },
  });
}

/**
 * Verify that an estimate exists and belongs to the given company.
 */
async function verifyEstimateOwnership(estimateId: string, companyId: string) {
  const estimate = await prisma.estimate.findFirst({
    where: { id: estimateId, companyId },
  });

  if (!estimate) {
    throw new NotFoundError('Estimate', estimateId);
  }

  return estimate;
}

/**
 * Verify a line item exists and that its parent estimate belongs to the given company.
 */
async function verifyLineItemOwnership(lineItemId: string, companyId: string) {
  const lineItem = await prisma.estimateLineItem.findUnique({
    where: { id: lineItemId },
    include: { estimate: { select: { id: true, companyId: true } } },
  });

  if (!lineItem || lineItem.estimate.companyId !== companyId) {
    throw new NotFoundError('EstimateLineItem', lineItemId);
  }

  return lineItem;
}

export async function listByEstimate(estimateId: string, companyId: string) {
  // Verify the estimate belongs to this company
  await verifyEstimateOwnership(estimateId, companyId);

  const lineItems = await prisma.estimateLineItem.findMany({
    where: { estimateId },
    orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }],
  });

  return lineItems;
}

export async function create(estimateId: string, companyId: string, data: CreateEstimateLineItemInput) {
  // Verify the estimate belongs to this company
  await verifyEstimateOwnership(estimateId, companyId);

  // Calculate line total: quantity * unitCost * (1 + markupPercent / 100)
  const markupPercent = data.markup_percent ?? 0;
  const lineTotal = data.quantity * data.unit_cost * (1 + markupPercent / 100);

  const lineItem = await prisma.estimateLineItem.create({
    data: {
      estimateId,
      category: data.category.toUpperCase() as LineItemCategory,
      name: data.name,
      description: data.description ?? null,
      quantity: data.quantity,
      unit: data.unit,
      unitCost: data.unit_cost,
      markupPercent,
      taxRate: data.tax_rate ?? 0,
      lineTotal,
      sortOrder: data.sort_order ?? 0,
      parentLineItemId: data.parent_line_item_id ?? null,
      sourceMaterialSuggestionId: data.source_material_suggestion_id ?? null,
      itemType: data.item_type ?? null,
    },
  });

  // Recalculate estimate totals after adding a line item
  await recalculateEstimateTotals(estimateId);

  return lineItem;
}

export async function update(lineItemId: string, companyId: string, data: UpdateEstimateLineItemInput) {
  const existing = await verifyLineItemOwnership(lineItemId, companyId);

  const updateData: any = {};

  if (data.category !== undefined) {
    updateData.category = data.category.toUpperCase() as LineItemCategory;
  }
  if (data.name !== undefined) {
    updateData.name = data.name;
  }
  if (data.description !== undefined) {
    updateData.description = data.description;
  }
  if (data.quantity !== undefined) {
    updateData.quantity = data.quantity;
  }
  if (data.unit !== undefined) {
    updateData.unit = data.unit;
  }
  if (data.unit_cost !== undefined) {
    updateData.unitCost = data.unit_cost;
  }
  if (data.markup_percent !== undefined) {
    updateData.markupPercent = data.markup_percent;
  }
  if (data.tax_rate !== undefined) {
    updateData.taxRate = data.tax_rate;
  }
  if (data.sort_order !== undefined) {
    updateData.sortOrder = data.sort_order;
  }
  if (data.parent_line_item_id !== undefined) {
    updateData.parentLineItemId = data.parent_line_item_id;
  }
  if (data.source_material_suggestion_id !== undefined) {
    updateData.sourceMaterialSuggestionId = data.source_material_suggestion_id;
  }
  if (data.item_type !== undefined) {
    updateData.itemType = data.item_type;
  }

  // Recalculate line total using merged values
  const quantity = data.quantity ?? Number(existing.quantity);
  const unitCost = data.unit_cost ?? Number(existing.unitCost);
  const markupPercent = data.markup_percent ?? Number(existing.markupPercent);
  updateData.lineTotal = quantity * unitCost * (1 + markupPercent / 100);

  const lineItem = await prisma.estimateLineItem.update({
    where: { id: lineItemId },
    data: updateData,
  });

  // Recalculate estimate totals
  await recalculateEstimateTotals(existing.estimateId);

  return lineItem;
}

export async function remove(lineItemId: string, companyId: string) {
  const existing = await verifyLineItemOwnership(lineItemId, companyId);

  await prisma.estimateLineItem.delete({ where: { id: lineItemId } });

  // Recalculate estimate totals after removal
  await recalculateEstimateTotals(existing.estimateId);
}
