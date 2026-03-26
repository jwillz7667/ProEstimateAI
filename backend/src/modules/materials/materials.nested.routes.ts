import { Router, Request, Response, NextFunction } from 'express';
import { listByGenerationHandler } from './materials.controller';

const router = Router({ mergeParams: true });

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/generations/:generationId/materials - list materials for a generation
router.get('/', asyncHandler(listByGenerationHandler));

export default router;
