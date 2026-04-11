import { Router, Request, Response, NextFunction } from 'express';
import { validate } from '../../middleware/validate.middleware';
import { getSharedProposal, respondToSharedProposal } from './proposals-share.controller';
import { respondToProposalSchema } from './proposals.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /v1/proposals/share/:shareToken — Public proposal view
router.get('/:shareToken', asyncHandler(getSharedProposal));

// POST /v1/proposals/share/:shareToken/respond — Client approves/declines
router.post('/:shareToken/respond', validate(respondToProposalSchema, 'body'), asyncHandler(respondToSharedProposal));

export default router;
