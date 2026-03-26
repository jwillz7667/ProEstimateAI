import { Router, Request, Response, NextFunction } from 'express';
import { getSummary, check } from './usage.controller';
import { validate } from '../../middleware/validate.middleware';
import { consumeUsageSchema } from './usage.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /usage - returns full entitlement snapshot with feature flags and usage
router.get('/', asyncHandler(getSummary));

// POST /usage/check - consume one credit for the given metric
router.post('/check', validate(consumeUsageSchema), asyncHandler(check));

export default router;
