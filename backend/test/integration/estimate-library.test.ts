import { randomUUID } from 'node:crypto';
import { beforeEach, describe, expect, it } from 'vitest';
import { prisma } from '../../src/config/database';
import * as library from '../../src/modules/estimate-library/estimate-library.service';
import * as proposals from '../../src/modules/proposals/proposals.service';
import { saveItemSchema } from '../../src/modules/estimate-library/estimate-library.validators';

async function fixture() {
  const company = await prisma.company.create({ data: { name: 'Library company' } });
  const user = await prisma.user.create({ data: { companyId: company.id, fullName: 'Owner', email: `${randomUUID()}@example.test` } });
  const project = await prisma.project.create({ data: { companyId: company.id, title: 'Original kitchen', projectType: 'KITCHEN' } });
  const estimate = await prisma.estimate.create({ data: { companyId: company.id, projectId: project.id, estimateNumber: 'SRC-1',
    title: 'Cabinet scope', notes: 'Keep work area clean', assumptions: 'Existing subfloor is sound', exclusions: 'Electrical work', discountAmount: 5 } });
  const parent = await prisma.estimateLineItem.create({ data: { estimateId: estimate.id, category: 'MATERIALS', name: 'Hardware', quantity: 2,
    unit: 'each', unitCost: 10, markupPercent: 10, taxRate: 0.1, lineTotal: 22, sortOrder: 0, sourceMaterialSuggestionId: 'old-ai-source' } });
  await prisma.estimateLineItem.create({ data: { estimateId: estimate.id, parentLineItemId: parent.id, category: 'LABOR', name: 'Install hardware',
    quantity: 1.5, unit: 'hours', unitCost: 20, lineTotal: 30, sortOrder: 1 } });
  await prisma.proposal.create({ data: { companyId: company.id, projectId: project.id, estimateId: estimate.id,
    title: 'Cabinet proposal', scopeOfWork: 'Replace cabinet hardware', termsAndConditions: 'Payment due at completion',
    clientMessage: 'Private message for the original client', heroImageUrl: 'https://example.test/original-job.png' } });
  return { company, user, project, estimate, parent };
}
const savedInput = () => saveItemSchema.parse({ request_id: randomUUID(), category: 'materials', name: 'Drywall board', description: 'Half-inch board',
  quantity: 2, unit: 'sheets', unit_cost: 10, markup_percent: 10, tax_rate: 0.1 });

