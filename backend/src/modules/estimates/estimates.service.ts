import { prisma } from "../../config/database";
import { ConflictError, NotFoundError, ValidationError } from "../../lib/errors";
import { calculateEstimateTotals, estimateMoney, normalizeEstimateLineMoney } from "../../lib/estimate-money";
import { assertEditableEstimate } from "./estimates.lifecycle";
import {
  PaginationParams,
  paginateResults,
  buildCursorWhere,
} from "../../lib/pagination";
import {
  CreateEstimateInput,
  UpdateEstimateInput,
} from "./estimates.validators";
import { EstimateStatus, LineItemCategory, Prisma } from "@prisma/client";
import {
  generateEstimate,
  type EstimateGenContext,
} from "../../lib/estimate-gen";
import { gateAIAction, runReservedAction } from "../commerce/entitlement-gate";
import { readProjectQualityTier } from "../../lib/project-quality-tier";
import { recordUsage } from "../../lib/usage-limits";

async function verifyPricingProfileOwnership(
  profileId: string | null | undefined,
  companyId: string,
  database: Prisma.TransactionClient = prisma,
) {
  if (!profileId) return;
  const profile = await database.pricingProfile.findFirst({
    where: { id: profileId, companyId },
    select: { id: true },
  });
  if (!profile) throw new NotFoundError("PricingProfile", profileId);
}

export async function list(
  companyId: string,
  pagination: PaginationParams,
  projectId?: string,
  clientId?: string,
) {
  const { cursor, pageSize = 25 } = pagination;

  const where: any = { companyId };
  if (projectId) {
    where.projectId = projectId;
  }
  // Filter by client by joining through Project.clientId. The Estimate row
  // doesn't carry clientId directly — projects own that link.
  if (clientId) {
    where.project = { clientId };
  }

  const estimates = await prisma.estimate.findMany({
    where,
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: pageSize + 1,
    ...buildCursorWhere(cursor),
  });

  return paginateResults(estimates, pageSize);
}

export async function getById(id: string, companyId: string) {
  const estimate = await prisma.estimate.findFirst({
    where: { id, companyId },
  });

  if (!estimate) {
    throw new NotFoundError("Estimate", id);
  }

  return estimate;
}

export async function create(
  companyId: string,
  userId: string,
  data: CreateEstimateInput,
) {
  // Verify the project belongs to this company
  const project = await prisma.project.findFirst({
    where: { id: data.project_id, companyId },
    select: {
      id: true,
      // qualityTier intentionally omitted (defensive; avoids enum decode crash)
    },
  });

  if (!project) {
    throw new NotFoundError("Project", data.project_id);
  }

  await verifyPricingProfileOwnership(data.pricing_profile_id, companyId);
  const qualityTier = await readProjectQualityTier(data.project_id, companyId);

  // Auto-increment estimate number inside a transaction
  const estimate = await prisma.$transaction(async (tx) => {
    // Atomically claim the next number. The increment row-locks the company
    // row, serializing concurrent creates for the same company; under the
    // default READ COMMITTED isolation a read-then-write would let two
    // transactions read the same value and collide on the
    // @@unique([companyId, estimateNumber]) constraint (spurious 500). The
    // returned counter is post-increment, so the number we claimed is one less.
    const company = await tx.company
      .update({
        where: { id: companyId },
        data: { nextEstimateNumber: { increment: 1 } },
        select: { estimatePrefix: true, nextEstimateNumber: true },
      })
      .catch((err: unknown) => {
        if (
          err instanceof Prisma.PrismaClientKnownRequestError &&
          err.code === "P2025"
        ) {
          throw new NotFoundError("Company", companyId);
        }
        throw err;
      });

    const estimateNumber = `${company.estimatePrefix || "EST"}-${company.nextEstimateNumber - 1}`;

    // Create the estimate
    const created = await tx.estimate.create({
      data: {
        projectId: data.project_id,
        companyId,
        estimateNumber,
        title: data.title ?? null,
        pricingProfileId: data.pricing_profile_id ?? null,
        notes: data.notes ?? null,
        assumptions: data.assumptions ?? null,
        exclusions: data.exclusions ?? null,
        contingencyAmount: data.contingency_amount === null || data.contingency_amount === undefined ? null : estimateMoney(data.contingency_amount, "Contingency"),
        validUntil: data.valid_until ? new Date(data.valid_until) : null,
        createdByUserId: userId,
        // Snapshot the tier the project carried at create time. If the project
        // is on Auto (null), we leave the estimate's tier null so audit shows
        // the contractor didn't lock a tier in.
        qualityTier,
      },
    });

    // Log activity
    await tx.activityLogEntry.create({
      data: {
        projectId: data.project_id,
        userId,
        action: "ESTIMATE_CREATED",
        description: `Estimate ${estimateNumber} created`,
      },
    });

    return created;
  });

  return estimate;
}

