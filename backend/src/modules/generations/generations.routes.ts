import { Router, Request, Response, NextFunction } from 'express';
import { getByIdHandler, getPreviewImageHandler } from './generations.controller';
import materialNestedRoutes from '../materials/materials.nested.routes';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/generations/:id - get a single generation (status polling)
router.get('/:id', asyncHandler(getByIdHandler));

// GET /v1/generations/:id/preview - serve generated image binary
router.get('/:id/preview', asyncHandler(getPreviewImageHandler));

// Mount materials nested under /v1/generations/:generationId/materials
router.use('/:generationId/materials', materialNestedRoutes);

export default router;
