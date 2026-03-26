import { Request, Response } from 'express';
import { sendSuccess } from '../../lib/envelope';
import { param } from '../../lib/params';
import * as invoiceLineItemsService from './invoice-line-items.service';
import { toInvoiceLineItemDto } from './invoice-line-items.dto';

// --- Nested handlers (mounted under /invoices/:invoiceId/line-items) ---

export async function listByInvoiceHandler(req: Request, res: Response) {
  const invoiceId = param(req.params.invoiceId);
  const items = await invoiceLineItemsService.listByInvoice(invoiceId, req.companyId!);
  sendSuccess(res, items.map(toInvoiceLineItemDto));
}

export async function createForInvoiceHandler(req: Request, res: Response) {
  const invoiceId = param(req.params.invoiceId);
  const item = await invoiceLineItemsService.create(invoiceId, req.companyId!, req.body);
  sendSuccess(res, toInvoiceLineItemDto(item), { statusCode: 201 });
}

// --- Top-level handlers (mounted under /invoice-line-items) ---

export async function updateHandler(req: Request, res: Response) {
  const item = await invoiceLineItemsService.update(param(req.params.id), req.companyId!, req.body);
  sendSuccess(res, toInvoiceLineItemDto(item));
}

export async function deleteHandler(req: Request, res: Response) {
  await invoiceLineItemsService.remove(param(req.params.id), req.companyId!);
  sendSuccess(res, {});
}
