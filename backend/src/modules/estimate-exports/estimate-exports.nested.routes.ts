import { Router, Request, Response, NextFunction } from 'express';
import { createForEstimateHandler, listByEstimateHandler } from './estimate-exports.controller';
import { validate } from '../../middleware/validate.middleware';
import { createEstimateExportSchema } from './estimate-exports.validators';

const router = Router({ mergeParams: true });

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/estimates/:estimateId/exports
router.get('/', asyncHandler(listByEstimateHandler));

// POST /v1/estimates/:estimateId/exports
router.post('/', validate(createEstimateExportSchema), asyncHandler(createForEstimateHandler));

export default router;
