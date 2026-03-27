import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { param } from '../../lib/params';
import * as assetsService from './assets.service';
import { toAssetDto } from './assets.dto';

/**
 * GET /projects/:projectId/assets
 * List all assets for a project.
 */
export async function listByProjectHandler(req: Request, res: Response) {
  const assets = await assetsService.listByProject(param(req.params.projectId), req.companyId!);
  sendSuccess(res, assets.map(toAssetDto));
}

/**
 * POST /projects/:projectId/assets
 * Create a new asset for a project.
 */
export async function createHandler(req: Request, res: Response) {
  const asset = await assetsService.create(param(req.params.projectId), req.companyId!, req.body);
  sendSuccess(res, toAssetDto(asset), { statusCode: 201 });
}

/**
 * GET /v1/assets/:id/image
 * Serve the stored image binary for an asset.
 */
export async function serveImageHandler(req: Request, res: Response) {
  const result = await assetsService.getImageData(param(req.params.id), req.companyId!);

  if (!result) {
    res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'No image data stored for this asset' } });
    return;
  }

  res.set('Content-Type', result.mimeType);
  res.set('Cache-Control', 'public, max-age=86400, immutable');
  res.send(result.data);
}

/**
 * DELETE /v1/assets/:id
 * Delete an asset by ID.
 */
export async function deleteHandler(req: Request, res: Response) {
  await assetsService.remove(param(req.params.id), req.companyId!);
  sendSuccess(res, {});
}
