import { Router, Request, Response, NextFunction } from 'express';
import { updateHandler } from './materials.controller';
import { validate } from '../../middleware/validate.middleware';
import { updateMaterialSchema } from './materials.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// PATCH /v1/materials/:id - update material selection
router.patch('/:id', validate(updateMaterialSchema), asyncHandler(updateHandler));

export default router;
