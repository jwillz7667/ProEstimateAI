import { randomUUID } from "crypto";
import { prisma } from "../../config/database";
import { NotFoundError, ValidationError } from "../../lib/errors";
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
  // Verify the estimate belongs to this company
  const estimate = await prisma.estimate.findFirst({
    where: { id: data.estimate_id, companyId },
  });

  if (!estimate) {
    throw new NotFoundError("Estimate", data.estimate_id);
  }

  // project_id is optional in the request — derive it from the estimate when missing.
  // If the caller did pass a project_id, it must match the estimate's project to prevent
  // accidentally creating a proposal that references a project the estimate doesn't belong to.
  const projectId = data.project_id ?? estimate.projectId;
  if (data.project_id && data.project_id !== estimate.projectId) {
    throw new ValidationError(
      "project_id does not match the estimate's project",
    );
  }

  // Verify the project belongs to this company
  const project = await prisma.project.findFirst({
    where: { id: projectId, companyId },
    select: { id: true },
  });

  if (!project) {
    throw new NotFoundError("Project", projectId);
  }

  // Generate a unique share token
  const shareToken = randomUUID();

  const proposal = await prisma.proposal.create({
    data: {
      estimateId: data.estimate_id,
      projectId,
      companyId,
      shareToken,
      heroImageUrl: data.hero_image_url ?? null,
      termsAndConditions: data.terms_and_conditions ?? null,
      clientMessage: data.client_message ?? null,
      expiresAt: data.expires_at ? new Date(data.expires_at) : null,
    },
  });

  return proposal;
}

export async function send(
  proposalId: string,
  companyId: string,
  userId: string,
  data?: SendProposalInput,
) {
  const updated = await prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw<
      Array<{ id: string }>
    >`SELECT id FROM "Proposal" WHERE id = ${proposalId} AND "companyId" = ${companyId} FOR UPDATE`;
    if (rows.length === 0) throw new NotFoundError("Proposal", proposalId);
    const proposal = await tx.proposal.findUniqueOrThrow({
      where: { id: proposalId },
    });
    if (
      proposal.respondedAt ||
      !["DRAFT", "SENT", "VIEWED"].includes(proposal.status)
    ) {
      throw new ValidationError(
        "Create a new proposal to request another client decision",
      );
    }
    if (proposal.expiresAt && proposal.expiresAt <= new Date())
      throw new ValidationError("This proposal has expired");
    const updateData: Record<string, unknown> = {
      status: "SENT",
      sentAt: new Date(),
    };
    // Override client message if provided in the send request
    if (data?.client_message !== undefined) {
      updateData.clientMessage = data.client_message;
    }

    const result = await tx.proposal.update({
      where: { id: proposalId },
      data: updateData,
    });

    // Log activity
    await tx.activityLogEntry.create({
      data: {
        projectId: proposal.projectId,
        userId,
        action: "PROPOSAL_SENT",
        description: `Proposal sent for estimate ${proposal.estimateId}`,
      },
    });

    return result;
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
    const rows = await tx.$queryRaw<
      Array<{ id: string }>
    >`SELECT id FROM "Proposal" WHERE id = ${proposalId} AND "companyId" = ${companyId} FOR UPDATE`;
    if (rows.length === 0) throw new NotFoundError("Proposal", proposalId);
    const existing = await tx.proposal.findFirst({
      where: { id: proposalId, companyId },
    });
    if (!existing) throw new NotFoundError("Proposal", proposalId);
    if (existing.respondedAt)
      throw new ValidationError(
        "A proposal with a recorded client decision cannot be edited; create a new proposal",
      );

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
  const existing = await prisma.proposal.findFirst({
    where: { id: proposalId, companyId },
  });
  if (!existing) throw new NotFoundError("Proposal", proposalId);
  await prisma.proposal.delete({ where: { id: proposalId } });
  if (existing.shareToken)
    await invalidateCache(CacheKeys.proposalShare(existing.shareToken));
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

export async function getByShareToken(shareToken: string) {
  return prisma.$transaction(async (tx) => {
    const proposal = await tx.proposal.findUnique({
      where: { shareToken },
      include: sharedProposalInclude,
    });
    if (!proposal) throw new NotFoundError("Proposal");
    const viewedAt = new Date();
    // Conditional update prevents a view racing a response from overwriting
    // APPROVED/DECLINED, and creates exactly one first-view activity entry.
    const viewed = await tx.proposal.updateMany({
      where: { id: proposal.id, status: "SENT" },
      data: { status: "VIEWED", viewedAt },
    });
    if (viewed.count === 1) {
      await tx.activityLogEntry.create({
        data: {
          projectId: proposal.projectId,
          action: "PROPOSAL_VIEWED",
          description: "Proposal viewed by client via share link",
        },
      });
    }
    return tx.proposal.findUniqueOrThrow({
      where: { shareToken },
      include: sharedProposalInclude,
    });
  });
}

export async function respondToProposal(
  shareToken: string,
  data: RespondToProposalInput,
) {
  const updated = await prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw<Array<{ id: string }>>`
      SELECT id FROM "Proposal" WHERE "shareToken" = ${shareToken} FOR UPDATE
    `;
    if (rows.length === 0) throw new NotFoundError("Proposal");
    const proposal = await tx.proposal.findUniqueOrThrow({
      where: { shareToken },
      include: sharedProposalInclude,
    });
    // Once recorded, the first decision remains authoritative even when
    // conflicting requests arrive together or the connection retries later.
    if (proposal.respondedAt) return proposal;
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