describe('estimate templates and saved pricing library', () => {
  beforeEach(async () => { await prisma.$executeRawUnsafe('TRUNCATE TABLE "Company" RESTART IDENTITY CASCADE'); });

  it('captures reusable scope and applies a new draft atomically with canonical prices, new IDs and no old recipient or AI links', async () => {
    const t = await fixture();
    const template = await library.saveTemplate(t.company.id, t.user.id, { request_id: randomUUID(), estimate_id: t.estimate.id, name: 'Cabinet package' });
    expect(template.itemCount).toBe(2); expect(template.totalAmount.toString()).toBe('49.2');
    await prisma.estimateLineItem.update({ where: { id: t.parent.id }, data: { unitCost: 99, lineTotal: 217.8 } });
    const project = await prisma.project.create({ data: { companyId: t.company.id, title: 'New job' } });
    const draft = await library.instantiateTemplate(t.company.id, t.user.id, template.id, { request_id: randomUUID(), project_id: project.id, title: 'New quote' });
    expect(draft).toMatchObject({ status: 'DRAFT', version: 1, title: 'New quote', projectId: project.id, validUntil: null });
    expect(draft.totalAmount.toString()).toBe('49.2'); expect(draft.taxAmount.toString()).toBe('2.2');
    expect(draft.assumptions).toBe('Existing subfloor is sound'); expect(draft.exclusions).toBe('Electrical work');
    const items = await prisma.estimateLineItem.findMany({ where: { estimateId: draft.id }, orderBy: { sortOrder: 'asc' } });
    expect(items).toHaveLength(2); expect(items[0].id).not.toBe(t.parent.id); expect(items[1].parentLineItemId).toBe(items[0].id);
    expect(items.every(i => i.sourceMaterialSuggestionId === null)).toBe(true);
    const proposal = await proposals.create(t.company.id, { estimate_id: draft.id });
    expect(proposal.scopeOfWork).toBe('Replace cabinet hardware'); expect(proposal.termsAndConditions).toBe('Payment due at completion');
    expect(proposal.clientMessage).toBeNull(); expect(proposal.heroImageUrl).toBeNull();
    const explicit = await proposals.create(t.company.id, { estimate_id: draft.id, terms_and_conditions: null, scope_of_work: 'Different scope' });
    expect(explicit.termsAndConditions).toBeNull(); expect(explicit.scopeOfWork).toBe('Different scope');
  });

  it('replays simultaneous template saves and rejects reusing a UUID with changed input', async () => {
    const t = await fixture();
    const input = { request_id: randomUUID(), estimate_id: t.estimate.id, name: 'Repeatable package' };
    const [one, two] = await Promise.all([library.saveTemplate(t.company.id, t.user.id, input), library.saveTemplate(t.company.id, t.user.id, input)]);
    expect(one.id).toBe(two.id); expect(await prisma.estimateTemplate.count()).toBe(1);
    await expect(library.saveTemplate(t.company.id, t.user.id, { ...input, name: 'Changed' })).rejects.toMatchObject({ statusCode: 409 });
  });

  it('creates one estimate and consumes one number when instantiation response is retried concurrently', async () => {
    const t = await fixture();
    const template = await library.saveTemplate(t.company.id, t.user.id, { request_id: randomUUID(), estimate_id: t.estimate.id, name: 'Package' });
    const input = { request_id: randomUUID(), project_id: t.project.id };
    const [one, two] = await Promise.all([library.instantiateTemplate(t.company.id, t.user.id, template.id, input), library.instantiateTemplate(t.company.id, t.user.id, template.id, input)]);
    expect(one.id).toBe(two.id); expect(await prisma.estimate.count()).toBe(2);
    expect((await prisma.company.findUniqueOrThrow({ where: { id: t.company.id } })).nextEstimateNumber).toBe(1002);
    expect(await prisma.activityLogEntry.count({ where: { action: 'ESTIMATE_CREATED' } })).toBe(1);
  });

  it('duplicates a protected estimate into a separate draft without modifying the original', async () => {
    const t = await fixture();
    await prisma.estimate.update({ where: { id: t.estimate.id }, data: { status: 'APPROVED' } });
    const before = await prisma.estimate.findUniqueOrThrow({ where: { id: t.estimate.id } });
    const request = { request_id: randomUUID() };
    const duplicate = await library.duplicateEstimate(t.company.id, t.user.id, t.estimate.id, request);
    const replay = await library.duplicateEstimate(t.company.id, t.user.id, t.estimate.id, request);
    expect(duplicate.id).toBe(replay.id); expect(duplicate.status).toBe('DRAFT'); expect(duplicate.version).toBe(1);
    expect(duplicate.revisesEstimateId).toBeNull(); expect(duplicate.totalAmount.toString()).toBe('49.2');
    expect(await prisma.estimate.findUniqueOrThrow({ where: { id: t.estimate.id } })).toEqual(before);
  });

  it('does not leak, copy, mutate, delete or paginate another company’s templates and saved items', async () => {
    const t = await fixture(), other = await fixture();
    const template = await library.saveTemplate(t.company.id, t.user.id, { request_id: randomUUID(), estimate_id: t.estimate.id, name: 'Private template' });
    const item = await library.saveItem(t.company.id, savedInput());
    expect((await library.listTemplates(other.company.id, { page_size: 25 })).items).toEqual([]);
    expect((await library.listItems(other.company.id, { page_size: 25 })).items).toEqual([]);
    for (const action of [
      () => library.saveTemplate(other.company.id, other.user.id, { request_id: randomUUID(), estimate_id: t.estimate.id, name: 'Stolen' }),
      () => library.instantiateTemplate(other.company.id, other.user.id, template.id, { request_id: randomUUID(), project_id: other.project.id }),
      () => library.instantiateTemplate(t.company.id, t.user.id, template.id, { request_id: randomUUID(), project_id: other.project.id }),
      () => library.duplicateEstimate(other.company.id, other.user.id, t.estimate.id, { request_id: randomUUID() }),
      () => library.saveItem(other.company.id, savedInput(), item.id),
      () => library.applyItem(other.company.id, item.id, { request_id: randomUUID(), estimate_id: other.estimate.id }),
      () => library.removeItem(other.company.id, item.id), () => library.removeTemplate(other.company.id, template.id),
      () => library.listTemplates(other.company.id, { page_size: 25, cursor: template.id }),
    ]) await expect(action()).rejects.toMatchObject({ statusCode: 404 });
  });

  it('applies a saved item once, recalculates tax and balance, and rejects new additions to sent estimates', async () => {
    const t = await fixture();
    const item = await library.saveItem(t.company.id, savedInput());
    const request = { request_id: randomUUID(), estimate_id: t.estimate.id };
    const [one, two] = await Promise.all([library.applyItem(t.company.id, item.id, request), library.applyItem(t.company.id, item.id, request)]);
    expect(one.id).toBe(two.id); expect(await prisma.estimateLineItem.count({ where: { estimateId: t.estimate.id } })).toBe(3);
    const estimate = await prisma.estimate.findUniqueOrThrow({ where: { id: t.estimate.id } });
    expect(estimate.totalAmount.toString()).toBe('73.4'); expect(estimate.taxAmount.toString()).toBe('4.4');
    await prisma.estimate.update({ where: { id: t.estimate.id }, data: { status: 'SENT' } });
    await expect(library.applyItem(t.company.id, item.id, { ...request, request_id: randomUUID() })).rejects.toMatchObject({ statusCode: 409 });
    expect((await library.applyItem(t.company.id, item.id, request)).id).toBe(one.id);
  });

  it('rejects monetary overflow before committing any catalog row', async () => {
    const t = await fixture();
    const input = savedInput();
    await expect(library.saveItem(t.company.id, { ...input, quantity: 99999999, unit_cost: 9999999999 })).rejects.toMatchObject({ statusCode: 400 });
    expect(await prisma.savedEstimateItem.count()).toBe(0); expect(await prisma.estimateLibraryOperation.count()).toBe(0);
    expect(saveItemSchema.safeParse({ ...input, tax_rate: 8.25 }).success).toBe(false);
    expect(saveItemSchema.safeParse({ ...input, markup_percent: 1000.01 }).success).toBe(false);
  });

  it('fails corrupt snapshot hierarchy atomically without claiming a number', async () => {
    const t = await fixture();
    const template = await library.saveTemplate(t.company.id, t.user.id, { request_id: randomUUID(), estimate_id: t.estimate.id, name: 'Package' });
    const snapshot = template.snapshotJson as any;
    snapshot.items[0].parent_key = snapshot.items[1].key;
    await prisma.estimateTemplate.update({ where: { id: template.id }, data: { snapshotJson: snapshot } });
    await expect(library.instantiateTemplate(t.company.id, t.user.id, template.id, { request_id: randomUUID(), project_id: t.project.id })).rejects.toMatchObject({ statusCode: 409 });
    expect(await prisma.estimate.count()).toBe(1);
    expect((await prisma.company.findUniqueOrThrow({ where: { id: t.company.id } })).nextEstimateNumber).toBe(1001);
  });

  it('searches and paginates the full saved catalog without duplicate rows', async () => {
    const t = await fixture();
    for (let i = 0; i < 28; i++) await library.saveItem(t.company.id, { ...savedInput(), name: `Drywall ${i}` });
    await library.saveItem(t.company.id, { ...savedInput(), name: 'Plumbing valve', description: null });
    const first = await library.listItems(t.company.id, { q: 'DRYWALL', page_size: 25 });
    expect(first.items).toHaveLength(25); expect(first.nextCursor).not.toBeNull();
    const second = await library.listItems(t.company.id, { q: 'DRYWALL', page_size: 25, cursor: first.nextCursor! });
    expect(second.items).toHaveLength(3); expect(second.nextCursor).toBeNull();
    expect(new Set([...first.items, ...second.items].map(i => i.id)).size).toBe(28);
  });

  it('keeps instantiated drafts and terms after deleting the reusable template', async () => {
    const t = await fixture();
    const template = await library.saveTemplate(t.company.id, t.user.id, { request_id: randomUUID(), estimate_id: t.estimate.id, name: 'Package' });
    const draft = await library.instantiateTemplate(t.company.id, t.user.id, template.id, { request_id: randomUUID(), project_id: t.project.id });
    await library.removeTemplate(t.company.id, template.id);
    expect((await proposals.create(t.company.id, { estimate_id: draft.id })).termsAndConditions).toBe('Payment due at completion');
    expect(await prisma.estimateLineItem.count({ where: { estimateId: draft.id } })).toBe(2);
  });
});