export async function update(
  id: string,
  companyId: string,
  userId: string,
  data: UpdateEstimateInput,
) {
  return prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw<
      Array<{ id: string }>
    >`SELECT id FROM "Estimate" WHERE id = ${id} AND "companyId" = ${companyId} FOR UPDATE`;
    if (rows.length === 0) throw new NotFoundError("Estimate", id);
    const existing = await tx.estimate.findFirst({
      where: { id, companyId },
    });

    if (!existing) {
      throw new NotFoundError("Estimate", id);
    }

    await assertEditableEstimate(tx, existing);

    await verifyPricingProfileOwnership(data.pricing_profile_id, companyId, tx);

    const updateData: any = {};

    if (data.status !== undefined) {
      updateData.status = data.status.toUpperCase() as EstimateStatus;
    }
    if (data.title !== undefined) {
      updateData.title = data.title;
    }
    if (data.pricing_profile_id !== undefined) {
      updateData.pricingProfileId = data.pricing_profile_id;
    }
    if (data.notes !== undefined) {
      updateData.notes = data.notes;
    }
    if (data.assumptions !== undefined) {
      updateData.assumptions = data.assumptions;
    }
    if (data.exclusions !== undefined) {
      updateData.exclusions = data.exclusions;
    }
    if (data.contingency_amount !== undefined) {
      updateData.contingencyAmount = data.contingency_amount;
    }
    if (data.valid_until !== undefined) {
      updateData.validUntil = data.valid_until
        ? new Date(data.valid_until)
        : null;
    }
    const lineItems = await tx.estimateLineItem.findMany({ where: { estimateId: id } });
    const totals = calculateEstimateTotals(lineItems, data.discount_amount ?? existing.discountAmount);
    const suppliedTotals = [
      ["subtotal_materials", "subtotalMaterials"], ["subtotal_labor", "subtotalLabor"],
      ["subtotal_other", "subtotalOther"], ["tax_amount", "taxAmount"], ["total_amount", "totalAmount"],
    ] as const;
    for (const [wireName, property] of suppliedTotals) {
      const value = data[wireName];
      if (value !== undefined && !estimateMoney(value, wireName).equals(totals[property])) {
        throw new ValidationError("Estimate totals must match the saved line items. Edit the items or discount instead of overriding totals.");
      }
    }
    if (!lineItems.length && !existing.totalAmount.isZero() && suppliedTotals.every(([key]) => data[key] === undefined)) {
      throw new ValidationError("Add priced line items before changing this legacy header-only estimate. Its existing value has been preserved.");
    }
    if (data.contingency_amount !== undefined && data.contingency_amount !== null) {
      updateData.contingencyAmount = estimateMoney(data.contingency_amount, "Contingency");
    }
    Object.assign(updateData, totals, { updatedAt: new Date(Math.max(Date.now(), existing.updatedAt.getTime() + 1)) });
    const estimate = await tx.estimate.update({
      where: { id },
      data: updateData,
    });

    // Log activity
    await tx.activityLogEntry.create({
      data: {
        projectId: existing.projectId,
        userId,
        action: "ESTIMATE_UPDATED",
        description: `Estimate ${existing.estimateNumber} updated`,
      },
    });

    return estimate;
  });
}

