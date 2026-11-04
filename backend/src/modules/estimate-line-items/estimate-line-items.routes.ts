import { Router, Request, Response, NextFunction } from 'express';
import { updateHandler, deleteHandler, reviewPriceHandler } from './estimate-line-items.controller';
import { validate } from '../../middleware/validate.middleware';
import { updateEstimateLineItemSchema, reviewEstimatePriceSchema } from './estimate-line-items.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// PATCH /v1/estimate-line-items/:id
router.patch('/:id', validate(updateEstimateLineItemSchema), asyncHandler(updateHandler));
router.post('/:id/price-review', validate(reviewEstimatePriceSchema), asyncHandler(reviewPriceHandler));

// DELETE /v1/estimate-line-items/:id
router.delete('/:id', asyncHandler(deleteHandler));

export default router;
