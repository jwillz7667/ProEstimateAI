import { Router, Request, Response, NextFunction } from 'express';
import { listByInvoiceHandler, createForInvoiceHandler } from './invoice-line-items.controller';
import { validate } from '../../middleware/validate.middleware';
import { createInvoiceLineItemSchema } from './invoice-line-items.validators';

const router = Router({ mergeParams: true });

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/invoices/:invoiceId/line-items
router.get('/', asyncHandler(listByInvoiceHandler));

// POST /v1/invoices/:invoiceId/line-items
router.post('/', validate(createInvoiceLineItemSchema), asyncHandler(createForInvoiceHandler));

export default router;
