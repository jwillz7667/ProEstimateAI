import { Router, Request, Response, NextFunction } from 'express';
import {
  getMeHandler,
  updateMeHandler,
  uploadLogoHandler,
  deleteLogoHandler,
} from './companies.controller';
import { validate } from '../../middleware/validate.middleware';
import { updateCompanySchema, uploadLogoSchema } from './companies.validators';

const router = Router();

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

router.get('/me', asyncHandler(getMeHandler));
router.patch('/me', validate(updateCompanySchema), asyncHandler(updateMeHandler));
router.post('/me/logo', validate(uploadLogoSchema), asyncHandler(uploadLogoHandler));
router.delete('/me/logo', asyncHandler(deleteLogoHandler));

export default router;
