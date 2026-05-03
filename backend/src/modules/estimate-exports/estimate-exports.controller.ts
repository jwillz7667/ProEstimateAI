import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { param } from '../../lib/params';
import * as service from './estimate-exports.service';
import { toEstimateExportDto } from './estimate-exports.dto';

/**
 * POST /v1/estimates/:estimateId/exports
 * Persist a rendered PDF for the given estimate.
 */
export async function createForEstimateHandler(req: Request, res: Response) {
  const record = await service.create(
    param(req.params.estimateId),
    req.companyId!,
    req.body,
  );
  sendSuccess(res, toEstimateExportDto(record), { statusCode: 201 });
}

/**
 * GET /v1/estimates/:estimateId/exports
 * List all saved PDFs for one estimate.
 */
export async function listByEstimateHandler(req: Request, res: Response) {
  const records = await service.listByEstimate(
    param(req.params.estimateId),
    req.companyId!,
  );
  sendSuccess(res, records.map(toEstimateExportDto));
}

/**
 * GET /v1/projects/:projectId/estimate-exports
 * Project-scoped list of every saved PDF across all estimates of the project.
 */
export async function listByProjectHandler(req: Request, res: Response) {
  const records = await service.listByProject(
    param(req.params.projectId),
    req.companyId!,
  );
  sendSuccess(res, records.map(toEstimateExportDto));
}

/**
 * GET /v1/estimate-exports/:id
 * Metadata for a single saved PDF.
 */
export async function getByIdHandler(req: Request, res: Response) {
  const record = await service.getById(param(req.params.id), req.companyId!);
  sendSuccess(res, toEstimateExportDto(record));
}

/**
 * DELETE /v1/estimate-exports/:id
 */
export async function deleteHandler(req: Request, res: Response) {
  await service.remove(param(req.params.id), req.companyId!);
  sendSuccess(res, {});
}
