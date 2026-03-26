import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { param } from '../../lib/params';
import * as laborRatesService from './labor-rates.service';
import { toLaborRateDto } from './labor-rates.dto';

// Nested handlers (used under /pricing-profiles/:profileId/labor-rates)

export async function listByProfileHandler(req: Request, res: Response) {
  const profileId = param(req.params.profileId);
  const rules = await laborRatesService.listByProfile(profileId, req.companyId!);
  sendSuccess(res, rules.map(toLaborRateDto));
}

export async function createHandler(req: Request, res: Response) {
  const profileId = param(req.params.profileId);
  const rule = await laborRatesService.create(profileId, req.companyId!, req.body);
  sendSuccess(res, toLaborRateDto(rule), { statusCode: 201 });
}

// Top-level handlers (used under /labor-rates/:id)

export async function updateHandler(req: Request, res: Response) {
  const rule = await laborRatesService.update(param(req.params.id), req.companyId!, req.body);
  sendSuccess(res, toLaborRateDto(rule));
}

export async function deleteHandler(req: Request, res: Response) {
  await laborRatesService.remove(param(req.params.id), req.companyId!);
  sendSuccess(res, {});
}
