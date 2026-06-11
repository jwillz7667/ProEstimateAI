import { Router, Request, Response, NextFunction } from 'express';
import { validate } from '../../middleware/validate.middleware';
import { requireAdmin } from '../../middleware/admin.middleware';
import { reapGenerationsSchema } from './admin.validators';
import { reapGenerationsHandler } from './admin.controller';

const router = Router();

// No shared wrapAsync export in this codebase — define a local one so a
// rejected promise reaches the error handler instead of hanging the request.
function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// requireAuth is applied at the mount point in app.ts; layer requireAdmin here
// so every admin route is deny-by-default to non-admins.
router.use(requireAdmin);

router.post(
  '/generations/reap',
  validate(reapGenerationsSchema),
  asyncHandler(reapGenerationsHandler),
);

export default router;
