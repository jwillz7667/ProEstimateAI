import { Router, Request, Response, NextFunction } from 'express';
import { searchHandler } from './contractors.controller';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/contractors/search?project_type=KITCHEN&lat=33.749&lng=-84.388
router.get('/search', asyncHandler(searchHandler));

export default router;
