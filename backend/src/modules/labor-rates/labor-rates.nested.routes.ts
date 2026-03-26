import { Router, Request, Response, NextFunction } from 'express';
import { listByProfileHandler, createHandler } from './labor-rates.controller';
import { validate } from '../../middleware/validate.middleware';
import { createLaborRateSchema } from './labor-rates.validators';

// Nested router: mounted at /pricing-profiles/:profileId/labor-rates
const router = Router({ mergeParams: true });

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

router.get('/', asyncHandler(listByProfileHandler));
router.post('/', validate(createLaborRateSchema), asyncHandler(createHandler));

export default router;
