import { Router, Request, Response, NextFunction } from "express";
import { sendSuccess } from "../../lib/envelope";
import { parsePagination } from "../../lib/pagination";
import { validate } from "../../middleware/validate.middleware";
import { ValidationError } from "../../lib/errors";
import * as service from "./job-costs.service";
import { createJobCostSchema, uploadJobReceiptSchema } from "./job-costs.validators";

const wrap = (handler: (req: Request, res: Response) => Promise<void>) =>
  (req: Request, res: Response, next: NextFunction) => handler(req, res).catch(next);
export const projectCostRoutes = Router({ mergeParams: true });
projectCostRoutes.get("/", wrap(async (req, res) => {
  if (req.query.include_voided !== undefined && !["true", "false"].includes(req.query.include_voided as string)) {
    throw new ValidationError("include_voided must be true or false");
  }
  const result = await service.list(req.params.projectId as string, req.companyId!, parsePagination(req.query as { cursor?: string; page_size?: string }), req.query.include_voided === "true");
  sendSuccess(res, result);
}));
projectCostRoutes.post("/", validate(createJobCostSchema), wrap(async (req, res) => {
  sendSuccess(res, await service.create(req.params.projectId as string, req.companyId!, req.userId!, req.body), { statusCode: 201 });
}));
export const jobCostRoutes = Router();
jobCostRoutes.delete("/:id", wrap(async (req, res) => {
  await service.voidEntry(req.params.id as string, req.companyId!, req.userId!);
  sendSuccess(res, {});
}));
jobCostRoutes.post("/:id/receipt", validate(uploadJobReceiptSchema), wrap(async (req, res) => {
  sendSuccess(res, await service.attachReceipt(req.params.id as string, req.companyId!, req.body));
}));
jobCostRoutes.get("/:id/receipt", wrap(async (req, res) => {
  const receipt = await service.getReceipt(req.params.id as string, req.companyId!);
  res.set("Content-Type", receipt.mimeType);
  res.set("Content-Disposition", `attachment; filename="${receipt.filename}"`);
  res.set("Cache-Control", "private, no-store");
  res.set("X-Content-Type-Options", "nosniff");
  res.send(receipt.data);
}));
