import { createHash } from "node:crypto";
import { Prisma, LineItemCategory } from "@prisma/client";
import sharp from "sharp";
import { prisma } from "../../config/database";
import { ConflictError, NotFoundError, ValidationError } from "../../lib/errors";
import { buildCursorWhere, paginateResults, PaginationParams } from "../../lib/pagination";
import type { CreateJobCostInput, UploadJobReceiptInput } from "./job-costs.validators";

const publicFields = {
  id: true, companyId: true, projectId: true, requestId: true, category: true,
  description: true, amount: true, currencyCode: true, laborHours: true, hourlyRate: true,
  recordedAt: true, createdAt: true, voidedAt: true, receiptFilename: true, receiptMimeType: true,
} satisfies Prisma.JobCostEntrySelect;

function dto(entry: Prisma.JobCostEntryGetPayload<{ select: typeof publicFields }>) {
  return { id: entry.id, project_id: entry.projectId, request_id: entry.requestId,
    category: entry.category.toLowerCase(), description: entry.description,
    amount: Number(entry.amount), currency_code: entry.currencyCode,
    labor_hours: entry.laborHours === null ? null : Number(entry.laborHours),
    hourly_rate: entry.hourlyRate === null ? null : Number(entry.hourlyRate),
    recorded_at: entry.recordedAt.toISOString(), created_at: entry.createdAt.toISOString(),
    voided_at: entry.voidedAt?.toISOString() ?? null,
    receipt_filename: entry.receiptFilename, receipt_mime_type: entry.receiptMimeType,
  };
}

async function projectOwned(projectId: string, companyId: string) {
  const project = await prisma.project.findFirst({ where: { id: projectId, companyId }, select: { id: true } });
  if (!project) throw new NotFoundError("Project", projectId);
}

export async function list(projectId: string, companyId: string, pagination: PaginationParams, includeVoided = false) {
  await projectOwned(projectId, companyId);
  const pageSize = pagination.pageSize ?? 25;
  const [entries, groups, approved, latest] = await Promise.all([
    prisma.jobCostEntry.findMany({ where: { projectId, companyId, ...(includeVoided ? {} : { voidedAt: null }) }, select: publicFields,
      orderBy: [{ createdAt: "desc" }, { id: "desc" }], take: pageSize + 1, ...buildCursorWhere(pagination.cursor) }),
    prisma.jobCostEntry.groupBy({ by: ["currencyCode", "category"], where: { projectId, companyId, voidedAt: null }, _sum: { amount: true } }),
    prisma.estimate.findFirst({ where: { projectId, companyId, status: "APPROVED" }, orderBy: [{ updatedAt: "desc" }, { createdAt: "desc" }, { id: "desc" }], include: { lineItems: true } }),
    prisma.estimate.findFirst({ where: { projectId, companyId }, orderBy: [{ createdAt: "desc" }, { id: "desc" }], include: { lineItems: true } }),
  ]);
  const estimate = approved ?? latest;
  const totals = new Map<string, { materials: Prisma.Decimal; labor: Prisma.Decimal; other: Prisma.Decimal }>();
  for (const group of groups) {
    const total = totals.get(group.currencyCode) ?? { materials: new Prisma.Decimal(0), labor: new Prisma.Decimal(0), other: new Prisma.Decimal(0) };
    total[group.category.toLowerCase() as "materials" | "labor" | "other"] = group._sum.amount ?? new Prisma.Decimal(0);
    totals.set(group.currencyCode, total);
  }
  // Existing estimate documents are denominated in USD. Other receipt currencies
  // remain separate and are never silently converted into this comparison.
  const currency = "USD";
  const recorded = totals.get(currency);
  const actual = recorded ? recorded.materials.plus(recorded.labor).plus(recorded.other) : new Prisma.Decimal(0);
  const revenue = estimate ? Prisma.Decimal.max(0, estimate.totalAmount.minus(estimate.taxAmount)) : null;
  const estimatedCost = estimate?.lineItems.reduce((sum, item) => sum.plus(item.quantity.times(item.unitCost).toDecimalPlaces(2)), new Prisma.Decimal(0));
  const page = paginateResults(entries, pageSize);
  return { items: page.items.map(dto), next_cursor: page.nextCursor,
    summary: {
      currency_code: currency, estimate_id: estimate?.id ?? null, estimate_number: estimate?.estimateNumber ?? null,
      estimate_status: estimate?.status.toLowerCase() ?? null,
      quote_before_tax: revenue === null ? null : Number(revenue),
      estimated_item_cost: estimatedCost === undefined ? null : Number(estimatedCost),
      recorded_cost: Number(actual),
      quote_less_recorded_cost: revenue === null ? null : Number(revenue.minus(actual)),
      costs_by_currency: [...totals].sort(([a], [b]) => a.localeCompare(b)).map(([code, total]) => ({
        currency_code: code, materials: Number(total.materials), labor: Number(total.labor), other: Number(total.other),
        total: Number(total.materials.plus(total.labor).plus(total.other)),
      })),
    },
  };
}

