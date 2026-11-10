import { createHash } from 'node:crypto';
import { LineItemCategory, Prisma, ProjectType, SavedEstimateItem } from '@prisma/client';
import { z } from 'zod';
import { prisma } from '../../config/database';
import { ConflictError, NotFoundError, ValidationError } from '../../lib/errors';
import { buildCursorWhere, paginateResults } from '../../lib/pagination';
import { assertEditableEstimate } from '../estimates/estimates.lifecycle';
import { recalculateEstimateTotals } from '../estimate-line-items/estimate-line-items.service';
import { SavedItemInput, SaveTemplateInput } from './estimate-library.validators';

const decimalText = z.string().regex(/^\d{1,12}(\.\d{1,4})?$/);
const nullableText = z.string().nullable();
export const proposalDefaultsSchema = z.object({
  title: nullableText, intro_text: nullableText, scope_of_work: nullableText,
  timeline_text: nullableText, terms_and_conditions: nullableText, footer_text: nullableText,
});
const snapshotSchema = z.object({
  schema_version: z.literal(1),
  header: z.object({
    title: nullableText, notes: nullableText, assumptions: nullableText, exclusions: nullableText,
    discount_amount: decimalText, contingency_amount: decimalText.nullable(),
    quality_tier: z.enum(['STANDARD', 'PREMIUM', 'LUXURY']).nullable(),
  }),
  items: z.array(z.object({
    key: z.string(), parent_key: nullableText,
    category: z.enum(['MATERIALS', 'LABOR', 'OTHER']), name: z.string().min(1).max(500),
    description: z.string().max(5000).nullable(), quantity: decimalText, unit: z.string().min(1).max(50),
    unit_cost: decimalText, markup_percent: decimalText, tax_rate: decimalText,
    item_type: nullableText, sort_order: z.number().int().nonnegative(),
  })).max(1000),
  proposal_defaults: proposalDefaultsSchema,
});
type Snapshot = z.infer<typeof snapshotSchema>;
type ResultWithId = { id: string };

function fingerprint(value: unknown): string {
  const stable = (input: unknown): unknown => Array.isArray(input) ? input.map(stable)
    : input && typeof input === 'object' ? Object.fromEntries(Object.entries(input).sort(([a], [b]) => a.localeCompare(b)).map(([k, v]) => [k, stable(v)])) : input;
  return createHash('sha256').update(JSON.stringify(stable(value))).digest('hex');
}

async function replayable<T extends ResultWithId>(companyId: string, requestId: string, operation: string, payload: unknown,
  load: (tx: Prisma.TransactionClient, id: string) => Promise<T>,
  work: (tx: Prisma.TransactionClient) => Promise<{ result: T; defaults?: Prisma.InputJsonValue }>) {
  const payloadHash = fingerprint(payload);
  return prisma.$transaction(async tx => {
    // Only the same logical request waits here. No company-wide lock is held
    // while waiting for a source estimate, preserving Estimate → Company order.
    await tx.$queryRaw`SELECT pg_advisory_xact_lock(hashtext('estimate-library'), hashtext(${`${companyId}:${requestId}`}))::text`;
    const prior = await tx.estimateLibraryOperation.findUnique({ where: { companyId_requestId: { companyId, requestId } } });
    if (prior) {
      if (prior.operation !== operation || prior.payloadHash !== payloadHash)
        throw new ConflictError('This request ID was already used for different library changes.');
      return load(tx, prior.resultId);
    }
    const { result, defaults } = await work(tx);
    await tx.estimateLibraryOperation.create({ data: {
      companyId, requestId, operation, payloadHash, resultId: result.id,
      proposalDefaults: defaults,
    } });
    return result;
  }, { maxWait: 10_000, timeout: 20_000 });
}

async function estimateInCompany(tx: Prisma.TransactionClient, id: string, companyId: string, lock = false) {
  if (lock) {
    const rows = await tx.$queryRaw<Array<{ id: string }>>`SELECT id FROM "Estimate" WHERE id = ${id} AND "companyId" = ${companyId} FOR UPDATE`;
    if (!rows.length) throw new NotFoundError('Estimate', id);
  }
  const estimate = await tx.estimate.findFirst({ where: { id, companyId } });
  if (!estimate) throw new NotFoundError('Estimate', id);
  return estimate;
}

/** Generic draft proposal content only: personal client messages, photographs,
 * recipient details, signatures, statuses and dates never become a template.
 */
export async function getTemplateProposalDefaults(tx: Prisma.TransactionClient, estimateId: string, companyId: string) {
  const operation = await tx.estimateLibraryOperation.findFirst({
    where: { companyId, resultId: estimateId, operation: { in: ['instantiate_template', 'duplicate_estimate'] } },
    orderBy: { createdAt: 'desc' }, select: { proposalDefaults: true },
  });
  if (!operation?.proposalDefaults) return null;
  const parsed = proposalDefaultsSchema.safeParse(operation.proposalDefaults);
  if (!parsed.success) throw new ConflictError('This estimate’s saved template terms could not be loaded.');
  return parsed.data;
}

