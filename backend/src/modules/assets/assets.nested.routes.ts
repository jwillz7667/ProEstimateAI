import { Router, Request, Response, NextFunction } from 'express';
import { listByProjectHandler, createHandler } from './assets.controller';
import { validate } from '../../middleware/validate.middleware';
import { createAssetSchema } from './assets.validators';

const router = Router({ mergeParams: true });

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /projects/:projectId/assets - list assets for a project
router.get('/', asyncHandler(listByProjectHandler));

// POST /projects/:projectId/assets - create an asset for a project
router.post('/', validate(createAssetSchema), asyncHandler(createHandler));

export default router;
