import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { param } from '../../lib/params';
import * as estimateLineItemsService from './estimate-line-items.service';
import { toEstimateLineItemDto } from './estimate-line-items.dto';

// --- Nested handlers (mounted under /estimates/:estimateId/line-items) ---

export async function listByEstimateHandler(req: Request, res: Response) {
  const estimateId = param(req.params.estimateId);
  const items = await estimateLineItemsService.listByEstimate(estimateId, req.companyId!);
  sendSuccess(res, items.map(toEstimateLineItemDto));
}

export async function createForEstimateHandler(req: Request, res: Response) {
  const estimateId = param(req.params.estimateId);
  const item = await estimateLineItemsService.create(estimateId, req.companyId!, req.body);
  sendSuccess(res, toEstimateLineItemDto(item), { statusCode: 201 });
}

// --- Top-level handlers (mounted under /estimate-line-items) ---

export async function updateHandler(req: Request, res: Response) {
  const item = await estimateLineItemsService.update(param(req.params.id), req.companyId!, req.body);
  sendSuccess(res, toEstimateLineItemDto(item));
}

export async function deleteHandler(req: Request, res: Response) {
  await estimateLineItemsService.remove(param(req.params.id), req.companyId!);
  sendSuccess(res, {});
}
