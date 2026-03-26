import { Router, Request, Response, NextFunction } from 'express';
import { updateHandler, deleteHandler } from './invoice-line-items.controller';
import { validate } from '../../middleware/validate.middleware';
import { updateInvoiceLineItemSchema } from './invoice-line-items.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// PATCH /v1/invoice-line-items/:id
router.patch('/:id', validate(updateInvoiceLineItemSchema), asyncHandler(updateHandler));

// DELETE /v1/invoice-line-items/:id
router.delete('/:id', asyncHandler(deleteHandler));

export default router;
