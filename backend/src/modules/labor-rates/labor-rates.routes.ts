import { Router, Request, Response, NextFunction } from 'express';
import { updateHandler, deleteHandler } from './labor-rates.controller';
import { validate } from '../../middleware/validate.middleware';
import { updateLaborRateSchema } from './labor-rates.validators';

// Top-level routes for individual labor rate operations
const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

router.patch('/:id', validate(updateLaborRateSchema), asyncHandler(updateHandler));
router.delete('/:id', asyncHandler(deleteHandler));

export default router;
