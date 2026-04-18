import { Router, Request, Response, NextFunction } from 'express';
import {
  listHandler,
  getByIdHandler,
  createHandler,
  updateHandler,
  deleteHandler,
  generateHandler,
} from './estimates.controller';
import { validate } from '../../middleware/validate.middleware';
import {
  createEstimateSchema,
  generateEstimateSchema,
  updateEstimateSchema,
} from './estimates.validators';
import estimateLineItemNestedRoutes from '../estimate-line-items/estimate-line-items.nested.routes';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

router.get('/', asyncHandler(listHandler));
// `POST /v1/estimates/generate` must appear before `:id` to avoid the id
// param swallowing the literal "generate" path segment.
router.post('/generate', validate(generateEstimateSchema), asyncHandler(generateHandler));
router.get('/:id', asyncHandler(getByIdHandler));
router.post('/', validate(createEstimateSchema), asyncHandler(createHandler));
router.patch('/:id', validate(updateEstimateSchema), asyncHandler(updateHandler));
router.delete('/:id', asyncHandler(deleteHandler));

// Nested line items: /v1/estimates/:estimateId/line-items
router.use('/:estimateId/line-items', estimateLineItemNestedRoutes);

export default router;
