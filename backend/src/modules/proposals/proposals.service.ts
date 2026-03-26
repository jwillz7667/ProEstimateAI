import { randomUUID } from 'crypto';
import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { PaginationParams, paginateResults, buildCursorWhere } from '../../lib/pagination';
import { CreateProposalInput, SendProposalInput } from './proposals.validators';

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

  // Verify the project belongs to this company
  const project = await prisma.project.findFirst({
    where: { id: data.project_id, companyId },
  });

  if (!project) {
    throw new NotFoundError('Project', data.project_id);
  }

  // Generate a unique share token
  const shareToken = randomUUID();

  const proposal = await prisma.proposal.create({
    data: {
      estimateId: data.estimate_id,
      projectId: data.project_id,
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

  return updated;
}
