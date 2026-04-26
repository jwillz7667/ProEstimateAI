import { randomUUID } from 'crypto';
import { prisma } from '../../config/database';
import { NotFoundError, ValidationError } from '../../lib/errors';
import { cached, invalidateCache, CacheKeys, CacheTTL } from '../../config/redis';
import { PaginationParams, paginateResults, buildCursorWhere } from '../../lib/pagination';
import { CreateProposalInput, SendProposalInput, RespondToProposalInput, UpdateProposalInput } from './proposals.validators';

export async function list(companyId: string, pagination: PaginationParams, projectId?: string) {
  const { cursor, pageSize = 25 } = pagination;

  const where: any = { companyId };
  if (projectId) {
    where.projectId = projectId;
  }

  const proposals = await prisma.proposal.findMany({
    where,
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
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
    throw new NotFoundError('Proposal', id);
  }

  return proposal;
}

export async function create(companyId: string, data: CreateProposalInput) {
  // Verify the estimate belongs to this company
  const estimate = await prisma.estimate.findFirst({
    where: { id: data.estimate_id, companyId },
  });

  if (!estimate) {
    throw new NotFoundError('Estimate', data.estimate_id);
  }

  // project_id is optional in the request — derive it from the estimate when missing.
  // If the caller did pass a project_id, it must match the estimate's project to prevent
  // accidentally creating a proposal that references a project the estimate doesn't belong to.
  const projectId = data.project_id ?? estimate.projectId;
  if (data.project_id && data.project_id !== estimate.projectId) {
    throw new ValidationError('project_id does not match the estimate\'s project');
  }

  // Verify the project belongs to this company
  const project = await prisma.project.findFirst({
    where: { id: projectId, companyId },
  });

  if (!project) {
    throw new NotFoundError('Project', projectId);
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

export async function send(proposalId: string, companyId: string, userId: string, data?: SendProposalInput) {
  const proposal = await prisma.proposal.findFirst({
    where: { id: proposalId, companyId },
  });

  if (!proposal) {
    throw new NotFoundError('Proposal', proposalId);
  }

  const updateData: any = {
    status: 'SENT',
    sentAt: new Date(),
  };

  // Override client message if provided in the send request
  if (data?.client_message !== undefined) {
    updateData.clientMessage = data.client_message;
  }

  const updated = await prisma.proposal.update({
    where: { id: proposalId },
    data: updateData,
  });

  // Log activity
  await prisma.activityLogEntry.create({
    data: {
      projectId: proposal.projectId,
      userId,
      action: 'PROPOSAL_SENT',
      description: `Proposal sent for estimate ${proposal.estimateId}`,
    },
  });

  // Send email to client if project has a client with email
  if (updated.shareToken) {
    const project = await prisma.project.findUnique({
      where: { id: proposal.projectId },
      include: { client: true, company: true },
    });
    if (project?.client?.email && project.company) {
      const { sendProposalEmail } = await import('../../lib/email');
      const { env: envConfig } = await import('../../config/env');
      const proposalUrl = `${envConfig.API_BASE_URL}/v1/proposals/share/${updated.shareToken}`;
      await sendProposalEmail(project.client.email, proposalUrl, project.company.name, updated.clientMessage ?? undefined);
    }
  }

  return updated;
}

export async function update(proposalId: string, companyId: string, data: UpdateProposalInput) {
  const existing = await prisma.proposal.findFirst({
    where: { id: proposalId, companyId },
  });
  if (!existing) throw new NotFoundError('Proposal', proposalId);

  const updateData: Record<string, unknown> = {};
  if (data.title !== undefined) updateData.title = data.title;
  if (data.intro_text !== undefined) updateData.introText = data.intro_text;
  if (data.scope_of_work !== undefined) updateData.scopeOfWork = data.scope_of_work;
  if (data.timeline_text !== undefined) updateData.timelineText = data.timeline_text;
  if (data.terms_and_conditions !== undefined) updateData.termsAndConditions = data.terms_and_conditions;
  if (data.footer_text !== undefined) updateData.footerText = data.footer_text;
  if (data.client_message !== undefined) updateData.clientMessage = data.client_message;
  if (data.hero_image_url !== undefined) updateData.heroImageUrl = data.hero_image_url;
  if (data.expires_at !== undefined) updateData.expiresAt = data.expires_at ? new Date(data.expires_at) : null;

  return prisma.proposal.update({ where: { id: proposalId }, data: updateData });
}

export async function remove(proposalId: string, companyId: string) {
  const existing = await prisma.proposal.findFirst({
    where: { id: proposalId, companyId },
  });
  if (!existing) throw new NotFoundError('Proposal', proposalId);
  await prisma.proposal.delete({ where: { id: proposalId } });
}

export async function getByShareToken(shareToken: string) {
  return cached(CacheKeys.proposalShare(shareToken), CacheTTL.PROPOSAL_SHARE, async () => {
    const proposal = await prisma.proposal.findUnique({
      where: { shareToken },
      include: {
        company: true,
        project: {
          include: {
            assets: {
              orderBy: { sortOrder: 'asc' },
            },
          },
        },
        estimate: {
          include: {
            lineItems: {
              orderBy: { sortOrder: 'asc' },
            },
          },
        },
      },
    });

    if (!proposal) {
      throw new NotFoundError('Proposal');
    }

    // Mark as viewed on first access (if currently in SENT status)
    if (proposal.status === 'SENT') {
      await prisma.proposal.update({
        where: { id: proposal.id },
        data: {
          status: 'VIEWED',
          viewedAt: new Date(),
        },
      });

      await prisma.activityLogEntry.create({
        data: {
          projectId: proposal.projectId,
          action: 'PROPOSAL_VIEWED',
          description: `Proposal viewed by client via share link`,
        },
      });

      // Return with updated status so the response is current
      proposal.status = 'VIEWED';
      proposal.viewedAt = new Date();

      // Invalidate so the next fetch sees the VIEWED status
      await invalidateCache(CacheKeys.proposalShare(shareToken));
    }

    return proposal;
  });
}

export async function respondToProposal(shareToken: string, data: RespondToProposalInput) {
  const proposal = await prisma.proposal.findUnique({
    where: { shareToken },
    include: {
      company: true,
      project: {
        include: {
          assets: {
            orderBy: { sortOrder: 'asc' },
          },
        },
      },
      estimate: {
        include: {
          lineItems: {
            orderBy: { sortOrder: 'asc' },
          },
        },
      },
    },
  });

  if (!proposal) {
    throw new NotFoundError('Proposal');
  }

  // Only SENT or VIEWED proposals can be responded to
  if (proposal.status !== 'SENT' && proposal.status !== 'VIEWED') {
    throw new ValidationError(`Proposal cannot be responded to in status '${proposal.status.toLowerCase()}'`);
  }

  // Check expiry
  if (proposal.expiresAt && proposal.expiresAt < new Date()) {
    throw new ValidationError('This proposal has expired');
  }

  const newStatus = data.decision === 'approved' ? 'APPROVED' : 'DECLINED';
  const activityAction = data.decision === 'approved' ? 'PROPOSAL_APPROVED' : 'PROPOSAL_DECLINED';

  const updated = await prisma.proposal.update({
    where: { id: proposal.id },
    data: {
      status: newStatus,
      respondedAt: new Date(),
      clientMessage: data.message ?? proposal.clientMessage,
    },
    include: {
      company: true,
      project: {
        include: {
          assets: {
            orderBy: { sortOrder: 'asc' },
          },
        },
      },
      estimate: {
        include: {
          lineItems: {
            orderBy: { sortOrder: 'asc' },
          },
        },
      },
    },
  });

  // Update project status to match
  await prisma.project.update({
    where: { id: proposal.projectId },
    data: {
      status: data.decision === 'approved' ? 'APPROVED' : 'DECLINED',
    },
  });

  await prisma.activityLogEntry.create({
    data: {
      projectId: proposal.projectId,
      action: activityAction,
      description: `Proposal ${data.decision} by client${data.message ? `: ${data.message}` : ''}`,
    },
  });

  await invalidateCache(CacheKeys.proposalShare(shareToken));

  return updated;
}
