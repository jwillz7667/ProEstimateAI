import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { parsePagination } from '../../lib/pagination';
import * as projectsService from './projects.service';
import { toProjectDto } from './projects.dto';

export async function listHandler(req: Request, res: Response) {
  const pagination = parsePagination(req.query as { cursor?: string; page_size?: string });
  const result = await projectsService.list(req.companyId!, pagination);

  sendSuccess(
    res,
    result.items.map(toProjectDto),
    { pagination: { next_cursor: result.nextCursor } }
  );
}

export async function getByIdHandler(req: Request, res: Response) {
  const project = await projectsService.getById(req.params.id as string, req.companyId!);
  sendSuccess(res, toProjectDto(project));
}

export async function createHandler(req: Request, res: Response) {
  const project = await projectsService.create(req.companyId!, req.body);
  sendSuccess(res, toProjectDto(project), { statusCode: 201 });
}

export async function updateHandler(req: Request, res: Response) {
  const project = await projectsService.update(req.params.id as string, req.companyId!, req.body);
  sendSuccess(res, toProjectDto(project));
}

export async function deleteHandler(req: Request, res: Response) {
  await projectsService.remove(req.params.id as string, req.companyId!);
  sendSuccess(res, {});
}
