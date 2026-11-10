import { Router, Request, Response, NextFunction } from "express";
import { sendSuccess } from "../../lib/envelope";
import { validate } from "../../middleware/validate.middleware";
import { shareRateLimit } from "../../middleware/rate-limit.middleware";
import * as service from "./invoice-finance.service";
import { invoiceScheduleSchema, recordInvoicePaymentSchema } from "./invoice-finance.validators";

const wrap = (handler: (req: Request, res: Response) => Promise<void>) =>
  (req: Request, res: Response, next: NextFunction) => handler(req, res).catch(next);

export const invoiceFinanceRoutes = Router({ mergeParams: true });
invoiceFinanceRoutes.get("/", wrap(async (req, res) => {
  sendSuccess(res, await service.getFinance(req.params.invoiceId as string, req.companyId!));
}));
invoiceFinanceRoutes.post("/payments", validate(recordInvoicePaymentSchema), wrap(async (req, res) => {
  sendSuccess(res, await service.recordPayment(req.params.invoiceId as string, req.companyId!, req.userId!, req.body));
}));
invoiceFinanceRoutes.put("/schedule", validate(invoiceScheduleSchema), wrap(async (req, res) => {
  sendSuccess(res, await service.replaceSchedule(req.params.invoiceId as string, req.companyId!, req.body));
}));

export const invoiceShareRoutes = Router();
invoiceShareRoutes.use(shareRateLimit);
invoiceShareRoutes.get("/:token", wrap(async (req, res) => {
  res.set("Cache-Control", "no-store");
  res.set("Referrer-Policy", "no-referrer");
  sendSuccess(res, await service.getSharedInvoice(req.params.token as string));
}));
