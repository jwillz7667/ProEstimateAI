import { Router, Request, Response, NextFunction } from 'express';
import { getByIdHandler } from './generations.controller';
import materialNestedRoutes from '../materials/materials.nested.routes';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/generations/:id - get a single generation
router.get('/:id', asyncHandler(getByIdHandler));

// Mount materials nested under /v1/generations/:generationId/materials
router.use('/:generationId/materials', materialNestedRoutes);

export default router;
