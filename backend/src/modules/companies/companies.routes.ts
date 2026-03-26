import { Router, Request, Response, NextFunction } from 'express';
import { getMeHandler, updateMeHandler } from './companies.controller';
import { validate } from '../../middleware/validate.middleware';
import { updateCompanySchema } from './companies.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

router.get('/me', asyncHandler(getMeHandler));
router.patch('/me', validate(updateCompanySchema), asyncHandler(updateMeHandler));

export default router;
