import { Request, Response } from "express";
import { sendSuccess } from "../../lib/envelope";
import { parsePagination } from "../../lib/pagination";
import * as clientsService from "./clients.service";
import { toClientDto } from "./clients.dto";
import * as projectsService from "../projects/projects.service";
import { toProjectListDto } from "../projects/projects.dto";

export async function listProjectsHandler(req: Request, res: Response) {
  const client = await clientsService.getById(req.params.id as string, req.companyId!);
  const pagination = parsePagination(req.query as { cursor?: string; page_size?: string });
  const result = await projectsService.list(req.companyId!, pagination, client.id);
  const thumbnails = await projectsService.buildThumbnailMap(result.items.map((project) => project.id));
  sendSuccess(res, result.items.map((project) => toProjectListDto(project, thumbnails.get(project.id) ?? null)), {
    pagination: { next_cursor: result.nextCursor },
  });
}

export async function listHandler(req: Request, res: Response) {
  const pagination = parsePagination(
    req.query as { cursor?: string; page_size?: string },
  );
  const result = await clientsService.list(req.companyId!, pagination);

  sendSuccess(res, result.items.map(toClientDto), {
    pagination: { next_cursor: result.nextCursor },
  });
}

export async function getByIdHandler(req: Request, res: Response) {
  const client = await clientsService.getById(
    req.params.id as string,
    req.companyId!,
  );
  sendSuccess(res, toClientDto(client));
}

export async function createHandler(req: Request, res: Response) {
  const client = await clientsService.create(
    req.companyId!,
    req.userId!,
    req.body,
  );
  sendSuccess(res, toClientDto(client), { statusCode: 201 });
}

export async function updateHandler(req: Request, res: Response) {
  const client = await clientsService.update(
    req.params.id as string,
    req.companyId!,
    req.userId!,
    req.body,
  );
  sendSuccess(res, toClientDto(client));
}

export async function deleteHandler(req: Request, res: Response) {
  await clientsService.remove(
    req.params.id as string,
    req.companyId!,
    req.userId!,
  );
  sendSuccess(res, {});
}