async function capture(tx: Prisma.TransactionClient, estimateId: string, companyId: string) {
  await estimateInCompany(tx, estimateId, companyId, true);
  const source = await tx.estimate.findFirstOrThrow({ where: { id: estimateId, companyId }, include: {
    lineItems: { orderBy: [{ sortOrder: 'asc' }, { id: 'asc' }] },
    project: { select: { projectType: true } },
    proposals: { orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], take: 1 },
  } });
  const proposal = source.proposals[0];
  const inheritedDefaults = await getTemplateProposalDefaults(tx, source.id, companyId);
  const snapshot = snapshotSchema.parse({
    schema_version: 1,
    header: { title: source.title, notes: source.notes, assumptions: source.assumptions, exclusions: source.exclusions,
      discount_amount: source.discountAmount.toFixed(2), contingency_amount: source.contingencyAmount?.toFixed(2) ?? null,
      quality_tier: source.qualityTier },
    items: source.lineItems.map(item => ({
      key: item.id, parent_key: item.parentLineItemId, category: item.category, name: item.name,
      description: item.description, quantity: item.quantity.toFixed(2), unit: item.unit,
      unit_cost: item.unitCost.toFixed(2), markup_percent: item.markupPercent.toFixed(2),
      tax_rate: item.taxRate.toFixed(4), item_type: item.itemType, sort_order: item.sortOrder,
    })),
    proposal_defaults: proposal ? {
      title: proposal.title, intro_text: proposal.introText, scope_of_work: proposal.scopeOfWork,
      timeline_text: proposal.timelineText, terms_and_conditions: proposal.termsAndConditions, footer_text: proposal.footerText,
    } : inheritedDefaults ?? { title: null, intro_text: null, scope_of_work: null, timeline_text: null, terms_and_conditions: null, footer_text: null },
  });
  verifyHierarchy(snapshot);
  return { source, snapshot };
}

function readSnapshot(value: unknown): Snapshot {
  const result = snapshotSchema.safeParse(value);
  if (!result.success) throw new ConflictError('This template could not be loaded. Save a new template from a valid estimate.');
  verifyHierarchy(result.data);
  return result.data;
}

function verifyHierarchy(snapshot: Snapshot) {
  const items = new Map(snapshot.items.map(i => [i.key, i]));
  if (items.size !== snapshot.items.length) throw new ConflictError('The template contains duplicate line items.');
  for (const item of snapshot.items) {
    let parent = item.parent_key;
    const seen = new Set([item.key]);
    while (parent) {
      if (seen.has(parent) || !items.has(parent)) throw new ConflictError('The template contains an invalid item hierarchy.');
      seen.add(parent); parent = items.get(parent)!.parent_key;
    }
  }
}

function storedMoney(input: { quantity: string | number; unit_cost: string | number; markup_percent: string | number; tax_rate: string | number }) {
  const quantity = new Prisma.Decimal(input.quantity).toDecimalPlaces(2);
  const unitCost = new Prisma.Decimal(input.unit_cost).toDecimalPlaces(2);
  const markupPercent = new Prisma.Decimal(input.markup_percent).toDecimalPlaces(2);
  const taxRate = new Prisma.Decimal(input.tax_rate).toDecimalPlaces(4);
  const lineTotal = quantity.times(unitCost).times(markupPercent.div(100).plus(1)).toDecimalPlaces(2);
  if (quantity.lte(0) || quantity.gt('99999999.99') || unitCost.lt(0) || unitCost.gt('9999999999.99') || markupPercent.lt(0)
    || markupPercent.gt('1000') || taxRate.lt(0) || taxRate.gt(1) || lineTotal.gt('9999999999.99'))
    throw new ValidationError('The saved item quantity, price, markup or total exceeds the supported range.');
  return { quantity, unitCost, markupPercent, taxRate, lineTotal };
}

function templateTotal(snapshot: Snapshot) {
  let subtotal = new Prisma.Decimal(0), tax = new Prisma.Decimal(0);
  for (const input of snapshot.items) {
    const item = storedMoney(input);
    subtotal = subtotal.plus(item.lineTotal); tax = tax.plus(item.lineTotal.times(item.taxRate));
  }
  const total = Prisma.Decimal.max(0, subtotal.plus(tax.toDecimalPlaces(2)).minus(snapshot.header.discount_amount));
  if (total.gt('9999999999.99')) throw new ValidationError('The template total exceeds the supported range.');
  return total;
}

