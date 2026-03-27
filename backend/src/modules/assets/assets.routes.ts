import { Router, Request, Response, NextFunction } from 'express';
import { deleteHandler, serveImageHandler } from './assets.controller';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/assets/:id/image - serve stored image binary
router.get('/:id/image', asyncHandler(serveImageHandler));

// DELETE /v1/assets/:id - delete an asset
router.delete('/:id', asyncHandler(deleteHandler));

export default router;
