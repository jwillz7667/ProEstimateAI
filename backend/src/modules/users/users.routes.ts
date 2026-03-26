import { Router, Request, Response, NextFunction } from 'express';
import { getMeHandler } from './users.controller';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

router.get('/me', asyncHandler(getMeHandler));

export default router;