async function materialize(tx: Prisma.TransactionClient, companyId: string, userId: string, projectId: string, snapshot: Snapshot, title?: string) {
  const project = await tx.project.findFirst({ where: { id: projectId, companyId }, select: { id: true } });
  if (!project) throw new NotFoundError('Project', projectId);
  templateTotal(snapshot);
  const company = await tx.company.update({ where: { id: companyId }, data: { nextEstimateNumber: { increment: 1 } }, select: { estimatePrefix: true, nextEstimateNumber: true } });
  const estimate = await tx.estimate.create({ data: {
    companyId, projectId, createdByUserId: userId, status: 'DRAFT', version: 1,
    estimateNumber: `${company.estimatePrefix || 'EST'}-${company.nextEstimateNumber - 1}`,
    title: title ?? snapshot.header.title, notes: snapshot.header.notes,
    assumptions: snapshot.header.assumptions, exclusions: snapshot.header.exclusions,
    discountAmount: snapshot.header.discount_amount, contingencyAmount: snapshot.header.contingency_amount,
    qualityTier: snapshot.header.quality_tier,
    // A new job has no copied recipient, prior approval, invoice or expiry date.
    validUntil: null,
  } });
  const copies = new Map<string, string>();
  for (const item of snapshot.items) {
    const copy = await tx.estimateLineItem.create({ data: {
      estimateId: estimate.id, category: item.category, name: item.name, description: item.description,
      unit: item.unit, itemType: item.item_type, sortOrder: item.sort_order, ...storedMoney(item),
      // Cross-job AI provenance and source links intentionally do not travel.
      sourceMaterialSuggestionId: null,
      priceOrigin: "COPIED_ESTIMATE",
      priceSourceLabel: "Copied scope and prices; confirm for this job",
    } });
    copies.set(item.key, copy.id);
  }
  for (const item of snapshot.items) {
    if (item.parent_key) await tx.estimateLineItem.update({ where: { id: copies.get(item.key)! }, data: { parentLineItemId: copies.get(item.parent_key)! } });
  }
  const result = await recalculateEstimateTotals(estimate.id, tx);
  await tx.activityLogEntry.create({ data: { projectId, userId, action: 'ESTIMATE_CREATED', description: `Estimate ${estimate.estimateNumber} created from saved scope and pricing` } });
  return result;
}

export async function saveTemplate(companyId: string, userId: string, data: SaveTemplateInput) {
  return replayable(companyId, data.request_id, 'save_template', data,
    async (tx, id) => { const found = await tx.estimateTemplate.findFirst({ where: { id, companyId } }); if (!found) throw new NotFoundError('EstimateTemplate', id); return found; },
    async tx => {
      const { source, snapshot } = await capture(tx, data.estimate_id, companyId);
      const result = await tx.estimateTemplate.create({ data: { companyId, name: data.name, description: data.description,
        projectType: source.project.projectType, snapshotJson: snapshot, itemCount: snapshot.items.length, totalAmount: templateTotal(snapshot) } });
      return { result };
    });
}

export async function instantiateTemplate(companyId: string, userId: string, templateId: string, data: { request_id: string; project_id: string; title?: string }) {
  return replayable(companyId, data.request_id, 'instantiate_template', { templateId, ...data },
    (tx, id) => estimateInCompany(tx, id, companyId), async tx => {
      const template = await tx.estimateTemplate.findFirst({ where: { id: templateId, companyId } });
      if (!template) throw new NotFoundError('EstimateTemplate', templateId);
      const snapshot = readSnapshot(template.snapshotJson);
      return { result: await materialize(tx, companyId, userId, data.project_id, snapshot, data.title), defaults: snapshot.proposal_defaults };
    });
}

export async function duplicateEstimate(companyId: string, userId: string, sourceId: string, data: { request_id: string; project_id?: string; title?: string }) {
  return replayable(companyId, data.request_id, 'duplicate_estimate', { sourceId, ...data },
    (tx, id) => estimateInCompany(tx, id, companyId), async tx => {
      const { source, snapshot } = await capture(tx, sourceId, companyId);
      return { result: await materialize(tx, companyId, userId, data.project_id ?? source.projectId, snapshot, data.title), defaults: snapshot.proposal_defaults };
    });
}

