import { randomUUID } from "crypto";
import { Prisma } from "@prisma/client";
import { prisma } from "../../config/database";
import { ConflictError, NotFoundError, ValidationError } from "../../lib/errors";
import { toLiveSharedProposalDto, type ProposalWithRelations } from "./proposals.share-dto";
import { readProposalSnapshot, sharedProposalContentSchema } from "./proposal-document-snapshot";
import { invalidateCache, CacheKeys } from "../../config/redis";
import {
  PaginationParams,
  paginateResults,
  buildCursorWhere,
} from "../../lib/pagination";
import {
  CreateProposalInput,
  SendProposalInput,
  RespondToProposalInput,
  UpdateProposalInput,
} from "./proposals.validators";

// Every path that needs both locks takes Estimate first, then Proposal. Item
// writes and estimate header edits use the same parent lock as first send.
async function lockProposal(
  tx: Prisma.TransactionClient,
  selector: { id: string; companyId: string } | { shareToken: string },
) {
  const found = await tx.proposal.findFirst({ where: selector, select: { id: true, estimateId: true } });
  if (!found) throw new NotFoundError("Proposal");
  const source = await tx.estimate.findUnique({ where: { id: found.estimateId }, select: { revisesEstimateId: true } });
  if (!source) throw new NotFoundError("Proposal");
  const ids = [found.estimateId, ...(source.revisesEstimateId ? [source.revisesEstimateId] : [])];
  const estimates = await tx.$queryRaw<Array<{ id: string }>>(Prisma.sql`
    SELECT id FROM "Estimate" WHERE id IN (${Prisma.join(ids)}) ORDER BY id FOR UPDATE
  `);
  if (estimates.length !== ids.length) throw new NotFoundError("Proposal");
  const rows = await tx.$queryRaw<Array<{ id: string }>>`
    SELECT id FROM "Proposal" WHERE id = ${found.id} FOR UPDATE
  `;
  if (!rows.length) throw new NotFoundError("Proposal");
  const proposal = await tx.proposal.findFirst({ where: selector, include: sharedProposalInclude });
  if (!proposal) throw new NotFoundError("Proposal");
  return proposal;
}

function documentSnapshot(proposal: ProposalWithRelations, capturedAt: Date, reason: "sent" | "legacy_backfill") {
  return {
    schema_version: 1,
    estimate_id: proposal.estimateId,
    estimate_version: proposal.estimate.version,
    captured_at: capturedAt.toISOString(),
    capture_reason: reason,
    content: sharedProposalContentSchema.parse(toLiveSharedProposalDto(proposal)),
  } satisfies Prisma.InputJsonObject;
}

/** Covers pre-migration/test/imported sent rows without inventing past prices. */
async function ensureSentSnapshot(tx: Prisma.TransactionClient, proposal: ProposalWithRelations) {
  if (proposal.sentSnapshot !== null) {
    readProposalSnapshot(proposal.sentSnapshot);
    return proposal;
  }
  if (proposal.status === "DRAFT" && !proposal.sentAt && !proposal.respondedAt) return proposal;
  const capturedAt = new Date();
  const frozen = await tx.proposal.update({
    where: { id: proposal.id },
    data: {
      sentSnapshot: documentSnapshot(proposal, capturedAt, "legacy_backfill"),
      sentSnapshotCapturedAt: capturedAt,
    },
    include: sharedProposalInclude,
  });
  const status = proposal.status === "APPROVED" || proposal.status === "DECLINED" ? proposal.status : "SENT";
  await tx.estimate.updateMany({ where: { id: proposal.estimateId, status: "DRAFT" }, data: { status } });
  return frozen;
}

function assertDraftProposal(proposal: ProposalWithRelations) {
  if (proposal.status !== "DRAFT" || proposal.sentSnapshot || proposal.sentAt || proposal.respondedAt) {
    throw new ConflictError("A sent proposal cannot be edited or deleted. Create a new estimate revision and proposal.");
  }
}

