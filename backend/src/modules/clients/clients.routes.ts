import { Router, Request, Response, NextFunction } from 'express';
import {
  listHandler,
  getByIdHandler,
  createHandler,
  updateHandler,
  deleteHandler,
} from './clients.controller';
import { validate } from '../../middleware/validate.middleware';
import { createClientSchema, updateClientSchema } from './clients.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

router.get('/', asyncHandler(listHandler));
router.get('/:id', asyncHandler(getByIdHandler));
router.post('/', validate(createClientSchema), asyncHandler(createHandler));
router.patch('/:id', validate(updateClientSchema), asyncHandler(updateHandler));
router.delete('/:id', asyncHandler(deleteHandler));

export default router;