function savedItemData(data: SavedItemInput) {
  const { lineTotal: _, ...money } = storedMoney(data);
  return { category: data.category.toUpperCase() as LineItemCategory, name: data.name, description: data.description ?? null,
    unit: data.unit, itemType: data.item_type ?? 'per_unit', ...money };
}
async function loadSavedItem(tx: Prisma.TransactionClient, id: string, companyId: string) {
  const item = await tx.savedEstimateItem.findFirst({ where: { id, companyId } });
  if (!item) throw new NotFoundError('SavedEstimateItem', id);
  return item;
}
export async function saveItem(companyId: string, data: SavedItemInput, itemId?: string) {
  return replayable(companyId, data.request_id, itemId ? 'update_item' : 'save_item', { itemId, ...data },
    (tx, id) => loadSavedItem(tx, id, companyId), async tx => {
      if (itemId) await loadSavedItem(tx, itemId, companyId);
      const fields = savedItemData(data);
      return { result: itemId ? await tx.savedEstimateItem.update({ where: { id: itemId }, data: fields })
        : await tx.savedEstimateItem.create({ data: { companyId, ...fields } }) };
    });
}
export async function applyItem(companyId: string, itemId: string, data: { request_id: string; estimate_id: string }) {
  return replayable(companyId, data.request_id, 'apply_item', { itemId, ...data },
    async (tx, id) => { const item = await tx.estimateLineItem.findFirst({ where: { id, estimate: { companyId } } }); if (!item) throw new NotFoundError('EstimateLineItem', id); return item; },
    async tx => {
      const estimate = await estimateInCompany(tx, data.estimate_id, companyId, true);
      await assertEditableEstimate(tx, estimate);
      const item = await loadSavedItem(tx, itemId, companyId);
      const order = await tx.estimateLineItem.aggregate({ where: { estimateId: estimate.id }, _max: { sortOrder: true } });
      const result = await tx.estimateLineItem.create({ data: {
        estimateId: estimate.id, category: item.category, name: item.name, description: item.description, unit: item.unit,
        priceOrigin: "SAVED_ITEM", priceSourceLabel: "Saved company item; confirm current pricing",
        itemType: item.itemType, sortOrder: (order._max.sortOrder ?? -1) + 1,
        ...storedMoney({ quantity: item.quantity.toString(), unit_cost: item.unitCost.toString(), markup_percent: item.markupPercent.toString(), tax_rate: item.taxRate.toString() }),
      } });
      await recalculateEstimateTotals(estimate.id, tx);
      return { result };
    });
}

export async function listTemplates(companyId: string, query: { q?: string; cursor?: string; page_size: number }) {
  if (query.cursor && !(await prisma.estimateTemplate.findFirst({ where: { id: query.cursor, companyId }, select: { id: true } }))) throw new NotFoundError('EstimateTemplate', query.cursor);
  const items = await prisma.estimateTemplate.findMany({ where: { companyId, ...(query.q ? { OR: [{ name: { contains: query.q, mode: 'insensitive' } }, { description: { contains: query.q, mode: 'insensitive' } }] } : {}) },
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], take: query.page_size + 1, ...buildCursorWhere(query.cursor) });
  return paginateResults(items, query.page_size);
}
export async function listItems(companyId: string, query: { q?: string; cursor?: string; page_size: number }) {
  if (query.cursor && !(await prisma.savedEstimateItem.findFirst({ where: { id: query.cursor, companyId }, select: { id: true } }))) throw new NotFoundError('SavedEstimateItem', query.cursor);
  const items = await prisma.savedEstimateItem.findMany({ where: { companyId, ...(query.q ? { OR: [{ name: { contains: query.q, mode: 'insensitive' } }, { description: { contains: query.q, mode: 'insensitive' } }] } : {}) },
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }], take: query.page_size + 1, ...buildCursorWhere(query.cursor) });
  return paginateResults(items, query.page_size);
}
export async function removeTemplate(companyId: string, id: string) {
  const deleted = await prisma.estimateTemplate.deleteMany({ where: { id, companyId } });
  if (!deleted.count) throw new NotFoundError('EstimateTemplate', id);
}
export async function removeItem(companyId: string, id: string) {
  const deleted = await prisma.savedEstimateItem.deleteMany({ where: { id, companyId } });
  if (!deleted.count) throw new NotFoundError('SavedEstimateItem', id);
}

export const templateDto = (t: { id: string; name: string; description: string | null; projectType: ProjectType; itemCount: number; totalAmount: Prisma.Decimal; createdAt: Date; updatedAt: Date }) => ({
  id: t.id, name: t.name, description: t.description, project_type: t.projectType.toLowerCase(), item_count: t.itemCount,
  total_amount: Number(t.totalAmount), created_at: t.createdAt.toISOString(), updated_at: t.updatedAt.toISOString(),
});
export const savedItemDto = (i: SavedEstimateItem) => ({
  id: i.id, category: i.category.toLowerCase(), name: i.name, description: i.description,
  quantity: Number(i.quantity), unit: i.unit, unit_cost: Number(i.unitCost), markup_percent: Number(i.markupPercent),
  tax_rate: Number(i.taxRate), item_type: i.itemType, created_at: i.createdAt.toISOString(), updated_at: i.updatedAt.toISOString(),
});
