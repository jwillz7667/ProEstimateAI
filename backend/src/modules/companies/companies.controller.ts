import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
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
