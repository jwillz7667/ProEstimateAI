import { prisma } from '../../config/database';
import { NotFoundError } from '../../lib/errors';
import { CreateAssetInput } from './assets.validators';

/**
 * Maps lowercase API asset_type values to the Prisma AssetType enum.
 */
const ASSET_TYPE_MAP: Record<string, 'ORIGINAL' | 'AI_GENERATED' | 'DOCUMENT'> = {
  original: 'ORIGINAL',
  ai_generated: 'AI_GENERATED',
  document: 'DOCUMENT',
};

/**
 * Verifies that a project exists and belongs to the given company.
 * Returns the project if valid, throws NotFoundError otherwise.
 */
async function verifyProjectOwnership(projectId: string, companyId: string) {
  const project = await prisma.project.findFirst({
    where: { id: projectId, companyId },
  });

  if (!project) {
    throw new NotFoundError('Project', projectId);
  }

  return project;
}

/**
 * List all assets for a project, ordered by sortOrder ascending.
 * Verifies the project belongs to the requesting company.
 */
export async function listByProject(projectId: string, companyId: string) {
  await verifyProjectOwnership(projectId, companyId);

  const assets = await prisma.asset.findMany({
    where: { projectId },
    orderBy: [{ sortOrder: 'asc' }, { createdAt: 'asc' }],
  });

  return assets;
}

/**
 * Create a new asset attached to a project.
 * Verifies the project belongs to the requesting company.
 */
export async function create(projectId: string, companyId: string, data: CreateAssetInput) {
  await verifyProjectOwnership(projectId, companyId);

  const asset = await prisma.asset.create({
    data: {
      projectId,
      url: data.url,
      thumbnailUrl: data.thumbnail_url ?? null,
      assetType: data.asset_type ? ASSET_TYPE_MAP[data.asset_type] : 'ORIGINAL',
      sortOrder: data.sort_order ?? 0,
    },
  });

  return asset;
}

/**
 * Delete an asset by ID.
 * Verifies the asset's project belongs to the requesting company.
 */
export async function remove(assetId: string, companyId: string) {
  // Load the asset and verify ownership through the project relation
  const asset = await prisma.asset.findUnique({
    where: { id: assetId },
    include: { project: { select: { companyId: true } } },
  });

  if (!asset || asset.project.companyId !== companyId) {
    throw new NotFoundError('Asset', assetId);
  }

  await prisma.asset.delete({ where: { id: assetId } });
}