export async function create(projectId: string, companyId: string, userId: string, input: CreateJobCostInput) {
  await projectOwned(projectId, companyId);
  const amount = input.labor_hours !== undefined && input.hourly_rate !== undefined
    ? new Prisma.Decimal(input.labor_hours).times(input.hourly_rate).toDecimalPlaces(2) : new Prisma.Decimal(input.amount ?? 0);
  if (amount.lte(0) || amount.gt("9999999999.99")) throw new ValidationError("The recorded cost is outside the supported range");
  if (input.amount !== undefined && !amount.equals(input.amount)) throw new ValidationError("Labor cost must match hours multiplied by hourly cost");
  if (new Date(input.recorded_at).getTime() > Date.now() + 86_400_000) throw new ValidationError("The cost date cannot be in the future");
  const payloadHash = createHash("sha256").update(JSON.stringify({ projectId, ...input })).digest("hex");
  return prisma.$transaction(async (tx) => {
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${companyId + ":cost:" + input.request_id}, 0))`;
    const previous = await tx.jobCostEntry.findUnique({ where: { companyId_requestId: { companyId, requestId: input.request_id } } });
    if (previous) {
      if (previous.payloadHash !== payloadHash || previous.projectId !== projectId) throw new ConflictError("This cost request was already used with different details");
      return dto(previous);
    }
    const entry = await tx.jobCostEntry.create({ data: {
      companyId, projectId, requestId: input.request_id, payloadHash,
      category: input.category.toUpperCase() as LineItemCategory, description: input.description,
      amount, currencyCode: input.currency_code, laborHours: input.labor_hours, hourlyRate: input.hourly_rate,
      recordedAt: new Date(input.recorded_at), createdByUserId: userId,
    }, select: publicFields });
    await tx.activityLogEntry.create({ data: { companyId, projectId, userId, action: "UPDATED", entityType: "JobCostEntry", entityId: entry.id, description: `Recorded ${input.category} cost` } });
    return dto(entry);
  });
}

export async function voidEntry(id: string, companyId: string, userId: string) {
  return prisma.$transaction(async (tx) => {
    const entry = await tx.jobCostEntry.findFirst({ where: { id, companyId } });
    if (!entry) throw new NotFoundError("Cost entry", id);
    if (!entry.voidedAt) {
      await tx.jobCostEntry.update({ where: { id }, data: { voidedAt: new Date() } });
      await tx.activityLogEntry.create({ data: { companyId, projectId: entry.projectId, userId, action: "UPDATED", entityType: "JobCostEntry", entityId: id, description: "Voided a recorded cost" } });
    }
  });
}

export async function attachReceipt(id: string, companyId: string, input: UploadJobReceiptInput) {
  const entry = await prisma.jobCostEntry.findFirst({ where: { id, companyId, voidedAt: null }, select: { id: true } });
  if (!entry) throw new NotFoundError("Cost entry", id);
  if (!/^[A-Za-z0-9+/]*={0,2}$/.test(input.data_base64)) throw new ValidationError("Invalid receipt encoding");
  let bytes = Buffer.from(input.data_base64, "base64");
  if (!bytes.length || bytes.length > 5_000_000) throw new ValidationError("Receipts must be no larger than 5 MB");
  let mimeType = input.mime_type;
  if (mimeType === "application/pdf") {
    if (bytes.subarray(0, 5).toString() !== "%PDF-") throw new ValidationError("The receipt is not a PDF file");
  } else {
    try {
      const metadata = await sharp(bytes, { limitInputPixels: 30_000_000 }).metadata();
      if ((mimeType === "image/jpeg" && metadata.format !== "jpeg") || (mimeType === "image/png" && metadata.format !== "png")) throw new Error("Invalid receipt image type");
      bytes = await sharp(bytes, { limitInputPixels: 30_000_000 }).rotate().resize({ width: 2000, height: 2000, fit: "inside", withoutEnlargement: true }).flatten({ background: "#ffffff" }).jpeg({ quality: 85 }).toBuffer();
      mimeType = "image/jpeg";
    } catch { throw new ValidationError("The receipt image could not be read"); }
  }
  const hash = createHash("sha256").update(bytes).digest("hex");
  const extension = mimeType === "application/pdf" ? "pdf" : "jpg";
  const name = input.filename.replace(/\.[^.]+$/, "").replace(/[^a-zA-Z0-9 _-]/g, "_").slice(0, 120) || "Receipt";
  const updated = await prisma.jobCostEntry.updateMany({ where: { id, companyId, voidedAt: null }, data: {
    receiptData: bytes.toString("base64"), receiptMimeType: mimeType, receiptFilename: `${name}.${extension}`, receiptHash: hash,
  } });
  if (!updated.count) throw new ConflictError("This cost was removed while the receipt was uploading");
  return { filename: `${name}.${extension}`, mime_type: mimeType };
}

export async function getReceipt(id: string, companyId: string) {
  const entry = await prisma.jobCostEntry.findFirst({ where: { id, companyId }, select: { receiptData: true, receiptMimeType: true, receiptFilename: true } });
  if (!entry?.receiptData || !entry.receiptMimeType || !entry.receiptFilename) throw new NotFoundError("Receipt");
  return { data: Buffer.from(entry.receiptData, "base64"), mimeType: entry.receiptMimeType, filename: entry.receiptFilename };
}
