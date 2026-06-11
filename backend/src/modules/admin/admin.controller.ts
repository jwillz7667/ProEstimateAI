import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import * as adminService from './admin.service';
import { ReapGenerationsInput } from './admin.validators';

export async function reapGenerationsHandler(req: Request, res: Response) {
  // Body is already validated + defaulted by the reapGenerationsSchema middleware.
  const result = await adminService.reapGenerations(req.body as ReapGenerationsInput);
  sendSuccess(res, result);
}
