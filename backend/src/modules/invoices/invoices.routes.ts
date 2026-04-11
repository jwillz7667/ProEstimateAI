import { Router, Request, Response, NextFunction } from 'express';
import {
  listHandler,
  getByIdHandler,
  createHandler,
  updateHandler,
  sendHandler,
  deleteHandler,
  exportPDFHandler,
} from './invoices.controller';
import { validate } from '../../middleware/validate.middleware';
import { createInvoiceSchema, updateInvoiceSchema } from './invoices.validators';
import invoiceLineItemNestedRoutes from '../invoice-line-items/invoice-line-items.nested.routes';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

router.get('/', asyncHandler(listHandler));
router.get('/:id', asyncHandler(getByIdHandler));
router.get('/:id/export', asyncHandler(exportPDFHandler));
router.post('/', validate(createInvoiceSchema), asyncHandler(createHandler));
router.patch('/:id', validate(updateInvoiceSchema), asyncHandler(updateHandler));
router.post('/:id/send', asyncHandler(sendHandler));
router.delete('/:id', asyncHandler(deleteHandler));

// Nested line items: /v1/invoices/:invoiceId/line-items
router.use('/:invoiceId/line-items', invoiceLineItemNestedRoutes);

export default router;
