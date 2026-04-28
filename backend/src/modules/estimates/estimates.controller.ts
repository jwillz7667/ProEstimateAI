import { Request, Response } from "express";
import { sendSuccess } from "../../lib/envelope";
import { parsePagination } from "../../lib/pagination";
import { param } from "../../lib/params";
import * as estimatesService from "./estimates.service";
import { toEstimateDto } from "./estimates.dto";

export async function listHandler(req: Request, res: Response) {
  const pagination = parsePagination(
    req.query as { cursor?: string; page_size?: string },
  );
  const projectId = req.query.project_id as string | undefined;
  const clientId = req.query.client_id as string | undefined;
  const result = await estimatesService.list(
    req.companyId!,
    pagination,
    projectId,
    clientId,
  );

  sendSuccess(res, result.items.map(toEstimateDto), {
    pagination: { next_cursor: result.nextCursor },
  });
}

export async function getByIdHandler(req: Request, res: Response) {
  const estimate = await estimatesService.getById(
    param(req.params.id),
    req.companyId!,
  );
  sendSuccess(res, toEstimateDto(estimate));
}

export async function createHandler(req: Request, res: Response) {
  const estimate = await estimatesService.create(
    req.companyId!,
    req.userId!,
    req.body,
  );
  sendSuccess(res, toEstimateDto(estimate), { statusCode: 201 });
}

export async function updateHandler(req: Request, res: Response) {
  const estimate = await estimatesService.update(
    param(req.params.id),
    req.companyId!,
    req.userId!,
    req.body,
  );
  sendSuccess(res, toEstimateDto(estimate));
}

export async function deleteHandler(req: Request, res: Response) {
  await estimatesService.remove(param(req.params.id), req.companyId!);
  sendSuccess(res, {});
}

export async function generateHandler(req: Request, res: Response) {
  const projectId = req.body.project_id as string;
  const estimate = await estimatesService.generateAI(
    req.companyId!,
    req.userId!,
    projectId,
  );
  sendSuccess(res, toEstimateDto(estimate), { statusCode: 201 });
}
