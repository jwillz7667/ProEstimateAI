import { Router, Request, Response, NextFunction } from 'express';
import { deleteHandler, getByIdHandler } from './estimate-exports.controller';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/estimate-exports/:id — metadata only
router.get('/:id', asyncHandler(getByIdHandler));

// DELETE /v1/estimate-exports/:id
router.delete('/:id', asyncHandler(deleteHandler));

export default router;
