import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { parsePagination } from '../../lib/pagination';
import { param } from '../../lib/params';
import * as proposalsService from './proposals.service';
import { toProposalDto } from './proposals.dto';

export async function listHandler(req: Request, res: Response) {
  const pagination = parsePagination(req.query as { cursor?: string; page_size?: string });
  const projectId = req.query.project_id as string | undefined;
  const result = await proposalsService.list(req.companyId!, pagination, projectId);

  sendSuccess(
    res,
    result.items.map(toProposalDto),
    { pagination: { next_cursor: result.nextCursor } }
  );
}

export async function getByIdHandler(req: Request, res: Response) {
  const proposal = await proposalsService.getById(param(req.params.id), req.companyId!);
  sendSuccess(res, toProposalDto(proposal));
}

export async function createHandler(req: Request, res: Response) {
  const proposal = await proposalsService.create(req.companyId!, req.body);
  sendSuccess(res, toProposalDto(proposal), { statusCode: 201 });
}

export async function sendHandler(req: Request, res: Response) {
  const proposal = await proposalsService.send(param(req.params.id), req.companyId!, req.userId!, req.body);
  sendSuccess(res, toProposalDto(proposal));
}
