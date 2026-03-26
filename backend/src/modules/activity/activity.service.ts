import { ActivityAction } from '@prisma/client';
import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { PaginationParams, paginateResults, buildCursorWhere } from '../../lib/pagination';

/**
 * List activity log entries for a project, scoped by company ownership.
 */
export async function list(projectId: string, companyId: string, pagination: PaginationParams) {
  // Verify the project belongs to the company
  const project = await prisma.project.findFirst({
    where: { id: projectId, companyId },
  });

  if (!project) {
    throw new NotFoundError('Project', projectId);
  }

  const { cursor, pageSize = 25 } = pagination;

  const entries = await prisma.activityLogEntry.findMany({
    where: { projectId },
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    take: pageSize + 1,
    ...buildCursorWhere(cursor),
  });

  return paginateResults(entries, pageSize);
}

/**
 * Log a new activity entry. Used by other modules to record actions on projects.
 */
export async function log(
  projectId: string,
  userId: string | null,
  action: ActivityAction,
  description: string
) {
  const entry = await prisma.activityLogEntry.create({
    data: {
      projectId,
      userId,
      action,
      description,
    },
  });

  return entry;
}