export async function remove(id: string, companyId: string) {
  await prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT id FROM "Estimate" WHERE id = ${id} AND "companyId" = ${companyId} FOR UPDATE
    `;
    if (!rows.length) throw new NotFoundError("Estimate", id);
    const existing = await tx.estimate.findUniqueOrThrow({ where: { id } });
    await assertEditableEstimate(tx, existing);
    await tx.proposal.deleteMany({ where: { estimateId: id } });
    await tx.estimate.delete({ where: { id } });
  });
}

/** A durable retry key prevents a lost response from creating two revisions. */
export async function revise(id: string, companyId: string, userId: string, requestId: string) {
  return prisma.$transaction(async (tx) => {
    const key = `revision:${companyId}:${requestId}`;
    await tx.$executeRaw`SELECT pg_advisory_xact_lock(hashtextextended(${key}, 0))`;
    const rows = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT id FROM "Estimate" WHERE id = ${id} AND "companyId" = ${companyId} FOR UPDATE
    `;
    if (!rows.length) throw new NotFoundError("Estimate", id);
    const receipt = await tx.estimateRevisionRequest.findUnique({ where: { companyId_requestId: { companyId, requestId } } });
    if (receipt) {
      if (receipt.sourceEstimateId !== id) throw new ConflictError("This revision request was already used for another estimate.");
      const result = receipt.revisionEstimateId ? await tx.estimate.findFirst({ where: { id: receipt.revisionEstimateId, companyId } }) : null;
      if (!result) throw new ConflictError("The previously created revision was removed. Start a new revision request to continue.");
      return result;
    }
    const source = await tx.estimate.findUniqueOrThrow({
      where: { id }, include: { lineItems: { orderBy: [{ sortOrder: "asc" }, { id: "asc" }] } },
    });
    if (source.status === "DRAFT") throw new ConflictError("This estimate is still a draft. Continue editing it before creating a revision.");
    const published = await tx.estimate.findFirst({ where: { companyId, revisesEstimateId: source.id, status: { not: "DRAFT" } }, select: { id: true } });
    if (published) throw new ConflictError("A later revision has already been sent. Open that revision and create the next version from it.");
    const pending = await tx.estimate.findFirst({
      where: { companyId, revisesEstimateId: source.id, status: "DRAFT" }, orderBy: [{ updatedAt: "desc" }, { id: "desc" }],
    });
    if (pending) {
      await tx.estimateRevisionRequest.create({ data: { companyId, requestId, sourceEstimateId: source.id, revisionEstimateId: pending.id } });
      return pending;
    }
    const company = await tx.company.update({
      where: { id: companyId }, data: { nextEstimateNumber: { increment: 1 } },
      select: { estimatePrefix: true, nextEstimateNumber: true },
    });
    const revision = await tx.estimate.create({
      data: {
        companyId, projectId: source.projectId, createdByUserId: userId,
        revisesEstimateId: source.id, revisionRequestId: requestId,
        estimateNumber: `${company.estimatePrefix || "EST"}-${company.nextEstimateNumber - 1}`,
        version: source.version + 1, title: source.title, pricingProfileId: source.pricingProfileId,
        qualityTier: source.qualityTier, subtotalMaterials: source.subtotalMaterials,
        subtotalLabor: source.subtotalLabor, subtotalOther: source.subtotalOther,
        taxAmount: source.taxAmount, discountAmount: source.discountAmount,
        contingencyAmount: source.contingencyAmount, totalAmount: source.totalAmount,
        assumptions: source.assumptions, exclusions: source.exclusions,
        notes: source.notes, validUntil: source.validUntil,
      },
    });
    const copiedIds = new Map<string, string>();
    for (const item of source.lineItems) {
      const { id: oldId, estimateId: _estimateId, parentLineItemId: _parent, ...fields } = item;
      const copy = await tx.estimateLineItem.create({ data: { ...fields, estimateId: revision.id } });
      copiedIds.set(oldId, copy.id);
    }
    for (const item of source.lineItems) {
      if (!item.parentLineItemId) continue;
      const parentId = copiedIds.get(item.parentLineItemId);
      if (!parentId) throw new ConflictError("The estimate contains an invalid item hierarchy. Contact support before revising it.");
      await tx.estimateLineItem.update({ where: { id: copiedIds.get(item.id)! }, data: { parentLineItemId: parentId } });
    }
    await tx.estimateRevisionRequest.create({ data: { companyId, requestId, sourceEstimateId: source.id, revisionEstimateId: revision.id } });
    await tx.activityLogEntry.create({ data: {
      projectId: source.projectId, userId, action: "ESTIMATE_CREATED",
      description: `Revision ${revision.estimateNumber} created from ${source.estimateNumber} (version ${source.version})`,
    } });
    return revision;
  });
}

