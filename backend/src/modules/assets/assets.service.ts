import { prisma } from '../../config/database';
import { env } from '../../config/env';
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
 *
 * If the URL is a data URL (base64-encoded image), the raw base64 data
 * is stored in the `imageData` column and the `url` is rewritten to the
 * binary-serve endpoint `/v1/assets/:id/image`.
 */
export async function create(projectId: string, companyId: string, data: CreateAssetInput) {
  await verifyProjectOwnership(projectId, companyId);

  let url = data.url;
  let imageData: string | null = null;
  let imageMimeType: string | null = null;

  // Detect data URL and extract base64 payload
  const dataUrlMatch = url.match(/^data:(image\/[a-z+]+);base64,(.+)$/i);
  if (dataUrlMatch) {
    imageMimeType = dataUrlMatch[1];
    imageData = dataUrlMatch[2];
    // Placeholder URL — will be replaced with the actual serve endpoint after creation
    url = '__pending__';
  }

  const asset = await prisma.asset.create({
    data: {
      projectId,
      url,
      thumbnailUrl: data.thumbnail_url ?? null,
      assetType: data.asset_type ? ASSET_TYPE_MAP[data.asset_type] : 'ORIGINAL',
      sortOrder: data.sort_order ?? 0,
      imageData,
      imageMimeType,
    },
  });

  // Rewrite URL to the binary-serve endpoint if we stored image data
  if (imageData) {
    const serveUrl = `${env.API_BASE_URL}/v1/assets/${asset.id}/image`;
    const updated = await prisma.asset.update({
      where: { id: asset.id },
      data: { url: serveUrl, thumbnailUrl: serveUrl },
    });
    return updated;
  }

  return asset;
}

/**
 * Serve the stored image binary for an asset.
 * Returns { data: Buffer, mimeType: string } or null if no image data stored.
 */
export async function getImageData(assetId: string, companyId: string) {
  const asset = await prisma.asset.findUnique({
    where: { id: assetId },
    include: { project: { select: { companyId: true } } },
  });

  if (!asset || asset.project.companyId !== companyId) {
    throw new NotFoundError('Asset', assetId);
  }

  if (!asset.imageData || !asset.imageMimeType) {
    return null;
  }

  return {
    data: Buffer.from(asset.imageData, 'base64'),
    mimeType: asset.imageMimeType,
  };
}

/**
 * Public (no-auth) image retrieval by asset ID.
 * Used for serving images to AsyncImage / <img> without auth headers.
 * Security: asset IDs are CUIDs (unguessable).
 */
export async function getPublicAssetImage(assetId: string) {
  const asset = await prisma.asset.findUnique({
    where: { id: assetId },
    select: { imageData: true, imageMimeType: true },
  });

  if (!asset?.imageData || !asset?.imageMimeType) {
    return null;
  }

  return {
    data: Buffer.from(asset.imageData, 'base64'),
    mimeType: asset.imageMimeType,
  };
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
