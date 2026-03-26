import { Router, Request, Response, NextFunction } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { parsePagination } from '../../lib/pagination';
import { param } from '../../lib/params';
import * as activityService from './activity.service';
import { toActivityDto } from './activity.dto';

// Nested router: mounted at /projects/:projectId/activity
const router = Router({ mergeParams: true });

function asyncHandler(fn: (req: Request, res: Response, next: NextFunction) => Promise<void>) {
  return (req: Request, res: Response, next: NextFunction) => fn(req, res, next).catch(next);
}

// GET /projects/:projectId/activity
router.get(
  '/',
  asyncHandler(async (req: Request, res: Response) => {
    const projectId = param(req.params.projectId);
    const companyId = req.companyId!;
    const pagination = parsePagination(req.query as { cursor?: string; page_size?: string });

    const result = await activityService.list(projectId, companyId, pagination);

    sendSuccess(
      res,
      result.items.map(toActivityDto),
      { pagination: { next_cursor: result.nextCursor } }
    );
  })
);

export default router;
