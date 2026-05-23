import { Router, Request, Response, NextFunction } from 'express';
import { listByProjectHandler } from './estimate-exports.controller';

const router = Router({ mergeParams: true });

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/projects/:projectId/estimate-exports
router.get('/', asyncHandler(listByProjectHandler));

export default router;
