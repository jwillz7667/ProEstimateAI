import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { parsePagination } from '../../lib/pagination';
import { param } from '../../lib/params';
import * as pricingProfilesService from './pricing-profiles.service';
import { toPricingProfileDto } from './pricing-profiles.dto';

export async function listHandler(req: Request, res: Response) {
  const pagination = parsePagination(req.query as { cursor?: string; page_size?: string });
  const result = await pricingProfilesService.list(req.companyId!, pagination);

  sendSuccess(
    res,
    result.items.map(toPricingProfileDto),
    { pagination: { next_cursor: result.nextCursor } }
  );
}

export async function getByIdHandler(req: Request, res: Response) {
  const profile = await pricingProfilesService.getById(param(req.params.id), req.companyId!);
  sendSuccess(res, toPricingProfileDto(profile));
}

export async function createHandler(req: Request, res: Response) {
  const profile = await pricingProfilesService.create(req.companyId!, req.body);
  sendSuccess(res, toPricingProfileDto(profile), { statusCode: 201 });
}

export async function updateHandler(req: Request, res: Response) {
  const profile = await pricingProfilesService.update(param(req.params.id), req.companyId!, req.body);
  sendSuccess(res, toPricingProfileDto(profile));
}

export async function deleteHandler(req: Request, res: Response) {
  await pricingProfilesService.remove(param(req.params.id), req.companyId!);
  sendSuccess(res, {});
}
