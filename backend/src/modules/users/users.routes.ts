import { Router, Request, Response, NextFunction } from 'express';
import { getMeHandler, updateMeHandler, deleteMeHandler } from './users.controller';
import { validate } from '../../middleware/validate.middleware';
import { updateUserSchema } from './users.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

router.get('/me', asyncHandler(getMeHandler));
router.patch('/me', validate(updateUserSchema), asyncHandler(updateMeHandler));
// DELETE /v1/users/me — required by App Store Review Guideline 5.1.1(v).
router.delete('/me', asyncHandler(deleteMeHandler));

export default router;
