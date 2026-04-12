import { Router, Request, Response, NextFunction } from 'express';
import { listByEstimateHandler, createForEstimateHandler, batchCreateForEstimateHandler } from './estimate-line-items.controller';
import { validate } from '../../middleware/validate.middleware';
import { createEstimateLineItemSchema, batchCreateEstimateLineItemsSchema } from './estimate-line-items.validators';

const router = Router({ mergeParams: true });

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/estimates/:estimateId/line-items
router.get('/', asyncHandler(listByEstimateHandler));

// POST /v1/estimates/:estimateId/line-items
router.post('/', validate(createEstimateLineItemSchema), asyncHandler(createForEstimateHandler));

// POST /v1/estimates/:estimateId/line-items/batch
router.post('/batch', validate(batchCreateEstimateLineItemsSchema), asyncHandler(batchCreateForEstimateHandler));

export default router;
