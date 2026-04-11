import { Router, Request, Response, NextFunction } from 'express';
import {
  listHandler,
  getByIdHandler,
  createHandler,
  updateHandler,
  deleteHandler,
  sendHandler,
  exportPDFHandler,
} from './proposals.controller';
import { validate } from '../../middleware/validate.middleware';
import { createProposalSchema, updateProposalSchema, sendProposalSchema } from './proposals.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

router.get('/', asyncHandler(listHandler));
router.get('/:id', asyncHandler(getByIdHandler));
router.get('/:id/export', asyncHandler(exportPDFHandler));
router.post('/', validate(createProposalSchema), asyncHandler(createHandler));
router.patch('/:id', validate(updateProposalSchema), asyncHandler(updateHandler));
router.delete('/:id', asyncHandler(deleteHandler));
router.post('/:id/send', validate(sendProposalSchema), asyncHandler(sendHandler));

export default router;
