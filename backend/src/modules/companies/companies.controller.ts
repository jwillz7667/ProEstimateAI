import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { param } from '../../lib/params';
import * as companiesService from './companies.service';
import { toCompanyDto } from './companies.dto';

export async function getMeHandler(req: Request, res: Response) {
  const company = await companiesService.getMe(req.companyId!);
  sendSuccess(res, toCompanyDto(company));
}

export async function updateMeHandler(req: Request, res: Response) {
  const company = await companiesService.updateMe(req.companyId!, req.body);
  sendSuccess(res, toCompanyDto(company));
}

export async function uploadLogoHandler(req: Request, res: Response) {
  const company = await companiesService.uploadLogo(req.companyId!, req.body);
  sendSuccess(res, toCompanyDto(company));
}

export async function deleteLogoHandler(req: Request, res: Response) {
  const company = await companiesService.deleteLogo(req.companyId!);
  sendSuccess(res, toCompanyDto(company));
}

/**
 * Public — serves the raw logo binary by company id. Cached immutably for a
 * day: the logoUrl embeds no version, so an upload replaces the bytes at the
 * same URL; clients that already cached a previous version will see it until
 * their TTL expires. A day is long enough to be useful but short enough that
 * an updated logo propagates the same day.
 */
export async function serveLogoHandler(req: Request, res: Response) {
  const result = await companiesService.getPublicCompanyLogo(param(req.params.id));

  if (!result) {
    res.status(404).json({ ok: false, error: { code: 'NOT_FOUND', message: 'No logo set for this company' } });
    return;
  }

  res.set('Content-Type', result.mimeType);
  res.set('Cache-Control', 'public, max-age=86400, immutable');
  res.send(result.data);
}
