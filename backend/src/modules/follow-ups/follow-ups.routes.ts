import { Router, type Request, type Response, type NextFunction } from "express";
import { z } from "zod";
import { validate } from "../../middleware/validate.middleware";
import { shareRateLimit } from "../../middleware/rate-limit.middleware";
import { requireApprovalShareAccess } from "../../middleware/feature-access.middleware";
import { sendSuccess } from "../../lib/envelope";
import { param } from "../../lib/params";
import * as service from "./follow-ups.service";

const handler = (fn: (req: Request, res: Response) => Promise<void>) => (req: Request, res: Response, next: NextFunction) => { fn(req, res).catch(next); };
const kind = z.enum(["proposal", "invoice"]);
const enqueueSchema = z.object({ entity_kind: kind, entity_id: z.string().min(1).max(200), request_id: z.string().uuid() }).strict();
const settingsSchema = z.object({ enabled: z.boolean(), quote_days: z.number().int().min(1).max(30), invoice_days: z.number().int().min(1).max(30) }).strict();
const historySchema = z.object({ entity_kind: kind, entity_id: z.string().min(1).max(200) });

export const followUpRoutes = Router();
followUpRoutes.get("/settings", handler(async (req, res) => { sendSuccess(res, await service.getSettings(req.companyId!, req.userId!)); }));
followUpRoutes.patch("/settings", validate(settingsSchema), handler(async (req, res) => { sendSuccess(res, await service.updateSettings(req.companyId!, req.userId!, req.body)); }));
followUpRoutes.get("/history", validate(historySchema, "query"), handler(async (req, res) => {
  const query = req.query as unknown as z.infer<typeof historySchema>;
  sendSuccess(res, await service.listHistory(req.companyId!, query.entity_kind, query.entity_id));
}));
followUpRoutes.post("/", validate(enqueueSchema), requireApprovalShareAccess, handler(async (req, res) => {
  sendSuccess(res, await service.enqueueManual(req.companyId!, req.userId!, req.body.entity_kind, req.body.entity_id, req.body.request_id), { statusCode: 202 });
}));

// Public bearer tokens can only stop reminders for their own document.
export const followUpPreferenceRoutes = Router();
followUpPreferenceRoutes.use(shareRateLimit);
followUpPreferenceRoutes.get("/:token", handler(async (req, res) => { sendSuccess(res, await service.getPreference(param(req.params.token))); }));
followUpPreferenceRoutes.post("/:token/unsubscribe", handler(async (req, res) => { sendSuccess(res, await service.unsubscribe(param(req.params.token))); }));
