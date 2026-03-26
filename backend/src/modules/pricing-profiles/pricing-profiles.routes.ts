import { Router, Request, Response, NextFunction } from 'express';
import {
  listHandler,
  getByIdHandler,
  createHandler,
  updateHandler,
  deleteHandler,
} from './pricing-profiles.controller';
import { validate } from '../../middleware/validate.middleware';
import {
  createPricingProfileSchema,
  updatePricingProfileSchema,
} from './pricing-profiles.validators';
import laborRateNestedRoutes from '../labor-rates/labor-rates.nested.routes';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// CRUD routes
router.get('/', asyncHandler(listHandler));
router.get('/:id', asyncHandler(getByIdHandler));
router.post('/', validate(createPricingProfileSchema), asyncHandler(createHandler));
router.patch('/:id', validate(updatePricingProfileSchema), asyncHandler(updateHandler));
router.delete('/:id', asyncHandler(deleteHandler));

// Nested labor rates
router.use('/:profileId/labor-rates', laborRateNestedRoutes);

export default router;
