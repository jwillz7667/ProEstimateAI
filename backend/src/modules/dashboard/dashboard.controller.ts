import { Request, Response, NextFunction } from 'express';
import { sendSuccess } from '../../lib/envelope';
import * as dashboardService from './dashboard.service';

function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<void>,
) {
  return (req: Request, res: Response, next: NextFunction) =>
    fn(req, res, next).catch(next);
}

export const getSummaryHandler = asyncHandler(
  async (req: Request, res: Response, _next: NextFunction) => {
    const summary = await dashboardService.getSummary(
      req.companyId!,
      req.userId!,
    );
    sendSuccess(res, summary);
  },
);