/**
 * AI-generate a complete, professional estimate for a project. Pulls the
 * project, the company's branding and numbering defaults, the project's
 * selected materials, and any configured pricing profile + labor rates, then
 * hands everything to the estimate-gen lib. The returned structured output is
 * persisted as an Estimate plus its line items in a single transaction.
 */
export async function generateAI(
  companyId: string,
  userId: string,
  projectId: string,
) {
  const project = await prisma.project.findFirst({
    where: { id: projectId, companyId },
    select: {
      id: true,
      projectType: true,
      title: true,
      description: true,
      squareFootage: true,
      dimensions: true,
      // qualityTier intentionally omitted (defensive; avoids enum decode crash)
    },
  });
  if (!project) {
    throw new NotFoundError("Project", projectId);
  }

  const company = await prisma.company.findUnique({ where: { id: companyId } });
  if (!company) {
    throw new NotFoundError("Company", companyId);
  }

  const [selectedMaterials, defaultPricingProfile] = await Promise.all([
    prisma.materialSuggestion.findMany({
      where: { projectId, isSelected: true },
      orderBy: { sortOrder: "asc" },
    }),
    prisma.pricingProfile.findFirst({
      where: { companyId, isDefault: true },
      include: { laborRates: true },
    }),
  ]);

  const qualityTier = await readProjectQualityTier(projectId, companyId);
  const context: EstimateGenContext = {
    projectType: project.projectType,
    // Auto-mode falls back to STANDARD for the prompt + clamping; the audit
    // snapshot below preserves the original null so we can tell apart "user
    // chose STANDARD" from "user left it on Auto".
    qualityTier: qualityTier ?? "STANDARD",
    projectTitle: project.title,
    projectDescription: project.description ?? undefined,
    squareFootage: project.squareFootage?.toString(),
    dimensions: project.dimensions ?? undefined,
    companyName: company.name,
    companyPhone: company.phone ?? undefined,
    companyEmail: company.email ?? undefined,
    companyAddress:
      [company.address, company.city, company.state, company.zip]
        .filter(Boolean)
        .join(", ") || undefined,
    companyWebsite: company.websiteUrl ?? undefined,
    defaultMarkupPercent: company.defaultMarkupPercent
      ? Number(company.defaultMarkupPercent)
      : undefined,
    laborMarkupPercent:
      company.laborMarkupPercent != null
        ? Number(company.laborMarkupPercent)
        : undefined,
    defaultTaxRate: company.defaultTaxRate
      ? Number(company.defaultTaxRate)
      : undefined,
    selectedMaterials: selectedMaterials.map((m) => ({
      name: m.name,
      category: m.category,
      estimatedCost: Number(m.estimatedCost),
      unit: m.unit,
      quantity: Number(m.quantity),
    })),
    pricingProfile: defaultPricingProfile
      ? {
          defaultMarkupPercent: Number(
            defaultPricingProfile.defaultMarkupPercent,
          ),
          contingencyPercent: Number(defaultPricingProfile.contingencyPercent),
          wasteFactor: Number(defaultPricingProfile.wasteFactor),
          laborRates: defaultPricingProfile.laborRates.map((r) => ({
            category: r.category,
            ratePerHour: Number(r.ratePerHour),
          })),
        }
      : undefined,
  };

  const reservation = await gateAIAction({
    userId,
    companyId,
    metric: "ESTIMATE_GENERATED",
  });
  return runReservedAction(reservation, async () => {
    const generated = await generateEstimate(context);

    const normalizedLines = generated.lineItems.map((item) => ({
      ...item, ...normalizeEstimateLineMoney(item.quantity, item.unitCost, item.markupPercent),
      taxRate: new Prisma.Decimal(item.taxRate).toDecimalPlaces(4),
    }));
    const canonicalTotals = calculateEstimateTotals(normalizedLines, 0);

    const validUntil = new Date();
    validUntil.setDate(validUntil.getDate() + generated.validDays);

    const notesWithTerms = [generated.overview, generated.terms]
      .filter((s) => s && s.trim().length > 0)
      .join("\n\n");

    // Compose Assumptions and Exclusions into the dedicated Estimate columns.
    const estimate = await prisma.$transaction(async (tx) => {
      // Atomically claim the next number — see the manual-create path above
      // for why the read-then-write is replaced by an increment-and-read.
      const co = await tx.company
        .update({
          where: { id: companyId },
          data: { nextEstimateNumber: { increment: 1 } },
          select: { estimatePrefix: true, nextEstimateNumber: true },
        })
        .catch((err: unknown) => {
          if (
            err instanceof Prisma.PrismaClientKnownRequestError &&
            err.code === "P2025"
          ) {
            throw new NotFoundError("Company", companyId);
          }
          throw err;
        });

      const estimateNumber = `${co.estimatePrefix || "EST"}-${co.nextEstimateNumber - 1}`;

      const created = await tx.estimate.create({
        data: {
          projectId,
          companyId,
          estimateNumber,
          title: generated.title,
          pricingProfileId: defaultPricingProfile?.id ?? null,
          createdByUserId: userId,
          // Snapshot the project's tier (or null for Auto). Stored alongside
          // the line items so audit trails show what was clamped against.
          qualityTier,
          ...canonicalTotals,
          assumptions: generated.assumptions || null,
          exclusions: generated.exclusions || null,
          notes: notesWithTerms || null,
          validUntil,
        },
      });

      // Persist each AI-generated line item.
      for (let i = 0; i < normalizedLines.length; i++) {
        const item = normalizedLines[i];
        const categoryEnum =
          item.category === "materials"
            ? LineItemCategory.MATERIALS
            : item.category === "labor"
              ? LineItemCategory.LABOR
              : LineItemCategory.OTHER;

        await tx.estimateLineItem.create({
          data: {
            estimateId: created.id,
            category: categoryEnum,
            priceOrigin: "AI_SUGGESTED",
            itemType: "per_unit",
            name: item.name,
            description: item.description || null,
            quantity: item.quantity,
            unit: item.unit,
            unitCost: item.unitCost,
            markupPercent: item.markupPercent,
            // Canonical: tax_rate stored as a fraction (e.g. 0.0825 for 8.25%),
            // matching the validator (max 1.0) and the recalc logic that
            // treats the DB value as a multiplier.
            taxRate: item.taxRate,
            lineTotal: item.lineTotal,
            sortOrder: i,
          },
        });
      }

      await tx.activityLogEntry.create({
        data: {
          projectId,
          userId,
          action: "ESTIMATE_CREATED",
          description: `AI-generated estimate ${estimateNumber} created`,
        },
      });

      return created;
    });

    // Record usage AFTER the estimate is committed so a failed write doesn't burn cap.
    if (!reservation)
      await recordUsage(userId, companyId, "ESTIMATE_GENERATED", {
        projectId,
        estimateId: estimate.id,
        kind: "ai_estimate",
      });
    return estimate;
  });
}