export async function list(
  companyId: string,
  pagination: PaginationParams,
  projectId?: string,
) {
  const { cursor, pageSize = 25 } = pagination;

  const where: any = { companyId };
  if (projectId) {
    where.projectId = projectId;
  }

  const proposals = await prisma.proposal.findMany({
    where,
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: pageSize + 1,
    ...buildCursorWhere(cursor),
  });

  return paginateResults(proposals, pageSize);
}

export async function getById(id: string, companyId: string) {
  const proposal = await prisma.proposal.findFirst({
    where: { id, companyId },
  });

  if (!proposal) {
    throw new NotFoundError("Proposal", id);
  }

  return proposal;
}

export async function create(companyId: string, data: CreateProposalInput) {
  return prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT id FROM "Estimate" WHERE id = ${data.estimate_id} AND "companyId" = ${companyId} FOR UPDATE
    `;
    if (!rows.length) throw new NotFoundError("Estimate", data.estimate_id);
    const estimate = await tx.estimate.findUniqueOrThrow({ where: { id: data.estimate_id } });
    if (estimate.status !== "DRAFT") {
      throw new ConflictError("Create a new estimate revision before preparing another proposal.");
    }
    const projectId = data.project_id ?? estimate.projectId;
    if (projectId !== estimate.projectId) throw new ValidationError("project_id does not match the estimate's project");
    const project = await tx.project.findFirst({ where: { id: projectId, companyId }, select: { id: true } });
    if (!project) throw new NotFoundError("Project", projectId);
    return tx.proposal.create({
      data: {
        estimateId: data.estimate_id, projectId, companyId, shareToken: randomUUID(),
        heroImageUrl: data.hero_image_url ?? null,
        termsAndConditions: data.terms_and_conditions ?? null,
        clientMessage: data.client_message ?? null,
        expiresAt: data.expires_at ? new Date(data.expires_at) : null,
      },
    });
  });
}

export async function send(
  proposalId: string,
  companyId: string,
  userId: string,
  data?: SendProposalInput,
) {
  const updated = await prisma.$transaction(async (tx) => {
    let proposal = await lockProposal(tx, { id: proposalId, companyId });
    if (proposal.respondedAt || !["DRAFT", "SENT", "VIEWED"].includes(proposal.status)) {
      throw new ValidationError("Create a new proposal to request another client decision");
    }
    if (proposal.expiresAt && proposal.expiresAt <= new Date()) throw new ValidationError("This proposal has expired");
    if (proposal.status === "DRAFT") {
      if (proposal.sentSnapshot || proposal.sentAt) throw new ConflictError("This proposal already has a sent version. Create a new estimate revision.");
      if (proposal.estimate.status !== "DRAFT") {
        throw new ConflictError("This estimate has already been sent. Create a new estimate revision.");
      }
      if (data?.expected_estimate_updated_at && new Date(data.expected_estimate_updated_at).getTime() !== proposal.estimate.updatedAt.getTime()) {
        throw new ConflictError("This estimate changed after you reviewed it. Refresh and review the latest prices before sending.");
      }
      if (proposal.estimate.revisesEstimateId) {
        const newer = await tx.estimate.findFirst({
          where: { revisesEstimateId: proposal.estimate.revisesEstimateId, id: { not: proposal.estimateId }, status: { not: "DRAFT" } },
          select: { id: true },
        });
        if (newer) throw new ConflictError("Another revision has already been sent. Revise that version to continue.");
        // Sending the replacement, not merely starting its draft, retires the
        // earlier pending offer. Historical accepted documents remain intact.
        await tx.proposal.updateMany({
          where: { estimateId: proposal.estimate.revisesEstimateId, status: { in: ["SENT", "VIEWED"] } },
          data: { status: "EXPIRED" },
        });
        await tx.estimate.updateMany({ where: { id: proposal.estimate.revisesEstimateId, status: "SENT" }, data: { status: "EXPIRED" } });
      }
      const sentAt = new Date();
      proposal = {
        ...proposal, status: "SENT", sentAt,
        clientMessage: data?.client_message !== undefined ? data.client_message : proposal.clientMessage,
      };
      proposal = await tx.proposal.update({
        where: { id: proposal.id },
        data: {
          status: "SENT", sentAt, clientMessage: proposal.clientMessage,
          sentSnapshot: documentSnapshot(proposal, sentAt, "sent"), sentSnapshotCapturedAt: sentAt,
        },
        include: sharedProposalInclude,
      });
      await tx.estimate.update({ where: { id: proposal.estimateId }, data: { status: "SENT" } });
      await tx.project.updateMany({
        where: { id: proposal.projectId, status: { in: ["DRAFT", "PHOTOS_UPLOADED", "GENERATION_COMPLETE", "ESTIMATE_CREATED"] } },
        data: { status: "PROPOSAL_SENT" },
      });
    } else {
      proposal = await ensureSentSnapshot(tx, proposal);
      if (data?.client_message !== undefined && data.client_message !== proposal.clientMessage) {
        throw new ConflictError("Resending preserves the original proposal. Create a revision to change its message.");
      }
    }
    await tx.activityLogEntry.create({
      data: {
        projectId: proposal.projectId, userId, action: "PROPOSAL_SENT",
        description: `Proposal sent for estimate ${proposal.estimateId}`,
      },
    });
    return proposal;
  });
  if (updated.shareToken)
    await invalidateCache(CacheKeys.proposalShare(updated.shareToken));

  // Send email to client if project has a client with email
  if (updated.shareToken) {
    const project = await prisma.project.findUnique({
      where: { id: updated.projectId },
      select: {
        id: true,
        client: true,
        company: true,
      },
    });
    if (project?.client?.email && project.company) {
      const { sendProposalEmail } = await import("../../lib/email");
      const { env: envConfig } = await import("../../config/env");
      const proposalUrl = `${envConfig.PUBLIC_PROPOSAL_BASE_URL.replace(/\/$/, "")}/${encodeURIComponent(updated.shareToken)}`;
      await sendProposalEmail(
        project.client.email,
        proposalUrl,
        project.company.name,
        updated.clientMessage ?? undefined,
      );
    }
  }

  return updated;
}

export async function update(
  proposalId: string,
  companyId: string,
  data: UpdateProposalInput,
) {
  return prisma.$transaction(async (tx) => {
    const existing = await lockProposal(tx, { id: proposalId, companyId });
    assertDraftProposal(existing);

    const updateData: Record<string, unknown> = {};
    if (data.title !== undefined) updateData.title = data.title;
    if (data.intro_text !== undefined) updateData.introText = data.intro_text;
    if (data.scope_of_work !== undefined)
      updateData.scopeOfWork = data.scope_of_work;
    if (data.timeline_text !== undefined)
      updateData.timelineText = data.timeline_text;
    if (data.terms_and_conditions !== undefined)
      updateData.termsAndConditions = data.terms_and_conditions;
    if (data.footer_text !== undefined)
      updateData.footerText = data.footer_text;
    if (data.client_message !== undefined)
      updateData.clientMessage = data.client_message;
    if (data.hero_image_url !== undefined)
      updateData.heroImageUrl = data.hero_image_url;
    if (data.expires_at !== undefined)
      updateData.expiresAt = data.expires_at ? new Date(data.expires_at) : null;

    const updated = await tx.proposal.update({
      where: { id: proposalId },
      data: updateData,
    });
    if (existing.shareToken)
      await invalidateCache(CacheKeys.proposalShare(existing.shareToken));
    return updated;
  });
}

export async function remove(proposalId: string, companyId: string) {
  const existing = await prisma.$transaction(async (tx) => {
    const proposal = await lockProposal(tx, { id: proposalId, companyId });
    assertDraftProposal(proposal);
    await tx.proposal.delete({ where: { id: proposal.id } });
    return proposal;
  });
  if (existing.shareToken) await invalidateCache(CacheKeys.proposalShare(existing.shareToken));
}

// Shared content contains Dates and Decimal values. Fetch it fresh instead of
// caching ORM objects as JSON, which loses their types and serves obsolete prices.
const sharedProposalInclude = {
  company: true,
  project: {
    select: {
      id: true,
      title: true,
      description: true,
      projectType: true,
      assets: { orderBy: { sortOrder: "asc" as const } },
    },
  },
  estimate: {
    include: { lineItems: { orderBy: { sortOrder: "asc" as const } } },
  },
} as const;

/** Authenticated preview/PDF access also uses the frozen sent document. */
export async function getForRendering(id: string, companyId: string) {
  return prisma.$transaction(async (tx) => {
    const proposal = await lockProposal(tx, { id, companyId });
    return ensureSentSnapshot(tx, proposal);
  });
}

export async function getByShareToken(shareToken: string) {
  return prisma.$transaction(async (tx) => {
    let proposal = await lockProposal(tx, { shareToken });
    if (proposal.status === "DRAFT") throw new NotFoundError("Proposal");
    proposal = await ensureSentSnapshot(tx, proposal);
    if (proposal.status === "SENT") {
      proposal = await tx.proposal.update({
        where: { id: proposal.id }, data: { status: "VIEWED", viewedAt: new Date() }, include: sharedProposalInclude,
      });
      await tx.activityLogEntry.create({
        data: { projectId: proposal.projectId, action: "PROPOSAL_VIEWED", description: "Proposal viewed by client via share link" },
      });
    }
    return proposal;
  });
}

export async function respondToProposal(
  shareToken: string,
  data: RespondToProposalInput,
) {
  const updated = await prisma.$transaction(async (tx) => {
    let proposal = await lockProposal(tx, { shareToken });
    if (proposal.status === "DRAFT") throw new ValidationError("This proposal has not been sent");
    proposal = await ensureSentSnapshot(tx, proposal);
    // Once recorded, the first decision remains authoritative even when
    // conflicting requests arrive together or the connection retries later.
    if (proposal.respondedAt) return proposal;
    const priorDecision = await tx.proposal.findFirst({
      where: { estimateId: proposal.estimateId, id: { not: proposal.id }, respondedAt: { not: null } },
      select: { id: true },
    });
    if (priorDecision) throw new ConflictError("A decision has already been recorded for another proposal of this estimate.");
    if (proposal.status !== "SENT" && proposal.status !== "VIEWED") {
      throw new ValidationError(
        `Proposal cannot be responded to in status '${proposal.status.toLowerCase()}'`,
      );
    }
    if (proposal.expiresAt && proposal.expiresAt <= new Date())
      throw new ValidationError("This proposal has expired");
    const status = data.decision === "approved" ? "APPROVED" : "DECLINED";
    const result = await tx.proposal.update({
      where: { id: proposal.id },
      data: {
        status,
        respondedAt: new Date(),
        clientMessage: data.message ?? proposal.clientMessage,
      },
      include: sharedProposalInclude,
    });
    await tx.estimate.update({
      where: { id: proposal.estimateId },
      data: { status },
    });
    // A late response must not reopen a project already invoiced or finished.
    await tx.project.updateMany({
      where: {
        id: proposal.projectId,
        status: { notIn: ["INVOICED", "COMPLETED", "ARCHIVED"] },
      },
      data: { status },
    });
    await tx.activityLogEntry.create({
      data: {
        projectId: proposal.projectId,
        action:
          data.decision === "approved"
            ? "PROPOSAL_APPROVED"
            : "PROPOSAL_DECLINED",
        description: `Proposal ${data.decision} by client${data.message ? `: ${data.message}` : ""}`,
      },
    });
    return result;
  });
  await invalidateCache(CacheKeys.proposalShare(shareToken));
  return updated;
}
