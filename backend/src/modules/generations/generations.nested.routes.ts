import { Router, Request, Response, NextFunction } from 'express';
import { listByProjectHandler, createHandler } from './generations.controller';
import { validate } from '../../middleware/validate.middleware';
import { createGenerationSchema } from './generations.validators';

const router = Router({ mergeParams: true });

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /projects/:projectId/generations - list generations for a project
router.get('/', asyncHandler(listByProjectHandler));

// POST /projects/:projectId/generations - create a generation (with entitlement check)
router.post('/', validate(createGenerationSchema), asyncHandler(createHandler));

export default router;
