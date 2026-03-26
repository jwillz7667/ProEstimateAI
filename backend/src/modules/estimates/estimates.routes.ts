import { Router, Request, Response, NextFunction } from 'express';
import {
  listHandler,
  getByIdHandler,
  createHandler,
  updateHandler,
  deleteHandler,
} from './estimates.controller';
import { validate } from '../../middleware/validate.middleware';
import { createEstimateSchema, updateEstimateSchema } from './estimates.validators';
import estimateLineItemNestedRoutes from '../estimate-line-items/estimate-line-items.nested.routes';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

router.get('/', asyncHandler(listHandler));
router.get('/:id', asyncHandler(getByIdHandler));
router.post('/', validate(createEstimateSchema), asyncHandler(createHandler));
router.patch('/:id', validate(updateEstimateSchema), asyncHandler(updateHandler));
router.delete('/:id', asyncHandler(deleteHandler));

// Nested line items: /v1/estimates/:estimateId/line-items
router.use('/:estimateId/line-items', estimateLineItemNestedRoutes);

export default router;
